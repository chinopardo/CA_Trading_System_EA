//+------------------------------------------------------------------+
//|                  CA Trading System EA (Core)                     |
//|   Safety gates, session presets, registry router, PM & panel     |
//|   Multi-symbol scheduler (per-symbol last-bar & locks)           |
//|   Profile presets (weights/throttles) + CSV export               |
//|   Regression KPIs export + Golden-run compare                    |
//|   Carry bias integration (strict or mild) + ML blender           |
//|   Confluence blend weights per archetype (Trend/MR/Others)       |
//|   Price/time gates + streak-based lot scaling                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"   // Cleaned lifecycle; price/time gates; streak lot scaling; bug fixes

// ================= Registry Mode Switch ============================
// Uncomment to enable handle caching for indicators.
// #define CA_USE_HANDLE_REGISTRY
// ==================================================================
// DEPRECATED tester-only harness for EvaluateOneSymbol().
// This helper is non-canonical and retained only for explicit legacy tester compatibility checks.
// Canonical new-order routing ownership is:
// OnTimer() -> MSH::HubTimerTick() -> RefreshRuntimeContextFromHub() -> RunCachedRouterPass().
// Leave commented out for all normal builds.
// #define CA_ENABLE_EVALUATE_ONE_SYMBOL_TEST_UTILITY
// DEPRECATED tester-only harness for legacy ProcessSymbol() diagnostics.
// Diagnostic builds only. Leave commented out for all normal builds.
// #define CA_ENABLE_LEGACY_TESTER_PROCESSSYMBOL

// ------------------- Engine & Infra includes ----------------------
#include <Trade/Trade.mqh>
#include "include/Config.mqh"
#include "include/TesterSettings.mqh"
#include "include/Types.mqh"
#include "include/TimeUtils.mqh"
#include <DebugChecklist.mqh>
#include <CAEA_dbg.mqh>
#include "include/strategies/SanityChecks.mqh"

#ifdef CA_USE_HANDLE_REGISTRY
#include "include/HandleRegistry.mqh"
#endif

#include "include/ICTWyckoffModel.mqh"   // ICT_Context assembly helpers
#include "include/ICTSessionModel.mqh"   // killzones / Silver Bullet timing
#include "include/ICTWyckoffPlaybook.mqh"
#include "include/MarketData.mqh"
#include "include/Indicators.mqh"
#include "include/DeltaProxy.mqh"
#include "include/Fibonacci.mqh"
#include "include/VSA.mqh"
#include "include/VWAP.mqh" 
#include "include/StructureSDOB.mqh"
#include "include/PivotsLevels.mqh"
#include "include/Patterns.mqh"
#include "include/AutochartistEngine.mqh"
#include "include/LiquidityCues.mqh"
#include "include/RegimeCorr.mqh"
#include "include/NewsFilter.mqh"
#include "include/OrderBookImbalance.mqh"
#include "include/VolumeProfile.mqh"
#define CONFLUENCE_API_BYNAME

//#define UNIT_TEST_ROUTER_GATE
#include "include/Confluence.mqh"

// --- MarketScannerHub route hook (must be defined BEFORE including the hub) ---
void MSH_RouteEvent(const Scan::ScanEvent &e);
#define MARKETSCANNERHUB_CUSTOM_ROUTE(e)  MSH_RouteEvent(e)

#include "include/MarketScannerHub.mqh"
#include "include/InstitutionalStateVector.mqh"
#include "include/CategorySelector.mqh"
#include "include/StrategyHypothesisBank.mqh"

// Optional meta-layers
#define ENABLE_ML_BLENDER
#ifdef ENABLE_ML_BLENDER
   #ifndef ML_HAS_TRADE_OUTCOME_HOOKS
      #define ML_HAS_TRADE_OUTCOME_HOOKS
   #endif
#endif
#include "include/MLBlender.mqh"

// Core trading stack
#include "include/RiskEngine.mqh"
#include "include/Execution.mqh"
#include "include/PositionMgmt.mqh"
#include "include/Policies.mqh"
#include "include/Integration.mqh"
#include "include/Router.mqh"

// Persistence & backend-only runtime
#include "include/State.mqh"      // persistent day cache / last signal context
// #include "include/Panel.mqh"    // backend-only live build: disabled
#include "include/Telemetry.mqh"  // keep only if using file/JSON telemetry
// #include "include/ReviewUI.mqh" // backend-only live build: disabled
#include "include/Tester.mqh"
#include "include/Logging.mqh"
#include "include/Warmup.mqh"
#include "include/BuildFlags.mqh"

#ifndef ROUTER_TRACE_FLOW
#define ROUTER_TRACE_FLOW 1   // set to 1 to enable #F breadcrumbs
#endif

// ================== Globals ==================
Settings g_cfg;        // live config snapshot (ICT/router-aware Settings)
EAState    g_state;      // global EA state (market buffers, ICT_Context, etc.)
CArrayObj g_strategies;  // StrategyBase*
Router   g_exec_router;     // strategy router / dispatcher
bool     g_inited = false;

// Canonical timer-owned transport scratch.
// State.mqh remains the ownership layer for freshness/cache.
// These are per-pass working objects consumed by router/risk/execution.
ISV::RawSignalBank_t                g_raw_bank;
CategorySelectedVector_t            g_cat_selected;
CategoryPassVector_t                g_cat_pass;
ISV::SignalStackGate_t              g_sig_stack_gate;
ISV::LocationPass_t                 g_location_pass;
StrategyHypothesisBank_t            g_hyp_bank;
FinalStrategyIntegratedStateVector_t g_final_integrated;

bool                                g_transport_ready = false;
datetime                            g_transport_bar_time = 0;
string                              g_transport_sym = "";

//--------------------------------------------------------------------
// Forward declarations for helper functions we add in this file
//--------------------------------------------------------------------
void BuildSettingsFromInputs(Settings &cfg);
string RuntimeSettingsHashHex(const Settings &cfg);
void   DriftAlarm_SetApproved(const string reason);
void   DriftAlarm_Check(const string where);

void PushICTTelemetryToReviewUI(const ICT_Context &ictCtx);

void DecisionTelemetry_MarkPassiveSkip(const string why);
void DecisionTelemetry_MarkGateBlocked(const string source, const string why);
void DecisionTelemetry_MarkNoCandidates(const string source, const string why);
void DecisionTelemetry_RecordPassFromPick(const string source,
                                          const StratReg::RoutedPick &pick);
void DecisionTelemetry_RecordPassFromRouterSnapshot(const string source);

void DecisionTelemetry_ResetTimerNotNewBarThrottle(const string sym,
                                                   const ENUM_TIMEFRAMES tf,
                                                   const datetime bar_time,
                                                   const datetime latch_time);

bool DecisionTelemetry_ShouldEmitTimerNotNewBar(const string sym,
                                                const ENUM_TIMEFRAMES tf,
                                                const datetime bar_time,
                                                const datetime latch_time);

void EmitDeterministicStartupStrategyAudit(const Settings &cfg);

bool RunMainOnlyConsistencyAudit(const Settings &cfg);
bool g_main_only_audit_empty_roster = false;

void PublishTesterDegradedFallbackRuntimeState(const string sym,
                                               const bool active,
                                               const string status,
                                               const string detail);
bool GetTesterDegradedFallbackRuntimeState(const string sym,
                                          bool &active,
                                          string &status,
                                          string &detail);

bool RuntimeTesterDegradedScorePolicySnapshot(const string sym,
                                              bool &active,
                                              string &policy_type,
                                              double &magnitude);
string RuntimeTesterDegradedScorePolicyTypeName(const int policy_type);

inline void _UnusedICTContext(const ICT_Context &ctx) { }

// Backend-only UI wrappers (no-op unless BUILD_WITH_UI is defined elsewhere)
void UI_Render(const Settings &cfg);
void UI_SetGate(const int gate_reason);
void UI_Init(const Settings &cfg);
void UI_Deinit();
void UI_PublishDecision(const ConfluenceBreakdown &bd, const StratScore &ss);
void UI_OnTradeTransaction(const MqlTradeTransaction &tx, const MqlTradeResult &rs);
void UI_Screenshot(const string tag);

// EA-side microstructure refresh bridge
bool RefreshMicrostructureSnapshot(const string sym, const bool force_refresh=false);
void PublishMicrostructureSnapshot(const string sym);
string CanonicalRouterSymbol();
bool   MicrostructureGateOK(const string sym, const datetime now_srv, const datetime required_bar_time, string &detail);

void ApplyTesterOnlyFeatureOverrides(Settings &cfg); // legacy bridge -> TesterSettings::ApplyToConfig
void RefreshICTContext(EAState &st);

bool RuntimeMainChecklistSoftFallbackEnabled();
bool UseLegacyProcessSymbolEngine();
bool DirectRegistryCompatRuntimeRequested(const Settings &cfg);
void WarnDirectRegistryCompatBlockedOnce(const string origin_tag,
                                         const Settings &cfg);

datetime ResolveCanonicalInstitutionalRequiredBarTime(const string sym);
datetime ResolveCanonicalInstitutionalClosedBarAnchorTime(const string sym);
bool EnsureCanonicalInstitutionalStateReady(const string sym,
                                            const datetime required_bar_time,
                                            string &diag_out);
void LogCanonicalInstitutionalGateDiag(const string sym,
                                       const datetime required_bar_time,
                                       const string origin_tag);
bool PreseedRuntimeSymbolStateAtStartup(const string sym,
                                        const Settings &cfg,
                                        string &diag_out);
void PreseedRuntimeSymbolPoolAtStartup(const Settings &cfg);
void ResetCanonicalSignalStackTransport();

bool BuildCanonicalSignalStackTransport(const string sym,
                                       const datetime required_bar_time,
                                       string &diag_out);

bool EA_IsTrackedWatchlistSymbol(const string sym);
void EA_EnsureCentralDOMSubscriptions();
void EA_ReleaseCentralDOMSubscriptions();

// ------------------------------------------------------------------
// Provide ONE global, guarded helper used by strategies.
// Strategy headers that also define this will be skipped by the guard.
// ------------------------------------------------------------------
#ifndef CONFL_BASE_RULES_SAFE_INLINE_GUARD
#define CONFL_BASE_RULES_SAFE_INLINE_GUARD
inline double ConflBaseRulesScoreSafe(const Direction dir,
                                      ConfluenceBreakdown &bd,
                                      const Settings &cfg,
                                      StratScore &ss)
  {
#ifdef CONFLUENCE_HAS_BASERULES
   return Confl::BaseRulesScore(dir, bd, cfg, ss);
#else
   bd.score_base=0.0;
   bd.score_after_penalty=0.0;
   bd.score_ml=0.0;
   bd.score_final=0.0;
   bd.veto=false;
   ss.id=(StrategyID)0;
   ss.score=0.0;
   ss.eligible=false;
   ss.risk_mult=1.0;
   return 0.0;
#endif
  }
#endif // CONFL_BASE_RULES_SAFE_INLINE_GUARD

// ------------------- Concrete strategies --------------------------
#include "include/strategies/StrategyCommon.mqh"
#include "include/strategies/StrategyBase.mqh"
#include "include/strategies/Strat_MainTradingLogic.mqh"
#include "include/strategies/Strat_Trend_VWAPPullback.mqh"
#include "include/strategies/Strat_Trend_BOSContinuation.mqh"
#include "include/strategies/Strat_MR_VWAPBand.mqh"
#include "include/strategies/Strat_MR_RangeNR7IB.mqh"
#include "include/strategies/Strat_Breakout_ORB.mqh"
#include "include/strategies/Strat_Breakout_Squeeze.mqh"
#include "include/strategies/Strat_Reversal_SweepCHOCH.mqh"
#include "include/strategies/Strat_Reversal_VSAClimaxFade.mqh"
#include "include/strategies/Strat_Corr_Divergence.mqh"
#include "include/strategies/Strat_Pairs_SpreadLite.mqh"
#include "include/strategies/Strat_News_Deviation.mqh"
#include "include/strategies/Strat_News_PostFade.mqh"

// Carry module — NEVER-SIGNAL by default (recommended). If you truly want
// carry to compete as a standalone strategy, define CARRY_CAN_SIGNAL=1
// BEFORE including the header (not recommended for production).
#include "include/strategies/StrategiesCarry.mqh"

// ------------------- Strategy registry (after strategies) ---------
#include "include/strategies/StrategyDirectExecGuards.mqh"
#include "include/strategies/StrategyRegistry.mqh"

// Human-readable strategy mode name (local, compile-safe)
inline string StrategyModeNameLocal(const StrategyMode s)
{
  switch(s)
  {
    case STRAT_MAIN_ONLY: return "Main Trading Strat";
    case STRAT_PACK_ONLY: return "Strat Pack";
    default:              return "Combined Main Trading & Strat Pack";
  }
}

// ---------------- Router confluence-only pool diagnostics ----------------
// Prints pool intent + key flags (compile-safe; no spam unless called).
inline void LogRouterConfluencePoolStatus(const Settings &cfg, const string where_tag)
{
  bool   use_pool = false;
  double blend_w  = 0.0;
  bool   have_any = false;

  #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
    use_pool = cfg.router_use_confl_pool;
    have_any = true;
  #endif

  #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
    blend_w  = cfg.router_pool_blend_w;
    have_any = true;
  #endif

  if(!have_any) return;

  const bool wanted = (use_pool || (blend_w > 0.0));
  const StrategyMode sm = Config::CfgStrategyMode(cfg);

  string msg = StringFormat("%s RouterPool: wanted=%d use=%d w=%.2f mode=%s(%d)",
                            where_tag,
                            (wanted ? 1 : 0),
                            (use_pool ? 1 : 0),
                            blend_w,
                            StrategyModeNameLocal(sm),
                            (int)sm);

  #ifdef CFG_HAS_ENABLE_PACK_STRATS
    msg += StringFormat(" enable_pack_strats=%d", (cfg.enable_pack_strats ? 1 : 0));
  #endif
  #ifdef CFG_HAS_DISABLE_PACKS
    msg += StringFormat(" disable_packs=%d", (cfg.disable_packs ? 1 : 0));
  #endif

  LogX::Info(msg);

  // Helpful warnings (no behavior changes)
  if(sm == STRAT_MAIN_ONLY && wanted)
  {
    #ifdef CFG_HAS_ENABLE_PACK_STRATS
      if(!cfg.enable_pack_strats)
        LogX::Warn("RouterPool is ON in MAIN_ONLY but enable_pack_strats=false; confluence-only pool may be empty.");
    #endif
    #ifdef CFG_HAS_DISABLE_PACKS
      if(cfg.disable_packs)
        LogX::Warn("RouterPool is ON in MAIN_ONLY but disable_packs=true; pack confluence pool is hard-disabled.");
    #endif
  }
}

// Optional: log once-per-entry-bar (prevents timer/tick spam)
inline void MaybeLogRouterConfluencePoolStatusOncePerBar(const Settings &cfg, const string where_tag)
{
  // Only when debug-ish
  bool want = cfg.debug;
  #ifdef CFG_HAS_ROUTER_DEBUG_LOG
    if(cfg.router_debug_log) want = true;
  #endif
  if(!want) return;

  static datetime s_last_bt = 0;
  const datetime bt = iTime(_Symbol, (ENUM_TIMEFRAMES)cfg.tf_entry, 0);
  if(bt <= 0) return;
  if(bt == s_last_bt) return;
  s_last_bt = bt;

  LogRouterConfluencePoolStatus(cfg, where_tag);
}

void EmitDeterministicStartupStrategyAudit(const Settings &cfg)
{
   LogX::Info(StratReg::BuildStartupAuditSummary(cfg));

   const StrategyMode sm = Config::CfgStrategyMode(cfg);
   const bool in_tester = IsTesterRuntime();
   const int tradable_n = StratReg::CountTradableRegisteredStrategies(cfg);

   if(in_tester)
   {
      const bool deprecated_selected_non_core_requested =
         (InpTester_MainOnlyAllowSelectedNonCoreOrderables ||
          StringLen(InpTester_MainOnlySelectedNonCoreIds) > 0);

      if(deprecated_selected_non_core_requested)
      {
         LogX::Warn(StringFormat(
            "[StartupAudit] tester MAIN_ONLY selected non-core override requested but deprecated/ignored. requested_flag=%s ids=%s active_behavior=ignored final_authority=Config::IsStrategyAllowedInMode canonical_execution=RunCachedRouterPass(Timer)->RouterEvaluateAll",
            (InpTester_MainOnlyAllowSelectedNonCoreOrderables ? "true" : "false"),
            (StringLen(InpTester_MainOnlySelectedNonCoreIds) > 0 ? InpTester_MainOnlySelectedNonCoreIds : "NONE")));
      }

      if(Config::CfgTesterSmokeRealSendArmed(cfg))
      {
         LogX::Warn("[StartupAudit] tester_smoke_real_sends_armed=true. Any send tagged exec_origin_class=diagnostic exec_origin_reason=TESTER_SMOKE is non-canonical and not strategy-routed.");
      }

      if(tradable_n < 3)
      {
         LogX::Warn(StringFormat(
            "[StartupAudit] tester safety warning: mode=%s(%d) tradable_in_mode=%d < 3. Orderable coverage is thin and tester diagnostics may be misleading.",
            StrategyModeNameLocal(sm),
            (int)sm,
            tradable_n));
      }
   }
   else
   {
      if(InpTester_MainOnlyAllowSelectedNonCoreOrderables || StringLen(InpTester_MainOnlySelectedNonCoreIds) > 0)
      {
         LogX::Warn("[StartupAudit] deprecated tester MAIN_ONLY selected non-core override inputs are configured but ignored outside tester.");
      }

      if(sm != STRAT_MAIN_ONLY && tradable_n < 2)
      {
         LogX::Warn(StringFormat(
            "[StartupAudit] low tradable population: mode=%s(%d) tradable_in_mode=%d. Candidate pool may be under-populated.",
            StrategyModeNameLocal(sm),
            (int)sm,
            tradable_n));
      }
   }
}

bool AuditArrayHasInt(const int &arr[], const int value)
{
   for(int i=0; i<ArraySize(arr); i++)
      if(arr[i] == value)
         return true;

   return false;
}

string AuditStrategyIdListToString(const int &ids[])
{
   string out = "";

   for(int i=0; i<ArraySize(ids); i++)
   {
      const StrategyID sid = (StrategyID)ids[i];

      if(StringLen(out) > 0)
         out += ", ";

      out += StringFormat("%s(%d)", StratReg::FriendlyName(sid), ids[i]);
   }

   if(StringLen(out) == 0)
      out = "NONE";

   return out;
}

bool RunMainOnlyConsistencyAudit(const Settings &cfg)
{
   g_main_only_audit_empty_roster = false;

   Settings audit_cfg = cfg;
   Config::ApplyStrategyMode(audit_cfg, STRAT_MAIN_ONLY);
   Config::Normalize(audit_cfg);

   int expected_ids[];
   Config::FillCanonicalMainOnlyIds(expected_ids);

   if(ArraySize(expected_ids) <= 0)
   {
      g_main_only_audit_empty_roster = true;
   
      LogX::Error(StringFormat(
         "[FATAL][MainOnlyAudit] canonical MAIN_ONLY roster empty | mode=%d | main=%d sb=%d po3=%d cont=%d wyck=%d",
         (int)Config::CfgStrategyMode(cfg),
         (int)cfg.enable_strat_main,
         (int)cfg.enable_strat_ict_silverbullet,
         (int)cfg.enable_strat_ict_po3,
         (int)cfg.enable_strat_ict_continuation,
         (int)cfg.enable_strat_ict_wyckoff_turn
      ));
      return false;
   }

   int router_missing_ids[];
   Router_FillMainOnlyModeFilterUnrecognizedIds(audit_cfg, router_missing_ids);

   int eligible_ids[];
   StratReg::FillEligibleRegisteredIds(audit_cfg, eligible_ids, true);

   int extra_ids[];
   ArrayResize(extra_ids, 0);

   for(int i=0; i<ArraySize(eligible_ids); i++)
   {
      if(!AuditArrayHasInt(expected_ids, eligible_ids[i]))
      {
         const int k = ArraySize(extra_ids);
         ArrayResize(extra_ids, k + 1);
         extra_ids[k] = eligible_ids[i];
      }
   }

   bool critical_mismatch = false;

   for(int i=0; i<ArraySize(expected_ids); i++)
   {
      const StrategyID sid = (StrategyID)expected_ids[i];

      bool registered_now = false;
      bool enabled_capable = false;
      bool enabled_now = false;
      bool tradable_now = false;
      string slug = "";

      StratReg::QueryMainOnlyExpectedIdState(audit_cfg,
                                             sid,
                                             registered_now,
                                             enabled_capable,
                                             enabled_now,
                                             tradable_now,
                                             slug);

      if(enabled_capable && !registered_now)
      {
         critical_mismatch = true;

         LogX::Error(StringFormat(
            "[FATAL][MainOnlyAudit] expected canonical MAIN_ONLY id missing from registry id=%d name=%s slug=%s enabled_capable=true",
            (int)sid,
            StratReg::FriendlyName(sid),
            slug));
      }
      else if(!enabled_capable && !registered_now)
      {
         LogX::Warn(StringFormat(
            "[WARN][MainOnlyAudit] canonical MAIN_ONLY id not registered because current config disables it id=%d name=%s",
            (int)sid,
            StratReg::FriendlyName(sid)));
      }
   }

   if(ArraySize(router_missing_ids) > 0)
   {
      critical_mismatch = true;

      LogX::Error(StringFormat(
         "[FATAL][MainOnlyAudit] router MAIN_ONLY mode filters do not recognize canonical ids: %s",
         AuditStrategyIdListToString(router_missing_ids)));
   }

   if(ArraySize(extra_ids) > 0)
   {
      if(IsTesterRuntime())
      {
         LogX::Warn(StringFormat(
            "[WARN][MainOnlyAudit] extra MAIN_ONLY-tradable ids detected outside canonical policy list: %s",
            AuditStrategyIdListToString(extra_ids)));
      }
      else
      {
         critical_mismatch = true;

         LogX::Error(StringFormat(
            "[FATAL][MainOnlyAudit] live MAIN_ONLY tradable set contains extra ids outside canonical policy list: %s",
            AuditStrategyIdListToString(extra_ids)));
      }
   }

   LogX::Info(StringFormat(
      "[MainOnlyAudit] expected=%s eligible_now=%s",
      AuditStrategyIdListToString(expected_ids),
      AuditStrategyIdListToString(eligible_ids)));

   if(critical_mismatch && InpStrat_Mode == STRAT_MAIN_ONLY)
   {
      LogX::Error("[FATAL][MainOnlyAudit] fail-closed: InpStrat_Mode=STRAT_MAIN_ONLY requires canonical MAIN_ONLY ID parity across Config, StrategyRegistry, and Router.");
      return false;
   }

   return true;
}

// ================== User Inputs ==================
// Assets / TFs
input string           InpAssetList             = "CURRENT"; // "CURRENT" or comma/space-separated symbols
input ENUM_TIMEFRAMES  InpEntryTF               = PERIOD_M15; // Entry Timeframe
input ENUM_TIMEFRAMES  InpHTF_H1                = PERIOD_H1; // Low HTF
input ENUM_TIMEFRAMES  InpHTF_H4                = PERIOD_H4; // Mid HTF
input ENUM_TIMEFRAMES  InpHTF_D1                = PERIOD_D1; // High HTF
// --- Timeframe / risk core ---
input ENUM_TIMEFRAMES InpTfHTF            = PERIOD_H4;  // ICT: HTF
input double          InpRiskPerTradePct  = 0.40;       // ICT: Risk Per Trade

// --- Manual direction selector (legacy control) ---
// DIR_BUY / DIR_SELL / DIR_BOTH (enum from Types.mqh)
input ENUM_TRADE_DIRECTION InpTradeDirectionSelector = TDIR_BOTH;

// --- Bias control ---
// If true => we let Smart Money / ICT auto-bias drive direction gating
//            (i.e. only long in markup, only short in markdown).
// If false => we obey InpTradeDirectionSelector.
input bool InpUseICTBias                  = true;    // "use_ICT_bias"

// We reflect this into cfg.direction_bias_mode later.

// --- Session gating / killzone discipline ---
// If true => only allow entries when we're inside a valid killzone window
//            (London, NY AM, NY PM). This is used by all strategies if desired.
input bool InpEnforceKillzone             = true;    // "enforce_killzone"

// --- Silver Bullet mode master switch ---
// If false => even if Silver Bullet setup conditions are met, we won't fire SB trades.
input bool InpEnable_SilverBulletMode     = true;    // "enable_silver_bullet"

// --- PO3 mode master switch ---
// If false => PO3 strategies won't arm even if PO3 distribution is live.
input bool InpEnable_PO3Mode              = true;    // "enable_PO3"

// --- Quality thresholds ---
// Global "this setup is good enough to touch real money"
// Fine-tuned thresholds for specialized strategies
input double InpQualityThresholdHigh      = 0.25;
input double InpQualityThresholdCont      = 0.20;    // continuation / pullback (OB+FVG+OTE)
input double InpQualityThresholdReversal  = 0.20;    // Wyckoff Spring / UTAD style reversals

// --- Fibonacci / OTE configuration (ICT/Wyckoff) ---
input int    InpFibDepth              = 5;      // Fib: pivot depth for leg detection
input int    InpFibATRPeriod          = 14;     // Fib: ATR period used for deviation
input double InpFibDevATRMult         = 3.0;    // Fib: dev threshold (ATR-based)
input int    InpFibMaxBarsBack        = 500;    // Fib: max bars scanned for legs

input bool   InpFibUseConfluence      = true;   // Fib: enable 2-leg OTE confluence
input double InpFibMinConfScore       = 0.35;   // Fib: 0..1, min accepted confluence
input double InpFibOTEToleranceATR    = 0.25;   // Fib: distance from OTE band (ATR units)

// --- Direction bias mode explicit override for debugging ---
// 0 = manual selector
// 1 = auto ICT/Wyckoff bias (will override manual even if you forgot InpUseICTBias)
input Config::DirectionBiasMode InpDirectionBiasMode = Config::DIRM_AUTO_SMARTMONEY; // Direction Bias Mode

// Risk core
input double           InpRiskPct               = 0.40; // Risk Percentage
input double           InpRiskCapPct            = 1.00; // Risk Cap Percentage
input double           InpChallengeInitEquity   = 0.0;  // Challenge Baseline: 0=auto capture; else force initial equity baseline
input double           InpMinSL_Pips            = 10.0; // Min SL (Pips)
input double           InpMinTP_Pips            = 15.0; // Min TP (Pips)
input double           InpMaxSLCeiling_Pips     = 2500.0; // Max Ceiling (Pips)
input double           InpMaxDailyDD_Pct        = 2.0; // Max Daily DD Percentage
input double           InpDayDD_LimitPct        = 2.0; // Max Daily DD taper onset (%); scales risk down from here

// ---- Adaptive Daily DD (rolling peak equity) ----
// Uses rolling peak equity over N days as the anchor for daily DD.
// 0.0 pct means "use InpMaxDailyDD_Pct".
input bool             InpAdaptiveDD_Enable       = false; // Adaptive DD Enable
input int              InpAdaptiveDD_WindowDays   = 30;    // Adaptive DD Window (days)
input double           InpAdaptiveDD_Pct          = 0.0;   // Adaptive Daily DD % of rolling peak (0=use InpMaxDailyDD_Pct)

// --- Monthly profit target gate ---
// 0.0 = disabled; otherwise stop new entries once equity is up by this % vs month-start.
input double           InpMonthlyTargetPct      = 10.0; // Monthly Target: +10% equity per calendar month: 0.0 = disabled; otherwise stop new entries once equity is up by this % for the cycle.
input int              InpMonthlyTargetCycleMode = 0; // Monthly Target cycle: 0 = calendar month, 1 = rolling 28-day cycle
input int              InpMonthlyTargetBaseMode  = 1;    // Base mode 0 = cycle-start equity, 1 = initial equity (linear per cycle), 2 = initial equity (compound; reserved)

input int              InpMaxLossesDay          = 6; // Max Daily Losses
input int              InpMaxTradesDay          = 20; // Max Daily Trades
input int              InpMaxSpreadPoints       = 300; // Max Spread Points
input int              InpSlippagePoints        = 500; // Max Slippage Points

input double           InpPolicy_LiqMinRatio        = 1.50; // Policy: live ATR/spread floor
input double           InpPolicy_LiqMinRatioTester  = 0.0;  // Policy: tester floor; 0.0 = auto-adapt from live floor
input bool             InpPolicy_LiqInvalidHardFail = false; // Policy: hard-fail calm/liquidity when ATR or spread is invalid

// Loop controls / heartbeat
input bool             InpOnlyNewBar            = true; // Loop controls / heartbeat: Only New Bar - Per-symbol last-bar gate
input bool             InpMain_OnlyNewBar       = true; // Timer routing: require new bar before RouterEvaluateAll on OnTimer
input int              InpTimerMS               = 150; // Loop controls / heartbeat: Timer MS
input int              InpTester_TimerSec                  = 60;    // Tester: OnTimer / Hub heartbeat in seconds
input bool             InpTester_ForceTimerEveryHeartbeat  = false; // Tester: bypass EA-level timer new-bar gate and evaluate every timer heartbeat
input int              InpTimer_MinForcedRouterEvalSec     = 0;     // Timer routing: minimum forced canonical evaluation cadence when no dirty symbols; 0=auto from hub_timer_sec * idle_fallback_after_n
input int              InpServerOffsetMinutes   = 0; // Loop controls / heartbeat: Server Offset Mins

// -------- Session windows (UTC minutes) — legacy union (London/NY) --------
input bool             InpSessionFilter         = false; // Sessions: Filter Enable
input SessionPreset    InpSessionPreset         = SESS_TOKYO_C3_TO_NY_CLOSE; // Sessions: Preset
input int              InpLondonOpenUTC         = 7*60; // Sessions: Ldn Open UTC Time
input int              InpLondonCloseUTC        = 17*60; // Sessions: Ldn Close UTC Time
input int              InpNYOpenUTC             = 12*60 + 30; // Sessions: NY Open UTC Time
input int              InpNYCloseUTC            = 22*60; // Sessions: NY Close UTC Time
input int              InpTokyoCloseUTC         = 6*60;  // Sessions: Tky Close UTC Time
input int              InpSydneyOpenUTC         = 21*60; // Sessions: Syd Open UTC Time

// -------- Trade Selector --------
input TradeSelector    InpTradeSelector         = TRADE_BOTH_AUTO; // Trade Selector: TRADE_BOTH_AUTO = 0 (Evaluate BUY & SELL, select stronger), TRADE_BUY_ONLY  = 1, TRADE_SELL_ONLY = 2

// ======== NEW — Time & Price Gates (server time) ===================
input double           InpTradeAtPrice          = 0.0;     // Time & Price Gates: 0=disabled; Trade at price
input double           InpStopTradeAtPrice      = 0.0;     // Time & Price Gates: 0=disabled; Stop Trade at price
input datetime         InpStartTime             = 0;       // Time & Price Gates: 0=disabled; Start server time
input datetime         InpExpirationTime        = 0;       // Time & Price Gates: 0=disabled; Expiry server time

// ======== NEW — Streak-based Lot Scaling ===========================
// Safer defaults: double-up after N wins, halve after N losses (configurable)
input int              InpStreakWinsToDouble    = 2;       // Streak-based Lot Scaling: Win Streaks to Double 0=off
input int              InpStreakLossesToHalve   = 2;       // Streak-based Lot Scaling: Loose Streaks to Halves 0=off
input double           InpStreakMaxBoost        = 2.0;     // Streak-based Lot Scaling: Max Boost Streaks cap multiplier (>=1)
input double           InpStreakMinScale        = 0.5;     // Streak-based Lot Scaling: Min Scale Streaksfloor multiplier (<=1)

// ---- Global cap for any risk multiplier scaling (streak/strategy/ML) ----
input double           InpRiskMultMax          = 2.0;     // Risk Mult Cap: 1=disable boosts; >1 allows boosts up to this cap

// ---- Streak hard reset triggers ----
// When News derisks or blocks entries, reset streak counters so boosts cannot "undo" derisking.
input bool             InpResetStreakOnNewsDerisk = true;  // Reset streaks when news derisks/blocks

// ---- Big-loss sizing reset (handled by Policies via r_multiple) ----
// Requires Policies to latch a reset window and expose SizingResetActive().
input bool             InpBigLossReset_Enable     = true;  // Enable big-loss sizing reset
input double           InpBigLossReset_R          = 2.0;   // Threshold in R (reset if r_multiple <= -InpBigLossReset_R)
input int              InpBigLossReset_Mins       = 120;   // Reset window minutes

// -------- Registry Router & Strategy knobs --------
input int              InpRouterMode            = 0;    // Registry Router & Strategy: Mode - 0=MAX,1=WEIGHTED,2=AB
input int              InpAB_Bucket             = 0;    // Registry Router & Strategy: AB_Bucket - 0=OFF,1=A,2=B
input double           InpRouterMinScore        = 0.0;  // Registry Router & Strategy: Min Score (0.0 is now a valid explicit tester floor)
input int              InpRouterMaxStrats       = 10;   // Registry Router & Strategy: Max Strat
input int              InpRouterThresholdPrecedence   = -1;   // Router threshold precedence: -1=legacy bool fallback, 0=manual, 1=profile
input bool             InpRouterTesterPreferManualThresholds = true; // Tester legacy precedence: true=force manual when precedence=-1, false=allow legacy/profile hints
input bool             InpRouterTesterClampProfileMin = true; // Tester safety: clamp profile-sourced min_score against manual
input double           InpRouterTesterClampMaxDelta   = 0.05; // Tester safety: max allowed profile overshoot above manual
input bool             InpRouterTesterAllowWideProfileMin = false; // Tester safety: allow profile min_score above manual + delta
input double           InpRouterTesterMinScoreOverride     = 0.0;  // Tester: effective router min score override when tester degraded mode is active; 0.0 is allowed explicitly

// Position management
input int              InpPMMode                = 2;     // Position Mgnt: PM Mode - 0=Off 1=Basic 2=Full
// Optional:
input bool             InpPMAllowDailyFlatten   = false; // Position Mgnt: Allow daily flatten (optional)
input int              InpPM_PostDDCooldownSec  = 0;     // Position Mgnt: Post-DD cooldown seconds (optional)

input bool             InpBE_Enable             = true;  // Position Mgnt: BE Enable
input double           InpBE_At_R               = 0.80;  // Position Mgnt: BE ATR
input double           InpBE_Lock_Pips          = 2.0;   // Position Mgnt: BE Lock pips

input TrailType        InpTrailType             = TRAIL_ATR;   // Position Mgnt: Trail Type - 0=None 1=Fixed 2=ATR 3=PSAR 4=ATRChannel 5=AUTO
input double           InpTrailPips             = 10.0;          // Position Mgnt: Trail Pips
input double           InpTrailATR_Mult         = 1.7;           // Position Mgnt: Trail ATR Mult

// ---- AUTO Trailing Regime Switch (ADX) ----
// Requires TRAIL_AUTO support inside PositionMgmt: ATR trail in trends, Fixed-pip trail in ranges.
input ENUM_TIMEFRAMES  InpTrailAuto_ADX_TF        = PERIOD_H1; // AUTO Trail: ADX timeframe
input int              InpTrailAuto_ADX_Period    = 14;        // AUTO Trail: ADX period
input double           InpTrailAuto_ADX_Min       = 25.0;      // AUTO Trail: ADX threshold (trend if >=)

input bool             InpPartial_Enable        = true;          // Position Mgnt: Partial TP Enable
input double           InpP1_At_R               = 1.50;           // Position Mgnt: Partial 1 TP ATR
input double           InpP1_ClosePct           = 50.0;          // Position Mgnt: Partial 1 Close Pct
input double           InpP2_At_R               = 3.00;           // Position Mgnt: Partial 2 TP ATR
input double           InpP2_ClosePct           = 25.0;          // Position Mgnt: Partial 2 Close Pct

// ================= Strategy family selector =================
// Strategy Mode:
// STRAT_MAIN_ONLY  => ONLY MainTradingLogic + the ICT/Wyckoff orderable specialists may send orders.
//                     Canonical MAIN_ONLY roster is defined in Config::FillCanonicalMainOnlyIds()
//                     and enforced by Config::IsStrategyAllowedInMode().
//                     All other modules/pack strategies remain confluence-only (no order sending).
// STRAT_PACK_ONLY  => Only non-core pack strategies may send orders.
// STRAT_COMBINED   => All strategies may send orders.
input StrategyMode InpStrat_Mode                = STRAT_MAIN_ONLY; // Strategy Mode: 0=Main, 1=Pack, 2=Combined

// ---- RouterEvaluateAll execution + caps ----
// 0 = best-of-all-symbols (current behavior)
// 1 = per-symbol execution (evaluate each symbol and send eligible entries per symbol)
input int InpRouterExecMode          = 0;  // Router exec mode: 0=best-of-all, 1=per-symbol

// ---- Router confluence-only pool (optional) ----
// When enabled, Router can blend "confluence-only pool" score into candidate ranking.
// This is used by Track 2 (pack strategies contribute confluence-only in MAIN_ONLY).
input bool   InpRouterUseConfluencePool = false; // Router: Use confluence-only pool in ranking
input double InpRouterPoolBlendW        = 0.0;   // Router: Pool blend weight (0..1)

// Position caps used by PositionMgmt/Router when "execute more than one" is enabled.
// Per-symbol: >=1 (1 preserves old behavior). Total: 0 = unlimited.
input int InpMaxPositionsPerSymbol   = 1;  // Max open/pending positions per symbol
input int InpMaxPositionsTotal       = 0;  // Max open/pending positions total (0=unlimited)

// Pack strategies runtime registration/trading (Option 2)
// Default OFF (confluence-only) unless explicitly enabled.
input bool InpEnable_PackStrategies          = false; // Allow pack strategies to register/trade in PACK_ONLY / COMBINED
input bool InpDisable_PackStrategies         = false; // Fail-safe hard disable pack strategies (overrides enable)
input bool   InpTester_MainOnlyAllowSelectedNonCoreOrderables = false; // Tester only: allow selected non-core StrategyID values to become orderable in MAIN_ONLY
input string InpTester_MainOnlySelectedNonCoreIds             = "";    // Tester only: CSV StrategyID list, example "20021,20024"

// Separate magic ranges (helps you segment PnL & mgmt)
input int MagicBase_Main               = 11000;
input int MagicBase_Pack               = 21000;
input int MagicBase_Combined           = 31000;

// Optional: trend vs mean umbrella (affects pack registry + router pick)
#ifndef TYPES_UMBRELLA_GUARD
   enum UmbrellaMode { UMB_ALL = 0, UMB_TREND = 1, UMB_MEAN = 2 };
#endif
input UmbrellaMode InpUmbrella         = UMB_ALL;

// --- Strategy enable toggles (per-strategy on/off) ---
input bool InpEnable_MainLogic            = true;
input bool InpEnable_ICT_SilverBullet     = true;
// --- Silver Bullet hard requirements (optional hard-gates) ---
input bool InpSB_Require_OTE          = false;  // SB: require OTE confluence
input bool InpSB_Require_VWAPStretch  = false;  // SB: require VWAP stretch condition

input bool InpEnable_ICT_PO3              = true; // Enable ICT Po3
input bool InpEnable_ICT_Continuation     = true; // Enable ICT Cont
input bool InpEnable_ICT_WyckoffTurn      = true; // Enable ICT Wyckoff Turn

// --- Per-strategy magic bases (unique magic ranges for bookkeeping/PnL) ---
input int  InpMagic_MainBase              = 11000;
input int  InpMagic_SilverBulletBase      = 12000;
input int  InpMagic_PO3Base               = 13000;
input int  InpMagic_ContinuationBase      = 14000;
input int  InpMagic_WyckoffTurnBase       = 15000;

// --- Per-strategy risk multipliers (position sizing bias per strat) ---
input double InpRiskMult_Main             = 0.50;
input double InpRiskMult_SilverBullet     = 0.60;
input double InpRiskMult_PO3              = 0.50;
input double InpRiskMult_Continuation     = 0.60;
input double InpRiskMult_WyckoffTurn      = 0.40;

// ================= Confluence Gate (base) =================
// ---- Main confluence gates
input int    InpConf_MinCount       = 0;       // Confluence Gate: Min Count
input double InpConf_MinScore       = 0.0;     // Confluence Gate: Min Score (tester-relaxed)
input bool   InpMain_SequentialGate = false;   // Confluence Gate: Seq Gate
input bool   InpMain_RequireChecklist = false; // Main: require checklist (disabled by default to reduce starvation)
input int    InpMain_ChecklistSoftFallbackMode = 0; // Main: checklist soft fallback policy (0=auto tester ON/live OFF, 1=force OFF, 2=force ON)
input bool   InpMain_RequireClassicalConfirm = false; // Main: require classical confirmation layer (optional hard requirement)

// --- Liquidity Pools (Lux-style, LuxAlgo Liquidity Pools) ---
input int    InpLiqPoolMinTouches      = 2;      // Liquidity Pools: min touches (cNum)
input int    InpLiqPoolGapBars         = 5;      // Liquidity Pools: bars between contacts (gapCount)
input int    InpLiqPoolConfirmWaitBars = 10;     // Liquidity Pools: confirmation bars (wait)
input double InpLiqPoolLevelEpsATR     = 0.10;   // Liquidity Pools: level EPS (fraction of ATR)
input int    InpLiqPoolMaxLookbackBars = 200;    // Liquidity Pools: max lookback bars
input double InpLiqPoolMinSweepATR     = 0.25;   // Liquidity Pools: min sweep size (fraction of ATR)

// ---- Extra confluences (only applied after main confirms)
input bool   InpExtra_VolumeFootprint = true;   // Confluence Gate: Vol Footprint
input double InpW_VolumeFootprint     = 0.20;   // Confluence Gate: Vol Footprint Weight

input bool   InpUseVWAPFilter       = true;     // Confluence Gate: VWAP
input bool   InpUseEMAFilter        = true;     // Confluence Gate: EMA
input bool   InpExtra_StochRSI      = true;     // Confluence Gate: Stoch RSI
input int    InpStochRSI_RSI_Period = 14;       // Confluence Gate: Stoch RSI Per
input int    InpStochRSI_K_Period   = 14;       // Confluence Gate: Stoch RSI K Per
input int    InpStochRSI_D_Period   = 3;        // Confluence Gate: Stoch RSI D Per
input double InpStochRSI_OB         = 80.0;     // Confluence Gate: Stoch RSI OB
input double InpStochRSI_OS         = 20.0;     // Confluence Gate: Stoch RSI OS
input double InpW_StochRSI          = 0.15;     // Confluence Gate: Stoch RSI Weight

input bool   InpExtra_MACD      = true;         // Confluence Gate: MACD
input int    InpMACD_Fast       = 12;           // Confluence Gate: MACD Fast
input int    InpMACD_Slow       = 26;           // Confluence Gate: MACD Slow
input int    InpMACD_Signal     = 9;            // Confluence Gate: MACD Signal
input double InpW_MACD          = 0.15;         // Confluence Gate: MACD Weight

input bool   InpExtra_ADXRegime = true;         // Confluence Gate: ADX
input int    InpADX_Period      = 14;           // Confluence Gate: ADX Per
input double InpADX_Min         = 18.0;         // Confluence Gate: ADX Min
input double InpADX_Upper       = 45.0;         // Confluence Gate: ADX Upper
input double InpW_ADXRegime     = 1.0;          // Confluence Gate: ADX Weight

input bool   InpExtra_Correlation = true;       // Confluence Gate: Correlation
input string InpCorr_RefSymbol    = "EURUSD";   // Confluence Gate: Correlation Sym
input ENUM_TIMEFRAMES InpCorr_TF  = PERIOD_H1;  // Confluence Gate: Correlation Timeframe
input int    InpCorr_Lookback     = 64;         // Confluence Gate: Correlation Lookback
input double InpCorr_MinAbs       = 0.60;       // Confluence Gate: Correlation Min ABS
input double InpCorr_MaxPen       = 0.20;       // Confluence Gate: Correlation Max Penalty
input double InpW_Correlation     = 0.10;       // Confluence Gate: Correlation Weight
input double InpW_CorrPen         = 1.0;        // Confluence Gate: Correlation Penalty Weight

input bool   InpExtra_DOMImbalance = true;     // Confluence Gate: DOM Imbalance (MarketBook)
input bool   InpExtra_News = true;              // Confluence Gate: News Filter
input double InpW_News     = 1.00;              // Confluence Gate: News Filter Weight

input bool   InpExtra_SilverBulletTZ = true;
input double InpW_SilverBulletTZ     = 0.06;

input bool   InpExtra_AMD_HTF        = true;
input double InpW_AMD_H1             = 0.06;
input double InpW_AMD_H4             = 0.08;

input bool   InpExtra_PO3_HTF       = true;
input double InpW_PO3_H1            = 0.05;
input double InpW_PO3_H4            = 0.07;

input bool   InpExtra_Wyckoff_Turn  = true;
input double InpW_Wyckoff_Turn      = 0.05;

input bool   InpExtra_MTF_Zones     = true;
input double InpW_MTFZone_H1        = 0.05;
input double InpW_MTFZone_H4        = 0.07;
input double Inp_MTFZone_MaxDistATR = 1.25;

// — Router/Confluence thresholds —
input bool   Inp_EnableHardGate            = false;  // Router/Confluence Threshold: Hard Gate
input double Inp_RouterFallbackMin         = 0.10;  // Router/Confluence Threshold: Fallback acceptance if normal gate rejects
input int    Inp_MinFeaturesMet            = 1;     // Router/Confluence Threshold: Min Feat. Met exclude NewsOK from count

// ================= Signal-Stack / Category Gating =================
// These inputs feed Config.mqh signal-stack settings.
// Use lower-case mode strings exactly as shown.
input bool   InpSigSel_Enable                 = true;   // Signal-stack: master enable
input string InpSigSel_Mode                   = "dynamic"; // Signal-stack: "fixed" or "dynamic"
input string InpSigSel_InstMode               = "anti_echo_subfamily"; // Institutional selection: "anti_echo_subfamily" or "direct_full"
input string InpSigSel_InstDegradeMode        = "proxy_substitute_then_stack_relax"; // Institutional degrade mode

input int    InpSigSel_FixedInstIndex         = 0;      // Fixed mode: Institutional candidate index
input int    InpSigSel_FixedTrendIndex        = 0;      // Fixed mode: Trend candidate index
input int    InpSigSel_FixedMomIndex          = 0;      // Fixed mode: Momentum candidate index
input int    InpSigSel_FixedVolIndex          = 0;      // Fixed mode: Volume candidate index
input int    InpSigSel_FixedVolaIndex         = 0;      // Fixed mode: Volatility candidate index

input double InpSigSel_ThInst                 = 1.0;    // Category pass threshold: direct Institutional |z|
input double InpSigSel_ThInstProxy            = 1.0;    // Category pass threshold: proxy Institutional |z|
input double InpSigSel_ThTrend                = 1.0;    // Category pass threshold: Trend |z|
input double InpSigSel_ThMom                  = 1.0;    // Category pass threshold: Momentum |z|
input double InpSigSel_ThVol                  = 1.0;    // Category pass threshold: Volume |z|
input double InpSigSel_ThVola                 = 1.0;    // Category pass threshold: Volatility regime pass

input double InpSigSel_BandRSI                = 5.0;    // DirMap band for RSI around 50
input double InpSigSel_BandStoch              = 5.0;    // DirMap band for StochRSI around 50
input double InpSigSel_ThADX                  = 20.0;   // DirMap threshold for ADX

input double InpSigSel_ATRMin                 = 0.0;    // RegimeMap ATR min
input double InpSigSel_ATRMax                 = 10000000000.0; // RegimeMap ATR max
input double InpSigSel_BBWidthMin             = 0.0;    // RegimeMap BB width min
input double InpSigSel_BBWidthMax             = 10000000000.0; // RegimeMap BB width max
input double InpSigSel_RVMin                  = 0.0;    // RegimeMap RV min
input double InpSigSel_RVMax                  = 10000000000.0; // RegimeMap RV max
input double InpSigSel_BVMin                  = 0.0;    // RegimeMap BV min
input double InpSigSel_BVMax                  = 10000000000.0; // RegimeMap BV max
input double InpSigSel_JumpMax                = 10000000000.0; // RegimeMap Jump max
input double InpSigSel_SigmaPMin              = 0.0;    // RegimeMap sigmaP min
input double InpSigSel_SigmaPMax              = 10000000000.0; // RegimeMap sigmaP max
input double InpSigSel_SigmaGKMin             = 0.0;    // RegimeMap sigmaGK min
input double InpSigSel_SigmaGKMax             = 10000000000.0; // RegimeMap sigmaGK max

input double InpSigSel_LocPivot               = 0.50;   // Location gate: PivotDist max
input double InpSigSel_LocSR                  = 0.50;   // Location gate: SRDist max
input double InpSigSel_LocFib                 = 0.50;   // Location gate: FibDist max
input double InpSigSel_LocSD                  = 0.0;    // Location gate: SDScore min
input double InpSigSel_LocOB                  = 0.0;    // Location gate: OBScore min
input double InpSigSel_LocFVG                 = 0.0;    // Location gate: FVGScore min
input double InpSigSel_LocSweep               = 0.0;    // Location gate: SweepScore min
input double InpSigSel_LocWyckoff             = 0.0;    // Location gate: Dir * WyckoffScore min

input int    InpSigSel_MinCategoryVotes       = 3;      // Signal-stack gate baseline before degrade relaxation
input int    InpSigSel_MinCategoryVotesFloor  = 2;      // Signal-stack gate minimum floor after relax
input int    InpSigSel_MinLocationVotes       = 2;      // Location gate: minimum location passes

input double InpSigSel_InstCoverageThreshold  = 0.50;   // InstCoverage below this means partial coverage

input double InpSigSel_W_OrderBook            = 1.0;    // Institutional anti-echo weight: OrderBook
input double InpSigSel_W_TradeFlow            = 1.0;    // Institutional anti-echo weight: TradeFlow
input double InpSigSel_W_Impact               = 1.0;    // Institutional anti-echo weight: Impact
input double InpSigSel_W_ExecQuality          = 1.0;    // Institutional anti-echo weight: ExecQuality

input double InpSigSel_W_ProxyMicropriceBias  = 1.0;    // Proxy Institutional weight: MicropriceBias
input double InpSigSel_W_ProxyAuctionBias     = 1.0;    // Proxy Institutional weight: AuctionBias
input double InpSigSel_W_ProxyComposite       = 1.0;    // Proxy Institutional weight: ProxyInstComposite

input string InpSigSel_InstWeightsCSV         = "";     // Institutional candidate weights; semicolon-separated
input string InpSigSel_TrendWeightsCSV        = "";     // Trend candidate weights; semicolon-separated
input string InpSigSel_MomWeightsCSV          = "";     // Momentum candidate weights; semicolon-separated
input string InpSigSel_VolWeightsCSV          = "";     // Volume candidate weights; semicolon-separated
input string InpSigSel_VolaWeightsCSV         = "";     // Volatility candidate weights; semicolon-separated

// Hard-gate recipe: Trend + ADX + (Struct || Candle || OB_Prox)
input bool   Inp_RequireTrendFilter        = false; // Market Structure: Required Trend Filter 
input bool   Inp_RequireADXRegime         = false; // Market Structure: Required ADX Reg
input bool   Inp_RequireStructOrPatternOB = false; // Market Structure: Required Struct Pattern OB

// — London policy —
input bool   Inp_LondonLiquidityPolicy     = false; // London Policy:
input string Inp_LondonStartLocal          = "06:30"; // London Policy: Start Time Local
input string Inp_LondonEndLocal            = "10:00"; // London Policy: End Time Local

// — Data reliability / fallbacks —
input bool   Inp_UseATRasDeltaProxy        = true;   // Data Rel: Use ATR as Delta Proxy
input double Inp_ATR_VolRegimeFloor        = 0.0008; // Data Rel: Symbol-scale aware (ATR Vol Reg Floor)
input int    InpATR_Period_Delta           = 14;     // Data Rel: ATR Period used for ATR-as-delta proxy (not TP/SL)

// Structure / OB tuning
input int    Inp_Struct_ZigZagDepth        = 8;      // Struct/OB Tuning: ZigZag Depth
input int    Inp_Struct_HTF_Multiplier     = 4;      // Struct/OB Tuning: HTF Mult e.g., M15 -> look at M60
input double Inp_OB_ProxMaxPips            = 20.0;   // Struct/OB Tuning: OB Prox Max Pips

// — Risk: ATR-based SL/TP —
input bool   Inp_Use_ATR_StopsTargets      = true;   // Risk ATR Based: Use ATR SL Targets
input double Inp_ATR_TP_Mult               = 1.80;   // Risk ATR Based: ATR TP Mult nudges R>1
input double Inp_RiskPerTradePct           = 0.5;    // Risk ATR Based: Risk/Trade Pct

// — Logging/Veto diagnostics —
input bool   Inp_LogVetoDetails            = true;   // Log Veto Details

// Toggle each confluence
input bool InpCF_InstZones             = true; // Institutional Demand/Supply zones (StructureSDOB)
input bool InpCF_OrderFlowDelta        = true; // Positive/Negative volume delta (DeltaProxy)
input double InpMain_OrderFlowThreshold = 0.60; // Main: orderflow confidence threshold (0..1). 0.80 is too strict for most FX feeds.
input bool InpCF_OrderBlockNear        = true; // OB near SD zone
input bool InpCF_CndlPattern           = true; // Candlestick patterns
input bool InpCF_ChartPattern          = true; // Chart patterns
input bool InpCF_MarketStructure       = true; // Market Struct: HH/HL/LH/LL bias, pivots
input bool InpCF_TrendRegime           = true; // Trend Regime (trend vs mean) + ADX strength
input bool InpCF_StochRSI              = true; // Stoch RSI OB/OS confirmation
input bool InpCF_MACD                  = true; // MACD crosses/confirmation
input bool InpCF_Correlation           = false; // Cross-pair confirmation
input bool InpCF_News                  = true; // News calendar filter (soft/pass as confluence)

// ===== Autochartist-style internal scanner =====
input bool   InpAuto_Enable             = true; // Auto: master enable
input int    InpAuto_ScanIntervalSec    = 60;    // Auto: rescan cadence (sec)
input int    InpAuto_ScanLookbackBars   = 320;   // Auto: lookback bars

input bool   InpCF_AutoChart            = true; // Auto: chart patterns confluence
input bool   InpCF_AutoFib              = true; // Auto: harmonic/fib confluence
input bool   InpCF_AutoKeyLevels        = true; // Auto: key levels confluence
input bool   InpCF_AutoVolatility       = true; // Auto: volatility/range confluence

input double InpW_AutoChart             = 0.70;
input double InpW_AutoFib               = 0.65;
input double InpW_AutoKeyLevels         = 0.55;
input double InpW_AutoVolatility        = 0.40;

input double InpAuto_Chart_MinQuality   = 0.60;
input int    InpAuto_Chart_PivotL       = 3;
input int    InpAuto_Chart_PivotR       = 3;

input double InpAuto_Fib_MinQuality     = 0.60;

input int    InpAuto_Key_MinTouches     = 3;
input double InpAuto_Key_ClusterATR     = 0.18;
input double InpAuto_Key_ApproachATR    = 0.25;

input int    InpAuto_Vol_LookbackDays   = 180;
input int    InpAuto_Vol_HorizonMin     = 60;
input double InpAuto_Vol_MinRangeATR    = 0.90;

// --- AutoVol cache (MarketData 5.6) ---
// Cached volatility analytics built once per day (24) or per N hours (any other value).
input int InpAutoVol_CacheHours       = 24; // 24 = daily aligned to closed D1; otherwise N-hour cadence
input int InpAutoVol_ADRLookbackDays  = 20; // ADR range distribution lookback (days)
input int InpAutoVol_RetLookbackD1    = 60; // D1 return sigma lookback (bars)

input bool   InpAuto_RiskScale_Enable   = true;
input double InpAuto_RiskScale_Floor    = 0.70;
input double InpAuto_RiskScale_Cap      = 1.20;

// Optional per-confluence weights (1.0 default)
input double InpW_InstZones            = 1.25;
input double InpW_OrderFlowDelta       = 1.20;
input double InpW_OrderBlockNear       = 1.0;
input double InpW_CndlPattern          = 0.6;
input double InpW_ChartPattern         = 0.8;
input double InpW_MarketStructure      = 1.20;
input double InpW_TrendRegime          = 1.0;

// ===== Extra confluences (only after Main Trading Strategy confirms) =====
input bool   InpCF_Extra_Enable        = true; // Exta Confluences: Enable extra confluences only if main logic confirmed
input int    InpExtra_MinScore         = 0;    // Extra Confluences: Min Needed before entry
input double InpExtra_MinGateScore     = 0.10; // Extra Confluences: Min Score gate before entry

// ---- Extras toggles + weights (used ONLY after main logic confirms) ----
input bool   InpCF_Liquidity           = true;  // Extra: Liquidity Pools
input double InpW_Liquidity            = 0.10;   // Extra weight

input bool   InpCF_VSAIncrease         = true;  // Extra: VSA
input double InpW_VSAIncrease          = 0.10;   // Extra weight

// MACD parameters
input int    InpMACD_FastEMA           = 12; // MACD: Fast EMA
input int    InpMACD_SlowEMA           = 26; // MACD: Slow EMA

// News hard-block window & surprise scaling
input bool             InpNewsOn                = false;  // News: Enable
input int              InpNewsBlockPreMins      = 5;     // News: Block PreMins
input int              InpNewsBlockPostMins     = 5;     // News: Block PostMins
input int              InpNewsImpactMask        = 6;     // News: Impact Mask
input int              InpNewsBackendMode       = 1;     // 0=DISABLED, 1=BROKER, 2=CSV
input bool             InpNewsMVP_NoBlock       = false; // if true: never hard-block trades (even if news_on)
input bool             InpNewsFailoverToCSV     = true;  // if broker calendar fails, try CSV
input bool             InpNewsNeutralOnNoData   = true;  // if no data, treat as not blocked (recommended)

// Calendar surprise thresholds (scale/skip)
input int              InpCal_LookbackMins      = 90;    // Calendar Thresholds: Lookback Mins
input double           InpCal_HardSkip          = 2.0;   // Calendar Thresholds: Hard Skip
input double           InpCal_SoftKnee          = 0.6;   // Calendar Thresholds: Soft Knee
input double           InpCal_MinScale          = 0.6;   // Calendar Thresholds: Min Scale

// ATR & quantile TP / SL
input int              InpATR_Period            = 10;    // ATR & Quantile TP/SL: Period
input double           InpTP_Quantile           = 0.6;   // ATR & Quantile TP/SL: TP Quantile
input double           InpTP_MinR_Floor         = 1.40;  // ATR & Quantile TP/SL: TP MinR Floor
input double           InpATR_SlMult            = 1.70;  // ATR & Quantile TP/SL: ATR SL Mult

// Feature toggles
input bool             InpVSA_Enable            = true;  // Feature: VSA Enable
input double           InpVSA_PenaltyMax        = 0.25;  // Feature: VSA Max Penalty
input bool             InpVSA_AllowTickVolume   = true;  // VSA: allow tick volume fallback (FX-friendly)
input bool             InpStructure_Enable      = true;  // Feature: Structure Enable
input bool             InpStructVetoOn          = false; // Feature: Hard Structure Veto
input bool             InpLiquidity_Enable      = true;  // Feature: Liquidity Enable
input bool             InpCorrSoftVeto_Enable   = false;  // Feature: Corr Soft Veto Enable

// Confluence thresholds (VWAP + patterns)
input double           InpVWAP_Z_Edge           = 1.25;  // Confluence Thresholds: VWAP Z Edge
input double           InpVWAP_Z_AvoidTrend     = 1.5;   // Confluence Thresholds: VWAP Z Avoid Trend
input int              InpPattern_Lookback      = 120;    // Confluence Thresholds: Pattern Lookback
input double           InpPattern_Tau           = 8.0;   // Confluence Thresholds: Pattern Tau

// VWAP engine params
input int              InpVWAP_Lookback         = 60;    // VWAP Engine: Lookback
input double           InpVWAP_Sigma            = 3.0;   // VWAP Engine: Sigma

// --------- Carry (bias only; no standalone entries) ----------
input bool             InpCarry_Enable          = true;   // Carry: Enable use carry to nudge scores & scale risk
input bool             InpCarry_StrictRiskOnly  = true;   // Carry: STRICT RISK: RiskMod01 only (never boosts)
input double           InpCarry_BoostMax        = 0.06;   // Carry: Boost Max - 0..0.12 typical
input double           InpCarry_RiskSpan        = 0.25;   // Carry: Risk Span ±25% risk scaling around 1.0 (LEGACY mild)

// --------- Confluence Blend Weights (dynamic, no recompile) ----------
input double           InpConflBlend_Trend      = 0.10;   // Confluence Blend Weights: Trends - 0..0.50
input double           InpConflBlend_MR         = 0.25;   // Confluence Blend Weights: MR - 0..0.50
input double           InpConflBlend_Others     = 0.20;   // Confluence Blend Weights: Others - 0..0.50 (optional)

// Strategy toggles
input bool             InpEnableTrend           = true;
input bool             InpEnableTrendBOS        = true;
input bool             InpEnableMR              = true;
input bool             InpEnableMRRange         = true;
input bool             InpEnableSqueeze         = true;
input bool             InpEnableORB             = true;
input bool             InpEnableSweepCHOCH      = true;
input bool             InpEnableVSAClimaxFade   = true;
input bool             InpEnableCorrDiv         = true;
input bool             InpEnablePairsLite       = true;
input bool             InpEnableNewsDeviation   = false;
input bool             InpEnableNewsPostFade    = true;

// Weights (manual overrides — can be superseded by Profile if desired)
input double           InpW_Trend               = 0.95;
input double           InpW_TrendBOS            = 0.95;
input double           InpW_MR                  = 1.10;
input double           InpW_MRRange             = 1.10;
input double           InpW_Squeeze             = 1.0;
input double           InpW_ORB                 = 0.8;
input double           InpW_SweepCHOCH          = 0.9;
input double           InpW_VSAClimaxFade       = 0.85;
input double           InpW_CorrDiv             = 0.8;
input double           InpW_PairsLite           = 0.8;
input double           InpW_NewsDeviation       = 0.5;
input double           InpW_NewsPostFade        = 0.5;

// Throttles (sec) (manual overrides — can be superseded by Profile)
input int              InpThrottle_Trend_Sec        = 0;
input int              InpThrottle_TrendBOS_Sec     = 0;
input int              InpThrottle_MR_Sec           = 0;
input int              InpThrottle_MRRange_Sec      = 0;
input int              InpThrottle_Sq_Sec           = 180;
input int              InpThrottle_ORB_Sec          = 900;
input int              InpThrottle_SweepCHOCH_Sec   = 600;
input int              InpThrottle_VSAClimaxFade_Sec= 600;
input int              InpThrottle_CorrDiv_Sec      = 600;
input int              InpThrottle_PairsLite_Sec    = 600;
input int              InpThrottle_NewsDev_Sec      = 0;
input int              InpThrottle_NewsPost_Sec     = 900;

// Policy cooldown
input int              InpTradeCooldown_Sec     = 900; // Policy Cooldown

// Routing choice
input bool             InpUseRegistryRouting         = false; // Legacy registry routing gate
input bool             InpLegacyProcessSymbolTester  = false; // Tester only: explicit legacy ProcessSymbol compatibility mode
input bool             InpTester_DirectRegistryCompat = false; // Tester only: explicit direct StrategyRegistry compatibility gate for deprecated helper paths
input double           InpRegimeThreshold            = 0.55;  // Regime Threshold

// --------- Profiles (top-level presets) ----------
input TradingProfile   InpProfileType           = PROF_TREND; // Profile Type: Balanced/Trend/MR/Scalp
input bool             InpProfileApply          = true;   // Profile Type Apply: apply profile weights/throttles + carry + confluence defaults
input bool             InpProfileAllowManual    = true;   // Profile allow manual inputs to override after profile
input bool             InpProfileUseRouterHints = true;   // Legacy fallback only: router threshold precedence now uses InpRouterThresholdPrecedence
input bool             InpProfileSaveCSV        = false;  // Profile: save profile CSV to Files/
input string           InpProfileCSVName        = "";     // Profile: optional filename stem

// --------- ML Blender ----------
input bool             InpML_Enable             = false; // ML Enable
input double           InpML_Temperature        = 1.00; // ML Temperature
input double           InpML_Threshold          = 0.55; // ML Threshold
input double           InpML_Weight             = 0.25; // ML Weight
input bool             InpML_Conformal          = true; // ML Conformal
input bool             InpML_Dampen             = true; // ML Dampen
input string           InpML_ModelFile          = "CAEA_MLModel.ini"; // ML Model File
input string           InpML_DatasetFile        = "CAEA_MLDataset.csv"; // ML Dataset File
input bool             InpML_UseCommonFiles     = true; // ML Use Common Files

input bool             InpML_AutoCalibrate      = true; // ML Auto Calibrate
input int              InpML_ModelMaxAgeHours   = 168; // ML Max Age Hours (e.g., 7 days)
input int              InpML_MinSamplesTrain    = 300; // ML Min Samples Train
input int              InpML_MinSamplesTest     = 120; // ML Min Sample Test
input double           InpML_MinOOS_AUC         = 0.55; // ML Min OOS AUX
input double           InpML_MinOOS_Acc         = 0.52; // ML Min OOS Acc

input int              InpML_LabelHorizonBars   = 6; // ML Label Horizon Bars
input double           InpML_LabelATRMult       = 0.25; // ML Label ATR Mult (or points threshold if you prefer)
input bool             InpML_TrainOnTesterEnd   = true; // ML Train at end of tester
input int              InpML_BackfillBars       = 0; // ML Backfill bars (0=off)
input int              InpML_BackfillStep       = 3; // ML Backfill step (e.g., every 3 bars)

input bool             InpML_ExternalEnable     = false; // ML External Enable
input int              InpML_ExternalMode       = 1; // ML External Mode: 1=file, 2=socket
input string           InpML_ExternalFile       = "CAEA_ext_signal.csv"; // ML External File
input int              InpML_ExternalPollMs     = 500; // ML External Poll Ms
input string           InpML_ExternalSocketHost = "127.0.0.1"; // ML External Socket Host
input int              InpML_ExternalSocketPort = 5555; // ML External Socket Port
input int              InpML_ExternalMaxAgeSec  = 10;   // ML External Max Age Sec
input double           InpML_LabelMinPoints     = 0.0;  // ML Label Min Points (0 = off)

input bool             InpML_OutcomeCapture     = true;
input string           InpML_OutcomeFile        = "";
input bool             InpML_PeriodicRetrain    = false;
input int              InpML_RetrainMinIntervalMin = 0;
input int              InpML_RetrainMinNewRows  = 0;
input bool             InpML_RetrainOnlyTester  = true;

// ---- ML SL/TP multipliers (explicit; off by default) ----
input bool             InpML_SLTP_Enable = false;  // ML SL/TP multiplier enable
input double           InpML_SLMult_Min  = 0.80;   // ML min SL multiplier
input double           InpML_SLMult_Max  = 1.20;   // ML max SL multiplier
input double           InpML_TPMult_Min  = 0.80;   // ML min TP multiplier
input double           InpML_TPMult_Max  = 1.30;   // ML max TP multiplier

// --------- Review/Screenshots ----------
input bool             InpReviewScreenshots     = false; // Review/Screenshots: Enable
input int              InpReviewSS_W            = 1280; // Review/Screenshots: SS_W
input int              InpReviewSS_H            = 720; // Review/Screenshots: SS_H

// --------- Indicator Benchmark (optional) ----------
input bool             InpBenchIndicators       = false; // Benchmark Indicator on init
input int              InpBenchWarmup           = 5;     // Benchmark Warmpup
input int              InpBenchLoops            = 200;   // Benchmark Loops
input int              InpBenchATR_Period       = 14;    // Benchmark ATR Period

// --------- Regression Batch / Golden Runs ----------
input bool             InpReg_Enable            = false;          // Regression Enable KPI export & compare
input string           InpReg_BatchTag          = "default";      // Regression logical batch name (e.g., "FXCore_v1")
input string           InpReg_KPIsFile          = "CAEA_KPIs.csv";// Regression export path (Files/)
input bool             InpReg_SaveWF            = true;           // Regression save slice PF table
input bool             InpReg_SaveEquity        = true;           // Regression save equity curve
input bool             InpReg_SaveAsGolden      = false;          // Regression overwrite golden file with this run
input bool             InpReg_Compare           = false;          // Regression compare against golden
input string           InpReg_GoldenFile        = "CAEA_KPIs_GOLDEN.csv"; // Regression frozen reference KPIs
input double           InpReg_TolerancePct      = 5.0;            // Regression % drift tolerated per KPI
input string           InpReg_ExtraNote         = "";             // Regression optional note to embed

// Diagnostics / UX
input bool             InpRouterDebugLog        = false; // Diagnostics / UX: Debug Log
input int              InpRouterTopKLog         = 6; // Diagnostics / UX: Top K Log
input bool             InpRouterForceOneNormalVol = false; // Diagnostics / UX: Force One Normal Vol
input bool             InpDebug                 = true; // Diagnostics / UX: Debug
input bool             InpFileLog               = false; // Diagnostics / UX: File Log
input bool             InpDriftAlarm            = true; // Diagnostics / UX: Drift Alarm
input bool             InpDriftHaltTrading      = false; // Diagnostics / UX: Halt trading on drift alarm
input bool             InpProfile               = false; // Diagnostics / UX: Profile

// Warmup gate control (tester-safe, prevents permanent stall)
input bool             InpWarmupGate            = true;    // Gate trading until warmup is ready
input int              InpWarmupSoftLatchMs     = 5000;    // Tester: latch open after N ms
input int              InpWarmupSoftLatchTicks  = 250;     // Tester: latch open after N ticks

// Institutional state bar freshness policy
input bool             InpInstStateStrictBarAlign = true;   // live: strict current/open-bar contract
input bool             InpInstStateAllowOneBarLag = false;  // live override: allow one closed-bar lag

// Execution failure visibility (Journal)
input bool             InpExecFailJournal       = true;    // Print execution failures to Journal
input int              InpExecFailThrottleSec   = 60;      // Throttle journal spam (seconds)

// ——— DebugChecklist switches (safe to leave OFF in production)
input bool             InpDebugChecklistOn      = false;   // Debug: master switch
input bool             InpDebugChecklistOverlay = true;    // Debug: draw rectangles/labels on chart
input bool             InpDebugChecklistCSV     = false;   // Debug: write CSV to MQL5/Files
input bool             InpDebugChecklistDryRun  = false;   // Debug: print DRYRUN entries, no orders
input double           InpDbgChkMinScore        = 0.55;    // Debug: testing threshold for “all_ok”
input double           InpDbgChkZoneProxATR     = 0.35;    // Debug: zone proximity (ATR multiples)
input double           InpDbgChkOBProxATR       = 0.30;    // Debug: order-block proximity (ATR multiples)

// --------- Microstructure runtime gates ----------
input bool             InpMS_EnableRuntimeGate = true;   // backend-only: enable OFI/OBI/VPIN/resil gates
input double           InpMS_MinOFIAbs         = 0.10;   // minimum |OFI| required
input double           InpMS_MinOBIAbs         = 0.10;   // minimum |OBI| required
input double           InpMS_MaxVPIN           = 0.65;   // block when VPIN is above this
input double           InpMS_MinResiliency     = 0.35;   // block when resiliency is below this
input int              InpMS_RefreshMinMs      = 250;    // local throttle for EA-side refresh helper

input int              InpMS_MaxSnapshotAgeMs   = 1250;   // block if last published micro snapshot is stale
input bool             InpMS_BlockIfUnavailable = true;   // block entries when no fresh micro snapshot exists
input bool             InpMS_TesterAllowUnavailable = true;   // canonical tester degraded institutional fallback when canonical micro transport is unavailable
input bool             InpMS_TesterLogUnavailable   = true;   // tester/optimization: print one throttled fallback diagnostic
input bool             InpMS_LiveAllowDegradedInstFallback = false; // live: optional degraded fallback when canonical micro is unavailable (default OFF)

enum TesterDegradedScorePolicyType
  {
   TESTER_DEGRADED_SCORE_POLICY_RELAX_MIN_SCORE = 0,
   TESTER_DEGRADED_SCORE_POLICY_ADD_SCORE       = 1
  };

enum TesterDegradedScorePolicyMode
{
   TESTER_DEGRADED_SCORE_POLICY_AUTO = 0,
   TESTER_DEGRADED_SCORE_POLICY_FORCE_OFF = 1,
   TESTER_DEGRADED_SCORE_POLICY_FORCE_ON = 2
};

input bool                           InpMS_TesterDegradedScorePolicyEnable = false;
input TesterDegradedScorePolicyMode  InpMS_TesterDegradedScorePolicyMode = TESTER_DEGRADED_SCORE_POLICY_AUTO;
input TesterDegradedScorePolicyType  InpMS_TesterDegradedScorePolicyType = TESTER_DEGRADED_SCORE_POLICY_RELAX_MIN_SCORE;
input double                         InpMS_TesterDegradedScorePolicyMagnitude = 0.04;

enum TesterRouterGateMode
{
   TESTER_ROUTER_GATE_MODE_AUTO = 0,                 // backward-compatible: maps to legacy bypass bool
   TESTER_ROUTER_GATE_MODE_STRICT = 1,               // full strict tester gating
   TESTER_ROUTER_GATE_MODE_SOFT_MICRO_FRESHNESS = 2, // keep core policy checks; soften freshness-only micro failures
   TESTER_ROUTER_GATE_MODE_BYPASS = 3                // full bypass (legacy tester behavior)
};

input TesterRouterGateMode InpTester_RouterGateMode = TESTER_ROUTER_GATE_MODE_AUTO;

input bool                           InpTester_BypassPolicyGates         = true;  // Tester: bypass news/regime/liquidity hard gates in degraded tester mode

// Reserved thresholds for downstream State/RiskEngine/Execution passes.
// Keep them here now so the EA owns the policy knobs, but do NOT consume them
// in this file until MarketData/Types/State expose the canonical fields.
input double           InpMS_MaxImpactBeta01    = 0.85;   // reserved
input double           InpMS_MaxImpactLambda01  = 0.85;   // reserved
input double           InpMS_MinAbsorption01    = 0.25;   // reserved
input double           InpMS_MinObservability01 = 0.30;   // reserved
input double           InpMS_MinDarkPoolConf01  = 0.20;   // reserved

// --------- Tester / Optimization ----------
enum TesterScoreMode { TESTER_SCORE_MIX=0, TESTER_SCORE_SHARPE=1, TESTER_SCORE_EXPECT=2 }; // Tester / Optimization: Score
input TesterScoreMode InpTesterScore  = TESTER_SCORE_MIX; // Tester / Optimization: Score Mode
input bool            InpTesterSnapshot = true; // Tester / Optimization: Snapshot
input bool            InpTester_DisableNewsAndCorrelation = true; // Tester / Optimization: disable news/correlation runtime overrides
input string          InpTesterNote     = ""; // Tester / Optimization: Note
input string          InpTestCase      = "none";  // see TesterCases::ScenarioList()
input string          InpTesterPreset  = "";
input bool            InpLooseMode                  = false; // Runtime override: relaxed gating mode
input bool            InpDisableMicrostructureGates = false; // Runtime override: bypass microstructure gate
input bool            InpAllowDirectExec            = true;  // Tester: allow StrategyDirectExec startup bypass

bool SR_Input_TesterMainOnlyAllowSelectedNonCoreOrderables()
{
   return InpTester_MainOnlyAllowSelectedNonCoreOrderables;
}

string SR_Input_TesterMainOnlySelectedNonCoreIds()
{
   return InpTester_MainOnlySelectedNonCoreIds;
}

// ================== Globals ==================
// g_cfg = canonical runtime snapshot
// S     = finalized runtime mirror retained for legacy read paths
// After FinalizeRuntimeSettings(), S must be treated as read-only in backend-only mode.
Settings S;

static bool g_show_breakdown = true;
static bool g_calm_mode      = false;
static bool g_ml_on          = false;
static bool g_is_tester      = false;   // true only in Strategy Tester / Optimization
static bool g_use_registry = false; // explicit tester-only legacy ProcessSymbol compatibility mode

bool        g_sr_direct_registry_compat_runtime = false;
static bool gTesterLooseGateMode = false;
static bool gDisableMicrostructureGatesRuntime = false;

bool EA_LooseModeActive()
{
   return gTesterLooseGateMode;
}

bool EA_MicrostructureGateDisabled()
{
   if(gDisableMicrostructureGatesRuntime)
      return true;

   return false;
}

bool EA_EffectiveEnforceKillzone()
{
   if(EA_LooseModeActive())
      return false;

   return InpEnforceKillzone;
}

bool EA_EffectiveNewsOn()
{
   if(EA_LooseModeActive())
      return false;

   return InpNewsOn;
}

bool EA_EffectiveCFCorrelation()
{
   if(EA_LooseModeActive())
      return false;

   return InpCF_Correlation;
}

bool EA_EffectiveExtraCorrelation()
{
   if(EA_LooseModeActive())
      return false;

   return InpExtra_Correlation;
}

// ---- Router threshold resolution telemetry/state ----
static bool   g_router_resolve_logged       = false;
static double g_router_last_manual_min      = -1.0;
static double g_router_last_profile_min     = -1.0;
static double g_router_last_requested_min   = -1.0;
static double g_router_last_resolved_min    = -1.0;
static int    g_router_last_manual_cap      = -1;
static int    g_router_last_profile_cap     = -1;
static int    g_router_last_resolved_cap    = -1;
static string g_router_last_source          = "";
static string g_router_last_policy          = "";
static bool   g_router_last_tester_clamped  = false;
static int    g_router_last_profile_type    = -1;

// ---- Runtime drift alarm (S must match g_cfg; S is read-only after finalize in backend-only mode) ----
static bool     g_drift_armed          = false;   // set true after finalize/approved commit
static datetime g_drift_last_check     = 0;       // throttle checks (seconds)
static datetime g_drift_last_alert     = 0;       // throttle alerts (seconds)
static int      g_drift_alert_count    = 0;       // counts alerts since last approved commit
static string   g_drift_hash_approved  = "";      // hash of last approved S (Finalize/UI commit)
static string   g_drift_hash_last_s    = "";      // last reported mismatch S hash
static string   g_drift_hash_last_cfg  = "";      // last reported mismatch g_cfg hash
// Optional hard stop when drift is detected (blocks NEW entries; PM can still manage)
static bool g_inhibit_trading = false;

// Multi-symbol scheduler
string   g_symbols[];              // parsed watchlist
int      g_symCount = 0;
static datetime g_lastBarTime[];   // per-symbol last closed-bar time on entry TF
static datetime g_decision_tel_timer_skip_bar[];
static int      g_decision_tel_timer_skip_tf[];
static datetime g_decision_tel_timer_skip_latch[];
static bool     g_decision_tel_timer_skip_emitted[];
static bool     g_dom_book_owned[];

// ================== MarketScannerHub: event-driven routing trigger ==================
#define MSH_DIRTY_MAX 64

static int      g_msh_dirty_n = 0;
static string   g_msh_dirty_sym[MSH_DIRTY_MAX];
static int      g_msh_dirty_tf[MSH_DIRTY_MAX];
static datetime g_msh_dirty_ts[MSH_DIRTY_MAX];
static int      g_msh_idle_heartbeat_streak = 0; // consecutive timer heartbeats with no dirty symbols
static int      g_msh_idle_fallback_after_n = 3; // throttled canonical fallback cadence
static datetime g_msh_last_forced_router_eval_ts = 0;
static int      g_msh_eval_dirty_trigger_n = 0;
static int      g_msh_eval_cadence_trigger_n = 0;

// ================== Backend-only microstructure cache ==================
// Requires MicrostructureStats in Types.mqh
MicrostructureStats g_ms_last;
static datetime     g_ms_last_refresh = 0;
static string       g_ms_last_symbol  = "";
static bool         g_ms_last_ok      = false;
static bool         g_ms_gate_pass    = true;

struct EAInstTransportStamp
{
   double observability01;
   double truth_tier01;
   double venue_scope01;
   bool   direct_micro_available;
   bool   proxy_micro_available;
   int    inst_flow_bundle_freshness_code;
};

static EAInstTransportStamp g_inst_transport;

void MSH_DirtyClear()
{
   g_msh_dirty_n = 0;
}

bool MSH_DirtyHasSym(const string sym)
{
   for(int i=0;i<g_msh_dirty_n;i++)
      if(g_msh_dirty_sym[i] == sym)
         return true;
   return false;
}

void MSH_DirtyTouch(const string sym, const int tf, const datetime ts)
{
   if(sym == "") return;

   // De-dup by symbol (router evaluates watchlist; tf is informational)
   for(int i=0;i<g_msh_dirty_n;i++)
   {
      if(g_msh_dirty_sym[i] == sym)
      {
         g_msh_dirty_tf[i] = tf;
         g_msh_dirty_ts[i] = ts;
         return;
      }
   }

   // If full: evict oldest (small N, linear is fine)
   if(g_msh_dirty_n >= MSH_DIRTY_MAX)
   {
      int oldest = 0;
      datetime ots = g_msh_dirty_ts[0];
      for(int k=1;k<g_msh_dirty_n;k++)
      {
         if(g_msh_dirty_ts[k] < ots)
         {
            ots = g_msh_dirty_ts[k];
            oldest = k;
         }
      }
      g_msh_dirty_sym[oldest] = sym;
      g_msh_dirty_tf[oldest]  = tf;
      g_msh_dirty_ts[oldest]  = ts;
      return;
   }

   g_msh_dirty_sym[g_msh_dirty_n] = sym;
   g_msh_dirty_tf[g_msh_dirty_n]  = tf;
   g_msh_dirty_ts[g_msh_dirty_n]  = ts;
   g_msh_dirty_n++;
}

// Called from MarketScannerHub.mqh RouteEvent(...) via MARKETSCANNERHUB_CUSTOM_ROUTE
void MSH_RouteEvent(const Scan::ScanEvent &e)
{
   // Scan::ScanEvent fields (confirmed from MarketScannerHub.mqh RouteEventDefault):
   // e.sym, e.tf, e.ts, ...
   MSH_DirtyTouch(e.sym, (int)e.tf, e.ts);

   // IMPORTANT:
   // MarketScannerHub / Scan remain the upstream scan owners.
   // Do NOT publish microstructure or trigger routing directly from this callback.
   // Canonical new-order routing ownership is OnTimer() only:
   // OnTimer() -> MSH::HubTimerTick() -> RefreshRuntimeContextFromHub() -> RunCachedRouterPass().
   // OnTick() may consume cached state for management, telemetry, and diagnostics only.
}

// Price/time gates state
static bool   g_armed_by_price     = false;
static bool   g_stopped_by_price   = false;
static double g_last_mid_arm       = 0.0;
static double g_last_mid_stop      = 0.0;

// streak state (reset daily by Risk day cache or session start)
static int    g_consec_wins        = 0;
static int    g_consec_losses      = 0;

struct DecisionTelemetryState
{
   bool      has_decision_ts;
   datetime  decision_ts;
   string    decision_source;
   string    status;
   string    last_drop_reason;

   bool      has_ict_score;
   double    ict_score;

   bool      has_classical_score;
   double    classical_score;

   bool      has_armed_name;
   string    armed_name;

   int       pick_id;
   int       pick_dir;
   double    pick_score;
};

static DecisionTelemetryState g_decision_tel;

struct TesterDegradedFallbackRuntimeState
{
   bool      known;
   datetime  ts;
   string    sym;
   bool      active;
   string    status;
   string    detail;
};

static TesterDegradedFallbackRuntimeState g_tester_fb_runtime;

void PublishTesterDegradedFallbackRuntimeState(const string sym,
                                               const bool active,
                                               const string status,
                                               const string detail)
{
   g_tester_fb_runtime.known  = true;
   g_tester_fb_runtime.ts     = TimeCurrent();
   g_tester_fb_runtime.sym    = sym;
   g_tester_fb_runtime.active = active;
   g_tester_fb_runtime.status = status;
   g_tester_fb_runtime.detail = detail;
}

bool GetTesterDegradedFallbackRuntimeState(const string sym,
                                          bool &active,
                                          string &status,
                                          string &detail)
{
   active = false;
   status = "off";
   detail = "";

   if(!g_tester_fb_runtime.known)
      return false;

   if(sym != "" &&
      g_tester_fb_runtime.sym != "" &&
      g_tester_fb_runtime.sym != sym)
      return false;

   active = g_tester_fb_runtime.active;
   status = g_tester_fb_runtime.status;
   detail = g_tester_fb_runtime.detail;
   return true;
}

string RuntimeTesterDegradedScorePolicyTypeName(const int policy_type)
{
   if(policy_type == (int)TESTER_DEGRADED_SCORE_POLICY_ADD_SCORE)
      return "add_score";

   return "relax_min_score";
}

string RuntimeTesterDegradedScorePolicyModeName(const int mode)
{
   if(mode == TESTER_DEGRADED_SCORE_POLICY_FORCE_OFF) return "force_off";
   if(mode == TESTER_DEGRADED_SCORE_POLICY_FORCE_ON)  return "force_on";
   return "auto";
}

bool RuntimeTesterDegradedScorePolicySnapshot(const string sym,
                                              bool &active,
                                              string &policy_type,
                                              double &magnitude)
{
   active = false;
   policy_type = "off";
   magnitude = 0.0;

   const bool tester_runtime =
      ((bool)MQLInfoInteger(MQL_TESTER) ||
       (bool)MQLInfoInteger(MQL_OPTIMIZATION) ||
       (bool)MQLInfoInteger(MQL_VISUAL_MODE));

   if(!tester_runtime)
      return false;

   bool fallback_active = false;
   string fallback_reason = "";
   string fallback_status = "off";
   string fallback_detail = "";
   
   if(!GetTesterDegradedFallbackRuntimeState(sym, fallback_active, fallback_status, fallback_detail))
      return true;

   const int mode = (int)InpMS_TesterDegradedScorePolicyMode;
   bool effective_on = false;

   if(mode == TESTER_DEGRADED_SCORE_POLICY_FORCE_OFF)
   {
      effective_on = false;
   }
   else if(mode == TESTER_DEGRADED_SCORE_POLICY_FORCE_ON)
   {
      effective_on = true;
   }
   else if(InpMS_TesterDegradedScorePolicyEnable)
   {
      // explicit legacy override kept for compatibility
      effective_on = true;
   }
   else
   {
      // AUTO
      effective_on =
         (InpMS_TesterAllowUnavailable &&
          fallback_active);
   }

   if(!effective_on)
      return false;

   active = true;

   // Under AUTO, prefer relax_min_score first.
   if(mode == TESTER_DEGRADED_SCORE_POLICY_AUTO && !InpMS_TesterDegradedScorePolicyEnable)
   {
      policy_type = "relax_min_score";
   }
   else
   {
      policy_type = RuntimeTesterDegradedScorePolicyTypeName((int)InpMS_TesterDegradedScorePolicyType);
   }

   magnitude = InpMS_TesterDegradedScorePolicyMagnitude;
   if(magnitude < 0.0)  magnitude = 0.0;
   if(magnitude > 0.08) magnitude = 0.08;

   // one-line effective-policy log on bar change only
   static string   s_last_sym = "";
   static datetime s_last_bar = 0;
   static bool     s_last_active = false;
   static string   s_last_type = "";
   static double   s_last_mag = -1.0;

   string log_sym = sym;
   if(StringLen(log_sym) == 0)
      log_sym = _Symbol;

   datetime bar0 = iTime(log_sym, (ENUM_TIMEFRAMES)Period(), 0);
   if(bar0 <= 0)
      bar0 = TimeCurrent();

   const bool changed =
      (s_last_sym != log_sym ||
       s_last_bar != bar0 ||
       s_last_active != active ||
       s_last_type != policy_type ||
       MathAbs(s_last_mag - magnitude) > 0.000001);

   if(changed)
   {
      PrintFormat("[DegradedScorePolicy] effective=ON mode=%s legacy_override=%s type=%s magnitude=%.3f sym=%s fallback_active=%s reason=%s",
                  RuntimeTesterDegradedScorePolicyModeName(mode),
                  (InpMS_TesterDegradedScorePolicyEnable ? "true" : "false"),
                  policy_type,
                  magnitude,
                  log_sym,
                  (fallback_active ? "true" : "false"),
                  fallback_reason);

      s_last_sym = log_sym;
      s_last_bar = bar0;
      s_last_active = active;
      s_last_type = policy_type;
      s_last_mag = magnitude;
   }

   return true;
}

// =================== No-Trade Breadcrumbs (Gate→Router→Policies→Risk→Exec) ===================
enum TraceStage
{
   TS_GATE     = 1,
   TS_ROUTER   = 2,
   TS_POLICIES = 3,
   TS_RISK     = 4,
   TS_EXEC     = 5
};

// Stage-specific "why" codes (avoid collision with gate codes by using 100+)
enum TraceCode
{
   TR_ROUTER_NO_CAND     = 101,
   TR_ROUTER_NO_INTENT   = 102,
   TR_ROUTER_PICK_DROP   = 103,
   TR_ROUTER_MODE_BLOCK  = 104,
   TR_POLICIES_SOFT_SKIP = 151,
   TR_RISK_COMPUTE_FAIL  = 201,
   TR_EXEC_REJECT        = 301
};

string _TraceStageStr(const int s)
{
   switch(s)
   {
      case TS_GATE:     return "GATE";
      case TS_ROUTER:   return "ROUTER";
      case TS_POLICIES: return "POLICIES";
      case TS_RISK:     return "RISK";
      case TS_EXEC:     return "EXEC";
      default:          return "NA";
   }
}

string _GateReasonStr(const int c)
{
   switch(c)
   {
      case GATE_POLICIES:   return "POLICIES";
      case GATE_SESSION:    return "SESSION";
      case GATE_TIMEWINDOW: return "TIMEWINDOW";
      case GATE_PRICE_ARM:  return "PRICE_ARM";
      case GATE_PRICE_STOP: return "PRICE_STOP";
      case GATE_NEWS:       return "NEWS";
      case GATE_EXEC_LOCK:  return "EXEC_LOCK";
      case GATE_TRADE_DISABLED: return "TRADE_DISABLED";
      case GATE_WARMUP:     return "WARMUP";
      case GATE_INHIBIT:    return "INHIBIT";
      case GATE_NONE:       return "NONE";
      case GATE_STRATMODE_PATH_BUG: return "STRATMODE_PATH_BUG";
      default:              return "UNKNOWN";
   }
}

bool _IsKnownGateReason(const int c)
{
  switch(c)
  {
    case GATE_POLICIES:
    case GATE_SESSION:
    case GATE_TIMEWINDOW:
    case GATE_PRICE_ARM:
    case GATE_PRICE_STOP:
    case GATE_NEWS:
    case GATE_EXEC_LOCK:
    case GATE_TRADE_DISABLED:
    case GATE_WARMUP:
    case GATE_INHIBIT:
    case GATE_NONE:
    case GATE_STRATMODE_PATH_BUG:
      return true;
    default:
      return false;
  }
}

bool _IsMicrostructurePolicyReason(const int reason)
{
   switch(reason)
   {
      case Policies::GATE_INSTITUTIONAL:
      case Policies::GATE_MICRO_VPIN:
      case Policies::GATE_MICRO_TOXICITY:
      case Policies::GATE_MICRO_SPREAD_STRESS:
      case Policies::GATE_MICRO_RESILIENCY:
      case Policies::GATE_MICRO_OBSERVABILITY:
      case Policies::GATE_MICRO_VENUE:
      case Policies::GATE_MICRO_IMPACT:
      case Policies::GATE_MICRO_DARKPOOL:
      case Policies::GATE_MICRO_TRUTH:
      case Policies::GATE_MICRO_QUOTE_INSTABILITY:
      case Policies::GATE_MICRO_THIN_LIQUIDITY:
      case Policies::GATE_SM_INVALIDATION:
      case Policies::GATE_LIQUIDITY_TRAP:
         return true;
   }
   return false;
}

string _PolicyReasonStr(const int pol_reason)
{
   if(pol_reason == 0 || pol_reason == Policies::GATE_OK)
      return "OK";
   return Policies::GateReasonToString(pol_reason);
}

string _GatePrecedenceTag(const string origin,
                          const int gate_reason,
                          const int pol_reason)
{
   if(_IsMicrostructurePolicyReason(pol_reason))
      return "MICROSTRUCTURE";

   if(gate_reason == GATE_SESSION)
      return "SESSION";

   if(gate_reason == GATE_TIMEWINDOW)
      return "TIMEWINDOW";

   if(gate_reason == GATE_EXEC_LOCK)
      return "EXECUTION";

   if(gate_reason == GATE_PRICE_ARM || gate_reason == GATE_PRICE_STOP)
      return "PRICE";

   if(gate_reason == GATE_TRADE_DISABLED)
      return "TRADE_ENV";

   if(gate_reason == GATE_INHIBIT)
      return "INHIBIT";

   if(gate_reason == GATE_STRATMODE_PATH_BUG)
      return "ROUTER";

   if(gate_reason == GATE_POLICIES)
      return "POLICIES";

   if(StringFind(origin, "trade_env") >= 0)
      return "TRADE_ENV";

   return _GateReasonStr(gate_reason);
}

string _MergeGateBlockedDetail(const string base_detail,
                               const int pol_reason,
                               const string pol_detail,
                               const string micro_detail)
{
   string out = base_detail;

   if(pol_reason != 0 && pol_reason != Policies::GATE_OK)
      out += StringFormat(" | pol_reason=%d(%s)",
                          pol_reason,
                          _PolicyReasonStr(pol_reason));

   if(StringLen(pol_detail) > 0)
      out += StringFormat(" | pol_detail=%s", pol_detail);

   if(StringLen(micro_detail) > 0)
      out += StringFormat(" | micro_detail=%s", micro_detail);

   return out;
}

string _TraceDirStr(const Direction d)
{
   return (d==DIR_BUY ? "BUY" : (d==DIR_SELL ? "SELL" : "NA"));
}

// Throttled, structured breadcrumb. Keeps your logs readable and consistent.
void TraceNoTrade(const string sym,
                  const int stage,
                  const int code,
                  const string detail,
                  const int strat_id=0,
                  const Direction dir=DIR_BOTH,
                  const double score=0.0,
                  const double lots=0.0,
                  const int retcode=0)
{
   const bool allow_non_debug_router_pick_drop =
      (stage == TS_ROUTER && code == TR_ROUTER_PICK_DROP);

   if(!InpDebug && !allow_non_debug_router_pick_drop)
      return;

   static datetime last_ts = 0;
   static int      last_stage = 0;
   static int      last_code = 0;
   static string   last_sym = "";
   static int      last_strat_id = 0;
   static string   last_detail = "";

   const datetime now = TimeCurrent();
   if(now == last_ts &&
      stage == last_stage &&
      code == last_code &&
      sym == last_sym &&
      strat_id == last_strat_id &&
      detail == last_detail)
      return;

   last_ts = now;
   last_stage = stage;
   last_code = code;
   last_sym = sym;
   last_strat_id = strat_id;
   last_detail = detail;

   const string code_str = (stage==TS_GATE ? _GateReasonStr(code) : IntegerToString(code));

   PrintFormat("[NoTrade] %s stage=%s code=%s strat=%d dir=%s score=%.3f lots=%.2f ret=%d | %s",
               sym, _TraceStageStr(stage), code_str, strat_id, _TraceDirStr(dir),
               score, lots, retcode, detail);
}

// Exec reject classifier (fallback). Keeps “retcode only” from being useless.
int ExecRejectClassify(const Exec::Outcome &ex, string &detail_out)
{
   detail_out = ex.last_error_text;

   switch((int)ex.retcode)
   {
      case TRADE_RETCODE_INVALID_STOPS:  detail_out = "INVALID_STOPS: stops too close / invalid"; return 311;
      case TRADE_RETCODE_INVALID_VOLUME: detail_out = "INVALID_VOLUME: lots/step/min/max";       return 312;
      case TRADE_RETCODE_MARKET_CLOSED:  detail_out = "MARKET_CLOSED";                            return 313;
      case TRADE_RETCODE_TRADE_DISABLED: detail_out = "TRADE_DISABLED";                           return 314;
      case TRADE_RETCODE_NO_MONEY:       detail_out = "NO_MONEY / margin";                        return 315;
      case TRADE_RETCODE_REQUOTE:        detail_out = "REQUOTE";                                  return 316;
      case TRADE_RETCODE_PRICE_OFF:      detail_out = "PRICE_OFF / off quotes";                   return 317;
      case TRADE_RETCODE_REJECT:         detail_out = "REJECTED by broker";                       return 318;
      default:                            /* keep ex.last_error_text */                           return 399;
   }
}

// ---------------- Unified warmup gate (single source of truth) ----------------
bool WarmupGateOK()
{
   if(!InpWarmupGate)
      return true;

   static bool latched = false;
   static uint t0_ms   = 0;
   static int  ticks   = 0;

   if(latched)
      return true;

   if(t0_ms == 0)
      t0_ms = GetTickCount();

   ticks++;

   // Primary readiness: same gates you already use elsewhere
   const bool gate_ready = (InpDebug ? Warmup::GateReadyOnce(InpDebug) : true); // debug info only
   const bool data_ready = Warmup::DataReadyForEntryRT(g_cfg, InpDebug);        // RT non-blocking series check
   const bool ready      = data_ready;     
   
   if(ready)
   {
      latched = true;
      return true;
   }

   // Tester/optimization soft latch only (do NOT weaken live behavior)
   const bool in_tester = IsTesterRuntime();
   if(in_tester)
   {
      const uint elapsed = GetTickCount() - t0_ms;
      const uint soft_ms = (InpWarmupSoftLatchMs > 0 ? (uint)InpWarmupSoftLatchMs : 0);

      if((soft_ms > 0 && elapsed > soft_ms) || (InpWarmupSoftLatchTicks > 0 && ticks > InpWarmupSoftLatchTicks))
      {
         if(InpDebug)
            Print("[Warmup] soft-latch engaged; proceeding.");
         latched = true;
         return true;
      }
   }

   if(InpDebug)
   {
      static datetime last_warn = 0;
      datetime now = TimeCurrent();
      if(now != last_warn)
      {
         last_warn = now;
         TraceNoTrade(_Symbol, TS_GATE, GATE_WARMUP,
                      StringFormat("WarmupGateOK=false gate_ready=%d data_ready=%d ticks=%d",
                                   (int)gate_ready, (int)data_ready, ticks));
      }
   }
   return false;
}

// ---------------- Exec failure journal (throttled) ----------------
void LogExecFailThrottled(const string sym,
                          const int dir,
                          const OrderPlan &plan,
                          const Exec::Outcome &ex,
                          const int slippage_points)
{
   if(ex.ok)
      return;

   if(!InpExecFailJournal)
      return;

   static datetime last = 0;
   datetime now = TimeCurrent();

   if((now - last) < InpExecFailThrottleSec)
      return;

   last = now;

   string side = (dir == DIR_BUY ? "BUY" : "SELL");

   const string exec_origin_class  = Exec::ExecOriginClassText(ex.origin_class);
   const string exec_origin_reason = Exec::ExecOriginReasonText(ex.origin_reason);
   const int non_canonical_exec = (ex.origin_class != Exec::EXEC_ORIGIN_CANONICAL ? 1 : 0);

   PrintFormat("[ExecFail] %s %s retcode=%u err=%d(%s) ticket=%I64d lots=%.2f price=%.5f sl=%.5f tp=%.5f slip=%d origin=%s reason=%s(%d) non_canonical=%d",
               sym, side, ex.retcode,
               ex.last_error, LogX::San(ex.last_error_text),
               (long)ex.ticket,
               plan.lots, plan.price, plan.sl, plan.tp, slippage_points,
               exec_origin_class, exec_origin_reason, ex.origin_reason, non_canonical_exec);

   PrintFormat("[ExecFailGate] %s pf=%d ssg=%d loc=%d exg=%d rkg=%d internal=%.2f depthFade=%.2f",
               sym,
               (ex.pre_filter_pass ? 1 : 0),
               (ex.signal_stack_gate_pass ? 1 : 0),
               (ex.location_pass ? 1 : 0),
               (ex.execution_gate_pass ? 1 : 0),
               (ex.risk_gate_pass ? 1 : 0),
               ex.internalisation01,
               ex.depth_fade01);
}

void HintTradeDisabledOnce(const Exec::Outcome &ex)
{
   if(ex.code != Exec::EXE_TRADE_DISABLED)
      return;

   static bool warned_trade_disabled = false;
   if(warned_trade_disabled)
      return;

   warned_trade_disabled = true;
   Print("[HINT] Trading is disabled. In Strategy Tester: enable Algo Trading and allow trading in the EA properties.");
}

// ================== Helpers ==================
double EA_RouterManualMinScore()
{
   if(InpRouterMinScore >= 0.0)
      return InpRouterMinScore;
   return Const::SCORE_ELIGIBILITY_MIN;
}

int EA_RouterManualMaxStrats()
{
   if(InpRouterMaxStrats > 0)
      return InpRouterMaxStrats;
   return 12;
}

double EA_RouterProfileMinScore(const Config::ProfileSpec &ps)
{
   if(ps.min_score > 0.0)
      return ps.min_score;
   return EA_RouterManualMinScore();
}

int EA_RouterProfileMaxStrats(const Config::ProfileSpec &ps)
{
   if(ps.max_strats > 0)
      return ps.max_strats;
   return EA_RouterManualMaxStrats();
}

bool EA_RouterUseProfileThresholds()
{
   if(InpRouterThresholdPrecedence == 0)
      return false;

   if(InpRouterThresholdPrecedence == 1)
      return true;

   if(g_is_tester && InpRouterTesterPreferManualThresholds)
      return false;

   return InpProfileUseRouterHints;
}

string EA_RouterThresholdPolicyName()
{
   if(InpRouterThresholdPrecedence == 0)
      return "manual";

   if(InpRouterThresholdPrecedence == 1)
      return "profile";

   if(g_is_tester && InpRouterTesterPreferManualThresholds)
      return "legacy_tester_manual";

   if(InpProfileUseRouterHints)
      return "legacy_profile";

   return "legacy_manual";
}

string EA_RouterThresholdSourceName(const bool use_profile_source)
{
   if(use_profile_source)
      return "profile";

   return "manual";
}

double EA_RouterClampProfileMinForTester(const double manual_min,
                                         const double requested_min,
                                         bool &clamped_out)
{
   clamped_out = false;

   double resolved = requested_min;

   if(!g_is_tester)
      return resolved;

   if(!InpRouterTesterClampProfileMin)
      return resolved;

   if(InpRouterTesterAllowWideProfileMin)
      return resolved;

   if(MathAbs(resolved - manual_min) > 0.000001)
      clamped_out = true;

   return manual_min;
}

double EA_RouterResolvedMinScore()
{
   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   if(rc.min_score > 0.0)
      return rc.min_score;
   return EA_RouterManualMinScore();
}

int EA_RouterResolvedMaxStrats()
{
   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   if(rc.max_strats > 0)
      return rc.max_strats;
   return EA_RouterManualMaxStrats();
}

int EA_ResolveHubTimerSec(const Settings &cfg)
{
   if(IsTesterRuntime())
      return MathMax(1, InpTester_TimerSec);

   return MathMax(1, (cfg.timer_ms <= 1000 ? 1 : cfg.timer_ms / 1000));
}

int EA_ResolveMinForcedRouterEvalSec(const Settings &cfg)
{
   if(InpTimer_MinForcedRouterEvalSec > 0)
      return InpTimer_MinForcedRouterEvalSec;

   return MathMax(1, EA_ResolveHubTimerSec(cfg) * MathMax(1, g_msh_idle_fallback_after_n));
}

int ResolveTesterRouterGateMode()
{
   if(!IsTesterRuntime())
      return TESTER_ROUTER_GATE_MODE_STRICT;

   if(InpTester_RouterGateMode == TESTER_ROUTER_GATE_MODE_AUTO)
   {
      if(InpTester_BypassPolicyGates)
         return TESTER_ROUTER_GATE_MODE_BYPASS;

      return TESTER_ROUTER_GATE_MODE_STRICT;
   }

   return (int)InpTester_RouterGateMode;
}

string TesterRouterGateModeName(const int mode)
{
   if(mode == TESTER_ROUTER_GATE_MODE_STRICT)
      return "strict";
   if(mode == TESTER_ROUTER_GATE_MODE_SOFT_MICRO_FRESHNESS)
      return "soft_micro_freshness";
   if(mode == TESTER_ROUTER_GATE_MODE_BYPASS)
      return "bypass";

   return "auto";
}

string EA_SigSelModeName(const int mode)
{
   if(mode == Config::SELECTION_FIXED)
      return "fixed";
   return "dynamic";
}

string EA_SigSelInstModeName(const int mode)
{
   if(mode == Config::INST_SELECTION_DIRECT_FULL)
      return "direct_full";
   return "anti_echo_subfamily";
}

string EA_SigSelInstDegradeModeName(const int mode)
{
   if(mode == INST_DEGRADE_PROXY_SUBSTITUTE)
      return "proxy_substitute";
   if(mode == INST_DEGRADE_SOFT_NEUTRAL_THEN_STACK_RELAX)
      return "soft_neutral_then_stack_relax";
   if(mode == INST_DEGRADE_HARD_BLOCK)
      return "hard_block";
   return "proxy_substitute_then_stack_relax";
}

int EA_ParseSigSelModeInput(const string mode_text)
{
   if(mode_text == "fixed" || mode_text == "FIXED" || mode_text == "Fixed")
      return Config::SELECTION_FIXED;

   return Config::SELECTION_DYNAMIC;
}

int EA_ParseSigSelInstModeInput(const string mode_text)
{
   if(mode_text == "direct_full" || mode_text == "DIRECT_FULL" || mode_text == "Direct_Full")
      return Config::INST_SELECTION_DIRECT_FULL;

   return Config::INST_SELECTION_ANTI_ECHO_SUBFAMILY;
}

int EA_ParseSigSelInstDegradeModeInput(const string mode_text)
{
   string t = mode_text;
   StringToLower(t);

   if(t == "proxy_substitute")
      return INST_DEGRADE_PROXY_SUBSTITUTE;
   if(t == "soft_neutral_then_stack_relax")
      return INST_DEGRADE_SOFT_NEUTRAL_THEN_STACK_RELAX;
   if(t == "hard_block")
      return INST_DEGRADE_HARD_BLOCK;

   return INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX;
}

string EA_InstSignalSourceName(const int src)
{
   if(src == INST_SIGNAL_SOURCE_PROXY)
      return "proxy";
   if(src == INST_SIGNAL_SOURCE_DIRECT)
      return "direct";
   return "none";
}

bool EA_RuntimeInstitutionalDegradeActive()
{
   if(StateInstitutionalHardInstBlock(g_state))
      return true;
   if(StateInstitutionalPartial(g_state))
      return true;
   if(StateInstitutionalUnavailable(g_state))
      return true;
   if(StateInstitutionalSignalSource(g_state) == INST_SIGNAL_SOURCE_PROXY)
      return true;

   return false;
}

void EA_LogInstitutionalDegradeStateOncePerBar(const string sym,
                                               const datetime bar_time)
{
   if(!InpDebug)
      return;

   const string use_sym = (sym == "" ? CanonicalRouterSymbol() : sym);
   if(use_sym == "")
      return;

   const bool degraded_active = EA_RuntimeInstitutionalDegradeActive();
   const bool hard_block      = StateInstitutionalHardInstBlock(g_state);

   if(!degraded_active && !hard_block)
      return;

   static string   last_sym = "";
   static datetime last_bar_time = 0;
   static int      last_sel_source = -1;
   static int      last_hard_block = -1;

   const datetime key           = (bar_time > 0 ? bar_time : TimeCurrent());
   const int      sel_source    = StateInstitutionalSignalSource(g_state);
   const int      hard_block_i  = (hard_block ? 1 : 0);

   if(use_sym == last_sym &&
      key == last_bar_time &&
      sel_source == last_sel_source &&
      hard_block_i == last_hard_block)
   {
      return;
   }

   last_sym        = use_sym;
   last_bar_time   = key;
   last_sel_source = sel_source;
   last_hard_block = hard_block_i;

   LogX::Warn(StringFormat(
      "[InstDegrade] sym=%s degraded=%d coverage=%.2f available=%d partial=%d unavailable=%d proxyAvail=%d selSource=%s(%d) hardBlock=%d effMinVotes=%d gates{pf=%d ssg=%d loc=%d}",
      use_sym,
      (degraded_active ? 1 : 0),
      StateInstitutionalCoverage01(g_state),
      (StateInstitutionalAvailable(g_state) ? 1 : 0),
      (StateInstitutionalPartial(g_state) ? 1 : 0),
      (StateInstitutionalUnavailable(g_state) ? 1 : 0),
      (StateInstitutionalProxyInstitutionalAvailable(g_state) ? 1 : 0),
      EA_InstSignalSourceName(sel_source),
      sel_source,
      hard_block_i,
      StateInstitutionalEffectiveMinCategoryVotes(g_state),
      (StateInstitutionalPreFilterPass(g_state) ? 1 : 0),
      (StateInstitutionalSignalStackGatePass(g_state) ? 1 : 0),
      (StateInstitutionalLocationPass(g_state) ? 1 : 0)));
}

bool TesterSoftMicroFreshnessFailure(const string detail)
{
   if(StringLen(detail) <= 0)
      return false;

   if(StringFind(detail, "canonical micro stale") >= 0)
      return true;
   if(StringFind(detail, "state_invalid_canonical") >= 0)
      return true;
   if(StringFind(detail, "bar_misaligned_hard") >= 0)
      return true;
   if(StringFind(detail, "tester_fallback:") >= 0)
      return true;

   return false;
}

void LogTesterRouterGateModeDiagOncePerBar(const string sym,
                                           const datetime bar_time,
                                           const string detail)
{
   if(!IsTesterRuntime())
      return;

   static string last_key = "";

   const int mode = ResolveTesterRouterGateMode();
   const string key =
      sym + "|" +
      IntegerToString((int)bar_time) + "|" +
      IntegerToString(mode) + "|" +
      detail;

   if(last_key == key)
      return;

   last_key = key;

   LogX::Info(StringFormat(
      "[TesterGate] sym=%s bar=%s mode=%s detail=%s",
      sym,
      InstDiagTimeStr(bar_time),
      TesterRouterGateModeName(mode),
      detail));
}

string EA_RuntimeGateJsonFragment(const Settings &cfg)
{
   bool degraded_policy_active = false;
   string degraded_policy_type = "";
   double degraded_policy_mag = 0.0;

   RuntimeTesterDegradedScorePolicySnapshot(CanonicalRouterSymbol(),
                                            degraded_policy_active,
                                            degraded_policy_type,
                                            degraded_policy_mag);

   string j = "";
   j += ",\"router_min_score\":" + DoubleToString(Config::CfgRouterMinScore(cfg), 3);
   j += ",\"tester_degraded\":" + (Config::CfgTesterDegradedModeActive(cfg) ? "true" : "false");
   j += ",\"news_gate\":" + (Config::CfgNewsBlockEnabled(cfg) ? "true" : "false");
   j += ",\"regime_gate\":" + (Config::CfgRegimeGateEnabled(cfg) ? "true" : "false");
   j += ",\"liquidity_gate\":" + (Config::CfgLiquidityGateEnabled(cfg) ? "true" : "false");
   j += ",\"tester_policy_bypass\":" + ((IsTesterRuntime() && ResolveTesterRouterGateMode() == TESTER_ROUTER_GATE_MODE_BYPASS) ? "true" : "false");
   j += ",\"tester_gate_mode\":" + Telemetry::JsonStringOrNull(IsTesterRuntime(), TesterRouterGateModeName(ResolveTesterRouterGateMode()));
   j += ",\"tester_gate_soft_micro\":" + ((IsTesterRuntime() && ResolveTesterRouterGateMode() == TESTER_ROUTER_GATE_MODE_SOFT_MICRO_FRESHNESS) ? "true" : "false");
   j += ",\"degraded_score_policy_active\":" + (degraded_policy_active ? "true" : "false");
   j += ",\"degraded_score_policy_type\":" + Telemetry::JsonStringOrNull(StringLen(degraded_policy_type) > 0, degraded_policy_type);
   j += ",\"degraded_score_policy_mag\":" + DoubleToString(degraded_policy_mag, 3);
   j += ",\"timer_sec\":" + IntegerToString(EA_ResolveHubTimerSec(cfg));
   j += ",\"timer_force_every_heartbeat\":" + ((IsTesterRuntime() && InpTester_ForceTimerEveryHeartbeat) ? "true" : "false");

   const double runtime_inst_coverage01 = StateInstitutionalCoverage01(g_state);
   const int    runtime_inst_sel_source = StateInstitutionalSignalSource(g_state);
   const bool   runtime_inst_degrade_active = EA_RuntimeInstitutionalDegradeActive();

   j += ",\"sigsel_enable\":" + (cfg.sigsel_enable ? "true" : "false");
   j += ",\"sigsel_mode\":" + Telemetry::JsonStringOrNull(true, EA_SigSelModeName(cfg.sigsel_selection_mode));
   j += ",\"sigsel_inst_mode\":" + Telemetry::JsonStringOrNull(true, EA_SigSelInstModeName(cfg.sigsel_inst_selection_mode));
   j += ",\"sigsel_inst_degrade_mode\":" + Telemetry::JsonStringOrNull(true, EA_SigSelInstDegradeModeName(cfg.sigsel_institutional_degrade_mode));
   j += ",\"sigsel_inst_coverage_threshold\":" + DoubleToString(cfg.sigsel_inst_coverage_threshold, 3);
   j += ",\"sigsel_min_category_votes\":" + IntegerToString(cfg.sigsel_min_category_votes);
   j += ",\"sigsel_min_category_votes_default\":" + IntegerToString(cfg.sigsel_min_category_votes_default);
   j += ",\"sigsel_min_category_votes_floor\":" + IntegerToString(cfg.sigsel_min_category_votes_floor);
   j += ",\"sigsel_min_location_votes\":" + IntegerToString(cfg.sigsel_min_location_votes);

   j += ",\"runtime_inst_degrade_active\":" + (runtime_inst_degrade_active ? "true" : "false");
   j += ",\"runtime_inst_coverage01\":" + DoubleToString(runtime_inst_coverage01, 3);
   j += ",\"runtime_inst_available\":" + (StateInstitutionalAvailable(g_state) ? "true" : "false");
   j += ",\"runtime_inst_partial\":" + (StateInstitutionalPartial(g_state) ? "true" : "false");
   j += ",\"runtime_inst_unavailable\":" + (StateInstitutionalUnavailable(g_state) ? "true" : "false");
   j += ",\"runtime_proxy_inst_available\":" + (StateInstitutionalProxyInstitutionalAvailable(g_state) ? "true" : "false");
   j += ",\"runtime_inst_sel_source\":" + IntegerToString(runtime_inst_sel_source);
   j += ",\"runtime_inst_sel_source_name\":" + Telemetry::JsonStringOrNull(true, EA_InstSignalSourceName(runtime_inst_sel_source));
   j += ",\"runtime_hard_inst_block\":" + (StateInstitutionalHardInstBlock(g_state) ? "true" : "false");
   j += ",\"runtime_effective_min_category_votes\":" + IntegerToString(StateInstitutionalEffectiveMinCategoryVotes(g_state));

   j += ",\"last_pre_filter_pass\":" + (Risk::LastDiagPreFilterPass() ? "true" : "false");
   j += ",\"last_signal_stack_gate_pass\":" + (Risk::LastDiagSignalStackGatePass() ? "true" : "false");
   j += ",\"last_location_pass\":" + (Risk::LastDiagLocationPass() ? "true" : "false");
   j += ",\"last_execution_gate_pass\":" + (Risk::LastDiagExecutionGatePass() ? "true" : "false");
   j += ",\"last_risk_gate_pass\":" + (Risk::LastDiagRiskGatePass() ? "true" : "false");

   j += ",\"last_internalisation_proxy01\":" + DoubleToString(Risk::LastDiagInternalisation01(), 3);
   j += ",\"last_depth_fade01\":" + DoubleToString(Risk::LastDiagDepthFade01(), 3);
   return j;
}

void EA_LogRuntimeGateSummary(const string where, const Settings &cfg)
{
   bool degraded_policy_active = false;
   string degraded_policy_type = "";
   double degraded_policy_mag = 0.0;

   RuntimeTesterDegradedScorePolicySnapshot(CanonicalRouterSymbol(),
                                            degraded_policy_active,
                                            degraded_policy_type,
                                            degraded_policy_mag);

   const double inst_coverage01 = StateInstitutionalCoverage01(g_state);
   const int    inst_sel_source = StateInstitutionalSignalSource(g_state);
   const bool   inst_degrade_active = EA_RuntimeInstitutionalDegradeActive();
   const bool   inst_available = StateInstitutionalAvailable(g_state);
   const bool   inst_partial = StateInstitutionalPartial(g_state);
   const bool   inst_unavailable = StateInstitutionalUnavailable(g_state);
   const bool   proxy_inst_available = StateInstitutionalProxyInstitutionalAvailable(g_state);
   const bool   hard_inst_block = StateInstitutionalHardInstBlock(g_state);
   const int    eff_min_votes = StateInstitutionalEffectiveMinCategoryVotes(g_state);

   LogX::Info(StringFormat(
      "%s runtime_gates tester=%d degraded=%d router_min=%.3f news_gate=%d regime_gate=%d liquidity_gate=%d tester_policy_bypass=%d tester_gate_mode=%s tester_gate_soft_micro=%d degraded_score_policy=%d degraded_score_type=%s degraded_score_mag=%.3f timer_sec=%d force_timer_every_heartbeat=%d",
      where,
      (IsTesterRuntime() ? 1 : 0),
      (Config::CfgTesterDegradedModeActive(cfg) ? 1 : 0),
      Config::CfgRouterMinScore(cfg),
      (Config::CfgNewsBlockEnabled(cfg) ? 1 : 0),
      (Config::CfgRegimeGateEnabled(cfg) ? 1 : 0),
      (Config::CfgLiquidityGateEnabled(cfg) ? 1 : 0),
      ((IsTesterRuntime() && ResolveTesterRouterGateMode() == TESTER_ROUTER_GATE_MODE_BYPASS) ? 1 : 0),
      TesterRouterGateModeName(ResolveTesterRouterGateMode()),
      ((IsTesterRuntime() && ResolveTesterRouterGateMode() == TESTER_ROUTER_GATE_MODE_SOFT_MICRO_FRESHNESS) ? 1 : 0),
      (degraded_policy_active ? 1 : 0),
      degraded_policy_type,
      degraded_policy_mag,
      EA_ResolveHubTimerSec(cfg),
      ((IsTesterRuntime() && InpTester_ForceTimerEveryHeartbeat) ? 1 : 0)));

   LogX::Info(StringFormat(
      "%s signal_stack cfg{enable=%d mode=%s inst_mode=%s degrade_mode=%s min_cat=%d min_cat_floor=%d min_loc=%d inst_cov_th=%.2f} gates{pf=%d ssg=%d loc=%d exg=%d rkg=%d internal=%.2f depthFade=%.2f} runtime_inst{degraded=%d coverage=%.2f available=%d partial=%d unavailable=%d proxyAvail=%d src=%s(%d) hardBlock=%d effMinVotes=%d}",
      where,
      (cfg.sigsel_enable ? 1 : 0),
      EA_SigSelModeName(cfg.sigsel_selection_mode),
      EA_SigSelInstModeName(cfg.sigsel_inst_selection_mode),
      EA_SigSelInstDegradeModeName(cfg.sigsel_institutional_degrade_mode),
      cfg.sigsel_min_category_votes_default,
      cfg.sigsel_min_category_votes_floor,
      cfg.sigsel_min_location_votes,
      cfg.sigsel_inst_coverage_threshold,
      (Risk::LastDiagPreFilterPass() ? 1 : 0),
      (Risk::LastDiagSignalStackGatePass() ? 1 : 0),
      (Risk::LastDiagLocationPass() ? 1 : 0),
      (Risk::LastDiagExecutionGatePass() ? 1 : 0),
      (Risk::LastDiagRiskGatePass() ? 1 : 0),
      Risk::LastDiagInternalisation01(),
      Risk::LastDiagDepthFade01(),
      (inst_degrade_active ? 1 : 0),
      inst_coverage01,
      (inst_available ? 1 : 0),
      (inst_partial ? 1 : 0),
      (inst_unavailable ? 1 : 0),
      (proxy_inst_available ? 1 : 0),
      EA_InstSignalSourceName(inst_sel_source),
      inst_sel_source,
      (hard_inst_block ? 1 : 0),
      eff_min_votes));

   if(inst_degrade_active || hard_inst_block)
   {
      LogX::Warn(StringFormat(
         "%s institutional_degrade active{coverage=%.2f available=%d partial=%d unavailable=%d proxyAvail=%d selSource=%s(%d) hardBlock=%d effMinVotes=%d pf=%d ssg=%d loc=%d}",
         where,
         inst_coverage01,
         (inst_available ? 1 : 0),
         (inst_partial ? 1 : 0),
         (inst_unavailable ? 1 : 0),
         (proxy_inst_available ? 1 : 0),
         EA_InstSignalSourceName(inst_sel_source),
         inst_sel_source,
         (hard_inst_block ? 1 : 0),
         eff_min_votes,
         (StateInstitutionalPreFilterPass(g_state) ? 1 : 0),
         (StateInstitutionalSignalStackGatePass(g_state) ? 1 : 0),
         (StateInstitutionalLocationPass(g_state) ? 1 : 0)));
   }
}

void EA_ApplyRouterModeAndBucket(RouterConfig &rc)
{
   if(InpRouterMode == 1)
      rc.select_mode = SEL_WEIGHTED;
   else
   if(InpRouterMode == 2)
      rc.select_mode = SEL_AB;
   else
      rc.select_mode = SEL_MAX;

   if(InpAB_Bucket == 1)
      rc.ab_bucket = (int)AB_A;
   else
   if(InpAB_Bucket == 2)
      rc.ab_bucket = (int)AB_B;
   else
      rc.ab_bucket = (int)AB_OFF;
}

void EA_LogRouterThresholdResolution(const string origin_tag,
                                     const string precedence_policy,
                                     const string resolved_source,
                                     const double manual_min,
                                     const double profile_min,
                                     const double requested_min,
                                     const double resolved_min,
                                     const int manual_cap,
                                     const int profile_cap,
                                     const int resolved_cap,
                                     const bool tester_clamped)
{
   const int profile_type = (int)InpProfileType;

   const bool changed =
      (!g_router_resolve_logged ||
       g_router_last_profile_type != profile_type ||
       g_router_last_policy != precedence_policy ||
       g_router_last_source != resolved_source ||
       MathAbs(g_router_last_manual_min - manual_min) > 0.000001 ||
       MathAbs(g_router_last_profile_min - profile_min) > 0.000001 ||
       MathAbs(g_router_last_requested_min - requested_min) > 0.000001 ||
       MathAbs(g_router_last_resolved_min - resolved_min) > 0.000001 ||
       g_router_last_manual_cap != manual_cap ||
       g_router_last_profile_cap != profile_cap ||
       g_router_last_resolved_cap != resolved_cap ||
       g_router_last_tester_clamped != tester_clamped);

   if(!changed)
      return;

   if(!g_router_resolve_logged)
   {
      LogX::Info(StringFormat(
         "[RouterStartup] resolved_min_score=%.2f source=%s profile=%s resolved_max_strats=%d precedence=%s tester_clamped=%s",
         resolved_min,
         resolved_source,
         Config::ProfileName((TradingProfile)InpProfileType),
         resolved_cap,
         precedence_policy,
         (tester_clamped ? "true" : "false")));
   }

   LogX::Info(StringFormat(
      "[RouterResolve][%s] precedence=%s source=%s profile=%s manual_min=%.2f profile_min=%.2f requested_min=%.2f resolved_min_score=%.2f manual_max_strats=%d profile_max_strats=%d resolved_max_strats=%d tester_clamped=%s",
      origin_tag,
      precedence_policy,
      resolved_source,
      Config::ProfileName((TradingProfile)InpProfileType),
      manual_min,
      profile_min,
      requested_min,
      resolved_min,
      manual_cap,
      profile_cap,
      resolved_cap,
      (tester_clamped ? "true" : "false")));

   if(tester_clamped)
   {
      LogX::Warn(StringFormat(
         "[RouterResolve] tester clamp applied: profile=%s manual_min=%.2f requested_min=%.2f resolved_min_score=%.2f max_delta=%.2f",
         Config::ProfileName((TradingProfile)InpProfileType),
         manual_min,
         requested_min,
         resolved_min,
         MathMax(0.0, InpRouterTesterClampMaxDelta)));
   }
   else
   if(StringCompare(resolved_source, "profile") == 0 && (resolved_min - manual_min) >= 0.20)
   {
      LogX::Warn(StringFormat(
         "[RouterResolve] resolved min_score %.2f is %.2f stricter than manual %.2f (profile=%s precedence=%s)",
         resolved_min,
         (resolved_min - manual_min),
         manual_min,
         Config::ProfileName((TradingProfile)InpProfileType),
         precedence_policy));
   }

   g_router_resolve_logged      = true;
   g_router_last_manual_min     = manual_min;
   g_router_last_profile_min    = profile_min;
   g_router_last_requested_min  = requested_min;
   g_router_last_resolved_min   = resolved_min;
   g_router_last_manual_cap     = manual_cap;
   g_router_last_profile_cap    = profile_cap;
   g_router_last_resolved_cap   = resolved_cap;
   g_router_last_source         = resolved_source;
   g_router_last_policy         = precedence_policy;
   g_router_last_tester_clamped = tester_clamped;
   g_router_last_profile_type   = profile_type;
}

void EA_SyncResolvedRouterThresholdsToRuntimeSnapshots(const double requested_min,
                                                       const double resolved_min,
                                                       const int resolved_cap,
                                                       const string resolved_source,
                                                       const bool tester_clamped)
{
#ifdef CFG_HAS_ROUTER_MIN_SCORE
   g_cfg.router_min_score = resolved_min;
   S.router_min_score     = resolved_min;
#endif

#ifdef CFG_HAS_ROUTER_MAX_STRATS
   g_cfg.router_max_strats = resolved_cap;
   S.router_max_strats     = resolved_cap;
#endif

   StratReg::SetRouterMinScoreResolutionTelemetry(requested_min,
                                                  resolved_min,
                                                  resolved_source,
                                                  tester_clamped);
}

void ApplyRouterConfig()  // manual-input version
{
   RouterConfig rc = StratReg::GetGlobalRouterConfig();

   EA_ApplyRouterModeAndBucket(rc);

   const double manual_min = EA_RouterManualMinScore();
   const int    manual_cap = EA_RouterManualMaxStrats();

   rc.min_score  = manual_min;
   rc.max_strats = manual_cap;

   StratReg::SetGlobalRouterConfig(rc);

   EA_SyncResolvedRouterThresholdsToRuntimeSnapshots(manual_min,
                                                     rc.min_score,
                                                     rc.max_strats,
                                                     "manual",
                                                     false);

   EA_LogRouterThresholdResolution("manual",
                                   "manual",
                                   "manual",
                                   manual_min,
                                   manual_min,
                                   manual_min,
                                   rc.min_score,
                                   manual_cap,
                                   manual_cap,
                                   rc.max_strats,
                                   false);

   LogX::Info(StringFormat(
      "Router policy=%d (0=max,1=w,2=ab) ab=%d min=%.2f cap=%d [source=manual precedence=manual]",
      InpRouterMode,
      InpAB_Bucket,
      rc.min_score,
      rc.max_strats));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyRouterConfig_Profile(const Config::ProfileSpec &ps)  // profile-aware version
{
   RouterConfig rc = StratReg::GetGlobalRouterConfig();

   EA_ApplyRouterModeAndBucket(rc);

   const double manual_min  = EA_RouterManualMinScore();
   const int    manual_cap  = EA_RouterManualMaxStrats();
   const double profile_min = EA_RouterProfileMinScore(ps);
   const int    profile_cap = EA_RouterProfileMaxStrats(ps);

   const bool   use_profile_source = EA_RouterUseProfileThresholds();
   const string precedence_policy  = EA_RouterThresholdPolicyName();
   const string resolved_source    = EA_RouterThresholdSourceName(use_profile_source);

   double requested_min = manual_min;
   bool   tester_clamped = false;

   if(use_profile_source)
   {
      requested_min = profile_min;
      rc.min_score  = EA_RouterClampProfileMinForTester(manual_min, profile_min, tester_clamped);
      rc.max_strats = profile_cap;
   }
   else
   {
      rc.min_score  = manual_min;
      rc.max_strats = manual_cap;
   }

   const double effective_min = rc.min_score;
   const int    effective_cap = rc.max_strats;

   StratReg::SetGlobalRouterConfig(rc);

   EA_SyncResolvedRouterThresholdsToRuntimeSnapshots(requested_min,
                                                     effective_min,
                                                     effective_cap,
                                                     resolved_source,
                                                     tester_clamped);

   EA_LogRouterThresholdResolution("profile",
                                   precedence_policy,
                                   resolved_source,
                                   manual_min,
                                   profile_min,
                                   requested_min,
                                   effective_min,
                                   manual_cap,
                                   profile_cap,
                                   effective_cap,
                                   tester_clamped);

   if(g_is_tester &&
      use_profile_source &&
      MathAbs(requested_min - effective_min) >= 0.01)
   {
      LogX::Warn(StringFormat(
         "[RouterResolve] tester requested profile min_score %.2f but effective min_score is %.2f (profile=%s precedence=%s tester_clamped=%s)",
         requested_min,
         effective_min,
         Config::ProfileName((TradingProfile)InpProfileType),
         precedence_policy,
         (tester_clamped ? "true" : "false")));
   }

   LogX::Info(StringFormat(
      "Router policy=%d (0=max,1=w,2=ab) ab=%d min=%.2f cap=%d [source=%s precedence=%s profile=%s manual_min=%.2f profile_min=%.2f requested_min=%.2f effective_min=%.2f manual_cap=%d profile_cap=%d tester_clamped=%s]",
      InpRouterMode,
      InpAB_Bucket,
      effective_min,
      effective_cap,
      resolved_source,
      precedence_policy,
      Config::ProfileName((TradingProfile)InpProfileType),
      manual_min,
      profile_min,
      requested_min,
      effective_min,
      manual_cap,
      profile_cap,
      (tester_clamped ? "true" : "false")));
}

// ------------------------------------------------------------------
// Forward declarations (defined later in this file)
// ------------------------------------------------------------------
bool   TryMinimalPathIntent(const string sym, const Settings &cfg,
                            StratReg::RoutedPick &pick_out);

double StreakRiskScale();
void   ResetStreakCounters();
bool   AllowStreakScalingNow(const double news_risk_mult, const bool news_skip);
double _RiskMultMaxCapFromInputs();

inline bool NewsDefensiveStateAtBarClose(const Settings &cfg,
                                        const string sym,
                                        const int shift,
                                        double &risk_mult,
                                        bool &skip,
                                        int &mins_left)
{
   News::CompositeRiskAtBarClose(cfg, sym, shift, risk_mult, skip, mins_left);
   return (skip || (risk_mult < 1.0));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool EvaluateOneSymbolCompileTimeEnabled()
{
#ifdef CA_ENABLE_EVALUATE_ONE_SYMBOL_TEST_UTILITY
   return true;
#else
   return false;
#endif
}

bool LegacyProcessSymbolCompileTimeEnabled()
{
#ifdef CA_ENABLE_LEGACY_TESTER_PROCESSSYMBOL
   return true;
#else
   return false;
#endif
}

bool DirectRegistryCompatRuntimeRequested(const Settings &cfg)
{
   if(!IsTesterRuntime())
      return false;

   if(Config::CfgStrategyMode(cfg) == STRAT_MAIN_ONLY)
      return false;

   #ifdef CFG_HAS_TESTER_DIRECT_REGISTRY_COMPAT
      return cfg.tester_direct_registry_compat;
   #else
      return InpTester_DirectRegistryCompat;
   #endif
}

bool LegacyProcessSymbolRuntimeRequested()
{
   return (DirectRegistryCompatRuntimeRequested(S) &&
           InpUseRegistryRouting &&
           InpLegacyProcessSymbolTester);
}

void WarnDirectRegistryCompatBlockedOnce(const string origin_tag,
                                         const Settings &cfg)
{
   static string last_key = "";

   const bool compat_on = DirectRegistryCompatRuntimeRequested(cfg);
   const string key = StringFormat("%s|%d|%d|%d",
                                   origin_tag,
                                   (int)IsTesterRuntime(),
                                   (int)compat_on,
                                   (int)Config::CfgStrategyMode(cfg));
   if(key == last_key)
      return;

   last_key = key;

   LogX::Warn(StringFormat(
      "[ROUTER-OWNERSHIP] %s blocked: non-canonical route disabled for trade execution. Direct StrategyRegistry compatibility route is diagnostics-only. Required: tester/optimization context + explicit tester direct-registry compatibility flag. Canonical path is OnTimer() with RunCachedRouterPass(Timer) and RouterEvaluateAll(). tester=%s compat=%s strat_mode=%d",
      origin_tag,
      (IsTesterRuntime() ? "true" : "false"),
      (compat_on ? "true" : "false"),
      (int)Config::CfgStrategyMode(cfg)));
}

void WarnNonCanonicalTradeExecutionDisabledOnce(const string origin_tag)
{
   static string seen = "|";
   const string key = origin_tag + "|";

   if(StringFind(seen, key) >= 0)
      return;

   seen += key;

   LogX::Warn(StringFormat(
      "[ROUTER-OWNERSHIP] %s is a non-canonical route disabled for trade execution. Diagnostics may inspect intent/picks only. Canonical live/tester owner is OnTimer() with RunCachedRouterPass(Timer) and RouterEvaluateAll().",
      origin_tag));
}

void WarnLegacyProcessSymbolCompileTimeBlocked(const string origin_tag)
{
   static datetime last_emit = 0;
   const datetime now = TimeCurrent();
   if(now == last_emit)
      return;

   last_emit = now;

   LogX::Warn(StringFormat(
      "[LEGACY][COMPILETIME-OFF] origin=%s requested legacy ProcessSymbol compatibility mode, but CA_ENABLE_LEGACY_TESTER_PROCESSSYMBOL is OFF. Non-canonical route disabled for trade execution. Canonical RunCachedRouterPass(Timer) remains active.",
      origin_tag));
}

void WarnEvaluateOneSymbolCompileTimeBlockedOnce(const string sym)
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(StringFormat(
      "[TEST-UTILITY] EvaluateOneSymbol(%s) blocked: CA_ENABLE_EVALUATE_ONE_SYMBOL_TEST_UTILITY is OFF. This harness is compile-time disabled for operational safety.",
      sym));
}

void WarnEvaluateOneSymbolTesterBlockedOnce(const string sym)
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(StringFormat(
      "[TEST-UTILITY] EvaluateOneSymbol(%s) blocked: g_is_tester=false. This harness is tester-only and must not run in live/manual operation.",
      sym));
}

void WarnEvaluateOneSymbolLegacyBlockedOnce(const string sym)
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(StringFormat(
      "[TEST-UTILITY] EvaluateOneSymbol(%s) blocked: UseLegacyProcessSymbolEngine()=false. Enable explicit legacy tester compatibility mode to use this harness.",
      sym));
}

void WarnEvaluateOneSymbolDeprecatedOnce(const string sym)
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(StringFormat(
"[DEPRECATED] EvaluateOneSymbol(%s) is a non-canonical route disabled for trade execution. Canonical live/tester owner is OnTimer() with MSH::HubTimerTick(), RefreshRuntimeContextFromHub(), RunCachedRouterPass(Timer), and RouterEvaluateAll().",
      sym));
}

void WarnEvaluateOneSymbolMainOnlyBlockedOnce(const string sym)
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(StringFormat(
      "[TEST-UTILITY] EvaluateOneSymbol(%s) blocked: STRAT_MAIN_ONLY must use canonical OnTimer-owned routing only. Direct helper evaluation is not allowed for MAIN_ONLY.",
      sym));
}

void EvaluateOneSymbol(const string sym)
  {
   // DEPRECATED non-canonical helper.
   // Retained only for explicit tester-side legacy compatibility checks.
   // It must never become an alternate owner of live/canonical routing.
   if(!EvaluateOneSymbolCompileTimeEnabled())
     {
      WarnEvaluateOneSymbolCompileTimeBlockedOnce(sym);
      return;
     }

   if(!g_is_tester)
     {
      WarnEvaluateOneSymbolTesterBlockedOnce(sym);
      return;
     }

   if(!UseLegacyProcessSymbolEngine())
     {
      WarnEvaluateOneSymbolLegacyBlockedOnce(sym);
      return;
     }

   WarnEvaluateOneSymbolDeprecatedOnce(sym);

   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
   {
      WarnEvaluateOneSymbolMainOnlyBlockedOnce(sym);
      return;
   }

   Settings cur = S; // per-symbol snapshot if you later need overrides

   // --- Hardening: prevent this path from bypassing the canonical gates ---
   if(!WarmupGateOK())
      return;

   int gate_reason = 0;
   // Use same session/policy gate used by Router pipeline (prevents “side door” trading)
   if(!RouterGateOK(sym, cur, TimeUtils::NowServer(), gate_reason))
      return;

// 1) Intent (registry router or manual fallback)
   StratReg::RoutedPick pick;
   ZeroMemory(pick);
   if(!TryMinimalPathIntent(sym, cur, pick))
     {
      UI_Render(S);
      return;
     }

// 2) Meta layers (news scaling, ML, calm, streak, carry risk-only)
   double risk_mult=1.0;
   bool skip=false;
   int mins_left=0;
   const datetime now_srv = TimeUtils::NowServer();

   NewsDefensiveStateAtBarClose(cur, sym, 1, risk_mult, skip, mins_left);
   News::SurpriseRiskAdjust(now_srv, sym, cur.news_impact_mask, cur.cal_lookback_mins,
                            cur.cal_hard_skip, cur.cal_soft_knee, cur.cal_min_scale,
                            risk_mult, skip);
   
   if(skip)
   {
      if(InpResetStreakOnNewsDerisk)
         ResetStreakCounters();
         
      UI_Render(S);
      return;
   }

   StratScore ss = pick.ss;
   Settings trade_cfg = cur;
   ApplyPickOverrides(pick, trade_cfg, ss);
   ss.risk_mult *= risk_mult;
   if(AllowStreakScalingNow(risk_mult, skip))
      ss.risk_mult *= StreakRiskScale();
   else
      ResetStreakCounters();

   ApplyMetaLayers(pick.dir, ss, pick.bd);

   if(trade_cfg.carry_enable && InpCarry_StrictRiskOnly)
      StrategiesCarry::RiskMod01(pick.dir, trade_cfg, ss.risk_mult);

   UI_PublishDecision(pick.bd, ss);

   WarnNonCanonicalTradeExecutionDisabledOnce("EvaluateOneSymbol");
   DecisionTelemetry_MarkPassiveSkip("evaluate_one_symbol_trade_execution_disabled");
   UI_Render(S);
   return;

// 3) Risk sizing → plan
   OrderPlan plan;
   ZeroMemory(plan);
   if(!Risk::ComputeOrder(pick.dir, trade_cfg, ss, plan, pick.bd))
     {
      UI_Render(S);
      return;
     }

// 3.5) Enforce strat_mode gate (match ProcessSymbol behavior)
   const StrategyID sid = (StrategyID)pick.id;
   if(!Router_GateWinnerByMode(S, sid))
   {
      UI_Render(S);
      return;
   }

// 4) Execute
   Exec::Outcome ex = Exec::SendAsyncSymEx(sym, plan, trade_cfg, (StrategyID)pick.id, false);
   HintTradeDisabledOnce(ex);
   LogExecFailThrottled(sym, pick.dir, plan, ex, trade_cfg.slippage_points);
   if(ex.ok)
   {
    Policies::NotifyTradePlaced();

    // Record executed decisions for ML training (label computed later on new bars)
    if(g_ml_on && ML::IsActive())
      {
       ML::ObserveWinnerSample(sym, trade_cfg.tf_entry, pick.dir, trade_cfg, pick.bd, ss);

       // Outcome-aware snapshot (ticket→position bind occurs in OnTradeTransaction)
       #ifdef ML_HAS_TRADE_OUTCOME_HOOKS
       if(ex.ticket > 0)
          ML::TradeOpenIntent(ex.ticket, sym, trade_cfg.tf_entry, pick.dir, (StrategyID)pick.id, trade_cfg, pick.bd, ss, plan.price, plan.sl, plan.tp);
       #endif
      }
   }
   
   LogX::Exec(sym, pick.dir, plan.lots, plan.price, plan.sl, plan.tp,
              ex.ok, ex.retcode, ex.ticket, trade_cfg.slippage_points,
              ex.last_error, ex.last_error_text);
#ifdef TELEMETRY_HAS_TRADEPLAN
   string side = (pick.dir==DIR_BUY ? "BUY" : "SELL");
   Telemetry::TradePlan(sym, side, plan.lots, plan.price, plan.sl, plan.tp, ss.score);
#endif

   UI_Render(S);
  }

bool RuntimeMainChecklistSoftFallbackEnabled()
{
   const bool in_tester = (MQLInfoInteger(MQL_TESTER) != 0);

   if(InpMain_ChecklistSoftFallbackMode == 1)
      return false;

   if(InpMain_ChecklistSoftFallbackMode == 2)
      return true;

   // Auto mode:
   // tester  => enabled
   // live    => disabled
   return in_tester;
}

// ================================== Inputs → Settings mirror ==================================
// Keep this single source of truth so Router/Policies/ProcessSymbol all see the same flags.
void MirrorInputsToSettings(Settings &cfg)
{
   // ---- Router / Hard-gate knobs: use canonical underscored names ----
   #ifdef CFG_HAS_ENABLE_HARD_GATE
     cfg.enable_hard_gate = Inp_EnableHardGate;
   #endif
   #ifdef CFG_HAS_MIN_FEATURES_MET
     cfg.min_features_met = MathMax(0, Inp_MinFeaturesMet);
   #endif
   #ifdef CFG_HAS_REQUIRE_TREND_FILTER
     cfg.require_trend_filter = Inp_RequireTrendFilter;
   #endif
   #ifdef CFG_HAS_REQUIRE_ADX_REGIME
     cfg.require_adx_regime = Inp_RequireADXRegime;
   #endif
   #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
     cfg.require_struct_or_pattern_ob = Inp_RequireStructOrPatternOB;
   #endif
   #ifdef CFG_HAS_LONDON_LIQ_POLICY
     cfg.london_liquidity_policy = Inp_LondonLiquidityPolicy;
   #endif
   #ifdef CFG_HAS_ROUTER_FB_MIN
     cfg.router_fb_min = MathMin(MathMax(Inp_RouterFallbackMin, 0.0), 1.0);
   #endif

   // ---- Router diagnostics (kept) ----
   #ifdef CFG_HAS_ROUTER_DEBUG_LOG
     cfg.router_debug_log = InpRouterDebugLog;
   #endif
   #ifdef CFG_HAS_ROUTER_TOPK_LOG
     cfg.router_topk_log = MathMax(1, InpRouterTopKLog);
   #endif
   #ifdef CFG_HAS_ROUTER_FORCE_ONE
     cfg.router_force_one_normal_vol = InpRouterForceOneNormalVol;
   #endif
   #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
     int rem = InpRouterExecMode;
     if(rem < 0) rem = 0;
     if(rem > 1) rem = 1;
     cfg.router_eval_all_mode = rem;
   #endif
   
   // ---- Router confluence-only pool controls (optional) ----
   #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
     cfg.router_use_confl_pool = InpRouterUseConfluencePool;
   #endif
   #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
     double pw = InpRouterPoolBlendW;
     if(pw < 0.0) pw = 0.0;
     if(pw > 1.0) pw = 1.0;
     cfg.router_pool_blend_w = pw;
   #endif
   cfg.profile = InpProfile;
   
   #ifdef CFG_HAS_ML_THRESHOLD
      cfg.ml_threshold = InpML_Threshold;
   #endif

   #ifdef CFG_HAS_ML_SLTP_MULT
      cfg.ml_sltp_enable = InpML_SLTP_Enable;
   
      // Clamp + order-correct bounds (prevents inverted ranges)
      cfg.ml_sltp_sl_min = MathMax(0.10, InpML_SLMult_Min);
      cfg.ml_sltp_sl_max = MathMax(cfg.ml_sltp_sl_min, InpML_SLMult_Max);
      
      cfg.ml_sltp_tp_min = MathMax(0.10, InpML_TPMult_Min);
      cfg.ml_sltp_tp_max = MathMax(cfg.ml_sltp_tp_min, InpML_TPMult_Max);
   #endif

   #ifdef CFG_HAS_LONDON_LOCAL_MINUTES
     int mm_open=-1, mm_close=-1;
     if(!Config::_parse_hhmm(Inp_LondonStartLocal, mm_open))  mm_open  = 6*60;
     if(!Config::_parse_hhmm(Inp_LondonEndLocal,   mm_close)) mm_close = 10*60;
     cfg.london_local_open_min  = mm_open;
     cfg.london_local_close_min = mm_close;
   #endif

  // ---- Assets / TFs / cadence ----
  cfg.tf_entry = InpEntryTF; cfg.tf_h1=InpHTF_H1; cfg.tf_h4=InpHTF_H4; cfg.tf_d1=InpHTF_D1;
  // ---- ICT / Smart Money mirror (keeps legacy S aligned with router g_cfg) ----
  #ifdef CFG_HAS_TF_HTF
    cfg.tf_htf = InpTfHTF;
  #endif
  #ifdef CFG_HAS_RISK_PER_TRADE
    cfg.risk_per_trade = InpRiskPerTradePct;
  #endif
  #ifdef CFG_HAS_TRADE_DIRECTION_SELECTOR
    cfg.trade_direction_selector = InpTradeDirectionSelector;
  #endif
  #ifdef CFG_HAS_DIRECTION_BIAS_MODE
    cfg.direction_bias_mode = InpDirectionBiasMode;
  #endif

  #ifdef CFG_HAS_MODE_USE_SILVERBULLET
    cfg.mode_use_silverbullet = (InpEnable_SilverBulletMode ? 1 : 0);
  #endif
  #ifdef CFG_HAS_MODE_USE_PO3
    cfg.mode_use_po3 = (InpEnable_PO3Mode ? 1 : 0);
  #endif
  #ifdef CFG_HAS_MODE_ENFORCE_KILLZONE
    cfg.mode_enforce_killzone = (EA_EffectiveEnforceKillzone() ? 1 : 0);
  #endif
  #ifdef CFG_HAS_MODE_USE_ICT_BIAS
    cfg.mode_use_ICT_bias = (InpUseICTBias ? 1 : 0);
  #endif

  cfg.only_new_bar = InpOnlyNewBar; cfg.timer_ms = InpTimerMS;
  cfg.server_offset_min = InpServerOffsetMinutes;

  // ---- Risk core ----
  cfg.risk_pct = InpRiskPct; cfg.risk_cap_pct = InpRiskCapPct;
  
  #ifdef CFG_HAS_RISK_MULT_MAX
    cfg.risk_mult_max = _RiskMultMaxCapFromInputs();
  #endif
  
  // ---- Optional hard baseline override (Policies uses this for initial equity baseline) ----
  #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
    // Optional hard baseline override (Policies uses this for initial equity baseline)
    cfg.challenge_init_equity = MathMax(0.0, InpChallengeInitEquity);
  #endif
  
  cfg.min_sl_pips = InpMinSL_Pips; cfg.min_tp_pips = InpMinTP_Pips; cfg.max_sl_ceiling_pips = InpMaxSLCeiling_Pips;
  #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
    cfg.day_dd_limit_pct = InpDayDD_LimitPct;
  #endif
  cfg.max_daily_dd_pct = InpMaxDailyDD_Pct;
  
  // ---- Adaptive Daily DD (rolling peak) ----
  #ifdef CFG_HAS_ADAPTIVE_DD_ENABLE
    cfg.adaptive_dd_enable = InpAdaptiveDD_Enable;
  #endif
  #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
    cfg.adaptive_dd_window_days = MathMax(1, InpAdaptiveDD_WindowDays);
  #endif
  #ifdef CFG_HAS_ADAPTIVE_DD_PCT
    cfg.adaptive_dd_pct = InpAdaptiveDD_Pct;
  #endif
   
  // ---- Big-loss sizing reset (R-multiple latch via Policies) ----
  #ifdef CFG_HAS_BIGLOSS_RESET_ENABLE
    cfg.bigloss_reset_enable = InpBigLossReset_Enable;
  #endif
  #ifdef CFG_HAS_BIGLOSS_RESET_R
    cfg.bigloss_reset_r = MathMax(0.0, InpBigLossReset_R);
  #endif
  #ifdef CFG_HAS_BIGLOSS_RESET_MINS
    cfg.bigloss_reset_mins = MathMax(0, InpBigLossReset_Mins);
  #endif
  
  cfg.max_losses_day = InpMaxLossesDay; cfg.max_trades_day = InpMaxTradesDay;
  #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
     cfg.max_positions_per_symbol = MathMax(1, InpMaxPositionsPerSymbol);
  #endif
  #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
     cfg.max_positions_total = MathMax(0, InpMaxPositionsTotal);
  #endif
  cfg.max_spread_points = InpMaxSpreadPoints; cfg.slippage_points = InpSlippagePoints;

  // ---- Monthly profit target gate ----
  #ifdef CFG_HAS_MONTHLY_TARGET
    cfg.monthly_target_pct = MathMax(0.0, InpMonthlyTargetPct);
   
    #ifdef CFG_HAS_MONTHLY_TARGET_CYCLE_MODE
      int cm = InpMonthlyTargetCycleMode;
      if(cm < 0) cm = 0;
      if(cm > 1) cm = 1;
      cfg.monthly_target_cycle_mode = cm;
    #endif
   
    #ifdef CFG_HAS_MONTHLY_TARGET_BASE_MODE
      int mbm = InpMonthlyTargetBaseMode;
      if(mbm < 0) mbm = 0;
      if(mbm > 2) mbm = 2;
      cfg.monthly_target_base_mode = mbm;
    #endif
  #endif
  
  // ---- Sessions (legacy union) + Preset ----
  cfg.session_filter = InpSessionFilter;
  cfg.london_open_utc = InpLondonOpenUTC; cfg.london_close_utc = InpLondonCloseUTC;
  cfg.ny_open_utc = InpNYOpenUTC; cfg.ny_close_utc = InpNYCloseUTC;
  cfg.session_preset = InpSessionPreset;
  cfg.tokyo_close_utc = InpTokyoCloseUTC; cfg.sydney_open_utc = InpSydneyOpenUTC;

  // ---- News block + calendar scaling ----
  cfg.news_on = EA_EffectiveNewsOn(); cfg.block_pre_m = InpNewsBlockPreMins; cfg.block_post_m = InpNewsBlockPostMins;
  cfg.news_impact_mask = InpNewsImpactMask;
  #ifdef CFG_HAS_NEWS_BACKEND
      int nbm = InpNewsBackendMode;
      if(nbm < 0) nbm = 0;
      if(nbm > 2) nbm = 2;
      cfg.news_backend_mode = nbm;
  #endif
   
  #ifdef CFG_HAS_NEWS_MVP_NO_BLOCK
      cfg.news_mvp_no_block = InpNewsMVP_NoBlock;
  #endif
   
  #ifdef CFG_HAS_NEWS_FAILOVER_TO_CSV
      cfg.news_failover_to_csv = InpNewsFailoverToCSV;
  #endif
   
  #ifdef CFG_HAS_NEWS_NEUTRAL_ON_NO_DATA
      cfg.news_neutral_on_no_data = InpNewsNeutralOnNoData;
  #endif
  cfg.cal_lookback_mins = InpCal_LookbackMins; cfg.cal_hard_skip = InpCal_HardSkip;
  cfg.cal_soft_knee = InpCal_SoftKnee; cfg.cal_min_scale = InpCal_MinScale;

  // ---- ATR / TP-SL (quantile) ----
  cfg.atr_period = InpATR_Period;
  cfg.tp_quantile = InpTP_Quantile;
  cfg.atr_sl_mult = InpATR_SlMult;
  cfg.tp_minr_floor = InpTP_MinR_Floor;

  // ---- Position mgmt ----
  #ifdef CFG_HAS_PM_MODE
     cfg.pm_mode = InpPMMode;
  #endif
   
  #ifdef CFG_HAS_PM_ALLOW_DAILY_FLATTEN
     cfg.pm_allow_daily_flatten = InpPMAllowDailyFlatten;
  #endif
   
  #ifdef CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS
     cfg.pm_post_dd_cooldown_seconds = InpPM_PostDDCooldownSec;
  #endif
   
  cfg.be_enable = InpBE_Enable; cfg.be_at_R = InpBE_At_R; cfg.be_lock_pips = InpBE_Lock_Pips;
  cfg.trail_type = InpTrailType; cfg.trail_pips = InpTrailPips; cfg.trail_atr_mult = InpTrailATR_Mult;
  
  #ifdef CFG_HAS_TRAIL_AUTO_ADX_TF
     cfg.trail_auto_adx_tf = InpTrailAuto_ADX_TF;
   #endif
   #ifdef CFG_HAS_TRAIL_AUTO_ADX_PERIOD
     cfg.trail_auto_adx_period = InpTrailAuto_ADX_Period;
   #endif
   #ifdef CFG_HAS_TRAIL_AUTO_ADX_MIN
     cfg.trail_auto_adx_min = InpTrailAuto_ADX_Min;
   #endif
   
  cfg.p1_at_R = InpP1_At_R; cfg.p1_close_pct = InpP1_ClosePct; cfg.p2_at_R = InpP2_At_R; cfg.p2_close_pct = InpP2_ClosePct;
  cfg.partial_enable = (InpPartial_Enable ? 1 : 0);

  // ---- Base Confluence gate ----
  cfg.cf_min_needed = MathMax(0, InpConf_MinCount);
  cfg.cf_min_score  = MathMax(0.0, InpConf_MinScore);

  if(IsTesterRuntime())
  {
     cfg.cf_min_needed = 0;
     cfg.cf_min_score  = 0.0;
  }

  // ---- Base Confluence toggles ----
  cfg.cf_inst_zones       = InpCF_InstZones;
  cfg.cf_orderflow_delta  = InpCF_OrderFlowDelta;
  cfg.cf_orderblock_near  = InpCF_OrderBlockNear;
  cfg.cf_candle_pattern   = InpCF_CndlPattern;
  cfg.cf_chart_pattern    = InpCF_ChartPattern;
  cfg.cf_market_structure = InpCF_MarketStructure;
  cfg.cf_trend_regime     = InpCF_TrendRegime;
  cfg.cf_stochrsi         = InpCF_StochRSI;
  cfg.cf_macd             = InpCF_MACD;
  cfg.cf_correlation      = EA_EffectiveCFCorrelation();
  cfg.cf_news_ok          = InpCF_News;

  // --- Autochartist-style confluence ---
  cfg.auto_enable             = InpAuto_Enable;
  cfg.auto_scan_interval_sec  = InpAuto_ScanIntervalSec;
  cfg.auto_scan_lookback_bars = InpAuto_ScanLookbackBars;

  cfg.cf_autochartist_chart      = InpCF_AutoChart;
  cfg.cf_autochartist_fib        = InpCF_AutoFib;
  cfg.cf_autochartist_keylevels  = InpCF_AutoKeyLevels;
  cfg.cf_autochartist_volatility = InpCF_AutoVolatility;

  cfg.w_autochartist_chart      = InpW_AutoChart;
  cfg.w_autochartist_fib        = InpW_AutoFib;
  cfg.w_autochartist_keylevels  = InpW_AutoKeyLevels;
  cfg.w_autochartist_volatility = InpW_AutoVolatility;

  cfg.auto_chart_min_quality = InpAuto_Chart_MinQuality;
  cfg.auto_chart_pivot_L     = InpAuto_Chart_PivotL;
  cfg.auto_chart_pivot_R     = InpAuto_Chart_PivotR;

  cfg.auto_fib_min_quality = InpAuto_Fib_MinQuality;

  cfg.auto_keylevel_min_touches  = InpAuto_Key_MinTouches;
  cfg.auto_keylevel_cluster_atr  = InpAuto_Key_ClusterATR;
  cfg.auto_keylevel_approach_atr = InpAuto_Key_ApproachATR;

  cfg.auto_vol_lookback_days   = InpAuto_Vol_LookbackDays;
  cfg.auto_vol_horizon_minutes = InpAuto_Vol_HorizonMin;
  cfg.auto_vol_min_range_atr   = InpAuto_Vol_MinRangeATR;
  
   #ifdef CFG_HAS_AUTOVOL_SETTINGS
    cfg.auto_vol_cache_hours       = InpAutoVol_CacheHours;
    cfg.auto_vol_adr_lookback_days = InpAutoVol_ADRLookbackDays;
    cfg.auto_vol_ret_lookback_d1   = InpAutoVol_RetLookbackD1;
  #endif

  cfg.auto_risk_scale_enable = InpAuto_RiskScale_Enable;
  cfg.auto_risk_scale_floor  = InpAuto_RiskScale_Floor;
  cfg.auto_risk_scale_cap    = InpAuto_RiskScale_Cap;

  // ---- Base weights (single source) ----
  cfg.w_inst_zones = InpW_InstZones;
  cfg.w_orderflow_delta = InpW_OrderFlowDelta;
  cfg.w_orderblock_near = InpW_OrderBlockNear;
  cfg.w_candle_pattern = InpW_CndlPattern;
  cfg.w_chart_pattern  = InpW_ChartPattern;
  cfg.w_market_structure = InpW_MarketStructure;
  cfg.w_trend_regime = InpW_TrendRegime;
  cfg.w_stochrsi = InpW_StochRSI;          // also reused by Extra
  cfg.w_macd     = InpW_MACD;              // also reused by Extra
  cfg.w_correlation = InpW_Correlation;    // also reused by Extra
  cfg.w_news       = InpW_News;            // also reused by Extra

   // ---- Extra (post-main) gate ----
   cfg.extra_enable     = InpCF_Extra_Enable;
   cfg.extra_min_needed = MathMax(0, InpExtra_MinScore);
   cfg.extra_min_score  = MathMax(0.0, InpExtra_MinGateScore);

  // ---- Extras toggles + weights ----
  cfg.extra_volume_footprint = InpExtra_VolumeFootprint;
  cfg.w_volume_footprint     = InpW_VolumeFootprint;

  cfg.cf_liquidity       = InpCF_Liquidity;     cfg.w_liquidity    = InpW_Liquidity;
  cfg.cf_vsa_increase    = InpCF_VSAIncrease;   cfg.w_vsa_increase = InpW_VSAIncrease;

  cfg.extra_stochrsi     = InpExtra_StochRSI;   // weight reuses base
  cfg.extra_macd         = InpExtra_MACD;       // weight reuses base
  cfg.extra_adx_regime   = InpExtra_ADXRegime;  cfg.w_adx_regime = InpW_ADXRegime;
  cfg.extra_correlation  = EA_EffectiveExtraCorrelation();// weight reuses base
  cfg.extra_dom_imbalance = InpExtra_DOMImbalance;
  cfg.extra_news         = InpExtra_News;       // weight reuses base

  // ---- ADX / StochRSI / MACD params ----
  cfg.adx_period = MathMax(1, InpADX_Period);
  cfg.adx_min_trend = InpADX_Min;
  cfg.adx_upper     = InpADX_Upper;

  cfg.rsi_period = MathMax(1, InpStochRSI_RSI_Period);
  cfg.stoch_k    = MathMax(1, InpStochRSI_K_Period);
  cfg.stoch_d    = MathMax(1, InpStochRSI_D_Period);
  const double ob01 = (InpStochRSI_OB/100.0);
  const double os01 = (InpStochRSI_OS/100.0);
  cfg.stoch_ob = MathMin(MathMax(ob01, 0.0), 1.0);
  cfg.stoch_os = MathMin(MathMax(os01, 0.0), 1.0);

  cfg.macd_fast   = (InpMACD_Fast  > 0 ? InpMACD_Fast  : MathMax(1, InpMACD_FastEMA));
  cfg.macd_slow   = (InpMACD_Slow  > 0 ? InpMACD_Slow  : MathMax(cfg.macd_fast+1, InpMACD_SlowEMA));
  cfg.macd_signal = MathMax(1, InpMACD_Signal);

  // ---- Correlation ----
  cfg.corr_ref_symbol = InpCorr_RefSymbol;
  cfg.corr_lookback   = (InpCorr_Lookback>0 ? InpCorr_Lookback : 200);
  cfg.corr_min_abs    = MathMin(MathMax(InpCorr_MinAbs, 0.0), 1.0);
  cfg.corr_ema_tf     = InpCorr_TF;
  cfg.corr_ema_fast   = 21;
  cfg.corr_ema_slow   = 50;
  cfg.corr_softveto_enable = InpCorrSoftVeto_Enable;

  // ---- VWAP / patterns ----
  cfg.vwap_z_edge = InpVWAP_Z_Edge; cfg.vwap_z_avoidtrend = InpVWAP_Z_AvoidTrend;
  cfg.pattern_lookback = InpPattern_Lookback; cfg.pattern_tau = InpPattern_Tau;
  cfg.vwap_lookback = InpVWAP_Lookback; cfg.vwap_sigma = InpVWAP_Sigma;

  // ---- Feature toggles ----
  cfg.vsa_enable = InpVSA_Enable;
  cfg.vsa_penalty_max = InpVSA_PenaltyMax;

  cfg.structure_enable = InpStructure_Enable;
  #ifdef CFG_HAS_STRUCT_VETO
    cfg.struct_veto_on = InpStructVetoOn;
  #endif

  cfg.liquidity_enable = InpLiquidity_Enable;

  // ---- Misc ----
  cfg.trade_selector = InpTradeSelector;
  #ifdef CFG_HAS_UMBRELLA
    cfg.umbrella_mode = (int)InpUmbrella;
  #endif
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyManualWeightsAndThrottles()
  {
// Weights
   StratReg::SetWeights(STRAT_TREND_VWAP,                 InpW_Trend,          InpW_Trend);
   StratReg::SetWeights(STRAT_TREND_BOSCONTINUATION,      InpW_TrendBOS,       InpW_TrendBOS);
   StratReg::SetWeights(STRAT_MR_VWAPBAND,                InpW_MR,             InpW_MR);
   StratReg::SetWeights((StrategyID)ST_RANGENR7IB_ID,     InpW_MRRange,        InpW_MRRange);
   StratReg::SetWeights((StrategyID)ST_SQUEEZE_ID,        InpW_Squeeze,        InpW_Squeeze);
   StratReg::SetWeights((StrategyID)STRAT_BREAKOUT_ORB,   InpW_ORB,            InpW_ORB);
   StratReg::SetWeights((StrategyID)ST_SWEEPCHOCH_ID,     InpW_SweepCHOCH,     InpW_SweepCHOCH);
   StratReg::SetWeights((StrategyID)ST_VSACLIMAXFADE_ID,  InpW_VSAClimaxFade,  InpW_VSAClimaxFade);
   StratReg::SetWeights((StrategyID)ST_CORRDIV_ID,        InpW_CorrDiv,        InpW_CorrDiv);
   StratReg::SetWeights((StrategyID)ST_PAIRSLITE_ID,      InpW_PairsLite,      InpW_PairsLite);
   StratReg::SetWeights((StrategyID)ST_NEWS_DEV_ID,       InpW_NewsDeviation,  InpW_NewsDeviation);
   StratReg::SetWeights((StrategyID)ST_NEWS_POSTFADE_ID,  InpW_NewsPostFade,   InpW_NewsPostFade);

// Throttles
   StratReg::SetThrottleSeconds(STRAT_TREND_VWAP,                 MathMax(0, InpThrottle_Trend_Sec));
   StratReg::SetThrottleSeconds(STRAT_TREND_BOSCONTINUATION,      MathMax(0, InpThrottle_TrendBOS_Sec));
   StratReg::SetThrottleSeconds(STRAT_MR_VWAPBAND,                MathMax(0, InpThrottle_MR_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_RANGENR7IB_ID,     MathMax(0, InpThrottle_MRRange_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_SQUEEZE_ID,        MathMax(0, InpThrottle_Sq_Sec));
   StratReg::SetThrottleSeconds((StrategyID)STRAT_BREAKOUT_ORB,   MathMax(0, InpThrottle_ORB_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_SWEEPCHOCH_ID,     MathMax(0, InpThrottle_SweepCHOCH_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_VSACLIMAXFADE_ID,  MathMax(0, InpThrottle_VSAClimaxFade_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_CORRDIV_ID,        MathMax(0, InpThrottle_CorrDiv_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_PAIRSLITE_ID,      MathMax(0, InpThrottle_PairsLite_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_NEWS_DEV_ID,       MathMax(0, InpThrottle_NewsDev_Sec));
   StratReg::SetThrottleSeconds((StrategyID)ST_NEWS_POSTFADE_ID,  MathMax(0, InpThrottle_NewsPost_Sec));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyProfileSpecToRegistry(const Config::ProfileSpec &ps)
  {
// Weights
   StratReg::SetWeights(STRAT_TREND_VWAP,                 ps.w_trend,       ps.w_trend);
   StratReg::SetWeights(STRAT_TREND_BOSCONTINUATION,      ps.w_trend_bos,   ps.w_trend_bos);
   StratReg::SetWeights(STRAT_MR_VWAPBAND,                ps.w_mr,          ps.w_mr);
   StratReg::SetWeights((StrategyID)ST_RANGENR7IB_ID,     ps.w_mr_range,    ps.w_mr_range);
   StratReg::SetWeights((StrategyID)ST_SQUEEZE_ID,        ps.w_squeeze,     ps.w_squeeze);
   StratReg::SetWeights((StrategyID)STRAT_BREAKOUT_ORB,   ps.w_orb,         ps.w_orb);
   StratReg::SetWeights((StrategyID)ST_SWEEPCHOCH_ID,     ps.w_sweepchoch,  ps.w_sweepchoch);
   StratReg::SetWeights((StrategyID)ST_VSACLIMAXFADE_ID,  ps.w_vsa,         ps.w_vsa);
   StratReg::SetWeights((StrategyID)ST_CORRDIV_ID,        ps.w_corrdiv,     ps.w_corrdiv);
   StratReg::SetWeights((StrategyID)ST_PAIRSLITE_ID,      ps.w_pairslite,   ps.w_pairslite);
   StratReg::SetWeights((StrategyID)ST_NEWS_DEV_ID,       ps.w_news_dev,    ps.w_news_dev);
   StratReg::SetWeights((StrategyID)ST_NEWS_POSTFADE_ID,  ps.w_news_post,   ps.w_news_post);

// Throttles
   StratReg::SetThrottleSeconds(STRAT_TREND_VWAP,                 MathMax(0, ps.th_trend));
   StratReg::SetThrottleSeconds(STRAT_TREND_BOSCONTINUATION,      MathMax(0, ps.th_trend_bos));
   StratReg::SetThrottleSeconds(STRAT_MR_VWAPBAND,                MathMax(0, ps.th_mr));
   StratReg::SetThrottleSeconds((StrategyID)ST_RANGENR7IB_ID,     MathMax(0, ps.th_mr_range));
   StratReg::SetThrottleSeconds((StrategyID)ST_SQUEEZE_ID,        MathMax(0, ps.th_squeeze));
   StratReg::SetThrottleSeconds((StrategyID)STRAT_BREAKOUT_ORB,   MathMax(0, ps.th_orb));
   StratReg::SetThrottleSeconds((StrategyID)ST_SWEEPCHOCH_ID,     MathMax(0, ps.th_sweepchoch));
   StratReg::SetThrottleSeconds((StrategyID)ST_VSACLIMAXFADE_ID,  MathMax(0, ps.th_vsa));
   StratReg::SetThrottleSeconds((StrategyID)ST_CORRDIV_ID,        MathMax(0, ps.th_corrdiv));
   StratReg::SetThrottleSeconds((StrategyID)ST_PAIRSLITE_ID,      MathMax(0, ps.th_pairslite));
   StratReg::SetThrottleSeconds((StrategyID)ST_NEWS_DEV_ID,       MathMax(0, ps.th_news_dev));
   StratReg::SetThrottleSeconds((StrategyID)ST_NEWS_POSTFADE_ID,  MathMax(0, ps.th_news_post));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BootRegistry_NoProfile(const Settings &cfg)
  {
   StratReg::Init(cfg);
   //StratReg::AutoRegisterBuiltins();
   
   // Scenario prune: disable strategies that don't belong to the selected test case
   {
     int ids[];
     StratReg::FillRegisteredIds(ids, /*only_enabled=*/false);
     for(int k=ArraySize(ids)-1; k>=0; --k)
     {
       string nm="";
       StratReg::GetStrategyNameById((StrategyID)ids[k], nm);  // internal name like "trend_vwap"
       if(!TesterCases::AllowStrategyIdForScenario(InpTestCase, nm))
         StratReg::Enable((StrategyID)ids[k], false);
     }
   }

   // Enable/disable
   StratReg::Enable(STRAT_TREND_VWAP,                 InpEnableTrend);
   StratReg::Enable(STRAT_TREND_BOSCONTINUATION,      InpEnableTrendBOS);
   StratReg::Enable(STRAT_MR_VWAPBAND,                InpEnableMR);
   StratReg::Enable((StrategyID)ST_RANGENR7IB_ID,     InpEnableMRRange);
   StratReg::Enable((StrategyID)ST_SQUEEZE_ID,        InpEnableSqueeze);
   StratReg::Enable((StrategyID)STRAT_BREAKOUT_ORB,   InpEnableORB);
   StratReg::Enable((StrategyID)ST_SWEEPCHOCH_ID,     InpEnableSweepCHOCH);
   StratReg::Enable((StrategyID)ST_VSACLIMAXFADE_ID,  InpEnableVSAClimaxFade);
   StratReg::Enable((StrategyID)ST_CORRDIV_ID,        InpEnableCorrDiv);
   StratReg::Enable((StrategyID)ST_PAIRSLITE_ID,      InpEnablePairsLite);
   StratReg::Enable((StrategyID)ST_NEWS_DEV_ID,       InpEnableNewsDeviation);
   StratReg::Enable((StrategyID)ST_NEWS_POSTFADE_ID,  InpEnableNewsPostFade);

   // Apply manual weights/throttles
   ApplyManualWeightsAndThrottles();

   // Router
   ApplyRouterConfig();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BootRegistry_WithProfile(const Settings &cfg, const Config::ProfileSpec &ps)
  {
   StratReg::Init(cfg);
   // Scenario prune: disable strategies that don't belong to the selected test case
   {
      int ids[];
      StratReg::FillRegisteredIds(ids, /*only_enabled=*/false);
      for(int k=ArraySize(ids)-1; k>=0; --k)
      {
         string nm="";
         StratReg::GetStrategyNameById((StrategyID)ids[k], nm);
         if(!TesterCases::AllowStrategyIdForScenario(InpTestCase, nm))
            StratReg::Enable((StrategyID)ids[k], false);
      }
   }
   //StratReg::AutoRegisterBuiltins();

// Enable/disable as usual (profile defines weights/throttles; toggles remain inputs)
   StratReg::Enable(STRAT_TREND_VWAP,                 InpEnableTrend);
   StratReg::Enable(STRAT_TREND_BOSCONTINUATION,      InpEnableTrendBOS);
   StratReg::Enable(STRAT_MR_VWAPBAND,                InpEnableMR);
   StratReg::Enable((StrategyID)ST_RANGENR7IB_ID,     InpEnableMRRange);
   StratReg::Enable((StrategyID)ST_SQUEEZE_ID,        InpEnableSqueeze);
   StratReg::Enable((StrategyID)STRAT_BREAKOUT_ORB,   InpEnableORB);
   StratReg::Enable((StrategyID)ST_SWEEPCHOCH_ID,     InpEnableSweepCHOCH);
   StratReg::Enable((StrategyID)ST_VSACLIMAXFADE_ID,  InpEnableVSAClimaxFade);
   StratReg::Enable((StrategyID)ST_CORRDIV_ID,        InpEnableCorrDiv);
   StratReg::Enable((StrategyID)ST_PAIRSLITE_ID,      InpEnablePairsLite);
   StratReg::Enable((StrategyID)ST_NEWS_DEV_ID,       InpEnableNewsDeviation);
   StratReg::Enable((StrategyID)ST_NEWS_POSTFADE_ID,  InpEnableNewsPostFade);

// Apply profile first
   ApplyProfileSpecToRegistry(ps);

// Optionally allow manual overrides after profile application
   if(InpProfileAllowManual)
      ApplyManualWeightsAndThrottles();

// Router (use profile’s hints if enabled)
   ApplyRouterConfig_Profile(ps);
  }

// -------------- Router “Evaluate-All” (collect top candidates) --------------
struct _Cand { StrategyID id; Direction dir; StratScore ss; ConfluenceBreakdown bd; };
int  _cmp_desc(const _Cand &a, const _Cand &b) { if(a.ss.score>b.ss.score) return -1; if(a.ss.score<b.ss.score) return 1; return 0; }

// --- Light debug helpers (guarded by InpDebug) ---
string _DirStr(const Direction d)
  {
   return (d==DIR_BUY ? "BUY" : (d==DIR_SELL ? "SELL" : "NA"));
  }

void _LogGateBlockedEx(const string origin,
                       const string sym,
                       const int reason,
                       const string detail,
                       const string precedence_override,
                       const int pol_reason,
                       const string pol_detail,
                       const string micro_detail)
{
   if(!InpDebug)
      return;

   static datetime last_emit = 0;
   const datetime now = TimeCurrent();
   if(now == last_emit)
      return; // one line max per second-tick
   last_emit = now;

   string precedence = precedence_override;
   if(StringLen(precedence) <= 0)
      precedence = _GatePrecedenceTag(origin, reason, pol_reason);

   const string full_detail =
      _MergeGateBlockedDetail(detail, pol_reason, pol_detail, micro_detail);

   LogX::Info(StringFormat("[WhyNoTrade] origin=%s stage=gate precedence=%s sym=%s reason=%d(%s) detail=%s",
                           origin,
                           precedence,
                           sym,
                           reason,
                           _GateReasonStr(reason),
                           full_detail));
}

void _LogGateBlocked(const string origin,
                     const string sym,
                     const int reason,
                     const string detail)
{
   _LogGateBlockedEx(origin, sym, reason, detail, "", 0, "", "");
}

void _LogRiskReject(const string origin,
                    const string sym,
                    const StrategyID id,
                    const Direction dir,
                    const StratScore &ss)
  {
   if(!InpDebug)
      return;

   static datetime last_emit = 0;
   const datetime now = TimeCurrent();
   if(now == last_emit)
      return;
   last_emit = now;

   const int code = Risk::LastRejectCode();
   const string why = Risk::LastRejectReason();

   LogX::Info(StringFormat("[WhyNoTrade] origin=%s stage=risk sym=%s id=%d dir=%s score=%.3f code=%d reason=%s",
                           origin, sym, (int)id, _DirStr(dir), ss.score, code, why));
  }

void _LogExecReject(const string origin,
                    const string sym,
                    const StrategyID id,
                    const Direction dir,
                    const StratScore &ss,
                    const OrderPlan &plan,
                    const Exec::Outcome &ex)
  {
   if(!InpDebug)
      return;
   if(ex.ok)
      return;

   static datetime last_emit = 0;
   const datetime now = TimeCurrent();
   if(now == last_emit)
      return;
   last_emit = now;

   LogX::Info(StringFormat("[WhyNoTrade] origin=%s stage=exec sym=%s id=%d dir=%s score=%.3f retcode=%u err=%d(%s) lots=%.2f",
                           origin, sym, (int)id, _DirStr(dir), ss.score,
                           ex.retcode, ex.last_error, LogX::San(ex.last_error_text), plan.lots));

   LogX::Info(StringFormat("[WhyNoTrade] origin=%s stage=exec_gate sym=%s pf=%d ssg=%d loc=%d exg=%d rkg=%d internal=%.2f depthFade=%.2f",
                           origin,
                           sym,
                           (ex.pre_filter_pass ? 1 : 0),
                           (ex.signal_stack_gate_pass ? 1 : 0),
                           (ex.location_pass ? 1 : 0),
                           (ex.execution_gate_pass ? 1 : 0),
                           (ex.risk_gate_pass ? 1 : 0),
                           ex.internalisation01,
                           ex.depth_fade01));
  }

// Throttled logger: avoid spamming every tick
void _LogCandidateDrop(const string origin,
                       const StrategyID id,
                       const Direction dir,
                       const StratScore &ss,
                       const ConfluenceBreakdown &bd,
                       const double min_sc)
  {
   if(!InpDebug)
      return;
   static datetime last_emit = 0;
   const datetime now = TimeCurrent();
   if(now == last_emit)
      return;     // one line max per second-tick
   last_emit = now;

   string why = "unknown_drop";
   if(bd.veto)                 why = StringFormat("veto(mask=%d)", (int)bd.veto_mask);
   else if(!ss.eligible)       why = "ineligible";
   else if(ss.score < min_sc)  why = "below_min_score";
   
   LogX::Info(StringFormat(
                 "[WhyNoTrade] origin=%s why=%s id=%d dir=%s eligible=%d score=%.3f min=%.2f veto=%d mask=%d | meta=%s",
                 origin, why, (int)id, _DirStr(dir),
                 (int)ss.eligible, ss.score, min_sc,
                 (int)bd.veto, (int)bd.veto_mask, bd.meta));
  }

string _BuildIntentDropDetail(const StrategyID id,
                              const Direction dir,
                              const StratScore &ss,
                              const ConfluenceBreakdown &bd,
                              const double min_sc,
                              const string why)
  {
   return StringFormat("why=%s id=%d dir=%s eligible=%d score=%.3f min_sc=%.3f bd.veto=%d veto_mask=%d meta=%s",
                       why,
                       (int)id,
                       _DirStr(dir),
                       (int)ss.eligible,
                       ss.score,
                       min_sc,
                       (int)bd.veto,
                       (int)bd.veto_mask,
                       LogX::San(bd.meta));
  }

void _EmitIntentDropInfo(const string sym,
                         const StrategyID id,
                         const Direction dir,
                         const StratScore &ss,
                         const ConfluenceBreakdown &bd,
                         const double min_sc,
                         const string why)
  {
   static datetime last_emit = 0;
   static string   last_key  = "";

   const datetime now = TimeCurrent();
   const string detail = _BuildIntentDropDetail(id, dir, ss, bd, min_sc, why);
   const string key =
      sym + "|" +
      IntegerToString((int)id) + "|" +
      _DirStr(dir) + "|" +
      why + "|" +
      detail;

   if(now == last_emit && key == last_key)
      return;

   last_emit = now;
   last_key  = key;

   LogX::Info(StringFormat("[IntentDrop] sym=%s %s", sym, detail));
   TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_PICK_DROP, detail, (int)id, dir, ss.score);
  }

bool PickPassesIntentGate(const string sym,
                          const StratReg::RoutedPick &pick,
                          const double min_sc,
                          string &why_out,
                          string &detail_out,
                          const bool emit_drop_info)
  {
   why_out = "";
   detail_out = "";

   if(!pick.ok && (int)pick.id <= 0)
     {
      why_out = "no_pick";
      return false;
     }

   if(pick.bd.veto)
      why_out = "veto";
   else if(!pick.ss.eligible)
   {
      if(IsTesterRuntime() && pick.ss.score > 0.0)
         return true;
      why_out = "ineligible";
   }
   else if(pick.ss.score < min_sc)
      why_out = "below_min_score";
   else
      return true;

   detail_out = _BuildIntentDropDetail(pick.id, pick.dir, pick.ss, pick.bd, min_sc, why_out);

   if(emit_drop_info)
      _EmitIntentDropInfo(sym, pick.id, pick.dir, pick.ss, pick.bd, min_sc, why_out);

   return false;
  }

// Echo static thresholds once at startup (useful context in logs)
void _LogThresholdsOnce(const Settings &cfg)
  {
   if(!InpDebug)
      return;
   static bool done=false;
   if(done)
      return;
   done=true;

   const double resolved_min = EA_RouterResolvedMinScore();
   const int    resolved_cap = EA_RouterResolvedMaxStrats();
   
   LogX::Info(StringFormat(
                 "[Thresholds] router_min=%.2f max_strats=%d vwap_z_edge=%.2f vwap_z_avoidtrend=%.2f vwap_sigma=%.2f patt_lookback=%d",
                 resolved_min,
                 resolved_cap,
                 cfg.vwap_z_edge, cfg.vwap_z_avoidtrend, cfg.vwap_sigma, cfg.pattern_lookback));
                 
   #ifdef CFG_HAS_NEWS_BACKEND
   LogX::Info(StringFormat("News cfg: on=%s backend=%d mvp_no_block=%s failover_csv=%s neutral_no_data=%s",
                           cfg.news_on ? "true" : "false",
                           cfg.news_backend_mode,
   #ifdef CFG_HAS_NEWS_MVP_NO_BLOCK
                           cfg.news_mvp_no_block ? "true" : "false",
   #else
                           "n/a",
   #endif
   #ifdef CFG_HAS_NEWS_FAILOVER_TO_CSV
                           cfg.news_failover_to_csv ? "true" : "false",
   #else
                           "n/a",
   #endif
   #ifdef CFG_HAS_NEWS_NEUTRAL_ON_NO_DATA
                           cfg.news_neutral_on_no_data ? "true" : "false"
   #else
                           "n/a"
   #endif
                           ));
   #endif
  }

// Collect from all enabled strategies using registry’s ComputeOne and router thresholds.
bool RouteRegistryAll(const Settings &cfg, StratReg::RoutedPick &pick, string &top_str)
  {
   ZeroMemory(pick);
   top_str = "";

   const double min_sc  = EA_RouterResolvedMinScore();
   const int    cap_top = EA_RouterResolvedMaxStrats();

   int ids[];
   ArrayResize(ids, 12);
   int k=0;
   ids[k++]=STRAT_TREND_VWAP;
   ids[k++]=STRAT_TREND_BOSCONTINUATION;
   ids[k++]=STRAT_MR_VWAPBAND;
   ids[k++]=(int)ST_RANGENR7IB_ID;
   ids[k++]=(int)ST_SQUEEZE_ID;
   ids[k++]=(int)STRAT_BREAKOUT_ORB;
   ids[k++]=(int)ST_SWEEPCHOCH_ID;
   ids[k++]=(int)ST_VSACLIMAXFADE_ID;
   ids[k++]=(int)ST_CORRDIV_ID;
   ids[k++]=(int)ST_PAIRSLITE_ID;
   ids[k++]=(int)ST_NEWS_DEV_ID;
   ids[k++]=(int)ST_NEWS_POSTFADE_ID;

   _Cand pool[64];
   int n=0;

// Evaluate BUY/SELL per trade selector
   for(int i=0;i<k;i++)
     {
      if(cfg.trade_selector!=TRADE_SELL_ONLY)
        {
         StratScore ss;
         ConfluenceBreakdown bd;
         if(StratReg::ComputeOne((StrategyID)ids[i], DIR_BUY, cfg, ss, bd, min_sc))
           {
            if(!bd.veto && ss.eligible && ss.score>=min_sc)
              { pool[n].id=(StrategyID)ids[i]; pool[n].dir=DIR_BUY; pool[n].ss=ss; pool[n].bd=bd; n++; }
            else
              { _LogCandidateDrop("registry_all", (StrategyID)ids[i], DIR_BUY, ss, bd, min_sc); }
           }
        }
      if(cfg.trade_selector!=TRADE_BUY_ONLY)
        {
         StratScore ss;
         ConfluenceBreakdown bd;
         if(StratReg::ComputeOne((StrategyID)ids[i], DIR_SELL, cfg, ss, bd, min_sc))
           {
            if(!bd.veto && ss.eligible && ss.score>=min_sc)
              { pool[n].id=(StrategyID)ids[i]; pool[n].dir=DIR_SELL; pool[n].ss=ss; pool[n].bd=bd; n++; }
            else
              { _LogCandidateDrop("registry_all", (StrategyID)ids[i], DIR_SELL, ss, bd, min_sc); }
           }
        }
     }

   if(n<=0)
   {
      TraceNoTrade(_Symbol, TS_ROUTER, TR_ROUTER_NO_CAND,
                   "RouteRegistryAll: no candidates survived thresholds");
      return false;
   }

// Sort by score desc
   for(int i=0;i<n-1;i++)
     {
      int best=i;
      for(int j=i+1;j<n;j++)
         if(_cmp_desc(pool[j], pool[best])<0)
            best=j;
      if(best!=i)
        {
         _Cand t=pool[i];
         pool[i]=pool[best];
         pool[best]=t;
        }
     }

// Compose top string (for debugging)
   const int show = MathMin(n, MathMax(1, MathMin(3, cap_top)));
   for(int i=0;i<show;i++)
     {
      if(i>0)
         top_str += " | ";
      top_str += StringFormat("#%d id=%d dir=%s sc=%.3f",
                              i+1, (int)pool[i].id, (pool[i].dir==DIR_BUY?"B":"S"), pool[i].ss.score);
     }

// Pick best
   pick.ok  = true;
   pick.id  = pool[0].id;
   pick.dir = pool[0].dir;
   pick.ss  = pool[0].ss;
   pick.bd  = pool[0].bd;

   StratReg::Stamp(pick.id, pick.dir);
   LogX::Decision(_Symbol, pick.id, pick.dir, pick.ss, pick.bd, 0, "router=all");
   return true;
  }

// Registry routing (legacy single-pick helpers kept for fallback)
bool RouteRegistryPick(const Settings &cfg, StratReg::RoutedPick &pick)
  {
   ZeroMemory(pick);
   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   if(rc.select_mode==SEL_WEIGHTED)
     {
      if(!StratReg::EvaluateAggregateWeighted(cfg, pick))
         return false;
     }
   else
     {
      int ids[];
      ArrayResize(ids, 12);
      int k=0;
      ids[k++]=STRAT_TREND_VWAP;
      ids[k++]=STRAT_TREND_BOSCONTINUATION;
      ids[k++]=STRAT_MR_VWAPBAND;
      ids[k++]=(int)ST_RANGENR7IB_ID;
      ids[k++]=(int)ST_SQUEEZE_ID;
      ids[k++]=(int)STRAT_BREAKOUT_ORB;
      ids[k++]=(int)ST_SWEEPCHOCH_ID;
      ids[k++]=(int)ST_VSACLIMAXFADE_ID;
      ids[k++]=(int)ST_CORRDIV_ID;
      ids[k++]=(int)ST_PAIRSLITE_ID;
      ids[k++]=(int)ST_NEWS_DEV_ID;
      ids[k++]=(int)ST_NEWS_POSTFADE_ID;

      if(!StratReg::EvaluateManySelectBest(ids, k, cfg, pick))
         return false;
     }
   LogX::Decision(_Symbol, pick.id, pick.dir, pick.ss, pick.bd, 0, "router=registry");
   return true;
  }

// Manual regime split as a fallback when registry routing is off
bool RouteManualRegimePick(const Settings &cfg, StratReg::RoutedPick &pick)
  {
   ZeroMemory(pick);
   const StrategyMode sm = Config::CfgStrategyMode(cfg);
   if(sm == STRAT_MAIN_ONLY)
      return RouteMainOnlyPick(cfg, pick);
   
   const double reg    = RegimeX::TrendQuality(_Symbol, cfg.tf_entry, 60);
   const double reg_th = (InpRegimeThreshold>0.0 ? InpRegimeThreshold : 0.55);
   const StrategyID choice_id = (reg>=reg_th ? STRAT_TREND_VWAP : STRAT_MR_VWAPBAND);

   StratScore sb, ss;
   ConfluenceBreakdown bb, bs;
   const double min_sc = EA_RouterResolvedMinScore();

   bool okB=false, okS=false;
   if(cfg.trade_selector!=TRADE_SELL_ONLY)
      okB = StratReg::ComputeOne(choice_id, DIR_BUY,  cfg, sb, bb, min_sc);
   if(cfg.trade_selector!=TRADE_BUY_ONLY)
      okS = StratReg::ComputeOne(choice_id, DIR_SELL, cfg, ss, bs, min_sc);

   if(!okB && !okS)
      return false;

   double scB = (okB?sb.score:0.0);
   double scS = (okS?ss.score:0.0);

   if(scB >= scS && scB>=min_sc)
     {
      pick.ok=true;
      pick.id=choice_id;
      pick.dir=DIR_BUY;
      pick.ss=sb;
      pick.bd=bb;
     }
   else
      if(scS>scB && scS>=min_sc)
        {
         pick.ok=true;
         pick.id=choice_id;
         pick.dir=DIR_SELL;
         pick.ss=ss;
         pick.bd=bs;
        }
      else
         return false;

   StratReg::Stamp(pick.id, pick.dir);
   LogX::Decision(_Symbol, pick.id, pick.dir, pick.ss, pick.bd, 1, "router=manual_regime");
   return true;
  }

//+------------------------------------------------------------------+
void ApplyMetaLayers(Direction dir, StratScore &ss, ConfluenceBreakdown &bd)
  {
   if(g_calm_mode)
      ss.risk_mult *= 0.60;
  }

// ------------ Multi-symbol helpers -------------
void ParseAssetList(const string raw, string &out_syms[])
  {
   ArrayResize(out_syms,0);
   string s = raw;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s)==0 || s=="CURRENT")
     {
      ArrayResize(out_syms,1);
      out_syms[0] = _Symbol;
      return;
     }
   StringReplace(s, ",", " ");
   StringReplace(s, ";", " ");
   while(StringFind(s,"  ")>=0)
      StringReplace(s,"  "," ");
   int pos=0, start=0, n=0;
   while(true)
     {
      pos = StringFind(s, " ", start);
      string tok = (pos<0 ? StringSubstr(s, start) : StringSubstr(s, start, pos-start));
      StringTrimLeft(tok);
      StringTrimRight(tok);
      if(StringLen(tok)>0)
        {
         SymbolSelect(tok, true);
         ArrayResize(out_syms, n+1);
         out_syms[n++] = tok;
        }
      if(pos<0)
         break;
      start = pos+1;
     }
  }

//+------------------------------------------------------------------+
int IndexOfSymbol(const string sym)
  {
   for(int i=0;i<g_symCount;i++)
      if(g_symbols[i]==sym)
         return i;
   return -1;
  }

// Per-symbol closed-bar gate (entry timeframe)
bool NewBarFor(const string sym, const ENUM_TIMEFRAMES tf)
  {
   const datetime t0 = iTime(sym, tf, 0);
   if(t0<=0)
      return false;
   const datetime closed = iTime(sym, tf, 1);
   int idx = IndexOfSymbol(sym);
   if(idx<0)
      return false;

   if(g_lastBarTime[idx] == 0)
     {
      g_lastBarTime[idx] = closed;
      return true; // first run: treat as new-bar to seed ATR snapshot
     }
   if(closed > g_lastBarTime[idx])
     {
      g_lastBarTime[idx] = closed;
      return true;
     }
   return false;
  }

// Router path new-bar latches (timer and tick must not share state)
static datetime g_router_lastBar_timer = 0;
static datetime g_router_lastBar_tick  = 0;

bool IsNewBarRouterByLatch(const string sym,
                           const ENUM_TIMEFRAMES tf,
                           datetime &last_bar_latch)
{
   const datetime t0 = iTime(sym, tf, 0);
   if(t0 <= 0)
      return false;

   if(last_bar_latch != t0)
   {
      last_bar_latch = t0;
      return true;
   }
   return false;
}

bool IsNewBarRouterTimer(const string sym, const ENUM_TIMEFRAMES tf)
{
   return IsNewBarRouterByLatch(sym, tf, g_router_lastBar_timer);
}

bool IsNewBarRouterTick(const string sym, const ENUM_TIMEFRAMES tf)
{
   return IsNewBarRouterByLatch(sym, tf, g_router_lastBar_tick);
}

string _RouterTFStr(const ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);
   if(StringLen(s) <= 0)
      s = IntegerToString((int)tf);
   return s;
}

string _RouterBarTimeStr(const datetime t)
{
   if(t <= 0)
      return "-";
   return TimeToString(t, TIME_DATE | TIME_MINUTES);
}

void _EmitRouterBarDiagKV(const string handler,
                          const string event_name,
                          const string sym,
                          const ENUM_TIMEFRAMES tf,
                          const datetime bar_time,
                          const datetime latch_ref)
{
   string j = "{";
   j += "\"sym\":\"" + Telemetry::_Esc(sym) + "\",";
   j += "\"tf\":" + IntegerToString((int)tf) + ",";
   j += "\"status\":\"router_bar_diag\",";
   j += "\"decision_source\":\"" + Telemetry::_Esc(handler) + "\",";
   j += "\"decision_ts\":" + Telemetry::JsonDateTimeOrNull(true, TimeCurrent()) + ",";
   j += "\"bar_event\":\"" + Telemetry::_Esc(event_name) + "\",";
   j += "\"handler\":\"" + Telemetry::_Esc(handler) + "\",";
   j += "\"bar_time\":" + Telemetry::JsonDateTimeOrNull(bar_time > 0, bar_time) + ",";
   j += "\"latch_ref\":" + Telemetry::JsonDateTimeOrNull(latch_ref > 0, latch_ref) + ",";
   j += "\"last_drop_reason\":null";
   j += "}";
   Telemetry::KV("ict.ctx", j);
}

void _DebugRouterNewBar(const string handler,
                        const string sym,
                        const ENUM_TIMEFRAMES tf,
                        const datetime bar_time,
                        const datetime prev_latch)
{
   if(!InpDebug)
      return;

   const string key =
      handler + "|" +
      sym + "|" +
      IntegerToString((int)tf) + "|" +
      IntegerToString((int)bar_time);

   if(handler == "Tick")
   {
      static string last_tick_key = "";
      if(last_tick_key == key)
         return;
      last_tick_key = key;
   }
   else
   {
      static string last_timer_key = "";
      if(last_timer_key == key)
         return;
      last_timer_key = key;
   }

   LogX::Info(StringFormat("[RouterBar] handler=%s event=new_bar sym=%s tf=%s bar=%s prev_latch=%s",
                           handler,
                           sym,
                           _RouterTFStr(tf),
                           _RouterBarTimeStr(bar_time),
                           _RouterBarTimeStr(prev_latch)));

   _EmitRouterBarDiagKV(handler, "new_bar", sym, tf, bar_time, prev_latch);
}

void _DebugRouterSkipNotNewBar(const string handler,
                               const string sym,
                               const ENUM_TIMEFRAMES tf,
                               const datetime bar_time,
                               const datetime timer_latch)
{
   if(!InpDebug)
      return;

   const string key =
      handler + "|" +
      sym + "|" +
      IntegerToString((int)tf) + "|" +
      IntegerToString((int)bar_time) + "|" +
      IntegerToString((int)timer_latch);

   static string last_skip_key = "";
   if(last_skip_key == key)
      return;
   last_skip_key = key;

   LogX::Info(StringFormat("[RouterBar] handler=%s event=skip_not_new_bar sym=%s tf=%s bar=%s timer_latch=%s",
                           handler,
                           sym,
                           _RouterTFStr(tf),
                           _RouterBarTimeStr(bar_time),
                           _RouterBarTimeStr(timer_latch)));

   _EmitRouterBarDiagKV(handler, "skip_not_new_bar", sym, tf, bar_time, timer_latch);
}

// ---------------- Indicator micro-benchmark ----------------
void RunIndicatorBenchmarks()
  {
   if(!InpBenchIndicators)
      return;

   ENUM_TIMEFRAMES tfs[] = { PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4 };
   const int N = ArraySize(tfs);
   for(int i=0;i<N;i++)
     {
#ifdef CA_USE_HANDLE_REGISTRY
      HR::BenchmarkPrint(_Symbol, tfs[i],
                         (InpBenchATR_Period>0?InpBenchATR_Period:14),
                         (InpBenchWarmup>0?InpBenchWarmup:5),
                         (InpBenchLoops>0?InpBenchLoops:200));
#else
      Indi::BenchmarkPrint_ATR(_Symbol, tfs[i],
                               (InpBenchATR_Period>0?InpBenchATR_Period:14),
                               (InpBenchWarmup>0?InpBenchWarmup:5),
                               (InpBenchLoops>0?InpBenchLoops:200));
#endif
     }
   Print("Indicator benchmark complete.");
  }

inline void UpdateRegistryRoutingFlag()
{
   // Legacy ProcessSymbol harness is tester-only and requires:
   // 1) diagnostic compile-time enable
   // 2) historical registry-routing input
   // 3) explicit legacy compatibility opt-in
   // 4) explicit direct StrategyRegistry compatibility arm
   g_use_registry = false;
   g_sr_direct_registry_compat_runtime = DirectRegistryCompatRuntimeRequested(g_cfg);
   
   if(LegacyProcessSymbolCompileTimeEnabled() && g_sr_direct_registry_compat_runtime)
      g_use_registry = LegacyProcessSymbolRuntimeRequested();
   
   // STRAT_MAIN_ONLY must always use RouterEvaluateAll()
   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
   {
      g_sr_direct_registry_compat_runtime = false;
      g_use_registry = false;
   }
}

bool UseLegacyProcessSymbolEngine()
{
   return (LegacyProcessSymbolCompileTimeEnabled() &&
           g_is_tester &&
           g_use_registry);
}

string ActiveRoutingEngineName()
{
   if(UseLegacyProcessSymbolEngine())
      return "legacy_processsymbol";

   return "canonical_router";
}

void WarnMaybeEvaluateDeprecatedOnce()
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(
            "[DEPRECATED] MaybeEvaluate() is a non-canonical route disabled for trade execution. Canonical live/tester owner is OnTimer() with RunCachedRouterPass(Timer) and RouterEvaluateAll().");
}

// DEPRECATED compatibility helper.
// Historically associated with alternate routing experiments.
// Keep fail-closed: canonical new-order routing ownership is OnTimer() only.
void MaybeEvaluate()
  {
   WarnMaybeEvaluateDeprecatedOnce();
   DecisionTelemetry_MarkPassiveSkip("deprecated_maybeevaluate");
   return;

   // Backend-only live build: alternate dispatcher is tester-only.
   if(!g_is_tester)
      return;

   // Unified warmup gate (tester-safe; single source of truth)
   if(!WarmupGateOK())
      return;
   
   // Short series gate is handled inside WarmupGateOK() (RT non-blocking). No duplicate gate here.
   static datetime last_bar = 0;
   const datetime bt = iTime(_Symbol, Warmup::TF_Entry(g_cfg), 0);

   if(InpOnlyNewBar && bt == last_bar)
      return;

   if(InpOnlyNewBar)
      last_bar = bt;

    // --- Hardening: Do not use alternate routing pipelines here ---
    const datetime now_srv = TimeUtils::NowServer();

    // Hard guarantee: STRAT_MAIN_ONLY always routes via RouterEvaluateAll()
    if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
       g_use_registry = false;

    if(UseLegacyProcessSymbolEngine())
    {
       if(!GateViaPolicies(g_cfg, _Symbol))
         return;

       ProcessSymbol(_Symbol, true);
       return;
    }

   const string router_sym = CanonicalRouterSymbol();

   RefreshRuntimeContextFromHub(router_sym, false);

   const datetime required_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(router_sym);
   string inst_diag = "";
   const bool inst_ready = EnsureCanonicalInstitutionalStateReady(router_sym, required_bar_time, inst_diag);

   if(InpDebug && !inst_ready && inst_diag != "")
   {
      static datetime last_tick_inst_key = 0;
      if(last_tick_inst_key != required_bar_time)
      {
         last_tick_inst_key = required_bar_time;
         PrintFormat("[InstReady][Tick] sym=%s ready=0 req=%s detail=%s",
                     router_sym,
                     InstDiagTimeStr(required_bar_time),
                     inst_diag);
      }
   }

   LogCanonicalInstitutionalGateDiag(router_sym, required_bar_time, "Tick");

   int gate_reason = 0;
   if(!RouterGateOK_Global(router_sym, g_cfg, now_srv, gate_reason))
      return;

   ICT_Context ictCtx = StateGetICTContext(g_state);

   RouterEvaluateAll(g_exec_router, g_cfg, ictCtx);
  }

//--------------------------------------------------------------------
// BuildSettingsFromInputs()
// Copy ICT / router inputs into the runtime Settings struct (g_cfg).
// This is separate from MirrorInputsToSettings(S) used for S.
//--------------------------------------------------------------------
void ApplyLiquidityPolicyInputs(Settings &cfg)
{
   #ifdef CFG_HAS_LIQ_MIN_RATIO
      double live_floor = InpPolicy_LiqMinRatio;
      if(live_floor <= 0.0)
         live_floor = 1.50;
      if(live_floor < 0.50)
         live_floor = 0.50;
      if(live_floor > 10.0)
         live_floor = 10.0;
      cfg.liq_min_ratio = live_floor;
   #endif

   #ifdef CFG_HAS_LIQ_MIN_RATIO_TESTER
      double tester_floor = InpPolicy_LiqMinRatioTester;

      if(tester_floor < 0.0)
         tester_floor = 0.0;

      if(tester_floor > 0.0)
      {
         if(tester_floor < 0.50)
            tester_floor = 0.50;
         if(tester_floor > 10.0)
            tester_floor = 10.0;
      }

      if(g_is_tester)
      {
         if(tester_floor <= 0.0)
            tester_floor = MathMax(0.50, MathMin(10.0, cfg.liq_min_ratio * 0.90));

         cfg.liq_min_ratio_tester = tester_floor;
      }
      else
      {
         cfg.liq_min_ratio_tester = 0.0;
      }
   #endif

   #ifdef CFG_HAS_LIQ_INVALID_HARDFAIL
      cfg.liq_hard_fail_on_invalid_metrics = InpPolicy_LiqInvalidHardFail;
   #endif
}

void BuildSettingsFromInputs(Settings &cfg)
{
   // 0) Start from finalized runtime S (after profile/overrides/normalize)
   // NOTE: Overlay helper. Caller must initialize cfg (Mirror/Profile/etc) before calling.

   // --- Core / generic ICT config ---
   cfg.tf_entry                  = InpEntryTF;          // ICT entry TF - SINGLE source of truth for entry TF (matches MirrorInputsToSettings)
   // Keep ICT/router Settings fully populated for multi-TF model pieces
   cfg.tf_h1                     = InpHTF_H1;
   cfg.tf_h4                     = InpHTF_H4;
   cfg.tf_d1                     = InpHTF_D1;
   #ifdef CFG_HAS_TF_HTF
      cfg.tf_htf = InpTfHTF;     // ICT HTF
   #endif
   #ifdef CFG_HAS_RISK_PER_TRADE
      cfg.risk_per_trade = InpRiskPerTradePct;     // ICT risk slider
   #endif
   #ifdef CFG_HAS_NEWS_FILTER_ENABLED
      cfg.newsFilterEnabled = EA_EffectiveNewsOn();        // reuse effective NewsOn runtime flag
   #endif
   #ifdef CFG_HAS_TRADE_DIRECTION_SELECTOR
      cfg.trade_direction_selector = InpTradeDirectionSelector;
   
      // Canonical manual selector (single source of truth for manual intent):
      cfg.trade_selector = InpTradeSelector;
   
      // Legacy alias: only apply the legacy selector if the newer selector is left at default.
      if(cfg.trade_selector == TRADE_BOTH_AUTO)
        {
         if(cfg.trade_direction_selector == TDIR_BUY)
            cfg.trade_selector = TRADE_BUY_ONLY;
         else if(cfg.trade_direction_selector == TDIR_SELL)
            cfg.trade_selector = TRADE_SELL_ONLY;
        }
   #endif

   // Direction bias mode:
   #ifdef CFG_HAS_DIRECTION_BIAS_MODE
      cfg.direction_bias_mode = InpDirectionBiasMode;
   #endif

   // --- Strategy enable toggles ---
   #ifdef CFG_HAS_ENABLE_STRAT_MAIN
      cfg.enable_strat_main = InpEnable_MainLogic;
   #endif
   #ifdef CFG_HAS_ENABLE_STRAT_ICT_SILVERBULLET
      cfg.enable_strat_ict_silverbullet = InpEnable_ICT_SilverBullet;
   #endif
   #ifdef CFG_HAS_ENABLE_STRAT_ICT_PO3
      cfg.enable_strat_ict_po3 = InpEnable_ICT_PO3;
   #endif
   #ifdef CFG_HAS_ENABLE_STRAT_ICT_CONTINUATION
      cfg.enable_strat_ict_continuation = InpEnable_ICT_Continuation;
   #endif
   #ifdef CFG_HAS_ENABLE_STRAT_ICT_WYCKOFF_TURN
      cfg.enable_strat_ict_wyckoff_turn = InpEnable_ICT_WyckoffTurn;
   #endif

   // --- Pack strategy registration toggle (runtime replacement for ENABLE_LEGACY_STRATEGIES) ---
   #ifdef CFG_HAS_ENABLE_PACK_STRATS
      cfg.enable_pack_strats = InpEnable_PackStrategies;
   #endif
   #ifdef CFG_HAS_DISABLE_PACKS
      cfg.disable_packs      = InpDisable_PackStrategies;
   #endif

   // --- ML SL/TP multiplier control (input-driven, applied LAST so profiles don't override) ---
   #ifdef CFG_HAS_ML_SETTINGS
     #ifdef CFG_HAS_ML_SLTP_MULT
        cfg.ml_sltp_enable   = InpML_SLTP_Enable;
        cfg.ml_sltp_sl_min   = InpML_SLMult_Min;
        cfg.ml_sltp_sl_max   = InpML_SLMult_Max;
        cfg.ml_sltp_tp_min   = InpML_TPMult_Min;
        cfg.ml_sltp_tp_max   = InpML_TPMult_Max;
     #endif
   #endif
    
   // --- Magic bases (per-strategy ranges) ---
   cfg.magic_main_base        = InpMagic_MainBase;
   cfg.magic_sb_base          = InpMagic_SilverBulletBase;
   cfg.magic_po3_base         = InpMagic_PO3Base;
   cfg.magic_cont_base        = InpMagic_ContinuationBase;
   cfg.magic_wyck_base        = InpMagic_WyckoffTurnBase;

   // --- Per-strategy risk multipliers ---
   cfg.risk_mult_main         = InpRiskMult_Main;
   cfg.risk_mult_sb           = InpRiskMult_SilverBullet;
   cfg.risk_mult_po3          = InpRiskMult_PO3;
   cfg.risk_mult_cont         = InpRiskMult_Continuation;
   cfg.risk_mult_wyck         = InpRiskMult_WyckoffTurn;
   
   // Keep baseline override deterministic even when profiles are applied
   #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
     // Keep baseline override deterministic even when profiles are applied
     cfg.challenge_init_equity = MathMax(0.0, InpChallengeInitEquity);
   #endif

   #ifdef CFG_HAS_RISK_MULT_MAX
     cfg.risk_mult_max = _RiskMultMaxCapFromInputs();
   #endif
   
   // Router will override these two per strategy before Evaluate():
   cfg.magic_base             = cfg.magic_main_base;
   cfg.risk_mult_current      = cfg.risk_mult_main;

   // --- Global quality thresholds for ICT stack ---
   cfg.qualityThresholdHigh         = InpQualityThresholdHigh;
   cfg.qualityThresholdContinuation = InpQualityThresholdCont;
   cfg.qualityThresholdReversal     = InpQualityThresholdReversal;

   // --- Fibonacci / OTE configuration (ICT/Wyckoff) ---
   cfg.fibDepth              = InpFibDepth;
   cfg.fibATRPeriod          = InpFibATRPeriod;
   cfg.fibDevATRMult         = InpFibDevATRMult;
   cfg.fibMaxBarsBack        = InpFibMaxBarsBack;
   cfg.fibUseConfluence      = InpFibUseConfluence;
   cfg.fibMinConfluenceScore = InpFibMinConfScore;
   cfg.fibOTEToleranceATR    = InpFibOTEToleranceATR;

   // --- Low-level filters used by ICT stack ---
   cfg.useVWAPFilter         = InpUseVWAPFilter;
   cfg.useEMAFilter          = InpUseEMAFilter;

   // --- VWAP / pattern config ---
   cfg.vwap_lookback         = InpVWAP_Lookback;
   cfg.vwap_sigma            = InpVWAP_Sigma;
   cfg.vwap_z_edge           = InpVWAP_Z_Edge;
   cfg.vwap_z_avoidtrend     = InpVWAP_Z_AvoidTrend;
   cfg.pattern_lookback      = InpPattern_Lookback;
   cfg.pattern_tau           = InpPattern_Tau;

   // --- Structure / OB detection tuning ---
   cfg.struct_zz_depth       = Inp_Struct_ZigZagDepth;
   cfg.struct_htf_mult       = Inp_Struct_HTF_Multiplier;
   cfg.ob_prox_max_pips      = Inp_OB_ProxMaxPips;

   // --- Liquidity Pools (Lux-style thresholds) ---
   cfg.liqPoolMinTouches      = InpLiqPoolMinTouches;
   cfg.liqPoolGapBars         = InpLiqPoolGapBars;
   cfg.liqPoolConfirmWaitBars = InpLiqPoolConfirmWaitBars;
   cfg.liqPoolLevelEpsATR     = InpLiqPoolLevelEpsATR;
   cfg.liqPoolMaxLookbackBars = InpLiqPoolMaxLookbackBars;
   cfg.liqPoolMinSweepATR     = InpLiqPoolMinSweepATR;

   // --- Feature toggles reused by ICT stack ---
   cfg.vsa_enable            = InpVSA_Enable;
   cfg.vsa_penalty_max       = InpVSA_PenaltyMax;
   cfg.structure_enable      = InpStructure_Enable;
   #ifdef CFG_HAS_STRUCT_VETO
      cfg.struct_veto_on     = InpStructVetoOn;
   #endif
   cfg.liquidity_enable      = InpLiquidity_Enable;

   // Optional FVG defaults if you added such fields (compile-safe)
   #ifdef CFG_HAS_FVG_MIN_SCORE
      cfg.fvg_min_score = 0.35;
   #endif
   #ifdef CFG_HAS_FVG_MODE
      cfg.fvg_mode = 0;
   #endif

   // --- Canonical degraded institutional fallback policy ---
   #ifdef CFG_HAS_ALLOW_TESTER_DEGRADED_INST_FALLBACK
      cfg.allow_tester_degraded_inst_fallback = InpMS_TesterAllowUnavailable;
   #endif

   #ifdef CFG_HAS_TESTER_DIRECT_REGISTRY_COMPAT
      cfg.tester_direct_registry_compat = InpTester_DirectRegistryCompat;
   #endif

   #ifdef CFG_HAS_ALLOW_LIVE_DEGRADED_INST_FALLBACK
      cfg.allow_live_degraded_inst_fallback   = InpMS_LiveAllowDegradedInstFallback;
   #endif

   #ifdef CFG_HAS_ROUTER_TESTER_MIN_SCORE_OVERRIDE
      cfg.router_tester_min_score_override =
         (InpRouterTesterMinScoreOverride >= 0.0 ? InpRouterTesterMinScoreOverride : InpRouterMinScore);
   #endif

   // --- Signal-stack / category gating ---
   cfg.sigsel_enable                      = (InpSigSel_Enable ? true : false);
   cfg.sigsel_selection_mode              = EA_ParseSigSelModeInput(InpSigSel_Mode);
   cfg.sigsel_inst_selection_mode         = EA_ParseSigSelInstModeInput(InpSigSel_InstMode);
   cfg.sigsel_institutional_degrade_mode  = EA_ParseSigSelInstDegradeModeInput(InpSigSel_InstDegradeMode);

   cfg.sigsel_fixed_inst_index            = InpSigSel_FixedInstIndex;
   cfg.sigsel_fixed_trend_index           = InpSigSel_FixedTrendIndex;
   cfg.sigsel_fixed_mom_index             = InpSigSel_FixedMomIndex;
   cfg.sigsel_fixed_vol_index             = InpSigSel_FixedVolIndex;
   cfg.sigsel_fixed_vola_index            = InpSigSel_FixedVolaIndex;

   cfg.sigsel_th_inst                     = InpSigSel_ThInst;
   cfg.sigsel_th_inst_proxy               = InpSigSel_ThInstProxy;
   cfg.sigsel_th_trend                    = InpSigSel_ThTrend;
   cfg.sigsel_th_mom                      = InpSigSel_ThMom;
   cfg.sigsel_th_vol                      = InpSigSel_ThVol;
   cfg.sigsel_th_vola                     = InpSigSel_ThVola;

   cfg.sigsel_band_rsi                    = InpSigSel_BandRSI;
   cfg.sigsel_band_stoch                  = InpSigSel_BandStoch;
   cfg.sigsel_th_adx                      = InpSigSel_ThADX;

   cfg.sigsel_th_atr_min                  = InpSigSel_ATRMin;
   cfg.sigsel_th_atr_max                  = InpSigSel_ATRMax;
   cfg.sigsel_th_bbwidth_min              = InpSigSel_BBWidthMin;
   cfg.sigsel_th_bbwidth_max              = InpSigSel_BBWidthMax;
   cfg.sigsel_th_rv_min                   = InpSigSel_RVMin;
   cfg.sigsel_th_rv_max                   = InpSigSel_RVMax;
   cfg.sigsel_th_bv_min                   = InpSigSel_BVMin;
   cfg.sigsel_th_bv_max                   = InpSigSel_BVMax;
   cfg.sigsel_th_jump_max                 = InpSigSel_JumpMax;
   cfg.sigsel_th_sigmap_min               = InpSigSel_SigmaPMin;
   cfg.sigsel_th_sigmap_max               = InpSigSel_SigmaPMax;
   cfg.sigsel_th_sigmagk_min              = InpSigSel_SigmaGKMin;
   cfg.sigsel_th_sigmagk_max              = InpSigSel_SigmaGKMax;

   cfg.sigsel_loc_th_pivot                = InpSigSel_LocPivot;
   cfg.sigsel_loc_th_sr                   = InpSigSel_LocSR;
   cfg.sigsel_loc_th_fib                  = InpSigSel_LocFib;
   cfg.sigsel_loc_th_sd                   = InpSigSel_LocSD;
   cfg.sigsel_loc_th_ob                   = InpSigSel_LocOB;
   cfg.sigsel_loc_th_fvg                  = InpSigSel_LocFVG;
   cfg.sigsel_loc_th_sweep                = InpSigSel_LocSweep;
   cfg.sigsel_loc_th_wyckoff              = InpSigSel_LocWyckoff;

   cfg.sigsel_min_category_votes          = InpSigSel_MinCategoryVotes;
   cfg.sigsel_min_category_votes_default  = InpSigSel_MinCategoryVotes;
   cfg.sigsel_min_category_votes_floor    = InpSigSel_MinCategoryVotesFloor;
   cfg.sigsel_min_location_votes          = InpSigSel_MinLocationVotes;

   cfg.sigsel_inst_coverage_threshold     = InpSigSel_InstCoverageThreshold;

   cfg.sigsel_w_orderbook                 = InpSigSel_W_OrderBook;
   cfg.sigsel_w_tradeflow                 = InpSigSel_W_TradeFlow;
   cfg.sigsel_w_impact                    = InpSigSel_W_Impact;
   cfg.sigsel_w_execquality               = InpSigSel_W_ExecQuality;

   cfg.sigsel_w_proxy_microprice_bias     = InpSigSel_W_ProxyMicropriceBias;
   cfg.sigsel_w_proxy_auction_bias        = InpSigSel_W_ProxyAuctionBias;
   cfg.sigsel_w_proxy_composite           = InpSigSel_W_ProxyComposite;

   cfg.sigsel_inst_weights_csv            = InpSigSel_InstWeightsCSV;
   cfg.sigsel_trend_weights_csv           = InpSigSel_TrendWeightsCSV;
   cfg.sigsel_mom_weights_csv             = InpSigSel_MomWeightsCSV;
   cfg.sigsel_vol_weights_csv             = InpSigSel_VolWeightsCSV;
   cfg.sigsel_vola_weights_csv            = InpSigSel_VolaWeightsCSV;

   #ifdef CFG_HAS_POLICY_ENABLE_NEWS_BLOCK
      cfg.enable_news_block = true;
   #endif
   #ifdef CFG_HAS_POLICY_ENABLE_REGIME_GATE
      cfg.enable_regime_gate = true;
   #endif
   #ifdef CFG_HAS_POLICY_ENABLE_LIQUIDITY_GATE
      cfg.enable_liquidity_gate = true;
   #endif

   if(g_is_tester && ResolveTesterRouterGateMode() == TESTER_ROUTER_GATE_MODE_BYPASS)
   {
      #ifdef CFG_HAS_POLICY_ENABLE_NEWS_BLOCK
         cfg.enable_news_block = false;
      #endif
      #ifdef CFG_HAS_POLICY_ENABLE_REGIME_GATE
         cfg.enable_regime_gate = false;
      #endif
      #ifdef CFG_HAS_POLICY_ENABLE_LIQUIDITY_GATE
         cfg.enable_liquidity_gate = false;
      #endif
   }

   // --- Session / mode flags (Smart Money runtime gates) ---
   cfg.mode_use_silverbullet =
      (InpEnable_SilverBulletMode && cfg.enable_strat_ict_silverbullet);
   cfg.mode_use_po3          =
      (InpEnable_PO3Mode && cfg.enable_strat_ict_po3);
   cfg.mode_enforce_killzone = EA_EffectiveEnforceKillzone();
   cfg.mode_use_ICT_bias     = InpUseICTBias;
}

void FinalizeRuntimeSettings()
{
   Settings cfg;
   ZeroMemory(cfg);

   // 0) Base snapshot from inputs (ONE time)
   MirrorInputsToSettings(cfg);
   if(cfg.max_daily_dd_pct <= 0.0) cfg.max_daily_dd_pct = InpMaxDailyDD_Pct;

   // ---- Adaptive DD clamps ----
   #ifdef CFG_HAS_ADAPTIVE_DD_ENABLE
     if(cfg.adaptive_dd_enable)
     {
       #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
         if(cfg.adaptive_dd_window_days < 1) cfg.adaptive_dd_window_days = 30;
       #endif
       #ifdef CFG_HAS_ADAPTIVE_DD_PCT
         if(cfg.adaptive_dd_pct <= 0.0) cfg.adaptive_dd_pct = cfg.max_daily_dd_pct;
       #endif
     }
   #endif
   
   // ---- Big-loss sizing reset clamps ----
   #ifdef CFG_HAS_BIGLOSS_RESET_ENABLE
     if(cfg.bigloss_reset_enable)
     {
       #ifdef CFG_HAS_BIGLOSS_RESET_R
         if(cfg.bigloss_reset_r <= 0.0) cfg.bigloss_reset_r = 2.0;
       #endif
       #ifdef CFG_HAS_BIGLOSS_RESET_MINS
         if(cfg.bigloss_reset_mins < 0) cfg.bigloss_reset_mins = 0;
       #endif
     }
   #endif

   // Move the MVP_NoBlock warning here (from OnInit lines 2157–2160), replacing S->cfg
   #ifdef CFG_HAS_NEWS_MVP_NO_BLOCK
      if(cfg.news_on && cfg.news_mvp_no_block)
         LogX::Warn("News is ON but MVP_NoBlock is true -> NewsFilter will NOT hard-block trades.");
   #endif

   // ---- Router multi-entry safety hint (warn only) ----
   #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
     #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
       #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
         if(cfg.router_eval_all_mode == 1 && cfg.max_positions_per_symbol > 1 && cfg.max_positions_total == 0)
           LogX::Warn("Router exec mode=1 with max_positions_per_symbol>1 and max_positions_total=0 (unlimited). Consider setting a total cap to avoid runaway entries.");
       #endif
     #endif
   #endif

   // 1) Extras (ONE time)
   Config::BuildExtras ex;
   Config::BuildExtrasDefaults(ex);

   // MOVE the entire ex.* assignment block from OnInit lines 2164–2267 into here (unchanged),
   // but the ApplyExtras target must be cfg:
   //    Config::ApplyExtras(cfg, ex);
   // (Replace the original "Config::ApplyExtras(S, ex);" with the cfg version.)
   Config::ApplyExtras(cfg, ex);

   // 2) Mode + key overrides (ONE time)
   Config::ApplyStrategyMode(cfg, InpStrat_Mode);
   Config::LoadInputs(cfg, InpMonthlyTargetPct);
   Config::ApplyKVOverrides(cfg);
   Config::FinalizeThresholds(cfg);

   // Keep DOM imbalance flag in the snapshot (move from OnInit line 2277, S->cfg)
   cfg.extra_dom_imbalance = (cfg.extra_dom_imbalance || InpExtra_DOMImbalance);

   // 3) Build profile spec + apply profile (MOVE OnInit lines 2389–2457, replace S->cfg)
   const TradingProfile prof = (TradingProfile)InpProfileType;
   Config::ProfileSpec ps;
   Config::BuildProfileSpec(prof, ps);

   if(InpProfileApply)
      Config::ApplyProfileHintsToSettings(cfg, ps, /*overwrite=*/true);

   Config::ApplyCarryDefaultsForProfile(cfg, prof);

   if(InpProfileSaveCSV)
      Config::SaveProfileSpecCSV(prof, ps, InpProfileCSVName, false);

   if(InpProfileApply)
   {
      Config::ApplyTradingProfile(cfg, prof,
                                 /*apply_router_hints=*/EA_RouterUseProfileThresholds(),
                                 /*apply_carry_defaults=*/true,
                                 /*log_summary=*/true);

      // Keep your manual override blocks, but target cfg (moved from 2406–2452, S->cfg)
      // (No logic changes needed—just replace S. with cfg.)
      if(InpProfileAllowManual)
      {
         cfg.carry_enable = InpCarry_Enable;
         #ifdef CFG_HAS_CARRY_BOOST_MAX
            cfg.carry_boost_max = MathMin(MathMax(InpCarry_BoostMax, 0.0), 0.20);
         #endif
         #ifdef CFG_HAS_CARRY_RISK_SPAN
            cfg.carry_risk_span = MathMin(MathMax(InpCarry_RiskSpan, 0.0), 0.50);
         #endif
         #ifdef CFG_HAS_CONFL_BLEND_TREND
            if(InpConflBlend_Trend > 0.0)
               cfg.confl_blend_trend = MathMin(InpConflBlend_Trend, 0.50);
         #endif
         #ifdef CFG_HAS_CONFL_BLEND_MR
            if(InpConflBlend_MR > 0.0)
               cfg.confl_blend_mr = MathMin(InpConflBlend_MR, 0.50);
         #endif
         #ifdef CFG_HAS_CONFL_BLEND_OTHERS
            if(InpConflBlend_Others > 0.0)
               cfg.confl_blend_others = MathMin(InpConflBlend_Others, 0.50);
         #endif
      }
      else
      {
         cfg.carry_enable = InpCarry_Enable;
         #ifdef CFG_HAS_CARRY_BOOST_MAX
            cfg.carry_boost_max = MathMin(MathMax(InpCarry_BoostMax, 0.0), 0.20);
         #endif
         #ifdef CFG_HAS_CARRY_RISK_SPAN
            cfg.carry_risk_span = MathMin(MathMax(InpCarry_RiskSpan, 0.0), 0.50);
         #endif

         Config::ApplyConfluenceBlendDefaultsForProfile(cfg, prof);

         #ifdef CFG_HAS_CONFL_BLEND_TREND
            if(InpConflBlend_Trend > 0.0)
               cfg.confl_blend_trend = MathMin(InpConflBlend_Trend, 0.50);
         #endif
         #ifdef CFG_HAS_CONFL_BLEND_MR
            if(InpConflBlend_MR > 0.0)
               cfg.confl_blend_mr = MathMin(InpConflBlend_MR, 0.50);
         #endif
         #ifdef CFG_HAS_CONFL_BLEND_OTHERS
            if(InpConflBlend_Others > 0.0)
               cfg.confl_blend_others = MathMin(InpConflBlend_Others, 0.50);
         #endif
      }
   }

   // Fix the missing braces in the strict-risk block while moving it (from 2454–2457)
   if(InpCarry_StrictRiskOnly)
   {
      #ifdef CFG_HAS_CARRY_RISK_SPAN
         cfg.carry_risk_span = 0.0;
      #endif
   }

   // 4) Apply remaining input overlays last (uses refactored overlay helper)
   BuildSettingsFromInputs(cfg);
   ApplyLiquidityPolicyInputs(cfg);

   // Re-assert strat_mode => enable_* toggle coherence after overlays (no full Normalize).
   Config::EnforceStrategyModeToggles(cfg);

   // 5) Set magic number INSIDE snapshot (MOVE OnInit lines 2317–2326, S->cfg)
   #ifdef CFG_HAS_MAGIC_NUMBER
      const StrategyMode sm = Config::CfgStrategyMode(cfg);
      switch(sm)
      {
         case STRAT_MAIN_ONLY: cfg.magic_number = MagicBase_Main; break;
         case STRAT_PACK_ONLY: cfg.magic_number = MagicBase_Pack; break;
         default:              cfg.magic_number = MagicBase_Combined; break;
      }
   #endif

   // 6) Session degeneracy guard INSIDE snapshot (MOVE OnInit lines 2364–2387, S->cfg)
   #ifdef POLICIES_HAS_SESSION_CTX
      SessionContext sc;
      Policies::BuildSessionContext(cfg, sc);
      if(cfg.session_filter && CfgSessionPreset(cfg) != SESS_OFF && !sc.has_any_window)
         cfg.session_filter = false;
   #else
      if(cfg.session_filter && CfgSessionPreset(cfg) != SESS_OFF)
      {
         const bool lon_empty = (cfg.london_open_utc == cfg.london_close_utc);
         const bool ny_empty  = (cfg.ny_open_utc     == cfg.ny_close_utc);
         if(lon_empty && ny_empty)
            cfg.session_filter = false;
      }
   #endif

   // 7) Normalize finalized local snapshot (includes signal-stack clamps + weight parsing)
   Config::Normalize(cfg);
   SyncRuntimeCfgFlags(cfg);

   // 8) Commit single source of truth
   S     = cfg;
   g_cfg = cfg;

   // 9) Optional pack-strats log (MOVE OnInit lines 2462–2469; no changes besides using S now)
   #ifdef CFG_HAS_ENABLE_PACK_STRATS
      string packs_msg = StringFormat("PackStrats: enable=%s",
                                      (S.enable_pack_strats ? "true" : "false"));
      #ifdef CFG_HAS_DISABLE_PACKS
         packs_msg += StringFormat(" disable=%s", (S.disable_packs ? "true" : "false"));
      #endif
      LogX::Info(packs_msg);
   #endif

   // 10) Tester overlays must be in-snapshot (MOVE 2477–2479, but GUARD it)
   if(g_is_tester)
   {
      TesterPresets::ApplyPresetByName(S, InpTesterPreset);
      TesterCases::ApplyTestCase(S, InpTestCase);
      ApplyLiquidityPolicyInputs(S);
      Config::Normalize(S);
      SyncRuntimeCfgFlags(S);
      g_cfg = S; // keep both identical after tester overlay
   }

   // 10A) Central tester-only override layer:
   // Apply AFTER profile resolution + tester preset/case overlays
   // and BEFORE registry/router boot so downstream gates consume
   // the final effective runtime config.
   TesterSettings::ApplyToConfig(S);
   Config::Normalize(S);
   SyncRuntimeCfgFlags(S);
   g_cfg = S;

   #ifdef CFG_HAS_STRUCT_VETO
   {
      static bool warned_struct_veto_migration = false;

      if(!warned_struct_veto_migration &&
         S.structure_enable &&
         !S.struct_veto_on)
      {
         warned_struct_veto_migration = true;
         LogX::Warn("[ConfigMigration] structure_enable no longer auto-enables struct_veto_on. Structure remains active for feature/scoring, but hard structure veto is OFF. Set InpStructVetoOn=true to restore legacy hard-veto behavior.");
      }
   }
   #endif

   #ifdef CFG_HAS_SCAN_INST_STATE_SETTINGS
   if(Config::CfgInstitutionalTransportRuntimeIntent(S) &&
      !Config::CfgInstitutionalStateProducerEnabled(S))
   {
      S.scan_inst_state_enable = true;
      g_cfg.scan_inst_state_enable = true;

      LogX::Warn("[RuntimeConsistency] auto-corrected scan_inst_state_enable=true because runtime intent requires canonical institutional transport.");
   }

   {
      bool tester_fb_allow = false;
      bool live_fb_allow   = false;

   #ifdef CFG_HAS_MICROSTRUCTURE_SETTINGS
      tester_fb_allow = Config::CfgAllowTesterDegradedInstFallback(S);
   #endif

   #ifdef CFG_HAS_ALLOW_LIVE_DEGRADED_INST_FALLBACK
      live_fb_allow = (S.allow_live_degraded_inst_fallback ? true : false);
   #endif

      const bool effective_fb_allow = (g_is_tester ? tester_fb_allow : live_fb_allow);

      LogX::Info(StringFormat("[InstFallback] tester_input=%s tester_cfg=%s live_input=%s live_cfg=%s effective=%s tester=%s",
                              (InpMS_TesterAllowUnavailable ? "true" : "false"),
                              (tester_fb_allow ? "true" : "false"),
                              (InpMS_LiveAllowDegradedInstFallback ? "true" : "false"),
                              (live_fb_allow ? "true" : "false"),
                              (effective_fb_allow ? "true" : "false"),
                              (g_is_tester ? "true" : "false")));

      bool degraded_active = false;
      string degraded_type = "off";
      double degraded_mag = 0.0;
      RuntimeTesterDegradedScorePolicySnapshot(CanonicalRouterSymbol(), degraded_active, degraded_type, degraded_mag);
   
      PrintFormat("[DegradedScorePolicy] configured{mode=%s legacy_override=%s type=%s magnitude=%.3f} effective{active=%s type=%s magnitude=%.3f} tester_allow_unavailable=%s tester=%s live_applies=false",
                  RuntimeTesterDegradedScorePolicyModeName((int)InpMS_TesterDegradedScorePolicyMode),
                  (InpMS_TesterDegradedScorePolicyEnable ? "true" : "false"),
                  RuntimeTesterDegradedScorePolicyTypeName((int)InpMS_TesterDegradedScorePolicyType),
                  InpMS_TesterDegradedScorePolicyMagnitude,
                  (degraded_active ? "true" : "false"),
                  degraded_type,
                  degraded_mag,
                  (InpMS_TesterAllowUnavailable ? "true" : "false"),
                  (IsTesterRuntime() ? "true" : "false"));
   }
   #endif

   // 11) Boot registry from finalized snapshot (MOVE 2471–2475)
   if(InpProfileApply)
      BootRegistry_WithProfile(S, ps);
   else
      BootRegistry_NoProfile(S);
   
   // 12) Sync router + routing mode flag from finalized snapshot
   StratReg::SyncRouterFromSettings(S);
   
   // Re-assert canonical router threshold resolution after registry/settings sync.
   // This keeps the resolved min_score/max_strats as the single source of truth.
   if(InpProfileApply)
      ApplyRouterConfig_Profile(ps);
   else
      ApplyRouterConfig();
   
   UpdateRegistryRoutingFlag();
   DriftAlarm_SetApproved("FinalizeRuntimeSettings");
}

void UI_CommitSettings(const string reason, const bool resync_router=false)
{
   // Recompute derived flags into the UI snapshot (allowed: hotkey mutation)
   SyncRuntimeCfgFlags(S);

   // Keep strat_mode authoritative even when UI/hotkeys toggle flags.
   Config::EnforceStrategyModeToggles(S);

   // Mirror UI snapshot into canonical runtime snapshot
   g_cfg = S;

   // If a UI hotkey ever changes routing/mode/enable flags, resync router and routing flag
   if(resync_router)
   {
      StratReg::SyncRouterFromSettings(S);
   
      if(InpProfileApply)
      {
         Config::ProfileSpec ps;
         Config::BuildProfileSpec((TradingProfile)InpProfileType, ps);
         ApplyRouterConfig_Profile(ps);
      }
      else
      {
         ApplyRouterConfig();
      }
   
      UpdateRegistryRoutingFlag();
   }

   // UI breadcrumb: confirms whether RouterPool is active after UI mutations
   if(InpDebug)
     LogRouterConfluencePoolStatus(S, "[UI]");
      
   if(InpDebug)
      LogX::Info(StringFormat("[UI] Settings committed: %s", reason));

   EA_LogRuntimeGateSummary("[UI]", S);
   DriftAlarm_SetApproved(reason);
}

//===========================
// Runtime Drift Alarm Helpers
//===========================

string RuntimeSettingsHashHex(const Settings &cfg)
{
   // Uses existing hashing helper already present in your codebase (Tester.mqh).
   // It compiles in live as well (you already call it elsewhere).
   return TesterX::SettingsHashHex(cfg);
}

void DriftAlarm_SetApproved(const string reason)
{
   if(!InpDriftAlarm)
   {
      g_drift_armed         = false;
      g_drift_hash_approved = "";
      return;
   }

   // Approved snapshot is whatever S currently is (and should already match g_cfg).
   g_drift_hash_approved = RuntimeSettingsHashHex(S);
   g_drift_armed         = true;

   // Reset alert throttles for the new approved baseline
   g_drift_last_alert    = 0;
   g_drift_alert_count   = 0;
   g_drift_hash_last_s   = "";
   g_drift_hash_last_cfg = "";

   if(InpDebug)
      LogX::Info(StringFormat("[DRIFT] Approved snapshot (%s) hash=%s", reason, g_drift_hash_approved));
}

void DriftAlarm_Check(const string where)
{
   if(!InpDriftAlarm || !g_drift_armed)
      return;

   // Throttle checks (seconds granularity is sufficient for “instant regression catch”)
   datetime now = TimeCurrent();
   if(g_drift_last_check != 0 && (now - g_drift_last_check) < 1)
      return;
   g_drift_last_check = now;

   const string hs = RuntimeSettingsHashHex(S);
   const string hc = RuntimeSettingsHashHex(g_cfg);

   // Primary requirement: hash-compare S vs g_cfg
   const bool mismatch = (hs != hc);

   // Secondary reinforcement: detect “unauthorized S mutation” even if someone also changed g_cfg
   const bool unauthorized = (g_drift_hash_approved != "" && hs != g_drift_hash_approved);

   if(!mismatch && !unauthorized)
      return;

   // Avoid spamming: only repeat within 10s if hashes changed
   if(g_drift_last_alert != 0 && (now - g_drift_last_alert) < 10 &&
      hs == g_drift_hash_last_s && hc == g_drift_hash_last_cfg)
      return;

   g_drift_last_alert   = now;
   g_drift_alert_count++;

   g_drift_hash_last_s   = hs;
   g_drift_hash_last_cfg = hc;

   string msg = StringFormat(
      "DRIFT_ALARM[%s] Settings drift detected. S must remain read-only after finalize. "
      "S_hash=%s g_cfg_hash=%s approved=%s alerts=%d",
      where, hs, hc, g_drift_hash_approved, g_drift_alert_count
   );

   // “Scream” into Journal
   Print(msg);
   LogX::Error(msg);
   
   // Optional: hard-stop NEW trading if drift is detected
   if(InpDriftHaltTrading && !g_inhibit_trading)
   {
      g_inhibit_trading = true;
      Print("DRIFT_ALARM: Trading is now INHIBITED (restart EA after fixing the drift source).");
      LogX::Error("DRIFT_ALARM: Trading is now INHIBITED (restart EA after fixing the drift source).");
   }

   if(InpDebug)
      Print("DRIFT_ALARM hint: search for 'S.' assignments or any function taking Settings& that receives S.");
}

//--------------------------------------------------------------------
// RefreshICTContext()
// Pulls updated ICT/Wyckoff/Session view into State, so strategies
// can reason about bias, killzones, PO3, Silver Bullet, etc.
//--------------------------------------------------------------------
void RefreshICTContext(EAState &st)
{
   // StateUpdateICTContext() is implemented in State.mqh
   StateUpdateICTContext(st, g_cfg);
}

bool UseCanonicalInstitutionalStrictOpenBarAlignment()
{
   if(g_is_tester)
      return false;

   return InpInstStateStrictBarAlign;
}

int CanonicalInstitutionalRequiredBarShift()
{
   return (UseCanonicalInstitutionalStrictOpenBarAlignment() ? 0 : 1);
}

int CanonicalInstitutionalAllowedLagBars()
{
   if(g_is_tester)
      return 1;

   return (InpInstStateAllowOneBarLag ? 1 : 0);
}

void SyncStateInstitutionalBarFreshnessPolicy()
{
   StateSetInstitutionalBarFreshnessPolicy(UseCanonicalInstitutionalStrictOpenBarAlignment(),
                                           CanonicalInstitutionalAllowedLagBars());
}

datetime ResolveCanonicalInstitutionalClosedBarAnchorTime(const string sym)
{
   string use_sym = sym;
   if(use_sym == "")
      use_sym = CanonicalRouterSymbol();

   const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(g_cfg);
   if(use_sym == "" || tf == PERIOD_CURRENT)
      return (datetime)0;

   const datetime bar1 = iTime(use_sym, tf, 1);
   if(bar1 > 0)
      return bar1;

   const datetime bar0 = iTime(use_sym, tf, 0);
   if(bar0 <= 0)
      return (datetime)0;

   const int tf_sec = PeriodSeconds(tf);
   if(tf_sec <= 0)
      return (datetime)0;

   return (datetime)(bar0 - tf_sec);
}

datetime ResolveCanonicalInstitutionalRequiredBarTime(const string sym)
{
   string use_sym = sym;
   if(use_sym == "")
      use_sym = CanonicalRouterSymbol();

   const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(g_cfg);
   if(use_sym == "" || tf == PERIOD_CURRENT)
      return (datetime)0;

   const int required_shift = CanonicalInstitutionalRequiredBarShift();
   const datetime required_bar_time = iTime(use_sym, tf, required_shift);
   const datetime closed_bar_time   = ResolveCanonicalInstitutionalClosedBarAnchorTime(use_sym);

   if(required_shift > 0)
   {
      if(closed_bar_time > 0)
         return closed_bar_time;

      return required_bar_time;
   }

   if(required_bar_time > 0)
      return required_bar_time;

   return closed_bar_time;
}

string InstDiagTimeStr(const datetime t)
{
   if(t <= 0)
      return "-";

   return TimeToString(t, TIME_DATE | TIME_MINUTES);
}

bool EnsureCanonicalInstitutionalStateReady(const string sym,
                                            const datetime required_bar_time,
                                            string &diag_out)
{
   diag_out = "";

   datetime effective_required_bar_time = required_bar_time;
   if(effective_required_bar_time <= 0)
      effective_required_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(sym);

   int fresh_code = StateInstitutionalFreshnessDiagCode(g_state, effective_required_bar_time);
   string fresh_why = StateInstitutionalPromotionDiagReason(fresh_code);

   bool state_fresh = StateInstitutionalStateFresh(g_state, effective_required_bar_time) &&
                      StateInstitutionalFreshnessDiagAccepted(fresh_code);
   datetime head_bar_time = StateInstitutionalHeadSnapshotBarTime(g_state);

   bool bar_misaligned_hard = false;
   datetime bar_misaligned_closed_bar_time = (datetime)0;

   if(!state_fresh)
   {
      RefreshICTContext(g_state);

      if(!StateInstitutionalStateFresh(g_state, effective_required_bar_time) ||
         !StateInstitutionalFreshnessDiagAccepted(StateInstitutionalFreshnessDiagCode(g_state, effective_required_bar_time)))
      {
         string promote_why = "";
         StateTryPromoteCanonicalInstitutionalState(g_state,
                                                    g_cfg,
                                                    effective_required_bar_time,
                                                    promote_why);

         if(promote_why != "")
            diag_out = "promotion=" + promote_why;
      }

      fresh_code = StateInstitutionalFreshnessDiagCode(g_state, effective_required_bar_time);
      fresh_why = StateInstitutionalPromotionDiagReason(fresh_code);
      state_fresh = StateInstitutionalStateFresh(g_state, effective_required_bar_time) &&
                    StateInstitutionalFreshnessDiagAccepted(fresh_code);
      head_bar_time = StateInstitutionalHeadSnapshotBarTime(g_state);
   }

   if(!state_fresh && g_is_tester)
   {
      const datetime closed_bar_time = ResolveCanonicalInstitutionalClosedBarAnchorTime(sym);

      if(closed_bar_time > 0 &&
         effective_required_bar_time > 0 &&
         closed_bar_time != effective_required_bar_time)
      {
         bar_misaligned_hard = true;
         bar_misaligned_closed_bar_time = closed_bar_time;

         string lag_promote_why = "";
         StateTryPromoteCanonicalInstitutionalState(g_state,
                                                    g_cfg,
                                                    closed_bar_time,
                                                    lag_promote_why);

         const int lag_code = StateInstitutionalFreshnessDiagCode(g_state, closed_bar_time);
         if(StateInstitutionalStateFresh(g_state, closed_bar_time) &&
            StateInstitutionalFreshnessDiagAccepted(lag_code))
         {
            diag_out = StringFormat("tester_closed_bar_fallback req=%s fallback=%s reason=%s",
                                    InstDiagTimeStr(required_bar_time),
                                    InstDiagTimeStr(closed_bar_time),
                                    StateInstitutionalPromotionDiagReason(lag_code));

            if(lag_promote_why != "")
               diag_out += " | promotion=" + lag_promote_why;

            return true;
         }
      }
   }

   if(state_fresh)
      return true;

   const datetime flow_ts = StateInstitutionalFlowBundleTime(g_state);
   const bool direct_ok = StateInstitutionalDirectMicroAvailable(g_state);
   const bool proxy_ok  = StateInstitutionalProxyMicroAvailable(g_state);

   if(!state_fresh &&
      g_is_tester &&
      StateInstitutionalDegradedTransportUsable(g_state) &&
      flow_ts > 0)
   {
      diag_out = StringFormat("degraded_tester_usable flow=%s direct=%d proxy=%d head=%s req=%s reason=%s",
                              InstDiagTimeStr(flow_ts),
                              (direct_ok ? 1 : 0),
                              (proxy_ok ? 1 : 0),
                              InstDiagTimeStr(head_bar_time),
                              InstDiagTimeStr(effective_required_bar_time),
                              fresh_why);
      return true;
   }

   const string fail_tag = (bar_misaligned_hard ? "bar_misaligned_hard" : "state_invalid_canonical");

   if(flow_ts <= 0)
   {
      if(bar_misaligned_hard)
         diag_out = StringFormat("%s flow=- direct=%d proxy=%d head=%s req=%s closed=%s reason=%s",
                                 fail_tag,
                                 (direct_ok ? 1 : 0),
                                 (proxy_ok ? 1 : 0),
                                 InstDiagTimeStr(head_bar_time),
                                 InstDiagTimeStr(effective_required_bar_time),
                                 InstDiagTimeStr(bar_misaligned_closed_bar_time),
                                 fresh_why);
      else
         diag_out = StringFormat("%s flow=- direct=%d proxy=%d head=%s req=%s reason=%s",
                                 fail_tag,
                                 (direct_ok ? 1 : 0),
                                 (proxy_ok ? 1 : 0),
                                 InstDiagTimeStr(head_bar_time),
                                 InstDiagTimeStr(effective_required_bar_time),
                                 fresh_why);
      return false;
   }

   if(bar_misaligned_hard)
      diag_out = StringFormat("%s flow=%s direct=%d proxy=%d head=%s req=%s closed=%s reason=%s",
                              fail_tag,
                              InstDiagTimeStr(flow_ts),
                              (direct_ok ? 1 : 0),
                              (proxy_ok ? 1 : 0),
                              InstDiagTimeStr(head_bar_time),
                              InstDiagTimeStr(effective_required_bar_time),
                              InstDiagTimeStr(bar_misaligned_closed_bar_time),
                              fresh_why);
   else
      diag_out = StringFormat("%s flow=%s direct=%d proxy=%d head=%s req=%s reason=%s",
                              fail_tag,
                              InstDiagTimeStr(flow_ts),
                              (direct_ok ? 1 : 0),
                              (proxy_ok ? 1 : 0),
                              InstDiagTimeStr(head_bar_time),
                              InstDiagTimeStr(effective_required_bar_time),
                              fresh_why);
   return false;
}

void LogCanonicalInstitutionalGateDiag(const string sym,
                                       const datetime required_bar_time,
                                       const string origin_tag)
{
   if(!InpDebug)
      return;

   const string use_sym = (sym == "" ? CanonicalRouterSymbol() : sym);
   const datetime effective_required_bar_time = (required_bar_time > 0
                                                 ? required_bar_time
                                                 : ResolveCanonicalInstitutionalRequiredBarTime(use_sym));
   const datetime throttle_key = (effective_required_bar_time > 0 ? effective_required_bar_time : TimeCurrent());
   
   static string last_sym = "";
   static string last_origin = "";
   static datetime last_key = 0;
   
   if(use_sym == last_sym && origin_tag == last_origin && throttle_key == last_key)
      return;
   
   last_sym = use_sym;
   last_origin = origin_tag;
   last_key = throttle_key;
   
   const datetime flow_ts = StateInstitutionalFlowBundleTime(g_state);
   const bool direct_ok = StateInstitutionalDirectMicroAvailable(g_state);
   const bool proxy_ok  = StateInstitutionalProxyMicroAvailable(g_state);
   const datetime head_bar_time = StateInstitutionalHeadSnapshotBarTime(g_state);
   const int fresh_code = StateInstitutionalFreshnessDiagCode(g_state, effective_required_bar_time);
   const string fresh_why = StateInstitutionalPromotionDiagReason(fresh_code);
   const bool state_fresh = StateInstitutionalStateFresh(g_state, effective_required_bar_time) &&
                            StateInstitutionalFreshnessDiagAccepted(fresh_code);
   const string anchor_mode = (CanonicalInstitutionalRequiredBarShift() > 0 ? "closed_bar" : "open_bar");
   
   PrintFormat("[InstGateDiag][%s] sym=%s anchor=%s fresh=%d flow=%s direct=%d proxy=%d head=%s req=%s code=%d reason=%s",
               origin_tag,
               use_sym,
               anchor_mode,
               (state_fresh ? 1 : 0),
               InstDiagTimeStr(flow_ts),
               (direct_ok ? 1 : 0),
               (proxy_ok ? 1 : 0),
               InstDiagTimeStr(head_bar_time),
               InstDiagTimeStr(effective_required_bar_time),
               fresh_code,
               fresh_why);
}

void Inst_ResetTransportStamp()
{
   g_inst_transport.observability01               = 0.45;
   g_inst_transport.truth_tier01                  = 0.45;
   g_inst_transport.venue_scope01                 = 0.45;
   g_inst_transport.direct_micro_available        = false;
   g_inst_transport.proxy_micro_available         = false;
   g_inst_transport.inst_flow_bundle_freshness_code = 0;
}

bool Inst_IsLikelyOTCSymbol(const string sym)
{
   string u = sym;
   StringToUpper(u);

   if(StringLen(u) == 6)
      return true;

   if(StringFind(u, "XAU", 0) >= 0)
      return true;

   if(StringFind(u, "XAG", 0) >= 0)
      return true;

   return false;
}

int Inst_ResolveFreshnessCode(const datetime now_srv)
{
   if(g_ms_last_refresh > 0)
   {
      long age_sec = (long)(now_srv - g_ms_last_refresh);

      if(age_sec <= 1)
         return 3;

      if(age_sec <= 5)
         return 2;

      if(age_sec <= 30)
         return 1;
   }

   if(g_msh_dirty_n > 0)
      return 1;

   return 0;
}

double Inst_Clamp01(const double x)
{
   if(x < 0.0) return 0.0;
   if(x > 1.0) return 1.0;
   return x;
}

int Inst_DiagOrdinalFrom01(const double v01, const int max_value)
{
   if(max_value <= 0)
      return 0;

   int out = (int)MathRound(Inst_Clamp01(v01) * (double)max_value);

   if(out < 0) out = 0;
   if(out > max_value) out = max_value;

   return out;
}

int Inst_ResolveFlowMode()
{
   if(g_inst_transport.direct_micro_available)
      return STATE_INST_FLOW_MODE_DIRECT;

   if(g_inst_transport.proxy_micro_available)
      return STATE_INST_FLOW_MODE_PROXY;

   return STATE_INST_FLOW_MODE_STRUCTURE_ONLY;
}

string Inst_FlowModeToStr(const int mode)
{
   if(mode == STATE_INST_FLOW_MODE_DIRECT)         return "DIRECT";
   if(mode == STATE_INST_FLOW_MODE_PROXY)          return "PROXY";
   if(mode == STATE_INST_FLOW_MODE_STRUCTURE_ONLY) return "STRUCTURE_ONLY";
   return "UNKNOWN";
}

double Inst_CenteredStrengthAbs01(const double x01)
{
   return Inst_Clamp01(MathAbs((Inst_Clamp01(x01) - 0.5) * 2.0));
}

bool Inst_ReadCanonicalMicroGateMetrics(const string sym,
                                        const datetime required_bar_time,
                                        double &ofi_abs01,
                                        double &obi_abs01,
                                        double &vpin01,
                                        double &resil01,
                                        bool &direct_ok,
                                        bool &proxy_ok,
                                        int &flow_mode,
                                        datetime &flow_ts,
                                        string &detail)
{
   detail    = "";
   ofi_abs01 = 0.0;
   obi_abs01 = 0.0;
   vpin01    = 0.0;
   resil01   = 1.0;
   direct_ok = false;
   proxy_ok  = false;
   flow_mode = STATE_INST_FLOW_MODE_STRUCTURE_ONLY;
   flow_ts   = (datetime)0;

   if(sym == "")
      return true;
   
   const datetime effective_required_bar_time = (required_bar_time > 0
                                                 ? required_bar_time
                                                 : ResolveCanonicalInstitutionalRequiredBarTime(sym));
   const datetime head_bar_time = StateInstitutionalHeadSnapshotBarTime(g_state);
   const int fresh_code = StateInstitutionalFreshnessDiagCode(g_state, effective_required_bar_time);
   const string fresh_why = StateInstitutionalPromotionDiagReason(fresh_code);
   
   const bool state_fresh = StateInstitutionalStateFresh(g_state, effective_required_bar_time) &&
                            StateInstitutionalFreshnessDiagAccepted(fresh_code);
   if(!state_fresh)
   {
      detail = StringFormat("canonical institutional state unavailable req=%s head=%s reason=%s",
                            InstDiagTimeStr(effective_required_bar_time),
                            InstDiagTimeStr(head_bar_time),
                            fresh_why);
      return false;
   }

   ofi_abs01 = Inst_CenteredStrengthAbs01(StateInstitutionalOFI01(g_state));
   obi_abs01 = Inst_CenteredStrengthAbs01(StateInstitutionalOBI01(g_state));
   vpin01    = Inst_Clamp01(StateInstitutionalVPIN01(g_state));
   resil01   = Inst_Clamp01(StateInstitutionalResiliency01(g_state));

   direct_ok = StateInstitutionalDirectMicroAvailable(g_state);
   proxy_ok  = StateInstitutionalProxyMicroAvailable(g_state);
   flow_mode = StateInstitutionalFlowMode(g_state);
   flow_ts   = StateInstitutionalFlowBundleTime(g_state);

   if(!direct_ok && !proxy_ok)
   {
      if(StateInstitutionalDegradedTransportUsable(g_state))
         detail = StringFormat("degraded canonical transport active req=%s head=%s flow=%s reason=%s",
                               InstDiagTimeStr(effective_required_bar_time),
                               InstDiagTimeStr(head_bar_time),
                               InstDiagTimeStr(flow_ts),
                               fresh_why);
      else
         detail = StringFormat("canonical micro route unavailable req=%s head=%s flow=%s reason=%s",
                               InstDiagTimeStr(effective_required_bar_time),
                               InstDiagTimeStr(head_bar_time),
                               InstDiagTimeStr(flow_ts),
                               fresh_why);
   
      return false;
   }
   
   if(flow_ts <= 0)
   {
      detail = StringFormat("canonical micro bundle time unavailable req=%s head=%s flow=%s reason=%s",
                            InstDiagTimeStr(effective_required_bar_time),
                            InstDiagTimeStr(head_bar_time),
                            InstDiagTimeStr(flow_ts),
                            fresh_why);
      return false;
   }

   return true;
}

void Inst_BuildTransportStamp(const string sym)
{
   Inst_ResetTransportStamp();

   if(sym == "")
      return;

   const bool otc = Inst_IsLikelyOTCSymbol(sym);
   const bool direct_ok = g_ms_last_ok;
   const bool proxy_ok  = (g_ms_last_refresh > 0 || g_msh_dirty_n > 0);

   g_inst_transport.direct_micro_available = direct_ok;
   g_inst_transport.proxy_micro_available  = proxy_ok;
   g_inst_transport.inst_flow_bundle_freshness_code = Inst_ResolveFreshnessCode(TimeUtils::NowServer());

   if(otc)
      g_inst_transport.venue_scope01 = 0.45;
   else
      g_inst_transport.venue_scope01 = 0.85;

   if(direct_ok)
   {
      g_inst_transport.observability01 = 1.00;
      g_inst_transport.truth_tier01    = (otc ? 0.70 : 1.00);
      return;
   }

   if(proxy_ok)
   {
      g_inst_transport.observability01 = 0.70;
      g_inst_transport.truth_tier01    = (otc ? 0.55 : 0.70);
      return;
   }

   g_inst_transport.observability01 = 0.45;
   g_inst_transport.truth_tier01    = (otc ? 0.45 : 0.55);
}

void Inst_CommitTransportStampToState(EAState &st)
{
   if(StateInstitutionalStateFresh(st) || StateInstitutionalDegradedTransportUsable(st))
      return;

   double observability01 = Inst_Clamp01(g_inst_transport.observability01);
   int truth_tier = Inst_DiagOrdinalFrom01(g_inst_transport.truth_tier01, STATE_DIAG_TRUTHTIER_MAX);
   int venue_scope = Inst_DiagOrdinalFrom01(g_inst_transport.venue_scope01, STATE_DIAG_VENUESCOPE_MAX);

   // Preserve richer canonical values when State already has a fresh transport.
   if(StateInstitutionalStateFresh(st))
   {
      observability01 = StateInstitutionalObservability01(st);
      truth_tier      = st.inst_state_truthTier;
      venue_scope     = st.inst_state_venueScope;
   }

   StateSetInstitutionalTransportStamp(st,
                                       observability01,
                                       truth_tier,
                                       venue_scope,
                                       g_inst_transport.direct_micro_available,
                                       g_inst_transport.proxy_micro_available,
                                       Inst_ResolveFlowMode(),
                                       g_ms_last_refresh,
                                       g_inst_transport.inst_flow_bundle_freshness_code);
}

string CanonicalRouterSymbol()
{
   return (g_symCount > 0 ? g_symbols[0] : _Symbol);
}

bool IsTesterRuntime()
{
   return ((MQLInfoInteger(MQL_TESTER) != 0) ||
           (MQLInfoInteger(MQL_OPTIMIZATION) != 0) ||
           (MQLInfoInteger(MQL_VISUAL_MODE) != 0));
}

void ApplyTesterOnlyFeatureOverrides(Settings &cfg)
{
   // Legacy bridge retained for compile-safe compatibility.
   // Central tester override ownership now lives in:
   // include/TesterSettings.mqh
   TesterSettings::ApplyToConfig(cfg);
}

bool MicrostructureGateOK(const string sym, const datetime now_srv, const datetime required_bar_time, string &detail)
{
   detail = "";

   if(EA_MicrostructureGateDisabled())
   {
      detail = "microstructure_gate_disabled_runtime";
      PublishTesterDegradedFallbackRuntimeState(sym, true, "runtime_disabled", detail);
      return true;
   }

   if(!InpMS_EnableRuntimeGate)
   {
      PublishTesterDegradedFallbackRuntimeState(sym, false, "off", "gate_disabled");
      return true;
   }

   if(sym == "")
   {
      PublishTesterDegradedFallbackRuntimeState(sym, false, "off", "sym_empty");
      return true;
   }

   if(IsTesterRuntime() && ResolveTesterRouterGateMode() == TESTER_ROUTER_GATE_MODE_BYPASS)
   {
      detail = "tester_bypass_policy_gates";
      PublishTesterDegradedFallbackRuntimeState(sym, true, "tester_bypass", detail);
      return true;
   }

   const datetime effective_required_bar_time = (required_bar_time > 0
                                                 ? required_bar_time
                                                 : ResolveCanonicalInstitutionalRequiredBarTime(sym));

   bool tester_allow_degraded = false;

   #ifdef CFG_HAS_ALLOW_TESTER_DEGRADED_INST_FALLBACK
      tester_allow_degraded = S.allow_tester_degraded_inst_fallback;
   #else
      tester_allow_degraded = InpMS_TesterAllowUnavailable;
   #endif

   string published_fb_status = "off";
   if(IsTesterRuntime())
      published_fb_status = (tester_allow_degraded ? "standby" : "disabled");

   PublishTesterDegradedFallbackRuntimeState(sym, false, published_fb_status, "");

   double ofi_abs01   = 0.0;
   double obi_abs01   = 0.0;
   double vpin01      = 0.0;
   double resil01     = 1.0;
   bool   direct_ok   = false;
   bool   proxy_ok    = false;
   int    flow_mode   = STATE_INST_FLOW_MODE_STRUCTURE_ONLY;
   datetime flow_ts   = 0;
   string state_detail = "";

   if(!Inst_ReadCanonicalMicroGateMetrics(sym,
                                          effective_required_bar_time,
                                          ofi_abs01,
                                          obi_abs01,
                                          vpin01,
                                          resil01,
                                          direct_ok,
                                          proxy_ok,
                                          flow_mode,
                                          flow_ts,
                                          state_detail))
   {
      if(!InpMS_BlockIfUnavailable)
      {
         PublishTesterDegradedFallbackRuntimeState(sym, false, published_fb_status, state_detail);
         return true;
      }

      if(IsTesterRuntime() && tester_allow_degraded)
      {
         detail = "tester_fallback: " + state_detail;
         PublishTesterDegradedFallbackRuntimeState(sym, true, "active", detail);

         if(InpMS_TesterLogUnavailable)
         {
            datetime throttle_key = effective_required_bar_time;
            if(throttle_key <= 0)
               throttle_key = now_srv;

            static string   last_sym = "";
            static datetime last_key = 0;

            if(last_sym != sym || last_key != throttle_key)
            {
               last_sym = sym;
               last_key = throttle_key;

               PrintFormat("[MSGate][TESTER_FALLBACK] sym=%s detail=%s",
                           sym,
                           detail);
            }
         }

         return true;
      }

      detail = state_detail;
      PublishTesterDegradedFallbackRuntimeState(sym, false, published_fb_status, detail);
      return false;
   }

   datetime freshness_anchor_time = effective_required_bar_time;
   if(freshness_anchor_time <= 0)
      freshness_anchor_time = now_srv;
   
   long age_ms = (long)(freshness_anchor_time - flow_ts) * 1000;
   if(age_ms < 0)
      age_ms = 0;
   
   if((int)age_ms > InpMS_MaxSnapshotAgeMs)
   {
      detail = StringFormat("canonical micro stale age_ms=%d max_ms=%d mode=%s req=%s flow=%s",
                            (int)age_ms,
                            InpMS_MaxSnapshotAgeMs,
                            Inst_FlowModeToStr(flow_mode),
                            InstDiagTimeStr(freshness_anchor_time),
                            InstDiagTimeStr(flow_ts));
      return false;
   }

   bool fail = false;

   // Always enforce toxicity / resiliency
   if(vpin01 > InpMS_MaxVPIN)
      fail = true;

   if(resil01 < InpMS_MinResiliency)
      fail = true;

   // Only enforce OFI / OBI floors when direct micro is genuinely available.
   // FX / OTC proxy paths must not be hard-blocked by structurally neutral
   // raw OFI / OBI values.
   if(direct_ok)
   {
      if(ofi_abs01 < InpMS_MinOFIAbs)
         fail = true;

      if(obi_abs01 < InpMS_MinOBIAbs)
         fail = true;
   }

   if(fail)
   {
      detail = StringFormat("canonical micro fail mode=%s ofi=%.3f obi=%.3f vpin=%.3f resil=%.3f direct=%d proxy=%d req=%s flow=%s",
                            Inst_FlowModeToStr(flow_mode),
                            ofi_abs01,
                            obi_abs01,
                            vpin01,
                            resil01,
                            (direct_ok ? 1 : 0),
                            (proxy_ok ? 1 : 0),
                            InstDiagTimeStr(freshness_anchor_time),
                            InstDiagTimeStr(flow_ts));
      return false;
   }

   const bool degraded_gate_active =
      (tester_allow_degraded &&
       StateInstitutionalDegradedTesterUsableActive(g_state,
                                                    effective_required_bar_time));

   if(degraded_gate_active)
   {
      const string degraded_detail =
         StringFormat("degraded_tester_usable mode=%s req=%s flow=%s",
                      Inst_FlowModeToStr(flow_mode),
                      InstDiagTimeStr(freshness_anchor_time),
                      InstDiagTimeStr(flow_ts));

      PublishTesterDegradedFallbackRuntimeState(sym,
                                                true,
                                                "degraded_tester_usable",
                                                degraded_detail);
   }
   else
   {
      PublishTesterDegradedFallbackRuntimeState(sym,
                                                false,
                                                published_fb_status,
                                                "");
   }

   return true;
}

//--------------------------------------------------------------------
// Backend-only UI wrappers
//--------------------------------------------------------------------
void UI_Render(const Settings &cfg)
{
#ifdef BUILD_WITH_UI
   Panel::Render(cfg);
#endif
}

void UI_SetGate(const int gate_reason)
{
#ifdef BUILD_WITH_UI
   Panel::SetGate(gate_reason);
#endif
}

void UI_Init(const Settings &cfg)
{
#ifdef BUILD_WITH_UI
   Panel::Init(cfg);
   Panel::ShowBreakdown(g_show_breakdown);
   Panel::SetCalmMode(g_calm_mode);
   Review::EnableScreenshots(InpReviewScreenshots, InpReviewSS_W, InpReviewSS_H);
#endif
}

void UI_Deinit()
{
#ifdef BUILD_WITH_UI
   Panel::Deinit();
   ReviewUI_ICT_Deinit();
   ReviewUI_Deinit();
#endif
}

void UI_PublishDecision(const ConfluenceBreakdown &bd, const StratScore &ss)
{
#ifdef BUILD_WITH_UI
   Panel::PublishBreakdown(bd);
   Panel::PublishScores(ss);
#endif
}

void UI_OnTradeTransaction(const MqlTradeTransaction &tx, const MqlTradeResult &rs)
{
#ifdef BUILD_WITH_UI
   Review::OnTx(tx, rs);
#endif
}

void UI_Screenshot(const string tag)
{
#ifdef BUILD_WITH_UI
   Review::Screenshot(tag);
#endif
}

//--------------------------------------------------------------------
// RefreshMicrostructureSnapshot()
// Requires MarketData::UpdateMicrostructureStats(...) and MicrostructureStats.
//--------------------------------------------------------------------
bool RefreshMicrostructureSnapshot(const string sym, const bool force_refresh)
{
   datetime now_srv = TimeUtils::NowServer();

   if(!force_refresh && g_ms_last_symbol == sym && g_ms_last_refresh != 0)
   {
      long age_ms = (long)(now_srv - g_ms_last_refresh) * 1000;
      if(age_ms >= 0 && age_ms < InpMS_RefreshMinMs)
         return g_ms_last_ok;
   }

   ZeroMemory(g_ms_last);
   g_ms_last_ok = MarketData::UpdateMicrostructureStats(sym, g_cfg, g_ms_last);
   g_ms_last_symbol = sym;
   g_ms_last_refresh = now_srv;

   if(!g_ms_last_ok)
   {
      g_ms_gate_pass = false;
      return false;
   }

   // IMPORTANT:
   // g_ms_last remains a lightweight EA-side raw cache only.
   // The live runtime veto is computed from canonical State/ICT transport
   // inside MicrostructureGateOK(), not from this raw cache.
   g_ms_gate_pass = g_ms_last_ok;
   
   //g_ms_gate_pass = true;
   //if(InpMS_EnableRuntimeGate)
   //{
   //   if(MathAbs(g_ms_last.ofi_norm) < InpMS_MinOFIAbs)      g_ms_gate_pass = false;
   //   if(MathAbs(g_ms_last.obi_norm) < InpMS_MinOBIAbs)      g_ms_gate_pass = false;
   //   if(g_ms_last.vpin > InpMS_MaxVPIN)                     g_ms_gate_pass = false;
   //   if(g_ms_last.resiliency < InpMS_MinResiliency)         g_ms_gate_pass = false;
   //}

   return true;
}

//--------------------------------------------------------------------
// PublishMicrostructureSnapshot()
// Bridge into Router / StrategyRegistry / State-side consumers.
//--------------------------------------------------------------------
void PublishMicrostructureSnapshot(const string sym)
{
   // Thin EA bridge only.
   // 1) MarketData owns scanner/microstructure production
   // 2) MarketScannerHub owns scan cadence
   // 3) State owns canonical runtime context
   // 4) Router / Strategy / Risk / Execution consume cached context
   //
   // Keep this as the canonical publish hook, but do NOT recompute
   // State / ICT / scanner math here.

   // Transport stamp only.
   // No canonical institutional state promotion here.
   // No scanner/confluence recomputation here.
   Inst_BuildTransportStamp(sym);

   if(!StateInstitutionalStateFresh(g_state) &&
      !StateInstitutionalDegradedTransportUsable(g_state))
   {
      Inst_CommitTransportStampToState(g_state);
   }

   if(sym == "")
      return;

   if(!g_ms_last_ok)
      return;
}

void RefreshRuntimeContextLight(const string sym = "")
{
   const string use_sym = (sym == "" ? CanonicalRouterSymbol() : sym);

   if(use_sym != "" && g_state.symbol != use_sym)
   {
      g_state.symbol = use_sym;
      g_state.digits = (int)SymbolInfoInteger(use_sym, SYMBOL_DIGITS);
      g_state.point  = SymbolInfoDouble(use_sym, SYMBOL_POINT);
      if(g_state.point <= 0.0)
         g_state.point = _Point;

      g_state.tickValue = SymbolInfoDouble(use_sym, SYMBOL_TRADE_TICK_VALUE);
      if(g_state.tickValue <= 0.0)
         g_state.tickValue = SymbolInfoDouble(use_sym, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      if(g_state.tickValue <= 0.0)
         g_state.tickValue = SymbolInfoDouble(use_sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   }

   StateOnTickUpdate(g_state);
   RefreshICTContext(g_state);
}

void ResetCanonicalSignalStackTransport()
{
   g_raw_bank.Reset();
   g_cat_selected.Reset();
   g_cat_pass.Reset();
   g_sig_stack_gate.Reset();
   g_location_pass.Reset();
   g_hyp_bank.Reset();
   g_final_integrated.Reset();

   g_transport_ready = false;
   g_transport_bar_time = 0;
   g_transport_sym = "";
}

bool BuildCanonicalSignalStackTransport(const string sym,
                                       const datetime required_bar_time,
                                       string &diag_out)
{
   diag_out = "";

   const string use_sym = (sym == "" ? CanonicalRouterSymbol() : sym);
   if(use_sym == "")
   {
      ResetCanonicalSignalStackTransport();
      diag_out = "router_symbol_empty";
      return false;
   }

   ResetCanonicalSignalStackTransport();

   // 1) Canonical raw market state + derived category transport
   const ENUM_TIMEFRAMES isv_tf = Warmup::TF_Entry(g_cfg);
   if(isv_tf == PERIOD_CURRENT)
   {
      diag_out = "raw_bank_tf_invalid";
      return false;
   }

   const int isv_closed_shift = CanonicalInstitutionalRequiredBarShift();
   const int isv_z_window = (g_cfg.scan_obi_z_window > 0 ? g_cfg.scan_obi_z_window : 80);

   static ISV::Runtime s_isv_runtime;
   static string s_isv_runtime_symbol = "";
   static ENUM_TIMEFRAMES s_isv_runtime_tf = PERIOD_CURRENT;

   if((!s_isv_runtime.initialized) ||
      s_isv_runtime_symbol != use_sym ||
      s_isv_runtime_tf != isv_tf)
   {
      s_isv_runtime.Reset(isv_z_window);
      s_isv_runtime_symbol = use_sym;
      s_isv_runtime_tf = isv_tf;
   }

   ISV::Result isv_result;
   if(!ISV::Build(use_sym,
                  isv_tf,
                  g_cfg,
                  s_isv_runtime,
                  isv_result,
                  isv_closed_shift))
   {
      diag_out = "raw_bank_build_failed";
      return false;
   }

   if(required_bar_time > 0 &&
      isv_result.bar_time > 0 &&
      isv_result.bar_time != required_bar_time)
   {
      diag_out = "raw_bank_bar_mismatch";
      return false;
   }

   if(!ISV::BuildRawSignalBank(isv_result, g_raw_bank))
   {
      diag_out = "raw_bank_project_failed";
      return false;
   }

   g_cat_selected = isv_result.cat_sel;
   g_cat_pass     = isv_result.cat_pass;
   ISV::FillSignalStackGateFromResult(isv_result, g_sig_stack_gate);
   ISV::FillLocationPassFromResult(isv_result, g_location_pass);

   // 2) Strategy hypothesis bank
   g_hyp_bank.Reset();

   if(!StratReg::BuildHypothesesFromRegistry(g_cfg,
                                             g_state,
                                             g_raw_bank,
                                             g_cat_selected,
                                             g_cat_pass,
                                             g_sig_stack_gate,
                                             g_location_pass,
                                             g_hyp_bank))
   {
      diag_out = "hypothesis_bank_build_failed";
      return false;
   }

   g_transport_ready = true;
   g_transport_bar_time = required_bar_time;
   g_transport_sym = use_sym;

   return true;
}

void RefreshRuntimeContextFromHub(const string sym, const bool force_micro_refresh)
{
   if(sym != "")
      RefreshMicrostructureSnapshot(sym, force_micro_refresh);

   RefreshRuntimeContextLight((sym == "" ? CanonicalRouterSymbol() : sym));

   const datetime requested_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(sym);
   string inst_diag = "";
   const bool inst_ready = EnsureCanonicalInstitutionalStateReady(sym, requested_bar_time, inst_diag);

   if(InpDebug && !inst_ready && inst_diag != "")
   {
      const string log_sym = (sym == "" ? CanonicalRouterSymbol() : sym);
      const datetime throttle_key = (requested_bar_time > 0 ? requested_bar_time : TimeCurrent());

      static string last_sym = "";
      static datetime last_key = 0;

      if(log_sym != last_sym || throttle_key != last_key)
      {
         last_sym = log_sym;
         last_key = throttle_key;

         PrintFormat("[InstReady] sym=%s ready=0 req=%s detail=%s",
                     log_sym,
                     InstDiagTimeStr(requested_bar_time),
                     inst_diag);
      }
   }

   // Publish canonical runtime transport only.
   // Do NOT build strategy hypotheses or route orders here.
   // The timer-owned route pass is the single owner of:
   // raw-bank build -> category selection -> hypothesis build -> router evaluation.
   PublishMicrostructureSnapshot(sym);

   EA_LogInstitutionalDegradeStateOncePerBar((sym == "" ? CanonicalRouterSymbol() : sym),
                                             requested_bar_time);
}

bool PreseedRuntimeSymbolStateAtStartup(const string sym,
                                        const Settings &cfg,
                                        string &diag_out)
{
   diag_out = "";

   const string use_sym = (sym == "" ? _Symbol : sym);
   const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)cfg.tf_entry;

   if(use_sym == "" || tf <= PERIOD_CURRENT)
   {
      diag_out = "invalid_symbol_or_tf";
      return false;
   }

   // Step 1: create / hydrate the runtime symbol slot even if promotion is not ready yet.
   EAState st_sym;
   if(!State::TryGetRuntimeStateBySymbol(cfg, use_sym, st_sym, false))
   {
      diag_out = "runtime_slot_seed_failed";
      return false;
   }

   State::UpsertRuntimeSymbolState(use_sym, st_sym);

   // Step 2: make sure the entry-TF inputs are available before trying promotion.
   const int bars_need = MathMax(100, MathMin(600, Warmup::NeededBars(cfg)));
   if(!MarketData::EnsureRuntimeStateInputsReady(use_sym, tf, bars_need))
   {
      diag_out = "runtime_slot_seeded_inputs_pending";
      return false;
   }

   // Step 3: prefer snapshot-driven canonical promotion when startup already has one.
   datetime required_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(use_sym);
   if(required_bar_time <= 0)
      required_bar_time = iTime(use_sym, tf, 1);
   if(required_bar_time <= 0)
      required_bar_time = iTime(use_sym, tf, 0);

   bool promoted_from_snapshot =
      Scan::PromoteRuntimeSymbolStateFromSnapshot(cfg,
                                                  use_sym,
                                                  tf,
                                                  required_bar_time);

   // Step 4: if no current snapshot is available yet, fall back to local State promotion.
   if(!promoted_from_snapshot)
   {
      StateOnTickUpdate(st_sym);
      RefreshICTContext(st_sym);

      string promote_why = "";
      StateTryPromoteCanonicalInstitutionalState(st_sym,
                                                 cfg,
                                                 required_bar_time,
                                                 promote_why);

      State::UpsertRuntimeSymbolState(use_sym, st_sym);

      if(promote_why != "")
         diag_out = "promotion=" + promote_why;
      else
         diag_out = "runtime_slot_seeded_local_promotion";
   }
   else
   {
      diag_out = "snapshot_promoted";
   }

   // Step 5: reload the symbol slot and confirm readiness.
   EAState st_chk;
   if(State::TryGetRuntimeStateBySymbol(cfg, use_sym, st_chk, false) &&
      StateInstitutionalStrategyReady(st_chk, required_bar_time))
   {
      return true;
   }

   if(diag_out == "")
      diag_out = "runtime_slot_seeded_not_ready";

   return false;
}

void PreseedRuntimeSymbolPoolAtStartup(const Settings &cfg)
{
   int attempted = 0;
   int seeded    = 0;
   int ready     = 0;

   const string router_sym = CanonicalRouterSymbol();

   // Seed the canonical router symbol first so the first route pass is less cold.
   if(router_sym != "")
   {
      attempted++;

      string diag0 = "";
      const bool ok0 = PreseedRuntimeSymbolStateAtStartup(router_sym, cfg, diag0);

      EAState tmp0;
      if(State::TryGetRuntimeStateBySymbol(cfg, router_sym, tmp0, false))
         seeded++;

      if(ok0)
         ready++;

      if(InpDebug || !ok0)
      {
         LogX::Info(StringFormat("[StatePoolBootstrap] sym=%s ready=%d detail=%s",
                                 router_sym,
                                 (ok0 ? 1 : 0),
                                 diag0));
      }
   }

   // Seed the remainder of the watchlist once.
   for(int i = 0; i < g_symCount; i++)
   {
      const string sym = g_symbols[i];
      if(sym == "" || sym == router_sym)
         continue;

      attempted++;

      string diag = "";
      const bool ok = PreseedRuntimeSymbolStateAtStartup(sym, cfg, diag);

      EAState tmp;
      if(State::TryGetRuntimeStateBySymbol(cfg, sym, tmp, false))
         seeded++;

      if(ok)
         ready++;

      if(InpDebug || !ok)
      {
         LogX::Info(StringFormat("[StatePoolBootstrap] sym=%s ready=%d detail=%s",
                                 sym,
                                 (ok ? 1 : 0),
                                 diag));
      }
   }

   LogX::Info(StringFormat("[StatePoolBootstrap] seeded=%d ready=%d attempted=%d entry_tf=%d router_sym=%s",
                           seeded,
                           ready,
                           attempted,
                           (int)cfg.tf_entry,
                           (router_sym == "" ? "-" : router_sym)));
}

bool EA_IsTrackedWatchlistSymbol(const string sym)
{
   if(sym == "")
      return false;

   for(int i = 0; i < g_symCount; i++)
   {
      if(g_symbols[i] == sym)
         return true;
   }

   return false;
}

void EA_EnsureCentralDOMSubscriptions()
{
   const bool dom_enabled = (g_cfg.extra_dom_imbalance || InpExtra_DOMImbalance);
   if(!dom_enabled)
      return;

   OBI::Settings obi;
   obi.enabled = true;

   for(int i = 0; i < g_symCount; i++)
   {
      if(i >= ArraySize(g_dom_book_owned))
         break;

      const string sym = g_symbols[i];
      if(sym == "")
         continue;

      if(g_dom_book_owned[i])
         continue;

      if(!SymbolSelect(sym, true))
      {
         if(InpDebug)
            LogX::Warn(StringFormat("[DOM] SymbolSelect failed sym=%s", sym));
         continue;
      }

      long book_depth = 0;
      if(!SymbolInfoInteger(sym, SYMBOL_TICKS_BOOKDEPTH, book_depth) || book_depth <= 0)
      {
         if(InpDebug)
            LogX::Info(StringFormat("[DOM] skipped sym=%s reason=no_book_depth", sym));
         continue;
      }

      OBI::EnsureSubscribed(sym, obi);
      g_dom_book_owned[i] = true;

      if(InpDebug)
         LogX::Info(StringFormat("[DOM] subscribed sym=%s depth=%d", sym, (int)book_depth));
   }
}

void EA_ReleaseCentralDOMSubscriptions()
{
   for(int i = 0; i < g_symCount; i++)
   {
      if(i >= ArraySize(g_dom_book_owned))
         break;

      if(!g_dom_book_owned[i])
         continue;

      const string sym = g_symbols[i];
      if(sym != "")
         MarketBookRelease(sym);

      g_dom_book_owned[i] = false;
   }
}

void DecisionTelemetry_ResetTimerNotNewBarThrottle(const string sym,
                                                   const ENUM_TIMEFRAMES tf,
                                                   const datetime bar_time,
                                                   const datetime latch_time)
{
   const int idx = IndexOfSymbol(sym);
   if(idx < 0 || idx >= ArraySize(g_decision_tel_timer_skip_bar))
      return;

   g_decision_tel_timer_skip_tf[idx]       = (int)tf;
   g_decision_tel_timer_skip_bar[idx]      = bar_time;
   g_decision_tel_timer_skip_latch[idx]    = latch_time;
   g_decision_tel_timer_skip_emitted[idx]  = false;
}

bool DecisionTelemetry_ShouldEmitTimerNotNewBar(const string sym,
                                                const ENUM_TIMEFRAMES tf,
                                                const datetime bar_time,
                                                const datetime latch_time)
{
   const int idx = IndexOfSymbol(sym);
   if(idx < 0 || idx >= ArraySize(g_decision_tel_timer_skip_bar))
      return true;

   if(g_decision_tel_timer_skip_tf[idx]    != (int)tf ||
      g_decision_tel_timer_skip_bar[idx]   != bar_time ||
      g_decision_tel_timer_skip_latch[idx] != latch_time)
   {
      g_decision_tel_timer_skip_tf[idx]      = (int)tf;
      g_decision_tel_timer_skip_bar[idx]     = bar_time;
      g_decision_tel_timer_skip_latch[idx]   = latch_time;
      g_decision_tel_timer_skip_emitted[idx] = false;
   }

   if(g_decision_tel_timer_skip_emitted[idx])
      return false;

   g_decision_tel_timer_skip_emitted[idx] = true;
   return true;
}

void DecisionTelemetry_MarkPassiveSkip(const string why)
{
   g_decision_tel.status = "decision_skipped";
   g_decision_tel.last_drop_reason = why;
}

void DecisionTelemetry_MarkGateBlocked(const string source, const string why)
{
   g_decision_tel.decision_source = source;
   g_decision_tel.status = "gate_blocked";
   g_decision_tel.last_drop_reason = why;
}

void DecisionTelemetry_MarkNoCandidates(const string source, const string why)
{
   g_decision_tel.decision_source = source;
   g_decision_tel.status = "no_candidates";
   g_decision_tel.last_drop_reason = why;
}

void DecisionTelemetry_RecordPassFromPick(const string source,
                                          const StratReg::RoutedPick &pick)
{
   string armed_name = "";
   StratReg::GetStrategyNameById((StrategyID)pick.id, armed_name);

   g_decision_tel.decision_source     = source;
   g_decision_tel.status              = "decision_passed";
   g_decision_tel.last_drop_reason    = "";
   g_decision_tel.has_decision_ts     = true;
   g_decision_tel.decision_ts         = TimeCurrent();

   g_decision_tel.has_ict_score       = true;
   g_decision_tel.ict_score           = pick.ss.score;

   g_decision_tel.has_classical_score = true;
   g_decision_tel.classical_score     = pick.bd.score_base;

   g_decision_tel.has_armed_name      = (StringLen(armed_name) > 0);
   g_decision_tel.armed_name          = armed_name;

   g_decision_tel.pick_id             = (int)pick.id;
   g_decision_tel.pick_dir            = (int)pick.dir;
   g_decision_tel.pick_score          = pick.ss.score;
}

void DecisionTelemetry_RecordPassFromRouterSnapshot(const string source)
{
   string armed_name = Telemetry::RouterDecisionPickName();

   if(StringLen(armed_name) <= 0 && Telemetry::RouterDecisionPickID() > 0)
      StratReg::GetStrategyNameById((StrategyID)Telemetry::RouterDecisionPickID(), armed_name);

   g_decision_tel.decision_source     = source;
   g_decision_tel.status              = "decision_passed";
   g_decision_tel.last_drop_reason    = "";
   g_decision_tel.has_decision_ts     = Telemetry::RouterDecisionHasSnapshot();
   g_decision_tel.decision_ts         = Telemetry::RouterDecisionTS();

   g_decision_tel.has_ict_score       = Telemetry::RouterDecisionHasSnapshot();
   g_decision_tel.ict_score           = Telemetry::RouterDecisionPickScore();

   g_decision_tel.has_classical_score = false;
   g_decision_tel.classical_score     = 0.0;

   g_decision_tel.has_armed_name      = (StringLen(armed_name) > 0);
   g_decision_tel.armed_name          = armed_name;

   g_decision_tel.pick_id             = Telemetry::RouterDecisionPickID();
   g_decision_tel.pick_dir            = (int)Telemetry::RouterDecisionPickDir();
   g_decision_tel.pick_score          = Telemetry::RouterDecisionPickScore();
}

void WarnRunCachedRouterPassOriginBlockedOnce(const string origin_tag)
{
   static bool warned = false;
   if(warned)
      return;

   warned = true;
   LogX::Warn(StringFormat(
      "[ROUTER-OWNERSHIP] RunCachedRouterPass(%s) blocked: canonical new-order routing ownership is OnTimer() only. Non-timer origins are deprecated and not allowed.",
      origin_tag));
}

bool RunCachedRouterPass(const string router_sym,
                         const datetime now_srv,
                         const string origin_tag)
{
   if(router_sym == "")
   {
      DecisionTelemetry_MarkPassiveSkip("router_sym_empty");
      return false;
   }

   if(StringCompare(origin_tag, "Timer") != 0)
   {
      WarnRunCachedRouterPassOriginBlockedOnce(origin_tag);
      DecisionTelemetry_MarkPassiveSkip("router_origin_not_timer");
      return false;
   }

   // Canonical new-order orchestration must remain timer-owned:
   // OnTimer()
   //    -> scanners / snapshots / confluence refresh
   //    -> canonical institutional state refresh
   //    -> raw bank build
   //    -> category selector + hard gates
   //    -> strategy hypothesis bank build
   //    -> router
   //    -> policies / risk
   //    -> execution
   //
   // Do not duplicate canonical raw-bank or category-selection assembly
   // anywhere else in this EA entry file.
   if(!WarmupGateOK())
   {
      DecisionTelemetry_MarkGateBlocked("router", "warmup");

      TraceNoTrade(router_sym, TS_GATE, GATE_WARMUP,
                   StringFormat("%s blocked: WarmupGateOK=false", origin_tag));
      return false;
   }

   const datetime required_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(router_sym);
   LogCanonicalInstitutionalGateDiag(router_sym, required_bar_time, origin_tag);

   int gate_reason = 0;
   if(!RouterGateOK_Global(router_sym, g_cfg, now_srv, gate_reason))
   {
      DecisionTelemetry_MarkGateBlocked("router", _GateReasonStr(gate_reason));

      if(InpDebug)
      {
         static datetime last_emit = 0;
         datetime now = TimeCurrent();
         if(now != last_emit)
         {
            last_emit = now;
            PrintFormat("[Router][%s] Skipping RouterEvaluateAll; gate_reason=%d(%s)",
                        origin_tag,
                        gate_reason,
                        _GateReasonStr(gate_reason));

            TraceNoTrade(router_sym, TS_GATE, gate_reason,
                         StringFormat("RouterGateOK=false (%s) [%s]",
                                      _GateReasonStr(gate_reason),
                                      origin_tag));
         }
      }
      return false;
   }

   string transport_diag = "";
   if(!BuildCanonicalSignalStackTransport(router_sym, required_bar_time, transport_diag))
   {
      DecisionTelemetry_MarkGateBlocked("router", "canonical_transport_not_ready");

      if(InpDebug && transport_diag != "")
      {
         PrintFormat("[Router][%s] Skipping hypothesis route; detail=%s",
                     origin_tag,
                     transport_diag);
      }

      return false;
   }

   if(g_hyp_bank.count <= 0)
   {
      DecisionTelemetry_MarkNoCandidates("router", "hypothesis_bank_empty");
      MSH_DirtyClear();
      return false;
   }

   const int router_seq_before = Telemetry::RouterDecisionSeq();

   const bool routed =
      RouterEvaluateHypothesisBank(g_exec_router,
                                   g_cfg,
                                   g_state,
                                   g_raw_bank,
                                   g_cat_selected,
                                   g_cat_pass,
                                   g_sig_stack_gate,
                                   g_location_pass,
                                   g_hyp_bank,
                                   g_final_integrated);

   if(routed && Telemetry::RouterDecisionSeq() != router_seq_before)
      DecisionTelemetry_RecordPassFromRouterSnapshot("router");
   else
      DecisionTelemetry_MarkNoCandidates("router", "router_no_hypothesis_pick");

   MSH_DirtyClear();
   return true;
}

//--------------------------------------------------------------------
// PushICTTelemetryToReviewUI()
// Backend-only: keep telemetry/log export, remove chart ReviewUI dependency.
//--------------------------------------------------------------------
void PushICTTelemetryToReviewUI(const ICT_Context &ictCtx)
{
   _UnusedICTContext(ictCtx);

   string status = g_decision_tel.status;
   if(StringLen(status) <= 0)
      status = "decision_skipped";

   string source = g_decision_tel.decision_source;
   if(StringLen(source) <= 0)
      source = (UseLegacyProcessSymbolEngine() ? "legacy_processsymbol" : "router");

   const bool has_drop_reason = (StringLen(g_decision_tel.last_drop_reason) > 0);

   string j = "{";
   j += "\"sym\":\"" + Telemetry::_Esc(_Symbol) + "\",";
   j += "\"tf\":" + IntegerToString(Period()) + ",";
   j += "\"ict_score\":" + Telemetry::JsonNumberOrNull(g_decision_tel.has_ict_score, g_decision_tel.ict_score, 3) + ",";
   j += "\"classical_score\":" + Telemetry::JsonNumberOrNull(g_decision_tel.has_classical_score, g_decision_tel.classical_score, 3) + ",";
   j += "\"armed\":" + Telemetry::JsonStringOrNull(g_decision_tel.has_armed_name, g_decision_tel.armed_name) + ",";
   j += "\"status\":\"" + Telemetry::_Esc(status) + "\",";
   j += "\"decision_source\":\"" + Telemetry::_Esc(source) + "\",";
   j += "\"decision_ts\":" + Telemetry::JsonDateTimeOrNull(g_decision_tel.has_decision_ts, g_decision_tel.decision_ts) + ",";
   j += EA_RuntimeGateJsonFragment(S) + ",";
   j += "\"last_drop_reason\":" + Telemetry::JsonStringOrNull(has_drop_reason, g_decision_tel.last_drop_reason);
   j += "}";

#ifdef TELEMETRY_HAS_KV
   Telemetry::KV("ict.ctx", j);
#endif
}

// ================== Lifecycle ==================
int OnInit()
  {
   g_show_breakdown = true;
   g_calm_mode      = false;
   g_ml_on          = InpML_Enable;
   g_is_tester      = IsTesterRuntime();
   
   gTesterLooseGateMode = false;
   gDisableMicrostructureGatesRuntime = false;
   
   if(InpLooseMode)
      gTesterLooseGateMode = true;
   
   if(g_is_tester)
      gTesterLooseGateMode = true;
   
   if(InpDisableMicrostructureGates)
      gDisableMicrostructureGatesRuntime = true;
   
   if(g_is_tester && gTesterLooseGateMode)
      gDisableMicrostructureGatesRuntime = true;

   Sanity::SetDebug(InpDebug);
   LogX::SetMinLevel(InpDebug ? LogX::LVL_DEBUG : LogX::LVL_INFO);
   LogX::EnablePrint(true);
   LogX::EnableCSV(InpFileLog);
   if(InpFileLog)
      LogX::InitAll();
   FinalizeRuntimeSettings();

   StrategyDirectExec::SetTesterBypass(g_is_tester && InpAllowDirectExec);

   LogX::Info(StringFormat("[OnInit] direct_exec_tester_bypass=%s",
                           ((g_is_tester && InpAllowDirectExec) ? "true" : "false")));

   if(gTesterLooseGateMode)
   {
      LogX::Warn(StringFormat("[OnInit] LooseMode active | tester=%s killzone=%s news=%s cf_corr=%s extra_corr=%s micro_bypass=%s",
                              (g_is_tester ? "true" : "false"),
                              (EA_EffectiveEnforceKillzone() ? "ON" : "OFF"),
                              (EA_EffectiveNewsOn() ? "ON" : "OFF"),
                              (EA_EffectiveCFCorrelation() ? "ON" : "OFF"),
                              (EA_EffectiveExtraCorrelation() ? "ON" : "OFF"),
                              (EA_MicrostructureGateDisabled() ? "ON" : "OFF")));
   }

   TesterSettings::EmitAudit(S);
   Config::LogSettingsWithHash(S, "CFG");

   string news_filter_state = (S.news_on ? "ON" : "OFF");

   #ifdef CFG_HAS_NEWS_FILTER_ENABLED
      news_filter_state = (S.newsFilterEnabled ? "ON" : "OFF");
   #endif

   // Central tester override audit is emitted by TesterSettings::EmitAudit(S)
   // immediately after FinalizeRuntimeSettings(). Keep the effective config
   // log below as a generic resolved-config snapshot, not the source-of-truth
   // tester override summary.

   string cfg_effective_msg = StringFormat(
      "[CFG_EFFECTIVE] cf_correlation=%s extra_correlation=%s corr_softveto_enable=%s news_on=%s cf_news_ok=%s extra_news=%s block_pre_m=%d block_post_m=%d news_impact_mask=%d",
      (S.cf_correlation ? "true" : "false"),
      (S.extra_correlation ? "true" : "false"),
      (S.corr_softveto_enable ? "true" : "false"),
      (S.news_on ? "true" : "false"),
      (S.cf_news_ok ? "true" : "false"),
      (S.extra_news ? "true" : "false"),
      S.block_pre_m,
      S.block_post_m,
      S.news_impact_mask
   );

   #ifdef CFG_HAS_NEWS_FILTER_ENABLED
      cfg_effective_msg += StringFormat(" newsFilterEnabled=%s",
                                        (S.newsFilterEnabled ? "true" : "false"));
   #endif

   LogX::Info(cfg_effective_msg);
   EA_LogRuntimeGateSummary("[OnInit]", S);

   // Backend-only live runtime: legacy ProcessSymbol harness is tester-only and opt-in.
   if(!g_is_tester)
      g_use_registry = false;

   LogX::Info(StringFormat("[Routing] engine=%s tester=%s registry_input=%s legacy_tester_mode=%s direct_registry_compat=%s legacy_compiletime=%s tester_gate_mode=%s",
                           ActiveRoutingEngineName(),
                           (g_is_tester ? "true" : "false"),
                           (InpUseRegistryRouting ? "true" : "false"),
                           (InpLegacyProcessSymbolTester ? "true" : "false"),
                           (g_sr_direct_registry_compat_runtime ? "true" : "false"),
                           (LegacyProcessSymbolCompileTimeEnabled() ? "ON" : "OFF"),
                           TesterRouterGateModeName(ResolveTesterRouterGateMode())));
                        
   #ifdef CA_USE_HANDLE_REGISTRY
      HR::Init();
      LogX::Info("Indicators mode: registry-cached (HandleRegistry active).");
   #else
      LogX::Info("Indicators mode: ephemeral handles (create/copy/release per call).");
   #endif
   News::ConfigureFromEA(S);
   VSA::SetAllowTickVolume(InpVSA_AllowTickVolume);

   // DOM subscription ownership is centralized later in OnInit(),
   // after the watchlist is finalized and MarketScannerHub is initialized.
   
   {
     const StrategyMode sm = Config::CfgStrategyMode(S);
     LogX::Info(StringFormat("StrategyMode = %s (%d)",
                             StrategyModeNameLocal(sm), (int)sm));
   }

   // Router confluence-only pool status (inputs -> Settings mirror)
   LogRouterConfluencePoolStatus(S, "[OnInit]");

   EmitDeterministicStartupStrategyAudit(S);

   // --- Init subsystems ---
   if(!MarketData::Init(S))
   {
      Print("MarketData init failed");
      return INIT_FAILED;
   }
   if(!Exec::Init())
   {
      return INIT_FAILED;
   }
   bool need_news_init = S.news_on;

   #ifdef CFG_HAS_NEWS_BACKEND
   need_news_init = (need_news_init || (S.news_backend_mode != 0)); // 0=DISABLED
   #endif
   
   if(need_news_init)
      News::Init();
   Risk::InitDayCache();
   Policies::Init(S);
   UI_Init(S);

   // ----- Persistent state load (guarded) -----
   #ifdef STATE_HAS_LOAD_SAVE
      if(!State::Load(S))
         LogX::Warn("[STATE] Load failed or empty; starting fresh.");
   #endif
   
   // Trade policy cooldown
   Policies::SetTradeCooldownSeconds(MathMax(0, InpTradeCooldown_Sec));
   ML::Configure(S, InpML_Temperature, InpML_Threshold, InpML_Weight, InpML_Conformal, InpML_Dampen);
   
   // Build lifecycle config (no ZeroMemory here because struct contains strings)
   ML::LifecycleCfg lc;
   
   lc.runtime_on          = g_ml_on;                 // or InpML_Enable (same value)
   lc.model_file          = InpML_ModelFile;
   lc.dataset_file        = InpML_DatasetFile;
   lc.use_common_files    = InpML_UseCommonFiles;
   lc.auto_calibrate      = InpML_AutoCalibrate;
   lc.model_max_age_hours = InpML_ModelMaxAgeHours;
   
   lc.min_train           = InpML_MinSamplesTrain;
   lc.min_test            = InpML_MinSamplesTest;
   lc.min_oos_auc         = InpML_MinOOS_AUC;
   lc.min_oos_acc         = InpML_MinOOS_Acc;
   
   lc.label_horizon_bars  = InpML_LabelHorizonBars;
   lc.atr_period          = S.atr_period;            // ✅ use your global EA ATR period (Config.mqh Settings)
   lc.label_atr_mult      = InpML_LabelATRMult;
   lc.label_min_points    = InpML_LabelMinPoints;     // keep default behavior unless you add an input
   
   lc.external_enable     = (g_ml_on && InpML_ExternalEnable);
   lc.external_mode       = InpML_ExternalMode;
   lc.external_file       = InpML_ExternalFile;
   lc.external_host       = InpML_ExternalSocketHost;
   lc.external_port       = InpML_ExternalSocketPort;
   lc.external_poll_ms    = InpML_ExternalPollMs;
   lc.external_max_age_sec = InpML_ExternalMaxAgeSec; // keep MLBlender default unless you add an input
   
   // ---- ML lifecycle: wire EA inputs (single source of truth) ----
   lc.outcome_capture     = (g_ml_on && InpML_OutcomeCapture);
   lc.outcome_file        = InpML_OutcomeFile;   // empty is OK: MLBlender may derive default
   
   lc.periodic_retrain         = (g_ml_on && InpML_PeriodicRetrain);
   lc.retrain_min_interval_min = MathMax(0, InpML_RetrainMinIntervalMin);
   lc.retrain_min_new_rows     = MathMax(0, InpML_RetrainMinNewRows);
   lc.retrain_only_tester      = InpML_RetrainOnlyTester;
   
   // Optional breadcrumb (does not change logic)
   if(lc.periodic_retrain && lc.retrain_only_tester && !g_is_tester)
      LogX::Warn("[ML] periodic_retrain=ON but retrain_only_tester=true; live retrain will not run.");

   ML::InitModel(lc);
   LogX::Info(StringFormat("[ML] %s", ML::StateString()));

   // Watchlist parse
   ParseAssetList(InpAssetList, g_symbols);
   g_symCount = ArraySize(g_symbols);
   
   if(g_use_registry && g_symCount > 1)
   {
      LogX::Warn("[MultiSymbol] Current strategy stack evaluates on chart symbol only; forcing watchlist to CURRENT.");
      g_symCount = 1;
      ArrayResize(g_symbols, 1);
      g_symbols[0] = _Symbol;
   }
   
   if(g_symCount<=0)
     {
      g_symCount=1;
      ArrayResize(g_symbols,1);
      g_symbols[0]=_Symbol;
     }

   ArrayResize(g_lastBarTime, g_symCount);
   ArrayResize(g_decision_tel_timer_skip_bar, g_symCount);
   ArrayResize(g_decision_tel_timer_skip_tf, g_symCount);
   ArrayResize(g_decision_tel_timer_skip_latch, g_symCount);
   ArrayResize(g_decision_tel_timer_skip_emitted, g_symCount);
   ArrayResize(g_dom_book_owned, g_symCount);
   
   for(int i=0; i<g_symCount; i++)
   {
      g_lastBarTime[i]                     = 0;
      g_decision_tel_timer_skip_bar[i]    = 0;
      g_decision_tel_timer_skip_tf[i]     = 0;
      g_decision_tel_timer_skip_latch[i]  = 0;
      g_decision_tel_timer_skip_emitted[i] = false;
      g_dom_book_owned[i]                 = false;
   }

   // History warm-up for entry + HTFs on all tracked symbols
   const int need = Warmup::NeededBars(S);
   bool warm_ok = true;
   for(int i=0;i<g_symCount; ++i)
     {
      const string sym = g_symbols[i];
      warm_ok &= Warmup::EnsureFor(sym, S, need);
     }
   if(!warm_ok)
      LogX::Warn("[Warmup] Some series are thin. Indicators may be unstable until history fully loads.");

   // ML: tester-only historic backfill (fast dataset generation)
   if(g_ml_on && MQLInfoInteger(MQL_TESTER) && InpML_BackfillBars > 0)
   {
      const Settings ml_cfg = (g_use_registry ? S : g_cfg);
      const ENUM_TIMEFRAMES ml_tf = (ENUM_TIMEFRAMES)ml_cfg.tf_entry;
      for(int i=0;i<g_symCount; ++i)
         ML::BackfillDataset(g_symbols[i], ml_tf, ml_cfg, InpML_BackfillBars, InpML_BackfillStep);
   }
    
   // Autochartist-style engine init (after warmup so rates/ATR are usable)
   // AutoC::Init(S, g_symbols, g_symCount);
   // Timer ownership moved to MarketScannerHub (MSH::InitWithSymbols sets timer cadence)

   // Optional benchmark
   RunIndicatorBenchmarks();

   // --- Telemetry wiring ---
   #ifdef TELEMETRY_HAS_CONFIGURE
      Telemetry::Configure(512*1024, /*to_common*/true, /*gv_breadcrumbs*/true, "CA_TEL", /*weekly*/false);
      // Telemetry::SetHUDBarGuardTF(S.tf_entry);  // backend-only live build: no HUD gating
   #endif

   #ifdef TELEMETRY_HAS_INIT
      Telemetry::Init(S);
   #endif

   DebugChecklist::Init(_Symbol, InpDbgChkMinScore, InpDbgChkZoneProxATR, InpDbgChkOBProxATR);

   // init price gates
   const double _mid0 = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK))*0.5;
   g_last_mid_arm  = _mid0;
   g_last_mid_stop = _mid0;
   g_armed_by_price   = (InpTradeAtPrice<=0.0); // if no arming price, we are armed by default
   g_stopped_by_price = false;

   // Streak state (fresh day)
   g_consec_wins   = 0;
   g_consec_losses = 0;
   
   #ifdef HAS_ICT_WYCKOFF_PLAYBOOK
      // g_playbook.InitDefaults(/*useSummerNY=*/false);
   #endif
   
   LogX::Info(StringFormat("DIR: trade_selector=%d  legacy_dir=%d  bias_mode=%d  require_checklist=%s  require_classical=%s",
                        (int)S.trade_selector,
                        (int)S.trade_direction_selector,
                        (int)S.direction_bias_mode,
                        (InpMain_RequireChecklist ? "true" : "false"),
                        (InpMain_RequireClassicalConfirm ? "true" : "false")));

   LogX::Info(StringFormat("[MainChecklistPolicy] require=%s soft_mode=%d soft_active=%s tester=%d",
                           (InpMain_RequireChecklist ? "true" : "false"),
                           InpMain_ChecklistSoftFallbackMode,
                           (RuntimeMainChecklistSoftFallbackEnabled() ? "true" : "false"),
                           (g_is_tester ? 1 : 0)));
   //g_cfg.tf_entry = S.tf_entry;
   //g_cfg.tf_h1 = S.tf_h1;
   //g_cfg.tf_h4 = S.tf_h4;
   //g_cfg.tf_d1 = S.tf_d1;

   // 2. Initialize State (pair with router config)
   SyncStateInstitutionalBarFreshnessPolicy();
   LogX::Info(StringFormat("[InstState] bar freshness policy strict_open_bar_alignment=%d allowed_lag_bars=%d tester=%d",
                           (UseCanonicalInstitutionalStrictOpenBarAlignment() ? 1 : 0),
                           CanonicalInstitutionalAllowedLagBars(),
                           (g_is_tester ? 1 : 0)));
   StateInit(g_state, g_cfg);
   Inst_ResetTransportStamp();
   Inst_CommitTransportStampToState(g_state);
   ResetCanonicalSignalStackTransport();

   MarketData::EnsureWarmup_ADX(_Symbol, g_cfg.tf_entry, g_cfg.adx_period, 1);
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Policies::CfgCorrTF(S);
   int            lb = Policies::CfgCorrLookback(S);
   MarketData::EnsureWarmup_CorrReturns(_Symbol, tf, lb, 1);

   // 3. Initialize Router strategies registry (ICT-aware)
   RouterInit(g_exec_router, g_cfg);
   RouterSetWatchlist(g_exec_router, g_symbols, g_symCount);

   if(!RunMainOnlyConsistencyAudit(S))
   {
      if(g_main_only_audit_empty_roster)
         return(INIT_PARAMETERS_INCORRECT);
   
      return(INIT_FAILED);
   }

   // Prime MarketData caches once after watchlist is finalized (enables AutoVol warm builds)
   MarketData::OnTimerRefresh();
   
   // Scanner hub init: MarketScannerHub is the active scanner/timer owner.
   // It owns scanner cadence and the AutoC + Scan timer flow.
   // Do not bypass it elsewhere with fragmented direct timer calls.
   MSH::HubOptions hub_opt;
   MSH::OptionsDefault(hub_opt);

   // Live: preserve existing fast cadence from cfg.timer_ms.
   // Tester: use a slower heartbeat to reduce same-bar spam while still guaranteeing evaluation within the bar.
   hub_opt.use_ms_timer = false;
   hub_opt.timer_sec    = EA_ResolveHubTimerSec(S);

   LogX::Info(StringFormat("[Timer] hub_timer_sec=%d entry_tf_sec=%d only_new_bar=%d tester=%d force_timer_every_heartbeat=%d",
                           hub_opt.timer_sec,
                           PeriodSeconds((ENUM_TIMEFRAMES)S.tf_entry),
                           ((InpOnlyNewBar && InpMain_OnlyNewBar) ? 1 : 0),
                           (g_is_tester ? 1 : 0),
                           ((g_is_tester && InpTester_ForceTimerEveryHeartbeat) ? 1 : 0)));

   // Universe cap (Hub has hard cap HUB_MAX_SYMBOLS)
   hub_opt.max_symbols  = MathMin(g_symCount, (int)MSH::HUB_MAX_SYMBOLS);

   // Keep hub logging passive unless debug is enabled
   hub_opt.log_events   = InpDebug;
   hub_opt.log_summary  = InpDebug;

   // Preserve existing OnTimer behavior: MarketData refresh is done on timer
   hub_opt.call_marketdata_refresh = true;

   // Avoid behavior change here; leave AutoVol timer ownership unchanged
   hub_opt.call_autovol_timer = false;
   
   if(!MSH::InitWithSymbols(S, hub_opt, g_symbols, g_symCount))
      return(INIT_FAILED);

   // Centralized DOM ownership starts only after the watchlist and hub are finalized.
   EA_EnsureCentralDOMSubscriptions();

   // 4. One-shot startup pre-seed of the runtime symbol-owned State pool.
   // This reduces first-timer catch-up by creating / hydrating each symbol slot once now.
   PreseedRuntimeSymbolPoolAtStartup(S);

   // 5. Prime cached runtime context for the canonical router symbol AFTER hub init.
   // RefreshRuntimeContextFromHub() already refreshes lightweight State/ICT context,
   // so do not duplicate RefreshICTContext() here.
   {
      const string ms_sym0 = CanonicalRouterSymbol();
      RefreshRuntimeContextFromHub(ms_sym0, true);
      MSH_DirtyClear(); // avoid a redundant immediate first-timer route off init-only warm state
   }

   PushICTTelemetryToReviewUI(StateGetICTContext(g_state));
   DecisionTelemetry_MarkPassiveSkip("init");

   // UX: show server/local times once for sanity
   datetime now_srv = TimeCurrent();
   MqlDateTime srvdt;
   TimeToStruct(now_srv, srvdt);
   datetime now_loc = TimeLocal();
   MqlDateTime locdt;
   TimeToStruct(now_loc, locdt);
   LogX::Info(StringFormat("Server time: %04d-%02d-%02d %02d:%02d  |  Local: %04d-%02d-%02d %02d:%02d",
                           srvdt.year, srvdt.mon, srvdt.day, srvdt.hour, srvdt.min,
                           locdt.year, locdt.mon, locdt.day, locdt.hour, locdt.min));

   if(InpDebug)
      DbgSymbol();

   if(InpDebug)
     {
      StratReg::RoutedPick pick;
      ZeroMemory(pick);
      if(TryMinimalPathIntent(_Symbol, S, pick))
         PrintFormat("[InitSmoke] router dir=%s score=%.3f eligible=%d",
                     (pick.dir==DIR_BUY?"BUY":"SELL"), pick.ss.score, (int)pick.ss.eligible);
     }

   _LogThresholdsOnce(S);

   // RouterInit(g_router, g_cfg) above already initialised the router
   // using the ICT-aware Settings. Keep the legacy Init() disabled to
   // avoid double-initialisation with inconsistent config.
   // g_router.Init(S, g_strategies);

   string win = TimeUtils::WindowSummary(S);
   if(InpDebug)
      PrintFormat("[SessionTap] filter=%d preset=%d summary=%s",
                  (int)CfgSessionFilter(S), (int)CfgSessionPreset(S), win);
   //#ifdef UNIT_TEST_ROUTER_GATE
   //  Router::_SelfTest_Gate(S);
   //#endif
   
   g_inited = true;
   Telemetry_LogInit("CA_Trading_System_EA initialized.");

   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_inited)
      return;
      
    ML::SetRuntimeOn(g_ml_on);
    if(g_ml_on)
    {
       const Settings ml_cfg = (g_use_registry ? S : g_cfg);
       const ENUM_TIMEFRAMES ml_tf = (ENUM_TIMEFRAMES)ml_cfg.tf_entry;
       for(int i=0;i<g_symCount; ++i)
          ML::Maintain(g_symbols[i], ml_tf);
    }
    
   // Unified warmup gate (tester-safe; avoids permanent stall)
   if(!WarmupGateOK())
   {
      TraceNoTrade(_Symbol, TS_GATE, GATE_WARMUP, "OnTick blocked: WarmupGateOK=false");
      UI_Render(S);
      return;
   }

   // Hard guarantee: STRAT_MAIN_ONLY always routes via RouterEvaluateAll()
   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
       g_use_registry = false;
       
   // Canonical ownership rule:
   // OnTimer() is the only owner of:
   // - scanner cadence
   // - canonical raw-bank/category pipeline
   // - strategy hypothesis building
   // - router dispatch
   // - new-order execution
   //
   // OnTick() is consumer-only:
   // lightweight runtime refresh, open-position management, telemetry/UI, diagnostics.
   // OnTick() must never build the canonical signal stack and must never become an alternate routing owner.
   const string runtime_sym = (UseLegacyProcessSymbolEngine() ? _Symbol : CanonicalRouterSymbol());
   RefreshRuntimeContextLight(runtime_sym);

   // Tick-side bar observer uses its own latch only for diagnostics/telemetry.
   // It must never control router dispatch.
   {
      const bool tick_use_reg = (g_use_registry && g_cfg.strat_mode != STRAT_MAIN_ONLY);
      const Settings tick_gate_cfg = (tick_use_reg ? S : g_cfg);
      const ENUM_TIMEFRAMES tick_tf = Warmup::TF_Entry(tick_gate_cfg);
      const string tick_sym = (tick_use_reg ? _Symbol : (g_symCount > 0 ? g_symbols[0] : _Symbol));

      const datetime tick_prev_latch = g_router_lastBar_tick;
      const bool tick_new_bar = IsNewBarRouterTick(tick_sym, tick_tf);

      if(tick_new_bar)
         _DebugRouterNewBar("Tick", tick_sym, tick_tf, iTime(tick_sym, tick_tf, 0), tick_prev_latch);
   }

   // Autochartist + scanner cadence remain timer-driven.
   ICT_Context ictCtx = StateGetICTContext(g_state);
   
   // New-order routing is timer-owned only.
   // Tester no longer routes through ProcessSymbol() on OnTick().
   // Canonical cached routing is consumed on OnTimer() to avoid split-brain execution.
   
   // Router mode still needs position management every tick (safer than relying on timer only)
   PM::ManageAll(S);

   // 1. Refresh low-level market data into State.
   //    This should update things like:
   //    - g_state.bid / g_state.ask
   //    - volume/Delta (DeltaProxy)
   //    - pivots / ADR / VWAP / spreads
   //    - absorption flags (absorptionBull/absorptionBear)
   //    - emaFastHTF / emaSlowHTF

   PushICTTelemetryToReviewUI(ictCtx);

   if(!g_use_registry)
   {
      // LIVE router flow is timer-owned only.
      // OnTick may refresh lightweight runtime state for UI / open-position management,
      // but it must NOT call RouterEvaluateAll() and must NOT trigger scanner cadence.
      //
      // Canonical live chain remains timer-owned:
      // scanners / signals
      // -> canonical institutional state
      // -> raw bank
      // -> category selector
      // -> strategy hypothesis bank
      // -> router
      // -> policies / risk
      // -> execution
      // -> trade fill
   }

   // DebugChecklist tracer on entry TF once per new bar (no early return so telemetry still runs)
   if(InpDebugChecklistOn)
     {
      const bool dbgNewBar = IsNewBar(_Symbol, S.tf_entry);
      DebugChecklist::Run(_Symbol, S.tf_entry,
                          dbgNewBar,
                          InpDebugChecklistOverlay,
                          InpDebugChecklistCSV,
                          InpDebugChecklistDryRun);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
{
   if(!g_inited)
      return;

   if(!(g_cfg.extra_dom_imbalance || InpExtra_DOMImbalance))
      return;

   if(symbol == "")
      return;

   if(!EA_IsTrackedWatchlistSymbol(symbol))
      return;

   if(!RefreshMicrostructureSnapshot(symbol, true))
      return;

   PublishMicrostructureSnapshot(symbol);

   const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(g_cfg);
   MSH_DirtyTouch(symbol, (int)tf, TimeCurrent());
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_inited = false;
   MSH::Deinit();
   EA_ReleaseCentralDOMSubscriptions();
   MSH_DirtyClear();
   ResetCanonicalSignalStackTransport();
   Exec::Deinit();
   MarketData::Deinit();
   UI_Deinit();
   Telemetry_LogDeinit("CA_Trading_System_EA deinitialized.");
   // Telemetry_Flush();

   #ifdef CA_USE_HANDLE_REGISTRY
      HR::Deinit();
   #endif
   
   // Persist state (guarded)
   #ifdef STATE_HAS_LOAD_SAVE
      if(!State::Save(S))
         LogX::Warn("[STATE] Save failed.");
   #endif
   
   // Telemetry flush (guarded)
   #ifdef TELEMETRY_HAS_FLUSH
      Telemetry::Flush();
   #endif
   
   // === Per-run param snapshot ===
   TesterX::SnapshotParams(S, "on_deinit");

   // Optional: summary log in tester contexts
   if(IsTesterRuntime())
      TesterX::PrintSummary();
      
   return;
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_inited)
      return;

   datetime now_srv = TimeUtils::NowServer();
   const string router_sym = CanonicalRouterSymbol();
   const bool timer_require_new_bar = (InpOnlyNewBar && InpMain_OnlyNewBar && !(g_is_tester && InpTester_ForceTimerEveryHeartbeat));
   const bool legacy_runtime_requested = LegacyProcessSymbolRuntimeRequested();

   // Canonical timer-owned routing policy:
   // 1) MSH::HubTimerTick(S)
   // 2) RefreshRuntimeContextFromHub(router_sym, true)
   //    - refresh microstructure snapshot
   //    - refresh light runtime state
   //    - confirm canonical institutional freshness / degrade state
   // 3) RunCachedRouterPass(router_sym, now_srv, "Timer")
   //    - build RawSignalBank_t
   //    - run CategorySelector
   //    - build StrategyHypothesisBank_t
   //    - router consumes hypotheses
   //    - policies / risk veto
   //    - execution sends
   //
   // Non-canonical routes remain diagnostics-only and must not dispatch trades.
   MSH::HubTimerTick(S);
   // Always refresh the microstructure snapshot.  Without this, the canonical
   // institutional state never becomes "fresh" in the tester, causing the
   // microstructure gate to veto all trades.
   RefreshRuntimeContextFromHub(router_sym, true);

   if(g_msh_dirty_n > 0)
      g_msh_idle_heartbeat_streak = 0;

   // Direct timer calls stay disabled here:
   // MarketScannerHub owns MarketData refresh + AutoC/Scan timer cadence.
   ML::SetRuntimeOn(g_ml_on);
   const Settings ml_cfg = (g_use_registry ? S : g_cfg);
   const ENUM_TIMEFRAMES ml_tf = (ENUM_TIMEFRAMES)ml_cfg.tf_entry;
   
   if(g_ml_on)
    {
       for(int i=0;i<g_symCount; ++i)
          ML::Maintain(g_symbols[i], ml_tf);
    }
   Risk::Heartbeat(now_srv);
   PM::ManageAll(S);
   UI_Render(S);
   MaybeResetStreaksDaily(now_srv);

   DriftAlarm_Check("OnTimer");
   if(timer_require_new_bar)
   {
      // Allow timer-driven routing ONCE per bar (fixes sparse-tick stalls).
      const bool use_reg = (g_use_registry && g_cfg.strat_mode != STRAT_MAIN_ONLY);
      const Settings gate_cfg = (use_reg ? S : g_cfg);
      const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(gate_cfg);

      // Router mode should use a stable watchlist reference; registry mode uses chart symbol.
      const string gate_sym = (use_reg ? _Symbol : (g_symCount > 0 ? g_symbols[0] : _Symbol));

      const datetime timer_prev_latch = g_router_lastBar_timer;
      const datetime timer_bar_time   = iTime(gate_sym, tf, 0);
      const bool timer_new_bar        = IsNewBarRouterTimer(gate_sym, tf);
      const datetime timer_latch_time = g_router_lastBar_timer;

      if(timer_new_bar)
      {
         _DebugRouterNewBar("Timer", gate_sym, tf, timer_bar_time, timer_prev_latch);

         DecisionTelemetry_ResetTimerNotNewBarThrottle(gate_sym,
                                                       tf,
                                                       timer_bar_time,
                                                       timer_latch_time);
      }

      if(!timer_new_bar)
      {
         if(DecisionTelemetry_ShouldEmitTimerNotNewBar(gate_sym,
                                                       tf,
                                                       timer_bar_time,
                                                       timer_latch_time))
         {
            _DebugRouterSkipNotNewBar("Timer",
                                      gate_sym,
                                      tf,
                                      timer_bar_time,
                                      timer_latch_time);

            DecisionTelemetry_MarkPassiveSkip("timer_not_new_bar");
            PushICTTelemetryToReviewUI(StateGetICTContext(g_state));
         }

         return;
      }
   }

   // Timer breadcrumb (once per entry bar): helps diagnose pool on sparse-tick symbols
   {
     const Settings pcfg = (g_use_registry ? S : g_cfg);
     MaybeLogRouterConfluencePoolStatusOncePerBar(pcfg, "[Timer]");
   }
    
   // Hard guarantee: STRAT_MAIN_ONLY always routes via RouterEvaluateAll()
   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
      g_use_registry = false;

#ifdef CA_ENABLE_LEGACY_TESTER_PROCESSSYMBOL
   if(legacy_runtime_requested || UseLegacyProcessSymbolEngine())
      WarnNonCanonicalTradeExecutionDisabledOnce("OnTimer.LegacyProcessSymbol");
#else
   if(legacy_runtime_requested)
      WarnLegacyProcessSymbolCompileTimeBlocked("OnTimer");
#endif

   // Legacy centralized router eval on timer – disabled.
   // if(!g_use_registry)
   //    MaybeEvaluate();
   
   // Canonical router pass (timer-only, cached-context only).
   // Do not call RunCachedRouterPass() from OnTick() or any alternate helper path.
   const bool dirty_triggered = (g_msh_dirty_n > 0);
   const int min_forced_eval_sec = EA_ResolveMinForcedRouterEvalSec(g_cfg);

   if(!dirty_triggered)
   {
      g_msh_idle_heartbeat_streak++;

      const bool cadence_triggered =
         (g_msh_last_forced_router_eval_ts <= 0 ||
          (now_srv - g_msh_last_forced_router_eval_ts) >= min_forced_eval_sec);

      if(!cadence_triggered)
      {
         DecisionTelemetry_MarkPassiveSkip("timer_no_dirty_symbols");
         PushICTTelemetryToReviewUI(StateGetICTContext(g_state));
         return;
      }

      g_msh_eval_cadence_trigger_n++;

      LogX::Info(StringFormat(
         "[ROUTER-CADENCE] trigger=cadence sym=%s dirty_n=%d dirty_runs=%d cadence_runs=%d min_eval_sec=%d idle_heartbeats=%d",
         router_sym,
         g_msh_dirty_n,
         g_msh_eval_dirty_trigger_n,
         g_msh_eval_cadence_trigger_n,
         min_forced_eval_sec,
         g_msh_idle_heartbeat_streak));

      g_msh_idle_heartbeat_streak = 0;
   }
   else
   {
      g_msh_idle_heartbeat_streak = 0;
      g_msh_eval_dirty_trigger_n++;

      LogX::Info(StringFormat(
         "[ROUTER-CADENCE] trigger=dirty sym=%s dirty_n=%d dirty_runs=%d cadence_runs=%d min_eval_sec=%d idle_heartbeats=%d",
         router_sym,
         g_msh_dirty_n,
         g_msh_eval_dirty_trigger_n,
         g_msh_eval_cadence_trigger_n,
         min_forced_eval_sec,
         g_msh_idle_heartbeat_streak));
   }

   g_msh_last_forced_router_eval_ts = now_srv;

   RunCachedRouterPass(router_sym, now_srv, "Timer");
   PushICTTelemetryToReviewUI(StateGetICTContext(g_state));
  }

   bool   RouteMainOnlyPick(const Settings &cfg,
                         StratReg::RoutedPick &pick_out);

   void   ApplyPickOverrides(const StratReg::RoutedPick &pick,
                             Settings &cfg_io,
                             StratScore &ss_io);
                          
   bool RouteMainOnlyPick(const Settings &cfg,
                       StratReg::RoutedPick &pick_out)
   {
      ZeroMemory(pick_out);
   
      // Force a MAIN_ONLY view for diagnostics-only registry inspection.
      // This route is non-canonical and disabled for trade execution.
      Settings cfg_core = cfg;
      Config::ApplyStrategyMode(cfg_core, STRAT_MAIN_ONLY);
      Config::Normalize(cfg_core);
   
      if(!StratReg::SR_AllowDirectRegistrySelection(cfg_core))
      {
         WarnDirectRegistryCompatBlockedOnce("RouteMainOnlyPick", cfg_core);
         return false;
      }
      
      if(!StratReg::Route(cfg_core, pick_out))
         return false;
   
      if(!pick_out.ok)
         return false;
   
      // Make sure score object carries the same ID as the pick (stability for logs/overrides)
      if((int)pick_out.ss.id != (int)pick_out.id)
         pick_out.ss.id = pick_out.id;
   
      LogX::Decision(_Symbol, pick_out.id, pick_out.dir, pick_out.ss, pick_out.bd, 0, "router=core");
      return true;
   }

   // --- Minimal intent path retained for diagnostics-only inspection ---
   // Non-canonical route disabled for trade execution.
   bool TryMinimalPathIntent(const string sym,
                             const Settings &cfg,
                             StratReg::RoutedPick &pick_out)
     {
   
   ZeroMemory(pick_out);

   const double min_sc = EA_RouterResolvedMinScore();   
   const StrategyMode sm = Config::CfgStrategyMode(cfg);
   bool okRoute = false;

   if(!DirectRegistryCompatRuntimeRequested(cfg))
   {
      WarnDirectRegistryCompatBlockedOnce("TryMinimalPathIntent", cfg);
      return false;
   }

   // MAIN_ONLY: route via registry with core-only gating
   if(sm == STRAT_MAIN_ONLY)
   {
      okRoute = RouteMainOnlyPick(cfg, pick_out);
   }
   else
   {
      // COMBINED: main-first, pack-fallback
      if(sm != STRAT_PACK_ONLY)
      {
         StratReg::RoutedPick main_pick;
         ZeroMemory(main_pick);
   
         if(RouteMainOnlyPick(cfg, main_pick))
         {
            string main_drop_why = "";
            string main_drop_detail = "";

            if(PickPassesIntentGate(sym, main_pick, min_sc, main_drop_why, main_drop_detail, false))
            {
               pick_out = main_pick;
               okRoute = true;
            }
         }
      }
   
      // PACK routing only if needed
      if(!okRoute)
      {
      Settings cfg_pack = cfg;
      
      // If we are in COMBINED, force fallback to PACK_ONLY so core does not compete twice
      if(sm != STRAT_PACK_ONLY)
         Config::ApplyStrategyMode(cfg_pack, STRAT_PACK_ONLY);
         
      Config::Normalize(cfg_pack);
         
   #ifdef STRATREG_HAS_ROUTE
      if(!StratReg::SR_AllowDirectRegistrySelection(cfg_pack))
      {
         WarnDirectRegistryCompatBlockedOnce("TryMinimalPathIntent.pack", cfg_pack);
         okRoute = false;
      }
      else
      {
         okRoute = (StratReg::Route(cfg_pack, pick_out) && pick_out.ok);
      }
   #else
      if(g_use_registry)
      {
         string top;
         okRoute = RouteRegistryAll(cfg_pack, pick_out, top);
         if(okRoute) LogX::Info(StringFormat("Router.Top: %s", top));
         if(!okRoute) okRoute = RouteRegistryPick(cfg_pack, pick_out);
      }
      else
      {
         okRoute = RouteManualRegimePick(cfg_pack, pick_out);
      }
   #endif
    }
   }
   
   // Allowlist containment must happen here first.
   // Downstream Execution mode enforcement remains as defense-in-depth only.
   if(okRoute)
   {
      const StrategyID sid = (StrategyID)pick_out.id;
      if(((int)sid) <= 0 || !Config::IsStrategyAllowedInMode(cfg, sid))
      {
         _LogCandidateDrop("allowlist_leak", pick_out.id, pick_out.dir, pick_out.ss, pick_out.bd, min_sc);
         if(InpDebug)
            LogX::Warn(StringFormat("[ALLOWLIST_LEAK] mode=%s sid=%d pick_id=%d (should be filtered upstream; Execution will hard-reject)",
                                    StrategyModeNameLocal(cfg.strat_mode), (int)sid, (int)pick_out.id));
         return false;
      }
   }

   if(!okRoute)
      return false;

   string pick_drop_why = "";
   string pick_drop_detail = "";

   if(!PickPassesIntentGate(sym, pick_out, min_sc, pick_drop_why, pick_drop_detail, true))
   {
      if(pick_drop_why != "no_pick")
         _LogCandidateDrop("intent_drop", pick_out.id, pick_out.dir, pick_out.ss, pick_out.bd, min_sc);

      return false;
   }
   
   // Normal UI hooks
   UI_PublishDecision(pick_out.bd, pick_out.ss);
   
   #ifdef TELEMETRY_HAS_EVENT
   string j_intent = "{";
   j_intent += "\"dir\":\""   + (pick_out.dir==DIR_BUY ? "BUY" : "SELL") + "\",";
   j_intent += "\"score\":"   + DoubleToString(pick_out.ss.score,3);
   j_intent += "}";
   Telemetry::KV("intent_ok", j_intent);
   #endif
   
   return true;
}

// -------- NEW: time & price gates -----------
bool TimeGateOK(const datetime now_srv)
  {
   if(InpStartTime>0 && now_srv < InpStartTime)
      return false;
   if(InpExpirationTime>0 && now_srv >= InpExpirationTime)
      return false;
   return true;
  }

bool PriceArmOK()
  {
   if(g_stopped_by_price)
      return false;
   if(g_armed_by_price)
      return true;

   if(InpTradeAtPrice<=0.0)
     {
      g_armed_by_price=true;
      return true;
     }

   const double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK))*0.5;
   bool crossed = ((g_last_mid_arm < InpTradeAtPrice && mid >= InpTradeAtPrice) ||
                (g_last_mid_arm > InpTradeAtPrice && mid <= InpTradeAtPrice));
   g_last_mid_arm = mid;
   if(crossed)
      g_armed_by_price = true;
   return g_armed_by_price;
  }

void CheckStopTradeAtPrice()
  {
   if(g_stopped_by_price)
      return;
   if(InpStopTradeAtPrice<=0.0)
      return;

   const double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK))*0.5;
   bool crossed = ((g_last_mid_stop < InpStopTradeAtPrice && mid >= InpStopTradeAtPrice) ||
                (g_last_mid_stop > InpStopTradeAtPrice && mid <= InpStopTradeAtPrice));
   g_last_mid_stop = mid;
   if(crossed)
     {
      g_stopped_by_price = true;
      LogX::Warn(StringFormat("[GATE] Stop-Trade price %.5f reached; new entries disabled.", InpStopTradeAtPrice));
     }
  }

// -------- Reset streaks once per server day (live-safe, tester-safe) ------
static int g_streak_day_key = -1;

void ResetStreakCounters()
{
   g_consec_wins   = 0;
   g_consec_losses = 0;
}

void MaybeResetStreaksDaily(const datetime now_srv)
{
   MqlDateTime dt;
   TimeToStruct(now_srv, dt);
   const int key = dt.year*10000 + dt.mon*100 + dt.day;
   if(g_streak_day_key != key)
   {
      ResetStreakCounters();
      g_streak_day_key = key;
   }
}

// -------- Streak lot multiplier (applied to risk_mult safely) ------
bool AllowStreakScalingNow(const double news_risk_mult, const bool news_skip)
{
   // Optional: big-loss latch from Policies (requires implementation in Policies.mqh)
   #ifdef POLICIES_HAS_SIZING_RESET_ACTIVE
     {
       static bool s_was_active = false;
       const bool active = Policies::SizingResetActive();

       if(active)
       {
         if(!s_was_active)
            ResetStreakCounters();   // true reset once per latch activation
         s_was_active = true;
         return false;
       }
       s_was_active = false;
     }
   #endif

   if(!InpResetStreakOnNewsDerisk)
      return true;

   if(news_skip)
      return false;

   if(news_risk_mult < 1.0)
      return false;

   return true;
}

double _RiskMultMaxCapFromInputs()
{
  // User cap: 1.0 disables boosts entirely.
  double cap = MathMax(1.0, InpRiskMultMax);
  if(cap <= 1.0)
    return 1.0;

  // Required minimum so configured multipliers don’t get silently clamped by RiskEngine.
  double req = 1.0;
  req = MathMax(req, MathMax(1.0, InpStreakMaxBoost));
  req = MathMax(req, InpRiskMult_Main);
  req = MathMax(req, InpRiskMult_SilverBullet);
  req = MathMax(req, InpRiskMult_PO3);
  req = MathMax(req, InpRiskMult_Continuation);
  req = MathMax(req, InpRiskMult_WyckoffTurn);

  if(cap < req)
    cap = req;

  // Keep in sync with Config::Normalize defensive clamp
  cap = MathMax(1.0, MathMin(5.0, cap));
  return cap;
}

double StreakRiskScale()
  {
   double mult = 1.0;

   const double max_boost = MathMax(1.0, InpStreakMaxBoost);
   const double min_scale = MathMin(1.0, MathMax(0.01, InpStreakMinScale));

   if(InpStreakWinsToDouble>0 && g_consec_wins >= InpStreakWinsToDouble)
      mult = MathMin(max_boost, 2.0);

   if(InpStreakLossesToHalve>0 && g_consec_losses >= InpStreakLossesToHalve)
      mult = MathMax(min_scale, mult*0.5);

   return mult;
  }

void ApplyPickOverrides(const StratReg::RoutedPick &pick,
                        Settings &cfg_io,
                        StratScore &ss_io)
{
   // Per-strategy overrides (risk + magic)
   switch(pick.id)
   {
      case STRAT_MAIN_ID: // STRAT_MAIN_LOGIC aliases to STRAT_MAIN_ID
         if(cfg_io.risk_mult_main > 0.0)
            ss_io.risk_mult *= cfg_io.risk_mult_main;
   
         if(cfg_io.magic_main_base > 0)
            cfg_io.magic_base = cfg_io.magic_main_base;
         break;
   
      case STRAT_ICT_SILVER_BULLET_ID:
         if(cfg_io.risk_mult_sb > 0.0)
            ss_io.risk_mult *= cfg_io.risk_mult_sb;
   
         if(cfg_io.magic_sb_base > 0)
            cfg_io.magic_base = cfg_io.magic_sb_base;
         break;
   
      case STRAT_ICT_PO3_ID:
         if(cfg_io.risk_mult_po3 > 0.0)
            ss_io.risk_mult *= cfg_io.risk_mult_po3;
   
         if(cfg_io.magic_po3_base > 0)
            cfg_io.magic_base = cfg_io.magic_po3_base;
         break;
   
      case STRAT_ICT_OBFVG_OTE_ID:
         if(cfg_io.risk_mult_cont > 0.0)
            ss_io.risk_mult *= cfg_io.risk_mult_cont;
   
         if(cfg_io.magic_cont_base > 0)
            cfg_io.magic_base = cfg_io.magic_cont_base;
         break;
   
      case STRAT_ICT_WYCKOFF_SPRING_UTAD_ID:
         if(cfg_io.risk_mult_wyck > 0.0)
            ss_io.risk_mult *= cfg_io.risk_mult_wyck;
   
         if(cfg_io.magic_wyck_base > 0)
            cfg_io.magic_base = cfg_io.magic_wyck_base;
         break;
   }
   
   #ifdef CFG_HAS_MAGIC_NUMBER
      cfg_io.magic_number = cfg_io.magic_base;
   #endif

   // Pack strategies: usually already consistent through StratReg weights/throttles.
   // If later you add more per-pick overrides, extend here.
}

void SyncRuntimeCfgFlags(Settings &cfg)
{
   cfg.mode_use_silverbullet = (InpEnable_SilverBulletMode && cfg.enable_strat_ict_silverbullet);
   cfg.mode_use_po3          = (InpEnable_PO3Mode && cfg.enable_strat_ict_po3);
   cfg.mode_enforce_killzone = EA_EffectiveEnforceKillzone();
   cfg.mode_use_ICT_bias     = InpUseICTBias;

   #ifdef CFG_HAS_DIRECTION_BIAS_MODE
   if(!InpUseICTBias)
      cfg.direction_bias_mode = Config::DIRM_MANUAL_SELECTOR;
   else
      cfg.direction_bias_mode = InpDirectionBiasMode;
   #endif
}

// Policies-only gate used by legacy/registry path warm dispatchers.
// Keeps the name intent ("Policies") and avoids duplicating full RouterGateOK().
bool GateViaPolicies(const Settings &cfg, const string sym)
{
   if(g_inhibit_trading)
   {
      UI_SetGate(GATE_INHIBIT);
      _LogGateBlocked("policies_gate", sym, GATE_INHIBIT, "Trading inhibited (drift alarm)");
      TraceNoTrade(sym, TS_GATE, GATE_INHIBIT, "Trading inhibited (drift alarm)");
      return false;
   }

   Policies::PolicyResult pol_eval;
   if(!Policies::EvaluateFull(cfg, sym, pol_eval))
   {
      const int pol_reason = pol_eval.primary_reason;
      const string pol_detail = Policies::FormatPrimaryVetoDetail(pol_eval);

      Policies::PolicyVetoLog(pol_eval);

      UI_SetGate(GATE_POLICIES);

      _LogGateBlockedEx("policies_gate",
                        sym,
                        GATE_POLICIES,
                        "Policies::EvaluateFull failed",
                        "",
                        pol_reason,
                        pol_detail,
                        "");

      TraceNoTrade(sym,
                   TS_GATE,
                   GATE_POLICIES,
                   _MergeGateBlockedDetail("Policies::EvaluateFull failed",
                                           pol_reason,
                                           pol_detail,
                                           ""));

      return false;
   }
   return true;
}

// -------- Trade environment gate (prevents pointless routing when trading is disabled) --------
bool TradeEnvGateOK(const string sym, int &gate_reason_out)
{
   gate_reason_out = 0;

   const bool in_tester = IsTesterRuntime();

   const bool acc_ok  = (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0);
   const bool mql_ok  = (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   const bool term_ok = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0);

   // In tester/optimization, ignore terminal "Algo Trading" toggles; in live, require them.
   if(!acc_ok || (!in_tester && (!mql_ok || !term_ok)))
   {
      gate_reason_out = GATE_TRADE_DISABLED;
      UI_SetGate(gate_reason_out);

      const string detail = StringFormat("Trade disabled: ACCOUNT=%d MQL=%d TERM=%d",
                                         (int)acc_ok, (int)mql_ok, (int)term_ok);

      _LogGateBlocked("trade_env_gate", sym, gate_reason_out, detail);
      TraceNoTrade(sym, TS_GATE, gate_reason_out, detail);

      return false;
   }
   return true;
}

// -------- Router GLOBAL gate (watchlist-safe): no session/news/exec-lock --------
bool RouterGateOK_Global(const string log_sym,
                         const Settings &cfg,
                         const datetime now_srv,
                         int &gate_reason_out)
{
   gate_reason_out = 0;

   // Tripwire: MAIN_ONLY must never use registry/candidate routing path.
   if(cfg.strat_mode == STRAT_MAIN_ONLY && g_use_registry)
   {
      gate_reason_out = GATE_STRATMODE_PATH_BUG;
      UI_SetGate(gate_reason_out);
   
      // Throttle the warning to max 1 per second to avoid log spam.
      static datetime last_emit = 0;
      const datetime now = TimeCurrent();
      if(now != last_emit)
      {
         last_emit = now;
         LogX::Warn(StringFormat("[Routing][BUG] MAIN_ONLY attempted registry routing (g_use_registry=true). Blocking. sym=%s", log_sym));
      }
   
      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out,
                      "BUG: STRAT_MAIN_ONLY cannot use registry/candidate routing path");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out,
                   "BUG: STRAT_MAIN_ONLY attempted registry/candidate routing path");
      return false;
   }

   if(g_inhibit_trading)
   {
      gate_reason_out = GATE_INHIBIT;
      UI_SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "Trading inhibited (drift alarm)");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "Trading inhibited (drift alarm)");
      return false;
   }

   if(!TradeEnvGateOK(log_sym, gate_reason_out))
      return false;

   string ms_detail = "";
   const int tester_gate_mode = ResolveTesterRouterGateMode();
   const bool tester_policy_bypass =
      (IsTesterRuntime() && tester_gate_mode == TESTER_ROUTER_GATE_MODE_BYPASS);
   const bool tester_soft_micro_freshness =
      (IsTesterRuntime() && tester_gate_mode == TESTER_ROUTER_GATE_MODE_SOFT_MICRO_FRESHNESS);
   const datetime ms_required_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(log_sym);

   if(IsTesterRuntime())
      LogTesterRouterGateModeDiagOncePerBar(log_sym, ms_required_bar_time, "enter");

   if(!tester_policy_bypass)
   {
      const bool ms_ok = MicrostructureGateOK(log_sym, now_srv, ms_required_bar_time, ms_detail);
      if(ms_ok)
      {
         if(StringLen(ms_detail) <= 0)
            ms_detail = "pass";
      }
      else
      {
         if(tester_soft_micro_freshness &&
            TesterSoftMicroFreshnessFailure(ms_detail))
         {
            ms_detail = "[TESTER_SOFT_MICRO_FRESHNESS] " + ms_detail;

            PublishTesterDegradedFallbackRuntimeState(log_sym,
                                                      true,
                                                      "tester_soft_micro_freshness",
                                                      ms_detail);

            LogTesterRouterGateModeDiagOncePerBar(log_sym, ms_required_bar_time, ms_detail);
         }
         else
         {
            gate_reason_out = GATE_POLICIES;
            UI_SetGate(gate_reason_out);

            _LogGateBlockedEx("router_gate_global",
                              log_sym,
                              gate_reason_out,
                              "Microstructure gate blocked",
                              "MICROSTRUCTURE",
                              0,
                              "",
                              ms_detail);

            TraceNoTrade(log_sym,
                         TS_GATE,
                         gate_reason_out,
                         _MergeGateBlockedDetail("Microstructure gate blocked",
                                                 0,
                                                 "",
                                                 ms_detail));
            return false;
         }
      }

      Policies::PolicyResult pol_eval;
      if(!Policies::EvaluateFull(cfg, log_sym, pol_eval))
      {
         const int pol_reason = pol_eval.primary_reason;
         const string pol_detail = Policies::FormatPrimaryVetoDetail(pol_eval);

         Policies::PolicyVetoLog(pol_eval);

         gate_reason_out = GATE_POLICIES;
         UI_SetGate(gate_reason_out);

         _LogGateBlockedEx("router_gate_global",
                           log_sym,
                           gate_reason_out,
                           "Policies::EvaluateFull failed",
                           "",
                           pol_reason,
                           pol_detail,
                           ms_detail);

         TraceNoTrade(log_sym,
                      TS_GATE,
                      gate_reason_out,
                      _MergeGateBlockedDetail("Policies::EvaluateFull failed",
                                              pol_reason,
                                              pol_detail,
                                              ms_detail));
         return false;
      }
   }
   else
   {
      ms_detail = "tester_bypass_policy_gates";
      LogTesterRouterGateModeDiagOncePerBar(log_sym, ms_required_bar_time, ms_detail);
   }

   // 2) Hard time window (start/expiry)
   if(!TimeGateOK(now_srv))
   {
      gate_reason_out = GATE_TIMEWINDOW;
      UI_SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "TimeGateOK blocked");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "TimeGateOK=false (start/expiry window)");
      return false;
   }

   // 3) Price gates (arm + stop) are truly global
   if(!PriceArmOK())
   {
      gate_reason_out = GATE_PRICE_ARM;
      UI_SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "PriceArmOK not armed");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "PriceArmOK=false (InpTradeAtPrice not armed?)");
      return false;
   }

   if(g_stopped_by_price)
   {
      gate_reason_out = GATE_PRICE_STOP;
      UI_SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "Stopped by price stop gate");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "Stopped by price gate (InpStopAtPrice hit)");
      return false;
   }

   // NOTE: No session/news/Exec::IsLocked here.
   // Those MUST be checked per-symbol inside Router.mqh / Execution.mqh.

   return true;
}

// -------- Router-friendly gate wrapper (no duplication of exec logic) --------
bool RouterGateOK(const string sym, const Settings &cfg, const datetime now_srv, int &gate_reason_out)
{
   gate_reason_out = 0;

   if(g_inhibit_trading)
   {
      gate_reason_out = GATE_INHIBIT;
      UI_SetGate(gate_reason_out);
   
      _LogGateBlocked("router_gate", sym, gate_reason_out, "Trading inhibited (drift alarm)");
      TraceNoTrade(sym, TS_GATE, gate_reason_out, "Trading inhibited (drift alarm)");
      return false;
   }

   if(!TradeEnvGateOK(sym, gate_reason_out))
      return false;

   string ms_detail = "";
   const bool tester_policy_bypass = (IsTesterRuntime() && InpTester_BypassPolicyGates);

   if(!tester_policy_bypass)
   {
      const datetime ms_required_bar_time = ResolveCanonicalInstitutionalRequiredBarTime(sym);
      const bool ms_ok = MicrostructureGateOK(sym, now_srv, ms_required_bar_time, ms_detail);
      if(ms_ok)
      {
         if(StringLen(ms_detail) <= 0)
            ms_detail = "pass";
      }
      else
      {
         gate_reason_out = GATE_POLICIES;
         UI_SetGate(gate_reason_out);

         _LogGateBlockedEx("router_gate",
                           sym,
                           gate_reason_out,
                           "Microstructure gate blocked",
                           "MICROSTRUCTURE",
                           0,
                           "",
                           ms_detail);

         TraceNoTrade(sym,
                      TS_GATE,
                      gate_reason_out,
                      _MergeGateBlockedDetail("Microstructure gate blocked",
                                              0,
                                              "",
                                              ms_detail));
         return false;
      }

      Policies::PolicyResult pol_eval;
      if(!Policies::EvaluateFull(cfg, sym, pol_eval))
      {
         const int pol_reason = pol_eval.primary_reason;
         const int mapped = (_IsKnownGateReason(pol_reason) ? pol_reason : GATE_POLICIES);
         const string pol_detail = Policies::FormatPrimaryVetoDetail(pol_eval);

         Policies::PolicyVetoLog(pol_eval);

         gate_reason_out = mapped;
         UI_SetGate(gate_reason_out);

         _LogGateBlockedEx("router_gate",
                           sym,
                           gate_reason_out,
                           "Policies::EvaluateFull failed",
                           "",
                           pol_reason,
                           pol_detail,
                           ms_detail);

         TraceNoTrade(sym,
                      TS_GATE,
                      gate_reason_out,
                      _MergeGateBlockedDetail("Policies::EvaluateFull failed",
                                              pol_reason,
                                              pol_detail,
                                              ms_detail));

         return false;
      }
   }
   else
   {
      ms_detail = "tester_bypass_policy_gates";
   }

   // 2) Session gate (legacy preset + TimeUtils)
   if(CfgSessionFilter(cfg))
   {
      const bool sess_on = Policies::EffSessionFilter(cfg, sym);
      if(sess_on)
      {
         TimeUtils::SessionContext sc;
         TimeUtils::BuildSessionContext(cfg, now_srv, sc);
         const bool allowed =
            (CfgSessionPreset(cfg) != SESS_OFF ? sc.preset_in_window : sc.in_window);

         if(!allowed)
         {
            gate_reason_out = GATE_SESSION;
            UI_SetGate(gate_reason_out);
            _LogGateBlocked("router_gate", sym, gate_reason_out, "Session gate");
            TraceNoTrade(sym, TS_GATE, GATE_SESSION, "Session gate blocked (not in window)");
            return false;
         }
      }
   }

   // 3) Hard time window (start/expiry)
   if(!TimeGateOK(now_srv))
   {
      gate_reason_out = GATE_TIMEWINDOW;
      UI_SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "TimeGateOK blocked");
      TraceNoTrade(sym, TS_GATE, GATE_TIMEWINDOW, "TimeGateOK=false (start/expiry window)");
      return false;
   }

   // 4) Price gates (arm + stop)
   if(!PriceArmOK())
   {
      gate_reason_out = GATE_PRICE_ARM;
      UI_SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "PriceArmOK not armed");
      TraceNoTrade(sym, TS_GATE, GATE_PRICE_ARM, "PriceArmOK=false (InpTradeAtPrice not armed?)");
      return false;
   }

   if(g_stopped_by_price)
   {
      gate_reason_out = GATE_PRICE_STOP;
      UI_SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "Stopped by price stop gate");
      TraceNoTrade(sym, TS_GATE, GATE_PRICE_STOP, "Stopped by price gate (InpStopAtPrice hit)");
      return false;
   }
      
   // 6) Execution lock (async send guard)
   if(Exec::IsLocked(sym))
   {
      gate_reason_out = GATE_EXEC_LOCK;
      UI_SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "Exec lock active");
      TraceNoTrade(sym, TS_GATE, GATE_EXEC_LOCK, "Exec::IsLocked=true (async send guard)");
      return false;
   }

   return true;
}

// DEPRECATED tester-only legacy harness.
// Non-canonical route disabled for trade execution.
// Live and tester both use the same canonical owner: OnTimer() with
// MSH::HubTimerTick(), RefreshRuntimeContextFromHub(), RunCachedRouterPass(Timer),
// and RouterEvaluateAll().
void ProcessSymbol(const string sym, const bool new_bar_for_sym)
  {
#ifndef CA_ENABLE_LEGACY_TESTER_PROCESSSYMBOL
   if(LegacyProcessSymbolRuntimeRequested())
   {
      WarnLegacyProcessSymbolCompileTimeBlocked(StringFormat("ProcessSymbol(%s)", sym));
      DecisionTelemetry_MarkPassiveSkip("legacy_compiletime_off");
   }
   return;
#else

   // Legacy harness is tester-only. Live must never enter ProcessSymbol().
   if(!g_is_tester)
      return;
      
   // 0) Unified warmup gate (single source of truth)
   if(!WarmupGateOK())
   {
      DecisionTelemetry_MarkGateBlocked("legacy_processsymbol", "warmup");

      TraceNoTrade(sym, TS_GATE, GATE_WARMUP, "ProcessSymbol blocked: WarmupGateOK=false");
      PM::ManageAll(S);
      UI_Render(S);
      return;
   }

   // Always keep managing open positions (even if we skip evaluation)
   PM::ManageAll(S);

   if(g_inhibit_trading)
   {
      DecisionTelemetry_MarkGateBlocked("legacy_processsymbol", "inhibit");
   
      UI_SetGate(GATE_INHIBIT);
      TraceNoTrade(sym, TS_GATE, GATE_INHIBIT, "ProcessSymbol blocked: trading inhibited (drift alarm)");
      UI_Render(S);
      return;
   }

   // Safety: ProcessSymbol is an opt-in tester compatibility harness only.
   if(!UseLegacyProcessSymbolEngine())
   {
      DecisionTelemetry_MarkPassiveSkip("legacy_engine_off");

      if(InpDebug)
         LogX::Warn("[LEGACY] ProcessSymbol blocked: non-canonical route disabled for trade execution.");
      return;
   }

   // NOTE: current strategies rely on _Symbol internally; only evaluate on chart symbol.
   if(sym != _Symbol)
   {
      DecisionTelemetry_MarkPassiveSkip("sym_mismatch");

      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_NO_INTENT, "sym != _Symbol; evaluation skipped");
      UI_Render(S);
      return;
   }

   // Keep State / ICT aligned to the exact symbol being evaluated.
   // This is defense-in-depth for all tester registry entry points.
   RefreshRuntimeContextFromHub(sym, false);

   // 1) Unified gate wrapper (Policies/Session/Time/Price/News/ExecLock)
   int gate_reason = 0;
   const datetime now_srv = TimeUtils::NowServer();
   if(!RouterGateOK(sym, S, now_srv, gate_reason))
   {
      DecisionTelemetry_MarkGateBlocked("legacy_processsymbol", _GateReasonStr(gate_reason));

      // RouterGateOK will breadcrumb; this keeps ProcessSymbol consistent too
      TraceNoTrade(sym, TS_GATE, gate_reason,
                   StringFormat("RouterGateOK=false (%s)", _GateReasonStr(gate_reason)));
      UI_Render(S);
      return;
   }

   // Clear the gate indicator when we pass all gates
   UI_SetGate(GATE_NONE);

   // 2) Policies::Evaluate (or router fallback) to intent/pick
   StratReg::RoutedPick pick;
   ZeroMemory(pick);

   const double min_sc = EA_RouterResolvedMinScore();
   if(!TryMinimalPathIntent(sym, S, pick))
     {
      string pick_drop_why = "";
      string pick_drop_detail = "";

      if(StringLen(pick_drop_why) <= 0)
         pick_drop_why = "no_pick";

      DecisionTelemetry_MarkNoCandidates("legacy_processsymbol", pick_drop_why);

      if(!PickPassesIntentGate(sym, pick, min_sc, pick_drop_why, pick_drop_detail, false) &&
         pick_drop_why != "no_pick")
        {
         // TryMinimalPathIntent() already emitted the authoritative intent-drop line.
         UI_Render(S);
         return;
        }

      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_NO_INTENT,
                   "TryMinimalPathIntent=false (no eligible pick/intent)");
      UI_Render(S);
      return;
     }

   // Intent gate already passed inside TryMinimalPathIntent(); do not re-check here.
   DecisionTelemetry_RecordPassFromPick("legacy_processsymbol", pick);

   // ---- Veto instrumentation (lightweight) ----
   static int veto_counts[16];
   static int veto_total = 0;
   if(pick.bd.veto)
      {
         const int mask = (int)(pick.bd.veto_mask & 15);
         veto_counts[mask]++;
         veto_total++;
   #ifdef TELEMETRY_HAS_EVENT
         Telemetry::Event("veto", IntegerToString(mask), pick.ss.score);
   #endif

      if((veto_total % 100) == 0)
         LogX::Warn(StringFormat("[VETO] total=%d last_mask=%d  (STRUCT=%d, LIQ=%d, CORR=%d)",
                                 veto_total, mask,
                                 veto_counts[VETO_STRUCTURE],
                                 veto_counts[VETO_LIQUIDITY],
                                 veto_counts[VETO_CORR]));
     }

   // 3) Meta layers (ML/Calm) + News surprise scaling + Streak scaling
   int mins_left = 0;
   double risk_mult=1.0;
   bool skip=false;
   NewsDefensiveStateAtBarClose(S, sym, 1, risk_mult, skip, mins_left);
   News::SurpriseRiskAdjust(now_srv, sym, S.news_impact_mask, S.cal_lookback_mins,
                            S.cal_hard_skip, S.cal_soft_knee, S.cal_min_scale,
                            risk_mult, skip);
   
   if(skip)
     {
      if(InpResetStreakOnNewsDerisk)
         ResetStreakCounters();
      PM::ManageAll(S);
      UI_Render(S);
      TraceNoTrade(sym, TS_POLICIES, TR_POLICIES_SOFT_SKIP,
                   "News::CompositeRiskAtBarClose / SurpriseRiskAdjust requested skip=true");
      return;
     }

   StratScore SS = pick.ss;
   Settings trade_cfg = S;              // local, per-trade settings (do NOT mutate global S)
   ApplyPickOverrides(pick, trade_cfg, SS);
   SS.risk_mult *= risk_mult;

   // Streak scaling (before ML so downstream can log final)
   if(AllowStreakScalingNow(risk_mult, skip))
      SS.risk_mult *= StreakRiskScale();
   else
      ResetStreakCounters();

   ApplyMetaLayers(pick.dir, SS, pick.bd);
   
   // -------- Carry integration (strict or mild) ----------
   if(trade_cfg.carry_enable && InpCarry_StrictRiskOnly)
      StrategiesCarry::RiskMod01(pick.dir, trade_cfg, SS.risk_mult);

   static bool s_logged_processsymbol_timer_owned = false;
   if(!s_logged_processsymbol_timer_owned)
   {
      s_logged_processsymbol_timer_owned = true;
      LogX::Info("[LEGACY] ProcessSymbol diagnostics complete. Trade-plan and order send are blocked here. Canonical execution is timer-owned via RunCachedRouterPass(Timer) -> RouterEvaluateAll().");
   }

   WarnNonCanonicalTradeExecutionDisabledOnce("ProcessSymbol");
   DecisionTelemetry_MarkPassiveSkip("legacy_processsymbol_execution_timer_owned");
   UI_Render(S);
   return;

   OrderPlan plan;
   const StrategyID sid = (StrategyID)pick.id;
   
   if(!Risk::ComputeOrder(pick.dir, trade_cfg, SS, plan, pick.bd))
   {
      _LogRiskReject("risk_reject", sym, sid, pick.dir, SS);
      UI_Render(S);
      return;
   }
   
   // Enforcement point #2 (Router gate) even for legacy harness
   if(!Router_GateWinnerByMode(S, sid))
   {
      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_MODE_BLOCK,
                   StringFormat("[LEGACY] Router gate blocked sid=%d mode=%s",
                                (int)sid, StrategyModeNameLocal(S.strat_mode)),
                   (int)sid, pick.dir, pick.ss.score);
      UI_Render(S);
      return;
   }
   
   Exec::Outcome ex = Exec::SendAsyncSymEx(sym, plan, trade_cfg, sid, /*skip_gates=*/false);
   HintTradeDisabledOnce(ex);
   LogExecFailThrottled(sym, pick.dir, plan, ex, trade_cfg.slippage_points);
   _LogExecReject("exec_reject", sym, sid, pick.dir, SS, plan, ex);
   if(ex.ok)
   {
    Policies::NotifyTradePlaced();

    // Record executed decisions for ML training (label computed later on new bars)
    if(g_ml_on && ML::IsActive())
      {
       ML::ObserveWinnerSample(sym, trade_cfg.tf_entry, pick.dir, trade_cfg, pick.bd, SS);

       // Outcome-aware snapshot (ticket→position bind occurs in OnTradeTransaction)
       #ifdef ML_HAS_TRADE_OUTCOME_HOOKS
          if(ex.ticket > 0)
             ML::TradeOpenIntent(ex.ticket, sym, trade_cfg.tf_entry, pick.dir, sid, trade_cfg, pick.bd, SS, plan.price, plan.sl, plan.tp);
       #endif
      }
   }
   
   LogX::Exec(sym, pick.dir, plan.lots, plan.price, plan.sl, plan.tp,
              ex.ok, ex.retcode, ex.ticket, trade_cfg.slippage_points,
              ex.last_error, ex.last_error_text);

   #ifdef TELEMETRY_HAS_TRADEPLAN
      string side = (pick.dir==DIR_BUY ? "BUY" : "SELL");
      Telemetry::TradePlan(sym, side, plan.lots, plan.price, plan.sl, plan.tp, SS.score);
   #endif

   UI_Render(S);
#endif
  }

// Helper to detect new bar on entry TF (for DebugChecklist cadence)
datetime g_dbg_lastBar=0;
bool IsNewBar(const string sym, const ENUM_TIMEFRAMES tf)
  {
   datetime t[];
   ArraySetAsSeries(t,true);
   if(CopyTime(sym, tf, 0, 1, t) != 1)
      return false;
   if(g_dbg_lastBar != t[0])
     {
      g_dbg_lastBar=t[0];
      return true;
     }
   return false;
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SmokeTestOne(const Settings &cfg)
{
  Candidate c;
  if(TryEval_TrendVWAP(DIR_BUY, cfg, c))
     PrintFormat("[Smoke] Trend_VWAP BUY eligible score=%.3f", c.blended);
  if(TryEval_TrendVWAP(DIR_SELL, cfg, c))
     PrintFormat("[Smoke] Trend_VWAP SELL eligible score=%.3f", c.blended);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &tx, const MqlTradeRequest &rq, const MqlTradeResult &rs)
{
   if(false)
     {
      Print(rq.symbol);   // silence warning
     }
   Exec::OnTx(tx);
   UI_OnTradeTransaction(tx, rs);
   Risk::OnTx(tx);
   LogX::LedgerOnTx(tx, rs);

   // Streak accounting (simple per-position logic)
   if(tx.type==TRADE_TRANSACTION_DEAL_ADD)
   {
      long entry = 0;
      HistoryDealGetInteger(tx.deal, DEAL_ENTRY, entry);
      double profit    = 0.0;
      HistoryDealGetDouble(tx.deal, DEAL_PROFIT, profit);
      
      double swap = 0.0;
      double comm = 0.0;
      HistoryDealGetDouble(tx.deal, DEAL_SWAP,       swap);
      HistoryDealGetDouble(tx.deal, DEAL_COMMISSION, comm);
      double net_profit = profit + swap + comm;
      
      // Only count exits (and in/out if you want partial close behavior included)
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      {
         if(net_profit > 0.0)
         {
            g_consec_wins++;
            g_consec_losses=0;
         }
         else if(net_profit < 0.0)
         {
            g_consec_losses++;
            g_consec_wins=0;
         }
         
         #ifdef ML_HAS_TRADE_OUTCOME_HOOKS
          if(g_ml_on && ML::IsActive())
          {
             long pos_id2 = 0;
             HistoryDealGetInteger(tx.deal, DEAL_POSITION_ID, pos_id2);

             long t_close_i = 0;
             HistoryDealGetInteger(tx.deal, DEAL_TIME, t_close_i);

             double close_price = 0.0;
             HistoryDealGetDouble(tx.deal, DEAL_PRICE, close_price);

             long reason_i = 0;
             HistoryDealGetInteger(tx.deal, DEAL_REASON, reason_i);

             if(pos_id2 > 0)
                ML::TradeCloseOutcome(pos_id2, tx.symbol, (datetime)t_close_i, close_price, net_profit, (int)reason_i);
          }
         #endif
      }
      
      if(entry == DEAL_ENTRY_IN)
      {
         long order_ticket=0, pos_id=0;
         HistoryDealGetInteger(tx.deal, DEAL_ORDER, order_ticket);
         HistoryDealGetInteger(tx.deal, DEAL_POSITION_ID, pos_id);
         
         #ifdef ML_HAS_TRADE_OUTCOME_HOOKS
            if(order_ticket > 0 && pos_id > 0 && g_ml_on && ML::IsActive())
               ML::TradeBindOrderToPosition(order_ticket, pos_id, tx.symbol, tx.deal);
         #endif
      }
      #ifdef POLICIES_HAS_SIZING_RESET_ACTIVE
         if(Policies::SizingResetActive())
            ResetStreakCounters();
      #endif
   }

   // --- FLOW breadcrumb (#F[..]) ---
   // Case A: successful trade request (server accepted)
   if(ROUTER_TRACE_FLOW &&
      tx.type==TRADE_TRANSACTION_REQUEST &&
      (rs.retcode==TRADE_RETCODE_DONE || rs.retcode==TRADE_RETCODE_DONE_PARTIAL))
     {
      const bool isBuy = (rq.type==ORDER_TYPE_BUY || rq.type==ORDER_TYPE_BUY_LIMIT ||
                          rq.type==ORDER_TYPE_BUY_STOP || rq.type==ORDER_TYPE_BUY_STOP_LIMIT);
      const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)ChartPeriod();
      const int dg = (int)SymbolInfoInteger(tx.symbol, SYMBOL_DIGITS);

      PrintFormat("#F[%s][%s][%d][%I64d] FILL req=OK price=%s lots=%.2f",
                  tx.symbol, (isBuy?"BUY":"SELL"), (int)tf,
                  (long)iTime(tx.symbol, tf, 1),
                  DoubleToString(rs.price, dg), rs.volume);
     }

   // Case B: deal was actually added to history (most reliable fill signal)
   if(ROUTER_TRACE_FLOW && tx.type==TRADE_TRANSACTION_DEAL_ADD)
     {
      long   dType=0;
      HistoryDealGetInteger(tx.deal, DEAL_TYPE, dType);
      double dPrice=0.0;
      HistoryDealGetDouble(tx.deal, DEAL_PRICE,  dPrice);
      double dVol=0.0;
      HistoryDealGetDouble(tx.deal, DEAL_VOLUME, dVol);

      // Only echo entries; closures will appear as OUT (you can extend if you want both)
      const bool isBuy = (dType==DEAL_TYPE_BUY);
      const bool isSell= (dType==DEAL_TYPE_SELL);
      if(isBuy || isSell)
        {
         const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)ChartPeriod();
         const int dg = (int)SymbolInfoInteger(tx.symbol, SYMBOL_DIGITS);

         PrintFormat("#F[%s][%s][%d][%I64d] FILL deal=%I64d price=%s lots=%.2f",
                     tx.symbol, (isBuy?"BUY":"SELL"), (int)tf,
                     (long)iTime(tx.symbol, tf, 1),
                     (long)tx.deal, DoubleToString(dPrice, dg), dVol);
        }
     }

// Telemetry (guarded)
#ifdef TELEMETRY_HAS_TX
   Telemetry::OnTx(tx, rs);
#endif
  }

// Backend-only chart event handler.
// No runtime settings mutation is allowed here.
int KeyCodeFromEvent(const long lparam) { return (int)lparam; }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(false)
   {
      Print(dparam);
      Print(sparam);
   }

   if(id != CHARTEVENT_KEYDOWN)
      return;

   int K = (int)lparam;
   if(K >= 'a' && K <= 'z')
      K = 'A' + (K - 'a');

   // Tester-only emergency resume after drift halt.
   if(K == 'T')
   {
      if(!g_is_tester)
         return;

      if(!g_inhibit_trading)
         return;

      g_inhibit_trading = false;
      UI_SetGate(GATE_NONE);
      DriftAlarm_SetApproved("tester hotkey T: resume");
      return;
   }

   // Optional: keep benchmark hotkey.
   if(K == 'H')
   {
      RunIndicatorBenchmarks();
      return;
   }
}

// ========================== Regression Batch & Golden Runs ==================
namespace Regression
{
struct KPI
  {
   string            batch_tag;
   string            symbol;
   int               tf;
   datetime          t_from;
   datetime          t_to;
   string            settings_hash;
   int               trades;
   double            net;
   double            pf;
   double            winrate;
   double            maxdd;
   double            sh_like;
   double            expectancy;
   double            wf_frac;
   double            wf_pf_med;
   double            wf_trd_med;
   string            note;
  };

inline void FirstLastFromDeals(const TesterX::DealRec &d[], const int n, datetime &tmin, datetime &tmax)
  {
   tmin=0;
   tmax=0;
   if(n<=0)
      return;
   tmin=d[0].ts;
   tmax=d[0].ts;
   for(int i=1;i<n;i++)
     {
      if(d[i].ts<tmin)
         tmin=d[i].ts;
      if(d[i].ts>tmax)
         tmax=d[i].ts;
     }
  }

inline string Stamp() { return TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS); }

inline string KPILine(const KPI &k)
  {
   return StringFormat("%s;%s;%d;%s;%s;%s;%d;%.2f;%.6f;%.2f;%.2f;%.6f;%.6f;%.4f;%.4f;%.2f;%s",
                       k.batch_tag, k.symbol, k.tf,
                       TimeToString(k.t_from, TIME_DATE), TimeToString(k.t_to, TIME_DATE),
                       k.settings_hash,
                       k.trades, k.net, k.pf, k.winrate, k.maxdd, k.sh_like, k.expectancy,
                       k.wf_frac, k.wf_pf_med, k.wf_trd_med, LogX::San(k.note));
  }

inline bool EnsureHeader(const string file)
  {
   uint flags = FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI;
   int h = FileOpen(file, flags);
   if(h==INVALID_HANDLE)
      return false;
   bool need = (FileSize(h)==0);
   if(need)
     {
      FileWriteString(h, "batch;symbol;tf;from;to;hash;trades;net;pf;winrate;maxdd;sh_like;expect;wf_frac;wf_pf_med;wf_trd_med;note\r\n");
      FileFlush(h);
     }
   FileClose(h);
   return true;
  }

inline void AppendKPIs(const string file, const KPI &k)
  {
   if(!EnsureHeader(file))
      return;
   int h = FileOpen(file, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, KPILine(k));
   FileWriteString(h, "\r\n");
   FileFlush(h);
   FileClose(h);
  }

// Return: true if same key (batch/symbol/tf/hash) found and diffs computed
inline bool CompareAgainstGolden(const KPI &cur, const string golden_file, const double tol_pct)
  {
   int h = FileOpen(golden_file, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      LogX::Warn(StringFormat("[REG] Golden file not found: %s", golden_file));
      return false;
     }

   string line;
   bool header=true;
   bool matched=false;
   while(!FileIsEnding(h))
     {
      line = FileReadString(h);
      if(StringLen(line)==0)
         continue;
      if(header)
        {
         header=false;
         continue;
        }
      string parts[];
      const int m = StringSplit(line, ';', parts);
      if(m<17)
         continue;

      const string gbatch = parts[0];
      const string gsym   = parts[1];
      const int    gtf    = (int)StringToInteger(parts[2]);
      const string ghash  = parts[5];

      if(gbatch==cur.batch_tag && gsym==cur.symbol && gtf==cur.tf && ghash==cur.settings_hash)
        {
         matched=true;
         KPI g;
         ZeroMemory(g);
         g.batch_tag = gbatch;
         g.symbol=gsym;
         g.tf=gtf;
         g.settings_hash=ghash;
         g.trades    = (int)StringToInteger(parts[6]);
         g.net       = StringToDouble(parts[7]);
         g.pf        = StringToDouble(parts[8]);
         g.winrate   = StringToDouble(parts[9]);
         g.maxdd     = StringToDouble(parts[10]);
         g.sh_like   = StringToDouble(parts[11]);
         g.expectancy= StringToDouble(parts[12]);
         g.wf_frac   = StringToDouble(parts[13]);
         g.wf_pf_med = StringToDouble(parts[14]);
         g.wf_trd_med= StringToDouble(parts[15]);

         struct KCmp { string name; double a; double b; };
         KCmp rows[9] =
           {
              {"trades", (double)cur.trades, (double)g.trades},
              {"net",    cur.net,    g.net},
              {"pf",     cur.pf,     g.pf},
              {"winrate",cur.winrate,g.winrate},
              {"maxdd",  cur.maxdd,  g.maxdd},
              {"sh_like",cur.sh_like,g.sh_like},
              {"expect", cur.expectancy,g.expectancy},
              {"wf_frac",cur.wf_frac,g.wf_frac},
              {"wf_pf_med",cur.wf_pf_med,g.wf_pf_med}
           };

         for(int i=0;i<9;i++)
           {
            const double base = (MathAbs(rows[i].b)>1e-9 ? rows[i].b : 1.0);
            const double drift = 100.0 * (rows[i].a - rows[i].b) / base;
            const bool bad = (MathAbs(drift) > tol_pct);
            string msg = StringFormat("[REG] %s drift=%.2f%% current=%.6f golden=%.6f (tol=%.2f%%)",
                                      rows[i].name, drift, rows[i].a, rows[i].b, tol_pct);
            if(bad)
               LogX::Warn(msg);
            else
               LogX::Info(msg);
           }
         break;
        }
     }
   FileClose(h);
   if(!matched)
      LogX::Warn(StringFormat("[REG] No golden row match for key batch=%s sym=%s tf=%d hash=%s",
                              cur.batch_tag, cur.symbol, cur.tf, cur.settings_hash));
   return matched;
  }

inline void SaveWFTablesAndEquity(const bool save_wf, const bool save_eq)
  {
   if(save_wf)
      TesterX::SaveWFTableCSV("CAEA_WF.csv", false);
   if(save_eq)
      TesterX::SaveEquityCSV("CAEA_Equity.csv", false, 0.0);
  }

inline void ExportCurrentRun(const string kpi_file, const string batch_tag, const string extra_note, KPI &out_k)
  {
   TesterX::DealRec deals[];
   TesterX::CollectDeals(deals);
   const int n = ArraySize(deals);

   TesterX::Perf p;
   TesterX::ComputePerf(deals, n, p);
   TesterX::WFResult wf;
   ZeroMemory(wf);
   TesterX::WFStats(wf);

   datetime t0=0,t1=0;
   FirstLastFromDeals(deals, n, t0, t1);

   KPI k;
   ZeroMemory(k);
   k.batch_tag     = batch_tag;
   k.symbol        = _Symbol;
   k.tf            = (int)S.tf_entry;
   k.t_from        = t0;
   k.t_to          = t1;
   k.settings_hash = TesterX::SettingsHashHex(S);
   k.trades        = p.trades;
   k.net           = p.net_pnl;
   k.pf            = p.profit_factor;
   k.winrate       = p.winrate;
   k.maxdd         = p.max_dd_abs;
   k.sh_like       = p.sharpe_like;
   k.expectancy    = p.expectancy;
   k.wf_frac       = wf.frac_profitable;
   k.wf_pf_med     = wf.pf_median;
   k.wf_trd_med    = wf.trades_median;
   k.note          = extra_note;

   AppendKPIs(kpi_file, k);
   out_k = k;

   LogX::Info(StringFormat("[REG] KPIs exported — batch=%s sym=%s tf=%d deals=%d net=%.2f PF=%.3f DD=%.2f",
                           batch_tag, _Symbol, (int)S.tf_entry, k.trades, k.net, k.pf, k.maxdd));
  }
} // namespace Regression

void OnTesterInit()
  {
   Risk::InitDayCache();
   // Reset streaks at tester run start for deterministic behavior
   g_consec_wins=0;
   g_consec_losses=0;
   g_streak_day_key = -1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTesterDeinit()
  {
   if(!InpReg_Enable)
      return;

   Regression::SaveWFTablesAndEquity(InpReg_SaveWF, InpReg_SaveEquity);

   Regression::KPI k;
   Regression::ExportCurrentRun(InpReg_KPIsFile, InpReg_BatchTag, InpReg_ExtraNote, k);

   if(InpReg_SaveAsGolden)
     {
      LogX::Warn("[REG] Overwriting GOLDEN file with this run.");
      int h = FileOpen(InpReg_GoldenFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE)
        {
         FileWriteString(h, "batch;symbol;tf;from;to;hash;trades;net;pf;winrate;maxdd;sh_like;expect;wf_frac;wf_pf_med;wf_trd_med;note\r\n");
         FileWriteString(h, Regression::KPILine(k));
         FileWriteString(h, "\r\n");
         FileFlush(h);
         FileClose(h);
        }
      else
        {
         LogX::Error(StringFormat("[REG] Unable to write golden file: %s", InpReg_GoldenFile));
        }
     }

   if(InpReg_Compare)
     {
      Regression::CompareAgainstGolden(k, InpReg_GoldenFile, (InpReg_TolerancePct>0.0?InpReg_TolerancePct:5.0));
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
   double score=0.0;
   if(InpTesterScore==TESTER_SCORE_SHARPE)
      score = TesterX::ScoreSharpe();
   else
      if(InpTesterScore==TESTER_SCORE_EXPECT)
         score = TesterX::ScoreExpectancy();
      else
         score = TesterX::Score();

   if(InpTesterSnapshot)
      TesterX::SnapshotParams(S, InpTesterNote);
   
   // ML: train + validate at end of Strategy Tester run
   if(g_ml_on && InpML_TrainOnTesterEnd)
       ML::CalibrateWalkForward();
   return score;
  }
//+------------------------------------------------------------------+