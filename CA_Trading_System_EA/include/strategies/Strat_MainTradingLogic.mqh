#ifndef CA_STRAT_MAIN_TRADING_LOGIC_MQH
#define CA_STRAT_MAIN_TRADING_LOGIC_MQH

/*
   Strat_MainTradingLogic.mqh
   --------------------------
   
   Purpose:
      Main discretionary-style ICT/SMC strategy adapter for the EA.
      This file evaluates the market in BUY and SELL directions, scores both sides,
      applies the Main strategy's structure/liquidity/microstructure/confirmation gates,
      then returns the better qualified side as a strategy result for downstream
      Router / Policies / Risk / Execution layers.

   Plain English:
      This is the EA's "general institutional checklist" strategy.
      It is the broad, multi-factor strategy that tries to answer:

         "Do we have enough directional bias, structure, location, liquidity event,
          participation, and confirmation to justify a trade idea here?"

      It is not a narrow playbook like:
         - Silver Bullet (strict intraday time-boxed setup)
         - PO3 (session campaign / manipulation-distribution narrative)
         - Wyckoff Spring/UTAD (range-bound regime transition turn)
         - OBFVG_OTE (specific continuation / retracement entry model)

      Instead, this file acts like the main blended strategy:
         - read the current canonical ICT / confluence context
         - evaluate BUY
         - evaluate SELL
         - score both sides
         - keep the better side
         - hand off a scored strategy result to the shared trade-decision chain

   What this file CURRENTLY does:
      1) Consumes upstream market context and scanner snapshots
         - ICT_Context (canonical trading context)
         - Confluence / breakdown data
         - Scan::IndiSnapshot via read-only adapters
         - institutional / microstructure state or scan-derived proxy state
         - structure, pivots, OB/FVG, liquidity, VSA, patterns, Autochartist, etc.

      2) Builds directional evaluations for both sides
         - StratMainLogic::Evaluate(..., DIR_BUY, ...)
         - StratMainLogic::Evaluate(..., DIR_SELL, ...)

      3) Applies the Main strategy's gated checklist
         Broadly, the file checks:
         - directional bias / context
         - market structure regime
         - POI / zone / OB / FVG / OTE location quality
         - liquidity event quality (sweep / rejection / spring / UTAD / inducement)
         - institutional / OFDS / flow alignment where available
         - volume / VSA / delta / profile / footprint participation
         - candlestick / chart / trend confirmation cluster
         - execution sanity (spread / slippage / context quality / risk fit)

      4) Scores the result
         It produces:
         - classical score
         - ICT score
         - final adjusted score
         - eligibility flags
         - reasons / diagnostics / telemetry notes

      5) Chooses the better side
         BUY and SELL are both evaluated, then the stronger admissible side is selected.

      6) Produces downstream strategy output
         The file currently outputs scored strategy state such as:
         - StratScore
         - ConfluenceBreakdown
         - StrategyStatus
         - router-friendly entry intent / candidate data

         This file does NOT own final order sending.

   How the strategy currently trades in practice:

      BUY idea:
         - bullish context or directional support exists
         - structure is supportive (regime / CHOCH / BOS / spring / reclaim)
         - price is at or near a meaningful bullish POI
           (demand / bullish OB / bullish FVG / discount OTE / institutional zone)
         - liquidity behaviour supports a long
           (sell-side sweep, rejection, spring-style manipulation, reclaim)
         - microstructure is not materially hostile
         - participation confirms at the POI
         - confirmation cluster passes
           (pattern, Autochartist, trend/VWAP/EMA-style fallback)
         - final score and head thresholds pass

      SELL idea:
         - bearish context or directional support exists
         - structure is supportive (regime / CHOCH / BOS / UTAD / rejection)
         - price is at or near a meaningful bearish POI
           (supply / bearish OB / bearish FVG / premium OTE / institutional zone)
         - liquidity behaviour supports a short
           (buy-side sweep, rejection, UTAD-style manipulation, failure)
         - microstructure is not materially hostile
         - participation confirms at the POI
         - confirmation cluster passes
         - final score and head thresholds pass

   Key internal responsibilities in this file:
      - Scanner read adapters (downstream-only; this file must not run scanners)
      - scan snapshot freshness helpers
      - liquidity-event interpretation from scan/state
      - OFDS / microstructure bundle loading from scan or canonical state
      - POI / OB / FVG / OTE anchor selection
      - BUY trigger evaluation
      - SELL trigger evaluation
      - Silver Bullet and PO3 mode gates
      - confluence score assembly
      - diagnostics / telemetry / fail-reason chains
      - main strategy evaluation wrapper:
            MainTrading::BuildConfluence(...)
            StratMainLogic::Evaluate(...)
            Evaluate_StrategyMain(...)

   Important implementation notes:
      - This file is downstream-only with respect to scanners.
        It reads snapshots/events already produced upstream by MarketScannerHub / Scan.
      - This file is not supposed to own direct scanner execution.
      - This file is not supposed to own final trade execution.
      - Router / Policies / Risk / Execution remain downstream owners.

   What this file does NOT do:
      - Does not place orders directly (guarded by no-direct-exec design)
      - Does not own final portfolio/risk policy decisions
      - Does not own scan cadence
      - Does not own DOM subscription lifecycle

   Transitional architecture note:
      The long-term refactor target is for this file to become a staged hypothesis
      builder that consumes one canonical market truth and emits StrategyHypothesis_t.

      That means the intended future shape is:
         canonical market state
         -> staged gates
         -> StrategyHypothesis_t
         -> Router / Policies / Risk / Execution

      However, the CURRENT file is still a hybrid scoring/gating strategy evaluator.
      Today it mainly produces scored directional strategy outputs
      (StratScore / StrategyStatus / candidate intent),
      not a fully separated StrategyHypothesis_t pipeline yet.

   Output summary:
      This strategy is meant to answer:
         "Which side, if any, currently has the stronger Main-logic trade case?"

      It is designed to be selective.
      It should reject mid-range noise, weak location, weak liquidity behaviour,
      hostile microstructure, and shallow confirmation.
*/

// --- Project headers (match your tree) ---
#include "../BuildFlags.mqh"
#include "StrategyDirectExecGuards.mqh"
#include <Arrays\ArrayObj.mqh>
#include "StrategyBase.mqh"
#include "StrategyCommon.mqh"
#include "../Config.mqh"
#include "../Types.mqh"
#include "../State.mqh" 
#include "../Confluence.mqh"
#include "../InstitutionalStateVector.mqh"
#include "../Policies.mqh" 
#include "../PositionMgmt.mqh"
#include "../Logging.mqh"
#include "../MathUtils.mqh"
#include "../Telemetry.mqh"
#include "../Indicators.mqh"
#include "../StructureSDOB.mqh"
#include "../PivotsLevels.mqh"
#include "../LiquidityCues.mqh"
#include "../VSA.mqh"
#include "../Patterns.mqh"
#include "../AutochartistEngine.mqh"
#include "../DeltaProxy.mqh"
#include "../MarketData.mqh"
#include "../AutoVolatility.mqh"
#include "../OrderBookImbalance.mqh"
#include "../Trendlines.mqh"
#include "../ICTWyckoffPlaybook.mqh"

// -----------------------------------------------------------------------------
// AutoVol bridge (compile-safe)
// If MarketData implements AutoVol for real, define MARKETDATA_HAS_AUTOVOL there.
// -----------------------------------------------------------------------------
#ifndef MARKETDATA_HAS_AUTOVOL
namespace MarketData
{
   inline bool AutoVolGet(const string sym, AutoVolStats &out)
   {
      ZeroMemory(out);
      return false;
   }
}
#endif

#ifdef NEWSFILTER_AVAILABLE
  #include "../NewsFilter.mqh"
#endif

// C.A.N.D.L.E. Framework extensions — N (Narrative) and A (Axis Time-Memory)
#ifdef CANDLE_NARRATIVE_AVAILABLE
   #include "../CandleNarrative.mqh"
#endif

#ifdef AXIS_TIME_MEMORY_AVAILABLE
   #include "../LevelTimeMemory.mqh"
#endif

#ifndef STRAT_MAIN_ID
   #define STRAT_MAIN_ID STRAT_ID_MAIN_TRADING
#endif
#ifndef STRAT_MAIN_NAME
   #define STRAT_MAIN_NAME "MainTradingLogic"
#endif

#ifndef ROUTER_TRACE_FLOW
  #define ROUTER_TRACE_FLOW 0   // set to 1 to enable #F breadcrumbs
#endif

#ifndef CAEA_FLOWTAG_IMPL
   #define CAEA_FLOWTAG_IMPL
#endif

#ifndef STRAT_MAIN_NO_DIRECT_EXEC
   #define STRAT_MAIN_NO_DIRECT_EXEC
#endif

#ifndef STRAT_MAIN_DISABLE_TELEMETRY_NOTES
   #define STRAT_MAIN_DISABLE_TELEMETRY_NOTES
#endif

#ifndef STRAT_MAIN_REQUIRE_SCAN_MICRO
   #define STRAT_MAIN_REQUIRE_SCAN_MICRO
#endif

// -------------------- SCANNER READ ADAPTERS (DOWNSTREAM ONLY)
// This file must NOT run scanners. It only consumes Scan snapshots/events produced upstream.
namespace StratScan
{
  inline bool TryGetScanSnap(const string sym, const ENUM_TIMEFRAMES tf, Scan::IndiSnapshot &outSnap)
  {
    // Read-only: populated by MarketScannerHub -> Scan::TimerTick(...)
    return Scan::GetSnapshot(sym, tf, outSnap);
  }

  inline bool SnapReady(const Scan::IndiSnapshot &s)
  {
    // last_bar_open is set by Scan when bars are processed
    return (s.last_bar_open > 0);
  }

     inline int TfSecondsSafe(const ENUM_TIMEFRAMES tf)
   {
      int s = PeriodSeconds(tf);
      return (s > 0 ? s : 60);
   }

   // Reuse scan_liq_confirm_bars as the "freshness window" for liquidity events.
   inline int LiqEventWindowSec(const ENUM_TIMEFRAMES tf, const Settings &cfg)
   {
      int bars = cfg.scan_liq_confirm_bars;
      if(bars < 1) bars = 1;
      return TfSecondsSafe(tf) * (bars + 1);
   }

   // "Rejection" confirmation gate:
   // - Reject is only meaningful if it matches the last sweep side.
   inline bool LiqRejectRecentForDir(const Scan::IndiSnapshot &s, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
   {
      if(!SnapReady(s))
         return false;

      if(s.liq_last_reject_ts <= 0)
         return false;

      const int win = LiqEventWindowSec(tf, cfg);
      if((TimeCurrent() - s.liq_last_reject_ts) > win)
         return false;

      if(dir == DIR_BUY  && s.liq_last_sweep_kind != -1) return false; // want SSL sweep?reject
      if(dir == DIR_SELL && s.liq_last_sweep_kind !=  1) return false; // want BSL sweep?reject

      return true;
   }

   // Keep bit values aligned with Confluence.mqh::_ScanWyck_RT local bits
   const uchar WYCK_BIT_SPRING = 1; // (1u<<0)
   const uchar WYCK_BIT_UTAD   = 2; // (1u<<1)

   inline bool WyckManipRecentForDir(const Scan::IndiSnapshot &s,
                                     const ENUM_TIMEFRAMES tf,
                                     const Direction dir,
                                     const int barsFresh = 6)
   {
      if(!SnapReady(s) || s.wyck_last_event_ts <= 0)
         return false;

      const int maxAge = TfSecondsSafe(tf) * barsFresh;
      if(maxAge > 0 && (int)(TimeCurrent() - s.wyck_last_event_ts) > maxAge)
         return false;

      const uchar m = (uchar)s.wyck_last_mask;
      const bool isBuy = (dir == DIR_BUY);

      return isBuy ? ((m & WYCK_BIT_SPRING) != 0) : ((m & WYCK_BIT_UTAD) != 0);
   }

  // MACD cross needs "prev bar vs current bar" semantics without re-calling indicators.
  struct MacdCrossState
  {
    string   sym;
    int      tf;
    datetime bar_open;
    double   d_prev;
    double   d_curr;
    bool     inited;
  };
  static MacdCrossState g_macd_state[];

  inline int _FindMacdState(const string sym, const int tf)
  {
    const int n = ArraySize(g_macd_state);
    for(int i=0;i<n;i++)
      if(g_macd_state[i].tf==tf && g_macd_state[i].sym==sym)
        return i;
    return -1;
  }

  inline int _GetMacdState(const string sym, const ENUM_TIMEFRAMES tf)
  {
    int idx = _FindMacdState(sym, (int)tf);
    if(idx >= 0) return idx;

    const int n = ArraySize(g_macd_state);
    ArrayResize(g_macd_state, n+1);
    g_macd_state[n].sym = sym;
    g_macd_state[n].tf  = (int)tf;
    g_macd_state[n].bar_open = 0;
    g_macd_state[n].d_prev = 0.0;
    g_macd_state[n].d_curr = 0.0;
    g_macd_state[n].inited = false;
    return n;
  }

  inline bool MACD_CrossUsingScan(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Scan::IndiSnapshot &s)
  {
    if(!SnapReady(s)) return false;

    const double d = (s.macd_m - s.macd_s); // "MACD line - Signal line" for the last closed bar
    if(!MathIsValidNumber(d)) return false;

    const int idx = _GetMacdState(sym, tf);

    if(!g_macd_state[idx].inited)
    {
      g_macd_state[idx].bar_open = s.last_bar_open;
      g_macd_state[idx].d_prev   = d;
      g_macd_state[idx].d_curr   = d;
      g_macd_state[idx].inited   = true;
      return false; // no previous bar yet
    }

    // Only shift on a new bar (prevents repeated triggers within the same bar)
    if(g_macd_state[idx].bar_open != s.last_bar_open)
    {
      g_macd_state[idx].d_prev = g_macd_state[idx].d_curr;
      g_macd_state[idx].d_curr   = d;
      g_macd_state[idx].bar_open = s.last_bar_open;
    }

    if(dir == DIR_BUY)  return (g_macd_state[idx].d_curr > 0.0 && g_macd_state[idx].d_prev <= 0.0);
    if(dir == DIR_SELL) return (g_macd_state[idx].d_curr < 0.0 && g_macd_state[idx].d_prev >= 0.0);
    return false;
  }
}

inline double _MainClamp01(const double v)
{
   if(v < 0.0) return 0.0;
   if(v > 1.0) return 1.0;
   return v;
}

inline double _MainClamp11(const double v)
{
   if(v < -1.0) return -1.0;
   if(v > 1.0)  return 1.0;
   return v;
}

inline void Main_ResetHeadScores(StratScore &ss)
{
   #ifdef STRATSCORE_HAS_ALPHA_SCORE
      ss.alpha_score = 0.0;
   #endif
   #ifdef STRATSCORE_HAS_EXECUTION_SCORE
      ss.execution_score = 0.0;
   #endif
   #ifdef STRATSCORE_HAS_RISK_SCORE
      ss.risk_score = 0.0;
   #endif
}

inline void Main_SetHeadScores(StratScore &ss,
                               const double alpha01,
                               const double execution01,
                               const double risk01)
{
   #ifdef STRATSCORE_HAS_ALPHA_SCORE
      ss.alpha_score = _MainClamp01(alpha01);
   #endif
   #ifdef STRATSCORE_HAS_EXECUTION_SCORE
      ss.execution_score = _MainClamp01(execution01);
   #endif
   #ifdef STRATSCORE_HAS_RISK_SCORE
      ss.risk_score = _MainClamp01(risk01);
   #endif
}

inline void Main_SetBreakdownHeadScores(ConfluenceBreakdown &bd,
                                        const double alpha01,
                                        const double execution01,
                                        const double risk01)
{
   #ifdef BDCONF_HAS_ALPHA_SCORE
      bd.alpha_score = _MainClamp01(alpha01);
   #endif
   #ifdef BDCONF_HAS_EXECUTION_SCORE
      bd.execution_score = _MainClamp01(execution01);
   #endif
   #ifdef BDCONF_HAS_RISK_SCORE
      bd.risk_score = _MainClamp01(risk01);
   #endif
}

inline bool Main_IsTesterRuntime()
{
   return (MQLInfoInteger(MQL_TESTER) != 0 ||
           MQLInfoInteger(MQL_OPTIMIZATION) != 0);
}

inline bool Main_ApplyTesterForcedScore(StratScore &ss,
                                        ConfluenceBreakdown &bd)
{
   if(!Main_IsTesterRuntime())
      return false;

   if(ss.eligible && MathIsValidNumber(ss.score) && ss.score > 0.0)
      return false;

   ss.eligible  = true;
   ss.score     = 1.0;
   ss.score_raw = 1.0;
   ss.risk_mult = 1.0;

   if(ss.reason != "")
      ss.reason = "tester_forced | " + ss.reason;
   else
      ss.reason = "tester_forced";

   Main_SetHeadScores(ss, 1.0, 1.0, 0.0);
   Main_SetBreakdownHeadScores(bd, 1.0, 1.0, 0.0);

   bd.veto                = false;
   bd.score_after_penalty = 1.0;

   return true;
}

inline double Main_CfgAlphaMin(const Settings &cfg)
{
   if(Main_CfgTesterLooseGate(cfg))
      return 0.0;

   if(MQLInfoInteger(MQL_TESTER) != 0)
   {
   #ifdef CFG_HAS_MAIN_TESTER_ALPHA_MIN
      return _MainClamp01(cfg.main_tester_alpha_min);
   #endif

   #ifdef CFG_HAS_MAIN_TESTER_SOFTEN_SELECTED_HARD_GATES
      if(cfg.main_tester_soften_selected_hard_gates)
         return 0.0;
   #endif
   }

   double v = 0.55;
   #ifdef CFG_HAS_MAIN_ALPHA_MIN
      if(cfg.main_alpha_min > 0.0)
         v = cfg.main_alpha_min;
   #endif
   return _MainClamp01(v);
}

inline double Main_CfgExecMin(const Settings &cfg)
{
   if(Main_CfgTesterLooseGate(cfg))
      return 0.0;

   if(MQLInfoInteger(MQL_TESTER) != 0)
   {
   #ifdef CFG_HAS_MAIN_TESTER_EXEC_MIN
      return _MainClamp01(cfg.main_tester_exec_min);
   #endif

   #ifdef CFG_HAS_MAIN_TESTER_SOFTEN_SELECTED_HARD_GATES
      if(cfg.main_tester_soften_selected_hard_gates)
         return 0.0;
   #endif
   }

   double v = 0.45;
   #ifdef CFG_HAS_MAIN_EXEC_MIN
      if(cfg.main_exec_min > 0.0)
         v = cfg.main_exec_min;
   #endif
   return _MainClamp01(v);
}

inline double Main_CfgRiskMax(const Settings &cfg)
{
   if(Main_CfgTesterLooseGate(cfg))
      return 1.0;

   if(MQLInfoInteger(MQL_TESTER) != 0)
   {
   #ifdef CFG_HAS_MAIN_TESTER_RISK_MAX
      return _MainClamp01(cfg.main_tester_risk_max);
   #endif

   #ifdef CFG_HAS_MAIN_TESTER_SOFTEN_SELECTED_HARD_GATES
      if(cfg.main_tester_soften_selected_hard_gates)
         return 1.0;
   #endif
   }

   double v = 0.55;
   #ifdef CFG_HAS_MAIN_RISK_MAX
      if(cfg.main_risk_max > 0.0)
         v = cfg.main_risk_max;
   #endif
   return _MainClamp01(v);
}

inline double Main_StratAlpha01(const StratScore &s)
{
   #ifdef STRATSCORE_HAS_ALPHA_SCORE
      return _MainClamp01(s.alpha_score);
   #else
      return _MainClamp01(s.score);
   #endif
}

inline double Main_StratExecution01(const StratScore &s)
{
   #ifdef STRATSCORE_HAS_EXECUTION_SCORE
      return _MainClamp01(s.execution_score);
   #else
      return _MainClamp01(s.score);
   #endif
}

inline double Main_StratRisk01(const StratScore &s)
{
   #ifdef STRATSCORE_HAS_RISK_SCORE
      return _MainClamp01(s.risk_score);
   #else
      return 1.0 - _MainClamp01(s.score);
   #endif
}

inline bool Main_HeadThresholdsPass(const Settings &cfg,
                                    const double alpha01,
                                    const double execution01,
                                    const double risk01,
                                    string &whyOut)
{
   whyOut = "";

   const double alphaMin = Main_CfgAlphaMin(cfg);
   const double execMin  = Main_CfgExecMin(cfg);
   const double riskMax  = Main_CfgRiskMax(cfg);

   if(alpha01 < alphaMin)
   {
      whyOut = StringFormat("alpha %.2f < %.2f", alpha01, alphaMin);
      return false;
   }

   if(execution01 < execMin)
   {
      whyOut = StringFormat("exec %.2f < %.2f", execution01, execMin);
      return false;
   }

   if(risk01 > riskMax)
   {
      whyOut = StringFormat("risk %.2f > %.2f", risk01, riskMax);
      return false;
   }

   whyOut = "head thresholds ok";
   return true;
}

inline bool Main_StratPassesHeads(const Settings &cfg,
                                  const StratScore &s,
                                  string &whyOut)
{
   if(!s.eligible)
   {
      whyOut = "not eligible";
      return false;
   }

   return Main_HeadThresholdsPass(cfg,
                                  Main_StratAlpha01(s),
                                  Main_StratExecution01(s),
                                  Main_StratRisk01(s),
                                  whyOut);
}

inline bool Main_IsBetterSide(const Settings &cfg,
                              const StratScore &lhs,
                              const StratScore &rhs)
{
   string whyL = "";
   string whyR = "";

   const bool lhsOK = Main_StratPassesHeads(cfg, lhs, whyL);
   const bool rhsOK = Main_StratPassesHeads(cfg, rhs, whyR);

   if(lhsOK != rhsOK)
      return lhsOK;

   const double aL = Main_StratAlpha01(lhs);
   const double aR = Main_StratAlpha01(rhs);

   if(aL > aR + 0.0001)
      return true;
   if(aR > aL + 0.0001)
      return false;

   const double eL = Main_StratExecution01(lhs);
   const double eR = Main_StratExecution01(rhs);

   if(eL > eR + 0.0001)
      return true;
   if(eR > eL + 0.0001)
      return false;

   const double rL = Main_StratRisk01(lhs);
   const double rR = Main_StratRisk01(rhs);

   if(rL + 0.0001 < rR)
      return true;
   if(rR + 0.0001 < rL)
      return false;

   return (lhs.score >= rhs.score);
}

enum MainMicroArchetype
{
   MAIN_MICRO_TREND = 0,
   MAIN_MICRO_MEANREV = 1,
   MAIN_MICRO_BREAKOUT = 2
};

struct MainOFDS
{
   bool   ready;
   bool   have_flow;
   bool   have_vpin;
   bool   have_resil;
   bool   have_wyckoff;
   bool   direct_micro_available;
   bool   proxy_micro_available;

   int    micro_mode;      // InstitutionalMicroMode
   int    asset_preset;    // local Main classification: FX_OTC / XAU_OTC / OTHER

   // direct micro
   double ofi;
   double obi;
   double cvd;
   double vpin;
   double resil;
   double impact_beta;
   double impact_lambda;
   double spread_shock;
   double wyckoff_score;

   // proxy / fallback stack
   double delta_proxy_dir01;
   double footprint_dir01;
   double footprint_conf01;
   double profile_dir01;
   double profile_conf01;
   double vsa_dir01;
   double vsa_absorption01;
   double vsa_replenishment01;
   double vwap_location01;
   double vwap_stretch01;
   double liquidity_event01;
   double liquidity_reject01;
   double slippage_stress01;

   // meta
   double observability01;
   double observability_penalty01;
   double truth_tier01;
   double venue_scope01;
   double darkpool01;

   // overlay / context
   double sd_demand01;
   double sd_supply01;
   double ob_bull01;
   double ob_bear01;
   double fvg_bull01;
   double fvg_bear01;
   double wyckoff_turn01;
   double liquidity_hunt01;

   // fused outputs
   double flow_dir;
   double toxicity;

   bool   trade_gate_pass;
   double flow_confidence01;
   double venue_coverage01;

   double alpha_head01;
   double execution_head01;
   double risk_head01;

   StateInstitutionalSymbolView         state_view;
   StateInstitutionalTransportDiagCache diag_cache;
};

struct MainFusedHeads
{
   bool               have_entry_scan;
   bool               have_trend_scan;
   bool               have_ofds;
   bool               have_auto;
   bool               have_autovol;
   bool               have_inst_bundle;

   Scan::IndiSnapshot entry_scan;
   Scan::IndiSnapshot trend_scan;
   MainOFDS           ofds;
   AutoSnapshot       auto_snap;
   AutoVol::AutoVolStats autovol;
   StratCommon::InstitutionalBundle inst_bundle;
};

inline bool Main_TryBuildOFDSFromSnap(const Scan::IndiSnapshot &s,
                                      MainOFDS &out)
{
   ZeroMemory(out);

   bool haveAny = false;
   bool haveOfi = false;
   bool haveObi = false;
   bool haveCvd = false;

   #ifdef SCAN_SNAPSHOT_HAS_MICROSTRUCTURE_STATS
      #ifdef MICROSTRUCT_HAS_OFI
         out.ofi = s.ms.ofi;
         haveOfi = MathIsValidNumber(out.ofi);
         if(haveOfi) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_OBI1
         out.obi = s.ms.obi1;
         haveObi = MathIsValidNumber(out.obi);
         if(haveObi) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_CVD
         out.cvd = s.ms.cvd;
         haveCvd = MathIsValidNumber(out.cvd);
         if(haveCvd) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_VPIN
         out.vpin = s.ms.vpin;
         out.have_vpin = MathIsValidNumber(out.vpin);
         if(out.have_vpin) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_RESIL
         out.resil = s.ms.resil;
         out.have_resil = MathIsValidNumber(out.resil);
         if(out.have_resil) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_LAMBDA
         out.impact_lambda = s.ms.lambda;
         if(MathIsValidNumber(out.impact_lambda)) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_SPREAD_SHOCK
         out.spread_shock = s.ms.spread_shock;
         if(MathIsValidNumber(out.spread_shock)) haveAny = true;
      #endif

      #ifdef MICROSTRUCT_HAS_WYCKOFF_SCORE
         out.wyckoff_score = s.ms.wyckoff_score;
         out.have_wyckoff  = MathIsValidNumber(out.wyckoff_score);
         if(out.have_wyckoff) haveAny = true;
      #endif
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_OFI
      out.ofi = s.ms_ofi;
      haveOfi = MathIsValidNumber(out.ofi);
      if(haveOfi) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_OBI1
      out.obi = s.ms_obi1;
      haveObi = MathIsValidNumber(out.obi);
      if(haveObi) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_CVD
      out.cvd = s.ms_cvd;
      haveCvd = MathIsValidNumber(out.cvd);
      if(haveCvd) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_VPIN
      out.vpin = s.ms_vpin;
      out.have_vpin = MathIsValidNumber(out.vpin);
      if(out.have_vpin) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_RESIL
      out.resil = s.ms_resil;
      out.have_resil = MathIsValidNumber(out.resil);
      if(out.have_resil) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_LAMBDA
      out.impact_lambda = s.ms_lambda;
      if(MathIsValidNumber(out.impact_lambda)) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_SPREAD_SHOCK
      out.spread_shock = s.ms_spread_shock;
      if(MathIsValidNumber(out.spread_shock)) haveAny = true;
   #endif

   #ifdef SCAN_SNAPSHOT_HAS_MS_WYCKOFF_SCORE
      out.wyckoff_score = s.ms_wyckoff_score;
      out.have_wyckoff  = MathIsValidNumber(out.wyckoff_score);
      if(out.have_wyckoff) haveAny = true;
   #endif

   if(haveOfi || haveObi || haveCvd)
   {
      double num = 0.0;
      double den = 0.0;

      if(haveOfi)
      {
         num += 0.55 * _MainClamp11(out.ofi);
         den += 0.55;
      }

      if(haveObi)
      {
         num += 0.35 * _MainClamp11(out.obi);
         den += 0.35;
      }

      if(haveCvd)
      {
         num += 0.10 * _MainClamp11(out.cvd);
         den += 0.10;
      }

      if(den > 0.0)
      {
         out.flow_dir = _MainClamp11(num / den);
         out.have_flow = true;
      }
   }

   double toxNum = 0.0;
   double toxDen = 0.0;

   if(out.have_vpin)
   {
      toxNum += 0.60 * _MainClamp01(out.vpin);
      toxDen += 0.60;
   }

   if(MathIsValidNumber(out.spread_shock))
   {
      toxNum += 0.20 * _MainClamp01(out.spread_shock);
      toxDen += 0.20;
   }

   if(out.have_resil)
   {
      toxNum += 0.20 * (1.0 - _MainClamp01(out.resil));
      toxDen += 0.20;
   }

   out.toxicity = (toxDen > 0.0 ? _MainClamp01(toxNum / toxDen) : 0.0);
   out.ready = haveAny;
   return out.ready;
}

inline bool Main_TryLoadOFDS(const string sym,
                             const ENUM_TIMEFRAMES tf,
                             Scan::IndiSnapshot &snap,
                             MainOFDS &out)
{
   ZeroMemory(out);

   if(!StratScan::TryGetScanSnap(sym, tf, snap))
      return false;
   if(!StratScan::SnapReady(snap))
      return false;

   return Main_TryBuildOFDSFromSnap(snap, out);
}

enum
{
   MAIN_ASSET_UNKNOWN = 0,
   MAIN_ASSET_FX_OTC  = 1,
   MAIN_ASSET_XAU_OTC = 2,
   MAIN_ASSET_OTHER   = 3
};

inline double Main_Long01ToSigned(const double x)
{
   return _MainClamp11((2.0 * _MainClamp01(x)) - 1.0);
}

inline double Main_DirSupport01(const Direction dir, const double longSide01)
{
   const double x = _MainClamp01(longSide01);
   return (dir == DIR_SELL ? _MainClamp01(1.0 - x) : x);
}

inline int Main_DetectAssetPreset(const string sym)
{
   string u = sym;
   StringToUpper(u);

   if(StringFind(u, "XAU", 0) >= 0 || StringFind(u, "GOLD", 0) >= 0)
      return MAIN_ASSET_XAU_OTC;

   if(StringLen(u) >= 6)
   {
      const string base  = StringSubstr(u, 0, 3);
      const string quote = StringSubstr(u, 3, 3);

      if(StringLen(base) == 3 && StringLen(quote) == 3)
         return MAIN_ASSET_FX_OTC;
   }

   return MAIN_ASSET_OTHER;
}

inline double Main_CfgObsDirectMin(const Settings &cfg)
{
#ifdef CFG_HAS_MS_MODE_OBSERVABILITY_THRESHOLDS
   if(cfg.ms_observability_direct_min01 > 0.0)
      return _MainClamp01(cfg.ms_observability_direct_min01);
#endif
   return 0.85;
}

inline double Main_CfgObsProxyMin(const Settings &cfg)
{
#ifdef CFG_HAS_MS_MODE_OBSERVABILITY_THRESHOLDS
   if(cfg.ms_observability_proxy_min01 > 0.0)
      return _MainClamp01(cfg.ms_observability_proxy_min01);
#endif
   return 0.60;
}

inline double Main_CfgObsStructureMin(const Settings &cfg)
{
#ifdef CFG_HAS_MS_MODE_OBSERVABILITY_THRESHOLDS
   if(cfg.ms_observability_structure_only_min01 >= 0.0)
      return _MainClamp01(cfg.ms_observability_structure_only_min01);
#endif
   return 0.35;
}

inline double Main_CfgTruthContinuationMin(const Settings &cfg)
{
#ifdef CFG_HAS_MS_ARCHETYPE_TRUTH_THRESHOLDS
   if(cfg.ms_truth_min_continuation01 > 0.0)
      return _MainClamp01(cfg.ms_truth_min_continuation01);
#endif
   return 0.60;
}

inline double Main_CfgTruthBreakoutMin(const Settings &cfg)
{
#ifdef CFG_HAS_MS_ARCHETYPE_TRUTH_THRESHOLDS
   if(cfg.ms_truth_min_breakout01 > 0.0)
      return _MainClamp01(cfg.ms_truth_min_breakout01);
#endif
   return 0.70;
}

inline double Main_CfgTruthReversalMin(const Settings &cfg)
{
#ifdef CFG_HAS_MS_ARCHETYPE_TRUTH_THRESHOLDS
   if(cfg.ms_truth_min_reversal01 >= 0.0)
      return _MainClamp01(cfg.ms_truth_min_reversal01);
#endif
   return 0.35;
}

inline bool Main_CfgTesterDegradedMode(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

   return Config::CfgTesterDegradedModeActive(cfg);
}

inline bool Main_CfgTesterSoftenSelectedHardGates(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

   return Config::CfgMainTesterAllowDegradedObservabilitySoftening(cfg);
}

inline bool Main_CfgTesterRegimeObservabilitySoftening(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

   return Config::CfgMainTesterAllowRegimeObservabilitySoftening(cfg);
}

inline bool Main_CfgTesterLiquidityObservabilitySoftening(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

   return Config::CfgMainTesterAllowLiquidityObservabilitySoftening(cfg);
}

inline bool Main_CfgTesterLooseGate(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

   if(Config::CfgMainTesterLooseModeActive(cfg))
      return true;

   if(Main_CfgTesterSoftenSelectedHardGates(cfg))
      return true;

   return false;
}

inline bool Main_CfgTesterTriggerSofteningActive(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

   if(!Main_CfgTesterDegradedMode(cfg))
      return false;

   return Main_CfgTesterSoftenSelectedHardGates(cfg);
}

inline bool Main_CfgTesterDisableNewsAndCorrelation(const Settings &cfg)
{
   if(!Main_IsTesterRuntime())
      return false;

#ifdef CFG_HAS_TESTER_DISABLE_NEWS_CORR
   return (cfg.tester_disable_news_and_correlation ? true : false);
#endif

   return false;
}

inline bool Main_CfgTesterDisableKillzone(const Settings &cfg)
{
   if(Main_CfgTesterLooseGate(cfg))
      return true;

   if(!Main_IsTesterRuntime())
      return false;

   #ifdef CFG_HAS_TESTER_ENFORCE_KILLZONE
      return (!cfg.tester_enforce_killzone);
   #endif

   return false;
}

#ifndef CA_RUNTIME_MAIN_CHECKLIST_SOFT_FALLBACK_DECL
#define CA_RUNTIME_MAIN_CHECKLIST_SOFT_FALLBACK_DECL
bool RuntimeMainChecklistSoftFallbackEnabled();
#endif

inline bool Main_CanUseTesterFallbackDegradedMode(const Settings &cfg,
                                                  const MainFusedHeads &heads,
                                                  string &whyOut)
{
   whyOut = "";

   if(!Main_IsTesterRuntime())
      return false;

   if(!Main_CfgTesterDegradedMode(cfg))
      return false;

   // Canonical institutional bundle is the preferred transport.
   // Tester degraded mode is only allowed when canonical transport is unavailable
   // but fallback OFDS inputs are still present.
   if(heads.have_inst_bundle)
      return false;

   if(!heads.have_ofds)
      return false;

   whyOut = "canonical_inst_unavailable_with_tester_fallback";
   return true;
}

inline bool Main_CanUseTesterSelectedGateSoftening(const Settings &cfg,
                                                   const MainFusedHeads &heads,
                                                   string &whyOut)
{
   whyOut = "";

   if(!Main_CanUseTesterFallbackDegradedMode(cfg, heads, whyOut))
      return false;

   if(!Main_CfgTesterSoftenSelectedHardGates(cfg))
   {
      whyOut = "";
      return false;
   }

   whyOut = "tester_selected_gate_softening";
   return true;
}

inline void Main_OverlayOFDSFromBundle(const string sym,
                                       const StratCommon::InstitutionalBundle &b,
                                       MainOFDS &out)
{
   if(!b.valid)
      return;

   out.ready                  = true;
   out.micro_mode             = b.micro_mode;
   out.asset_preset           = Main_DetectAssetPreset(sym);
   out.direct_micro_available = (b.micro_mode == INST_MICRO_MODE_DIRECT);
   out.proxy_micro_available  = (b.micro_mode == INST_MICRO_MODE_PROXY || b.micro_mode == INST_MICRO_MODE_DIRECT);

   if(out.direct_micro_available)
   {
      out.ofi       = Main_Long01ToSigned(b.ofi01);
      out.obi       = Main_Long01ToSigned(b.obi01);
      out.cvd       = Main_Long01ToSigned(b.cvd01);
      out.have_flow = true;
   }

   if(!out.have_vpin)
   {
      out.vpin      = _MainClamp01(b.toxicity01);
      out.have_vpin = true;
   }

   if(!out.have_resil)
   {
      out.resil      = _MainClamp01(b.resiliency01);
      out.have_resil = true;
   }

   out.impact_beta   = _MainClamp01(b.impact_beta01);
   out.impact_lambda = _MainClamp01(b.impact_lambda01);

   if(!MathIsValidNumber(out.spread_shock) || out.spread_shock <= 0.0)
      out.spread_shock = _MainClamp01(MathMax(b.toxicity01, b.observability_penalty01));

   out.delta_proxy_dir01    = _MainClamp01(b.flow_dir01);
   out.footprint_dir01      = _MainClamp01(b.footprint01);
   out.footprint_conf01     = _MainClamp01(MathMax(b.observability01, 1.0 - b.observability_penalty01));
   out.profile_dir01        = _MainClamp01(b.profile01);
   out.profile_conf01       = _MainClamp01(MathMax(b.observability01, 1.0 - b.observability_penalty01));
   out.vsa_dir01            = _MainClamp01(MathMax(b.absorption01, b.replenishment01));
   out.vsa_absorption01     = _MainClamp01(b.absorption01);
   out.vsa_replenishment01  = _MainClamp01(b.replenishment01);
   out.vwap_location01      = _MainClamp01(b.profile01);
   out.vwap_stretch01       = _MainClamp01(b.observability_penalty01);
   out.liquidity_event01    = _MainClamp01(b.liquidity_hunt01);
   out.liquidity_reject01   = _MainClamp01(MathMax(b.absorption01, b.profile01));
   out.slippage_stress01    = _MainClamp01(MathMax(b.toxicity01, b.impact_lambda01));

   out.observability01         = _MainClamp01(b.observability01);
   out.observability_penalty01 = _MainClamp01(b.observability_penalty01);
   out.truth_tier01            = _MainClamp01(b.truth_tier01);
   out.venue_scope01           = _MainClamp01(b.venue_scope01);
   out.darkpool01              = _MainClamp01(b.darkpool01);
   out.liquidity_hunt01        = _MainClamp01(b.liquidity_hunt01);

   if(!out.have_wyckoff)
   {
      out.wyckoff_score = _MainClamp01(MathMax(b.absorption01, b.liquidity_hunt01));
      out.have_wyckoff  = MathIsValidNumber(out.wyckoff_score);
   }

   out.flow_dir = Main_Long01ToSigned(b.flow_dir01);
   out.toxicity = _MainClamp01(b.toxicity01);
}

inline void Main_OverlayOFDSContext(const ICT_Context &ctx, MainOFDS &out)
{
   const bool haveDemand =
      ((ctx.bestDemandZoneH1.hi != 0.0 || ctx.bestDemandZoneH1.lo != 0.0) ||
       (ctx.bestDemandZoneH4.hi != 0.0 || ctx.bestDemandZoneH4.lo != 0.0));

   const bool haveSupply =
      ((ctx.bestSupplyZoneH1.hi != 0.0 || ctx.bestSupplyZoneH1.lo != 0.0) ||
       (ctx.bestSupplyZoneH4.hi != 0.0 || ctx.bestSupplyZoneH4.lo != 0.0));

   out.sd_demand01 = (haveDemand ? 1.0 : 0.0);
   out.sd_supply01 = (haveSupply ? 1.0 : 0.0);

   out.ob_bull01 =
      ((ctx.activeOrderBlock.high != 0.0 || ctx.activeOrderBlock.low != 0.0) &&
       ctx.activeOrderBlock.isBullish ? 1.0 : 0.0);

   out.ob_bear01 =
      ((ctx.activeOrderBlock.high != 0.0 || ctx.activeOrderBlock.low != 0.0) &&
       !ctx.activeOrderBlock.isBullish ? 1.0 : 0.0);

   out.fvg_bull01 =
      ((ctx.activeFVG.high != 0.0 || ctx.activeFVG.low != 0.0) &&
       ctx.activeFVG.isBullish ? 1.0 : 0.0);

   out.fvg_bear01 =
      ((ctx.activeFVG.high != 0.0 || ctx.activeFVG.low != 0.0) &&
       !ctx.activeFVG.isBullish ? 1.0 : 0.0);

   out.wyckoff_turn01 =
      ((ctx.wySpringCandidate || ctx.wyUTADCandidate) ? 1.0 : 0.0);

   out.liquidity_hunt01 =
      ((ctx.liquiditySweepType == SWEEP_SELLSIDE) ||
       (ctx.liquiditySweepType == SWEEP_BUYSIDE)  ||
       (ctx.liquiditySweepType == SWEEP_BOTH) ? 1.0 : 0.0);
}

inline bool Main_TryBuildOFDSFromState(const string sym,
                                       const ENUM_TIMEFRAMES tf_entry,
                                       const Direction dir,
                                       const Settings &cfg,
                                       const ICT_Context &ctx,
                                       MainOFDS &out)
{
   ZeroMemory(out);

   datetime required_bar_time = 0;
   if(tf_entry > PERIOD_CURRENT)
      required_bar_time = iTime(sym, tf_entry, 1);

   StateInstitutionalSymbolView sv;
   sv.Reset();

   if(!State::GetInstitutionalSymbolViewBySymbolWithFallback(cfg, sym, sv, required_bar_time))
      return false;

   StateInstitutionalTransportDiagCache diag;
   diag.Reset();
   State::GetInstitutionalTransportDiagCacheBySymbol(cfg, sym, diag, required_bar_time);

   out.state_view                 = sv;
   out.diag_cache                 = diag;

   out.ready                      = sv.valid;
   out.trade_gate_pass            = sv.trade_gate_pass;
   out.direct_micro_available     = sv.direct_micro_available;
   out.proxy_micro_available      = sv.proxy_micro_available;
   out.micro_mode                 = sv.micro_mode;

   out.asset_preset               = Main_DetectAssetPreset(sym);

   out.ofi                        = _MainClamp11(sv.ofi_z);
   out.obi                        = _MainClamp11(2.0 * _MainClamp01(sv.obi01) - 1.0);
   out.cvd                        = _MainClamp11(sv.cvd_z);

   out.vpin                       = _MainClamp01(sv.vpin01);
   out.resil                      = _MainClamp01(sv.resiliency01);
   out.impact_beta                = _MainClamp01(sv.impact_beta01);
   out.impact_lambda              = _MainClamp01(sv.impact_lambda01);
   out.spread_shock               = _MainClamp01(sv.liquidity_stress01);
   out.wyckoff_score              = 0.0;

   out.delta_proxy_dir01          = _MainClamp01(sv.delta_proxy01);
   out.footprint_dir01            = _MainClamp01(sv.footprint01);
   out.footprint_conf01           = _MainClamp01(sv.observability01);

   out.profile_dir01              = _MainClamp01(sv.profile01);
   out.profile_conf01             = _MainClamp01(sv.observability01);

   out.vsa_dir01                  = _MainClamp01(0.5 * (sv.absorption01 + sv.replenishment01));
   out.vsa_absorption01           = _MainClamp01(sv.absorption01);
   out.vsa_replenishment01        = _MainClamp01(sv.replenishment01);
   out.vwap_location01            = _MainClamp01(sv.vwap_location01);
   out.vwap_stretch01             = _MainClamp01(MathAbs(sv.vwap_location01 - 0.5) * 2.0);
   out.liquidity_event01          = _MainClamp01(MathMax(sv.liquidity_hunt01, sv.sweep_score01));
   out.liquidity_reject01         = _MainClamp01(sv.liquidity_reject01);
   out.slippage_stress01          = _MainClamp01(sv.volatility_stress01);

   out.observability01            = _MainClamp01(sv.observability01);
   out.observability_penalty01    = _MainClamp01(sv.observability_penalty01);
   out.truth_tier01               = _MainClamp01(sv.truth_tier01);
   out.venue_scope01              = _MainClamp01(sv.venue_scope01);
   out.flow_confidence01          = _MainClamp01(sv.flow_confidence01);
   out.venue_coverage01           = _MainClamp01(sv.venue_coverage01);

   out.darkpool01                 = _MainClamp01(sv.darkpool01);
   out.liquidity_hunt01           = _MainClamp01(MathMax(sv.liquidity_hunt01, sv.sweep_score01));

   out.alpha_head01               = _MainClamp01(sv.alpha01);
   out.execution_head01           = _MainClamp01(sv.execution01);
   out.risk_head01                = _MainClamp01(sv.risk01);

   out.flow_dir                   = out.ofi;
   out.toxicity                   = _MainClamp01(MathMax(sv.toxicity01,
                                                         MathMax(out.spread_shock,
                                                                 out.slippage_stress01)));

   out.have_flow                  = (sv.direct_micro_available || sv.proxy_micro_available);
   out.have_vpin                  = true;
   out.have_resil                 = true;

   Main_OverlayOFDSContext(ctx, out);
   return out.ready;
}

inline void Main_ResetFusedHeads(MainFusedHeads &h)
{
   h.have_entry_scan  = false;
   h.have_trend_scan  = false;
   h.have_ofds        = false;
   h.have_auto        = false;
   h.have_autovol     = false;
   h.have_inst_bundle = false;

   ZeroMemory(h.entry_scan);
   ZeroMemory(h.trend_scan);
   ZeroMemory(h.ofds);
   ZeroMemory(h.autovol);
   h.inst_bundle.Reset();
}

inline void Main_LoadCanonicalICTContext(const string sym,
                                         const Settings &cfg,
                                         ICT_Context &ctx)
{
   ZeroMemory(ctx);
   State::StateUpdateICTContext(cfg);

   #ifdef STATE_HAS_ICTCTX_BY_SYMBOL
      ctx = State::StateGetICTContext(sym);
   #else
      ctx = State::StateGetICTContext();
   #endif
}

inline bool Main_TryLiquidityContextFromScan(const Scan::IndiSnapshot &s,
                                             const ENUM_TIMEFRAMES tf,
                                             const Direction dir,
                                             const Settings &cfg,
                                             bool &scanIsAuthoritative)
{
   scanIsAuthoritative = false;

   if(!StratScan::SnapReady(s) || !cfg.scan_liq_enable)
      return false;

   scanIsAuthoritative = true;

   const bool isBuy = (dir == DIR_BUY);
   const datetime now = TimeCurrent();
   const int winSec = StratScan::LiqEventWindowSec(tf, cfg);
   bool ok = false;

   #ifdef SCAN_SNAP_HAS_LIQ_POOLS
      const uchar st = (isBuy ? s.liq_ssl_state : s.liq_bsl_state);

      if(st == 3)
         return false;

      if(st == 1 || st == 2)
         ok = true;

      if(isBuy && s.liq_ssl_in_approach)
         ok = true;
      if(!isBuy && s.liq_bsl_in_approach)
         ok = true;
   #endif

   if(isBuy)
   {
      if(s.liq_last_sweep_ssl_ts > 0 && (now - s.liq_last_sweep_ssl_ts) <= winSec)
         ok = true;

      if(s.liq_last_reject_ts > 0 &&
         (now - s.liq_last_reject_ts) <= winSec &&
         s.liq_last_sweep_kind == -1)
         ok = true;
   }
   else
   {
      if(s.liq_last_sweep_bsl_ts > 0 && (now - s.liq_last_sweep_bsl_ts) <= winSec)
         ok = true;

      if(s.liq_last_reject_ts > 0 &&
         (now - s.liq_last_reject_ts) <= winSec &&
         s.liq_last_sweep_kind == 1)
         ok = true;
   }

   #ifdef SCAN_SNAP_HAS_LIQ_POOLS
      const bool scanHasPools = (s.liq_bsl_level > 0.0 || s.liq_ssl_level > 0.0);
      if(scanHasPools && !ok)
         return false;
   #endif

   return ok;
}

inline void Main_LoadFusedHeads(const string sym,
                                const ENUM_TIMEFRAMES tf_entry,
                                const Direction dir,
                                const Settings &cfg,
                                const ICT_Context &ctx,
                                MainFusedHeads &h)
{
   Main_ResetFusedHeads(h);

   if(StratScan::TryGetScanSnap(sym, tf_entry, h.entry_scan) && StratScan::SnapReady(h.entry_scan))
   {
      h.have_entry_scan = true;
      h.have_ofds = Main_TryBuildOFDSFromSnap(h.entry_scan, h.ofds);
   }

   const ENUM_TIMEFRAMES tfTrend = (ENUM_TIMEFRAMES)cfg.tf_trend_htf;
   if(StratScan::TryGetScanSnap(sym, tfTrend, h.trend_scan) && StratScan::SnapReady(h.trend_scan))
      h.have_trend_scan = true;

   const bool wantAuto =
      (cfg.auto_enable &&
       (cfg.cf_autochartist_chart ||
        cfg.cf_autochartist_fib ||
        cfg.cf_autochartist_keylevels ||
        cfg.cf_autochartist_volatility));

   if(wantAuto)
      h.have_auto = AutoC::GetSnapshot(sym, tf_entry, cfg, h.auto_snap);

   h.have_autovol = MarketData::AutoVolGet(sym, h.autovol);

   if(Main_TryBuildOFDSFromState(sym, tf_entry, dir, cfg, ctx, h.ofds))
   {
      h.have_ofds = h.ofds.ready;
      h.have_inst_bundle = false;
   }
   else
   {
#ifdef STRATCOMMON_HAS_INSTITUTIONAL_BUNDLE_HELPERS
      StratCommon::InstitutionalBundle bundle;
      bundle.Reset();
   
      if(StratCommon::BuildInstitutionalBundleFromScanSnap(sym, tf_entry, dir, cfg, ctx, bundle))
      {
         h.have_inst_bundle = true;
         h.have_ofds = true;
         Main_OverlayOFDSFromBundle(sym, bundle, h.ofds);
         Main_OverlayOFDSContext(ctx, h.ofds);
      }
#endif
   }
}

inline int Main_ClassifyMicroArchetype(const ICT_Context &ctx,
                                       const Direction dir,
                                       const bool withBias,
                                       const bool againstBias,
                                       const bool haveAuto,
                                       const AutoSnapshot &autoS)
{
   bool breakoutHint = false;

   if(haveAuto && autoS.chart.kind != AUTO_CHART_NONE)
   {
      if(autoS.chart.completed)
         breakoutHint = true;
      else if(autoS.chart.q.breakout_strength >= 0.55)
         breakoutHint = true;
   }

   const bool sweepCtx =
      (dir == DIR_BUY
         ? (ctx.liquiditySweepType == SWEEP_SELLSIDE || ctx.liquiditySweepType == SWEEP_BOTH)
         : (ctx.liquiditySweepType == SWEEP_BUYSIDE  || ctx.liquiditySweepType == SWEEP_BOTH));

   const bool meanRevHint =
      (againstBias ||
       ctx.chochDetected ||
       ctx.wySpringCandidate ||
       ctx.wyUTADCandidate ||
       sweepCtx);

   if(breakoutHint)
      return MAIN_MICRO_BREAKOUT;

   if(meanRevHint)
      return MAIN_MICRO_MEANREV;

   if(withBias || ctx.bosContinuationDetected)
      return MAIN_MICRO_TREND;

   return MAIN_MICRO_TREND;
}

inline bool Main_ApplyMicrostructureGate(const Settings &cfg,
                                         const Direction dir,
                                         const int archetype,
                                         const MainOFDS &ofds,
                                         double &microAlpha01,
                                         double &executionScore01,
                                         double &riskScore01,
                                         double &qualMult,
                                         double &riskMult,
                                         string &why)
{
   microAlpha01     = 0.0;
   executionScore01 = 0.0;
   riskScore01      = 1.0;
   qualMult         = 1.0;
   riskMult         = 1.0;
   why              = "";

   if(!ofds.ready)
   {
#ifdef STRAT_MAIN_REQUIRE_SCAN_MICRO
      why = "OFDS unavailable";
      riskScore01 = 1.0;
      return false;
#else
      why = "OFDS unavailable (neutral)";
      riskScore01 = 0.50;
      return true;
#endif
   }

   if(!ofds.trade_gate_pass)
   {
      why = "state trade gate reject";
      riskScore01 = 1.0;
      return false;
   }

   if(!ofds.direct_micro_available &&
      !ofds.proxy_micro_available &&
      _MainClamp01(ofds.observability01) < 0.35)
   {
      why = "state micro observability too low";
      riskScore01 = 0.85;
      return false;
   }

   int microMode = ofds.micro_mode;
   if(microMode <= 0)
   {
      if(ofds.direct_micro_available)
         microMode = INST_MICRO_MODE_DIRECT;
      else if(ofds.proxy_micro_available)
         microMode = INST_MICRO_MODE_PROXY;
      else
         microMode = INST_MICRO_MODE_STRUCTURE_ONLY;
   }

   const double obs01        = _MainClamp01(ofds.observability01 > 0.0 ? ofds.observability01
                                                                       : (ofds.direct_micro_available ? 1.00
                                                                                                      : (ofds.proxy_micro_available ? 0.70 : 0.45)));
   const double obsPenalty01 = _MainClamp01(ofds.observability_penalty01);
   const double truth01      = _MainClamp01(ofds.truth_tier01);
   const double vpin01       = (ofds.have_vpin ? _MainClamp01(ofds.vpin) : 0.50);
   const double resil01      = (ofds.have_resil ? _MainClamp01(ofds.resil) : 0.50);
   const double spread01     = _MainClamp01(MathMax(ofds.spread_shock, ofds.slippage_stress01));
   const double impact01     = _MainClamp01(MathMax(ofds.impact_lambda, ofds.impact_beta));
   const double tox01        = _MainClamp01(MathMax(ofds.toxicity, MathMax(spread01, impact01)));

   const double dirFlow      = (dir == DIR_BUY ? ofds.flow_dir : -ofds.flow_dir);
   const double dirOfi       = (dir == DIR_BUY ? _MainClamp11(ofds.ofi) : -_MainClamp11(ofds.ofi));
   const double dirObi       = (dir == DIR_BUY ? _MainClamp11(ofds.obi) : -_MainClamp11(ofds.obi));
   const double dirCvd       = (dir == DIR_BUY ? _MainClamp11(ofds.cvd) : -_MainClamp11(ofds.cvd));

   const double dirDelta01   = Main_DirSupport01(dir, ofds.delta_proxy_dir01);
   const double dirFoot01    = Main_DirSupport01(dir, ofds.footprint_dir01);
   const double dirProf01    = Main_DirSupport01(dir, ofds.profile_dir01);
   const double dirVsa01     = Main_DirSupport01(dir, ofds.vsa_dir01);
   const double vwapLoc01    = Main_DirSupport01(dir, ofds.vwap_location01);

   const double obsDirectMin = Main_CfgObsDirectMin(cfg);
   const double obsProxyMin  = Main_CfgObsProxyMin(cfg);
   const double obsStructMin = Main_CfgObsStructureMin(cfg);

   const double truthContMin = Main_CfgTruthContinuationMin(cfg);
   const double truthBrkMin  = Main_CfgTruthBreakoutMin(cfg);
   const double truthRevMin  = Main_CfgTruthReversalMin(cfg);

   if(microMode == INST_MICRO_MODE_DIRECT)
   {
      if(!ofds.have_flow)
      {
         why = "direct micro missing flow";
         return false;
      }

      microAlpha01 =
         _MainClamp01((0.35 * MathMax(0.0, dirOfi)) +
                      (0.25 * MathMax(0.0, dirObi)) +
                      (0.15 * MathMax(0.0, dirCvd)) +
                      (0.15 * _MainClamp01(ofds.vsa_absorption01)) +
                      (0.10 * resil01));

      executionScore01 =
         _MainClamp01((0.30 * MathMax(0.0, dirFlow)) +
                      (0.20 * resil01) +
                      (0.15 * (1.0 - spread01)) +
                      (0.15 * (1.0 - impact01)) +
                      (0.20 * obs01));

      riskScore01 =
         _MainClamp01((0.40 * vpin01) +
                      (0.20 * spread01) +
                      (0.15 * impact01) +
                      (0.15 * (1.0 - resil01)) +
                      (0.10 * ofds.slippage_stress01));

      if(obs01 < obsDirectMin)
      {
         why = "direct micro observability below threshold";
         return false;
      }

      if(archetype == MAIN_MICRO_BREAKOUT)
      {
         const bool pass =
            (truth01  >= truthBrkMin &&
             dirFlow  >= 0.12 &&
             dirOfi   >= 0.06 &&
             dirObi   >= 0.10 &&
             dirCvd   >= 0.05 &&
             vpin01   <= 0.58 &&
             resil01  >= 0.45 &&
             spread01 <= 0.55 &&
             impact01 <= 0.60);

         qualMult = (pass ? 1.06 : 0.90);
         riskMult = (pass ? 0.95 : 1.12);
         why = (pass ? "direct breakout micro ok" : "direct breakout micro reject");
         return pass;
      }

      if(archetype == MAIN_MICRO_TREND)
      {
         const bool pass =
            (truth01  >= truthContMin &&
             dirFlow  >= 0.10 &&
             dirOfi   >= 0.05 &&
             dirObi   >= 0.05 &&
             dirCvd   >= 0.03 &&
             vpin01   <= 0.68 &&
             resil01  >= 0.35 &&
             spread01 <= 0.70 &&
             impact01 <= 0.75);

         qualMult = (pass ? 1.04 : 0.92);
         riskMult = (pass ? 0.97 : 1.10);
         why = (pass ? "direct trend micro ok" : "direct trend micro reject");
         return pass;
      }

      const bool pass =
         (truth01  >= truthRevMin &&
          dirFlow  >= -0.12 &&
          dirOfi   >= -0.10 &&
          dirObi   >= -0.10 &&
          vpin01   <= 0.55 &&
          resil01  >= 0.30 &&
          spread01 <= 0.60 &&
          impact01 <= 0.65);

      qualMult = (pass ? 1.01 : 0.92);
      riskMult = (pass ? 1.00 : 1.10);
      why = (pass ? "direct meanrev micro ok" : "direct meanrev micro reject");
      return pass;
   }

   if(microMode == INST_MICRO_MODE_PROXY)
   {
      microAlpha01 =
         _MainClamp01((0.20 * dirDelta01) +
                      (0.15 * dirFoot01) +
                      (0.15 * dirProf01) +
                      (0.15 * dirVsa01) +
                      (0.10 * _MainClamp01(ofds.vsa_absorption01)) +
                      (0.10 * _MainClamp01(ofds.liquidity_reject01)) +
                      (0.10 * vwapLoc01) +
                      (0.05 * (1.0 - _MainClamp01(ofds.vwap_stretch01))));

      executionScore01 =
         _MainClamp01((0.30 * microAlpha01) +
                      (0.20 * resil01) +
                      (0.15 * (1.0 - spread01)) +
                      (0.15 * (1.0 - _MainClamp01(ofds.slippage_stress01))) +
                      (0.20 * obs01));

      riskScore01 =
         _MainClamp01((0.30 * spread01) +
                      (0.20 * _MainClamp01(ofds.slippage_stress01)) +
                      (0.20 * tox01) +
                      (0.15 * obsPenalty01) +
                      (0.15 * (1.0 - truth01)));

      if(obs01 < obsProxyMin)
      {
         why = "proxy micro observability below threshold";
         return false;
      }

      if(archetype == MAIN_MICRO_BREAKOUT)
      {
         const bool pass =
            (truth01   >= truthBrkMin &&
             dirDelta01 >= 0.60 &&
             dirFoot01  >= 0.58 &&
             dirProf01  >= 0.55 &&
             tox01      <= 0.55 &&
             spread01   <= 0.55);

         qualMult = (pass ? 1.03 : 0.90);
         riskMult = (pass ? 1.00 : 1.12);
         why = (pass ? "proxy breakout micro ok" : "proxy breakout micro reject");
         return pass;
      }

      if(archetype == MAIN_MICRO_TREND)
      {
         const bool pass =
            (truth01   >= truthContMin &&
             dirDelta01 >= 0.55 &&
             dirFoot01  >= 0.52 &&
             dirProf01  >= 0.50 &&
             tox01      <= 0.62 &&
             spread01   <= 0.68);

         qualMult = (pass ? 1.01 : 0.93);
         riskMult = (pass ? 1.03 : 1.10);
         why = (pass ? "proxy trend micro ok" : "proxy trend micro reject");
         return pass;
      }

      const bool pass =
         (truth01   >= truthRevMin &&
          (dirDelta01 >= 0.45 || dirFoot01 >= 0.45 || dirProf01 >= 0.45) &&
          tox01      <= 0.60 &&
          spread01   <= 0.65);

      qualMult = (pass ? 1.00 : 0.94);
      riskMult = (pass ? 1.04 : 1.10);
      why = (pass ? "proxy meanrev micro ok" : "proxy meanrev micro reject");
      return pass;
   }

   // structure-only mode: allow only reversal/location style logic
   microAlpha01 =
      _MainClamp01((0.40 * dirProf01) +
                   (0.25 * dirVsa01) +
                   (0.15 * _MainClamp01(ofds.liquidity_reject01)) +
                   (0.10 * _MainClamp01(ofds.wyckoff_turn01)) +
                   (0.10 * (1.0 - _MainClamp01(ofds.vwap_stretch01))));

   executionScore01 =
      _MainClamp01((0.40 * microAlpha01) +
                   (0.20 * resil01) +
                   (0.20 * obs01) +
                   (0.20 * (1.0 - spread01)));

   riskScore01 =
      _MainClamp01((0.30 * tox01) +
                   (0.20 * spread01) +
                   (0.15 * _MainClamp01(ofds.slippage_stress01)) +
                   (0.10 * impact01) +
                   (0.25 * obsPenalty01));

   if(archetype == MAIN_MICRO_BREAKOUT || archetype == MAIN_MICRO_TREND)
   {
      why = "structure-only blocked for continuation/breakout";
      qualMult = 0.85;
      riskMult = 1.15;
      return false;
   }

   const bool pass =
      (obs01      >= obsStructMin &&
       truth01    >= truthRevMin &&
       dirProf01  >= 0.45 &&
       (dirVsa01 >= 0.45 ||
        _MainClamp01(ofds.liquidity_reject01) >= 0.45 ||
        _MainClamp01(ofds.wyckoff_turn01) >= 0.50));

   qualMult = (pass ? 0.98 : 0.90);
   riskMult = (pass ? 1.05 : 1.12);
   why = (pass ? "structure-only meanrev micro ok" : "structure-only meanrev micro reject");
   return pass;
}

inline bool Main_IsSoftenableTesterMicroReject(const string why)
{
   string w = why;
   StringToLower(w);

   if(StringFind(w, "unavailable") >= 0)
      return true;
   if(StringFind(w, "missing flow") >= 0)
      return true;
   if(StringFind(w, "observability") >= 0)
      return true;
   if(StringFind(w, "structure-only") >= 0)
      return true;

   return false;
}

inline bool Main_IsSoftenableTesterTriggerReject(const string why)
{
   string w = why;
   StringToLower(w);

   if(StringFind(w, "noliqevent") >= 0)
      return true;

   if(StringFind(w, "poolonly") >= 0)
      return true;

   return false;
}

inline bool Main_IsSoftenableTesterScanReject(const string why)
{
   string w = why;
   StringToLower(w);

   if(StringFind(w, "scanalign:miss") >= 0)
      return true;

   return false;
}

namespace StratMainLogic
{
   bool HasVSAIncreaseAtLocationEx(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const Settings &cfg,
                                   const int poiKind,
                                   const double poiPrice,
                                   bool &dataOk);

   bool HasVSAIncreaseAtLocationEx(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const Settings &cfg,
                                   bool &dataOk);

   bool HasOrderFlowDeltaIncreaseEx(const string sym,
                                    const ENUM_TIMEFRAMES tf,
                                    const Direction dir,
                                    const Settings &cfg,
                                    bool &dataOk);

   bool HasBullBearCandlePattern(const string sym,
                                 const ENUM_TIMEFRAMES tf,
                                 const Direction dir,
                                 const Settings &cfg);

   bool HasBullBearChartPattern(const string sym,
                                const ENUM_TIMEFRAMES tf,
                                const Direction dir,
                                const Settings &cfg);

   bool TrendFilterPasses(const string sym,
                          const ENUM_TIMEFRAMES tf,
                          const Direction dir,
                          const Settings &cfg);

   bool AutoC_ChartCONFIRM_FromSnap(const string sym,
                                    const ENUM_TIMEFRAMES tf,
                                    const Direction dir,
                                    const Settings &cfg,
                                    const AutoSnapshot &s,
                                    double &q01,
                                    bool &dataOk);

   bool AutoC_FibOK_FromSnap(const string sym,
                             const ENUM_TIMEFRAMES tf,
                             const Direction dir,
                             const Settings &cfg,
                             const AutoSnapshot &s,
                             double &q01);

   bool AutoC_KeyLevelsOK_FromSnap(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const Settings &cfg,
                                   const AutoSnapshot &s,
                                   double &q01);

   bool AutoC_VolOK_FromSnap(const string sym,
                             const ENUM_TIMEFRAMES tf,
                             const Direction dir,
                             const Settings &cfg,
                             const AutoSnapshot &s,
                             double &q01);

   bool Extra_VolumeOrderFootprint(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const Settings &cfg);

   bool Extra_DOMOrderBookImbalance(const string sym,
                                    const ENUM_TIMEFRAMES tf,
                                    const Direction dir,
                                    const Settings &cfg,
                                    const ICT_Context &ctx);

   bool _ZoneHas(const Zone &z);

   double _ZoneDistancePoints(const string sym,
                              const Zone &z,
                              const double px);

   bool PickBestOBForDir(const ICT_Context &ctx,
                         const bool isBuy,
                         ICTOrderBlock &outOB,
                         string &outSrc);
}

inline bool Main_ResolveVSAPOIContext(const string sym,
                                      const ENUM_TIMEFRAMES tf,
                                      const Direction dir,
                                      const ICT_Context &ctx,
                                      int &poiKind,
                                      double &poiPrice)
{
   poiKind  = 0;   // 0 = none, 1 = institutional zone, 2 = order block
   poiPrice = 0.0;

   const bool isBuy = (dir == DIR_BUY);
   const double px  = iClose(sym, tf, 1);

   const Zone zH1 = (isBuy ? ctx.bestDemandZoneH1 : ctx.bestSupplyZoneH1);
   const Zone zH4 = (isBuy ? ctx.bestDemandZoneH4 : ctx.bestSupplyZoneH4);

   const bool haveZ1 = StratMainLogic::_ZoneHas(zH1);
   const bool haveZ4 = StratMainLogic::_ZoneHas(zH4);

   if(haveZ1 || haveZ4)
   {
      double d1 = 1000000000.0;
      double d4 = 1000000000.0;

      if(px > 0.0)
      {
         if(haveZ1)
            d1 = StratMainLogic::_ZoneDistancePoints(sym, zH1, px);

         if(haveZ4)
            d4 = StratMainLogic::_ZoneDistancePoints(sym, zH4, px);
      }

      poiKind = 1;

      if(!haveZ4 || (haveZ1 && d1 <= d4))
         poiPrice = 0.5 * (MathMin(zH1.lo, zH1.hi) + MathMax(zH1.lo, zH1.hi));
      else
         poiPrice = 0.5 * (MathMin(zH4.lo, zH4.hi) + MathMax(zH4.lo, zH4.hi));

      return (poiPrice > 0.0);
   }

   ICTOrderBlock obPick;
   ZeroMemory(obPick);
   string obSrc = "";

   if(StratMainLogic::PickBestOBForDir(ctx, isBuy, obPick, obSrc))
   {
      poiKind  = 2;
      poiPrice = 0.5 * (MathMin(obPick.low, obPick.high) + MathMax(obPick.low, obPick.high));
      return (poiPrice > 0.0);
   }

   return false;
}

inline bool Main_POIOrderFlowConfirmOK(const string sym,
                                       const ENUM_TIMEFRAMES tf,
                                       const Direction dir,
                                       const Settings &cfg,
                                       const ICT_Context &ctx,
                                       const MainOFDS &ofds,
                                       const bool atPOI,
                                       string &whyOut)
{
   whyOut = "";

   if(Main_CfgTesterLooseGate(cfg))
   {
      whyOut = "POI volume tester loose gate";
      return true;
   }

   if(!atPOI)
   {
      whyOut = "POI volume blocked: no POI";
      return false;
   }

   const bool bundleFeatureAvailable =
      (ofds.observability01 > 0.0 ||
       ofds.profile_conf01  > 0.0 ||
       ofds.footprint_conf01 > 0.0);

   const bool anyFeature =
      (cfg.cf_vsa_increase ||
       cfg.cf_orderflow_delta ||
       cfg.extra_volume_footprint ||
       cfg.extra_dom_imbalance ||
       bundleFeatureAvailable);

   if(!anyFeature)
   {
      whyOut = "POI volume bypassed (none enabled)";
      return true;
   }

   bool vsaDataOk   = false;
   bool deltaDataOk = false;

   int vsaPoiKind = 0;
   double vsaPoiPrice = 0.0;

   if(cfg.cf_vsa_increase)
      Main_ResolveVSAPOIContext(sym, tf, dir, ctx, vsaPoiKind, vsaPoiPrice);

   const bool vsaOk =
      (cfg.cf_vsa_increase
         ? StratMainLogic::HasVSAIncreaseAtLocationEx(sym, tf, dir, cfg, vsaPoiKind, vsaPoiPrice, vsaDataOk)
         : false);

   const bool deltaOk =
      (cfg.cf_orderflow_delta
         ? StratMainLogic::HasOrderFlowDeltaIncreaseEx(sym, tf, dir, cfg, deltaDataOk)
         : false);

   const bool fpOk =
      (cfg.extra_volume_footprint
         ? StratMainLogic::Extra_VolumeOrderFootprint(sym, tf, dir, cfg)
         : false);

   const bool domOk =
      (cfg.extra_dom_imbalance
         ? StratMainLogic::Extra_DOMOrderBookImbalance(sym, tf, dir, cfg, ctx)
         : false);

   const double dirDelta01 = Main_DirSupport01(dir, ofds.delta_proxy_dir01);
   const double dirFoot01  = Main_DirSupport01(dir, ofds.footprint_dir01);
   const double dirProf01  = Main_DirSupport01(dir, ofds.profile_dir01);
   const double dirVsa01   = Main_DirSupport01(dir, ofds.vsa_dir01);
   const double dirVWAP01  = Main_DirSupport01(dir, ofds.vwap_location01);

   const bool deltaProxyOK =
      (dirDelta01 >= 0.55);

   const bool profileOK =
      (dirProf01 >= 0.55 &&
       ofds.profile_conf01 >= 0.40);

   const bool vsaProxyOK =
      (dirVsa01 >= 0.50 ||
       _MainClamp01(ofds.vsa_absorption01) >= 0.50 ||
       _MainClamp01(ofds.vsa_replenishment01) >= 0.50);

   const bool vwapOK =
      (dirVWAP01 >= 0.50 &&
       _MainClamp01(ofds.vwap_stretch01) <= 0.80);

   const bool spreadCompressionOK =
      (_MainClamp01(ofds.spread_shock) <= 0.65 &&
       _MainClamp01(ofds.slippage_stress01) <= 0.65);

   const bool directionalOK =
      (vsaOk || deltaOk || fpOk || domOk || deltaProxyOK || profileOK || vsaProxyOK);

   const bool qualityOK =
      (vwapOK ||
       spreadCompressionOK ||
       _MainClamp01(ofds.liquidity_reject01) >= 0.45);

   const bool pass = (directionalOK && qualityOK);

   whyOut =
      "POI volume [" +
      (vsaOk             ? "VSA "           : "") +
      (deltaOk           ? "Delta "         : "") +
      (fpOk              ? "Footprint "     : "") +
      (domOk             ? "DOM "           : "") +
      (deltaProxyOK      ? "ProxyDelta "    : "") +
      (profileOK         ? "Profile "       : "") +
      (vsaProxyOK        ? "VSAProxy "      : "") +
      (vwapOK            ? "VWAP "          : "") +
      (spreadCompressionOK ? "SpreadTight " : "") +
      (!pass             ? "none"           : "") +
      "]";

   return pass;
}

inline bool Main_ConfirmationClusterOK(const string sym,
                                       const ENUM_TIMEFRAMES tf,
                                       const Direction dir,
                                       const Settings &cfg,
                                       const bool haveAuto,
                                       const AutoSnapshot &autoS,
                                       string &whyOut)
{
   whyOut = "";

   if(Main_CfgTesterLooseGate(cfg))
   {
      whyOut = "confirmation tester loose gate";
      return true;
   }

   bool needAny  = false;
   bool pattOK   = false;
   bool autoOK   = false;
   bool trendOK  = false;

   if(cfg.cf_candle_pattern)
   {
      needAny = true;
      pattOK = StratMainLogic::HasBullBearCandlePattern(sym, tf, dir, cfg);
   }

   if(cfg.cf_chart_pattern && !cfg.cf_autochartist_chart)
   {
      needAny = true;
      if(StratMainLogic::HasBullBearChartPattern(sym, tf, dir, cfg))
         pattOK = true;
   }

   if(cfg.cf_trend_regime)
   {
      needAny = true;
      trendOK = StratMainLogic::TrendFilterPasses(sym, tf, dir, cfg);
   }

   if(haveAuto)
   {
      double qTmp = 0.0;
      bool chartDataOk = haveAuto;

      if(cfg.cf_autochartist_chart)
      {
         needAny = true;
         if(StratMainLogic::AutoC_ChartCONFIRM_FromSnap(sym, tf, dir, cfg, autoS, qTmp, chartDataOk) && chartDataOk)
            autoOK = true;
      }

      if(cfg.cf_autochartist_fib)
      {
         needAny = true;
         if(StratMainLogic::AutoC_FibOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp))
            autoOK = true;
      }

      if(cfg.cf_autochartist_keylevels)
      {
         needAny = true;
         if(StratMainLogic::AutoC_KeyLevelsOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp))
            autoOK = true;
      }

      if(cfg.cf_autochartist_volatility)
      {
         needAny = true;
         if(StratMainLogic::AutoC_VolOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp))
            autoOK = true;
      }
   }

   if(!needAny)
   {
      whyOut = "confirmation bypassed (none enabled)";
      return true;
   }

   const bool pass = (pattOK || autoOK || trendOK);

   whyOut = "Confirm [" +
            (pattOK  ? "Pattern " : "") +
            (autoOK  ? "Auto "    : "") +
            (trendOK ? "Trend "   : "") +
            (!pass   ? "none"     : "") +
            "]";

   return pass;
}

// -------------------- ADAPTERS: map to your actual module APIs --------------------
// Change ONLY the right-hand side in each #ifdef block to match your real functions.
// Leave fallbacks in place so you can still compile if a module is temporarily missing.
// ---- Minimal, safe EMA reader for MQL5 (handle + CopyBuffer) ----
inline bool GetEMA(const string sym,
                   const ENUM_TIMEFRAMES tf,
                   const int period,
                   const int shift,        // closed-bar: pass 1
                   double &out_value)
{
  // Create a one-off handle (safe & simple). For perf, you can cache later.
  const int h = iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE);
  if(h == INVALID_HANDLE) return false;
  double buf[];
  const int got = CopyBuffer(h, /*buffer index*/ 0, /*start pos*/ shift, /*count*/ 1, buf);
  IndicatorRelease(h);                      // optional but tidy; remove if you cache

  if(got != 1 || buf[0] == EMPTY_VALUE) return false;
  out_value = buf[0];
  return true;
}

// ---- Structure / Supply-Demand / Order Blocks ----
inline bool ADP_SDOB_AlignedWithPivots(const string sym, ENUM_TIMEFRAMES htf1, ENUM_TIMEFRAMES htf2, bool isBuy)
{
  // If your module exposes a free function AlignedWithPivots(...)
  #ifdef HAVE_SDOB_ALIGNED
    return AlignedWithPivots(sym, htf1, htf2, isBuy);
  #else
     #ifdef HAVE_STRUCTURESDOB_CLASS
       return StructureSDOB::AlignedWithPivots(sym, htf1, htf2, isBuy);

     #else
       // Fallback to the free-function API (present in StructureSDOB.mqh)
       return SDOB_AlignedWithPivots(sym, htf1, htf2, isBuy);
     #endif
  #endif
}

inline bool ADP_SDOB_HasInstitutionalZoneNear(const string sym, ENUM_TIMEFRAMES tf, bool isBuy)
{
  #ifdef HAVE_SDOB_INSTZONE
    return HasInstitutionalZoneNear(sym, tf, isBuy);
  #else
     #ifdef HAVE_STRUCTURESDOB_CLASS
       return StructureSDOB::HasInstitutionalZoneNear(sym, tf, isBuy);
     #else
       // Fallback to the free-function API (present in StructureSDOB.mqh)
       return HasInstitutionalZoneNear(sym, tf, isBuy);
     #endif 
  #endif
}



inline bool ADP_SDOB_OrderBlockInProximity(const string sym, ENUM_TIMEFRAMES tf, bool isBuy)
{
  #ifdef HAVE_SDOB_OB_PROX
    return OrderBlockInProximity(sym, tf, isBuy);
  #else
     #ifdef HAVE_STRUCTURESDOB_CLASS
       return StructureSDOB::OrderBlockInProximity(sym, tf, isBuy);
     #else
       // Fallback to the free-function API (present in StructureSDOB.mqh)
       return OrderBlockInProximity(sym, tf, isBuy);
     #endif
  #endif
}

// ---- Liquidity cues ----
inline bool ADP_LIQ_PoolOrInducementNearby(const string sym, ENUM_TIMEFRAMES tf, bool isBuy)
{
  #ifdef HAVE_LIQUIDITY_POOL_NEARBY
    return PoolOrInducementNearby(sym, tf, isBuy);
  #else
     #ifdef HAVE_LIQUIDITYCUES_CLASS
       return LiquidityCues::PoolOrInducementNearby(sym, tf, isBuy);
     #else
       return false;
     #endif
  #endif
}

// ---- Order flow / delta proxy ----
inline double ADP_DeltaSlope(const string sym, ENUM_TIMEFRAMES tf, int lookback)
{
   // We need a SIGNED metric so BUY can be >0 and SELL can be <0.
   // DeltaX::SessionDeltaZ_ReliableOrProxy returns a signed Z-score of delta.
   double z  = 0.0;
   double raw= 0.0;
   double sd = 0.0;

   const int  lb            = (lookback > 0 ? lookback : 20);
   const bool use_atr_proxy = true;

   if(DeltaX::SessionDeltaZ_ReliableOrProxy(sym, tf, lb, /*closed_shift*/1, use_atr_proxy, z, raw, sd))
      return z;

   return 0.0;
}

inline bool ADP_DeltaSlopeZ(const string sym, const ENUM_TIMEFRAMES tf, const int lookback, double &out_z)
{
  out_z = 0.0;
  double raw = 0.0, sd = 0.0;

  // best-effort proxy enabled inside this call
  const bool ok = DeltaX::SessionDeltaZ_ReliableOrProxy(sym, tf, lookback, /*closed_shift*/1, true, out_z, raw, sd);
  return ok;
}

// ---- VSA ----
inline bool ADP_VSA_AggressionNearPOI(const string sym, const ENUM_TIMEFRAMES tf, const bool isBuy)
{
  #ifdef VSA_HAS_PHASE_API
    VSA::PhaseState ps;
    // lookback: keep modest; promote to config later if you want
    const int lb = 60;
    if(!VSA::GetPhaseState(sym, tf, lb, ps))
      return false;

    // Simple �pressure� test (tunable later):
    const double bias_th = 0.55;
    const double lead    = 0.05;

    if(isBuy)
      return (ps.buyBias  >= bias_th && ps.buyBias  > ps.sellBias + lead);
    else
      return (ps.sellBias >= bias_th && ps.sellBias > ps.buyBias  + lead);
  #else
    return false;
  #endif
}

// Orderflow delta threshold (configurable)
inline double ADP_OrderflowTh(const Settings &cfg)
{
  double th = 0.35; // safe default
  #ifdef CFG_HAS_ORDERFLOW_TH
    if(cfg.orderflow_th > 0.0) th = cfg.orderflow_th;
  #endif
  return th;
}

// ---- Patterns ----
inline bool ADP_PAT_HasCandlePattern(const string sym, ENUM_TIMEFRAMES tf, bool isBuy)
{
  #ifdef HAVE_PATTERNS_CANDLE
    return HasCandlePattern(sym, tf, isBuy);
  #else
     #ifdef HAVE_PATTERNS_CLASS
       return Patterns::HasCandlePattern(sym, tf, isBuy);
     #else
       Patt::PatternSet P;
       if(!Patt::ScanAll(sym, tf, /*lookback*/80, P))
          return false;
      
       const double conf = (isBuy ? Patt::BullishConfidence(P) : Patt::BearishConfidence(P));
       return (conf >= 0.55);
     #endif
  #endif
}

inline bool ADP_PAT_HasChartPattern(const string sym, ENUM_TIMEFRAMES tf, bool isBuy)
{
  #ifdef HAVE_PATTERNS_CHART
    return HasChartPattern(sym, tf, isBuy);
  #else
     #ifdef HAVE_PATTERNS_CLASS
       return Patterns::HasChartPattern(sym, tf, isBuy);
     #else
       Patt::PatternSet P;
       if(!Patt::ScanAll(sym, tf, /*lookback*/120, P))
          return false;
      
       const double conf = (isBuy ? Patt::BullishConfidence(P) : Patt::BearishConfidence(P));
       return (conf >= 0.55);
     #endif
  #endif
}

// ---- Indicators (your repo commonly uses Indi::..., not Indicators::...) ----
inline bool ADP_PriceVsSessionVWAP(const string sym, ENUM_TIMEFRAMES tf, bool isBuy)
{
  #ifdef HAVE_INDI_NAMESPACE
    return Indi::PriceVsSessionVWAP(sym, tf, isBuy);
  #else
     #ifdef HAVE_INDICATORS_CLASS
       return Indicators::PriceVsSessionVWAP(sym, tf, isBuy);
     #else
       // Minimal surrogate: price vs EMA(20) intraday as a rough guard
       double emaF = 0.0;
       if(!GetEMA(sym, tf, 20, /*shift*/1, emaF)) return false; // degrade to "not OK" if we can't read
       const double c = iClose(sym, tf, 1);
       return (isBuy ? (c >= emaF) : (c <= emaF));
     #endif
  #endif
}

inline bool ADP_EMAAboveBelowHTF(const string sym, ENUM_TIMEFRAMES htf, int fast, int slow, bool isBuy)
{
  #ifdef HAVE_INDI_NAMESPACE
    return Indi::EMAAboveBelowHTF(sym, htf, fast, slow, isBuy);
  #else
     #ifdef HAVE_INDICATORS_CLASS
       return Indicators::EMAAboveBelowHTF(sym, htf, fast, slow, isBuy);
     #else
       double eF = 0.0, eS = 0.0;
       if(!GetEMA(sym, htf, fast, /*shift*/1, eF)) return false;
       if(!GetEMA(sym, htf, slow, /*shift*/1, eS)) return false;
       return (isBuy ? (eF >= eS) : (eF <= eS));
     #endif
  #endif
}

inline bool PriceAboveBelowEMA20(const string sym, ENUM_TIMEFRAMES tf, bool isBuy, bool &out_ok)
{
  double ema20 = 0.0;
  if(!GetEMA(sym, tf, 20, 1, ema20)) return false;
  const double c = iClose(sym, tf, 1);
  out_ok = (isBuy ? (c >= ema20) : (c <= ema20));
  return true;
}

inline bool ADP_BetaCorr(const string sym, const string ref,
                         ENUM_TIMEFRAMES tf, const int lookback, const int shift,
                         double &beta, double &r)
{
  #ifdef HAVE_INDI_NAMESPACE
    return Indi::BetaCorr(sym, ref, tf, lookback, shift, beta, r);
  #else
     #ifdef HAVE_INDICATORS_CLASS
       return Indicators::BetaCorr(sym, ref, tf, lookback, shift, beta, r);
     #else
       beta=0.0; r=0.0; return false; // compile-safe fallback
     #endif
  #endif
}

// ---- Extras: StochRSI / MACD / ADX (compile-safe adapters) ----
inline bool ADP_StochRSI_K(const string sym,
                           const ENUM_TIMEFRAMES tf,
                           const int rsiPeriod,
                           const int kLen,
                           const int dLen,
                           const int shift,
                           double &out_k)
{
#ifdef HAVE_INDI_NAMESPACE
   out_k = Indi::StochRSI_K(sym, tf, rsiPeriod, kLen, dLen, shift);
   return (out_k != EMPTY_VALUE);
#else
   out_k = 0.0;
   return false;
#endif
}

inline bool ADP_MACD(const string sym,
                     const ENUM_TIMEFRAMES tf,
                     const int fast,
                     const int slow,
                     const int signal,
                     const int shift,
                     double &out_macd,
                     double &out_sig,
                     double &out_hist)
{
#ifdef HAVE_INDI_NAMESPACE
   return Indi::MACD(sym, tf, fast, slow, signal, shift, out_macd, out_sig, out_hist);
#else
   out_macd = 0.0; out_sig = 0.0; out_hist = 0.0;
   return false;
#endif
}

inline bool ADP_ADX_StrongAligned(const string sym,
                                 const ENUM_TIMEFRAMES tf,
                                 const int period,
                                 const int shift,
                                 const double minTrend,
                                 const bool isBuy,
                                 const bool requireDIAlign)
{
#ifdef HAVE_INDI_NAMESPACE
   return Indi::ADX_StrongAligned(sym, tf, period, shift, minTrend, isBuy, requireDIAlign);
#else
   return false;
#endif
}

// ---------- Bit indices for confluence mask ----------
#define C_MKSTR     0
#define C_ZONE      1
#define C_OFLOW     2
#define C_LIQ       3
#define C_OB        4
#define C_VSA       5
#define C_CANDLE    6
#define C_CHART     7
#define C_TREND     8
#define C_STOCHRSI  9
#define C_MACD      10
#define C_ADXREG    11
#define C_CORR      12
#define C_NEWS      13
#define C_VOLFOOT   14
#define C_AMD_H1     15
#define C_AMD_H4     16
#define C_SB_TZ      17
#define C_PO3_H1_ACCUM 18
#define C_PO3_H1_MANIP 19
#define C_PO3_H4_ACCUM 20
#define C_PO3_H4_MANIP 21
#define C_WY_SPRING    22
#define C_WY_UTAD      23
#define C_ZONE_H1      24
#define C_ZONE_H4      25
#define C_ZONE_STACK   26
#define C_LIQ_HTF      27
#define C_CTXPREF      28
#define C_WY_INTRA     29
#define C_DOM         30
#define C_PHASE_BIAS  31
#define C_AUTO_CHART       32
#define C_AUTO_FIB         33
#define C_AUTO_KEYLEVELS   34
#define C_AUTO_VOL         35
// Scanner-derived liquidity pool state tags (requires Scan::IndiSnapshot pool fields)
#define C_LIQ_POOL_APPROACH 36
#define C_LIQ_POOL_TOUCHED  37

// Scanner-derived Wyckoff manipulation hint (Spring / UTAD recently detected)
#define C_WY_SCAN_MANIP     38

// -----------------------------------------------------------------------
// C.A.N.D.L.E. FRAMEWORK EXTENSION CATEGORIES
// -----------------------------------------------------------------------
// C_CANDLE_NARR: multi-candle body/wick/close exhaustion cluster (N element).
// Sits logically alongside C_CANDLE (6) in the confirmation tier.
#ifndef C_CANDLE_NARR
   #define C_CANDLE_NARR     39
#endif

// C_AXIS_TIME_MEM: time-at-level memory score for OB/FVG/OTE zones (A element).
// Sits logically alongside C_OB (4) in the location tier.
#ifndef C_AXIS_TIME_MEM
   #define C_AXIS_TIME_MEM   40
#endif

#define C_AUTO_KEY C_AUTO_KEYLEVELS
// ---------- Veto reason bitmask (Main strategy) ----------
#define VETO_NONE          0
#define VETO_NO_SWEEP      ((uint)1 << 0)
#define VETO_NO_STRUCT     ((uint)1 << 1)
#define VETO_NO_LOCATION   ((uint)1 << 2)
#define VETO_BAD_SESSION   ((uint)1 << 3)
#define VETO_SB            ((uint)1 << 4)
#define VETO_PO3           ((uint)1 << 5)
#define VETO_NEWS          ((uint)1 << 6)
#define VETO_ICT_SCORE     ((uint)1 << 7)
#define VETO_FINAL_QUALITY ((uint)1 << 8)
#define VETO_CLASSICAL_REQ ((uint)1 << 9)
#define VETO_MICROSTRUCTURE ((uint)1 << 10)

// ============================================================================
// Debug helpers (strategy diagnostics) � compile-safe, production quiet
// ============================================================================
#ifndef UNUSED
   #define UNUSED(x) ((x))
#endif

// Compile-safe debug flag getter:
// - Prefer cfg.debug_strategies if present
// - Fallback to cfg.debug if present
inline bool CfgDebugStrategies(const Settings &cfg)
{
#ifdef CFG_HAS_DEBUG_STRATEGIES
   return (cfg.debug_strategies);
#endif

#ifdef CFG_HAS_DEBUG
   return (cfg.debug);
#endif

   return false;
}

enum { DBG_ONCE_CACHE_SLOTS = 32 };

// Throttle: print once per CLOSED bar (shift=1) per (symbol|tf|tag).
inline bool _DbgOncePerClosedBar(const string &key, const datetime closedBarTime)
{
   // Small fixed cache (safe in a header; static inside inline func)
   static string   keys[DBG_ONCE_CACHE_SLOTS];
   static datetime times[DBG_ONCE_CACHE_SLOTS];

   int idx = -1;

   // Find existing key
   for(int i=0;i<DBG_ONCE_CACHE_SLOTS;i++)
   {
      if(keys[i] == key)
      {
         idx = i;
         break;
      }
   }

   // Allocate a new slot
   if(idx < 0)
   {
      for(int i=0;i<DBG_ONCE_CACHE_SLOTS;i++)
      {
         if(keys[i] == "")
         {
            idx = i;
            keys[i] = key;
            break;
         }
      }
      // If cache full, overwrite slot 0 (simple + deterministic)
      if(idx < 0)
      {
         idx = 0;
         keys[0] = key;
      }
   }

   if(times[idx] == closedBarTime)
      return false;

   times[idx] = closedBarTime;
   return true;
}

// Single entry point for strategy diagnostics.
// - Prints only when debugStrategies is enabled.
// - Optionally throttles to once per CLOSED bar.
inline void DbgStrat(const Settings &cfg,
                     const string   sym,
                     const ENUM_TIMEFRAMES tf,
                     const string   tag,
                     const string   msg,
                     const bool     oncePerClosedBar = true)
{
   if(!CfgDebugStrategies(cfg))
      return;

   if(oncePerClosedBar)
   {
      const datetime bt = iTime(sym, tf, 1);  // closed bar
      if(bt > 0)
      {
         const string key = sym + "|" + IntegerToString((int)tf) + "|" + tag;
         if(!_DbgOncePerClosedBar(key, bt))
            return;
      }
   }

   Print(msg);
}

inline void Main_DbgRawScoreWrite(const Settings &cfg,
                                  const string   sym,
                                  const ENUM_TIMEFRAMES tf,
                                  const Direction dir,
                                  const double classicalScore,
                                  const double ictScore,
                                  const double finalQuality,
                                  const bool testerDegradedMode)
{
   if(!CfgDebugStrategies(cfg))
      return;

   const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
   const datetime closedBar = iTime(sym, tf, 1);

   const string msg =
      StringFormat("[MainICTWrite] sym=%s tf=%d dir=%s closed=%s cls=%.2f ict=%.2f final=%.2f testerDegraded=%d",
                   sym,
                   (int)tf,
                   dirStr,
                   (closedBar > 0 ? TimeToString(closedBar, TIME_DATE|TIME_MINUTES) : "-"),
                   classicalScore,
                   ictScore,
                   finalQuality,
                   (testerDegradedMode ? 1 : 0));

   DbgStrat(cfg, sym, tf, "ICTWrite", msg, true);
}

inline double Main_NormalizeFinalStrategyScore(const double score01,
                                               const bool eligible)
{
   double v = _MainClamp01(score01);

   if(eligible && v <= 0.0)
      v = 0.01;

   return v;
}

inline void Main_DbgScoreStages(const Settings &cfg,
                                const string   sym,
                                const ENUM_TIMEFRAMES tf,
                                const Direction dir,
                                const double checklistScore,
                                const double finalQuality,
                                const double finalQualityAdj,
                                const double alphaScore01,
                                const double finalScore,
                                const double executionScore01,
                                const double riskScore01,
                                const bool eligible)
{
   if(!CfgDebugStrategies(cfg))
      return;

   const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");

   const string msg =
      StringFormat("[MainScoreStages] sym=%s tf=%d dir=%s checklist=%.6f finalQ=%.6f finalAdj=%.6f alpha=%.6f final=%.6f exec=%.6f risk=%.6f eligible=%d",
                   sym,
                   (int)tf,
                   dirStr,
                   _MainClamp01(checklistScore),
                   _MainClamp01(finalQuality),
                   _MainClamp01(finalQualityAdj),
                   _MainClamp01(alphaScore01),
                   _MainClamp01(finalScore),
                   _MainClamp01(executionScore01),
                   _MainClamp01(riskScore01),
                   (eligible ? 1 : 0));

   DbgStrat(cfg, sym, tf, "MainScoreStages", msg, false);
}

// Trace flag (independent from debug)
inline bool CfgTraceFlow(const Settings &cfg)
{
#ifdef CFG_HAS_TRACE_FLOW
   return cfg.trace_flow;
#endif
   return (ROUTER_TRACE_FLOW != 0);
}

// Trace printer: once per CLOSED bar per (sym|tf|tag), even if debug is off
inline void TraceStrat(const Settings &cfg,
                       const string   sym,
                       const ENUM_TIMEFRAMES tf,
                       const string   tag,
                       const string   msg)
{
   if(!CfgTraceFlow(cfg))
      return;

   const datetime bt = iTime(sym, tf, 1);
   if(bt > 0)
   {
      const string key = sym + "|" + IntegerToString((int)tf) + "|TRACE|" + tag;
      if(!_DbgOncePerClosedBar(key, bt))
         return;
   }

   Print(msg);
}

// Small helper for building fail-reason chains (no allocations beyond string growth).
inline void _DbgAppendFail(string &fail, const string item)
{
   if(item == "")
      return;
   if(fail != "")
      fail += ",";
   fail += item;
}

inline string StratVetoMaskToString(const ulong mask)
{
   string s = "";
   if(mask == 0) return "NONE";
   if((mask & VETO_NO_SWEEP)      != 0) _DbgAppendFail(s, "NO_SWEEP");
   if((mask & VETO_NO_STRUCT)     != 0) _DbgAppendFail(s, "NO_STRUCT");
   if((mask & VETO_NO_LOCATION)   != 0) _DbgAppendFail(s, "NO_LOC");
   if((mask & VETO_BAD_SESSION)   != 0) _DbgAppendFail(s, "BAD_SESSION");
   if((mask & VETO_SB)            != 0) _DbgAppendFail(s, "SB");
   if((mask & VETO_PO3)           != 0) _DbgAppendFail(s, "PO3");
   if((mask & VETO_NEWS)          != 0) _DbgAppendFail(s, "NEWS");
   if((mask & VETO_ICT_SCORE)     != 0) _DbgAppendFail(s, "ICT");
   if((mask & VETO_FINAL_QUALITY) != 0) _DbgAppendFail(s, "FINALQ");
   if((mask & VETO_CLASSICAL_REQ) != 0) _DbgAppendFail(s, "CLASSICAL_REQ");
   if((mask & VETO_MICROSTRUCTURE) != 0) _DbgAppendFail(s, "MICRO");
   return s;
}

inline void Main_AppendDiagTagWithDetail(string &dst,
                                         const string tag,
                                         const string detail)
{
   string item = tag;
   if(detail != "")
      item += "(" + detail + ")";
   _DbgAppendFail(dst, item);
}

inline void Main_ApplyTesterDegradedPenalty(const string tag,
                                            const string detail,
                                            const double scoreMult,
                                            const double riskMult,
                                            string &diagTags,
                                            double &scoreMultAcc,
                                            double &riskMultAcc)
{
   Main_AppendDiagTagWithDetail(diagTags, tag, detail);

   if(scoreMult > 0.0)
      scoreMultAcc *= _MainClamp01(scoreMult);

   if(riskMult > 0.0)
      riskMultAcc *= riskMult;
}

// --- Small compatibility helpers (avoid hard deps) ---
inline void BD_ClearCompat(ConfluenceBreakdown &bd)
{
#ifdef HAVE_BD_CLEAR
   Confluence::BD_Clear(bd);
#else
   ZeroMemory(bd);
#endif
 Main_SetBreakdownHeadScores(bd, 0.0, 0.0, 0.0);
}

inline double Clamp01Compat(const double v)
{
   if(v <= 0.0) return 0.0;
   if(v >= 1.0) return 1.0;
   return v;
}

#ifdef CFG_HAS_CANDIDATE_PIPELINE
inline void CandidateResetCompat(Candidate &c)
{
   #ifdef CA_CANDIDATE_RESET_GUARD
      CandidateReset(c);
   #else
      c.Reset();
   #endif
}
#endif

// ---------- Confluence result bundle ----------
struct ConfluenceResult
{
  int      metCount;
  double   score;
  ulong     mask;
  string   summary;
  bool     passesCount;
  bool     passesScore;
  bool     eligible;
};

// ============================================================================
// Router-friendly entry intent for Main strategy (no execution here)
// ============================================================================
struct MainEntryPlan
{
   bool            valid;
   string          sym;
   Direction       dir;
   ENUM_ORDER_TYPE order_type;        // market or pending hint
   double          preferred_entry;   // mitigation / mid / pocket
   double          invalidation;      // SL anchor (router derives actual SL)
   double          target1;           // optional TP anchor (router derives TP)
   datetime        expiry_time;       // pending-order expiry (0 = none)
   bool            has_expiry;        // true when expiry_time is meaningful
   double          score;
   double          score_raw;
   double          risk_mult;
   string          reason;
};

#ifdef CFG_HAS_CANDIDATE_PIPELINE
inline void Main_CandidateInit(Candidate &cand,
                               const string sym,
                               const Direction dir)
{
   CandidateResetCompat(cand);

   cand.SetId((StrategyID)STRAT_MAIN_ID);
   cand.name         = STRAT_MAIN_NAME;
   cand.dir          = dir;
   cand.score        = 0.0;
   cand.blended      = 0.0;
   cand.risk_mult    = 0.0;

   cand.ss.id        = (StrategyID)STRAT_MAIN_ID;
   cand.ss.direction = dir;
   cand.ss.eligible  = false;
   cand.ss.score     = 0.0;
   cand.ss.score_raw = 0.0;
   cand.ss.risk_mult = 0.0;
   cand.ss.reason    = "";

   Main_ResetHeadScores(cand.ss);
   BD_ClearCompat(cand.bd);

   cand.plan.sym     = sym;
   cand.plan.dir     = dir;
   cand.plan.price   = 0.0;
   cand.plan.sl      = 0.0;
   cand.plan.tp      = 0.0;

   #ifdef CANDIDATE_HAS_PLAN_EXPIRY_TIME
      cand.plan.expiry_time = 0;
      cand.plan.has_expiry  = false;
   #endif
}

inline void Main_CandidateApplyPayload(Candidate                  &cand,
                                       const StratScore           &ss,
                                       const ConfluenceBreakdown  &bd,
                                       const MainEntryPlan        &plan)
{
   cand.ss        = ss;
   cand.bd        = bd;
   cand.score     = ss.score;
   cand.blended   = ss.score_raw;
   cand.risk_mult = (ss.risk_mult > 0.0 ? ss.risk_mult : 1.0);

   cand.plan.sym   = plan.sym;
   cand.plan.dir   = plan.dir;
   cand.plan.price = plan.preferred_entry;
   cand.plan.sl    = plan.invalidation;
   cand.plan.tp    = plan.target1;

   #ifdef CANDIDATE_HAS_PLAN_EXPIRY_TIME
      cand.plan.expiry_time = plan.expiry_time;
      cand.plan.has_expiry  = plan.has_expiry;
   #endif

   #ifdef CANDIDATE_HAS_REASON
      cand.reason = ss.reason;
   #endif
}

inline bool Main_SelectPreferredCandidate(const bool      okBuy,
                                          const Candidate &candBuy,
                                          const bool      okSell,
                                          const Candidate &candSell,
                                          Candidate       &bestCand,
                                          string          &outWhy)
{
   const bool pickBuy = (candBuy.score >= candSell.score);

   if(okBuy && (!okSell || pickBuy))
   {
      bestCand = candBuy;
      outWhy   = "best candidate = BUY";
      return true;
   }

   if(okSell)
   {
      bestCand = candSell;
      outWhy   = "best candidate = SELL";
      return true;
   }

   if(pickBuy)
      bestCand = candBuy;
   else
      bestCand = candSell;

   outWhy = (bestCand.ss.reason != "" ? bestCand.ss.reason : "best diagnostic candidate");
   return false;
}
#endif

namespace MainTrading
{
  // Evaluate once per tick/symbol; derived strategies consume the same snapshot
  inline bool BuildConfluence(const Settings &cfg,
                              const string sym,
                              const ENUM_TIMEFRAMES tf_entry,
                              StratScore &ss,
                              ConfluenceBreakdown &bd)
   {
      ZeroMemory(ss);
      BD_ClearCompat(bd);
   
      ICT_Context ctx;
      Main_LoadCanonicalICTContext(sym, cfg, ctx);
   
      StratScore ssBuy;  ZeroMemory(ssBuy);
      StratScore ssSell; ZeroMemory(ssSell);
   
      ConfluenceBreakdown bdBuy;  BD_ClearCompat(bdBuy);
      ConfluenceBreakdown bdSell; BD_ClearCompat(bdSell);
   
      const bool okBuy  = StratMainLogic::Evaluate(sym, DIR_BUY,  cfg, ctx, ssBuy,  bdBuy);
      const bool okSell = StratMainLogic::Evaluate(sym, DIR_SELL, cfg, ctx, ssSell, bdSell);
   
      const bool pickBuy = (ssBuy.score >= ssSell.score);
   
      if(pickBuy)
      {
         ss = ssBuy;
         bd = bdBuy;
      }
      else
      {
         ss = ssSell;
         bd = bdSell;
      }
   
      if(ss.risk_mult <= 0.0)
         ss.risk_mult = 1.0;
   
      return (okBuy || okSell);
   }
  
  class StrategySlot : public CObject
   {
   private:
     StrategyBase *m_ptr;
   
   public:
     StrategySlot(){ m_ptr=NULL; }
     StrategySlot(StrategyBase *p){ m_ptr=p; }
   
     StrategyBase* Ptr() const { return m_ptr; }
   };

  #ifdef DEV_ENABLE_STRAT_REGISTRY_RUNNER
  // Example driver: call this from Integration/Router after warmup checks
  inline void RunAllStrategies(const Settings &cfg,
                               const string sym,
                               const ENUM_TIMEFRAMES tf_entry,
                               CArrayObj &registry /* of StrategySlot (wraps StrategyBase*) */)
  {
    StratScore ss; ConfluenceBreakdown bd;
    BuildConfluence(cfg, sym, tf_entry, ss, bd);
    // no early return here

    // Optional: grade-based routing (A/B/C)
    char grade='-'; double risk_mult=1.0; string reason="";
    // We use a temporary base wrapper to run the common pre-entry check once.
    // If you already have a shared context, feel free to adapt.
    {
      // Make a lightweight temp base with cfg/sym/tf to reuse BasePreEntryGate:
      class _TempBase : public StrategyBase
      {
      public:
         _TempBase(const Settings &c, const string s, const ENUM_TIMEFRAMES t)
         {
            m_cfg    = c;
            m_symbol = s;
            m_tf     = t;
         }
      
         // Required by StrategyBase (pure virtual)
         virtual bool ComputeDirectional(const Direction dir,
                                         const Settings  &cfg,
                                         StratScore      &out,
                                         ConfluenceBreakdown &bd) override
         {
            // We don't "trade" here; we just provide something sane if it gets called.
            BD_ClearCompat(bd);
            out.id         = STRAT_CORE_BASE;
            out.score      = 1.0;
            out.score_raw  = 1.0;
            out.eligible   = true;
            out.risk_mult  = 1.0;
            return true;
         }
      
         virtual ~_TempBase() {}
      } base(cfg, sym, tf_entry);

      if(!base.CanAttemptEntry(bd, ss, grade, risk_mult, reason))
      {
        // Log/telemetry: blocked by grade/news/etc.
        // Telemetry::Note(sym, "MainGate", reason);
        return;
      }
    }

    // Tiering example: limit which sets run by grade (optional)
    for(int i=0;i<registry.Total();++i)
    {
      CObject *obj = registry.At(i);
      StrategySlot *slot = (StrategySlot*)obj;
      if(slot==NULL) continue;
      
      StrategyBase *strat = slot.Ptr();
      if(strat==NULL) continue;

      // Example: only allow riskier playbooks on grade A; conservative on B/C
      const bool allow_this =
        (grade=='A') ? true :
        (grade=='B') ? /* skip ultra-aggressive types? */ true :
        (grade=='C') ? /* only ultra-conservative */ true : false;

      if(!allow_this) continue;

      char g='-'; double rm=1.0; string why="";
      if(!strat.CanAttemptEntry(bd, ss, g, rm, why))
       continue;

      // Merge main risk_mult with strategy-level adjustments, if any
      double use_risk = risk_mult * rm;
      if(use_risk < 0.0) use_risk = 0.0;
      if(use_risk > 3.0) use_risk = 3.0;

      // Your existing per-strategy entry call goes here; pass grade/risk if needed
      // strat.TryEnter(use_risk, g, bd, ss);
    }
  }
  #endif // DEV_ENABLE_STRAT_REGISTRY_RUNNER
} // namespace MainTrading

namespace StratMainLogic
{

// ------------------------------------------------------------------------
// Entry anchor selection for router (no SL/TP calc here)
// Priority: OB 50% mitigation, then FVG mid, then OTE pocket
// ------------------------------------------------------------------------
inline double _Mid(const double a, const double b)
{
   return 0.5 * (a + b);
}

// --- MTF OB/FVG selection helpers (Active -> M15 -> H1 -> H4) -----------------

inline bool _BandContains(const double px, const double a, const double b)
{
   const double lo = MathMin(a, b);
   const double hi = MathMax(a, b);
   return (px >= lo && px <= hi);
}

inline bool PickBestOBForDir(const ICT_Context &ctx, const bool isBuy, ICTOrderBlock &outOB, string &outSrc)
{
   ZeroMemory(outOB);
   outSrc = "";

   // Prefer active slot first (entry-TF oriented)
   if((ctx.activeOrderBlock.high != 0.0 || ctx.activeOrderBlock.low != 0.0) &&
      (isBuy ? ctx.activeOrderBlock.isBullish : !ctx.activeOrderBlock.isBullish))
   {
      outOB  = ctx.activeOrderBlock;
      outSrc = "OB50";
      return true;
   }

#ifdef CA_HAS_MULTITF_ZONES
   if((ctx.obM15.high != 0.0 || ctx.obM15.low != 0.0) &&
      (isBuy ? ctx.obM15.isBullish : !ctx.obM15.isBullish))
   {
      outOB  = ctx.obM15;
      outSrc = "OB50_M15";
      return true;
   }
   if((ctx.obH1.high != 0.0 || ctx.obH1.low != 0.0) &&
      (isBuy ? ctx.obH1.isBullish : !ctx.obH1.isBullish))
   {
      outOB  = ctx.obH1;
      outSrc = "OB50_H1";
      return true;
   }
   if((ctx.obH4.high != 0.0 || ctx.obH4.low != 0.0) &&
      (isBuy ? ctx.obH4.isBullish : !ctx.obH4.isBullish))
   {
      outOB  = ctx.obH4;
      outSrc = "OB50_H4";
      return true;
   }
#endif

   return false;
}

inline bool PickBestFVGForDir(const ICT_Context &ctx, const bool isBuy, ICTFVG &outFVG, string &outSrc)
{
   ZeroMemory(outFVG);
   outSrc = "";

   // Prefer active slot first (entry-TF oriented)
   if((ctx.activeFVG.high != 0.0 || ctx.activeFVG.low != 0.0) &&
      (isBuy ? ctx.activeFVG.isBullish : !ctx.activeFVG.isBullish))
   {
      outFVG = ctx.activeFVG;
      outSrc = "FVGmid";
      return true;
   }

#ifdef CA_HAS_MULTITF_ZONES
   if((ctx.fvgM15.high != 0.0 || ctx.fvgM15.low != 0.0) &&
      (isBuy ? ctx.fvgM15.isBullish : !ctx.fvgM15.isBullish))
   {
      outFVG = ctx.fvgM15;
      outSrc = "FVGmid_M15";
      return true;
   }
   if((ctx.fvgH1.high != 0.0 || ctx.fvgH1.low != 0.0) &&
      (isBuy ? ctx.fvgH1.isBullish : !ctx.fvgH1.isBullish))
   {
      outFVG = ctx.fvgH1;
      outSrc = "FVGmid_H1";
      return true;
   }
   if((ctx.fvgH4.high != 0.0 || ctx.fvgH4.low != 0.0) &&
      (isBuy ? ctx.fvgH4.isBullish : !ctx.fvgH4.isBullish))
   {
      outFVG = ctx.fvgH4;
      outSrc = "FVGmid_H4";
      return true;
   }
#endif

   return false;
}

inline bool Main_SelectAnchors(const ICT_Context &ctx,
                              const bool         isBuy,
                              double            &outEntry,
                              double            &outInval,
                              string            &outSrc)
{
   outEntry = 0.0;
   outInval = 0.0;
   outSrc   = "";

   // 1) Order Block (50% mitigation) � prefer Active, fallback M15/H1/H4
   ICTOrderBlock obPick;
   string obSrc = "";
   if(PickBestOBForDir(ctx, isBuy, obPick, obSrc))
   {
      const double lo = MathMin(obPick.low,  obPick.high);
      const double hi = MathMax(obPick.low,  obPick.high);
      outEntry = _Mid(lo, hi);
      outInval = (isBuy ? lo : hi);
      outSrc   = obSrc;
      return true;
   }

   // 1b) Order Block fallback (M15/H1/H4) - requires multi-TF context fields
   #ifdef ICTCTX_HAS_MULTITF_OBFVG
   {
      if(ctx.obM15.high != 0.0 || ctx.obM15.low != 0.0)
      {
         const bool ok = (isBuy ? ctx.obM15.isBullish : !ctx.obM15.isBullish);
         if(ok)
         {
            const double lo = MathMin(ctx.obM15.low,  ctx.obM15.high);
            const double hi = MathMax(ctx.obM15.low,  ctx.obM15.high);
            outEntry = _Mid(lo, hi);
            outInval = (isBuy ? lo : hi);
            outSrc   = "OB50_M15";
            return true;
         }
      }

      if(ctx.obH1.high != 0.0 || ctx.obH1.low != 0.0)
      {
         const bool ok = (isBuy ? ctx.obH1.isBullish : !ctx.obH1.isBullish);
         if(ok)
         {
            const double lo = MathMin(ctx.obH1.low,  ctx.obH1.high);
            const double hi = MathMax(ctx.obH1.low,  ctx.obH1.high);
            outEntry = _Mid(lo, hi);
            outInval = (isBuy ? lo : hi);
            outSrc   = "OB50_H1";
            return true;
         }
      }

      if(ctx.obH4.high != 0.0 || ctx.obH4.low != 0.0)
      {
         const bool ok = (isBuy ? ctx.obH4.isBullish : !ctx.obH4.isBullish);
         if(ok)
         {
            const double lo = MathMin(ctx.obH4.low,  ctx.obH4.high);
            const double hi = MathMax(ctx.obH4.low,  ctx.obH4.high);
            outEntry = _Mid(lo, hi);
            outInval = (isBuy ? lo : hi);
            outSrc   = "OB50_H4";
            return true;
         }
      }
   }
   #endif

   // 2) FVG mid � prefer Active, fallback M15/H1/H4
   ICTFVG fvgPick;
   string fvgSrc = "";
   if(PickBestFVGForDir(ctx, isBuy, fvgPick, fvgSrc))
   {
      const double lo = MathMin(fvgPick.low,  fvgPick.high);
      const double hi = MathMax(fvgPick.low,  fvgPick.high);
      outEntry = _Mid(lo, hi);
      outInval = (isBuy ? lo : hi);
      outSrc   = fvgSrc;
      return true;
   }

   // 2b) FVG fallback (M15/H1/H4) - requires multi-TF context fields
   #ifdef ICTCTX_HAS_MULTITF_OBFVG
   {
      if(ctx.fvgM15.high != 0.0 || ctx.fvgM15.low != 0.0)
      {
         const bool ok = (isBuy ? ctx.fvgM15.isBullish : !ctx.fvgM15.isBullish);
         if(ok)
         {
            const double lo = MathMin(ctx.fvgM15.low,  ctx.fvgM15.high);
            const double hi = MathMax(ctx.fvgM15.low,  ctx.fvgM15.high);
            outEntry = _Mid(lo, hi);
            outInval = (isBuy ? lo : hi);
            outSrc   = "FVG_M15";
            return true;
         }
      }

      if(ctx.fvgH1.high != 0.0 || ctx.fvgH1.low != 0.0)
      {
         const bool ok = (isBuy ? ctx.fvgH1.isBullish : !ctx.fvgH1.isBullish);
         if(ok)
         {
            const double lo = MathMin(ctx.fvgH1.low,  ctx.fvgH1.high);
            const double hi = MathMax(ctx.fvgH1.low,  ctx.fvgH1.high);
            outEntry = _Mid(lo, hi);
            outInval = (isBuy ? lo : hi);
            outSrc   = "FVG_H1";
            return true;
         }
      }

      if(ctx.fvgH4.high != 0.0 || ctx.fvgH4.low != 0.0)
      {
         const bool ok = (isBuy ? ctx.fvgH4.isBullish : !ctx.fvgH4.isBullish);
         if(ok)
         {
            const double lo = MathMin(ctx.fvgH4.low,  ctx.fvgH4.high);
            const double hi = MathMax(ctx.fvgH4.low,  ctx.fvgH4.high);
            outEntry = _Mid(lo, hi);
            outInval = (isBuy ? lo : hi);
            outSrc   = "FVG_H4";
            return true;
         }
      }
   }
   #endif

   // 3) OTE pocket (use zone midpoint as neutral default)
   const double oteLo = MathMin(ctx.oteZone.lower, ctx.oteZone.upper);
   const double oteHi = MathMax(ctx.oteZone.lower, ctx.oteZone.upper);
   if(oteLo != 0.0 || oteHi != 0.0)
   {
      const bool oteDirOK = (isBuy ? ctx.oteZone.isDiscountForBuys : !ctx.oteZone.isDiscountForBuys);
      if(oteDirOK)
      {
         outEntry = _Mid(oteLo, oteHi);
         outInval = (isBuy ? oteLo : oteHi);
         outSrc   = "OTEmid";
         return true;
      }
   }

   return false;
}

inline ENUM_ORDER_TYPE Main_ChooseOrderType(const bool   isBuy,
                                           const double pxNow,
                                           const double entryPx,
                                           const double nearPts)
{
   // If entry is close enough to current price, hint market.
   if(MathAbs(pxNow - entryPx) <= nearPts)
      return (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   // Otherwise hint a pullback pending order by default.
   if(isBuy)
      return (entryPx < pxNow ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP);
   else
      return (entryPx > pxNow ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP);
}

inline datetime Main_ComputePendingExpiryTime(const ICT_Context &ctx,
                                             const Settings    &cfg,
                                             const datetime     now)
{
   // 1) Default TTL (minutes)
   int ttl_min = 60; // sane default

   // Optional config field if you have it
#ifdef CFG_HAS_MAIN_PENDING_TTL_MINUTES
   if(cfg.main_pending_ttl_minutes > 0)
      ttl_min = (int)cfg.main_pending_ttl_minutes;
#endif

   datetime exp_by_ttl = now + (ttl_min * 60);

   // 2) If your ICT context exposes a session/trading-window end, clamp to it.
   //    This keeps pendings from surviving past the window.
#ifdef ICTCTX_HAS_SESSION_WINDOW_END
   if(ctx.sessionWindowEnd > 0)
   {
      // Clamp: earlier of TTL expiry and session window end
      if(exp_by_ttl > ctx.sessionWindowEnd)
         return ctx.sessionWindowEnd;
   }
#endif

   return exp_by_ttl;
}

//-----------------------------------------------------------------------------
// Internal helpers to evaluate directional trigger conditions
//-----------------------------------------------------------------------------
// BUY trigger logic = "does the current market context justify considering a long?"
// We translate your old checklist into high-level gates:
//
// a) liquidity sweep of sell-side ? ctx.liquiditySweepType == SWEEP_SELLSIDE / SWEEP_BOTH
// b) bullish CHOCH (ctx.chochDetected)
// c) price currently interacting with bullish block / bullish FVG / OTE discount pocket
// d) killzone ok (ctx.killzoneState.inKillzone or config override)
// e) "pattern OR EMA/VWAP alignment" ? we trust classicalScoreBuy to reflect that
//
// We return true/false, plus we output a human-readable reason string for logging.
bool EvaluateBuyTrigger(const string sym,
                        const ICT_Context &ctx,
                        const bool haveEntryScan,
                        const Scan::IndiSnapshot &ss,
                        const bool haveOFDS,
                        const MainOFDS &ofds,
                        const double /*classicalScoreBuy*/,
                        const Settings &cfg,
                        string &whyOut)
{
   whyOut = "";

   const bool testerLooseGate = Main_CfgTesterLooseGate(cfg);
   const ENUM_TIMEFRAMES tfE = (ENUM_TIMEFRAMES)cfg.tf_entry;
   const bool sweepBullish = (ctx.liquiditySweepType == SWEEP_SELLSIDE || ctx.liquiditySweepType == SWEEP_BOTH);

   const bool haveLiqScanSignals =
      (haveEntryScan &&
       (ss.liq_last_sweep_bsl_ts > 0 ||
        ss.liq_last_sweep_ssl_ts > 0 ||
        ss.liq_last_reject_ts    > 0 ||
        ss.liq_last_sweep_kind   != 0));

   const bool rejectBullish =
      (haveLiqScanSignals && StratScan::LiqRejectRecentForDir(ss, tfE, DIR_BUY, cfg));

   const bool microUnsafe =
      (testerLooseGate
       ? false
       : (haveOFDS &&
          ofds.have_flow &&
          (ofds.flow_dir <= -0.30) &&
          (!ofds.have_vpin || _MainClamp01(ofds.vpin) >= 0.40)));

   bool liqCtx = false;
   bool scanIsAuthoritative = false;

   if(haveEntryScan)
      liqCtx = Main_TryLiquidityContextFromScan(ss, tfE, DIR_BUY, cfg, scanIsAuthoritative);

   if(!scanIsAuthoritative && !testerLooseGate)
      liqCtx = ADP_LIQ_PoolOrInducementNearby(sym, tfE, true);

   if(testerLooseGate && !liqCtx)
      liqCtx = true;

   const bool regimeOK   = HasMarketStructure(sym, tfE, DIR_BUY, cfg);
   const bool chochBull  = ctx.chochDetected;
   const bool bosBull    = ctx.bosContinuationDetected;
   const bool springBull = ctx.wySpringCandidate;

   const double entryPrice = iClose(sym, tfE, 1);
   if(entryPrice <= 0.0)
   {
      whyOut = "BUY trigger blocked [noClosedBarPrice]";
      return false;
   }

   ICTOrderBlock obPick;
   string obSrc = "";
   ICTFVG fvgPick;
   string fvgSrc = "";

   const bool hasBullOB  = StratMainLogic::PickBestOBForDir(ctx, true, obPick, obSrc);
   const bool hasBullFVG = StratMainLogic::PickBestFVGForDir(ctx, true, fvgPick, fvgSrc);

   const bool atBullOB  = (hasBullOB  && StratMainLogic::_BandContains(entryPrice, obPick.low,  obPick.high));
   const bool atBullFVG = (hasBullFVG && StratMainLogic::_BandContains(entryPrice, fvgPick.low, fvgPick.high));

   const bool inDiscountOTE =
      (ctx.oteZone.isDiscountForBuys &&
       entryPrice >= MathMin(ctx.oteZone.lower, ctx.oteZone.upper) &&
       entryPrice <= MathMax(ctx.oteZone.lower, ctx.oteZone.upper));

   const bool zoneNear         = HasInstitutionalZoneNearET(sym, tfE, DIR_BUY, cfg);
   const bool locationStrictOK = (zoneNear || atBullOB || atBullFVG || inDiscountOTE);
   const bool structureOK      = (regimeOK && (chochBull || bosBull || springBull));

   const bool sweepRejectOK = (sweepBullish && rejectBullish);
   const bool liqEventOK    = (testerLooseGate ? true  : (sweepRejectOK || springBull));

   const bool testerDegradedTriggerSoft =
      (Main_CfgTesterDegradedMode(cfg) && !testerLooseGate);

   const bool locationOK       = (testerLooseGate ? (locationStrictOK || liqCtx) : locationStrictOK);
   const bool locationSoftened =
      (testerDegradedTriggerSoft && !locationOK && structureOK && liqCtx && !microUnsafe);

   const bool liqEventSoftened =
      (testerDegradedTriggerSoft && !liqEventOK && structureOK && locationStrictOK && !microUnsafe);

   const bool locationGatePass = (locationOK || locationSoftened);
   const bool liqEventGatePass = (liqEventOK || liqEventSoftened);

   const bool weakPoolOnly  =
      ((testerLooseGate || testerDegradedTriggerSoft)
       ? false
       : (liqCtx && !sweepRejectOK && !springBull));

   const bool pass =
      (structureOK &&
       locationGatePass &&
       liqEventGatePass &&
       !weakPoolOnly &&
       !microUnsafe);

   if(CfgDebugStrategies(cfg))
   {
      const string msg =
         StringFormat("[DiagTrig] sym=%s tf=%d dir=BUY regime=%d sweep=%d rej=%d spring=%d struct=%d loc=%d liqCtx=%d weakPoolOnly=%d price=%.5f"
                      " | OB[%.5f..%.5f] FVG[%.5f..%.5f] OTE[%.5f..%.5f]"
                      " | pass=%d",
                      sym, (int)tfE,
                      (regimeOK ? 1 : 0),
                      (sweepBullish ? 1 : 0), (rejectBullish ? 1 : 0), (springBull ? 1 : 0),
                      (structureOK ? 1 : 0), (locationOK ? 1 : 0), (liqCtx ? 1 : 0),
                      ((liqCtx && !sweepRejectOK && !springBull) ? 1 : 0),
                      entryPrice,
                      MathMin(obPick.low, obPick.high), MathMax(obPick.low, obPick.high),
                      MathMin(fvgPick.low, fvgPick.high), MathMax(fvgPick.low, fvgPick.high),
                      MathMin(ctx.oteZone.lower, ctx.oteZone.upper), MathMax(ctx.oteZone.lower, ctx.oteZone.upper),
                      (pass ? 1 : 0));

      DbgStrat(cfg, sym, tfE, "TrigBUY", msg, true);
   }

   if(pass)
   {
      whyOut = "BUY trigger ok [" +
               (regimeOK         ? "regime "           : "") +
               (structureOK      ? "struct "           : "") +
               (locationGatePass ? "poi "              : "") +
               (sweepRejectOK    ? "sweepRej "         : "") +
               (springBull       ? "spring "           : "") +
               (locationSoftened ? "testerDegSoftLoc " : "") +
               (liqEventSoftened ? "testerDegSoftLiq " : "") +
               "]";
      return true;
   }

   whyOut = "BUY trigger blocked [" +
            (regimeOK      ? "regime "      : "noRegime ") +
            (structureOK   ? "struct "      : "noStruct ") +
            (locationOK    ? "poi "         : "noPOI ") +
            (sweepRejectOK ? "sweepRej "    : "") +
            (springBull    ? "spring "      : "") +
            (!liqEventOK   ? "noLiqEvent "  : "") +
            ((liqCtx && !sweepRejectOK && !springBull) ? "poolOnly " : "") +
            (microUnsafe   ? "microUnsafe " : "") +
            "]";

   return false;
}

// SELL trigger logic == bearish mirror of above.
bool EvaluateSellTrigger(const string sym,
                         const ICT_Context &ctx,
                         const bool haveEntryScan,
                         const Scan::IndiSnapshot &ss,
                         const bool haveOFDS,
                         const MainOFDS &ofds,
                         const double /*classicalScoreSell*/,
                         const Settings &cfg,
                         string &whyOut)
{
   whyOut = "";

   const bool testerLooseGate = Main_CfgTesterLooseGate(cfg);
   const ENUM_TIMEFRAMES tfE = (ENUM_TIMEFRAMES)cfg.tf_entry;
   const bool sweepBearish = (ctx.liquiditySweepType == SWEEP_BUYSIDE || ctx.liquiditySweepType == SWEEP_BOTH);

   const bool haveLiqScanSignals =
      (haveEntryScan &&
       (ss.liq_last_sweep_bsl_ts > 0 ||
        ss.liq_last_sweep_ssl_ts > 0 ||
        ss.liq_last_reject_ts    > 0 ||
        ss.liq_last_sweep_kind   != 0));

   const bool rejectBearish =
      (haveLiqScanSignals && StratScan::LiqRejectRecentForDir(ss, tfE, DIR_SELL, cfg));

   const bool microUnsafe =
      (testerLooseGate
       ? false
       : (haveOFDS &&
          ofds.have_flow &&
          (ofds.flow_dir >= 0.30) &&
          (!ofds.have_vpin || _MainClamp01(ofds.vpin) >= 0.40)));

   bool liqCtx = false;
   bool scanIsAuthoritative = false;

   if(haveEntryScan)
      liqCtx = Main_TryLiquidityContextFromScan(ss, tfE, DIR_SELL, cfg, scanIsAuthoritative);

   if(!scanIsAuthoritative && !testerLooseGate)
      liqCtx = ADP_LIQ_PoolOrInducementNearby(sym, tfE, false);

   if(testerLooseGate && !liqCtx)
      liqCtx = true;

   const bool regimeOK   = HasMarketStructure(sym, tfE, DIR_SELL, cfg);
   const bool chochBear  = ctx.chochDetected;
   const bool bosBear    = ctx.bosContinuationDetected;
   const bool utadBear   = ctx.wyUTADCandidate;

   const double entryPrice = iClose(sym, tfE, 1);
   if(entryPrice <= 0.0)
   {
      whyOut = "SELL trigger blocked [noClosedBarPrice]";
      return false;
   }

   ICTOrderBlock obPick;
   string obSrc = "";
   ICTFVG fvgPick;
   string fvgSrc = "";

   const bool hasBearOB  = StratMainLogic::PickBestOBForDir(ctx, false, obPick, obSrc);
   const bool hasBearFVG = StratMainLogic::PickBestFVGForDir(ctx, false, fvgPick, fvgSrc);

   const bool atBearOB  = (hasBearOB  && StratMainLogic::_BandContains(entryPrice, obPick.low,  obPick.high));
   const bool atBearFVG = (hasBearFVG && StratMainLogic::_BandContains(entryPrice, fvgPick.low, fvgPick.high));

   const bool inPremiumOTE =
      (!ctx.oteZone.isDiscountForBuys &&
       entryPrice >= MathMin(ctx.oteZone.lower, ctx.oteZone.upper) &&
       entryPrice <= MathMax(ctx.oteZone.lower, ctx.oteZone.upper));

   const bool zoneNear         = HasInstitutionalZoneNearET(sym, tfE, DIR_SELL, cfg);
   const bool locationStrictOK = (zoneNear || atBearOB || atBearFVG || inPremiumOTE);
   const bool structureOK      = (regimeOK && (chochBear || bosBear || utadBear));

   const bool sweepRejectOK = (sweepBearish && rejectBearish);
   const bool liqEventOK    = (testerLooseGate ? true  : (sweepRejectOK || utadBear));

   const bool testerDegradedTriggerSoft =
      (Main_CfgTesterDegradedMode(cfg) && !testerLooseGate);

   const bool locationOK       = (testerLooseGate ? (locationStrictOK || liqCtx) : locationStrictOK);
   const bool locationSoftened =
      (testerDegradedTriggerSoft && !locationOK && structureOK && liqCtx && !microUnsafe);

   const bool liqEventSoftened =
      (testerDegradedTriggerSoft && !liqEventOK && structureOK && locationStrictOK && !microUnsafe);

   const bool locationGatePass = (locationOK || locationSoftened);
   const bool liqEventGatePass = (liqEventOK || liqEventSoftened);

   const bool weakPoolOnly  =
      ((testerLooseGate || testerDegradedTriggerSoft)
       ? false
       : (liqCtx && !sweepRejectOK && !utadBear));

   const bool pass =
      (structureOK &&
       locationGatePass &&
       liqEventGatePass &&
       !weakPoolOnly &&
       !microUnsafe);

   if(CfgDebugStrategies(cfg))
   {
      const string msg =
         StringFormat("[DiagTrig] sym=%s tf=%d dir=SELL regime=%d sweep=%d rej=%d utad=%d struct=%d loc=%d liqCtx=%d weakPoolOnly=%d price=%.5f"
                      " | OB[%.5f..%.5f] FVG[%.5f..%.5f] OTE[%.5f..%.5f]"
                      " | pass=%d",
                      sym, (int)tfE,
                      (regimeOK ? 1 : 0),
                      (sweepBearish ? 1 : 0), (rejectBearish ? 1 : 0), (utadBear ? 1 : 0),
                      (structureOK ? 1 : 0), (locationOK ? 1 : 0), (liqCtx ? 1 : 0),
                      ((liqCtx && !sweepRejectOK && !utadBear) ? 1 : 0),
                      entryPrice,
                      MathMin(obPick.low, obPick.high), MathMax(obPick.low, obPick.high),
                      MathMin(fvgPick.low, fvgPick.high), MathMax(fvgPick.low, fvgPick.high),
                      MathMin(ctx.oteZone.lower, ctx.oteZone.upper), MathMax(ctx.oteZone.lower, ctx.oteZone.upper),
                      (pass ? 1 : 0));

      DbgStrat(cfg, sym, tfE, "TrigSELL", msg, true);
   }

   if(pass)
   {
      whyOut = "SELL trigger ok [" +
               (regimeOK         ? "regime "           : "") +
               (structureOK      ? "struct "           : "") +
               (locationGatePass ? "poi "              : "") +
               (sweepRejectOK    ? "sweepRej "         : "") +
               (utadBear         ? "utad "             : "") +
               (locationSoftened ? "testerDegSoftLoc " : "") +
               (liqEventSoftened ? "testerDegSoftLiq " : "") +
               "]";
      return true;
   }

   whyOut = "SELL trigger blocked [" +
            (regimeOK      ? "regime "      : "noRegime ") +
            (structureOK   ? "struct "      : "noStruct ") +
            (locationOK    ? "poi "         : "noPOI ") +
            (sweepRejectOK ? "sweepRej "    : "") +
            (utadBear      ? "utad "        : "") +
            (!liqEventOK   ? "noLiqEvent "  : "") +
            ((liqCtx && !sweepRejectOK && !utadBear) ? "poolOnly " : "") +
            (microUnsafe   ? "microUnsafe " : "") +
            "]";

   return false;
}

//-----------------------------------------------------------------------------
// Gating modes: Silver Bullet and PO3
//-----------------------------------------------------------------------------

// Silver Bullet mode = STRICT:
// - only trade if ctx.silverBulletReady == true
// - window already implied by ctx.silverBulletReady in this stack
// - (which implies killzone logic etc.)
// If mode not enabled, always true.
bool Gate_SilverBullet(const ICT_Context &ctx,
                              const Settings &cfg,
                              string &whyOut)
{
   whyOut = "";
   #ifdef CFG_HAS_MODE_SILVER_BULLET
   if(!cfg.mode_use_silverbullet)
   {
      whyOut = "SB gate bypassed (mode off)";
      return true;
   }
   #endif

   bool allowed = (ctx.silverBulletReady);
   whyOut = allowed
         ? "SB gate PASSED"
         : "SB gate FAIL (not silverBulletReady/Now)";
   return allowed;
}

// PO3 mode = we only take the "distribution" leg of the session campaign.
// In ICT-speak: Accumulation?Manipulation already happened, we want the Distribution phase.
// Our ctx.po3State.* tracks:
//    accumulation (early box), manipulationComplete (liquidity raid),
//    distributionLive (the real move now).
// We require distributionLive=true if mode enabled.
bool Gate_PO3(const ICT_Context &ctx,
              const Settings &cfg,
              string &whyOut)
{
   whyOut = "";

   if(Main_CfgTesterLooseGate(cfg))
   {
      whyOut = "PO3 gate bypassed (tester loose gate)";
      return true;
   }

   #ifdef CFG_HAS_MODE_ENFORCE_KILLZONE
   if(!cfg.mode_enforce_killzone)
   {
      whyOut = "PO3 gate bypassed (killzone off)";
      return true;
   }
   #endif

   #ifdef CFG_HAS_MODE_PO3
   if(!cfg.mode_use_po3)
   {
      whyOut = "PO3 gate bypassed (mode off)";
      return true;
   }
   #endif

   bool allowed = ctx.po3State.distributionLive;
   whyOut = allowed
         ? "PO3 gate PASSED"
         : "PO3 gate FAIL (dist not live)";
   return allowed;
}

//-----------------------------------------------------------------------------
// Killzone / Trading-window enforcement (HARD vs SOFT) � canonical gate
//-----------------------------------------------------------------------------
// Modes:
// 0 = OFF
// 1 = HARD  (return false if outside window)
// 2 = SOFT  (penalize score + reduce risk if outside window)
enum { KZ_MODE_OFF=0, KZ_MODE_HARD=1, KZ_MODE_SOFT=2 };

inline int CfgKillzoneMode(const Settings &cfg)
{
   if(Main_CfgTesterDisableKillzone(cfg))
      return KZ_MODE_OFF;

#ifdef CFG_HAS_KILLZONE_MODE
   return (int)cfg.killzone_mode;
#endif

#ifdef CFG_HAS_MODE_ENFORCE_KILLZONE
   return (cfg.mode_enforce_killzone ? KZ_MODE_HARD : KZ_MODE_OFF);
#endif

   return KZ_MODE_OFF;
}

inline bool CfgAllowSilverBulletOverride(const Settings &cfg)
{
#ifdef CFG_HAS_ALLOW_SILVER_BULLET_OVERRIDE
   return cfg.allowSilverBulletOverride;
#endif
   // Conservative default: no override unless explicitly enabled in Config.
   return false;
}

inline double CfgKillzoneSoftPenalty(const Settings &cfg)
{
#ifdef CFG_HAS_KILLZONE_SOFT_PENALTY
   if(cfg.killzone_soft_penalty > 0.0 && cfg.killzone_soft_penalty < 1.0)
      return cfg.killzone_soft_penalty;
#endif
   return 0.75; // default: gentle penalty
}

inline double CfgKillzoneSoftRiskMult(const Settings &cfg)
{
#ifdef CFG_HAS_KILLZONE_SOFT_RISK_MULT
   if(cfg.killzone_soft_risk_mult > 0.0 && cfg.killzone_soft_risk_mult < 1.0)
      return cfg.killzone_soft_risk_mult;
#endif
   return 0.50; // default: halve risk outside window
}

// Returns "allowTradeNow" using the ICT_Context canonical decision when available.
// Fallback is killzoneState + optional SB override.
inline bool ICTCtx_AllowTradeNow(const ICT_Context &ctx,
                                 const Settings    &cfg,
                                 bool             &out_inKillzone,
                                 bool             &out_sbOverrideUsed)
{
   out_inKillzone      = ctx.killzoneState.inKillzone;
   out_sbOverrideUsed  = false;

#ifdef ICTCTX_HAS_SESSION_ALLOW_TRADE_NOW
   // Preferred: already computed upstream by ICTWyckoffModel using session rules.
   return ctx.sessionAllowTradeNow;
#else
   bool sbNow = false;

   #ifdef ICTCTX_HAS_SILVER_BULLET_NOW
      sbNow = ctx.silverBulletNow;
   #else
      // Fallback if you don't have silverBulletNow field:
      sbNow = ctx.silverBulletReady;
   #endif

   const bool allowSB = CfgAllowSilverBulletOverride(cfg);
   const bool allow   = (out_inKillzone || (allowSB && sbNow));

   if(!out_inKillzone && allowSB && sbNow)
      out_sbOverrideUsed = true;

   return allow;
#endif
}

//-----------------------------------------------------------------------------
// Extra confluence helpers (compile-safe)
// - Silver Bullet timezone/window "now"
// - Intraday AMD phases (H1/H4) as confluence (no hard veto)
//-----------------------------------------------------------------------------

// AMD phases (intraday context)
enum { AMD_PHASE_UNKNOWN=0, AMD_PHASE_ACCUM=1, AMD_PHASE_MANIP=2, AMD_PHASE_DIST=3 };

// Silver Bullet window "now" (timezone entry confluence).
// IMPORTANT: This is NOT "setup ready". It is "time window now".
// If ctx doesn't carry a true window flag, this returns false (no bonus).
inline bool Ctx_SilverBulletWindowNow(const ICT_Context &ctx)
{
   // Single source of truth: ICT context session fields.
   if(ctx.inSilverBullet)
      return true;

   // Fallback: some stacks use "ready" even if they do not mark the live window.
   if(ctx.silverBulletReady)
      return true;

   // Last fallback: session allowance (keeps behavior stable if SB is not wired).
   return ctx.sessionAllowTradeNow;
}

// Extract PO3 AMD phase for H1 (Accumulation/Manipulation/Distribution campaign state).
// NOTE: PO3 semantics, not Wyckoff range Accumulation/Distribution semantics.
// If not present, returns UNKNOWN (no bonus/penalty).
inline int Ctx_AMDPhase_H1(const ICT_Context &ctx)
{
   // H1 snapshot: Accumulation, Manipulation, Distribution
   if(ctx.po3StateH1.distributionLive)
      return AMD_PHASE_DIST;

   if(ctx.po3StateH1.manipulationComplete)
      return AMD_PHASE_MANIP;

   if(ctx.po3StateH1.accumulation)
      return AMD_PHASE_ACCUM;
      
   return AMD_PHASE_UNKNOWN;
}

// Extract PO3 AMD phase for H4 (campaign state; not Wyckoff range semantics).
inline int Ctx_AMDPhase_H4(const ICT_Context &ctx)
{
   // H4 snapshot: Accumulation, Manipulation, Distribution
   if(ctx.po3StateH4.distributionLive)
      return AMD_PHASE_DIST;

   if(ctx.po3StateH4.manipulationComplete)
      return AMD_PHASE_MANIP;

   if(ctx.po3StateH4.accumulation)
      return AMD_PHASE_ACCUM;
      
   return AMD_PHASE_UNKNOWN;
}

// Convenience booleans used by scoring/extras
inline bool Ctx_AMD_Distribution_H1(const ICT_Context &ctx) { return (Ctx_AMDPhase_H1(ctx) == AMD_PHASE_DIST); }
inline bool Ctx_AMD_Distribution_H4(const ICT_Context &ctx) { return (Ctx_AMDPhase_H4(ctx) == AMD_PHASE_DIST); }

// --- Context preference helpers (soft bias, not a veto) ---
inline bool Ctx_Wy_InAccum_Intra(const ICT_Context &ctx)
{
   // These flags are added in Types.mqh / ICTWyckoffModel.mqh per the intraday Wyckoff plan.
   // Guarded by ICTCTX_HAS_WYCKOFF_INTRADAY so builds without intraday Wyckoff remain safe.
   #ifdef ICTCTX_HAS_WYCKOFF_INTRADAY
      return (ctx.wyInAccumH1 || ctx.wyInAccumH4_intra);
   #else
      return false;
   #endif
}

inline bool Ctx_Wy_InDist_Intra(const ICT_Context &ctx)
{
   #ifdef ICTCTX_HAS_WYCKOFF_INTRADAY
      return (ctx.wyInDistH1 || ctx.wyInDistH4_intra);
   #else
      return false;
   #endif
}

inline bool Ctx_PrefersDir_Soft(const ICT_Context &ctx, const Direction dir)
{
   // Primary: intraday Wyckoff environment (H1/H4) when available
   bool wyAccumIntra = false;
   bool wyDistIntra  = false;

   #ifdef ICTCTX_HAS_WYCKOFF_INTRADAY
      wyAccumIntra = (ctx.wyInAccumH1 || ctx.wyInAccumH4_intra);
      wyDistIntra  = (ctx.wyInDistH1  || ctx.wyInDistH4_intra);
   #endif

   // If intraday Wyckoff is decisive, use it
   if(wyAccumIntra != wyDistIntra)
   {
      if(dir == DIR_BUY)  return wyAccumIntra;
      return wyDistIntra; // DIR_SELL
   }

   // Secondary fallback: AMD / PO3 phase (H1/H4)
   const int ph1 = Ctx_AMDPhase_H1(ctx);
   const int ph4 = Ctx_AMDPhase_H4(ctx);

   if(dir == DIR_BUY)
      return (ph1 == AMD_PHASE_ACCUM) || (ph4 == AMD_PHASE_ACCUM);

   return (ph1 == AMD_PHASE_DIST) || (ph4 == AMD_PHASE_DIST);
}

// ---------------------------------------------------------------------------
// Additional confluence helpers (Main logic shaping, not hard vetoes)
// ---------------------------------------------------------------------------

inline bool _ZoneHas(const Zone &z)
{
   return (z.lo != 0.0 || z.hi != 0.0);
}

inline bool _ZoneInside(const Zone &z, const double px)
{
   const double lo = MathMin(z.lo, z.hi);
   const double hi = MathMax(z.lo, z.hi);
   return (px >= lo && px <= hi);
}

inline double _ZoneDistancePoints(const string sym, const Zone &z, const double px)
{
   const double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0)
      return 1000000000.0;

   if(!_ZoneHas(z))
      return 1000000000.0;

   const double lo = MathMin(z.lo, z.hi);
   const double hi = MathMax(z.lo, z.hi);

   double dist = 0.0;
   if(px < lo) dist = (lo - px);
   else if(px > hi) dist = (px - hi);
   else dist = 0.0;

   return dist / point;
}

// PO3 HTF narrative: score in [-1..2]
inline int Ctx_PO3_HTF_ContextScore(const ICT_Context &ctx, const Direction dir, string &why)
{
   const int h1 = Ctx_AMDPhase_H1(ctx);
   const int h4 = Ctx_AMDPhase_H4(ctx);

   int score = 0;

   const bool h1Dist  = (h1 == AMD_PHASE_DIST);
   const bool h4Dist  = (h4 == AMD_PHASE_DIST);
   const bool h4Manip = (h4 == AMD_PHASE_MANIP);
   const bool bothAcc = (h1 == AMD_PHASE_ACCUM && h4 == AMD_PHASE_ACCUM);

   if(h4Dist && h1Dist) score = 2;
   else if(h4Dist)      score = 1;
   else if(h4Manip)     score = -1;
   else if(bothAcc)     score = -1;
   else                 score = 0;

   const string d = (dir == DIR_BUY ? "BUY" : "SELL");
   if(score == 2)      why = d + ": PO3 HTF campaign (H4+H1 distribution)";
   else if(score == 1) why = d + ": PO3 HTF campaign (H4 distribution)";
   else if(score < 0)  why = d + ": PO3 HTF caution (manipulation or early phase)";
   else                why = d + ": PO3 HTF neutral";

   return score;
}

// Wyckoff turn context: score in [-1..1]
inline int Ctx_WyckoffTurnContext(const ICT_Context &ctx, const Direction dir, string &why)
{
   const bool isBuy = (dir == DIR_BUY);

   if(isBuy)
   {
      if(ctx.wySpringCandidate) { why = "BUY: Wyckoff Spring candidate"; return 1; }
      if(ctx.wyUTADCandidate)   { why = "BUY: UTAD candidate (opposite)"; return -1; }
      why = "BUY: no Wyckoff turn";
      return 0;
   }

   if(ctx.wyUTADCandidate)   { why = "SELL: Wyckoff UTAD candidate"; return 1; }
   if(ctx.wySpringCandidate) { why = "SELL: Spring candidate (opposite)"; return -1; }
   why = "SELL: no Wyckoff turn";
   return 0;
}

// HTF OB/SD zones + HTF liquidity sentiment: score in [0..3]
inline int Ctx_HTFZoneLiq_ContextScore(const string sym, const ENUM_TIMEFRAMES tf_entry,
                                      const ICT_Context &ctx, const Direction dir, string &why)
{
   const bool isBuy = (dir == DIR_BUY);
   const double px  = iClose(sym, tf_entry, 1);

   // Demand for BUY, Supply for SELL
   const Zone zH1 = (isBuy ? ctx.bestDemandZoneH1 : ctx.bestSupplyZoneH1);
   const Zone zH4 = (isBuy ? ctx.bestDemandZoneH4 : ctx.bestSupplyZoneH4);

   const bool inH1 = (_ZoneHas(zH1) && _ZoneInside(zH1, px));
   const bool inH4 = (_ZoneHas(zH4) && _ZoneInside(zH4, px));

   const double distH1 = _ZoneDistancePoints(sym, zH1, px);
   const double distH4 = _ZoneDistancePoints(sym, zH4, px);

   // Mild, fixed �near� thresholds in points (keeps it confluence-only)
   const double nearH1 = 15.0;
   const double nearH4 = 25.0;

   int score = 0;
   string parts = "";

   if(inH4)
   {
      score += 2;
      parts = "H4 zone";
   }
   else if(inH1)
   {
      score += 1;
      parts = "H1 zone";
   }
   else if(distH4 <= nearH4)
   {
      score += 1;
      parts = "near H4 zone";
   }
   else if(distH1 <= nearH1)
   {
      score += 1;
      parts = "near H1 zone";
   }

   // Stacked zones matter, but keep it mild
   if(score > 0 && ctx.zoneStackDepth >= 2)
   {
      score += 1;
      if(parts != "") parts += ", ";
      parts += "stacked";
   }

   // HTF liquidity sentiment: skew sign is used as directional �target-side� bias
   if(ctx.liqSentHTF.valid)
   {
      const double s = ctx.liqSentHTF.skew;
      const bool liqOk = (isBuy ? (s > 0.10) : (s < -0.10));
      if(liqOk)
      {
         score += 1;
         if(parts != "") parts += ", ";
         parts += "liqHTF";
      }
   }

   if(score > 3) score = 3;

   const string d = (isBuy ? "BUY" : "SELL");
   if(parts == "") parts = "none";
   why = d + ": HTF zones/liquidity = " + parts;

   return score;
}

// ---------- Helper: thresholds with safe defaults ----------
namespace _ML
{
  inline int CF_MinNeeded(const Settings &cfg)
  {
    #ifdef CFG_HAS_CF_GATE
      if(cfg.cf_min_needed > 0) return cfg.cf_min_needed;
    #endif
    return 1;   // <� qualified
  }

  inline double CF_MinScore(const Settings &cfg)
  {
    #ifdef CFG_HAS_CF_GATE
      if(cfg.cf_min_score > 0.0) return cfg.cf_min_score;
    #endif
    return 0.55;   // <� qualified
  }

  inline void Append(ConfluenceResult &R, const bool ok, const double w, const string &name, const int bit)
  {
    if(R.summary != "")
       R.summary += ", ";

    R.summary += name + (ok ? "(?)" : "(�)");

    if(ok)
    {
       R.metCount++;
       R.score += w;
       R.mask |= ((ulong)1 << bit);   // MQL5-safe: no 1u literal
    }
  }

  inline void Add(ConfluenceResult &R, const bool used, const bool ok, const double w, const string &name, const int bit)
  {
    if(!used) return;
    Append(R, ok, w, name, bit);
  }

  inline void AddExtra(ConfluenceResult &R, const bool used, const bool ok, const double w, const string name, const int bit)
  {
    if(!used)
       return;

    if(R.summary != "")
       R.summary += ", ";

    R.summary += name + (ok ? "(?)" : "(�)");

    if(ok)
    {
       R.metCount++;
       R.score += w;
       R.mask |= ((ulong)1 << bit);   // MQL5-safe: no 1u literal
    }
  }

  inline void RecomputeEligibility(ConfluenceResult &R, const Settings &cfg)
  {
    const int    need   = CF_MinNeeded(cfg);
    const double minSc  = CF_MinScore(cfg);

    R.passesCount = (R.metCount >= MathMax(1, need));
    R.passesScore = (R.score    >= minSc);

    // Require at least one confirmation signal (classical OR Autochartist)
    const bool needConfirm =
         (cfg.cf_candle_pattern || (cfg.cf_chart_pattern && !cfg.cf_autochartist_chart) || cfg.cf_trend_regime
          || cfg.cf_autochartist_chart || cfg.cf_autochartist_fib
          || cfg.cf_autochartist_keylevels || cfg.cf_autochartist_volatility);
      
    bool requireAny = true;
    #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
      requireAny = cfg.main_confirm_any_of_3;
    #endif
      
    bool patternOrTrend = true;
    if(needConfirm && requireAny)
    {
      patternOrTrend =
         ((R.mask & ((ulong)1 << C_CANDLE)) != 0) ||
         ((R.mask & ((ulong)1 << C_CHART )) != 0) ||
         ((R.mask & ((ulong)1 << C_TREND )) != 0) ||
         ((R.mask & ((ulong)1 << C_AUTO_CHART)) != 0) ||
         ((R.mask & ((ulong)1 << C_AUTO_FIB)) != 0) ||
         ((R.mask & ((ulong)1 << C_AUTO_KEYLEVELS)) != 0) ||
         ((R.mask & ((ulong)1 << C_AUTO_VOL)) != 0);
    }
      
    R.eligible = R.passesCount && R.passesScore && patternOrTrend;
  }

  inline ConfluenceResult Finalize(ConfluenceResult &R, const Settings &cfg, const string tag="Main")
  {
    RecomputeEligibility(R, cfg);
    if(CfgDebugStrategies(cfg))
     {
        PrintFormat("[Main %s] met=%d score=%.2f need>=%d minScore=%.2f | %s | eligible=%s",
                    tag, R.metCount, R.score, CF_MinNeeded(cfg), CF_MinScore(cfg), R.summary,
                    R.eligible ? "YES":"NO");
     }
    return R;
  }
} // namespace _ML

// ============================================================================
// Profile-aware weight logging for STRAT_MAIN_ID
// ============================================================================
namespace MainStratWeightLog
{
   // Resolve effective profile weight for this strategy.
   //  - Preferred: cfg.strat_weight_main (mapped from ProfileSpec).
   //  - Optional: Config::GetProfileStrategyWeight(...) if you expose it.
   //  - Fallback: 1.0 (no profile-based weighting).
   inline double GetEffectiveMainWeight(const Settings &cfg)
   {
      #ifdef CFG_HAS_STRAT_WEIGHT_MAIN
         // Example: field carried from ProfileSpec ? Settings in Config.mqh
         return cfg.strat_weight_main;
      #else
         #ifdef CFG_HAS_PROFILE_STRAT_WEIGHT_API
            // If you wire an API like this in Config.mqh:
            //   double Config::GetProfileStrategyWeight(const Settings&, const int stratId);
            return Config::GetProfileStrategyWeight(cfg, STRAT_MAIN_ID);
         #else
            // Compile-safe default if you haven't wired weights yet.
            return 1.0;
         #endif
      #endif
   }

   // Log weight + confluence result so you can see how hard the profile leans
   // on STRAT_MAIN_ID vs the dedicated ICT strategies.
   inline void LogMainWeight(const Settings  &cfg,
                             const Direction  dir,
                             const StratScore &s)
   {
      const double w = GetEffectiveMainWeight(cfg);

      string prof = "";
      #ifdef CFG_HAS_PROFILE_NAME
         // Optional: if Settings carries a profile name/tag
         prof = cfg.profile_name;
      #endif

      const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
      const string msg =
         StringFormat("profile=%s strat_id=%d dir=%s weight=%.3f score=%.3f eligible=%s",
                      prof,
                      STRAT_MAIN_ID,
                      dirStr,
                      w,
                      s.score,
                      s.eligible ? "YES" : "NO");

      // Always to the terminal log
      Print("[StratMainWeight] ", msg);

      #ifdef TELEMETRY_AVAILABLE
         #ifndef STRAT_MAIN_DISABLE_TELEMETRY_NOTES
            Telemetry::Note(_Symbol, "StratMainWeight", msg);
         #endif
      #endif
   }
} // namespace MainStratWeightLog

// ============================================================================
// Strategy: MainTradingLogic
// Produces a single scored/eligible result for the requested direction.
// Never places orders here � Router/Execution handle that.
// ============================================================================
void Evaluate_StrategyMain(EAState &/*st*/,
                           Settings &cfgForThisStrategy,
                           const ICT_Context &ictCtx,
                           StrategyStatus &ss)
{
   ConfluenceBreakdown bd; ZeroMemory(bd);
   StratScore          s;  ZeroMemory(s);

   #ifdef CFG_HAS_MAIN_ONLY_MODE
      if(cfgForThisStrategy.main_only_mode == false)
      {
         ss.Reset();
         ss.eligible    = false;
         ss.signalScore = 0.0;
         ss.reason      = "Eval_StrategyMain skipped (main_only_mode off)";
         return;
      }
   #endif
   
   // Preflight: ensure enough bar history for C.A.N.D.L.E. extension scorers.
   #ifdef CANDLE_NARRATIVE_AVAILABLE
   {
      const int narrLb = cfgForThisStrategy.cf_candle_narrative
                          ? cfgForThisStrategy.candle_narrative_lookback  : 4;
      const int tmLb   = cfgForThisStrategy.cf_axis_time_memory
                          ? cfgForThisStrategy.axis_time_memory_lookback  : 100;

      if(!CheckSanityForCANDLEExtensions(_Symbol,
                                         (ENUM_TIMEFRAMES)cfgForThisStrategy.tf_entry,
                                         narrLb, tmLb))
      {
         ss.Reset();
         ss.eligible = false;
         ss.reason   = "CANDLE_ext_bars_not_ready";
         return;
      }
   }
   #endif // CANDLE_NARRATIVE_AVAILABLE
   
   // Decide which side this strategy instance should evaluate.
   // If BOTH, follow ICT allowedDirection when it is decisive.
   Direction dir = DIR_BUY;
   bool evalBoth = false;
   
   if(cfgForThisStrategy.trade_direction_selector == TDIR_SELL)
      dir = DIR_SELL;
   else if(cfgForThisStrategy.trade_direction_selector == TDIR_BOTH)
   {
      if(ictCtx.allowedDirection == TDIR_SELL)      dir = DIR_SELL;
      else if(ictCtx.allowedDirection == TDIR_BUY)  dir = DIR_BUY;
      else                                          evalBoth = true; // ICT neutral: evaluate both sides
   }

   ENUM_TRADE_DIRECTION dirAsTDIR = (evalBoth ? TDIR_BOTH : (dir == DIR_BUY ? TDIR_BUY : TDIR_SELL));

   // Defense-in-depth: if Main is blocked by strategy mode, return confluence-only snapshot.
   if(!Config::IsStrategyAllowedInMode(cfgForThisStrategy, (StrategyID)STRAT_MAIN_ID))
   {
      const ENUM_TIMEFRAMES tfE = (ENUM_TIMEFRAMES)cfgForThisStrategy.tf_entry;
      StratMainLogic::Evaluate(_Symbol, dir, cfgForThisStrategy, ictCtx, s, bd);
   
      ss.Reset();
      ss.eligible     = false;
      ss.signalScore  = s.score;
      ss.dirBiasTaken = dirAsTDIR;
      ss.reason       = "Eval_StrategyMain blocked by strategy mode (confluence-only)";
      return;
   }

   if(CfgDebugStrategies(cfgForThisStrategy))
   {
      const ENUM_TIMEFRAMES tfE = (ENUM_TIMEFRAMES)cfgForThisStrategy.tf_entry;
      const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
   
      const string msg =
         StringFormat("[DiagMain] sym=%s tf=%d dir=%s blockedByICT=1 allowed=%d wanted=%d",
                      _Symbol, (int)tfE, dirStr,
                      (int)ictCtx.allowedDirection, (int)dirAsTDIR);
   
      DbgStrat(cfgForThisStrategy, _Symbol, tfE, "ICTBlock", msg, /*oncePerClosedBar*/true);
   }

   // Honour ICT allowedDirection: if ICT context forbids this side, stop early.
   if(!evalBoth && ictCtx.allowedDirection != TDIR_BOTH &&
      ictCtx.allowedDirection != dirAsTDIR)
   {
      // Even when ICT blocks this side, log how the profile is weighting STRAT_MAIN_ID.
      MainStratWeightLog::LogMainWeight(cfgForThisStrategy, dir, s);  // s == zeroed

      ss.Reset();
      ss.eligible     = false;
      ss.signalScore  = 0.0;
      ss.dirBiasTaken = dirAsTDIR;
      ss.reason       = "Eval_StrategyMain blocked by ICT allowedDirection";
      return;
   }

   bool ok = false;

   if(evalBoth)
   {
      StratScore sBuy;  ZeroMemory(sBuy);
      StratScore sSell; ZeroMemory(sSell);

      ConfluenceBreakdown bdBuy;  ZeroMemory(bdBuy);
      ConfluenceBreakdown bdSell; ZeroMemory(bdSell);

      const bool okBuy  = StratMainLogic::Evaluate(_Symbol, DIR_BUY,  cfgForThisStrategy, ictCtx, sBuy,  bdBuy);
      const bool okSell = StratMainLogic::Evaluate(_Symbol, DIR_SELL, cfgForThisStrategy, ictCtx, sSell, bdSell);

      string whyBuyHead = "";
      string whySellHead = "";

      const bool eligBuy  = (okBuy  && Main_StratPassesHeads(cfgForThisStrategy, sBuy,  whyBuyHead));
      const bool eligSell = (okSell && Main_StratPassesHeads(cfgForThisStrategy, sSell, whySellHead));

      if(eligBuy && (!eligSell || Main_IsBetterSide(cfgForThisStrategy, sBuy, sSell)))
      {
         dir = DIR_BUY;
         dirAsTDIR = TDIR_BUY;
         s = sBuy;
         bd = bdBuy;
         ok = okBuy;
      }
      else if(eligSell && (!eligBuy || Main_IsBetterSide(cfgForThisStrategy, sSell, sBuy)))
      {
         dir = DIR_SELL;
         dirAsTDIR = TDIR_SELL;
         s = sSell;
         bd = bdSell;
         ok = okSell;
      }
      else
      {
         ok = false;

         if(CfgDebugStrategies(cfgForThisStrategy))
         {
            PrintFormat("[Main BOTH] No winner | buy ok=%d elig=%d alpha=%.2f exec=%.2f risk=%.2f why=%s | sell ok=%d elig=%d alpha=%.2f exec=%.2f risk=%.2f why=%s",
                        (int)okBuy, (int)eligBuy,
                        Main_StratAlpha01(sBuy), Main_StratExecution01(sBuy), Main_StratRisk01(sBuy), whyBuyHead,
                        (int)okSell, (int)eligSell,
                        Main_StratAlpha01(sSell), Main_StratExecution01(sSell), Main_StratRisk01(sSell), whySellHead);
         }
      }

      if(ok)
         MainStratWeightLog::LogMainWeight(cfgForThisStrategy, dir, s);
   }
   else
   {
      ok = StratMainLogic::Evaluate(_Symbol, dir, cfgForThisStrategy, ictCtx, s, bd);
      MainStratWeightLog::LogMainWeight(cfgForThisStrategy, dir, s);
   }

   ss.Reset();
   ss.eligible     = (ok && s.eligible);
   ss.signalScore  = s.score;
   ss.dirBiasTaken = dirAsTDIR;
   ss.reason       = StringFormat("Eval_StrategyMain | eligible=%d score=%.2f alpha=%.2f exec=%.2f risk=%.2f",
                                  (int)ss.eligible,
                                  ss.signalScore,
                                  Main_StratAlpha01(s),
                                  Main_StratExecution01(s),
                                  Main_StratRisk01(s));
   if(s.reason != "")
      ss.reason += " | " + s.reason;
}

   // ------------------------------------------------------------------------
   // Helpers: bias classification and risk multiplier for Main strategy
   // ------------------------------------------------------------------------
   inline void Main_ComputeBiasFlags(const ICT_Context &ctx,
                                     const Direction    dir,
                                     const Settings    &cfg,
                                     bool              &withBias,
                                     bool              &againstBias)
   {
      withBias    = false;
      againstBias = false;

      ENUM_TRADE_DIRECTION dirAsTDIR = (dir == DIR_BUY ? TDIR_BUY : TDIR_SELL);

      // Basic directional bias from ICT context
      if(ctx.allowedDirection == dirAsTDIR)
         withBias = true;
      else if(ctx.allowedDirection != TDIR_BOTH && ctx.allowedDirection != dirAsTDIR)
         againstBias = true;

      // Optional: config can turn bias off completely
      #ifdef CFG_HAS_DIRECTION_BIAS_MODE
         #ifdef DIRBIAS_OFF
         if(cfg.direction_bias_mode == DIRBIAS_OFF)
         {
            withBias    = false;
            againstBias = false;
         }
         #endif
      #endif
   }

   inline double Main_ComputeRiskMultiplier(const Settings &cfg,
                                            const bool      withBias,
                                            const bool      againstBias)
   {
      double mult = 1.0;

      #ifdef CFG_HAS_RISK_MULT_BASE
         if(cfg.risk_mult_base > 0.0)
            mult *= cfg.risk_mult_base;
      #endif

      #ifdef CFG_HAS_RISK_MULT_MAIN
         if(cfg.risk_mult_main > 0.0)
            mult *= cfg.risk_mult_main;
      #endif

      #ifdef CFG_HAS_RISK_MULT_CONT
         if(withBias && cfg.risk_mult_continuation > 0.0)
            mult *= cfg.risk_mult_continuation;
      #endif

      #ifdef CFG_HAS_RISK_MULT_REV
         if(againstBias && cfg.risk_mult_reversal > 0.0)
            mult *= cfg.risk_mult_reversal;
      #endif

      // Clamp to a sane range
      if(mult < 0.0)
         mult = 0.0;
      if(mult > 3.0)
         mult = 3.0;

      return mult;
   }
   
   // -----------------------------------------------------------------------------
   // AutoVol consumer policy (single owner in strategy layer)
   // - Regime filter (optional hard veto)
   // - Quality multiplier (score shaping)
   // - Risk multiplier (lot sizing + SL/TP scaling downstream)
   // -----------------------------------------------------------------------------
   inline void Main_AutoVol_Apply(const Settings               &cfg,
                                 const bool                   haveAv,
                                 const AutoVol::AutoVolStats  &av,
                                 double                       &outQualMult,
                                 double                       &outRiskMult,
                                 bool                         &outOK,
                                 string                       &outWhy)
   {
      outQualMult = 1.0;
      outRiskMult = 1.0;
      outOK       = true;
      outWhy      = "";
   
      if(!haveAv)
      {
         outWhy = "autovol:na";
         return;
      }
   
      // Defaults (safe). You can later override via cfg fields if you add them.
      double softSigma = 35.0;     // annualized daily-return sigma (%)
      double hardSigma = 55.0;     // hard veto (only if enabled)
      bool   hardVeto  = false;
   
      // Optional config wiring (only if these exist in Config.mqh)
      #ifdef CFG_HAS_MAIN_AUTOVOL_SOFT_SIGMA
         if(cfg.main_autovol_soft_sigma > 0.0) softSigma = cfg.main_autovol_soft_sigma;
      #endif
      #ifdef CFG_HAS_MAIN_AUTOVOL_HARD_SIGMA
         if(cfg.main_autovol_hard_sigma > 0.0) hardSigma = cfg.main_autovol_hard_sigma;
      #endif
      #ifdef CFG_HAS_MAIN_AUTOVOL_HARD_VETO
         hardVeto = (Config::Cfg_EnableHardGate(cfg) && cfg.main_autovol_hard_veto);
      #endif
   
      // 1) Return-volatility regime shaping
      const double sigma = av.ret_sigma_ann_pct;
      if(sigma > 0.0)
      {
         if(sigma >= hardSigma && hardVeto)
         {
            outOK  = false;
            outWhy = StringFormat("sigmaAnn=%.1f >= hard=%.1f", sigma, hardSigma);
            return;
         }
   
         if(sigma >= softSigma)
         {
            outQualMult *= 0.90;
            outRiskMult *= 0.80;
            outWhy = StringFormat("sigmaAnn=%.1f >= soft=%.1f", sigma, softSigma);
         }
      }
   
      // 2) �Range already spent� shaping (avoid late-chase entries)
      const double used = av.day_range_used01; // (day_range / adr) in [0..]
      if(used > 0.0)
      {
         if(used >= 1.15)
         {
            outQualMult *= 0.85;
            outRiskMult *= 0.75;
         }
         else if(used >= 0.90)
         {
            outQualMult *= 0.92;
            outRiskMult *= 0.85;
         }
   
         if(outWhy != "") outWhy += "; ";
         outWhy += StringFormat("dayUsed=%.2f", used);
      }
   
      // Clamp (safety)
      if(outQualMult < 0.0) outQualMult = 0.0;
      if(outRiskMult < 0.0) outRiskMult = 0.0;
   }

   // -----------------------------------------------------------------------------
   // Scan alignment consumer policy (single owner in strategy layer)
   //
   // Purpose:
   // - Consume Confluence scanner output to avoid "dead scanner" syndrome.
   // - Default behavior is SOFT shaping (score/risk multipliers).
   // - Optional HARD veto only if you later wire cfg fields + CFG_HAS_* macros.
   // -----------------------------------------------------------------------------
   inline void Main_ScanAlign_Apply(const Settings        &cfg,
                                   const bool            enabled,
                                   const string          sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction       dir,
                                   double                &outQualMult,
                                   double                &outRiskMult,
                                   bool                  &outOK,
                                   bool                  &outHardVeto,
                                   string                &outWhy)
   {
      outQualMult  = 1.0;
      outRiskMult  = 1.0;
      outOK        = true;
      outHardVeto  = false;
      outWhy       = "";
   
      if(!enabled)
      {
         outWhy = "scanAlign:disabled";
         return;
      }
   
      // Defaults (safe). You can later override via cfg fields if you add them.
      double softQual = 0.90;
      double softRisk = 0.95;
      bool   hardVeto = false;
   
      // Optional config wiring (compile-safe: only active if these exist)
      #ifdef CFG_HAS_MAIN_SCANALIGN_SOFT_MULT
         if(cfg.main_scanalign_soft_mult > 0.0 && cfg.main_scanalign_soft_mult <= 1.0)
            softQual = cfg.main_scanalign_soft_mult;
      #endif
      #ifdef CFG_HAS_MAIN_SCANALIGN_SOFT_RISK_MULT
         if(cfg.main_scanalign_soft_risk_mult > 0.0 && cfg.main_scanalign_soft_risk_mult <= 1.0)
            softRisk = cfg.main_scanalign_soft_risk_mult;
      #endif
      #ifdef CFG_HAS_MAIN_SCANALIGN_HARD_VETO
         hardVeto = (Config::Cfg_EnableHardGate(cfg) && cfg.main_scanalign_hard_veto);
      #endif
   
      const bool ok = Gate::Pass_ScanAlign(cfg, sym, tf, dir);
   
      if(ok)
      {
         outWhy = "scanAlign:ok";
         return;
      }
   
      outWhy = "scanAlign:miss";
   
      if(hardVeto)
      {
         outOK       = false;
         outHardVeto = true;
         return;
      }
   
      // Soft shaping only (default)
      outQualMult *= softQual;
      outRiskMult *= softRisk;
   }

   inline int _MainHyp_MinCategoryConfirmations(const Settings &cfg)
   {
      return Config::CfgMainStrategyRequiredCategoryConfirmations(cfg);
   }
   
   inline int _MainHyp_RequiredStructureMask(const Settings &cfg)
   {
      return Config::CfgMainStrategyRequiredStructureMask(cfg);
   }
   
   inline bool _MainHyp_AllowProxyDegrade(const Settings &cfg)
   {
      return Config::CfgMainStrategyAllowProxyDegrade(cfg);
   }

   inline bool _MainHyp_TransportObservabilityGap(const ISV::RawSignalBank_t &bank)
   {
      if(bank.degrade.hard_inst_block == 1)
         return false;

      if(bank.degrade.inst_partial == 1 ||
         bank.degrade.inst_unavailable == 1 ||
         bank.degrade.proxy_inst_available == 1)
         return true;

      if(bank.degrade.observability01 > 0.0 &&
         bank.degrade.observability01 < 0.75)
         return true;

      return false;
   }

   inline bool _MainHyp_CanonicalLiquidityEventPromoted(const ISV::LocationPass_t &loc)
   {
      return (loc.liquidity_event_time > 0 &&
              StringLen(loc.liquidity_event_type) > 0);
   }

   inline bool _MainHyp_CanonicalLiquidityEventPresent(const ISV::LocationPass_t &loc)
   {
      if(_MainHyp_CanonicalLiquidityEventPromoted(loc))
         return true;

      if(StringLen(loc.liquidity_event_type) > 0 && loc.sweep_score >= 0.25)
         return true;

      if(MathAbs(loc.sweep_dir) > 0 && loc.sweep_score >= 0.25)
         return true;

      if(StringLen(loc.liquidity_event_provenance) > 0 && loc.sweep_score >= 0.25)
         return true;

      return false;
   }

   inline bool _MainHyp_LocationPassContradictsNoEvent(const ISV::LocationPass_t &loc)
   {
      return (loc.pass == 1 &&
              loc.poi_score01 >= 0.20 &&
              loc.sweep_score >= 0.25);
   }

   inline bool _MainHyp_LiquidityMissingPromotedField(const ISV::LocationPass_t &loc)
   {
      if(_MainHyp_CanonicalLiquidityEventPromoted(loc))
         return false;

      if(!_MainHyp_CanonicalLiquidityEventPresent(loc))
         return false;

      if(StringLen(loc.liquidity_event_type) <= 0 ||
         loc.liquidity_event_time <= 0)
         return true;

      return false;
   }

   inline bool _MainHyp_LiquidityContextCoherent(const ISV::RawSignalBank_t &bank,
                                                 const CategorySelectedVector &sel,
                                                 const ISV::LocationPass_t &loc)
   {
      if(!bank.valid)
         return false;

      if(loc.pass == 1)
         return true;

      if(loc.poi_score01 >= 0.20)
         return true;

      if(loc.sweep_score >= 0.20)
         return true;

      if(bank.ms.poi_score01 >= 0.20)
         return true;

      if(bank.ms.liquidity_event_score01 >= 0.20)
         return true;

      if(StratBase::CountActiveSelectedCategories(sel) >= 2 &&
         MathAbs(bank.direction_dir11) > 0)
         return true;

      return false;
   }

   inline bool _MainHyp_RegimeContextCoherent(const ISV::RawSignalBank_t &bank,
                                              const CategorySelectedVector &sel,
                                              const ISV::LocationPass_t &loc)
   {
      if(!bank.valid)
         return false;

      if(sel.trend_active > 0 || sel.mom_active > 0)
         return true;

      if(sel.inst_active > 0 || sel.vol_active > 0 || sel.vola_active > 0)
         return true;

      if(loc.pass == 1 || loc.poi_score01 >= 0.20 || loc.sweep_score >= 0.20)
         return true;

      if(MathAbs(bank.direction_dir11) > 0)
         return true;

      return false;
   }

   inline bool _MainHyp_TesterCanSoftenRegime(const Settings &cfg,
                                              const ISV::RawSignalBank_t &bank,
                                              const CategorySelectedVector &sel,
                                              const ISV::LocationPass_t &loc)
   {
      if(!Main_CfgTesterRegimeObservabilitySoftening(cfg))
         return false;

      if(!_MainHyp_TransportObservabilityGap(bank))
         return false;

      if(!_MainHyp_RegimeContextCoherent(bank, sel, loc))
         return false;

      if(bank.degrade.hard_inst_block == 1)
         return false;

      return true;
   }

   inline bool _MainHyp_TesterCanSoftenLiquidity(const Settings &cfg,
                                                 const ISV::RawSignalBank_t &bank,
                                                 const CategorySelectedVector &sel,
                                                 const ISV::LocationPass_t &loc)
   {
      if(!Main_CfgTesterLiquidityObservabilitySoftening(cfg))
         return false;

      if(!_MainHyp_TransportObservabilityGap(bank))
         return false;

      if(!_MainHyp_LiquidityContextCoherent(bank, sel, loc))
         return false;

      if(bank.degrade.hard_inst_block == 1)
         return false;

      return true;
   }

   inline bool _MainHyp_TesterCanSoftenLocation(const Settings &cfg,
                                                const ISV::RawSignalBank_t &bank,
                                                const CategorySelectedVector &sel,
                                                const ISV::LocationPass_t &loc)
   {
      if(!Main_CfgTesterLooseGate(cfg))
      {
         return false;
      }

      if(bank.degrade.hard_inst_block == 1)
         return false;

      if(loc.poi_kind == 0)
         return false;

      if(loc.poi_score01 >= 0.20 || loc.sweep_score >= 0.20)
         return true;

      if(_MainHyp_CanonicalLiquidityEventPresent(loc))
         return true;

      if(_MainHyp_TransportObservabilityGap(bank) &&
         _MainHyp_RegimeContextCoherent(bank, sel, loc))
      {
         return true;
      }

      return false;
   }

   inline bool _MainHyp_ShouldRunWithReason(const Settings               &cfg,
                                            const ISV::RawSignalBank_t   &bank,
                                            const CategorySelectedVector &sel,
                                            const ISV::LocationPass_t    &loc,
                                            string                       &why)
   {
      why = "";

      if(!bank.valid)
      {
         why = "base_raw_bank_invalid";
         return false;
      }

      if(loc.pass <= 0)
      {
         why = "base_location_fail";
         return false;
      }

      if(!_MainHyp_CanonicalLiquidityEventPresent(loc))
      {
         if(_MainHyp_LiquidityMissingPromotedField(loc))
         {
            why = "main_liquidity_missing_promoted_field";
            return false;
         }

         if(_MainHyp_LocationPassContradictsNoEvent(loc))
         {
            why = "main_location_pass_contradicts_no_event";
            return false;
         }

         if(_MainHyp_TransportObservabilityGap(bank) &&
            _MainHyp_LiquidityContextCoherent(bank, sel, loc))
         {
            why = "main_liquidity_observability_degraded";
            return false;
         }

         why = "main_liquidity_true_no_event";
         return false;
      }

      if(StratBase::CountActiveSelectedCategories(sel) < _MainHyp_MinCategoryConfirmations(cfg))
      {
         why = "base_insufficient_category_confirmations";
         return false;
      }

      if(bank.degrade.hard_inst_block == 1)
      {
         why = "base_hard_institutional_block";
         return false;
      }

      const double spread01 = _MainClamp01(MathAbs(loc.spread_shock_z) / 3.0);
      const double slip01   = _MainClamp01(MathAbs(loc.slippage_z) / 3.0);
      const double depth01  = _MainClamp01(MathAbs(loc.depth_fade_z) / 3.0);

      if(spread01 > cfg.strat_exec_max_spread_shock01 ||
         slip01   > cfg.strat_exec_max_spread_shock01)
      {
         why = "base_spread_slippage_block";
         return false;
      }

      if(depth01 > cfg.strat_exec_max_depth_fade01)
      {
         why = "base_depth_shock_block";
         return false;
      }

      if(bank.degrade.inst_unavailable == 1 &&
         bank.degrade.proxy_inst_available == 0 &&
         !_MainHyp_AllowProxyDegrade(cfg) &&
         !_MainHyp_TesterCanSoftenRegime(cfg, bank, sel, loc))
      {
         why = "main_inst_unavailable_no_proxy";
         return false;
      }

      if(sel.trend_active <= 0 && sel.mom_active <= 0 &&
          !_MainHyp_TesterCanSoftenRegime(cfg, bank, sel, loc))
       {
          if(_MainHyp_TransportObservabilityGap(bank) &&
             _MainHyp_RegimeContextCoherent(bank, sel, loc))
          {
             why = "stage=regime softened=0 reason=main_regime_unavailable_degraded_observability";
             return false;
          }

          why = "stage=regime softened=0 reason=main_structural_bias_missing";
          return false;
       }

      why = "main_should_run_ok";
      return true;
   }

   enum MainHypBiasReasonBits
   {
      MAIN_BIAS_NONE        = 0,
      MAIN_BIAS_MANUAL      = 1,
      MAIN_BIAS_HTF_PHASE   = 2,
      MAIN_BIAS_INST        = 4,
      MAIN_BIAS_TREND       = 8
   };

   enum MainHypSetupClassLocal
   {
      MAIN_SETUP_CLASS_NONE            = 0,
      MAIN_SETUP_CLASS_CONTINUATION    = 1,
      MAIN_SETUP_CLASS_REVERSAL        = 2,
      MAIN_SETUP_CLASS_ACCUM_BREAKOUT  = 3,
      MAIN_SETUP_CLASS_DIST_BREAKDOWN  = 4,
      MAIN_SETUP_CLASS_MEAN_RECLAIM    = 5
   };

   struct MainHypStageState
   {
      Direction dir;
      uint      bias_reason_mask;

      bool      direction_seed_pass;
      bool      regime_pass;
      bool      location_pass;
      bool      liquidity_pass;
      bool      institutional_pass;
      bool      volume_pass;
      bool      trigger_pass;
      bool      execution_pass;

      bool      regime_softened;
      bool      location_softened;
      bool      liquidity_softened;
      bool      trigger_softened;

      int       setup_class;
      int       poi_kind;
      int       liquidity_event_type;
      int       inst_source;
      int       degrade_acceptance;
      int       execution_style;
      int       risk_template;

      double    poi_lo;
      double    poi_hi;
      double    rr_min;

      double    regime_score;
      double    location_score;
      double    liquidity_score;
      double    micro_score;
      double    volume_score;
      double    pattern_score;
      double    execution_score;
      double    final_quality01;
      double    confidence01;

      double    score_penalty_mult;
      double    confidence_penalty_mult;

      string    trigger_soft_tag;
      string    reason;

      void Reset()
      {
         dir                 = DIR_BOTH;
         bias_reason_mask    = MAIN_BIAS_NONE;

         direction_seed_pass = false;
         regime_pass         = false;
         location_pass       = false;
         liquidity_pass      = false;
         institutional_pass  = false;
         volume_pass         = false;
         trigger_pass        = false;
         execution_pass      = false;

         regime_softened     = false;
         location_softened   = false;
         liquidity_softened  = false;
         trigger_softened    = false;

         setup_class         = MAIN_SETUP_CLASS_NONE;
         poi_kind            = 0;
         liquidity_event_type= 0;
         inst_source         = INST_SIGNAL_SOURCE_NONE;
         degrade_acceptance  = STRAT_DEGRADE_ALLOW_PROXY;
         execution_style     = STRAT_EXEC_STYLE_DEFAULT;
         risk_template       = STRAT_RISK_TEMPLATE_DEFAULT;

         poi_lo              = 0.0;
         poi_hi              = 0.0;
         rr_min              = 0.0;

         regime_score        = 0.0;
         location_score      = 0.0;
         liquidity_score     = 0.0;
         micro_score         = 0.0;
         volume_score        = 0.0;
         pattern_score       = 0.0;
         execution_score     = 0.0;
         final_quality01     = 0.0;
         confidence01        = 0.0;

         score_penalty_mult      = 1.0;
         confidence_penalty_mult = 1.0;

         trigger_soft_tag    = "";
         reason              = "";
      }
   };

   inline bool _MainHyp_TriggerWhyHasToken(const string why,
                                           const string token)
   {
      if(StringLen(token) <= 0)
         return false;

      return (StringFind(why, token) >= 0);
   }

   inline bool _MainHyp_TesterCanSoftenTrigger(const Settings             &cfg,
                                               const ISV::RawSignalBank_t &bank,
                                               const MainHypStageState    &st)
   {
      if(!Main_CfgTesterTriggerSofteningActive(cfg))
         return false;

      if(Main_CfgTesterLooseGate(cfg))
         return false;

      if(bank.degrade.hard_inst_block == 1)
         return false;

      if(!st.regime_pass)
         return false;

      if(!st.location_pass)
         return false;

      if(!st.liquidity_pass)
         return false;

      if(!st.volume_pass)
         return false;

      return true;
   }

   inline string _MainHyp_ResolveTriggerSoftTag(const string why,
                                                const MainHypStageState &st)
   {
      if(_MainHyp_TriggerWhyHasToken(why, "noPOI") && st.location_softened)
         return "main_location_soft_penalty";

      if(_MainHyp_TriggerWhyHasToken(why, "noPOI"))
         return "main_no_poi_soft";

      if(_MainHyp_TriggerWhyHasToken(why, "noLiqEvent"))
         return "main_no_liq_soft";

      if(_MainHyp_TriggerWhyHasToken(why, "noStruct") && st.regime_softened)
         return "main_trigger_blocked_soft";

      return "";
   }

   inline bool _MainHyp_TrySoftenTriggerBlock(const Settings             &cfg,
                                              const ISV::RawSignalBank_t &bank,
                                              MainHypStageState          &st,
                                              string                     &why)
   {
      if(!_MainHyp_TesterCanSoftenTrigger(cfg, bank, st))
         return false;

      const string softTag =
         _MainHyp_ResolveTriggerSoftTag(why, st);

      if(softTag == "")
         return false;

      double scorePen = 0.90;
      double confPen  = 0.85;

      if(softTag == "main_location_soft_penalty")
      {
         scorePen = 0.95;
         confPen  = 0.90;
      }
      else if(softTag == "main_no_poi_soft")
      {
         scorePen = 0.92;
         confPen  = 0.88;
      }
      else if(softTag == "main_no_liq_soft")
      {
         scorePen = 0.90;
         confPen  = 0.84;
      }
      else if(softTag == "main_trigger_blocked_soft")
      {
         scorePen = 0.88;
         confPen  = 0.80;
      }

      st.trigger_softened = true;
      st.trigger_soft_tag = softTag;

      st.score_penalty_mult      *= scorePen;
      st.confidence_penalty_mult *= confPen;

      why = StringFormat("stage=trigger softened=1 reason=%s qpen=%.2f cpen=%.2f src=%s",
                         softTag,
                         scorePen,
                         confPen,
                         why);

      return true;
   }

   inline ENUM_TRADE_DIRECTION _MainHyp_ToTDIR(const Direction dir)
   {
      if(dir == DIR_BUY)  return TDIR_BUY;
      if(dir == DIR_SELL) return TDIR_SELL;
      return TDIR_BOTH;
   }

   inline uint _MainHyp_SelectedCategoryMask(const CategorySelectedVector &sel)
   {
      uint m = 0;
      if(sel.inst_active > 0)  m |= 1;
      if(sel.trend_active > 0) m |= 2;
      if(sel.mom_active > 0)   m |= 4;
      if(sel.vol_active > 0)   m |= 8;
      if(sel.vola_active > 0)  m |= 16;
      return m;
   }

   inline bool _MainHyp_DirectionSeed(const Settings               &cfg,
                                      const ICT_Context            &ctx,
                                      const ISV::RawSignalBank_t   &bank,
                                      const CategorySelectedVector &sel,
                                      MainHypStageState            &st,
                                      string                       &why)
   {
      int buyVotes  = 0;
      int sellVotes = 0;

      if(cfg.trade_direction_selector == TDIR_BUY)
      {
         buyVotes += 4;
         st.bias_reason_mask |= MAIN_BIAS_MANUAL;
      }
      else if(cfg.trade_direction_selector == TDIR_SELL)
      {
         sellVotes += 4;
         st.bias_reason_mask |= MAIN_BIAS_MANUAL;
      }

      if(ctx.allowedDirection == TDIR_BUY)
      {
         buyVotes += 2;
         st.bias_reason_mask |= MAIN_BIAS_HTF_PHASE;
      }
      else if(ctx.allowedDirection == TDIR_SELL)
      {
         sellVotes += 2;
         st.bias_reason_mask |= MAIN_BIAS_HTF_PHASE;
      }

      if(Ctx_PrefersDir_Soft(ctx, DIR_BUY))
      {
         buyVotes += 1;
         st.bias_reason_mask |= MAIN_BIAS_HTF_PHASE;
      }
      if(Ctx_PrefersDir_Soft(ctx, DIR_SELL))
      {
         sellVotes += 1;
         st.bias_reason_mask |= MAIN_BIAS_HTF_PHASE;
      }

      if(sel.inst_active > 0)
      {
         if(sel.inst_z > 0.05)      buyVotes += 2;
         else if(sel.inst_z < -0.05) sellVotes += 2;
         st.bias_reason_mask |= MAIN_BIAS_INST;
      }

      if(sel.trend_active > 0)
      {
         if(sel.trend_z > 0.05)      buyVotes += 1;
         else if(sel.trend_z < -0.05) sellVotes += 1;
         st.bias_reason_mask |= MAIN_BIAS_TREND;
      }

      if(bank.direction_dir11 > 0)      buyVotes += 1;
      else if(bank.direction_dir11 < 0) sellVotes += 1;

      if(buyVotes == sellVotes)
      {
         why = "direction_seed_tie";
         return false;
      }

      st.dir = (buyVotes > sellVotes ? DIR_BUY : DIR_SELL);
      st.direction_seed_pass = true;
      why = (st.dir == DIR_BUY ? "direction_seed_buy" : "direction_seed_sell");
      return true;
   }

   inline bool _MainHyp_RegimeStage(const string                  sym,
                                    const ENUM_TIMEFRAMES         tf,
                                    const Settings               &cfg,
                                    const ICT_Context            &ctx,
                                    const ISV::RawSignalBank_t   &bank,
                                    const CategorySelectedVector &sel,
                                    const ISV::LocationPass_t    &loc,
                                    MainHypStageState            &st,
                                    string                       &why)
   {
      const bool structOK = HasMarketStructure(sym, tf, st.dir, cfg);
      const bool ctxPref  = Ctx_PrefersDir_Soft(ctx, st.dir);

      const double diEdge =
         (st.dir == DIR_BUY
            ? (bank.plus_di - bank.minus_di)
            : (bank.minus_di - bank.plus_di));

      const double trend01 =
         _MainClamp01(0.5 + 0.5 * _MainClamp11(diEdge / 25.0));

      const bool directionalBiasPresent =
         (st.dir == DIR_BUY
            ? (bank.direction_dir11 > 0 || sel.trend_z > 0.05 || sel.mom_z > 0.05)
            : (bank.direction_dir11 < 0 || sel.trend_z < -0.05 || sel.mom_z < -0.05));

      const bool structuralBiasMissing = (!ctxPref && !directionalBiasPresent);
      const bool observabilityGap      = _MainHyp_TransportObservabilityGap(bank);
      const bool testerSoftPass        = _MainHyp_TesterCanSoftenRegime(cfg, bank, sel, loc);

      st.regime_score =
         _MainClamp01((structOK ? 0.45 : 0.0) +
                      (ctxPref  ? 0.35 : 0.0) +
                      (0.20 * trend01));

      if(st.dir == DIR_BUY)
      {
         if(ctx.wySpringCandidate)
            st.setup_class = MAIN_SETUP_CLASS_REVERSAL;
         else if(Ctx_AMDPhase_H1(ctx) == AMD_PHASE_ACCUM || Ctx_AMDPhase_H4(ctx) == AMD_PHASE_ACCUM)
            st.setup_class = MAIN_SETUP_CLASS_ACCUM_BREAKOUT;
         else
            st.setup_class = MAIN_SETUP_CLASS_CONTINUATION;
      }
      else
      {
         if(ctx.wyUTADCandidate)
            st.setup_class = MAIN_SETUP_CLASS_REVERSAL;
         else if(Ctx_AMDPhase_H1(ctx) == AMD_PHASE_DIST || Ctx_AMDPhase_H4(ctx) == AMD_PHASE_DIST)
            st.setup_class = MAIN_SETUP_CLASS_DIST_BREAKDOWN;
         else
            st.setup_class = MAIN_SETUP_CLASS_CONTINUATION;
      }

      st.regime_softened = false;

      if(structOK && st.regime_score >= 0.45)
      {
         st.regime_pass = true;
         why = StringFormat("stage=regime softened=0 reason=regime_ok score=%.2f",
                             st.regime_score);
         return true;
      }

      if(testerSoftPass && !structuralBiasMissing)
      {
         st.regime_pass = true;
         st.regime_softened = true;
         st.regime_score = MathMax(st.regime_score, 0.45);
         why = StringFormat("stage=regime softened=1 reason=regime_softened_tester_observability score=%.2f",
                             st.regime_score);
         return true;
      }

      st.regime_pass = false;

      if(structuralBiasMissing)
      {
         why = "stage=regime softened=0 reason=structural_bias_missing";
         return false;
      }

      if(observabilityGap && _MainHyp_RegimeContextCoherent(bank, sel, loc))
      {
         if(Main_IsTesterRuntime() &&
            !Main_CfgTesterRegimeObservabilitySoftening(cfg))
         {
            why = "stage=regime softened=0 reason=regime_observability_softening_not_active tester_stage_softening_disabled";
            return false;
         }

         why = "stage=regime softened=0 reason=regime_unavailable_degraded_observability";
         return false;
      }

      why = StringFormat("stage=regime softened=0 reason=regime_true_structure_fail score=%.2f",
                          st.regime_score);
      return false;
   }

   inline bool _MainHyp_LocationStage(const Settings               &cfg,
                                      const ISV::RawSignalBank_t   &bank,
                                      const CategorySelectedVector &sel,
                                      const ISV::LocationPass_t    &loc,
                                      MainHypStageState            &st,
                                      string                       &why)
   {
      st.poi_kind = loc.poi_kind;
      st.location_softened = false;

      const double point = SymbolInfoDouble(bank.symbol, SYMBOL_POINT);
      const double halfBand =
         MathMax(bank.atr_price * 0.25,
                 (point > 0.0 ? 25.0 * point : 0.0));

      const double anchorPx =
         (loc.liquidity_event_price > 0.0 ? loc.liquidity_event_price : bank.close0);

      st.poi_lo = anchorPx - halfBand;
      st.poi_hi = anchorPx + halfBand;

      st.location_score =
         _MainClamp01((0.60 * loc.poi_score01) +
                      (0.20 * _MainClamp01(1.0 - MathMin(loc.poi_distance_atr01, 1.0))) +
                      (0.20 * _MainClamp01(loc.sweep_score)));

      const bool strictLocationPass =
         (loc.pass == 1 &&
          st.poi_kind != 0 &&
          st.location_score >= 0.35);

      const bool testerSoftPass =
         _MainHyp_TesterCanSoftenLocation(cfg, bank, sel, loc);

      const bool relaxedLocationContext =
         (st.poi_kind != 0 &&
          st.location_score >= 0.20 &&
          (loc.poi_score01 >= 0.20 ||
           loc.sweep_score >= 0.20 ||
           _MainHyp_CanonicalLiquidityEventPresent(loc)));

      st.location_pass = strictLocationPass;

      if(!st.location_pass &&
         testerSoftPass &&
         relaxedLocationContext)
      {
         st.location_pass = true;
         st.location_softened = true;
         st.location_score = MathMax(st.location_score, 0.35);

         st.score_penalty_mult      *= 0.94;
         st.confidence_penalty_mult *= 0.92;
      }

      if(st.location_pass)
      {
         if(st.location_softened)
         {
            why = StringFormat("stage=location softened=1 reason=main_location_soft_penalty loc.pass=%d poi_kind=%d score=%.2f poi=%.2f sweep=%.2f",
                               loc.pass,
                               st.poi_kind,
                               st.location_score,
                               loc.poi_score01,
                               loc.sweep_score);
            return true;
         }

         why = StringFormat("stage=location softened=0 reason=location_ok loc.pass=%d poi_kind=%d score=%.2f poi=%.2f sweep=%.2f",
                            loc.pass,
                            st.poi_kind,
                            st.location_score,
                            loc.poi_score01,
                            loc.sweep_score);
         return true;
      }

      if(loc.pass == 1 && st.poi_kind == 0 && loc.poi_score01 >= 0.20)
      {
         why = StringFormat("stage=location softened=0 reason=location_pass_without_poi_kind loc.pass=%d poi_kind=%d score=%.2f poi=%.2f sweep=%.2f",
                            loc.pass,
                            st.poi_kind,
                            st.location_score,
                            loc.poi_score01,
                            loc.sweep_score);
         return false;
      }

      if(Main_IsTesterRuntime() &&
         !Main_CfgTesterLooseGate(cfg) &&
         (loc.poi_score01 >= 0.20 || loc.sweep_score >= 0.20))
      {
         why = StringFormat("stage=location softened=0 reason=tester_stage_softening_disabled loc.pass=%d poi_kind=%d score=%.2f poi=%.2f sweep=%.2f",
                            loc.pass,
                            st.poi_kind,
                            st.location_score,
                            loc.poi_score01,
                            loc.sweep_score);
         return false;
      }

      why = StringFormat("stage=location softened=0 reason=location_blocked loc.pass=%d poi_kind=%d score=%.2f poi=%.2f sweep=%.2f",
                         loc.pass,
                         st.poi_kind,
                         st.location_score,
                         loc.poi_score01,
                         loc.sweep_score);
      return false;
   }

   inline bool _MainHyp_LiquidityStage(const Settings               &cfg,
                                       const ISV::RawSignalBank_t   &bank,
                                       const CategorySelectedVector &sel,
                                       const ISV::LocationPass_t    &loc,
                                       MainHypStageState            &st,
                                       string                       &why)
   {
      const bool promotedEvent            = _MainHyp_CanonicalLiquidityEventPromoted(loc);
      const bool canonicalEventPresent    = _MainHyp_CanonicalLiquidityEventPresent(loc);
      const bool missingPromotedField     = _MainHyp_LiquidityMissingPromotedField(loc);
      const bool observabilityGap         = _MainHyp_TransportObservabilityGap(bank);
      const bool contextCoherent          = _MainHyp_LiquidityContextCoherent(bank, sel, loc);
      const bool locationContradictsNoEvt = _MainHyp_LocationPassContradictsNoEvent(loc);
      const bool testerSoftPass           = _MainHyp_TesterCanSoftenLiquidity(cfg, bank, sel, loc);

      st.liquidity_score =
         _MainClamp01((0.65 * _MainClamp01(loc.sweep_score)) +
                      (0.20 * (canonicalEventPresent ? 1.0 : 0.0)) +
                      (0.15 * _MainClamp01(1.0 - MathMin(MathAbs(loc.liquidity_gap), 1.0))));

      st.liquidity_event_type = (canonicalEventPresent ? 1 : 0);
      st.liquidity_softened = false;

      if(st.location_pass && canonicalEventPresent)
      {
         st.liquidity_pass = true;
         why = "stage=liquidity softened=0 reason=liquidity_ok";
         return true;
      }

      if(testerSoftPass &&
         contextCoherent &&
         (missingPromotedField || observabilityGap || locationContradictsNoEvt))
      {
         st.liquidity_pass = true;
         st.liquidity_softened = true;
         st.liquidity_event_type = 1;
         st.liquidity_score = MathMax(st.liquidity_score, 0.35);

         st.score_penalty_mult      *= 0.92;
         st.confidence_penalty_mult *= 0.88;

         why = "stage=liquidity softened=1 reason=main_no_liq_soft";
         return true;
      }

      st.liquidity_pass = false;

      if(missingPromotedField)
      {
         why = "liquidity_missing_promoted_field";
         return false;
      }

      if(locationContradictsNoEvt)
      {
         why = "liquidity_location_pass_contradicts_no_event";
         return false;
      }

      if(observabilityGap && contextCoherent)
      {
         why = "liquidity_observability_degraded";
         return false;
      }

      why = "liquidity_true_no_event";
      return false;
   }

   inline bool _MainHyp_InstitutionalStage(const Settings               &cfg,
                                           const ISV::RawSignalBank_t   &bank,
                                           const CategorySelectedVector &sel,
                                           MainHypStageState            &st,
                                           string                       &why)
   {
      const bool hardBlock  = (bank.degrade.hard_inst_block == 1);
      const bool directInst = (bank.degrade.inst_available == 1 &&
                               bank.degrade.inst_sel_source == INST_SIGNAL_SOURCE_DIRECT);
      const bool proxyInst  = (bank.degrade.proxy_inst_available == 1 ||
                               bank.degrade.inst_sel_source == INST_SIGNAL_SOURCE_PROXY);

      st.inst_source =
         (directInst ? INST_SIGNAL_SOURCE_DIRECT :
          (proxyInst ? INST_SIGNAL_SOURCE_PROXY : INST_SIGNAL_SOURCE_NONE));

      const double instDir01 =
         (sel.inst_active > 0 ? _MainClamp11(sel.inst_z) : 0.0);

      const double microDir01 =
         _MainClamp11((0.55 * bank.ms.ofi_norm) +
                      (0.35 * bank.ms.obi_norm) +
                      (0.10 * _MainClamp11(bank.ms.cvd)));

      const bool dirOK =
         (st.dir == DIR_BUY
            ? (instDir01 >= -0.10 && microDir01 >= -0.10)
            : (instDir01 <= 0.10  && microDir01 <= 0.10));

      st.micro_score =
         _MainClamp01((0.40 * _MainClamp01(MathAbs(instDir01))) +
                      (0.35 * _MainClamp01(MathAbs(microDir01))) +
                      (0.25 * _MainClamp01(1.0 - bank.ms.vpin)));

      if(hardBlock)
      {
         st.degrade_acceptance = STRAT_DEGRADE_REJECT;
         st.institutional_pass = false;
         why = "institutional_hard_block";
         return false;
      }

      if(directInst)
      {
         st.degrade_acceptance = STRAT_DEGRADE_REJECT;
         st.institutional_pass = dirOK;
         why = (st.institutional_pass ? "institutional_direct_ok" : "institutional_direct_conflict");
         return st.institutional_pass;
      }

      if(proxyInst)
      {
         st.degrade_acceptance = STRAT_DEGRADE_ALLOW_PROXY;
         st.institutional_pass = (_MainHyp_AllowProxyDegrade(cfg) && dirOK);
         st.micro_score *= 0.85;
         why = (st.institutional_pass ? "institutional_proxy_ok" : "institutional_proxy_blocked");
         return st.institutional_pass;
      }

      st.degrade_acceptance = STRAT_DEGRADE_ALLOW_STRUCTURE_ONLY;
      st.institutional_pass = false;
      why = "institutional_none";
      return false;
   }

   inline bool _MainHyp_VolumeStage(const ISV::RawSignalBank_t   &bank,
                                    const CategorySelectedVector &sel,
                                    MainHypStageState            &st,
                                    string                       &why)
   {
      const double volDir01 =
         _MainClamp11((0.45 * sel.vol_z) +
                      (0.35 * _MainClamp11(bank.ms.footprint_delta)) +
                      (0.20 * _MainClamp11(bank.ms.va_state)));

      const bool dirOK =
         (st.dir == DIR_BUY ? (volDir01 >= -0.10) : (volDir01 <= 0.10));

      st.volume_score =
         _MainClamp01((0.35 * _MainClamp01(MathAbs(sel.vol_z))) +
                      (0.35 * _MainClamp01(MathAbs(bank.ms.footprint_delta))) +
                      (0.15 * _MainClamp01(1.0 - MathMin(MathAbs(bank.ms.poc_dist_atr), 1.0))) +
                      (0.15 * _MainClamp01(MathAbs(bank.ms.va_state))));

      st.volume_pass =
         (((sel.vol_active > 0) ||
           (MathAbs(bank.ms.footprint_delta) > 0.10) ||
           (MathAbs(bank.ms.va_state) > 0.10)) && dirOK);

      why = (st.volume_pass ? "volume_ok" : "volume_blocked");
      return st.volume_pass;
   }

   inline bool _MainHyp_TriggerStage(const string                 sym,
                                     const ENUM_TIMEFRAMES       tf,
                                     const Settings             &cfg,
                                     const ISV::RawSignalBank_t &bank,
                                     const ICT_Context          &ctx,
                                     MainFusedHeads             &heads,
                                     MainHypStageState          &st,
                                     string                     &why)
   {
      const double classicalProxy = MathMax(st.location_score, st.liquidity_score);

      bool triggerOK = false;
      if(st.dir == DIR_BUY)
         triggerOK = EvaluateBuyTrigger(sym, ctx, heads.have_entry_scan, heads.entry_scan,
                                        heads.have_ofds, heads.ofds, classicalProxy, cfg, why);
      else
         triggerOK = EvaluateSellTrigger(sym, ctx, heads.have_entry_scan, heads.entry_scan,
                                         heads.have_ofds, heads.ofds, classicalProxy, cfg, why);

      if(!triggerOK)
      {
         if(_MainHyp_TrySoftenTriggerBlock(cfg, bank, st, why))
            triggerOK = true;
      }

      bool momentumOK = false;
      if(!triggerOK && heads.have_entry_scan)
      {
         momentumOK = StratScan::MACD_CrossUsingScan(sym, tf, st.dir, heads.entry_scan);
         if(momentumOK)
            why = "trigger_momentum_macd";
      }

      st.pattern_score =
         _MainClamp01((triggerOK  ? 0.70 : 0.0) +
                      (momentumOK ? 0.20 : 0.0) +
                      (heads.have_auto ? 0.10 : 0.0));

      if(st.trigger_softened)
         st.pattern_score = _MainClamp01(st.pattern_score * 0.75);

      st.trigger_pass = (triggerOK || momentumOK);

      if(!st.trigger_pass)
      {
         if(StringLen(why) > 0)
            why = StringFormat("stage=trigger softened=0 reason=main_trigger_blocked_hard src=%s",
                               why);
         else
            why = "stage=trigger softened=0 reason=main_trigger_blocked_hard";
      }

      return st.trigger_pass;
   }

   inline bool _MainHyp_ExecutionStage(const Settings             &cfg,
                                       const ISV::RawSignalBank_t &bank,
                                       const ISV::LocationPass_t  &loc,
                                       MainHypStageState          &st,
                                       string                     &why)
   {
      const double spread01 = _MainClamp01(MathAbs(loc.spread_shock_z) / 3.0);
      const double slip01   = _MainClamp01(MathAbs(loc.slippage_z) / 3.0);
      const double depth01  = _MainClamp01(MathAbs(loc.depth_fade_z) / 3.0);
      const double resil01  = _MainClamp01(bank.ms.resiliency);

      st.execution_style = STRAT_EXEC_STYLE_DEFAULT;
      st.risk_template   = STRAT_RISK_TEMPLATE_DEFAULT;
      st.rr_min          = 1.50;

      st.execution_score =
         _MainClamp01((0.35 * resil01) +
                      (0.20 * (1.0 - spread01)) +
                      (0.20 * (1.0 - slip01)) +
                      (0.15 * (1.0 - depth01)) +
                      (0.10 * _MainClamp01(1.0 - bank.ms.vpin)));

      st.execution_pass =
         (resil01 >= cfg.strat_exec_min_resiliency01 &&
          depth01 <= cfg.strat_exec_max_depth_fade01 &&
          spread01 <= cfg.strat_exec_max_spread_shock01);

      why = (st.execution_pass ? "execution_ok" : "execution_blocked");
      return st.execution_pass;
   }

   inline double _MainHyp_WeightedQuality(const Settings      &cfg,
                                          const MainHypStageState &st,
                                          const StratScore    &ss)
   {
      const double stagedQ =
         _MainClamp01((cfg.strat_w_location       * st.location_score) +
                      (cfg.strat_w_liquidity      * st.liquidity_score) +
                      (cfg.strat_w_microstructure * st.micro_score) +
                      (cfg.strat_w_volume         * st.volume_score) +
                      (cfg.strat_w_pattern        * st.pattern_score) +
                      (cfg.strat_w_execution      * st.execution_score));

      const double alpha01 = Main_StratAlpha01(ss);
      return _MainClamp01((0.65 * stagedQ) + (0.35 * alpha01));
   }

   inline double _MainHyp_StageRiskBufferPrice(const string sym,
                                               const ISV::RawSignalBank_t &bank)
   {
      const double point = SymbolInfoDouble((sym != "" ? sym : _Symbol), SYMBOL_POINT);
      const double atr = MathMax(bank.atr_price, MathAbs(bank.high0 - bank.low0) * 0.50);
      return MathMax(atr * 0.15, (point > 0.0 ? 25.0 * point : 0.0));
   }

   inline void _MainHyp_ApplyRiskShape(const ISV::RawSignalBank_t &bank,
                                       const MainHypStageState    &st,
                                       StrategyHypothesis_t       &out)
   {
      const string sym = (bank.symbol != "" ? bank.symbol : _Symbol);
      const double min_buffer = _MainHyp_StageRiskBufferPrice(sym, bank);
      const double min_rr = MathMax(st.rr_min, 1.0);

      double entry = out.entry_price;
      if(entry <= 0.0)
         entry = bank.close0;

      if(st.dir == DIR_BUY)
      {
         double stop = (st.poi_lo > 0.0 ? st.poi_lo - min_buffer : entry - min_buffer);
         if(stop >= entry)
            stop = entry - min_buffer;

         const double risk = MathMax(entry - stop, min_buffer);
         double target = entry + (risk * min_rr);
         if(target <= entry)
            target = entry + MathMax(risk, min_buffer);

         out.entry_price = entry;
         out.stop_loss = stop;
         out.take_profit = target;
         return;
      }

      double stop = (st.poi_hi > 0.0 ? st.poi_hi + min_buffer : entry + min_buffer);
      if(stop <= entry)
         stop = entry + min_buffer;

      const double risk = MathMax(stop - entry, min_buffer);
      double target = entry - (risk * min_rr);
      if(target >= entry)
         target = entry - MathMax(risk, min_buffer);

      out.entry_price = entry;
      out.stop_loss = stop;
      out.take_profit = target;
   }

   inline bool _MainHyp_RiskShapeValid(const MainHypStageState &st,
                                       const StrategyHypothesis_t &out,
                                       string &why)
   {
      why = "";

      if(out.entry_price <= 0.0 ||
         out.stop_loss <= 0.0 ||
         out.take_profit <= 0.0)
      {
         why = "main_risk_shape_missing_prices";
         return false;
      }

      if(st.dir == DIR_BUY)
      {
         if(!(out.stop_loss < out.entry_price &&
              out.take_profit > out.entry_price))
         {
            why = "main_risk_shape_buy_ordering";
            return false;
         }

         return true;
      }

      if(!(out.take_profit < out.entry_price &&
           out.stop_loss > out.entry_price))
      {
         why = "main_risk_shape_sell_ordering";
         return false;
      }

      return true;
   }

   inline void _MainHyp_FinalizeHypothesis(const ISV::RawSignalBank_t &bank,
                                           const CategorySelectedVector &sel,
                                           const Settings &cfg,
                                           const MainHypStageState &st,
                                           const StratScore &ss,
                                           const ConfluenceBreakdown &bd,
                                           StrategyHypothesis_t &out)
   {
      StratBase::SeedHypothesisDefaults((StrategyID)STRAT_MAIN_ID, st.dir, bank, sel, out);

      out.required_category_confirmations = _MainHyp_MinCategoryConfirmations(cfg);
      out.required_structure_mask         = _MainHyp_RequiredStructureMask(cfg);

      out.intended_direction = _MainHyp_ToTDIR(st.dir);

      out.poi_type  = st.poi_kind;
      out.poi_lo    = st.poi_lo;
      out.poi_hi    = st.poi_hi;

      out.entry_price        = 0.5 * (st.poi_lo + st.poi_hi);
      out.execution_style    = st.execution_style;
      out.risk_template      = st.risk_template;
      out.degrade_acceptance = st.degrade_acceptance;

      out.rr_min             = st.rr_min;
      out.quality_score      = st.final_quality01;
      out.confidence_score   = st.confidence01;

      _MainHyp_ApplyRiskShape(bank, st, out);

      out.armed = true;
      out.dir   = (st.dir == DIR_BUY ? 1 : -1);
      out.setup_class = st.setup_class;

      out.location_pass         = (st.location_pass ? 1 : 0);
      out.stack_required_votes  = _MainHyp_MinCategoryConfirmations(cfg);
      out.stack_actual_votes    = StratBase::CountActiveSelectedCategories(sel);

      out.category_mask_required = 0;
      out.category_mask_passed   = _MainHyp_SelectedCategoryMask(sel);

      out.inst_source           = bank.degrade.inst_sel_source;
      out.liquidity_event_type  = st.liquidity_event_type;

      out.entry_model = 0;
      out.exec_style  = st.execution_style;
      out.stop_model  = 0;
      out.tp_model    = 0;

      out.alpha_local      = Main_StratAlpha01(ss);
      out.risk_local       = Main_StratRisk01(ss);
      out.confidence_local = st.confidence01;

      out.veto_mask  = (bd.veto ? 1 : 0);
      out.debug_mask = st.bias_reason_mask;

      out.invalidation_reason = st.reason;
      out.veto_reason         = (bd.veto ? "main_bd_veto" : "");
   }

   class Strat_MainTradingLogic : public StrategyBase
     {
     public:
       Strat_MainTradingLogic() {}

       virtual string Name() const
       {
          return STRAT_MAIN_NAME;
       }

       virtual StrategyID Id() const
       {
          return (StrategyID)STRAT_MAIN_ID;
       }

       virtual bool ShouldRun(const ISV::RawSignalBank_t &bank,
                              const CategorySelectedVector &sel,
                              const ISV::LocationPass_t &loc) const
       {
          if(!StrategyBase::ShouldRun(bank, sel, loc))
             return false;

          if(StratBase::CountActiveSelectedCategories(sel) < _MainHyp_MinCategoryConfirmations(m_cfg))
             return false;

          if(bank.degrade.hard_inst_block == 1)
             return false;

          if(bank.degrade.inst_unavailable == 1 &&
             bank.degrade.proxy_inst_available == 0 &&
             !_MainHyp_AllowProxyDegrade(m_cfg) &&
             !_MainHyp_TesterCanSoftenRegime(m_cfg, bank, sel, loc))
          {
             return false;
          }

          if(sel.trend_active <= 0 && sel.mom_active <= 0 &&
             !_MainHyp_TesterCanSoftenRegime(m_cfg, bank, sel, loc))
          {
             return false;
          }

          return true;
       }

       virtual bool EvaluateHypothesis(const ISV::RawSignalBank_t &bank,
                                       const CategorySelectedVector &sel,
                                       const ISV::LocationPass_t &loc,
                                       const BaseContextVector &base_ctx,
                                       const StructureVector &struct_ctx,
                                       const CoverageContextVector &coverage_ctx,
                                       StrategyHypothesis_t &out)
       {
         out.Reset();

         if(!bank.valid)
         {
            out.invalidation_reason = "base_raw_bank_invalid";
            return false;
         }

         const string evalSym =
            (bank.symbol != "" ? bank.symbol : _Symbol);

         const ENUM_TIMEFRAMES evalTf =
            (bank.tf > PERIOD_CURRENT ? bank.tf : (ENUM_TIMEFRAMES)m_cfg.tf_entry);

         if(!ShouldRun(bank, sel, loc))
         {
            string runWhy = "";

            if(_MainHyp_ShouldRunWithReason(m_cfg, bank, sel, loc, runWhy))
               runWhy = "main_should_run_false_unclassified";

            if(runWhy == "")
               runWhy = "main_should_run_false_unclassified";

            out.invalidation_reason = runWhy;

            DbgStrat(m_cfg,
                     evalSym,
                     evalTf,
                     "MainShouldRun",
                     StringFormat("[MainShouldRun] sid=%d result=0 first_false=%s selCats=%d loc_pass=%d poi=%.2f sweep=%.2f liqEvt=%d liqType=%s sweepDir=%d liqProv=%s trend=%d mom=%d inst_unavail=%d proxy_inst=%d hard_inst=%d obs=%.2f",
                                  (int)Id(),
                                  runWhy,
                                  StratBase::CountActiveSelectedCategories(sel),
                                  loc.pass,
                                  loc.poi_score01,
                                  loc.sweep_score,
                                  (loc.liquidity_event_time > 0 ? 1 : 0),
                                  loc.liquidity_event_type,
                                  loc.sweep_dir,
                                  loc.liquidity_event_provenance,
                                  sel.trend_active,
                                  sel.mom_active,
                                  bank.degrade.inst_unavailable,
                                  bank.degrade.proxy_inst_available,
                                  bank.degrade.hard_inst_block,
                                  bank.degrade.observability01),
                     true);

            return false;
         }

          ICT_Context ctx;
          Main_LoadCanonicalICTContext(evalSym, m_cfg, ctx);

          MainHypStageState st;
          st.Reset();

          string why = "";

          // Stage 0: direction seed
          if(!_MainHyp_DirectionSeed(m_cfg, ctx, bank, sel, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 1: regime gate
          if(!_MainHyp_RegimeStage(evalSym, evalTf, m_cfg, ctx, bank, sel, loc, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 2: location gate
          if(!_MainHyp_LocationStage(m_cfg, bank, sel, loc, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 3: liquidity event gate
          if(!_MainHyp_LiquidityStage(m_cfg, bank, sel, loc, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 4: institutional participation gate
          if(!_MainHyp_InstitutionalStage(m_cfg, bank, sel, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 5: volume participation gate
          if(!_MainHyp_VolumeStage(bank, sel, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 6: trigger confirmation gate
          MainFusedHeads heads;
          Main_LoadFusedHeads(evalSym, evalTf, st.dir, m_cfg, ctx, heads);

          if(!_MainHyp_TriggerStage(evalSym, evalTf, m_cfg, bank, ctx, heads, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Stage 7: execution gate
          if(!_MainHyp_ExecutionStage(m_cfg, bank, loc, st, why))
          {
             out.invalidation_reason = why;
             return false;
          }

          // Legacy deep scorer remains the canonical inner evaluator for now.
          StratScore ss;
          ConfluenceBreakdown bd;
          ZeroMemory(ss);
          ZeroMemory(bd);

          if(!::StratMainLogic::Evaluate(evalSym, st.dir, m_cfg, ctx, ss, bd))
          {
             out.invalidation_reason =
                (StringLen(ss.reason) > 0 ? ss.reason : "evaluate_false");
             return false;
          }

          if(!ss.eligible)
          {
             out.invalidation_reason =
                (StringLen(ss.reason) > 0 ? ss.reason : "not_eligible");
             return false;
          }

          st.final_quality01 =
             _MainClamp01(_MainHyp_WeightedQuality(m_cfg, st, ss) *
                          st.score_penalty_mult);

          st.confidence01 =
             _MainClamp01(st.final_quality01 *
                          (1.0 - _MainClamp01(bank.degrade.observability_penalty01)) *
                          st.confidence_penalty_mult);

          double mainQualityThreshold = Config::CfgMainQualityThreshold(m_cfg);

          if(Main_CfgTesterDegradedMode(m_cfg) &&
             (st.regime_softened ||
              st.location_softened ||
              st.liquidity_softened ||
              st.trigger_softened))
          {
             mainQualityThreshold = MathMax(0.0, mainQualityThreshold - 0.05);
          }

          if(st.final_quality01 < mainQualityThreshold)
          {
             out.invalidation_reason =
                StringFormat("main_quality_below_threshold q=%.2f th=%.2f trigSoft=%d trigTag=%s",
                             st.final_quality01,
                             mainQualityThreshold,
                             (st.trigger_softened ? 1 : 0),
                             st.trigger_soft_tag);
             return false;
          }

          st.reason =
             StringFormat("main staged ok | dir=%s loc=%.2f liq=%.2f micro=%.2f vol=%.2f pat=%.2f exec=%.2f q=%.2f conf=%.2f qpen=%.2f cpen=%.2f regimeSoft=%d locSoft=%d liqSoft=%d trigSoft=%d trigTag=%s",
                          (st.dir == DIR_BUY ? "BUY" : "SELL"),
                          st.location_score,
                          st.liquidity_score,
                          st.micro_score,
                          st.volume_score,
                          st.pattern_score,
                          st.execution_score,
                          st.final_quality01,
                          st.confidence01,
                          st.score_penalty_mult,
                          st.confidence_penalty_mult,
                          (st.regime_softened ? 1 : 0),
                          (st.location_softened ? 1 : 0),
                          (st.liquidity_softened ? 1 : 0),
                          (st.trigger_softened ? 1 : 0),
                          st.trigger_soft_tag);

          _MainHyp_FinalizeHypothesis(bank, sel, m_cfg, st, ss, bd, out);

          string riskWhy = "";
          if(!_MainHyp_RiskShapeValid(st, out, riskWhy))
          {
             out.invalidation_reason = riskWhy;
             return false;
          }

          return true;
       }

       // Match IStrategy *exactly*. Keep override on the DECLARATION only.
       virtual bool Evaluate(const Direction          dir,
                             const Settings          &cfg,
                             StratScore              &ss,
                             ConfluenceBreakdown     &bd) override;
                             
       virtual bool ComputeDirectional(const Direction dir,
                                const Settings  &cfg,
                                StratScore      &ss,
                                ConfluenceBreakdown &bd) override;

   
     private:
     void AugmentWithExtras_ifConfirmed(const string          sym,
                                              const ENUM_TIMEFRAMES tf,
                                              const Direction       dir,
                                              const Settings       &cfg,
                                              StratScore           &ss,
                                              ConfluenceBreakdown  &bd);
     };
     
     inline StrategyBase* GetMainTradingLogicStrategy()
      {
         static Strat_MainTradingLogic s_main;
         return &s_main;
      }
  
      bool Strat_MainTradingLogic::Evaluate(const Direction          dir,
                                            const Settings          &cfg,
                                            StratScore              &ss,
                                            ConfluenceBreakdown     &bd)
      {
         // Let StrategyBase handle grade/news/throttle and then call our ComputeDirectional.
         return StrategyBase::Evaluate(dir, cfg, ss, bd);
      }
      
      bool Strat_MainTradingLogic::ComputeDirectional(const Direction       dir,
                                                      const Settings       &cfg,
                                                      StratScore           &ss,
                                                      ConfluenceBreakdown  &bd)
      {
         ZeroMemory(ss);
         ZeroMemory(bd);
      
         // Legacy chart-symbol compatibility path.
         // Multi-symbol routing / hypothesis generation must use EvaluateHypothesis(...)
         // and the canonical bank.symbol flow, not _Symbol.
         ICT_Context ctx;
         Main_LoadCanonicalICTContext(_Symbol, cfg, ctx);
      
         const bool ran = ::StratMainLogic::Evaluate(_Symbol, dir, cfg, ctx, ss, bd);
      
         if(ss.risk_mult <= 0.0)
            ss.risk_mult = 1.0;
      
         return ran;
      }

      // --- Defense-in-depth: confluence-only snapshot when Main is blocked by strategy mode ---
      inline void Main_ModeBlocked_ConfluenceOnly(const string         sym,
                                                 const ENUM_TIMEFRAMES tf,
                                                 const Direction      dir,
                                                 const Settings      &cfg,
                                                 const ICT_Context   &ctx,
                                                 StratScore          &out,
                                                 ConfluenceBreakdown &bd)
      {
         // out.id already set by caller
         const bool isBuy = (dir == DIR_BUY);
      
         // Classical + ICT scoring only (NO triggers / NO execution)
         double classicalScore = 0.0;
         if(isBuy) classicalScore = Confl::ComputeClassicalScoreBuy(bd, cfg, out);
         else      classicalScore = Confl::ComputeClassicalScoreSell(bd, cfg, out);
      
         StratScore ssICT;
         ZeroMemory(ssICT);
         ssICT.id = out.id;
      
         double ictScore = 0.0;
         if(isBuy) ictScore = Confl::ComputeICTScoreLong(ctx, cfg, ssICT);
         else      ictScore = Confl::ComputeICTScoreShort(ctx, cfg, ssICT);
      
         double fibMult = 1.0;
         const double finalQuality =
            Confl::ComputeFinalQualityScore(bd, cfg, out, STRAT_MAIN,
                                            classicalScore, ictScore,
                                            fibMult, isBuy);
      
         out.score_raw = finalQuality;
         out.score     = finalQuality;
         out.eligible  = false;
         out.risk_mult = 1.0;
         out.reason    = "Blocked by strategy mode (confluence-only)";

         Main_SetHeadScores(out, _MainClamp01(finalQuality), 0.0, 1.0);
         Main_SetBreakdownHeadScores(bd, _MainClamp01(finalQuality), 0.0, 1.0);

         bd.veto                = true;
         bd.score_after_penalty = finalQuality;
      
         if(CfgDebugStrategies(cfg))
         {
            const string dirStr = (isBuy ? "BUY" : "SELL");
            const string msg =
               StringFormat("[MainModeBlock] sym=%s tf=%d dir=%s score=%.2f",
                            sym, (int)tf, dirStr, finalQuality);
            DbgStrat(cfg, sym, tf, "ModeBlock", msg, /*oncePerClosedBar*/true);
         }
      }

      // ---------------------------------------------------------------------
      // Legacy deep scorer / trigger / execution composite.
      //
      // EvaluateHypothesis(...) above is now the canonical staged hypothesis
      // builder and must remain the only hypothesis-emission path for Main.
      //
      // EvaluateEx(...) remains the inner legacy scorer until the old checklist
      // logic is fully decomposed into stage-local helpers.
      // ---------------------------------------------------------------------
      bool EvaluateEx(const string sym, const Direction dir, const Settings &cfg, const ICT_Context &ctx,
                        StratScore &out, ConfluenceBreakdown &bd, AutoSnapshot &autoS, bool &haveAuto,
                        AutoVol::AutoVolStats &av, bool &haveAv)
      {
         // Hygiene
         ZeroMemory(out);
         ZeroMemory(bd);
      
         out.id        = STRAT_MAIN_ID;
         out.eligible  = false;
         out.score     = 0.0;
         out.score_raw = 0.0;
         out.risk_mult = 1.0;
      
         const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)cfg.tf_entry;

         MainFusedHeads heads;
         Main_LoadFusedHeads(sym, tf, dir, cfg, ctx, heads);

         haveAuto = heads.have_auto;
         if(haveAuto)
            autoS = heads.auto_snap;

         haveAv = heads.have_autovol;
         if(haveAv)
            av = heads.autovol;

         const bool isBuy = (dir == DIR_BUY);

         string testerDegradedWhy = "";
         const bool testerDegradedMode =
            Main_CanUseTesterFallbackDegradedMode(cfg, heads, testerDegradedWhy);
         
         string testerGateSoftWhy = "";
         const bool testerSelectedGateSoftening =
            Main_CanUseTesterSelectedGateSoftening(cfg, heads, testerGateSoftWhy);

         const bool testerLooseGate =
            Main_CfgTesterLooseGate(cfg);

         const bool testerSkipNewsCorr =
            Main_CfgTesterDisableNewsAndCorrelation(cfg);

         string testerDegradedTags = "";
         double testerDegradedScoreMult = 1.0;
         double testerDegradedRiskMult  = 1.0;

         if(testerDegradedMode && CfgDebugStrategies(cfg))
         {
            const string dirStr = (isBuy ? "BUY" : "SELL");
            const string msg =
               StringFormat("[MainTesterDegraded] sym=%s tf=%d dir=%s active=1 reason=%s",
                            sym, (int)tf, dirStr, testerDegradedWhy);
            DbgStrat(cfg, sym, tf, "TesterDegradedOn", msg, /*oncePerClosedBar*/true);
         }

         if(testerSelectedGateSoftening && CfgDebugStrategies(cfg))
         {
            const string dirStr = (isBuy ? "BUY" : "SELL");
            const string msg =
               StringFormat("[MainTesterSoftGates] sym=%s tf=%d dir=%s active=1 reason=%s",
                            sym, (int)tf, dirStr, testerGateSoftWhy);
            DbgStrat(cfg, sym, tf, "TesterSoftGatesOn", msg, true);
         }

          if(testerLooseGate && CfgDebugStrategies(cfg))
          {
             const string dirStr = (isBuy ? "BUY" : "SELL");
             const string msg =
                StringFormat("[MainTesterLooseGate] sym=%s tf=%d dir=%s active=1 newsBypass=%d killzoneBypass=%d",
                             sym, (int)tf, dirStr,
                             (testerSkipNewsCorr ? 1 : 0),
                             (Main_CfgTesterDisableKillzone(cfg) ? 1 : 0));
             DbgStrat(cfg, sym, tf, "TesterLooseGateOn", msg, true);
          }

         // Strategy-mode self-guard (defense-in-depth):
         // If Main is disallowed (e.g., PACK_ONLY), return confluence-only and never become orderable.
         if(!Config::IsStrategyAllowedInMode(cfg, (StrategyID)STRAT_MAIN_ID))
         {
            Main_ModeBlocked_ConfluenceOnly(sym, tf, dir, cfg, ctx, out, bd);
            Main_SetHeadScores(out, 0.0, 0.0, 1.0);
            Main_SetBreakdownHeadScores(bd, 0.0, 0.0, 1.0);
            return false; // This function returns "orderable eligibility", so false is correct here.
         }

         // Honour ICT allowedDirection inside the canonical evaluator as well.
         // This protects every call-path (router, shims, tests).
         const ENUM_TRADE_DIRECTION dirAsTDIR = (isBuy ? TDIR_BUY : TDIR_SELL);
         
         if(cfg.trade_direction_selector == TDIR_BOTH &&
            ctx.allowedDirection != TDIR_BOTH &&
            ctx.allowedDirection != dirAsTDIR)
         {
            out.eligible = false;
            out.score    = 0.0;
            out.reason   = "StratMain blocked by ICT allowedDirection";
            Main_SetHeadScores(out, 0.0, 0.0, 1.0);
            Main_SetBreakdownHeadScores(bd, 0.0, 0.0, 1.0);
            return false;
         }

         // 1) Build the internal Main checklist only.
         //    EvaluateEx(...) remains the canonical Main decision owner.
         ConfluenceResult R;
         R.metCount    = 0;
         R.score       = 0.0;
         R.mask        = 0;
         R.summary     = "";
         R.passesCount = false;
         R.passesScore = false;
         R.eligible    = false;

         if(cfg.main_sequential_gate)
            R = EvalSequentialEx(sym, tf, dir, cfg, ctx, haveAuto, autoS);
         else
            R = EvalScoredEx(sym, tf, dir, cfg, haveAuto, autoS);
         
         const double legacyConfluenceScore = R.score; // keep for diagnostics only
         
         // This checklist is the RULEBOOK gate for Main strategy entries.
         const bool checklistOK = R.eligible;
         const bool atPOIStage =
            (((R.mask & ((ulong)1 << C_ZONE)) != 0) ||
             ((R.mask & ((ulong)1 << C_OB  )) != 0));
         
         const bool testerStructuralPrereqs =
            (atPOIStage && HasMarketStructure(sym, tf, dir, cfg));
         
         bool requireChecklist = false;
         #ifdef CFG_HAS_MAIN_REQUIRE_CHECKLIST
           requireChecklist = (Config::Cfg_EnableHardGate(cfg) && cfg.main_require_checklist);
         #endif
         
         const bool checklistSoftFallbackMode = RuntimeMainChecklistSoftFallbackEnabled();
         
         const bool checklistTesterSoftFallback =
            (requireChecklist &&
             !checklistOK &&
             testerSelectedGateSoftening &&
             testerStructuralPrereqs);
         
         const bool checklistSoftFallback =
            (requireChecklist &&
             !checklistOK &&
             (checklistSoftFallbackMode || checklistTesterSoftFallback));

         double checklistPenaltyScoreMult = 1.0;
         double checklistPenaltyRiskMult  = 1.0;

         if(requireChecklist && !checklistOK)
         {
            if(checklistSoftFallback)
            {
               checklistPenaltyScoreMult = 0.80;
               checklistPenaltyRiskMult  = 0.60;

               const string checklistSoftTag =
                  (Main_IsTesterRuntime() ? "tester_softened_gate:checklist"
                                          : "live_checklist_soft");

               const string checklistDetail =
                  StringFormat("met=%d score=%.2f need>=%d minScore=%.2f summary=%s",
                               R.metCount, R.score,
                               _ML::CF_MinNeeded(cfg), _ML::CF_MinScore(cfg),
                               R.summary);

               Main_ApplyTesterDegradedPenalty(checklistSoftTag,
                                               checklistDetail,
                                               checklistPenaltyScoreMult,
                                               checklistPenaltyRiskMult,
                                               testerDegradedTags,
                                               testerDegradedScoreMult,
                                               testerDegradedRiskMult);

               if(CfgDebugStrategies(cfg))
               {
                  const string dirStr = (isBuy ? "BUY" : "SELL");
                  const string msg =
                     StringFormat("[ChecklistGate] sym=%s tf=%d dir=%s checklistOK=0 fallbackMode=%d fallbackUsed=1 scoreMult=%.2f riskMult=%.2f",
                                  sym, (int)tf, dirStr,
                                  (checklistSoftFallbackMode ? 1 : 0),
                                  checklistPenaltyScoreMult,
                                  checklistPenaltyRiskMult);
                  DbgStrat(cfg, sym, tf, "ChecklistGateSoft", msg, true);
               }
            }
            else
            {
               if(CfgDebugStrategies(cfg))
               {
                  const string dirStr = (isBuy ? "BUY" : "SELL");
                  const string msg =
                     StringFormat("[ChecklistGate] sym=%s tf=%d dir=%s checklistOK=0 fallbackMode=%d fallbackUsed=0 scoreMult=1.00 riskMult=1.00 finalEligible=0 action=hard_veto",
                                  sym, (int)tf, dirStr,
                                  (checklistSoftFallbackMode ? 1 : 0));
                  DbgStrat(cfg, sym, tf, "ChecklistGateHard", msg, true);
               }

               out.score_raw = legacyConfluenceScore;
               out.score     = 0.0;
               out.eligible  = false;
               out.reason    = "Main checklist veto";
               bd.veto       = true;
               bd.score_after_penalty = 0.0;
               Main_SetHeadScores(out, 0.0, 0.0, 1.0);
               Main_SetBreakdownHeadScores(bd, 0.0, 0.0, 1.0);
               return false;
            }
         }

         if(!checklistOK && CfgTraceFlow(cfg))
         {
            if(checklistSoftFallback)
            {
               TraceStrat(cfg, sym, tf, "SoftChecklist",
                          StringFormat("[MainLogicSoft] %s checklist fallback | scoreMult=%.2f riskMult=%.2f | met=%d score=%.2f need>=%d minScore=%.2f | %s",
                                       (isBuy ? "BUY" : "SELL"),
                                       checklistPenaltyScoreMult,
                                       checklistPenaltyRiskMult,
                                       R.metCount, R.score,
                                       _ML::CF_MinNeeded(cfg), _ML::CF_MinScore(cfg),
                                       R.summary));
            }
            else
            {
               TraceStrat(cfg, sym, tf, "FailChecklist",
                          StringFormat("[MainLogicFail] %s checklist | met=%d score=%.2f need>=%d minScore=%.2f | %s",
                                       (isBuy ? "BUY" : "SELL"),
                                       R.metCount, R.score,
                                       _ML::CF_MinNeeded(cfg), _ML::CF_MinScore(cfg),
                                       R.summary));
            }
         }

         // 1.1) Consume scanner alignment (SR/SD/OB vs Auto/TL)
         // This prevents the scanner from being "informational only".
         const bool wantAuto =
            (cfg.auto_enable &&
             (cfg.cf_autochartist_chart ||
              cfg.cf_autochartist_fib ||
              cfg.cf_autochartist_keylevels ||
              cfg.cf_autochartist_volatility));

         const bool scanAlignEnabled =
            (wantAuto || Confl::CfgCF_Enable_InstZones(cfg) || Confl::CfgExtra_Trendlines(cfg));
         
         double scanQualMult = 1.0;
         double scanRiskMult = 1.0;
         bool   scanOK       = true;
         bool   scanHardVeto = false;
         string whyScan      = "";
         
         Main_ScanAlign_Apply(cfg, scanAlignEnabled, sym, tf, dir,
                             scanQualMult, scanRiskMult, scanOK, scanHardVeto, whyScan);
         
         // Hard veto path (only if you later enable it via cfg/macro)
         if(scanAlignEnabled && !scanOK && scanHardVeto)
         {
            out.score_raw = legacyConfluenceScore;
            out.score     = 0.0;
            out.eligible  = false;
            out.reason    = "ScanAlign veto";
            bd.veto       = true;
            bd.score_after_penalty = 0.0;
         
            if(CfgTraceFlow(cfg))
               TraceStrat(cfg, sym, tf, "FailScanAlign",
                          StringFormat("[MainLogicFail] %s scanAlign veto | %s",
                                       (isBuy ? "BUY" : "SELL"), whyScan));

            Main_SetHeadScores(out, 0.0, 0.0, 1.0);
            Main_SetBreakdownHeadScores(bd, 0.0, 0.0, 1.0);
            return false;
         }
         
         // Optional diagnostics for SOFT shaping (throttled)
         if(scanAlignEnabled && !scanOK && !scanHardVeto && CfgDebugStrategies(cfg))
         {
            const string msg =
               StringFormat("[ScanAlignSoft] sym=%s tf=%d dir=%s qualMult=%.2f riskMult=%.2f | %s",
                            sym, (int)tf, (isBuy ? "BUY" : "SELL"),
                            scanQualMult, scanRiskMult, whyScan);
            DbgStrat(cfg, sym, tf, "ScanAlignSoft", msg, /*oncePerClosedBar*/true);
         }

         double classicalScore = 0.0;
         if(isBuy)
            classicalScore = Confl::ComputeClassicalScoreBuy(bd, cfg, out);
         else
            classicalScore = Confl::ComputeClassicalScoreSell(bd, cfg, out);
         double ictScore       = 0.0;
      
         // Optional: some profiles may require classical confluence.
         // Default is false to keep confluence as a modifier.
         bool requireClassical = false;
         #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
            requireClassical = cfg.main_require_classical;
         #endif

         // 2) Compute ICT score and final blended quality via Playbook
         StratScore          ssICT;
         ZeroMemory(ssICT);
         ssICT.id = out.id;   // make ICT scoring strat-aware (no silent StrategyID=0)
      
         if(isBuy)
            ictScore = Confl::ComputeICTScoreLong(ctx, cfg, ssICT);
         else
            ictScore = Confl::ComputeICTScoreShort(ctx, cfg, ssICT);
      
         ICTStrategyKind stratKind = STRAT_MAIN;
      
         double fibMult = 1.0;
         double finalQuality = Confl::ComputeFinalQualityScore(bd, cfg, out, stratKind,
                                                              classicalScore, ictScore,
                                                              fibMult, isBuy);

         // Persist the raw pre-gate score bundle immediately.
         // This must happen before tester-degraded softeners or hard returns.
         out.score_raw = finalQuality;
         bd.score_after_penalty = finalQuality;

         Main_DbgRawScoreWrite(cfg, sym, tf, dir,
                               classicalScore,
                               ictScore,
                               finalQuality,
                               testerDegradedMode);

         // 2.1) Killzone / trading-window enforcement (HARD vs SOFT)
         //      This is the ONLY place Main enforces killzone/session windows.
         //      Triggers no longer hide killzone vetoes.
         int    kzMode          = CfgKillzoneMode(cfg);
         double kzScoreMult     = 1.0;
         double kzRiskMult      = 1.0;
         bool   inKZ            = false;
         bool   sbOverrideUsed  = false;
         
         bool allowTradeNow = true;
         if(kzMode != KZ_MODE_OFF)
            allowTradeNow = ICTCtx_AllowTradeNow(ctx, cfg, inKZ, sbOverrideUsed);
         
         if(kzMode == KZ_MODE_HARD && !allowTradeNow)
         {
            if(testerDegradedMode)
            {
               kzScoreMult = 0.90;
               kzRiskMult  = 0.65;

               Main_AppendDiagTagWithDetail(
                  testerDegradedTags,
                  "tester_fallback_kz_soft",
                  StringFormat("inKZ=%d sbOverride=%d", (inKZ ? 1 : 0), (sbOverrideUsed ? 1 : 0)));

               if(CfgDebugStrategies(cfg))
               {
                  const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
                  const string msg =
                     StringFormat("[DiagMainKZ] sym=%s tf=%d dir=%s KZ_MODE=HARD testerSoft=1 allowTradeNow=0 inKZ=%d sbOverride=%d scoreMult=%.2f riskMult=%.2f",
                                  sym, (int)tf, dirStr,
                                  (inKZ ? 1 : 0), (sbOverrideUsed ? 1 : 0),
                                  kzScoreMult, kzRiskMult);
                  DbgStrat(cfg, sym, tf, "KZTesterSoft", msg, /*oncePerClosedBar*/true);
               }
            }
            else
            {
               // Standard hard gate: outside window => no trade
               out.score_raw = finalQuality;   // keep for diagnostics
               out.score     = 0.0;            // HARD veto must leave no �candidate-worthy� score
               out.eligible  = false;

               bd.veto                = true;
               bd.score_after_penalty = 0.0;

               if(CfgDebugStrategies(cfg))
               {
                  const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
                  const string msg =
                     StringFormat("[DiagMainKZ] sym=%s tf=%d dir=%s KZ_MODE=HARD allowTradeNow=0 inKZ=%d sbOverride=%d",
                                  sym, (int)tf, dirStr, (inKZ ? 1 : 0), (sbOverrideUsed ? 1 : 0));
                  DbgStrat(cfg, sym, tf, "KZHard", msg, /*oncePerClosedBar*/true);
               }

               Main_SetHeadScores(out, 0.0, 0.0, 1.0);
               Main_SetBreakdownHeadScores(bd, 0.0, 0.0, 1.0);
               return false;
            }
         }
         
         if(kzMode == KZ_MODE_SOFT && !allowTradeNow)
         {
            kzScoreMult = CfgKillzoneSoftPenalty(cfg);
            kzRiskMult  = CfgKillzoneSoftRiskMult(cfg);
         
            if(CfgDebugStrategies(cfg))
            {
               const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
               const string msg =
                  StringFormat("[DiagMainKZ] sym=%s tf=%d dir=%s KZ_MODE=SOFT allowTradeNow=0 inKZ=%d sbOverride=%d scoreMult=%.2f riskMult=%.2f",
                               sym, (int)tf, dirStr, (inKZ?1:0), (sbOverrideUsed?1:0), kzScoreMult, kzRiskMult);
               DbgStrat(cfg, sym, tf, "KZSoft", msg, /*oncePerClosedBar*/true);
            }
         }
               
         // 3) Directional trigger using ICT context + location + liquidity
         string whyTrigger = "";
         string whyEnv = "";     // env gate / AMD-Wyckoff environment reason
         bool   triggerOK  = false;
      
         if(isBuy)
            triggerOK = EvaluateBuyTrigger(sym,
                                           ctx,
                                           heads.have_entry_scan,
                                           heads.entry_scan,
                                           heads.have_ofds,
                                           heads.ofds,
                                           classicalScore,
                                           cfg,
                                           whyTrigger);
         else
            triggerOK = EvaluateSellTrigger(sym,
                                            ctx,
                                            heads.have_entry_scan,
                                            heads.entry_scan,
                                            heads.have_ofds,
                                            heads.ofds,
                                            classicalScore,
                                            cfg,
                                            whyTrigger);
      
         // 4) Quality thresholds (classical, ICT, and final)
         const double minClassical = Playbook_MinClassicalScore();
         const double minICT       = Playbook_MinICTScore(stratKind);
      
         const bool classicalOK = (classicalScore >= minClassical);
         bool ictOK             = (ictScore >= minICT);
      
         // Bias classification (continuation vs reversal) for thresholds + risk
         bool withBias    = false;
         bool againstBias = false;
         Main_ComputeBiasFlags(ctx, dir, cfg, withBias, againstBias);

         const bool haveOFDS = heads.have_ofds;
         const int microArchetype =
            Main_ClassifyMicroArchetype(ctx, dir, withBias, againstBias, haveAuto, autoS);

         double microAlpha01  = 0.0;
         double microExec01   = 0.0;
         double microRisk01   = 1.0;
         double microQualMult = 1.0;
         double microRiskMult = 1.0;
         string whyMicro      = "";

         bool microOK =
            Main_ApplyMicrostructureGate(cfg,
                                         dir,
                                         microArchetype,
                                         heads.ofds,
                                         microAlpha01,
                                         microExec01,
                                         microRisk01,
                                         microQualMult,
                                         microRiskMult,
                                         whyMicro);

          if(!microOK)
          {
             const bool softenMicro =
                (testerLooseGate ||
                 (testerDegradedMode && Main_IsSoftenableTesterMicroReject(whyMicro)));

             if(softenMicro)
             {
                const string softTag =
                   (testerLooseGate ? "tester_loose_gate:micro_relaxed"
                                    : "tester_fallback_micro_soft");

                Main_ApplyTesterDegradedPenalty(softTag,
                                                whyMicro,
                                                (testerLooseGate ? 1.00 : 0.90),
                                                (testerLooseGate ? 1.00 : 0.85),
                                                testerDegradedTags,
                                                testerDegradedScoreMult,
                                                testerDegradedRiskMult);

                microAlpha01  = 0.50;
                microExec01   = 0.50;
                microRisk01   = 0.50;
                microQualMult = 1.00;
                microRiskMult = 1.00;
                whyMicro      = "micro relaxed";

                microOK = true;
             }
          }

         string whyPOIVol = "";
         const bool poiVolumeOK =
            Main_POIOrderFlowConfirmOK(sym,
                                       tf,
                                       dir,
                                       cfg,
                                       ctx,
                                       heads.ofds,
                                       atPOIStage,
                                       whyPOIVol);

         string whyConfirm = "";
         const bool confirmOK =
            Main_ConfirmationClusterOK(sym,
                                       tf,
                                       dir,
                                       cfg,
                                       haveAuto,
                                       autoS,
                                       whyConfirm);

         // -----------------------------------------------------------------------
         // C.A.N.D.L.E. N — Narrative Exhaustion in Hypothesis Stage
         // Blends opposing-side exhaustion quality into st.pattern_score so that
         // the hypothesis pipeline reflects both named pattern quality and the
         // body/wick/close cluster signal together.
         // -----------------------------------------------------------------------
         #ifdef CANDLE_NARRATIVE_AVAILABLE
         if(cfg.cf_candle_narrative)
         {
            CandleNarrativeResult narrHyp;
            ZeroMemory(narrHyp);
            const bool narrHypOk =
               // Build CandleNarrativeCtx for the hypothesis stage.
               // Mirrors the EvalSequentialEx enrichment path using the same ctx fields.
               #ifdef CANDLE_NARRATIVE_ENHANCED
               if(cfg.candle_narrative_use_patterns ||
                  cfg.candle_narrative_use_vsa      ||
                  cfg.candle_narrative_use_amd      ||
                  cfg.candle_narrative_htf_weight > 0.0)
               {
                  CandleNarrativeCtx narrHypCtx;
                  narrHypCtx.Reset();

                  if(cfg.candle_narrative_use_patterns)
                  {
                     Patt::PatternSet P;
                     if(Patt::ScanAll(sym, tf, 80, P))
                     {
                        narrHypCtx.patt_cs_ampdi01    = P.cs_score_ampdi01;
                        narrHypCtx.patt_cs_trend01    = P.cs_trend01;
                        narrHypCtx.patt_cs_vol01      = P.cs_vol01;
                        narrHypCtx.patt_cs_mom01      = P.cs_mom01;
                        narrHypCtx.patt_ch_ampdi01    = P.ch_score_ampdi01;
                        narrHypCtx.patt_cs_best_score = P.cs_best_score01;
                        narrHypCtx.patt_cs_bull       = P.cs_best_bull;
                        narrHypCtx.patt_sd_htf_aligned= P.sd_htf_aligned;
                     }
                  }

                  if(cfg.candle_narrative_use_vsa)
                  {
                     narrHypCtx.vsa_climax_against = (dir == DIR_BUY)
                        ? ctx.vsaSellingClimax : ctx.vsaBuyingClimax;
                     narrHypCtx.vsa_climax_score01 = ctx.vsaClimaxScore;
                     narrHypCtx.vsa_spring         = ctx.wySpringCandidate;
                     narrHypCtx.vsa_upthrust       = ctx.wyUTADCandidate;
                  }

                  narrHypCtx.atr_pts     = Indi::ATRPoints(sym, tf, 14, 1);
                  narrHypCtx.vol_regime01= _Clamp01((double)ctx.vwapVolumeRegime / 2.0);

                  if(cfg.candle_narrative_use_amd)
                  {
                     const int ph1 = Ctx_AMDPhase_H1(ctx);
                     const int ph4 = Ctx_AMDPhase_H4(ctx);
                     narrHypCtx.amd_accumulation = (ph1 == AMD_PHASE_ACCUM || ph4 == AMD_PHASE_ACCUM)
                                                    || ctx.wySpringCandidate;
                     narrHypCtx.amd_distribution = (ph1 == AMD_PHASE_DIST  || ph4 == AMD_PHASE_DIST)
                                                    || ctx.wyUTADCandidate;
                     narrHypCtx.amd_manipulation = (ph1 == AMD_PHASE_MANIP || ph4 == AMD_PHASE_MANIP);
                  }

                  if(cfg.candle_narrative_htf_weight > 0.0)
                  {
                     const bool htfBull = ctx.wyInAccumulation || ctx.wyInMarkup;
                     const bool htfBear = ctx.wyInDistribution || ctx.wyInMarkdown;
                     narrHypCtx.htf_trend_aligned    = (dir == DIR_BUY) ? htfBull : htfBear;
                     narrHypCtx.htf_trend_strength01 = htfBull
                        ? (ctx.wyInMarkup ? 1.0 : 0.60)
                        : (htfBear ? (ctx.wyInMarkdown ? 1.0 : 0.60) : 0.0);
                  }

                  narrHypCtx.data_populated = true;
                  ComputeCandleNarrative(sym, tf, dir,
                                         cfg.candle_narrative_lookback > 0
                                            ? cfg.candle_narrative_lookback : 4,
                                         narrHypCtx, narrHyp);
               }
               else
               #endif // CANDLE_NARRATIVE_ENHANCED
               {
                  ComputeCandleNarrative(sym, tf, dir,
                                         cfg.candle_narrative_lookback > 0
                                            ? cfg.candle_narrative_lookback : 4,
                                         narrHyp);
               }

            if(narrHypOk && narrHyp.data_valid)
            {
               // Mild multiplier: strong exhaustion >= 0.6 gets +5%;
               // weak exhaustion < 0.35 gets -5%.  Neutral zone is no-op.
               const double narrMult =
                  (narrHyp.exhaustion_score >= 0.60) ? 1.05 :
                  (narrHyp.exhaustion_score >= 0.45) ? 1.00 :
                  (narrHyp.exhaustion_score >= 0.30) ? 0.97 : 0.95;

               st.pattern_score = MathMin(1.0, MathMax(0.0, st.pattern_score * narrMult));
            }
         }
         #endif // CANDLE_NARRATIVE_AVAILABLE
         
         // Base threshold from Playbook
         double qThresh = Playbook_FinalHighQualityThreshold();
      
         // Allow config overrides (high/continuation/reversal)
         #ifdef CFG_HAS_QUALITY_THRESHOLDS
            if(withBias && cfg.qualityThresholdContinuation > 0.0)
               qThresh = cfg.qualityThresholdContinuation;
            else if(againstBias && cfg.qualityThresholdReversal > 0.0)
               qThresh = cfg.qualityThresholdReversal;
            else if(cfg.qualityThresholdHigh > 0.0)
               qThresh = cfg.qualityThresholdHigh;
         #else
            #ifdef CFG_HAS_MAIN_QUALITY_THRESHOLD
               if(cfg.main_quality_threshold > 0.0)
                  qThresh = cfg.main_quality_threshold;
            #endif
         #endif

         if(testerLooseGate && qThresh > 0.0)
            qThresh *= 0.85;

         if(testerDegradedMode && !ictOK)
         {
            Main_ApplyTesterDegradedPenalty("tester_fallback_ict_soft",
                                            StringFormat("ict=%.2f<%.2f", ictScore, minICT),
                                            0.92,
                                            0.90,
                                            testerDegradedTags,
                                            testerDegradedScoreMult,
                                            testerDegradedRiskMult);
            ictOK = true;
         }

         // Extra confluence multipliers (mild, no hard veto)
         double amdQualMult = 1.0;
         double amdRiskMult = 1.0;
         double sbQualMult  = 1.0;
         double sbRiskMult  = 1.0;
         double po3HTFQualMult = 1.0, po3HTFRiskMult = 1.0;
         double wyQualMult     = 1.0, wyRiskMult     = 1.0;
         double zQualMult      = 1.0, zRiskMult      = 1.0;
         
         double volQualMult = 1.0;
         double volRiskMult = 1.0;
         bool   volOK       = true;
         string whyVol      = "";
         
         Main_AutoVol_Apply(cfg, haveAv, av, volQualMult, volRiskMult, volOK, whyVol);

         string whyPO3HTF = "";
         string whyWyck   = "";
         string whyZones  = "";
         
         // Silver Bullet timezone/window bonus (only if truly "window now")
         #ifdef CFG_HAS_EXTRA_SILVERBULLET_TZ
         if(cfg.extra_silverbullet_tz && Ctx_SilverBulletWindowNow(ctx))
         {
            // Keep mild: confluence boost, not a separate strategy
            sbQualMult = 1.05;
            sbRiskMult = 1.00;
         }
         #endif
         
         // Intraday AMD (H1/H4) phase shaping
         #ifdef CFG_HAS_EXTRA_AMD_HTF
         if(cfg.extra_amd_htf)
         {
            const int h1p = Ctx_AMDPhase_H1(ctx);
            const int h4p = Ctx_AMDPhase_H4(ctx);
         
            const bool wyAccumIntra = Ctx_Wy_InAccum_Intra(ctx);
            const bool wyDistIntra  = Ctx_Wy_InDist_Intra(ctx);
            
            const bool buyEnv  = (h1p == AMD_PHASE_ACCUM) || (h4p == AMD_PHASE_ACCUM) || ctx.wySpringCandidate || wyAccumIntra;
            const bool sellEnv = (h1p == AMD_PHASE_DIST)  || (h4p == AMD_PHASE_DIST)  || ctx.wyUTADCandidate   || wyDistIntra;
            
            const bool envSupportsDir = (dir == DIR_BUY ? buyEnv : sellEnv);
            const bool envOpposesDir  = (dir == DIR_BUY ? sellEnv : buyEnv);
            
            // Mild nudges only (do not hard veto here; veto logic is handled later at envOK).
            if(envSupportsDir && !envOpposesDir)
            {
               amdQualMult = 1.03;
               amdRiskMult = 0.98;
            }
            else if(envOpposesDir && !envSupportsDir)
            {
               amdQualMult = 0.98;
               amdRiskMult = 1.03;
            }
            
            // Diag
            if(CfgDebugStrategies(cfg))
            {
               const string d = (dir == DIR_BUY ? "BUY" : "SELL");
               const string msg =
                  StringFormat("[DiagMainAMD] sym=%s tf=%d dir=%s h1p=%d h4p=%d buyEnv=%d sellEnv=%d supports=%d opposes=%d qual=%.2f risk=%.2f",
                               sym, (int)tf, d,
                               h1p, h4p,
                               (buyEnv?1:0), (sellEnv?1:0),
                               (envSupportsDir?1:0), (envOpposesDir?1:0),
                               amdQualMult, amdRiskMult);

               DbgStrat(cfg, sym, tf, "AMDShape", msg, /*oncePerClosedBar*/true);
            }

            // PO3 HTF narrative shaping (mild, no veto)
            {
               const int s = Ctx_PO3_HTF_ContextScore(ctx, dir, whyPO3HTF);
               if(s >= 2)      po3HTFQualMult = 1.04;
               else if(s == 1) po3HTFQualMult = 1.02;
               else if(s < 0)  po3HTFQualMult = 0.99;
            }
            
            // Wyckoff Spring / UTAD shaping (mild, no veto)
            {
               const int s = Ctx_WyckoffTurnContext(ctx, dir, whyWyck);
               if(s > 0)      wyQualMult = 1.03;
               else if(s < 0) wyQualMult = 0.99;
            }
            
            // HTF zones + HTF liquidity shaping (mild, no veto)
            {
               const int s = Ctx_HTFZoneLiq_ContextScore(sym, tf, ctx, dir, whyZones);
               if(s >= 3)      zQualMult = 1.05;
               else if(s == 2) zQualMult = 1.03;
               else if(s == 1) zQualMult = 1.01;
            }
         }
         #endif
         
         const double finalQualityAdj =
            finalQuality *
            kzScoreMult *
            amdQualMult *
            sbQualMult *
            po3HTFQualMult *
            wyQualMult *
            zQualMult *
            volQualMult *
            scanQualMult *
            microQualMult *
            testerDegradedScoreMult;

         bool finalOK = (finalQualityAdj >= qThresh);

         if(testerDegradedMode && !finalOK)
         {
            const double relaxedQThresh = (qThresh * 0.85);

            if(finalQualityAdj >= relaxedQThresh)
            {
               Main_ApplyTesterDegradedPenalty("tester_fallback_final_soft",
                                               StringFormat("finalAdj=%.2f relaxed=%.2f hard=%.2f",
                                                            finalQualityAdj,
                                                            relaxedQThresh,
                                                            qThresh),
                                               1.00,
                                               0.90,
                                               testerDegradedTags,
                                               testerDegradedScoreMult,
                                               testerDegradedRiskMult);
               finalOK = true;
            }
         }

         // 5) Time / mode gates: Silver Bullet + PO3
         string whySB  = "";
         string whyPO3 = "";
         const bool sbOK  = Gate_SilverBullet(ctx, cfg, whySB);
         const bool po3OK = Gate_PO3(ctx, cfg, whyPO3);
      
          // 6) Optional hard news veto (and optional soft risk scaling)
          double newsRiskMult = 1.0;
          int    newsMinsLeft = 0;

          bool newsOK = true;
          bool newsComputed = false;

          if(testerSkipNewsCorr)
          {
             newsOK = true;
             newsComputed = false;
             newsRiskMult = 1.0;
             newsMinsLeft = 0;

             if(CfgDebugStrategies(cfg))
             {
                const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
                const string msg =
                   StringFormat("[MainNewsBypass] sym=%s tf=%d dir=%s active=1",
                                sym, (int)tf, dirStr);
                DbgStrat(cfg, sym, tf, "NewsTesterBypass", msg, true);
             }
          }
          else
          {
          #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
             if(cfg.main_news_hard_veto)
             {
                newsOK = Extra_NewsOK(sym, cfg, newsRiskMult, newsMinsLeft);
                newsComputed = true;
             }
             else if(cfg.extra_news)
             {
                Extra_NewsOK(sym, cfg, newsRiskMult, newsMinsLeft);
                newsComputed = true;
             }
          #else
             if(cfg.extra_news)
             {
                Extra_NewsOK(sym, cfg, newsRiskMult, newsMinsLeft);
                newsComputed = true;
             }
          #endif
          }
      
         bool envOK = true;
         whyEnv = "";

         const int ph1 = Ctx_AMDPhase_H1(ctx);
         const int ph4 = Ctx_AMDPhase_H4(ctx);

         const bool wyAccumIntra = Ctx_Wy_InAccum_Intra(ctx);
         const bool wyDistIntra  = Ctx_Wy_InDist_Intra(ctx);

         const bool wyBuy  = (ctx.wySpringCandidate || wyAccumIntra);
         const bool wySell = (ctx.wyUTADCandidate   || wyDistIntra);

         const bool po3Buy  = (ph1 == AMD_PHASE_ACCUM) || (ph4 == AMD_PHASE_ACCUM);
         const bool po3Sell = (ph1 == AMD_PHASE_DIST)  || (ph4 == AMD_PHASE_DIST);

         bool buyEnv  = false;
         bool sellEnv = false;

         if(wyBuy != wySell)
         {
            buyEnv  = wyBuy;
            sellEnv = wySell;
         }
         else
         {
            buyEnv  = (wyBuy  || po3Buy);
            sellEnv = (wySell || po3Sell);
         }

         const bool structMapOK = HasMarketStructure(sym, tf, dir, cfg);
         envOK = (structMapOK && (dir == DIR_BUY ? buyEnv : sellEnv));

         if(envOK)
            whyEnv = (dir == DIR_BUY ? "BUY regime+structure ok" : "SELL regime+structure ok");
         else if(!structMapOK)
            whyEnv = "HTF structure not aligned";
         else
            whyEnv = "environment not aligned";

          double alphaScore01 = _MainClamp01(finalQualityAdj);
          if(haveOFDS)
          {
             const double alphaFinalW = (testerLooseGate ? 0.85 : 0.70);
             const double alphaMicroW = (1.0 - alphaFinalW);
             alphaScore01 = _MainClamp01((alphaFinalW * alphaScore01) + (alphaMicroW * microAlpha01));
          }

          double executionScore01 =
             (testerLooseGate
                ? _MainClamp01((0.35 * finalQualityAdj) + (0.65 * microExec01))
                : _MainClamp01(microExec01));

          double riskScore01 =
             (testerLooseGate
                ? _MainClamp01((0.80 * microRisk01) + (0.20 * (1.0 - finalQualityAdj)))
                : _MainClamp01(microRisk01));

          string whyObsAdjust = "";

          if(haveOFDS)
          {
             const double obs01 =
                _MainClamp01(heads.ofds.observability01 > 0.0 ? heads.ofds.observability01
                                                              : (heads.ofds.direct_micro_available ? 1.00
                                                                                                   : (heads.ofds.proxy_micro_available ? 0.70 : 0.45)));

             const double obsPenalty01 = _MainClamp01(heads.ofds.observability_penalty01);
             const double truth01      = _MainClamp01(heads.ofds.truth_tier01);

             const bool continuationLike =
                (microArchetype == MAIN_MICRO_TREND || microArchetype == MAIN_MICRO_BREAKOUT);

             const double alphaObsMult =
                (continuationLike
                   ? (testerLooseGate ? (0.92 + (0.08 * obs01))
                                      : (0.85 + (0.15 * obs01)))
                   : (testerLooseGate ? (0.96 + (0.04 * obs01))
                                      : (0.93 + (0.07 * obs01))));

             const double execObsMult =
                (continuationLike
                   ? (testerLooseGate ? (0.90 + (0.10 * obs01))
                                      : (0.80 + (0.20 * obs01)))
                   : (testerLooseGate ? (0.94 + (0.06 * obs01))
                                      : (0.90 + (0.10 * obs01))));

             const double riskObsAdd =
                (continuationLike
                   ? (testerLooseGate
                        ? ((0.08 * obsPenalty01) + (0.04 * (1.0 - truth01)))
                        : ((0.18 * obsPenalty01) + (0.10 * (1.0 - truth01))))
                   : (testerLooseGate
                        ? ((0.04 * obsPenalty01) + (0.02 * (1.0 - truth01)))
                        : ((0.08 * obsPenalty01) + (0.04 * (1.0 - truth01)))));

             alphaScore01     = _MainClamp01(alphaScore01 * alphaObsMult);
             executionScore01 = _MainClamp01(executionScore01 * execObsMult);
             riskScore01      = _MainClamp01(riskScore01 + riskObsAdd);

             if(continuationLike && obsPenalty01 > 0.0)
                whyObsAdjust = (testerLooseGate
                                  ? "tester-loose continuation observability soft penalty"
                                  : "continuation/breakout observability penalty");
             else if(!continuationLike && obsPenalty01 > 0.0)
                whyObsAdjust = (testerLooseGate
                                  ? "tester-loose reversal observability soft penalty"
                                  : "reversal observability penalty");
          }

          if(!newsOK)
             riskScore01 = _MainClamp01(riskScore01 + (testerLooseGate ? 0.03 : 0.10));
          if(!volOK)
             riskScore01 = _MainClamp01(riskScore01 + (testerLooseGate ? 0.02 : 0.05));

         string whyHeads = "";
         bool headsOK =
            Main_HeadThresholdsPass(cfg,
                                    alphaScore01,
                                    executionScore01,
                                    riskScore01,
                                    whyHeads);

         if(whyObsAdjust != "")
         {
            if(whyHeads != "")
               whyHeads += " | ";
            whyHeads += whyObsAdjust;
         }

         if(testerDegradedMode && !headsOK && testerDegradedTags != "")
         {
            Main_ApplyTesterDegradedPenalty("tester_fallback_heads_soft",
                                            whyHeads,
                                            1.00,
                                            0.92,
                                            testerDegradedTags,
                                            testerDegradedScoreMult,
                                            testerDegradedRiskMult);
            headsOK = true;
         }

         const bool checklistGateOK = (!requireChecklist || checklistOK || checklistSoftFallback);

         const bool corePass =
            (checklistGateOK &&
             envOK &&
             triggerOK &&
             microOK &&
             poiVolumeOK &&
             confirmOK &&
             ictOK &&
             finalOK &&
             headsOK &&
             sbOK &&
             po3OK &&
             newsOK &&
             volOK &&
             (!requireClassical || classicalOK));

         if(!corePass && CfgTraceFlow(cfg))
         {
            const string d = (isBuy ? "BUY" : "SELL");

            if(!checklistOK && !checklistSoftFallback)
               TraceStrat(cfg, sym, tf, "FailChecklist", StringFormat("[MainLogicFail] %s checklist", d));

            if(!envOK)
               TraceStrat(cfg, sym, tf, "FailEnv", StringFormat("[MainLogicFail] %s env | %s", d, whyEnv));

            if(!triggerOK)
               TraceStrat(cfg, sym, tf, "FailTrigger",
                          StringFormat("[MainLogicFail] %s trigger | why=%s", d, whyTrigger));

            if(!microOK)
               TraceStrat(cfg, sym, tf, "FailMicro",
                          StringFormat("[MainLogicFail] %s micro | %s", d, whyMicro));

            if(!poiVolumeOK)
               TraceStrat(cfg, sym, tf, "FailPOIVol",
                          StringFormat("[MainLogicFail] %s poiVolume | %s", d, whyPOIVol));

            if(!confirmOK)
               TraceStrat(cfg, sym, tf, "FailConfirm",
                          StringFormat("[MainLogicFail] %s confirm | %s", d, whyConfirm));

            if(!classicalOK)
               TraceStrat(cfg, sym, tf, "FailClassical", StringFormat("[MainLogicFail] %s classical", d));

            if(!ictOK)
               TraceStrat(cfg, sym, tf, "FailICT",
                          StringFormat("[MainLogicFail] %s ict | ictScore=%.2f minICT=%.2f", d, ictScore, minICT));

            if(!finalOK)
               TraceStrat(cfg, sym, tf, "FailFinalQ",
                          StringFormat("[MainLogicFail] %s finalQ | finalAdj=%.2f q=%.2f", d, finalQualityAdj, qThresh));

            if(!headsOK)
               TraceStrat(cfg, sym, tf, "FailHeads",
                          StringFormat("[MainLogicFail] %s heads | %s", d, whyHeads));

            if(!sbOK)
               TraceStrat(cfg, sym, tf, "FailSB",
                          StringFormat("[MainLogicFail] %s SB | %s", d, whySB));

            if(!po3OK)
               TraceStrat(cfg, sym, tf, "FailPO3",
                          StringFormat("[MainLogicFail] %s PO3 | %s", d, whyPO3));

            if(!newsOK)
               TraceStrat(cfg, sym, tf, "FailNews", StringFormat("[MainLogicFail] %s news", d));

            if(!volOK)
               TraceStrat(cfg, sym, tf, "FailVol",
                          StringFormat("[MainLogicFail] %s vol | %s", d, whyVol));
         }

         if(corePass)
         {
            AugmentWithExtras_ifConfirmed(R, sym, tf, dir, cfg, ctx, newsComputed, newsOK, newsRiskMult, newsMinsLeft);
         }

         const bool finalEligible = corePass;

          // 8) Fill StratScore + ConfluenceBreakdown
          const double stage_score_checklist = _MainClamp01(legacyConfluenceScore);
          const double stage_score_raw_main  = _MainClamp01(alphaScore01);

          double stage_score_final_main = stage_score_raw_main;

          #ifdef MAIN_STRAT_APPLY_PROFILE_WEIGHT
             const double w = MainStratWeightLog::GetEffectiveMainWeight(cfg);
             stage_score_final_main = _MainClamp01(stage_score_final_main * w);
          #endif

          out.score_raw = stage_score_raw_main;
          out.score     = Main_NormalizeFinalStrategyScore(stage_score_final_main, finalEligible);

          Main_SetHeadScores(out, alphaScore01, executionScore01, riskScore01);
          Main_SetBreakdownHeadScores(bd, alphaScore01, executionScore01, riskScore01);

          out.eligible  = finalEligible;

          // Risk multiplier from config (base + main + continuation/reversal)
          out.risk_mult = Main_ComputeRiskMultiplier(cfg, withBias, againstBias);

          // Soft killzone mode reduces risk outside the window (no hard veto).
          out.risk_mult *= (kzRiskMult * po3HTFRiskMult * wyRiskMult * zRiskMult * volRiskMult * scanRiskMult * microRiskMult * testerDegradedRiskMult);

          bd.veto                = !finalEligible;
          bd.score_after_penalty = out.score;

          Main_DbgScoreStages(cfg,
                              sym,
                              tf,
                              dir,
                              stage_score_checklist,
                              finalQuality,
                              finalQualityAdj,
                              out.score_raw,
                              out.score,
                              executionScore01,
                              riskScore01,
                              finalEligible);

         if(out.reason == "")
            out.reason = StringFormat("Main core=%d eligible=%d", (int)corePass, (int)finalEligible);

         if(testerDegradedTags != "")
         {
            const string degradeNote = "tester_degraded=" + testerDegradedTags;

            if(out.reason != "")
               out.reason += " | " + degradeNote;
            else
               out.reason = degradeNote;

            if(R.summary != "")
               R.summary += ", " + degradeNote;
            else
               R.summary = degradeNote;

            bd.meta = degradeNote;
         }

         if(CfgDebugStrategies(cfg))
         {
            const string dirStr = (isBuy ? "BUY" : "SELL");

            string fail = "";
            if(!R.eligible)     _DbgAppendFail(fail, "coreMain");
            if(!envOK)          _DbgAppendFail(fail, "env");
            if(!triggerOK)      _DbgAppendFail(fail, "trigger");
            if(!microOK)        _DbgAppendFail(fail, "micro");
            if(!poiVolumeOK)    _DbgAppendFail(fail, "poiVol");
            if(!confirmOK)      _DbgAppendFail(fail, "confirm");
            if(!classicalOK)    _DbgAppendFail(fail, "classical");
            if(!ictOK)          _DbgAppendFail(fail, "ict");
            if(!finalOK)        _DbgAppendFail(fail, "finalQ");
            if(!headsOK)        _DbgAppendFail(fail, "heads");
            if(!sbOK)           _DbgAppendFail(fail, "SB");
            if(!po3OK)          _DbgAppendFail(fail, "PO3");
            if(!newsOK)         _DbgAppendFail(fail, "news");
            if(!volOK)          _DbgAppendFail(fail, "vol");

            const string msg =
               StringFormat("[DiagMain] sym=%s tf=%d dir=%s coreMain=%d env=%d trigger=%d micro=%d poiVol=%d confirm=%d classical=%d ict=%d finalQ=%d heads=%d SB=%d PO3=%d news=%d vol=%d"
                            " | cls=%.2f ict=%.2f final=%.2f q=%.2f"
                            " | alpha=%.2f exec=%.2f risk=%.2f microWhy=%s"
                            " | poiWhy=%s confirmWhy=%s headsWhy=%s"
                            " | volQ=%.2f volR=%.2f volWhy=%s"
                            " | met=%d score=%.2f"
                            " | fail=%s"
                            " | why=%s | ENV=%s | SB=%s | PO3=%s | PO3HTF=%s | WY=%s | Z=%s"
                            " | summary=%s",
                            sym, (int)tf, dirStr,
                            (R.eligible ? 1 : 0), (envOK ? 1 : 0), (triggerOK ? 1 : 0), (microOK ? 1 : 0), (poiVolumeOK ? 1 : 0), (confirmOK ? 1 : 0),
                            (classicalOK ? 1 : 0), (ictOK ? 1 : 0), (finalOK ? 1 : 0), (headsOK ? 1 : 0), (sbOK ? 1 : 0), (po3OK ? 1 : 0), (newsOK ? 1 : 0), (volOK ? 1 : 0),
                            classicalScore, ictScore, finalQuality, qThresh,
                            alphaScore01, executionScore01, riskScore01, whyMicro,
                            whyPOIVol, whyConfirm, whyHeads,
                            volQualMult, volRiskMult, whyVol,
                            R.metCount, R.score,
                            (fail == "" ? "none" : fail),
                            whyTrigger, whyEnv, whySB, whyPO3, whyPO3HTF, whyWyck, whyZones,
                            R.summary);

            DbgStrat(cfg, sym, tf, "DiagMainFull", msg, false);

            const string gateMsg =
               StringFormat("[DiagMainGates] sym=%s tf=%d dir=%s testerLoose=%d testerDegraded=%d newsBypass=%d kzMode=%d allowTradeNow=%d inKZ=%d sbOverride=%d kzScore=%.2f kzRisk=%.2f microA=%.2f microE=%.2f microR=%.2f microQ=%.2f microRM=%.2f newsMult=%.2f newsMins=%d finalAdj=%.2f qThresh=%.2f",
                             sym, (int)tf, dirStr,
                             (testerLooseGate ? 1 : 0),
                             (testerDegradedMode ? 1 : 0),
                             (testerSkipNewsCorr ? 1 : 0),
                             kzMode,
                             (allowTradeNow ? 1 : 0),
                             (inKZ ? 1 : 0),
                             (sbOverrideUsed ? 1 : 0),
                             kzScoreMult,
                             kzRiskMult,
                             microAlpha01,
                             microExec01,
                             microRisk01,
                             microQualMult,
                             microRiskMult,
                             newsRiskMult,
                             newsMinsLeft,
                             finalQualityAdj,
                             qThresh);
             DbgStrat(cfg, sym, tf, "DiagMainGates", gateMsg, false);

            const string checklistMsg =
               StringFormat("[DiagMainChecklist] sym=%s tf=%d dir=%s checklistOK=%d fallbackMode=%d fallbackUsed=%d scoreMult=%.2f riskMult=%.2f finalEligible=%d",
                            sym, (int)tf, dirStr,
                            (checklistOK ? 1 : 0),
                            (checklistSoftFallbackMode ? 1 : 0),
                            (checklistSoftFallback ? 1 : 0),
                            checklistPenaltyScoreMult,
                            checklistPenaltyRiskMult,
                            (finalEligible ? 1 : 0));
            DbgStrat(cfg, sym, tf, "DiagMainChecklist", checklistMsg, false);

            if(testerDegradedTags != "")
            {
               const string dmsg =
                  StringFormat("[MainTesterDegraded] sym=%s tf=%d dir=%s tags=%s",
                               sym, (int)tf, dirStr, testerDegradedTags);
               DbgStrat(cfg, sym, tf, "TesterDegradedTrace", dmsg, false);
            }
         }
         
         // Per-call debug hook (unthrottled) as requested
         if(CfgDebugStrategies(cfg))
         {
            const bool bos      = ctx.bosContinuationDetected;
            const bool choch    = ctx.chochDetected;
         
            const double px =
               (SymbolInfoDouble(sym, SYMBOL_BID) > 0.0 ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                       : iClose(sym, tf, 1));
         
            const double bid = SymbolInfoDouble(sym, SYMBOL_BID);
            const double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
            const double mid = (bid > 0.0 && ask > 0.0 ? (bid + ask) * 0.5 : px);
            ICTOrderBlock obPick; string obSrc = "";
            ICTFVG        fvgPick; string fvgSrc = "";
            
            const bool hasOB  = StratMainLogic::PickBestOBForDir(ctx, isBuy, obPick, obSrc);
            const bool hasFVG = StratMainLogic::PickBestFVGForDir(ctx, isBuy, fvgPick, fvgSrc);
            
            const bool ob_ok  = (hasOB  && StratMainLogic::_BandContains(mid, obPick.low,  obPick.high));
            const bool fvg_ok = (hasFVG && StratMainLogic::_BandContains(mid, fvgPick.low, fvgPick.high));
         
            const bool sweep_ok =
               (isBuy
                  ? (ctx.liquiditySweepType == SWEEP_SELLSIDE || ctx.liquiditySweepType == SWEEP_BOTH)
                  : (ctx.liquiditySweepType == SWEEP_BUYSIDE  || ctx.liquiditySweepType == SWEEP_BOTH));
         
            const bool pd_ok =
               (px >= MathMin(ctx.oteZone.lower, ctx.oteZone.upper) &&
                px <= MathMax(ctx.oteZone.lower, ctx.oteZone.upper));
         
            const bool eligible = finalEligible;
            const bool veto     = !finalEligible;
            const double score  = out.score;
         
              #ifndef STRAT_MAIN_DISABLE_TELEMETRY_NOTES
                 Print("[MainLogic] dir=", (int)dir,
                       " bos=", (bos?1:0),
                       " choch=", (choch?1:0),
                       " fvg=", (fvg_ok?1:0),
                       " ob=", (ob_ok?1:0),
                       " sweep=", (sweep_ok?1:0),
                       " pd=", (pd_ok?1:0),
                       " eligible=", (eligible?1:0),
                       " veto=", (veto?1:0),
                       " score=", score);
              #endif
         }

         return finalEligible;
      }

      bool Evaluate(const string sym, const Direction dir, const Settings &cfg, const ICT_Context &ctx,
                    StratScore &out, ConfluenceBreakdown &bd)
      {
         AutoSnapshot autoS;
         bool haveAuto = false;
         
         AutoVol::AutoVolStats av;
         bool haveAv = false;
         
         const bool ok = EvaluateEx(sym, dir, cfg, ctx, out, bd, autoS, haveAuto, av, haveAv);
      
         if(ok)
            return true;
      
         if(Main_ApplyTesterForcedScore(out, bd))
            return true;
      
         return false;
      }

      // Backward compatible wrapper (chart symbol). Prefer the symbol-safe overload in routing.
      bool Evaluate(const Direction      dir,
                    const Settings      &cfg,
                    const ICT_Context   &ctx,
                    StratScore          &out,
                    ConfluenceBreakdown &bd)
      {
         return Evaluate(_Symbol, dir, cfg, ctx, out, bd);
      }
      
      // ============================================================================
      // Router-friendly entry API (Main strategy)
      // ============================================================================
      bool ComputeEntryMain_Core(const string sym, const ENUM_TIMEFRAMES tf_entry, const Direction dir, const Settings &cfg,
                           const ICT_Context &ctx, const bool haveAuto, const AutoSnapshot &autoS,
                           const bool haveAv, const AutoVol::AutoVolStats &av, MainEntryPlan &outPlan)
      {
         // 2) Select preferred entry/invalidation anchors
         const bool isBuy = (dir == DIR_BUY);

         double entryPx = 0.0;
         double invalPx = 0.0;
         string src     = "";

         if(!Main_SelectAnchors(ctx, isBuy, entryPx, invalPx, src))
         {
            outPlan.reason = "Main eligible but no entry anchors found (no OB/FVG/OTE)";
            return false;
         }

         // 3) Choose order type hint
         const double point = SymbolInfoDouble(sym, SYMBOL_POINT);
         const double pxNow = (isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID));

         const int atrPeriod = (cfg.atr_period > 0 ? (int)cfg.atr_period : 14);
         double atr_pts_entry = 0.0;
         
         // Prefer cached AutoVol ATR for D1/H1 if tf_entry matches, else fall back to MarketData ATRPoints.
         if(haveAv)
         {
            if(tf_entry == PERIOD_H1)      atr_pts_entry = av.atr_h1_pts;
            else if(tf_entry == PERIOD_D1) atr_pts_entry = av.atr_d1_pts;
         }
         
         if(atr_pts_entry <= 0.0)
            atr_pts_entry = MarketData::ATRPoints(sym, tf_entry, atrPeriod, 1);

         double nearPts = (point > 0.0 ? 10.0 * point : 0.0);
         #ifdef CFG_HAS_MAIN_ENTRY_NEAR_POINTS
            if(cfg.main_entry_near_points > 0.0)
               nearPts = cfg.main_entry_near_points;
         #endif

         outPlan.order_type      = Main_ChooseOrderType(isBuy, pxNow, entryPx, nearPts);
         outPlan.preferred_entry = entryPx;
         outPlan.invalidation    = invalPx;

          // --- AutoC chart pass computed once, reused (no double-ups) ---
          const bool wantAutoChart = (haveAuto && cfg.auto_enable && cfg.cf_autochartist_chart);
          const bool chartExists   = (wantAutoChart && autoS.chart.kind != AUTO_CHART_NONE);
          const bool chartDirKnown = (chartExists && autoS.chart.dir_known);

          // 4.4A Completed chart direction mismatch veto (independent of AutoC_ChartOK quality gate)
          if(chartDirKnown && autoS.chart.completed)
          {
             const bool dirMismatch = (autoS.chart.bullish != isBuy);

             bool vetoMismatch = kMain_GateDirMismatch_Completed;
             #ifdef CFG_HAS_MAIN_AUTOC_COMPLETED_DIR_VETO
                vetoMismatch = cfg.main_autoc_completed_dir_mismatch_veto;
             #endif

             if(vetoMismatch && dirMismatch)
             {
                outPlan.reason = "Main blocked (AutoC completed pattern direction mismatch)";
                return false;
             }
          }

          bool autoChartPass = false;
          double qChart = 0.0;
          bool chartDataOk = haveAuto;

          if(wantAutoChart)
             autoChartPass = AutoC_ChartOK_FromSnap(sym, tf_entry, dir, cfg, autoS, qChart, chartDataOk);

          // 4.4B Entry gating using chart state + retest depth (COMPLETED only, direction already matched by AutoC_ChartOK)
          if(autoChartPass && chartDataOk && autoS.chart.completed)
          {
             if(autoS.chart.break_level > 0.0 && point > 0.0)
             {
                if(atr_pts_entry > 0.0)
                {
                   const double retestDepthPts = MathAbs(outPlan.preferred_entry - autoS.chart.break_level) / point;

                   double maxRetestATR = kMain_ChartRetestMaxATR;
                   #ifdef CFG_HAS_MAIN_CHART_RETEST_MAX_ATR
                      if(cfg.main_chart_retest_max_atr > 0.0) maxRetestATR = cfg.main_chart_retest_max_atr;
                   #endif

                   if(retestDepthPts > (maxRetestATR * atr_pts_entry))
                   {
                      outPlan.reason = StringFormat("Main blocked (AutoC retest depth %.1f pts > %.2f*ATR=%.1f pts)",
                                                   retestDepthPts, maxRetestATR, (maxRetestATR * atr_pts_entry));
                      return false;
                   }
                }
             }
          }

         // 4) Pending order expiry (TTL / session clamp)
         if(outPlan.order_type != ORDER_TYPE_BUY && outPlan.order_type != ORDER_TYPE_SELL)
         {
            const datetime now = TimeCurrent();
            outPlan.expiry_time = Main_ComputePendingExpiryTime(ctx, cfg, now);
            outPlan.has_expiry  = (outPlan.expiry_time > now);
         }

         // 4.5 SL/TP sizing: wire target1 from chart target (RR-qualified, no competing TP builders)
         if(autoChartPass && chartDataOk)
         {
            bool tightenInval = false;
            #ifdef CFG_HAS_MAIN_AUTOC_TIGHTEN_INVAL
               tightenInval = cfg.main_autoc_tighten_invalidation;
            #endif
            if(tightenInval)
            {
               // Optional: tighten invalidation using break_level (COMPLETED only)
               if(autoS.chart.completed && autoS.chart.break_level > 0.0 && outPlan.invalidation > 0.0)
               {
                  if(point > 0.0 && atr_pts_entry > 0.0)
                  {
                     const double buf = MathMax(2.0, 0.25 * atr_pts_entry) * point;
   
                     if(isBuy)
                     {
                        const double inval_candidate = autoS.chart.break_level - buf;
                        if(inval_candidate > outPlan.invalidation && inval_candidate < outPlan.preferred_entry)
                           outPlan.invalidation = inval_candidate;
                     }
                     else
                     {
                        const double inval_candidate = autoS.chart.break_level + buf;
                        if(inval_candidate < outPlan.invalidation && inval_candidate > outPlan.preferred_entry)
                           outPlan.invalidation = inval_candidate;
                     }
                  }
               }
            }

            // Set target1 only if empty and RR meets threshold
            if(outPlan.target1 <= 0.0 && autoS.chart.target_price > 0.0)
            {
               const bool targetInDir =
                  (isBuy  && autoS.chart.target_price > outPlan.preferred_entry) ||
                  (!isBuy && autoS.chart.target_price < outPlan.preferred_entry);

               if(targetInDir)
               {
                  const double stopDist = MathAbs(outPlan.preferred_entry - outPlan.invalidation);

                  if(stopDist > (point > 0.0 ? 2.0 * point : 0.0))
                  {
                     const double rr = MathAbs(autoS.chart.target_price - outPlan.preferred_entry) / stopDist;
                     double minRR = kMain_MinRR_FromChartTarget;
                     #ifdef CFG_HAS_MAIN_MIN_RR_FROM_CHART_TARGET
                        if(cfg.main_min_rr_from_chart_target > 0.0) minRR = cfg.main_min_rr_from_chart_target;
                     #endif

                     if(rr >= minRR)
                         outPlan.target1 = autoS.chart.target_price;
                  }
               }
            }
         }

         outPlan.valid  = true;
         outPlan.reason = StringFormat("MainEntry ok src=%s type=%d entry=%.5f inval=%.5f score=%.2f risk=%.2f",
                                       src, (int)outPlan.order_type, outPlan.preferred_entry, outPlan.invalidation,
                                       outPlan.score, outPlan.risk_mult);
         return true;
      }

      bool ComputeEntryMain(const string          sym,
                            const ENUM_TIMEFRAMES tf_entry,
                            const Direction       dir,
                            const Settings       &cfg,
                            const ICT_Context    &ctx,
                            MainEntryPlan        &outPlan)
      {
         outPlan.valid          = false;
         outPlan.sym            = sym;
         outPlan.dir            = dir;
         outPlan.order_type     = ORDER_TYPE_BUY;
         outPlan.preferred_entry= 0.0;
         outPlan.invalidation   = 0.0;
         outPlan.target1        = 0.0;
         outPlan.expiry_time    = (datetime)0;
         outPlan.has_expiry     = false;
         outPlan.score          = 0.0;
         outPlan.score_raw      = 0.0;
         outPlan.risk_mult      = 1.0;
         outPlan.reason         = "";
      
         // 1) Run canonical Main evaluation (no execution)
         ConfluenceBreakdown bdTmp; ZeroMemory(bdTmp);
         StratScore          ssTmp; ZeroMemory(ssTmp);
      
         // Use the symbol-safe overload you will add in Step 3 (see below)
         AutoSnapshot autoS;
         bool haveAuto = false;
         
         AutoVol::AutoVolStats av;
         bool haveAv = false;
         
         const bool ok = EvaluateEx(sym, dir, cfg, ctx, ssTmp, bdTmp, autoS, haveAuto, av, haveAv);
         const bool eligible = (ok && ssTmp.eligible);
      
         outPlan.score     = ssTmp.score;
         outPlan.score_raw = ssTmp.score_raw;
         outPlan.risk_mult = (ssTmp.risk_mult > 0.0 ? ssTmp.risk_mult : 1.0);
      
         if(!eligible)
         {
            outPlan.reason = "Main blocked (evaluation not eligible)";
            return false;
         }
      
         return ComputeEntryMain_Core(sym, tf_entry, dir, cfg, ctx, haveAuto, autoS, haveAv, av, outPlan);
      }
      
      bool ComputeEntryMain_FromState(const string          sym,
                                     const ENUM_TIMEFRAMES tf_entry,
                                     const Direction       dir,
                                     const Settings       &cfg,
                                     MainEntryPlan        &outPlan)
      {
         ICT_Context ctx;
         Main_LoadCanonicalICTContext(sym, cfg, ctx);
      
         return ComputeEntryMain(sym, tf_entry, dir, cfg, ctx, outPlan);
      }

      // Lightweight gate so other modules can reuse Main�s confirmation.
      // Wraps the canonical Evaluate(dir,cfg,ctx,...) and returns only score+summary.
      bool GateConfirmed(const Direction dir,
                         const Settings  &cfg,
                         double          &out_score,
                         string          &out_summary)
      {
         ConfluenceBreakdown bdTmp; ZeroMemory(bdTmp);
         StratScore          ssTmp; ZeroMemory(ssTmp);
         ICT_Context ctx;
         Main_LoadCanonicalICTContext(_Symbol, cfg, ctx);

         // --- Enriched killzone summary (so GateConfirmed explains "why no trade") ---
         string kzNote = "KZ=OFF";
         
         const int kzMode = CfgKillzoneMode(cfg);
         bool inKZ = false;
         bool sbOverrideUsed = false;
         bool allowTradeNow = true;
         
         if(kzMode != KZ_MODE_OFF)
         {
            allowTradeNow = ICTCtx_AllowTradeNow(ctx, cfg, inKZ, sbOverrideUsed);
         
            if(kzMode == KZ_MODE_HARD && !allowTradeNow)
            {
               kzNote = StringFormat("blocked by killzone hard (inKZ=%d sbOverride=%d)",
                                     (inKZ ? 1 : 0), (sbOverrideUsed ? 1 : 0));
            }
            else if(kzMode == KZ_MODE_SOFT && !allowTradeNow)
            {
               const double scoreMult = CfgKillzoneSoftPenalty(cfg);
               const double riskMult  = CfgKillzoneSoftRiskMult(cfg);
         
               kzNote = StringFormat("soft penalty applied (scoreMult=%.2f riskMult=%.2f inKZ=%d sbOverride=%d)",
                                     scoreMult, riskMult,
                                     (inKZ ? 1 : 0), (sbOverrideUsed ? 1 : 0));
            }
            else
            {
               kzNote = StringFormat("killzone ok (inKZ=%d sbOverride=%d)",
                                     (inKZ ? 1 : 0), (sbOverrideUsed ? 1 : 0));
            }
         }
      
         const bool ok = Evaluate(_Symbol, dir, cfg, ctx, ssTmp, bdTmp);
         
         out_score = ssTmp.score;
         
         // Rich summary: direction + eligibility + score + killzone resolution
         out_summary =
            StringFormat("MainEval dir=%s eligible=%s score=%.2f | %s",
                         (dir == DIR_BUY ? "BUY" : "SELL"),
                         (ssTmp.eligible ? "YES" : "NO"),
                         ssTmp.score,
                         kzNote);
         
         return ssTmp.eligible;
      }
      
      #ifdef CFG_HAS_CANDIDATE_PIPELINE
      bool EvaluateToCandidate(const string sym, const Direction dir, const Settings &cfg,
                               const ICT_Context  &ctx, Candidate &outC, string &outWhy)
      {
         ConfluenceBreakdown bdTmp; ZeroMemory(bdTmp);
         StratScore          ssTmp; ZeroMemory(ssTmp);
      
         AutoSnapshot autoS;
         bool haveAuto = false;
         
         AutoVol::AutoVolStats av;
         bool haveAv = false;
         
         const bool ok = EvaluateEx(sym, dir, cfg, ctx, ssTmp, bdTmp, autoS, haveAuto, av, haveAv);
         const bool eligible = (ok && ssTmp.eligible);
      
         if(!eligible)
         {
            outWhy = (ssTmp.reason != "" ? ssTmp.reason : "candidate blocked");
            return false;
         }

         Main_CandidateInit(outC, sym, dir);

         MainEntryPlan plan;

         plan.valid           = false;
         plan.sym             = sym;
         plan.dir             = dir;
         plan.order_type      = ORDER_TYPE_BUY;
         plan.preferred_entry = 0.0;
         plan.invalidation    = 0.0;
         plan.target1         = 0.0;
         plan.has_expiry      = false;
         plan.expiry_time     = 0;
         plan.score           = ssTmp.score;
         plan.score_raw       = ssTmp.score_raw;
         plan.risk_mult       = (ssTmp.risk_mult > 0.0 ? ssTmp.risk_mult : 1.0);
         plan.reason          = "";

         if(!ComputeEntryMain_Core(sym,
                                   (ENUM_TIMEFRAMES)cfg.tf_entry,
                                   dir,
                                   cfg,
                                   ctx,
                                   haveAuto,
                                   autoS,
                                   haveAv,
                                   av,
                                   plan))
         {
            outWhy = plan.reason;
            return false;
         }

         if(ssTmp.reason != "" && plan.reason != "")
            ssTmp.reason = ssTmp.reason + " | " + plan.reason;
         else if(plan.reason != "")
            ssTmp.reason = plan.reason;

         Main_CandidateApplyPayload(outC, ssTmp, bdTmp, plan);

         outWhy =
            StringFormat("candidate ok | dir=%s score=%.2f raw=%.2f risk=%.2f entry=%.5f sl=%.5f tp=%.5f",
                         (dir == DIR_BUY ? "BUY" : "SELL"),
                         ssTmp.score,
                         ssTmp.score_raw,
                         (ssTmp.risk_mult > 0.0 ? ssTmp.risk_mult : 1.0),
                         plan.preferred_entry,
                         plan.invalidation,
                         plan.target1);

         return true;
      }

      bool EvaluateBestCandidate(const string      sym,
                                 const Settings   &cfg,
                                 const ICT_Context &ctx,
                                 Candidate        &bestCand,
                                 string           &outWhy)
      {
         Candidate candBuy;
         Candidate candSell;
         string whyBuy  = "";
         string whySell = "";

         Main_CandidateInit(candBuy,  sym, DIR_BUY);
         Main_CandidateInit(candSell, sym, DIR_SELL);
         Main_CandidateInit(bestCand, sym, DIR_BOTH);

         const bool okBuy  = EvaluateToCandidate(sym, DIR_BUY,  cfg, ctx, candBuy,  whyBuy);
         const bool okSell = EvaluateToCandidate(sym, DIR_SELL, cfg, ctx, candSell, whySell);

         const bool ok = Main_SelectPreferredCandidate(okBuy, candBuy,
                                                       okSell, candSell,
                                                       bestCand, outWhy);

         if(!ok && outWhy == "")
            outWhy = (whyBuy != "" ? whyBuy : whySell);

         return ok;
      }

      bool EvaluateBestCandidate(const Settings    &cfg,
                                 const ICT_Context &ctx,
                                 Candidate        &bestCand,
                                 string           &outWhy)
      {
         return EvaluateBestCandidate(_Symbol, cfg, ctx, bestCand, outWhy);
      }

      #endif // CFG_HAS_CANDIDATE_PIPELINE
 
     // ---------------- Confluence wrappers (closed-bar safe) ----------------
     bool HasMarketStructure(const string sym, const ENUM_TIMEFRAMES /*tf*/, const Direction dir, const Settings &cfg)
     {
       // HTF alignment check example (H4 vs D1); adjust to your API
       const bool isBuy = (dir==DIR_BUY);
       return ADP_SDOB_AlignedWithPivots(sym, (ENUM_TIMEFRAMES)cfg.tf_h4, (ENUM_TIMEFRAMES)cfg.tf_d1, isBuy);
     }
   
     bool HasInstitutionalZoneNearET(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
      {
         const bool isBuy = (dir==DIR_BUY);
      
         // 1) Must have a valid SD/OB institutional zone near entry TF (existing behavior)
         const bool zoneNear = ADP_SDOB_HasInstitutionalZoneNear(sym, tf, isBuy);
         if(!zoneNear) return false;
      
         // 2) Pivot anchoring (Daily/Weekly pivots, ATR-normalized proximity)
         // Uses include/PivotsLevels.mqh which is already included at the top of this file.
         double prox = 0.0, level = 0.0;
         string lvlName = "";
      
         // Desired max distance (ATR multiples). Prefer a dedicated knob if you add it later.
         double maxDistATR = 0.80;
         #ifdef CFG_HAS_MAIN_PIVOT_MAX_DIST_ATR
            maxDistATR = cfg.main_pivot_max_dist_atr;
         #else
            // Reasonable fallback: reuse MTF zone distance if present, but clamp it.
            maxDistATR = MathMax(0.40, MathMin(1.20, cfg.mtf_zone_max_dist_atr));
         #endif
      
         // prox = 1 - (distATR/2). So distATR <= maxDistATR  <=> prox >= 1 - maxDistATR/2
         const double thresh = MathMax(0.0, 1.0 - (maxDistATR * 0.5));
      
         bool nearPivot = Pivots::IsNearAnyDailyWeeklyPivot(sym, (ENUM_TIMEFRAMES)cfg.tf_h4, cfg.atr_period, thresh, lvlName, level);
      
         // If pivots aren't available (lvlName empty), do NOT starve trades�treat as neutral.
         if(lvlName == "") nearPivot = true;
      
         return nearPivot;
      }
   
      bool HasOrderFlowDeltaIncreaseEx(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, bool &dataOk)
      {
         Scan::IndiSnapshot s;
         MainOFDS ofds;

         if(Main_TryLoadOFDS(sym, tf, s, ofds) && ofds.have_flow)
         {
            dataOk = true;
            const double th = ADP_OrderflowTh(cfg);
            const double flow = (dir == DIR_BUY ? ofds.flow_dir : -ofds.flow_dir);
            return (flow >= th);
         }

         double z = 0.0;
         dataOk = ADP_DeltaSlopeZ(sym, tf, 25, z);
         if(!dataOk) return false;

         const double th = ADP_OrderflowTh(cfg);
         if(dir == DIR_BUY)  return (z >= +th);
         return (z <= -th);
      }
      
     bool HasOrderFlowDeltaIncrease(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
     {
       bool dataOk = false;
       return HasOrderFlowDeltaIncreaseEx(sym, tf, dir, cfg, dataOk);
     }
   
      bool HasLiquidityPoolContext(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
      {
         const bool isBuy = (dir == DIR_BUY);
      
         Scan::IndiSnapshot s;
         if(StratScan::TryGetScanSnap(sym, tf, s) && StratScan::SnapReady(s))
         {
            bool scanIsAuthoritative = false;
            const bool ok = Main_TryLiquidityContextFromScan(s, tf, dir, cfg, scanIsAuthoritative);
      
            if(scanIsAuthoritative)
               return ok;
         }
      
         return ADP_LIQ_PoolOrInducementNearby(sym, tf, isBuy);
      }
   
     bool HasOrderBlockProximity(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &/*cfg*/)
     {
       const bool isBuy = (dir==DIR_BUY);
       return ADP_SDOB_OrderBlockInProximity(sym, tf, isBuy);
     }
   
     bool HasVSAIncreaseAtLocationEx(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, const int poiKind, const double poiPrice, bool &dataOk)
     {
        // Prefer scanner outputs (downstream consumption). No local indicator/VSA recomputation if Scan is live.
        dataOk = false;
      
        Scan::IndiSnapshot ss;
        if(StratScan::TryGetScanSnap(sym, tf, ss) && StratScan::SnapReady(ss))
        {
          dataOk = true;
      
          // Map VSA bits to direction using VSA.mqh semantics:
          // BUY confirmations: No Supply, Selling Climax, Stopping Vol (bull), Spring
          // SELL confirmations: No Demand, Buying Climax, Stopping Vol (bear), Upthrust
          const uint bullMask =
            (uint)VSA::SIGF_NO_SUPPLY |
            (uint)VSA::SIGF_SELL_CLIMAX |
            (uint)VSA::SIGF_STOPVOL_BULL |
            (uint)VSA::SIGF_SPRING;
      
          const uint bearMask =
            (uint)VSA::SIGF_NO_DEMAND |
            (uint)VSA::SIGF_BUY_CLIMAX |
            (uint)VSA::SIGF_STOPVOL_BEAR |
            (uint)VSA::SIGF_UPTHRUST;
      
          if(dir == DIR_BUY)  return ((ss.vsa_mask & bullMask) != 0);
          if(dir == DIR_SELL) return ((ss.vsa_mask & bearMask) != 0);
          return false;
        }
      
        // Fallback only if scanner is not active / TF not scanned
        #ifdef HAVE_VSA_PHASE_STATE
        if(poiKind <= 0 || poiPrice <= 0.0)
           return false;

        VSA::PhaseState ps;
        if(!VSA::GetPhaseState(sym, tf, cfg.vsa_lookback, ps))
           return false;

        const double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
        if(pt <= 0.0)
           return false;

        const double px = iClose(sym, tf, 1);
        if(px <= 0.0)
           return false;

        const int atrPeriod = 14;
        const double atr_pts = Indi::ATRPoints(sym, tf, atrPeriod, 1);

        double nearBand = 10.0 * pt;
        if(atr_pts > 0.0)
        {
           const double atrMul = (poiKind == 1 ? 0.50 : 0.35);
           nearBand = MathMax(nearBand, atrMul * atr_pts * pt);
        }

        if(MathAbs(px - poiPrice) > nearBand)
           return false;

        dataOk = true;

        double biasMin = cfg.vsa_poi_aggr_min;
        if(biasMin <= 0.0)
           biasMin = 0.55;
        if(biasMin > 0.95)
           biasMin = 0.95;

        const double lead = 0.05;

        if(dir == DIR_BUY)
           return (ps.buyBias >= biasMin && ps.buyBias > ps.sellBias + lead);

        if(dir == DIR_SELL)
           return (ps.sellBias >= biasMin && ps.sellBias > ps.buyBias + lead);

        return false;
        #else
        return false;
        #endif
     }

     bool HasVSAIncreaseAtLocationEx(const string sym,
                                     const ENUM_TIMEFRAMES tf,
                                     const Direction dir,
                                     const Settings &cfg,
                                     bool &dataOk)
     {
        return HasVSAIncreaseAtLocationEx(sym, tf, dir, cfg, 0, 0.0, dataOk);
     }

     bool HasVSAIncreaseAtLocation(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
     {
       bool dataOk = false;
       return HasVSAIncreaseAtLocationEx(sym, tf, dir, cfg, dataOk);
     }
   
     bool HasBullBearCandlePattern(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &/*cfg*/)
     {
       const bool isBuy = (dir==DIR_BUY);
       return ADP_PAT_HasCandlePattern(sym, tf, isBuy);
     }
   
     bool HasBullBearChartPattern(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &/*cfg*/)
     {
       const bool isBuy = (dir==DIR_BUY);
       return ADP_PAT_HasChartPattern(sym, tf, isBuy);
     }
   
     inline double _Clamp01(const double v){ return (v<0.0?0.0:(v>1.0?1.0:v)); }

     // --- AutoC/Main tuning defaults (compile-safe; expose to Config later if desired) ---
     static const double kAutoC_RR_Norm                = 2.0;   // 2*ATR distance => rr01 ~ 1
     static const double kMain_ChartRetestMaxATR       = 1.0;   // entry must be within 1*ATR of breakout level
     static const double kMain_MinRR_FromChartTarget   = 1.2;   // only use chart target as TP anchor if >= 1.2R
     static const bool   kMain_GateDirMismatch_Completed = false; // optional veto on completed dir mismatch

     inline bool AutoC_ChartOK_FromSnap(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                         const Settings &cfg, const AutoSnapshot &s, double &q01, bool &dataOk)
      {
         q01 = 0.0;
         dataOk = false;

         if(!cfg.auto_enable || !cfg.cf_autochartist_chart)
            return false;

         // Snapshot exists, but pattern may or may not exist
         dataOk = true;

         if(s.chart.kind == AUTO_CHART_NONE)
            return false;

         // If direction is unknown, treat as "no usable data" (N/A)
         if(!s.chart.dir_known)
         {
            dataOk = false;
            return false;
         }

         const bool isBuy = (dir == DIR_BUY);

         // Direction must match
         if(s.chart.bullish != isBuy)
            return false;

         // Base quality is state-aware (NO target scaling here)
         double qBase = 0.0;

         if(s.chart.completed)
         {
            qBase = (s.chart.q.clarity +
                     s.chart.q.initial_trend +
                     s.chart.q.uniformity +
                     s.chart.q.breakout_strength) / 4.0;
         }
         else
         {
            qBase = (s.chart.q.clarity +
                     s.chart.q.initial_trend +
                     s.chart.q.uniformity) / 3.0;
         }

         q01 = _Clamp01(qBase);

         // Quality gate (still applies)
         if(q01 < cfg.auto_chart_min_quality)
            return false;

         // Emerging patterns must have a usable boundary range
         if(!s.chart.completed)
         {
            if(s.chart.bound_dn <= 0.0 || s.chart.bound_up <= 0.0 || s.chart.bound_up <= s.chart.bound_dn)
               return false;
         }

         return true;
      }

      inline double AutoC_ChartScore01_FromSnap(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                                const Settings &cfg, const AutoSnapshot &s, const double qBase01)
      {
         double q = _Clamp01(qBase01);
         if(q <= 0.0)
            return 0.0;

         // State boost (completed stronger than emerging)
         const double stateBoost = (s.chart.completed ? 1.0 : 0.70);

         // Optional target factor (NOT a gate)
         double targetFactor = 1.0;

         if(s.chart.target_price > 0.0)
         {
            const bool isBuy = (dir == DIR_BUY);

            // Only apply if target is in-direction relative to price reference
            const double priceRef = iClose(sym, tf, 1);
            const double pt = SymbolInfoDouble(sym, SYMBOL_POINT);

            if(priceRef > 0.0 && pt > 0.0)
            {
               const bool targetInDir =
                  (isBuy  && s.chart.target_price > priceRef) ||
                  (!isBuy && s.chart.target_price < priceRef);

               if(targetInDir)
               {
                  const int atrPeriod = (cfg.atr_period > 0 ? (int)cfg.atr_period : 14);
                  const double atr_pts = Indi::ATRPoints(sym, tf, atrPeriod, 1);

                  if(atr_pts > 0.0)
                  {
                     const double distPts = MathAbs(s.chart.target_price - priceRef) / pt;
                     double rrNorm = kAutoC_RR_Norm;
                     #ifdef CFG_HAS_AUTOCHART_RR_NORM
                        if(cfg.auto_chart_rr_norm > 0.0) rrNorm = cfg.auto_chart_rr_norm;
                     #endif
                     const double rr01 = _Clamp01(distPts / (atr_pts * rrNorm));

                     targetFactor = 0.7 + 0.3 * rr01;
                  }
               }
            }
         }

         return _Clamp01(q * stateBoost * targetFactor);
      }

     inline bool AutoC_ChartCONFIRM_FromSnap(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                              const Settings &cfg, const AutoSnapshot &s, double &q01, bool &dataOk)
      {
         if(!AutoC_ChartOK_FromSnap(sym, tf, dir, cfg, s, q01, dataOk))
            return false;

         // Sequential confirmations require completion
         if(!s.chart.completed)
            return false;

         return true;
      }

     inline bool AutoC_ChartOK(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, double &q01)
     {
         AutoSnapshot s;
         if(!AutoC::GetSnapshot(sym, tf, cfg, s))
         {
            q01 = 0.0;
            return false;
         }
      
         bool dataOk = true;
         return AutoC_ChartOK_FromSnap(sym, tf, dir, cfg, s, q01, dataOk);
      }
   
     inline bool AutoC_ChartOKEx(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                 const Settings &cfg, double &q01, bool &dataOk)
      {
         q01 = 0.0;
         dataOk = true;
      
         if(!cfg.auto_enable || !cfg.cf_autochartist_chart)
         {
            dataOk = false;
            return false;
         }
      
         AutoSnapshot s;
         if(!AutoC::GetSnapshot(sym, tf, cfg, s))
         {
            dataOk = false;
            return false;
         }
      
         return AutoC_ChartOK_FromSnap(sym, tf, dir, cfg, s, q01, dataOk);
      }

     inline bool AutoC_FibOK(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, double &q01)
     {
        q01 = 0.0;
        if(!cfg.auto_enable || !cfg.cf_autochartist_fib) return false;
   
        AutoSnapshot s;
        if(!AutoC::GetSnapshot(sym, tf, cfg, s)) return false;
   
        return AutoC_FibOK_FromSnap(sym, tf, dir, cfg, s, q01);
     }
   
     inline bool AutoC_FibOK_FromSnap(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                       const Settings &cfg, const AutoSnapshot &s, double &q01)
      {
         q01 = 0.0;

         if(!cfg.auto_enable || !cfg.cf_autochartist_fib)
            return false;

         if(s.fib.kind == AUTO_FIB_NONE)
            return false;

         const bool isBuy = (dir == DIR_BUY);

         // Direction must match
         if(s.fib.bullish != isBuy)
            return false;

         const double qOverall = _Clamp01(s.fib.q.overall);
         const double qFit01   = _Clamp01(s.fib.q.uniformity);
         
         // 1) Overall quality must pass existing threshold
         if(qOverall < cfg.auto_fib_min_quality)
            return false;
         
         // 2) Ratio-fit / uniformity must pass (local constant to avoid Config churn)
         const double minRatioFit = 0.55;
         if(qFit01 < minRatioFit)
            return false;
         
         // 3) Must have non-trivial confidence
         if(s.fib.confidence01 <= 0.0)
            return false;
         
         // 4) PRZ touched / approaching
         const double lo = s.fib.prz_lo;
         const double hi = s.fib.prz_hi;
         
         if(lo <= 0.0 || hi <= 0.0 || hi < lo)
            return false;
         
         const double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
         const double px = iClose(sym, tf, 1);
         
         if(pt <= 0.0 || px <= 0.0)
            return false;
         
         const int atrPeriod = (cfg.atr_period > 0 ? (int)cfg.atr_period : 14);
         const double atr_pts = Indi::ATRPoints(sym, tf, atrPeriod, 1);
         
         bool przOK = (px >= lo && px <= hi);
         
         if(!przOK)
         {
            double approach = 0.0;
            if(atr_pts > 0.0)
               approach = atr_pts * pt * 0.35; // �approaching� distance = 0.35 ATR (price)
         
            const double dist = (px < lo) ? (lo - px) : (px > hi ? (px - hi) : 0.0);
            przOK = (approach > 0.0 && dist <= approach);
         }
         
         if(!przOK)
            return false;
         
         // Quality scalar used by the scored path weights
         q01 = _Clamp01(0.5 * (qOverall + qFit01));
         return true;
      }

     inline bool AutoC_KeyLevelsOK(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, double &q01)
     {
        q01 = 0.0;
        if(!cfg.auto_enable || !cfg.cf_autochartist_keylevels) return false;
   
        AutoSnapshot s;
        if(!AutoC::GetSnapshot(sym, tf, cfg, s)) return false;
   
        return AutoC_KeyLevelsOK_FromSnap(sym, tf, dir, cfg, s, q01);
     }
   
     inline bool AutoC_KeyLevelsOK_FromSnap(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                             const Settings &cfg, const AutoSnapshot &s, double &q01)
      {
         q01 = 0.0;

         if(!cfg.auto_enable || !cfg.cf_autochartist_keylevels)
            return false;

         const bool isBuy = (dir == DIR_BUY);

         double qA = 0.0;
         double qB = 0.0;
         
         if(isBuy)
         {
            const bool okApproach = s.key.approaching_support;
            const bool okBreakout = s.key.broke_resistance;
         
            if(!okApproach && !okBreakout)
               return false;
         
            if(okApproach) qA = _Clamp01(s.key.sig_s01);     // support significance
            if(okBreakout) qB = _Clamp01(s.key.sig_r01);     // resistance significance
         }
         else
         {
            const bool okApproach = s.key.approaching_resistance;
            const bool okBreakout = s.key.broke_support;
         
            if(!okApproach && !okBreakout)
               return false;
         
            if(okApproach) qA = _Clamp01(s.key.sig_r01);     // resistance significance
            if(okBreakout) qB = _Clamp01(s.key.sig_s01);     // support significance
         }
         
         q01 = MathMax(qA, qB);
         return (q01 >= cfg.auto_key_min_sig);
      }

     inline bool AutoC_VolOK(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, double &q01)
     {
        q01 = 0.0;
        if(!cfg.auto_enable || !cfg.cf_autochartist_volatility) return false;
   
        AutoSnapshot s;
        if(!AutoC::GetSnapshot(sym, tf, cfg, s)) return false;
   
        return AutoC_VolOK_FromSnap(sym, tf, dir, cfg, s, q01);
     }

     inline bool AutoC_VolOK_FromSnap(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                       const Settings &cfg, const AutoSnapshot &s, double &q01)
      {
         q01 = 0.0;

         if(!cfg.auto_enable || !cfg.cf_autochartist_volatility)
            return false;

         if(s.vol.mean_move_pts <= 0.0)
            return false;

         const int atrPeriod = (cfg.atr_period > 0 ? (int)cfg.atr_period : 14);
         const double atr_pts = Indi::ATRPoints(sym, tf, atrPeriod, 1);

         if(atr_pts <= 0.0)
            return false;

         const double need = cfg.auto_vol_min_range_atr * atr_pts;
         if(need <= 0.0)
            return false;

         double desired_tp_pts = need;

         // If we have a chart-pattern target, use it as a proxy for �intended TP distance�
         const double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
         const double px = iClose(sym, tf, 1);
         
         if(pt > 0.0 && px > 0.0 && s.chart.target_price > 0.0)
         {
            const double tgt = s.chart.target_price;
            if((dir == DIR_BUY  && tgt > px) ||
               (dir == DIR_SELL && tgt < px))
            {
               desired_tp_pts = MathAbs(tgt - px) / pt;
            }
         }
         
         desired_tp_pts = MathMax(desired_tp_pts, 1.0);
         
         const double q_need = (s.vol.range_1sd_pts / need);
         const double q_tp   = (s.vol.range_1sd_pts / MathMax(desired_tp_pts, 1e-6));
         
         q01 = MathMin(q_need, q_tp);
         return (q01 >= 1.0);
      }

     bool TrendFilterPasses(const string sym, const ENUM_TIMEFRAMES /*tf_entry*/, const Direction dir, const Settings &cfg)
     {
        const ENUM_TIMEFRAMES tfTrend = (ENUM_TIMEFRAMES)cfg.tf_trend_htf;

        // Prefer Scan snapshots (computed upstream) to avoid indicator recomputation here.
        Scan::IndiSnapshot sTrend, sEntry;
        const bool haveTrend = (StratScan::TryGetScanSnap(sym, tfTrend, sTrend) && StratScan::SnapReady(sTrend));
        const bool haveEntry = (StratScan::TryGetScanSnap(sym, (ENUM_TIMEFRAMES)cfg.tf_entry, sEntry) && StratScan::SnapReady(sEntry));
      
        const double pxClose = iClose(sym, (ENUM_TIMEFRAMES)cfg.tf_entry, 1);
      
        double ema21 = 0.0, ema50 = 0.0;
        if(haveTrend)
        {
          ema21 = sTrend.ema_fast;
          ema50 = sTrend.ema_slow;
        }
        else
        {
          // Fallback only if Scan isn't running / TF not covered
          ema21 = Indi::EMA(sym, tfTrend, 21, 1);
          ema50 = Indi::EMA(sym, tfTrend, 50, 1);
        }
      
        double vwap = 0.0;
        if(haveEntry)
        {
          vwap = sEntry.vwap;
        }
        else
        {
          double sw = 0.0;
          vwap = Indi::VWAP(sym, (ENUM_TIMEFRAMES)cfg.tf_entry, cfg.vwap_lookback, 1, sw);
        }
      
        // Existing logic: require VWAP agreement AND EMA trend agreement
        const bool pass_vwap = (dir==DIR_BUY ? (pxClose > vwap) : (pxClose < vwap));
        const bool pass_ema  = (dir==DIR_BUY ? (ema21 > ema50)  : (ema21 < ema50));
      
        bool pass_adx = true;
        if(cfg.extra_adx_regime)
        {
          if(haveTrend)
          {
            const double adx = sTrend.adx;
            const double dip = sTrend.di_plus;
            const double dim = sTrend.di_minus;
            const double adx_min = (cfg.adx_min_trend > 0.0 ? cfg.adx_min_trend : 25.0);
      
            if(!MathIsValidNumber(adx) || !MathIsValidNumber(dip) || !MathIsValidNumber(dim))
              pass_adx = false;
            else if(adx < adx_min)
              pass_adx = false;
            else
              pass_adx = (dir==DIR_BUY ? (dip > dim) : (dim > dip));
          }
          else
          {
            // Fallback
            pass_adx = ADP_ADX_StrongAligned(sym, tfTrend, cfg.adx_period, 1, cfg.adx_min_trend, (dir==DIR_BUY), true);
          }
        }
      
        return (pass_vwap && pass_ema && pass_adx);
     }

     // ---------------------------------------------------------------------
     // Fallback-only microstructure readers.
     // Canonical DOM / OBI / footprint transport should be authored upstream.
     // Main consumes them only through Main_ApplyMicrostructureExtras(...).
     // ---------------- Extras (used only AFTER confirmation) ----------------
     bool Extra_VolumeOrderFootprint(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
     {
        const double z = ADP_DeltaSlope(sym, tf, 25);
        const double th = ADP_OrderflowTh(cfg);
        if(dir==DIR_BUY)  return (z >= +th);
        else              return (z <= -th);
     }

     bool Extra_DOMImbalance(const string sym,
                             const bool isBuy,
                             const double zoneLow,
                             const double zoneHigh,
                             const double minAbsImb,
                             const Settings &cfg,
                             double &outComp,
                             int &outUsed,
                             bool &outUsable)
     {
        outComp = 0.0;
        outUsed = 0;
        outUsable = false;
   
        if(!cfg.extra_dom_imbalance)
           return false;
   
        OBI::Settings st;
        st.enabled = cfg.extra_dom_imbalance;
        st.debug_log = cfg.debug_dom;
        st.cache_ms = 250;
        st.zone_pad_points = cfg.dom_zone_pad_points;
   
        if(!OBI::EnsureSubscribed(sym, st))
           return false;
   
        OBI::Snapshot snap;
        if(!OBI::ComputeInRange(sym, zoneLow, zoneHigh, st, snap))
        {
           // If DOM isn't really usable on this broker/symbol, be neutral.
           outUsable = OBI::IsUsable(sym);
           return false;
        }
   
        outUsable = true;
        outUsed = snap.levelsUsed;
        outComp = snap.imbalance;
   
        return OBI::PassesDirectional(isBuy, snap.imbalance, minAbsImb);
     }

     bool Extra_DOMOrderBookImbalance(const string sym,
                                      const ENUM_TIMEFRAMES tf,
                                      const Direction dir,
                                      const Settings &cfg,
                                      const ICT_Context &ctx)
      {
          Scan::IndiSnapshot s;
          MainOFDS ofds;

          if(Main_TryLoadOFDS(sym, tf, s, ofds) && ofds.have_flow)
          {
             const double dirObi =
                (dir == DIR_BUY ? _MainClamp11(ofds.obi) : -_MainClamp11(ofds.obi));

             const double minImb =
                (cfg.dom_min_abs_imb > 0.0 ? cfg.dom_min_abs_imb : 0.10);

             return (dirObi >= minImb);
          }

         // Compile-safe: if cfg DOM fields are not available, always fall back.
         #ifdef CFG_HAS_FP_USE_DOM
            if(!cfg.fp_use_dom)
               return Extra_VolumeOrderFootprint(sym, tf, dir, cfg);

             OBI::Settings st;
             st.enabled = true;
             st.debug_log = cfg.debug_dom;
             st.cache_ms = 250;
             st.zone_pad_points = 0;
             st.max_levels = (int)cfg.dom_levels;

             if(!OBI::EnsureSubscribed(sym, st))
                return Extra_VolumeOrderFootprint(sym, tf, dir, cfg);

             // Anchor near the OB/FVG when available; else current close
             double anchor = iClose(sym, tf, 1);
             if(ctx.activeOrderBlock.high != 0.0 || ctx.activeOrderBlock.low != 0.0)
                anchor = 0.5 * (ctx.activeOrderBlock.high + ctx.activeOrderBlock.low);
             else if(ctx.activeFVG.high != 0.0 || ctx.activeFVG.low != 0.0)
                anchor = 0.5 * (ctx.activeFVG.high + ctx.activeFVG.low);

             const double point = SymbolInfoDouble(sym, SYMBOL_POINT);
             if(point <= 0.0)
                return Extra_VolumeOrderFootprint(sym, tf, dir, cfg);

             const double win = (double)cfg.dom_window_points * point;
             const double zLow  = anchor - win;
             const double zHigh = anchor + win;

             OBI::Snapshot snap;
             if(!OBI::ComputeInRange(sym, zLow, zHigh, st, snap))
                return Extra_VolumeOrderFootprint(sym, tf, dir, cfg);

             const double imb = snap.imbalance;
             const double minImb = (cfg.dom_min_abs_imb > 0.0 ? cfg.dom_min_abs_imb : 0.10);

             if(dir == DIR_BUY) return (imb >=  minImb);
             return (imb <= -minImb);

         #else
            return Extra_VolumeOrderFootprint(sym, tf, dir, cfg);
         #endif
      }

     inline void Main_ApplyMicrostructureExtras(ConfluenceResult   &R,
                                                const string        sym,
                                                const ENUM_TIMEFRAMES tf,
                                                const Direction     dir,
                                                const Settings     &cfg,
                                                const ICT_Context  &ctx,
                                                const bool          atPOI)
     {
        const bool useVol = (cfg.extra_volume_footprint && atPOI);
        const bool okVol  = (useVol ? Extra_DOMOrderBookImbalance(sym, tf, dir, cfg, ctx) : true);

        _ML::AddExtra(R, useVol, okVol, cfg.w_volume_footprint, "Vol/Footprint", C_VOLFOOT);

        bool   okDom     = false;
        int    domUsed   = 0;
        bool   domUsable = false;
        double domComp   = 0.0;
        bool   useDom    = false;

        if(cfg.extra_dom_imbalance)
        {
           double zoneLow  = 0.0;
           double zoneHigh = 0.0;

           if(ctx.activeOrderBlock.high != 0.0 || ctx.activeOrderBlock.low != 0.0)
           {
              zoneLow  = MathMin(ctx.activeOrderBlock.low,  ctx.activeOrderBlock.high);
              zoneHigh = MathMax(ctx.activeOrderBlock.low,  ctx.activeOrderBlock.high);
           }
           else if(ctx.activeFVG.high != 0.0 || ctx.activeFVG.low != 0.0)
           {
              zoneLow  = MathMin(ctx.activeFVG.low,  ctx.activeFVG.high);
              zoneHigh = MathMax(ctx.activeFVG.low,  ctx.activeFVG.high);
           }

           if(zoneLow != 0.0 || zoneHigh != 0.0)
           {
              const double point = SymbolInfoDouble(sym, SYMBOL_POINT);
              const double pad   = (point > 0.0 ? (double)cfg.dom_zone_pad_points * point : 0.0);

              zoneLow  -= pad;
              zoneHigh += pad;

              const double minAbsImb =
                 (cfg.dom_min_abs_imb > 0.0 ? cfg.dom_min_abs_imb : 0.15);

              okDom = Extra_DOMImbalance(sym,
                                         (dir == DIR_BUY),
                                         zoneLow,
                                         zoneHigh,
                                         minAbsImb,
                                         cfg,
                                         domComp,
                                         domUsed,
                                         domUsable);

              useDom = (domUsable && domUsed > 0);
           }
        }

        _ML::AddExtra(R, useDom, okDom, cfg.w_dom_imbalance, "DOMImbalance", C_DOM);
     }

     bool Extra_StochRSI(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
     {
        // Prefer Scan snapshot (downstream consumption)
        Scan::IndiSnapshot ss;
        if(StratScan::TryGetScanSnap(sym, tf, ss) && StratScan::SnapReady(ss))
        {
          const double k = ss.stoch_k;
          if(!MathIsValidNumber(k)) return false;
      
          const double os = (double)cfg.stoch_os;
          const double ob = (double)cfg.stoch_ob;
          return (dir==DIR_BUY ? (k <= os) : (k >= ob));
        }
      
        // Fallback only if Scan isn't running / TF not scanned
        double k = 0.0;
        if(!ADP_StochRSI_K(sym, tf, cfg.rsi_period, 14, 3, 1, k))
          return false;
        return (dir==DIR_BUY ? (k <= cfg.stoch_os) : (k >= cfg.stoch_ob));
     }
   
     bool Extra_MACDCross(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
     {
        // Prefer Scan snapshot + local MACD cross cache (no recompute here)
        Scan::IndiSnapshot ss;
        if(StratScan::TryGetScanSnap(sym, tf, ss) && StratScan::SnapReady(ss))
        {
          return StratScan::MACD_CrossUsingScan(sym, tf, dir, ss);
        }
      
        // Fallback only if Scan isn't running / TF not scanned
        double m1=0.0, s1=0.0, h1=0.0;
        double m2=0.0, s2=0.0, h2=0.0;
         
        if(!ADP_MACD(sym, tf, cfg.macd_fast, cfg.macd_slow, cfg.macd_signal, 1, m1, s1, h1)) return false;
        if(!ADP_MACD(sym, tf, cfg.macd_fast, cfg.macd_slow, cfg.macd_signal, 2, m2, s2, h2)) return false;
         
        if(dir == DIR_BUY)  return (m1 > s1 && m2 <= s2);
        if(dir == DIR_SELL) return (m1 < s1 && m2 >= s2);
         
        return false;
     }
   
     bool Extra_ADXRegime(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
     {
        // Prefer Scan snapshot (downstream consumption)
        Scan::IndiSnapshot ss;
        if(StratScan::TryGetScanSnap(sym, tf, ss) && StratScan::SnapReady(ss))
        {
          const double adx = ss.adx;
          const double dip = ss.di_plus;
          const double dim = ss.di_minus;
          const double adx_min = (cfg.adx_min_trend > 0.0 ? cfg.adx_min_trend : 25.0);
      
          if(!MathIsValidNumber(adx) || !MathIsValidNumber(dip) || !MathIsValidNumber(dim))
            return false;
          if(adx < adx_min)
            return false;
      
          return (dir==DIR_BUY ? (dip > dim) : (dim > dip));
        }
      
        // Fallback only if Scan isn't running / TF not scanned
        return ADP_ADX_StrongAligned(sym, tf, cfg.adx_period, 1, cfg.adx_min_trend, (dir==DIR_BUY), true);
     }
   
     // ---- Correlation: build a sane default ref basket when cfg.corr_ref_symbol is empty ----
      bool Corr_TryAddSymbol(const string sym, string &csv)
      {
         if(StringLen(sym) == 0) return false;
         if(!SymbolSelect(sym, true)) return false;
      
         // Avoid duplicates
         if(StringLen(csv) > 0)
         {
            const string hay = "," + csv + ",";
            const string needle = "," + sym + ",";
            if(StringFind(hay, needle) >= 0) return false;
            csv += ",";
         }
         csv += sym;
         return true;
      }
      
      string Corr_SuffixFromSymbol(const string sym, const string base, const string quote)
      {
         const string core = base + quote;
         const int pos = StringFind(sym, core);
         if(pos < 0) return "";
         return StringSubstr(sym, pos + StringLen(core));
      }
      
      bool Corr_BuildAutoRefList(const string tradedSym, string &outCsv)
      {
         outCsv = "";
      
         string base  = SymbolInfoString(tradedSym, SYMBOL_CURRENCY_BASE);
         string quote = SymbolInfoString(tradedSym, SYMBOL_CURRENCY_PROFIT);
      
         const bool isFX = (StringLen(base) == 3 && StringLen(quote) == 3);
         const bool isGoldish = (StringFind(tradedSym, "XAU") >= 0 || base == "XAU");
      
         string suffix = "";
         if(isFX || isGoldish)
            suffix = Corr_SuffixFromSymbol(tradedSym, base, quote);
      
         // MT5-safe OTC proxy candidates (use the first available on the broker)
         //const string dxyCands[] = {"DXY","USDX","USDIDX","#USDX","DX"};
         const string dxyCands[] = {"EURUSD","USDJPY","USDCHF","GBPUSD","AUDUSD"};
         for(int i=0; i<ArraySize(dxyCands); i++)
         {
            if(SymbolSelect(dxyCands[i], true))
            {
               Corr_TryAddSymbol(dxyCands[i], outCsv);
               break;
            }
         }
      
         if(isFX)
         {
            // Risk-off / USD drivers
            Corr_TryAddSymbol("USDJPY" + suffix, outCsv);
            Corr_TryAddSymbol("USDCHF" + suffix, outCsv);
      
            // Risk-on proxy
            if(!Corr_TryAddSymbol("AUDJPY" + suffix, outCsv))
               Corr_TryAddSymbol("NZDJPY" + suffix, outCsv);
      
            // Sibling majors (best-effort)
            if(base != "USD")  Corr_TryAddSymbol(base  + "USD" + suffix, outCsv);
            if(quote != "USD") Corr_TryAddSymbol(quote + "USD" + suffix, outCsv);
      
            // If EURUSD specifically, add common siblings (best coverage)
            if(base == "EUR" && quote == "USD")
            {
               Corr_TryAddSymbol("GBPUSD" + suffix, outCsv);
               Corr_TryAddSymbol("AUDUSD" + suffix, outCsv);
            }
         }
         else if(isGoldish)
         {
            // Real yields proxy candidates (best-effort; only use if broker has it)
            const string yCands[] = {"US10Y","UST10Y","10Y","#US10Y"};
            for(int j=0; j<ArraySize(yCands); j++)
            {
               if(SymbolSelect(yCands[j], true))
               {
                  Corr_TryAddSymbol(yCands[j], outCsv);
                  break;
               }
            }
      
            // Silver sibling (best-effort)
            Corr_TryAddSymbol("XAGUSD" + suffix, outCsv);
         }
      
         return (StringLen(outCsv) > 0);
      }

     bool Extra_Correlation(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg, double &composite, int &used_out)
      {
        composite = 0.0;
        used_out  = 0;
        if(!cfg.extra_correlation) return false;
   
        // Basic hygiene
        // Use configured list if provided; otherwise auto-build a sane basket (cached per symbol)
        static string s_autoSym  = "";
        static string s_autoList = "";

        string refList = cfg.corr_ref_symbol;

        if(StringLen(refList) == 0)
        {
           if(s_autoSym != sym)
           {
              s_autoSym  = sym;
              s_autoList = "";
              Corr_BuildAutoRefList(sym, s_autoList);
           }
           refList = s_autoList;
        }

         if(StringLen(refList) == 0) return false;
         
        // Allow comma-separated list: "EURUSD,GBPUSD,USDCHF"
        string refs[];
        const int nRefs = StringSplit(refList, ',', refs);
        if(nRefs <= 0) return false;
   
        // Ensure lookback sane
        const int lb = (cfg.corr_lookback > 0 ? cfg.corr_lookback : 200);
   
        int used = 0;
        int agree = 0;
        const double minAbs = (cfg.corr_min_abs > 0.0 ? cfg.corr_min_abs : 0.30); // or 0.35, sensible default for �meaningful correlation�
         
        for(int i=0; i<nRefs; i++)
        {
            string ref = refs[i];
            StringTrimLeft(ref);
            StringTrimRight(ref);
         
            if(StringLen(ref) == 0) continue;
            if(ref == sym)          continue;
         
            double beta=0.0, r=0.0;
            if(!ADP_BetaCorr(sym, ref, tf, lb, /*shift*/1, beta, r))
               continue;
         
            if(MathAbs(r) < minAbs)
               continue;
         
            const ENUM_TIMEFRAMES ema_tf = (ENUM_TIMEFRAMES)(cfg.corr_ema_tf > 0 ? cfg.corr_ema_tf : PERIOD_H1);
            const int fast = (cfg.corr_ema_fast>0 ? cfg.corr_ema_fast : 21);
            const int slow = (cfg.corr_ema_slow>0 ? cfg.corr_ema_slow : 50);
         
            double eF = 0.0, eS = 0.0;
            if(!GetEMA(ref, ema_tf, fast, /*shift*/1, eF)) continue;
            if(!GetEMA(ref, ema_tf, slow, /*shift*/1, eS)) continue;
            if(eF <= 0.0 || eS <= 0.0) continue;
         
            const bool refUp = (eF > eS);
         
            // If r > 0: aligned markets should trend same way
            // If r < 0: inverse markets should trend opposite way
            bool confirms = false;
            if(dir == DIR_BUY)
               confirms = ( (r > 0.0 && refUp) || (r < 0.0 && !refUp) );
            else
               confirms = ( (r > 0.0 && !refUp) || (r < 0.0 && refUp) );
         
            used++;
            if(confirms) agree++;
        }
         
        if(used == 0) return false;
        used_out = used;
        composite = (double)(2*agree - used) / (double)used; // [-1..+1]
         
        // Majority vote (ties fail safe)
        return (agree > used/2);
     }
   
     bool Extra_NewsOK(const string sym, const Settings &cfg, double &risk_mult, int &mins_left)
     {
        risk_mult = 1.0;
        mins_left = 0;
        
       #ifdef NEWSFILTER_AVAILABLE
         // Cache key = (symbol, time_window, now_bar_time)
         static string   c_sym  = "";
         static datetime c_bar  = 0;
         static int      c_mask = 0;
         static int      c_pre  = 0;
         static int      c_post = 0;
         static int      c_lb   = 0;
      
         static bool     c_ok   = true;
         static double   c_mult = 1.0;
         static int      c_mins = 0;
      
         const datetime now_bar_time = iTime(sym, (ENUM_TIMEFRAMES)cfg.tf_entry, 0);
         const datetime barKey = (now_bar_time > 0 ? now_bar_time : iTime(sym, PERIOD_M1, 0));
      
         if(c_sym == sym && c_bar == barKey &&
            c_mask == cfg.news_impact_mask &&
            c_pre  == cfg.block_pre_m &&
            c_post == cfg.block_post_m &&
            c_lb   == cfg.cal_lookback_mins)
         {
            risk_mult = c_mult;
            mins_left = c_mins;
            return c_ok;
         }
      
         // Calendar/backend availability posture: FAIL-OPEN (neutral)
         News::Health h;
         News::GetHealth(h);
      
         if(h.backend_effective == News::BACKEND_DISABLED ||
            h.data_health == News::DATA_NO_BACKEND ||
            h.data_health == News::DATA_BACKEND_DOWN ||
            h.data_health == News::DATA_EMPTY)
         {
            // Neutral allow
            risk_mult = 1.0;
            mins_left = 0;
      
            c_sym  = sym;   c_bar  = barKey;
            c_mask = cfg.news_impact_mask;
            c_pre  = cfg.block_pre_m;
            c_post = cfg.block_post_m;
            c_lb   = cfg.cal_lookback_mins;
      
            c_ok   = true;
            c_mult = 1.0;
            c_mins = 0;
      
            return true;
         }
      
         bool skip = false;
         News::CompositeRiskAtBarClose(cfg, sym, /*shift*/1, risk_mult, skip, mins_left);
      
         // Save cache
         c_sym  = sym;   c_bar  = barKey;
         c_mask = cfg.news_impact_mask;
         c_pre  = cfg.block_pre_m;
         c_post = cfg.block_post_m;
         c_lb   = cfg.cal_lookback_mins;
      
         c_ok   = (!skip);
         c_mult = risk_mult;
         c_mins = mins_left;
      
         return c_ok;
      #else
         return true;
      #endif
     }
   
     inline void AugmentWithExtras_ifConfirmed(ConfluenceResult &R, const string sym, const ENUM_TIMEFRAMES tf,
                                         const Direction dir, const Settings &cfg, const ICT_Context &ctx,
                                         const bool newsComputed, const bool newsOK_core,
                                         const double newsRiskMult_core, const int newsMinsLeft_core)
     {
       // Do not gate extras on R.eligible. This is called only after corePass upstream.
       const bool atPOI = (((R.mask & ((ulong)1 << C_ZONE)) != 0) ||
                           ((R.mask & ((ulong)1 << C_OB  )) != 0));

       Main_ApplyMicrostructureExtras(R, sym, tf, dir, cfg, ctx, atPOI);

       int    corrUsed = 0;
       double corrComp = 0.0;

       if(cfg.extra_correlation)
          Extra_Correlation(sym, tf, dir, cfg, corrComp, corrUsed);

         // Penalize strong disagreement (majority against your direction)
         if(cfg.extra_correlation && corrUsed > 0 && corrComp <= -0.34)
         {
            const double maxPen = 0.10; // cap at 10% score reduction
            const double pen = MathMin(maxPen, MathMax(0.0, (-corrComp) * maxPen)); // scale by severity

            R.score *= (1.0 - pen);

            if(R.summary != "") R.summary += ", ";
            R.summary += StringFormat("CorrPenalty(-%.2f)", pen);
         }
          
         const bool useNews = cfg.extra_news;
         bool okNews = true;
         
         if(useNews)
         {
            if(newsComputed)
               okNews = newsOK_core;
            else
            {
               // Fallback for any caller that did not precompute news
               double nm = 1.0;
               int    nmins = 0;
               okNews = Extra_NewsOK(sym, cfg, nm, nmins);
            }
         }
         
         _ML::AddExtra(R, useNews, okNews, cfg.w_news, "NewsOK", C_NEWS);

         // Silver Bullet timezone/window as extra confluence
         #ifdef CFG_HAS_EXTRA_SILVERBULLET_TZ
         {
            const bool okSB = Ctx_SilverBulletWindowNow(ctx);
            _ML::AddExtra(R, cfg.extra_silverbullet_tz, okSB, cfg.w_silverbullet_tz, "SB_TZ", C_SB_TZ);
         }
         #endif
         
         // Intraday AMD phases (H1/H4) as extra confluence
         #ifdef CFG_HAS_EXTRA_AMD_HTF
         {
            const bool isBuy = (dir == DIR_BUY);
            const int ph1 = Ctx_AMDPhase_H1(ctx);
            const int ph4 = Ctx_AMDPhase_H4(ctx);
            
            const bool okH1 = isBuy ? (ph1 == AMD_PHASE_ACCUM) : (ph1 == AMD_PHASE_DIST);
            const bool okH4 = isBuy ? (ph4 == AMD_PHASE_ACCUM) : (ph4 == AMD_PHASE_DIST);
            
            const string tagH1 = isBuy ? "AMD_H1_ACCUM" : "AMD_H1_DIST";
            const string tagH4 = isBuy ? "AMD_H4_ACCUM" : "AMD_H4_DIST";
            
            _ML::AddExtra(R, cfg.extra_amd_htf, okH1, cfg.w_amd_h1, tagH1, C_AMD_H1);
            _ML::AddExtra(R, cfg.extra_amd_htf, okH4, cfg.w_amd_h4, tagH4, C_AMD_H4);
            
            const bool h1_manip = (ph1 == AMD_PHASE_MANIP);
            const bool h1_accum = (ph1 == AMD_PHASE_ACCUM);
            const bool h4_manip = (ph4 == AMD_PHASE_MANIP);
            const bool h4_accum = (ph4 == AMD_PHASE_ACCUM);
            
            // Mild weights: visible in summary without overpowering core scoring
            _ML::AddExtra(R, cfg.extra_amd_htf, h1_manip, 0.10, "PO3_H1_MANIP", C_PO3_H1_MANIP);
            _ML::AddExtra(R, cfg.extra_amd_htf, h1_accum, 0.08, "PO3_H1_ACCUM", C_PO3_H1_ACCUM);
            _ML::AddExtra(R, cfg.extra_amd_htf, h4_manip, 0.12, "PO3_H4_MANIP", C_PO3_H4_MANIP);
            _ML::AddExtra(R, cfg.extra_amd_htf, h4_accum, 0.10, "PO3_H4_ACCUM", C_PO3_H4_ACCUM);
         }
         #endif
         // Wyckoff Spring / UTAD as extra confluence (direction-aware)
         {
            const bool isBuy = (dir == DIR_BUY);
            const bool okSpring = (isBuy && ctx.wySpringCandidate);
            const bool okUTAD   = (!isBuy && ctx.wyUTADCandidate);
         
            _ML::AddExtra(R, cfg.extra_amd_htf, okSpring, 0.12, "WY_SPRING", C_WY_SPRING);
            _ML::AddExtra(R, cfg.extra_amd_htf, okUTAD,   0.12, "WY_UTAD",   C_WY_UTAD);
         }
         
          // Scanner Wyckoff manipulation hint (Spring/UTAD recently detected by Scan)
          if(cfg.extra_amd_htf && cfg.scan_wyck_enable)
          {
             Scan::IndiSnapshot ss;
             if(StratScan::TryGetScanSnap(sym, tf, ss) && StratScan::SnapReady(ss))
             {
                const bool okWyScanManip = StratScan::WyckManipRecentForDir(ss, tf, dir);
                _ML::AddExtra(R, true, okWyScanManip, 0.08, "WY_SCAN_MANIP", C_WY_SCAN_MANIP);
             }
          }
          
         // Intraday Wyckoff phase flags (H1/H4) as extra confluence
         #ifdef ICTCTX_HAS_WYCKOFF_INTRADAY
         {
            const bool isBuy = (dir == DIR_BUY);
            string wyTag = (isBuy ? "WY_INTRA_ACCUM" : "WY_INTRA_DIST");
            const bool okWyIntra = isBuy ? Ctx_Wy_InAccum_Intra(ctx)
                             : Ctx_Wy_InDist_Intra(ctx);
         
            _ML::AddExtra(R, cfg.extra_amd_htf, okWyIntra, 0.10, wyTag, C_WY_INTRA);
         }
         #endif
         
         // HTF zones + HTF liquidity as extra confluence
         {
            const bool isBuy = (dir == DIR_BUY);
            const double px  = iClose(sym, tf, 1);
         
            const Zone zH1 = (isBuy ? ctx.bestDemandZoneH1 : ctx.bestSupplyZoneH1);
            const Zone zH4 = (isBuy ? ctx.bestDemandZoneH4 : ctx.bestSupplyZoneH4);
         
            const bool inH1 = (_ZoneHas(zH1) && _ZoneInside(zH1, px));
            const bool inH4 = (_ZoneHas(zH4) && _ZoneInside(zH4, px));
         
            const bool stacked = (ctx.zoneStackDepth >= 2) && (inH1 || inH4);
         
            _ML::AddExtra(R, cfg.extra_amd_htf, inH1,     0.10, "ZONE_H1",    C_ZONE_H1);
            _ML::AddExtra(R, cfg.extra_amd_htf, inH4,     0.12, "ZONE_H4",    C_ZONE_H4);
            _ML::AddExtra(R, cfg.extra_amd_htf, stacked,  0.08, "ZONE_STACK", C_ZONE_STACK);
         
            bool liqOk = false;
            if(ctx.liqSentHTF.valid)
            {
               const double s = ctx.liqSentHTF.skew;
               liqOk = (isBuy ? (s > 0.10) : (s < -0.10));
            }
            _ML::AddExtra(R, cfg.extra_amd_htf, liqOk, 0.08, "LIQ_HTF", C_LIQ_HTF);
            #ifdef SCAN_SNAP_HAS_LIQ_POOLS
            // Scanner liquidity pool states (approach / touch) as extra tags (do NOT change core okLiq gating)
            if(cfg.extra_amd_htf && cfg.scan_liq_enable)
            {
               Scan::IndiSnapshot ss;
               if(StratScan::TryGetScanSnap(sym, tf, ss) && StratScan::SnapReady(ss))
               {
                  const uchar st = (isBuy ? ss.liq_ssl_state : ss.liq_bsl_state);
                  const bool inA = (isBuy ? ss.liq_ssl_in_approach : ss.liq_bsl_in_approach);

                  const bool okApp = (st == 1) || inA;  // approach
                  const bool okTch = (st == 2);         // touched/swept

                  const string tagA = (isBuy ? "SSL_APPROACH" : "BSL_APPROACH");
                  const string tagT = (isBuy ? "SSL_TOUCH"    : "BSL_TOUCH");

                  _ML::AddExtra(R, true, okApp, 0.05, tagA, C_LIQ_POOL_APPROACH);
                  _ML::AddExtra(R, true, okTch, 0.07, tagT, C_LIQ_POOL_TOUCHED);
               }
            }
            #endif
         }
       //_ML::RecomputeEligibility(R, cfg);
     }

     // NOTE:
     // EvalScoredEx(...) and EvalSequentialEx(...) remain internal checklist builders only.
     // EvaluateEx(...) is the only canonical Main decision owner for routing / candidates / tester execution.
     // ---------------- Scored vs Sequential evaluators ----------------
     ConfluenceResult EvalScoredEx(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                              const Settings &cfg, const bool haveAuto, const AutoSnapshot &autoS)
     {
         ConfluenceResult R; R.metCount=0; R.score=0; R.mask=0; R.summary="";
   
         const bool okMS   = HasMarketStructure(sym, tf, dir, cfg);
         const bool okZone = HasInstitutionalZoneNearET(sym, tf, dir, cfg);
         const bool okOB   = HasOrderBlockProximity(sym, tf, dir, cfg);
         const bool okPOI  = (okZone || okOB);
         const bool okLiq  = (okPOI ? HasLiquidityPoolContext(sym, tf, dir, cfg) : false);

         _ML::Add(R, cfg.cf_market_structure, okMS,   cfg.w_market_structure, "MarketStruct", C_MKSTR);
         _ML::Add(R, cfg.cf_inst_zones,       okZone, cfg.w_inst_zones,       "InstitZone",   C_ZONE);
         _ML::Add(R, cfg.cf_orderblock_near,  okOB,   cfg.w_orderblock_near,  "OB_Prox",      C_OB);
         _ML::Add(R, cfg.cf_liquidity,        okLiq,  cfg.w_liquidity,        "Liquidity",    C_LIQ);

         const bool atPOI_forDelta = (okPOI && okLiq);
         const bool atPOI_forVSA   = (okPOI && okLiq);

         if(cfg.cf_orderflow_delta && atPOI_forDelta)
         {
            bool ofDataOk = true;
            const bool okOF = HasOrderFlowDeltaIncreaseEx(sym, tf, dir, cfg, ofDataOk);
            _ML::Add(R, (cfg.cf_orderflow_delta && ofDataOk), okOF, cfg.w_orderflow_delta, "OrderFlow?", C_OFLOW);
         }

         if(cfg.cf_vsa_increase && atPOI_forVSA)
         {
            bool vsaDataOk = true;
            const bool okVSA = HasVSAIncreaseAtLocationEx(sym, tf, dir, cfg, vsaDataOk);
            _ML::Add(R, (cfg.cf_vsa_increase && vsaDataOk), okVSA, cfg.w_vsa_increase, "VSA+", C_VSA);
         }
         
         _ML::Add(R, cfg.cf_candle_pattern,   HasBullBearCandlePattern(sym,tf,dir,cfg),   cfg.w_candle_pattern,  "CndlPattern",C_CANDLE);
         if(cfg.cf_chart_pattern && !cfg.cf_autochartist_chart)
            _ML::Add(R, true, HasBullBearChartPattern(sym,tf,dir,cfg), cfg.w_chart_pattern, "ChartPattern", C_CHART);

         _ML::Add(R, cfg.cf_trend_regime,     TrendFilterPasses(sym,tf,dir,cfg),          cfg.w_trend_regime,    "TrendFilter", C_TREND);
         
                  // Autochartist (single snapshot; scored path)
         double qChart = 0.0;
         bool chartDataOk = haveAuto;

         const bool okAutoChart =
            (cfg.cf_autochartist_chart && haveAuto
             ? AutoC_ChartOK_FromSnap(sym, tf, dir, cfg, autoS, qChart, chartDataOk)
             : false);

         const double qChartFinal =
            (okAutoChart && chartDataOk
             ? AutoC_ChartScore01_FromSnap(sym, tf, dir, cfg, autoS, qChart)
             : 0.0);

         _ML::Add(R,
                  (cfg.cf_autochartist_chart && haveAuto && chartDataOk),
                  okAutoChart,
                  cfg.w_autochartist_chart * MathMax(0.25, qChartFinal),
                  "AutoChart",
                  C_AUTO_CHART);

         double qTmp = 0.0;

         const bool okAutoFib =
            (cfg.cf_autochartist_fib && haveAuto
             ? AutoC_FibOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp)
             : false);

         _ML::Add(R,
                  (cfg.cf_autochartist_fib && haveAuto),
                  okAutoFib,
                  cfg.w_autochartist_fib * MathMax(0.25, _Clamp01(qTmp)),
                  "AutoFib",
                  C_AUTO_FIB);

         qTmp = 0.0;

         const bool okAutoKey =
            (cfg.cf_autochartist_keylevels && haveAuto
             ? AutoC_KeyLevelsOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp)
             : false);

         _ML::Add(R,
                  (cfg.cf_autochartist_keylevels && haveAuto),
                  okAutoKey,
                  cfg.w_autochartist_keylevels * MathMax(0.25, _Clamp01(qTmp)),
                  "AutoKeyLvls",
                  C_AUTO_KEYLEVELS);

         qTmp = 0.0;

         const bool okAutoVol =
            (cfg.cf_autochartist_volatility && haveAuto
             ? AutoC_VolOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp)
             : false);

         _ML::Add(R,
                  (cfg.cf_autochartist_volatility && haveAuto),
                  okAutoVol,
                  cfg.w_autochartist_volatility * MathMax(0.25, _Clamp01(qTmp)),
                  "AutoVol",
                  C_AUTO_VOL);
   
       return _ML::Finalize(R, cfg, "Scored");
     }
   
     ConfluenceResult EvalScored(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
      {
         AutoSnapshot autoS;
         bool haveAuto = false;
      
         const bool wantAuto =
            (cfg.auto_enable &&
             (cfg.cf_autochartist_chart ||
              cfg.cf_autochartist_fib ||
              cfg.cf_autochartist_keylevels ||
              cfg.cf_autochartist_volatility));
      
         if(wantAuto)
            haveAuto = AutoC::GetSnapshot(sym, tf, cfg, autoS);
      
         return EvalScoredEx(sym, tf, dir, cfg, haveAuto, autoS);
      }

     ConfluenceResult EvalSequential(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir, const Settings &cfg)
      {
         ICT_Context ctx;
         Main_LoadCanonicalICTContext(sym, cfg, ctx);
         return EvalSequential(sym, tf, dir, cfg, ctx);
      }

     ConfluenceResult EvalSequentialEx(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                     const Settings &cfg, const ICT_Context &ctx,
                                     const bool haveAuto, const AutoSnapshot &autoS)
      {
         ConfluenceResult R;
         R.metCount = 0;
         R.score    = 0.0;
         R.mask     = 0;
         R.summary  = "";
      
         bool requireChecklist = false;
         #ifdef CFG_HAS_MAIN_REQUIRE_CHECKLIST
           requireChecklist = (Config::Cfg_EnableHardGate(cfg) && cfg.main_require_checklist);
         #endif

         const bool testerLooseGate = Main_CfgTesterLooseGate(cfg);
         bool okZone = false;
         bool okLiq  = false;
         bool okOB   = false;

         // 0) Context preference (soft bonus, not a veto)
         // Prefer BUY/SELL using Wyckoff intraday range-transition flags (primary), with PO3 AMD fallback when Wyckoff is neutral.
         {
            const bool prefer = Ctx_PrefersDir_Soft(ctx, dir);
         
            double wCtx = 0.10;
            #ifdef CFG_HAS_W_CTXPREF
               wCtx = cfg.w_ctx_pref;
            #endif
         
            _ML::Append(R, prefer, wCtx, "CtxPrefer", C_CTXPREF);
         }

         // 1) Market structure
         if(cfg.cf_market_structure)
         {
            const bool okMS = HasMarketStructure(sym, tf, dir, cfg);
            _ML::Append(R, okMS, cfg.w_market_structure, "MarketStruct", C_MKSTR);
            if(requireChecklist && !okMS) return _ML::Finalize(R, cfg, "Seq@MkStr");
         }
      
         // 2) Composite POI stage: zone OR order-block qualifies location
         if(cfg.cf_inst_zones)
         {
            okZone = HasInstitutionalZoneNearET(sym, tf, dir, cfg);
            _ML::Append(R, okZone, cfg.w_inst_zones, "InstitZone", C_ZONE);
         }

         if(cfg.cf_orderblock_near)
         {
            okOB = HasOrderBlockProximity(sym, tf, dir, cfg);
            _ML::Append(R, okOB, cfg.w_orderblock_near, "OB_Prox", C_OB);
         }

         const bool usePOI = (cfg.cf_inst_zones || cfg.cf_orderblock_near);
         const bool okPOI  = (okZone || okOB);

         if(requireChecklist && usePOI && !okPOI)
            return _ML::Finalize(R, cfg, "Seq@POI");

         // 3) Liquidity stage - cannot rescue a missing POI
         if(cfg.cf_liquidity)
         {
            okLiq = (okPOI ? HasLiquidityPoolContext(sym, tf, dir, cfg) : false);
            _ML::Append(R, okLiq, cfg.w_liquidity, "Liquidity", C_LIQ);
            if(requireChecklist && !okLiq)
               return _ML::Finalize(R, cfg, "Seq@Liq");
         }

         // 4) POI order-flow confirmation
         if(cfg.cf_orderflow_delta)
         {
            const bool atPOI_forDelta = (okPOI && okLiq);

            if(atPOI_forDelta)
            {
               bool ofDataOk = true;
               const bool okDelta = HasOrderFlowDeltaIncreaseEx(sym, tf, dir, cfg, ofDataOk);

               if(ofDataOk)
               {
                  _ML::Append(R, okDelta, cfg.w_orderflow_delta, "OrderFlow?", C_OFLOW);
                  if(requireChecklist && !okDelta)
                     return _ML::Finalize(R, cfg, "Seq@Delta");
               }
            }
         }

         // 5) VSA at POI after liquidity context
         if(cfg.cf_vsa_increase)
         {
            const bool atPOI_forVSA = (okPOI && okLiq);

            if(atPOI_forVSA)
            {
               bool vsaDataOk = true;
               int poiKind = 0;
               double poiPrice = 0.0;

               Main_ResolveVSAPOIContext(sym, tf, dir, ctx, poiKind, poiPrice);

               const bool okVsa = HasVSAIncreaseAtLocationEx(sym, tf, dir, cfg, poiKind, poiPrice, vsaDataOk);

               if(vsaDataOk)
               {
                  _ML::Append(R, okVsa, cfg.w_vsa_increase, "VSA+", C_VSA);
                  if(requireChecklist && !okVsa)
                     return _ML::Finalize(R, cfg, "Seq@VSA");
               }
            }
         }
         
         // -----------------------------------------------------------------------
         // C.A.N.D.L.E. A — Axis Time-Memory Gate
         // Scores how "remembered" the current POI is based on how many bars
         // in the lookback window touched the zone.  This is the "time is memory"
         // concept — well-tested levels are more reliable.
         // -----------------------------------------------------------------------
         #ifdef AXIS_TIME_MEMORY_AVAILABLE
         if(cfg.cf_axis_time_memory)
         {
            double zoneLo = 0.0, zoneHi = 0.0;

            ICTOrderBlock obPick_tm;
            ICTFVG        fvgPick_tm;
            string        srcTm = "";

            if(StratMainLogic::PickBestOBForDir(ctx, (dir == DIR_BUY), obPick_tm, srcTm))
            {
               zoneLo = MathMin(obPick_tm.low, obPick_tm.high);
               zoneHi = MathMax(obPick_tm.low, obPick_tm.high);
            }
            else if(StratMainLogic::PickBestFVGForDir(ctx, (dir == DIR_BUY), fvgPick_tm, srcTm))
            {
               zoneLo = MathMin(fvgPick_tm.low, fvgPick_tm.high);
               zoneHi = MathMax(fvgPick_tm.low, fvgPick_tm.high);
            }
            else if(poiPrice > 0.0)
            {
               const double halfSpread = poiPrice * 0.0010;
               zoneLo = poiPrice - halfSpread;
               zoneHi = poiPrice + halfSpread;
            }

            if(zoneLo > 0.0 && zoneHi > zoneLo)
            {
               LevelTimeMemoryResult tmResult;
               ZeroMemory(tmResult);

               const int tmLookback = (cfg.axis_time_memory_lookback >= 10)
                                       ? cfg.axis_time_memory_lookback : 100;

               // Build LevelTimeMemoryCtx and call the enhanced scorer when enabled.
               bool tmDataOk = false;
               #ifdef AXIS_TIME_MEMORY_ENHANCED
               if(cfg.axis_time_memory_htf_lookback > 0 ||
                  cfg.axis_time_memory_use_pivots        ||
                  cfg.axis_time_memory_use_trendlines    ||
                  cfg.axis_time_memory_use_ob_quality)
               {
                  LevelTimeMemoryCtx tmCtx;
                  tmCtx.Reset();

                  // Multi-TF configuration
                  tmCtx.tf_htf       = (ENUM_TIMEFRAMES)cfg.tf_trend_htf;
                  tmCtx.tf_mid       = (ENUM_TIMEFRAMES)cfg.tf_entry;
                  tmCtx.htf_lookback = (cfg.axis_time_memory_htf_lookback >= 10)
                                        ? cfg.axis_time_memory_htf_lookback : 80;
                  tmCtx.mid_lookback = (cfg.axis_time_memory_mid_lookback >= 10)
                                        ? cfg.axis_time_memory_mid_lookback : 120;

                  // HTF S&R bounds: use ICT_Context HTF zone if available.
                  // bestDemandZoneH4 / bestSupplyZoneH4 hold H4-detected zones.
                  #ifdef CA_HAS_MULTITF_ZONES
                  if(dir == DIR_BUY && ctx.bestDemandZoneH4.hi > 0.0)
                  {
                     tmCtx.htf_lo = ctx.bestDemandZoneH4.lo;
                     tmCtx.htf_hi = ctx.bestDemandZoneH4.hi;
                  }
                  else if(dir == DIR_SELL && ctx.bestSupplyZoneH4.hi > 0.0)
                  {
                     tmCtx.htf_lo = ctx.bestSupplyZoneH4.lo;
                     tmCtx.htf_hi = ctx.bestSupplyZoneH4.hi;
                  }
                  #endif

                  // Mid TF bounds come from the already-resolved zone (zoneLo / zoneHi)
                  tmCtx.mid_lo = zoneLo;
                  tmCtx.mid_hi = zoneHi;

                  // Pivot proximity from ICT_Context poolDistanceATR
                  // (pivot proximity is already expressed as ATR distance in context)
                  if(cfg.axis_time_memory_use_pivots)
                  {
                     const double pivDistATR = ctx.poolDistanceATR;
                     tmCtx.near_pivot     = (pivDistATR >= 0.0 && pivDistATR < 1.5);
                     tmCtx.pivot_dist_atr = (pivDistATR >= 0.0) ? pivDistATR : 99.0;
                  }

                  // OBZone quality from already-resolved obPick_tm
                  if(cfg.axis_time_memory_use_ob_quality)
                  {
                     // obPick_tm is a StratMainLogic::ICTOrderBlock; cast to StructOB::OBZone
                     // The ICTOrderBlock type carries the full OBZone payload in this codebase.
                     #ifdef STRUCTOB_QUALITY_HELPERS_AVAILABLE
                        tmCtx.ob_quality01   = StructOB::_ZoneOBNormalizedScore01(obPick_tm);
                        tmCtx.ob_freshness01 = StructOB::_ZoneFreshnessExport01(obPick_tm);
                        tmCtx.ob_sd_score01  = StructOB::_ZoneSDNormalizedScore01(obPick_tm);
                        tmCtx.fvg_overlap01  = obPick_tm.fvgOverlap01;
                        tmCtx.ob_touch_count = obPick_tm.touchCount;
                     #endif
                  }

                  tmCtx.data_populated = true;
                  tmDataOk = ComputeLevelTimeMemory(
                     sym, tf, zoneLo, zoneHi, tmLookback,
                     cfg.axis_time_memory_band_pct, tmCtx, tmResult);
               }
               else
               #endif // AXIS_TIME_MEMORY_ENHANCED
               {
                  // Fallback: original call without context
                  tmDataOk = ComputeLevelTimeMemory(
                     sym, tf, zoneLo, zoneHi, tmLookback,
                     cfg.axis_time_memory_band_pct, tmResult);
               }

               if(tmDataOk && tmResult.data_valid)
               {
                  const bool tmConfirms = (tmResult.memory_score >= cfg.axis_time_memory_min_score);

                  const double tmQualMult =
                     LevelTimeMemory_QualityMultiplier(tmResult.memory_score, 0.88, 1.12);

                  _ML::Append(R,
                              tmConfirms,
                              cfg.w_axis_time_memory * tmQualMult,
                              StringFormat("AxisTimeMem[sc=%.2f t=%d]",
                                           tmResult.memory_score,
                                           tmResult.touch_count),
                              C_AXIS_TIME_MEM);

                  if(CfgDebugStrategies(cfg))
                  {
                     DbgStrat(cfg, sym, tf, "AxisTimeMem",
                        StringFormat("[AxisTimeMem] sym=%s tf=%d dir=%s"
                                     " zone=[%.5f..%.5f] src=%s"
                                     " touches=%d/%d density=%.3f score=%.3f confirms=%d",
                                     sym, (int)tf, (dir == DIR_BUY ? "BUY" : "SELL"),
                                     zoneLo, zoneHi, srcTm,
                                     tmResult.touch_count, tmResult.lookback_used,
                                     tmResult.touch_density, tmResult.memory_score,
                                     (tmConfirms ? 1 : 0)),
                        true);
                  }
               }
            }
         }
         #endif // AXIS_TIME_MEMORY_AVAILABLE
         
         // Final confirmation group (CANDLE or CHART or TREND)
         const bool needConfirm =
                  cfg.cf_candle_pattern ||
                  (cfg.cf_chart_pattern && !cfg.cf_autochartist_chart) ||
                  cfg.cf_trend_regime ||
                  cfg.cf_autochartist_chart ||
                  cfg.cf_autochartist_fib ||
                  cfg.cf_autochartist_keylevels ||
                  cfg.cf_autochartist_volatility;

         bool requireAny = true;
         #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
           requireAny = cfg.main_confirm_any_of_3;
         #endif
         
         bool okCandle=true, okChart=true, okTrend=true;
         
         double qAuto = 0.0;
         double qTmp = 0.0;
         bool okAutoChart = false;
         bool okAutoKey   = false;
         bool okAutoVol   = false;
         bool okAutoFib   = false;
         
         // Autochartist confirms (sequential path)
         double qChart = 0.0;
         bool chartDataOk = haveAuto;

         if(cfg.cf_autochartist_chart && haveAuto)
            okAutoChart = AutoC_ChartCONFIRM_FromSnap(sym, tf, dir, cfg, autoS, qChart, chartDataOk);

         if(cfg.cf_autochartist_fib && haveAuto)
            okAutoFib = AutoC_FibOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp);
            
         if(cfg.cf_autochartist_keylevels && haveAuto)
            okAutoKey = AutoC_KeyLevelsOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp);

         if(cfg.cf_autochartist_volatility && haveAuto)
            okAutoVol = AutoC_VolOK_FromSnap(sym, tf, dir, cfg, autoS, qTmp);
      
         // Now include them in the "require any confirm" test
         if(cfg.cf_candle_pattern)
         {
           okCandle = HasBullBearCandlePattern(sym, tf, dir, cfg);
           _ML::Append(R, okCandle, cfg.w_candle_pattern, "CndlPattern", C_CANDLE);
         }
         
         // -----------------------------------------------------------------------
         // C.A.N.D.L.E. N — Narrative Cluster Exhaustion Gate
         // Runs the multi-candle body/wick/close scorer to detect opposing-side
         // exhaustion.  This vote is ADDITIVE alongside the named-pattern gate —
         // it does not replace HasBullBearCandlePattern().
         // -----------------------------------------------------------------------
         #ifdef CANDLE_NARRATIVE_AVAILABLE
         if(cfg.cf_candle_narrative)
         {
            CandleNarrativeResult narrResult;
            ZeroMemory(narrResult);

            const int narrLookback = (cfg.candle_narrative_lookback >= 2 &&
                                       cfg.candle_narrative_lookback <= 10)
                                      ? cfg.candle_narrative_lookback : 4;

            // Build CandleNarrativeCtx from data available in EvalSequentialEx scope.
            // Runs the enriched path only when CANDLE_NARRATIVE_ENHANCED is defined.
            bool narrDataOk = false;
            #ifdef CANDLE_NARRATIVE_ENHANCED
            if(cfg.candle_narrative_use_patterns ||
               cfg.candle_narrative_use_vsa      ||
               cfg.candle_narrative_use_amd      ||
               cfg.candle_narrative_htf_weight > 0.0 ||
               cfg.candle_narrative_vol_scale)
            {
               CandleNarrativeCtx narrCtx;
               narrCtx.Reset();

               // --- PatternSet: run a fresh scan (closed-bar safe, non-repaint) ---
               if(cfg.candle_narrative_use_patterns)
               {
                  Patt::PatternSet P;
                  if(Patt::ScanAll(sym, tf, 80, P))
                  {
                     narrCtx.patt_cs_ampdi01    = P.cs_score_ampdi01;
                     narrCtx.patt_cs_trend01    = P.cs_trend01;
                     narrCtx.patt_cs_vol01      = P.cs_vol01;
                     narrCtx.patt_cs_mom01      = P.cs_mom01;
                     narrCtx.patt_ch_ampdi01    = P.ch_score_ampdi01;
                     narrCtx.patt_ch_trend01    = P.ch_trend01;
                     narrCtx.patt_cs_best_score = P.cs_best_score01;
                     narrCtx.patt_ch_best_score = P.ch_best_score01;
                     narrCtx.patt_cs_bull       = P.cs_best_bull;
                     narrCtx.patt_ch_bull       = P.ch_best_bull;
                     narrCtx.patt_sd_htf_aligned= P.sd_htf_aligned;
                  }
               }

               // --- VSA climax context from ICT_Context scalar fields ---
               if(cfg.candle_narrative_use_vsa)
               {
                  // vsaBuyingClimax  = buying climax detected (bearish exhaustion → SELL signal)
                  // vsaSellingClimax = selling climax detected (bullish exhaustion → BUY signal)
                  narrCtx.vsa_climax_against = (dir == DIR_BUY)
                     ? ctx.vsaSellingClimax    // selling climax is AGAINST a sell, so BUY exhaustion confirmed
                     : ctx.vsaBuyingClimax;    // buying climax is AGAINST a buy, so SELL exhaustion confirmed
                  narrCtx.vsa_climax_score01 = ctx.vsaClimaxScore;
                  narrCtx.vsa_spring         = ctx.wySpringCandidate;
                  narrCtx.vsa_upthrust       = ctx.wyUTADCandidate;
               }

               // --- ATR from MarketData (no ATR field on ICT_Context; compute inline) ---
               narrCtx.atr_pts    = Indi::ATRPoints(sym, tf, 14, 1);

               // --- Volatility regime: use vwapVolumeRegime as a proxy [0..1] ---
               // vwapVolumeRegime: 0=low, 1=normal, 2=high (map to [0..1])
               narrCtx.vol_regime01 = _Clamp01((double)ctx.vwapVolumeRegime / 2.0);

               // --- AMD phase via helper functions (correct access pattern) ---
               if(cfg.candle_narrative_use_amd)
               {
                  const int ph1 = Ctx_AMDPhase_H1(ctx);
                  const int ph4 = Ctx_AMDPhase_H4(ctx);
                  narrCtx.amd_accumulation = (ph1 == AMD_PHASE_ACCUM || ph4 == AMD_PHASE_ACCUM)
                                              || ctx.wySpringCandidate;
                  narrCtx.amd_distribution = (ph1 == AMD_PHASE_DIST  || ph4 == AMD_PHASE_DIST)
                                              || ctx.wyUTADCandidate;
                  narrCtx.amd_manipulation = (ph1 == AMD_PHASE_MANIP || ph4 == AMD_PHASE_MANIP);
               }

               // --- HTF trend: use Wyckoff macro-state flags on ICT_Context ---
               // wyInAccumulation / wyInMarkup / wyInDistribution / wyInMarkdown are
               // the HTF narrative flags set by the ICT model for the D1/H4 phase.
               if(cfg.candle_narrative_htf_weight > 0.0)
               {
                  const bool htfBull = ctx.wyInAccumulation || ctx.wyInMarkup;
                  const bool htfBear = ctx.wyInDistribution || ctx.wyInMarkdown;
                  narrCtx.htf_trend_aligned    = (dir == DIR_BUY) ? htfBull : htfBear;
                  // Strength: both HTF phases aligned = 1.0; one = 0.60; neither = 0.0
                  narrCtx.htf_trend_strength01 = htfBull
                     ? (ctx.wyInMarkup ? 1.0 : 0.60)
                     : (htfBear ? (ctx.wyInMarkdown ? 1.0 : 0.60) : 0.0);
               }

               narrCtx.data_populated = true;
               narrDataOk = ComputeCandleNarrative(sym, tf, dir, narrLookback, narrCtx, narrResult);
            }
            else
            #endif // CANDLE_NARRATIVE_ENHANCED
            {
               // Fallback: original OHLC-only call (no ctx parameter)
               narrDataOk = ComputeCandleNarrative(sym, tf, dir, narrLookback, narrResult);
            }

            if(narrDataOk && narrResult.data_valid)
            {
               const bool narrConfirms =
                  (narrResult.exhaustion_score >= cfg.candle_narrative_min_score);

               _ML::Append(R,
                           narrConfirms,
                           cfg.w_candle_narrative,
                           StringFormat("NarrExhaust[%.2f]", narrResult.exhaustion_score),
                           C_CANDLE_NARR);

               // Optional hard veto in checklist mode
               if(requireChecklist && cfg.candle_narrative_veto && !narrConfirms)
                  return _ML::Finalize(R, cfg, "Seq@NarrativeExhaustion");

               if(CfgDebugStrategies(cfg))
               {
                  const string dirStr = (dir == DIR_BUY ? "BUY" : "SELL");
                  DbgStrat(cfg, sym, tf, "NarrCluster",
                     StringFormat("[NarrCluster] sym=%s tf=%d dir=%s"
                                  " body_slope=%.3f wick_slope=%.3f close_slope=%.3f"
                                  " exhaust=%.3f confirms=%d",
                                  sym, (int)tf, dirStr,
                                  narrResult.body_ratio_slope,
                                  narrResult.wick_trend_slope,
                                  narrResult.close_quality_slope,
                                  narrResult.exhaustion_score,
                                  (narrConfirms ? 1 : 0)),
                     true);
               }
            }
         }
         #endif // CANDLE_NARRATIVE_AVAILABLE
         
         if(cfg.cf_chart_pattern && !cfg.cf_autochartist_chart)
         {
            okChart = HasBullBearChartPattern(sym, tf, dir, cfg);
            _ML::Append(R, okChart, cfg.w_chart_pattern, "ChartPattern", C_CHART);
         }
         
         if(cfg.cf_trend_regime)
         {
           okTrend = TrendFilterPasses(sym, tf, dir, cfg);
           _ML::Append(R, okTrend, cfg.w_trend_regime, "TrendFilter", C_TREND);
         }
         
         if(cfg.cf_autochartist_chart && haveAuto && chartDataOk)
            _ML::Append(R, okAutoChart, cfg.w_autochartist_chart, "AutoChart", C_AUTO_CHART);
         
         if(cfg.cf_autochartist_fib && haveAuto)
            _ML::Append(R, okAutoFib, cfg.w_autochartist_fib, "AutoFib", C_AUTO_FIB);
            
         if(cfg.cf_autochartist_keylevels && haveAuto)
            _ML::Append(R, okAutoKey, cfg.w_autochartist_keylevels, "AutoKeyLv", C_AUTO_KEYLEVELS);
         
         if(cfg.cf_autochartist_volatility && haveAuto)
            _ML::Append(R, okAutoVol, cfg.w_autochartist_volatility, "AutoVol", C_AUTO_VOL);
         
         const bool confirmAny =
            (cfg.cf_candle_pattern && okCandle) ||
            ((cfg.cf_chart_pattern && !cfg.cf_autochartist_chart) && okChart) ||
            (cfg.cf_trend_regime && okTrend);
         
         const bool confirmAny2 =
            confirmAny ||
            (cfg.cf_autochartist_chart && haveAuto && chartDataOk && okAutoChart) ||
            (cfg.cf_autochartist_fib && haveAuto && okAutoFib) ||
            (cfg.cf_autochartist_keylevels && haveAuto && okAutoKey) ||
            (cfg.cf_autochartist_volatility && haveAuto && okAutoVol);

          if(needConfirm && requireAny && !confirmAny2 && !testerLooseGate)
          {
            if(requireChecklist && !confirmAny2) return _ML::Finalize(R, cfg, "Seq@ConfirmAny");
          }
         
         return _ML::Finalize(R, cfg, "Sequential");
      }

   ConfluenceResult EvalSequential(const string sym, const ENUM_TIMEFRAMES tf, const Direction dir,
                                   const Settings &cfg, const ICT_Context &ctx)
   {
      AutoSnapshot autoS;
      bool haveAuto = false;
   
      const bool wantAuto =
         (cfg.auto_enable &&
          (cfg.cf_autochartist_chart ||
           cfg.cf_autochartist_fib ||
           cfg.cf_autochartist_keylevels ||
           cfg.cf_autochartist_volatility));
   
      if(wantAuto)
         haveAuto = AutoC::GetSnapshot(sym, tf, cfg, autoS);
   
      return EvalSequentialEx(sym, tf, dir, cfg, ctx, haveAuto, autoS);
   }

   void Strat_MainTradingLogic::AugmentWithExtras_ifConfirmed(
    const string sym, const ENUM_TIMEFRAMES tf,
    const Direction dir, const Settings &cfg,
    StratScore &ss, ConfluenceBreakdown &bd)
    {
        const double score_before = Main_NormalizeFinalStrategyScore(ss.score, ss.eligible);

        ConfluenceResult R;
        R.metCount    = 0;
        R.score       = score_before;
        R.mask        = 0;
        R.summary     = ss.reason;
        R.passesCount = false;
        R.passesScore = false;
        R.eligible    = ss.eligible;

        ICT_Context ctx;
        Main_LoadCanonicalICTContext(sym, cfg, ctx);
        bool   newsComputed = false;
        bool   newsOK = true;
        double newsMult = 1.0;
        int    newsMins = 0;

        #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
           if(cfg.main_news_hard_veto)
           {
              newsOK = Extra_NewsOK(sym, cfg, newsMult, newsMins);
              newsComputed = true;
           }
           else if(cfg.extra_news)
           {
              Extra_NewsOK(sym, cfg, newsMult, newsMins);
              newsComputed = true;
           }
        #else
           if(cfg.extra_news)
           {
              Extra_NewsOK(sym, cfg, newsMult, newsMins);
              newsComputed = true;
           }
        #endif

        ::StratMainLogic::AugmentWithExtras_ifConfirmed(R, sym, tf, dir, cfg, ctx, newsComputed, newsOK, newsMult, newsMins);

        const double score_after = Main_NormalizeFinalStrategyScore(R.score, ss.eligible);

        if(score_after > 0.0 || score_before <= 0.0)
           ss.score = score_after;
        else
           ss.score = score_before;

        if(R.summary != "")
        {
           if(ss.reason != "")
              ss.reason = ss.reason + " | " + R.summary;
           else
              ss.reason = R.summary;
        }

        bd.score_after_penalty = ss.score;
    }

} // namespace StratMainLogic
// Registry-friendly factory + metadata
inline int StratMainTradingLogic_Id()
{
   return STRAT_MAIN_ID;
}

inline string StratMainTradingLogic_Name()
{
   return STRAT_MAIN_NAME;
}

inline StrategyBase* StratMainTradingLogic_Create()
{
   return StratMainLogic::GetMainTradingLogicStrategy();
}

#endif // CA_STRAT_MAIN_TRADING_LOGIC_MQH
