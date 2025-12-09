#ifndef CA_POLICIES_MQH
#define CA_POLICIES_MQH
#property strict

// Make Execution.mqh compile-safe: it checks this macro for persistence hooks.
#define CA_POLICIES_AVAILABLE 1

//=============================================================================
// Policies.mqh — Core gates, filters & orchestration (Persistent)
//-----------------------------------------------------------------------------
//  • Central policy gates (spread, ADR/ATR, regime, session, news, liquidity).
//  • Daily DD / Day-loss stops (persisted so restarts resume correctly).
//  • Loss-streak cooldown & per-trade cooldown (persisted).
//  • Daily equity start persisted per Account+Magic to keep day limits stable.
//  • Hooks used by Execution.mqh to record attempts/results & start cooldowns.
//  • HUD/telemetry snapshot (seconds left, reasons, PL, ratios, etc.).
//  • All Settings access is compile-safe (CFG_HAS_* guards) with defaults.
//=============================================================================

// ---------- Includes ----------
#include "Config.mqh"
#include "MarketData.mqh"
#include "Indicators.mqh"
#include "TimeUtils.mqh"
#include "RegimeCorr.mqh"
#include "RiskEngine.mqh"
#ifdef NEWSFILTER_AVAILABLE
  #include "NewsFilter.mqh"
#endif
#ifdef CFG_HAS_CONFLUENCE
  #include "Confluence.mqh"
#endif
#include "CAEA_dbg.mqh"
#include "ICTWyckoffPlaybook.mqh"

// ---------------------------------------------
// Local window test in "minutes since midnight"
// Handles normal and wrap-around windows (e.g., 23:00->02:00)
// ---------------------------------------------
inline bool _WithinLocalWindowMins(const int open_min, const int close_min, const datetime now_local)
{
  MqlDateTime lt; 
  TimeToStruct(now_local, lt);
  const int mm = lt.hour * 60 + lt.min;

  if(open_min == close_min)   // degenerate -> treat as always allowed (or return false if you prefer)
    return true;

  if(close_min > open_min)    // normal window: [open, close)
    return (mm >= open_min && mm < close_min);

  // wrap-around window: e.g., 23:00 -> 02:00
  return (mm >= open_min || mm < close_min);
}

// ----------------------------------------------------------------------------
// Reason codes
// ----------------------------------------------------------------------------
enum PolicyBlockCode
{
  POLICY_OK            = 0,
  POLICY_SESSION_OFF   = 1,
  POLICY_NEWS_BLOCK    = 2,
  POLICY_MAX_LOSSES    = 3,
  POLICY_MAX_TRADES    = 4,
  POLICY_SPREAD_HIGH   = 5,
  POLICY_COOLDOWN      = 6
};

namespace Policies
{
  enum GateReason
  {
    GATE_OK         = 0,
    GATE_SPREAD     = 10,
    GATE_DAILYDD    = 11,
    GATE_VOLATILITY = 12,
    GATE_MOD_SPREAD = 13,
    GATE_COOLDOWN   = 14,
    GATE_REGIME     = 15,
    GATE_CALM       = 16,
    GATE_DAYLOSS    = 17,
    GATE_SESSION    = 18,
    GATE_NEWS       = 19,
    GATE_LIQUIDITY  = 20,
    GATE_CONFLICT   = 21,
    GATE_ADR        = 22,
    GATE_ACCOUNT_DD = 23
  };

  inline string ReasonString(const int r)
  {
    switch(r){
      case GATE_OK:         return "OK";
      case GATE_SPREAD:     return "SPREAD_CAP";
      case GATE_DAILYDD:    return "DAILY_DD";
      case GATE_VOLATILITY: return "VOLATILITY_BREAKER";
      case GATE_MOD_SPREAD: return "MOD_SPREAD";
      case GATE_COOLDOWN:   return "COOLDOWN";
      case GATE_REGIME:     return "REGIME";
      case GATE_CALM:       return "CALM";
      case GATE_DAYLOSS:    return "DAY_LOSS_STOP";
      case GATE_SESSION:    return "SESSION";
      case GATE_NEWS:       return "NEWS_BLOCK";
      case GATE_LIQUIDITY:  return "LIQUIDITY";
      case GATE_CONFLICT:   return "CONFLICT";
      case GATE_ADR:        return "ADR_CAP";
      case GATE_ACCOUNT_DD: return "ACCOUNT_DD_FLOOR";
      default:              return "UNKNOWN";
    }
  }

  // ----------------------------------------------------------------------------
  // Math helpers
  // ----------------------------------------------------------------------------
  inline double Clamp01(const double x){ return (x<0.0?0.0:(x>1.0?1.0:x)); }
  inline double Clamp  (const double x, const double lo, const double hi){ return (x<lo?lo:(x>hi?hi:x)); }
  inline int    EpochDay(datetime t){ return (int)(t/86400); }

  // ----------------------------------------------------------------------------
  // Compile-safe Settings getters
  // ----------------------------------------------------------------------------
  inline int CfgMaxSpreadPts(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAX_SPREAD_POINTS
      return (cfg.max_spread_points>0 ? cfg.max_spread_points : 0);
    #else
      return 0;
    #endif
  }
  inline bool CfgSessionFilter(const Settings &cfg)
  {
    #ifdef CFG_HAS_SESSION_FILTER
      return (bool)cfg.session_filter;
    #else
      return false;
    #endif
  }
  inline ENUM_TIMEFRAMES CfgTFEntry(const Settings &cfg)
  {
    #ifdef CFG_HAS_TF_ENTRY
      return cfg.tf_entry;
    #else
      return PERIOD_M15;
    #endif
  }
  inline int CfgATRPeriod(const Settings &cfg)
  {
    #ifdef CFG_HAS_ATR_PERIOD
      return (cfg.atr_period>0 ? cfg.atr_period : 14);
    #else
      return 14;
    #endif
  }
  inline double CfgAtrDampenF(const Settings &cfg)
  {
    #ifdef CFG_HAS_ATR_DAMPEN_F
      return Clamp(cfg.atr_dampen_f, 0.25, 2.00);
    #else
      return 1.00;
    #endif
  }
  inline double CfgMaxDailyDDPct(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAX_DAILY_DD_PCT
      return (cfg.max_daily_dd_pct>0.0 ? cfg.max_daily_dd_pct : 0.0);
    #else
      return 0.0;
    #endif
  }
  inline double CfgDayLossCapMoney(const Settings &cfg)
   {
     #ifdef CFG_HAS_DAY_LOSS_CAP_MONEY
       return (cfg.day_loss_cap_money>0.0 ? cfg.day_loss_cap_money : 0.0);
     #else
       return 0.0;
     #endif
   }
   inline double CfgDayLossCapPct(const Settings &cfg)
   {
     #ifdef CFG_HAS_DAY_LOSS_CAP_PCT
       return (cfg.day_loss_cap_pct>0.0 ? cfg.day_loss_cap_pct : 0.0);
     #else
       return 0.0; // falls back to daily DD if you prefer (see step 4)
     #endif
   }
   
   // --- Account-wide (challenge) DD taps ---------------------------------------
   inline double CfgMaxAccountDDPct(const Settings &cfg)
   {
     #ifdef CFG_HAS_MAX_ACCOUNT_DD_PCT
       return (cfg.max_account_dd_pct > 0.0 ? cfg.max_account_dd_pct : 0.0);
     #else
       // Sensible default for prop-challenge protection if field/macro absent
       return 5.0;
     #endif
   }
   
   inline double CfgChallengeInitEquity(const Settings &cfg)
   {
     #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
       return (cfg.challenge_init_equity > 0.0 ? cfg.challenge_init_equity : 0.0);
     #else
       return 0.0; // 0 => auto-capture from current equity on first use
     #endif
   }

  inline long CfgMagicNumber(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAGIC_NUMBER
      return (cfg.magic_number>0 ? (long)cfg.magic_number : 0);
    #else
      return 0;
    #endif
  }
  inline bool CfgCalmEnable(const Settings &cfg)
  {
    #ifdef CFG_HAS_CALM_MODE
      return (bool)cfg.calm_mode;
    #else
      return false;
    #endif
  }
  inline double CfgCalmMinATRPips(const Settings &cfg)
  {
    #ifdef CFG_HAS_CALM_MIN_ATR_PIPS
      return (cfg.calm_min_atr_pips>0.0 ? cfg.calm_min_atr_pips : 0.0);
    #else
      return 0.0;
    #endif
  }
  inline double CfgCalmMinATRtoSpread(const Settings &cfg)
  {
    #ifdef CFG_HAS_CALM_MIN_ATR_TO_SPREAD
      return (cfg.calm_min_atr_to_spread>0.0 ? cfg.calm_min_atr_to_spread : 0.0);
    #else
      return 0.0;
    #endif
  }
  // --- Weekly-open ramp (compile-safe) -----------------------------------------
   inline bool CfgWeeklyRampOn(const Settings &cfg)
   {
     #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
       return (bool)cfg.weekly_open_spread_ramp;
     #else
       // If the field/macro isn't compiled in, keep legacy behavior (ramp ON)
       return true;
     #endif
   }

  // --- News (compile-safe) ---------------------------------------------------
  inline bool CfgNewsOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_NEWS_ON
      return (bool)cfg.news_on;
    #else
      return false;
    #endif
  }
  inline int CfgNewsImpactMask(const Settings &cfg)
  {
    #ifdef CFG_HAS_NEWS_IMPACT_MASK
      return cfg.news_impact_mask;
    #else
      return (1<<1) | (1<<2); // MED+HIGH default
    #endif
  }
  inline int CfgNewsBlockPreMins(const Settings &cfg)
  {
    #ifdef CFG_HAS_NEWS_BLOCK_PRE_M
      return cfg.block_pre_m;
    #else
      return 0;
    #endif
  }
  inline int CfgNewsBlockPostMins(const Settings &cfg)
  {
    #ifdef CFG_HAS_NEWS_BLOCK_POST_M
      return cfg.block_post_m;
    #else
      return 0;
    #endif
  }
  inline int CfgCalLookbackMins(const Settings &cfg)
  {
    #ifdef CFG_HAS_CAL_LOOKBACK_MINS
      return cfg.cal_lookback_mins;
    #else
      return 60;
    #endif
  }
  inline double CfgCalHardSkip(const Settings &cfg)
  {
    #ifdef CFG_HAS_CAL_HARD_SKIP
      return (cfg.cal_hard_skip>0.0? cfg.cal_hard_skip : 2.0);
    #else
      return 2.0;
    #endif
  }
  inline double CfgCalSoftKnee(const Settings &cfg)
  {
    #ifdef CFG_HAS_CAL_SOFT_KNEE
      return (cfg.cal_soft_knee>0.0? cfg.cal_soft_knee : 0.6);
    #else
      return 0.6;
    #endif
  }
  inline double CfgCalMinScale(const Settings &cfg)
  {
    #ifdef CFG_HAS_CAL_MIN_SCALE
      return (cfg.cal_min_scale>0.0? cfg.cal_min_scale : 0.6);
    #else
      return 0.6;
    #endif
  }

  // --- Strategy toggles ------------------------------------------------------
  inline bool CfgEnableTrendPullback(const Settings &cfg)
  {
    #ifdef CFG_HAS_ENABLE_TREND_PULLBACK
      return (bool)cfg.enable_trend_pullback;
    #else
      return true;
    #endif
  }
  inline bool CfgEnableMRRange(const Settings &cfg)
  {
    #ifdef CFG_HAS_ENABLE_MR_RANGE
      return (bool)cfg.enable_mr_range_nr7ib;
    #else
      return true;
    #endif
  }
  inline bool CfgEnableNewsFade(const Settings &cfg)
  {
    #ifdef CFG_HAS_ENABLE_NEWS_FADE
      return (bool)cfg.enable_news_fade;
    #else
      return true;
    #endif
  }

  // --- Volatility breaker & spread adapt knobs -------------------------------
  inline double CfgVolBreakerLimit(const Settings &cfg)
  {
    #ifdef CFG_HAS_VOL_BREAKER_LIMIT
      return Clamp(cfg.vol_breaker_limit, 1.10, 5.00);
    #else
      return 2.50;
    #endif
  }
  inline double CfgModSpreadMult(const Settings &cfg)
  {
    #ifdef CFG_HAS_MOD_SPREAD_MULT
      return Clamp(cfg.mod_spread_mult, 0.10, 1.00);
    #else
      return 0.60;
    #endif
  }
  inline int CfgATRShort(const Settings &cfg)
  {
    #ifdef CFG_HAS_ATR_SHORT
      return (cfg.atr_short>0 ? cfg.atr_short : MathMax(10, CfgATRPeriod(cfg)));
    #else
      return MathMax(10, CfgATRPeriod(cfg));
    #endif
  }
  inline int CfgATRLong(const Settings &cfg)
  {
    #ifdef CFG_HAS_ATR_LONG
      return (cfg.atr_long>0 ? cfg.atr_long : 100);
    #else
      return 100;
    #endif
  }
  inline double CfgSpreadAdaptFloor(const Settings &cfg)
  {
    #ifdef CFG_HAS_SPREAD_ADAPT_FLOOR
      return Clamp(cfg.spread_adapt_floor, 0.30, 1.00);
    #else
      return 0.60;
    #endif
  }
  inline double CfgSpreadAdaptCeil(const Settings &cfg)
  {
    #ifdef CFG_HAS_SPREAD_ADAPT_CEIL
      return Clamp(cfg.spread_adapt_ceil, 1.00, 2.00);
    #else
      return 1.30;
    #endif
  }

  // --- Liquidity & regime ----------------------------------------------------
  inline double CfgLiqMinRatio(const Settings &cfg)
  {
    #ifdef CFG_HAS_LIQ_MIN_RATIO
      return (cfg.liq_min_ratio>0.0? cfg.liq_min_ratio : 1.50);
    #else
      return 1.50;
    #endif
  }
  inline bool CfgRegimeGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_REGIME_GATE_ON
      return (bool)cfg.regime_gate_on;
    #else
      return false;
    #endif
  }
  inline double CfgRegimeTQMin(const Settings &cfg)
  {
    #ifdef CFG_HAS_REGIME_TQ_MIN
      return Clamp01(cfg.regime_tq_min);
    #else
      return 0.10;
    #endif
  }
  inline double CfgRegimeSGMin(const Settings &cfg)
  {
    #ifdef CFG_HAS_REGIME_SG_MIN
      return Clamp01(cfg.regime_sg_min);
    #else
      return 0.10;
    #endif
  }

  // --- ADR caps --------------------------------------------------------------
  inline int CfgADRLookbackDays(const Settings &cfg)
   {
     #ifdef CFG_HAS_ADR_LOOKBACK
       return (cfg.adr_lookback_days>4 ? cfg.adr_lookback_days : 20);
     #else
       return 20;
     #endif
   }
   inline double CfgADRCapMult(const Settings &cfg)
   {
     #ifdef CFG_HAS_ADR_CAP_MULT
       return (cfg.adr_cap_mult>0.0 ? cfg.adr_cap_mult : 0.0); // 0 => disabled
     #else
       return 0.0;
     #endif
   }

  inline double CfgADRMinPips(const Settings &cfg)
  {
    #ifdef CFG_HAS_ADR_MIN_PIPS
      return (cfg.adr_min_pips>0.0? cfg.adr_min_pips : 0.0);
    #else
      return 0.0;
    #endif
  }
  inline double CfgADRMaxPips(const Settings &cfg)
  {
    #ifdef CFG_HAS_ADR_MAX_PIPS
      return (cfg.adr_max_pips>0.0? cfg.adr_max_pips : 0.0);
    #else
      return 0.0;
    #endif
  }

  // --- Cooldown knobs --------------------------------------------------------
  inline int CfgLossCooldownN(const Settings &cfg)
  {
    #ifdef CFG_HAS_LOSS_CD_N
      return (cfg.loss_cd_n>0? cfg.loss_cd_n : 2);
    #else
      return 2;
    #endif
  }
  inline int CfgLossCooldownMin(const Settings &cfg)
  {
    #ifdef CFG_HAS_LOSS_CD_MIN
      return (cfg.loss_cd_min>0? cfg.loss_cd_min : 15);
    #else
      return 15;
    #endif
  }
  inline int CfgTradeCooldownSec(const Settings &cfg)
  {
    #ifdef CFG_HAS_TRADE_CD_SEC
      return (cfg.trade_cd_sec>0? cfg.trade_cd_sec : 0);
    #else
      return 0;
    #endif
  }
  
  // =============================== ADX taps ===================================
   inline int CfgADXPeriod(const Settings &cfg)
   {
     #ifdef CFG_HAS_ADX_PARAMS
       return (cfg.adx_period>0? cfg.adx_period : 14);
     #else
       return 14;
     #endif
   }
   inline double CfgADXMinTrend(const Settings &cfg)
   {
     #ifdef CFG_HAS_ADX_PARAMS
       return (cfg.adx_min_trend>0.0? cfg.adx_min_trend : 18.0);
     #else
       return 18.0;
     #endif
   }
   inline double CfgADXUpper(const Settings &cfg)
   {
     #ifdef CFG_HAS_ADX_UPPER
       return (cfg.adx_upper>0.0? cfg.adx_upper : 35.0);
     #else
       return 35.0;
     #endif
   }
   
   // =============================== Corr taps ==================================
   inline string CfgCorrRefSymbol(const Settings &cfg)
   {
     #ifdef CFG_HAS_CORR_REF
       return cfg.corr_ref_symbol;
     #else
       return ""; // disabled by default
     #endif
   }
   inline int CfgCorrLookback(const Settings &cfg)
   {
     #ifdef CFG_HAS_CORR_LOOKBACK
       return (cfg.corr_lookback>0? cfg.corr_lookback : 180);
     #else
       return 180;
     #endif
   }
   inline double CfgCorrAbsMin(const Settings &cfg)
   {
     #ifdef CFG_HAS_CORR_ABS_MIN
       return (cfg.corr_min_abs>0.0? cfg.corr_min_abs : 0.60);
     #else
       return 0.60;
     #endif
   }
   inline ENUM_TIMEFRAMES CfgCorrTF(const Settings &cfg)
   {
     #ifdef CFG_HAS_CORR_TF
       return (cfg.corr_ema_tf>PERIOD_M1? cfg.corr_ema_tf : PERIOD_H1);
     #else
       return PERIOD_H1;
     #endif
   }
   inline double CfgCorrMaxPenalty(const Settings &cfg)
   {
     #ifdef CFG_HAS_CORR_MAX_PEN
       return (cfg.corr_max_pen>0.0? cfg.corr_max_pen : 0.25);
     #else
       return 0.25;
     #endif
   }
   
   // =============================== Weights ====================================
   inline double CfgW_ADXRegime(const Settings &cfg)
   {
     #ifdef CFG_HAS_W_ADX_REGIME
       return MathMax(0.0, cfg.w_adx_regime);
     #else
       return 1.0;
     #endif
   }
   inline double CfgW_News(const Settings &cfg)
   {
     #ifdef CFG_HAS_W_NEWS
       return MathMax(0.0, cfg.w_news);
     #else
       return 1.0;
     #endif
   }
   inline double CfgW_CorrPenalty(const Settings &cfg)
   {
     #ifdef CFG_HAS_W_CORR_PEN
       return MathMax(0.0, cfg.w_corr_pen);
     #else
       return 1.0;
     #endif
   }

   // -----------------------------------------------------------------------------
   // Fib / OTE score weights and thresholds
   // -----------------------------------------------------------------------------
   //
   // NOTE: The #ifdef guards mean you can safely compile even before
   // adding the corresponding fields into Config::Settings.
   // If you later add:
   //   double fib_ote_tol_atr;
   //   double fib_min_confluence;
   //   double fib_w_ote;
   //   double fib_w_conf;
   //   double fib_w_targets;
   //   double fib_sl_atr_mult;
   // and define the CFG_HAS_FIB_* macros in Config.mqh, these wrappers
   // will automatically pick them up.
   //
   
   inline double CfgFib_OTEToleranceATR(const Settings &cfg)
   {
   #ifdef CFG_HAS_FIB_OTE_TOL_ATR
      return (cfg.fib_ote_tol_atr > 0.0 ? cfg.fib_ote_tol_atr : 1.5);
   #else
      // How many ATRs from OTE mid until contribution decays to 0
      return 1.5;
   #endif
   }
   
   inline double CfgFib_MinConfluenceScore(const Settings &cfg)
   {
   #ifdef CFG_HAS_FIB_MIN_CONFLUENCE
      return (cfg.fib_min_confluence >= 0.0 ? cfg.fib_min_confluence : 0.50);
   #else
      // Minimum conf.score before we even consider it as a positive component
      return 0.50;
   #endif
   }
   
   inline double CfgFib_MinRRFibAllowed(const Settings &cfg)
   {
      return (cfg.minRRFibAllowed > 0.0 ? cfg.minRRFibAllowed : 1.5);
   }
   
   inline bool CfgFib_HardReject(const Settings &cfg)
   {
      return cfg.fibRRHardReject;
   }
   
   inline double CfgFib_W_OTE(const Settings &cfg)
   {
   #ifdef CFG_HAS_FIB_W_OTE
      return (cfg.fib_w_ote > 0.0 ? cfg.fib_w_ote : 0.10);
   #else
      // Weight of OTE component inside ICT score
      return 0.10;
   #endif
   }
   
   inline double CfgFib_W_Confluence(const Settings &cfg)
   {
   #ifdef CFG_HAS_FIB_W_CONFL
      return (cfg.fib_w_conf > 0.0 ? cfg.fib_w_conf : 0.05);
   #else
      // Weight of fib confluence component
      return 0.05;
   #endif
   }
   
   inline double CfgFib_W_Targets(const Settings &cfg)
   {
   #ifdef CFG_HAS_FIB_W_TARGETS
      return (cfg.fib_w_targets > 0.0 ? cfg.fib_w_targets : 0.05);
   #else
      // Weight of fib TP RR component
      return 0.05;
   #endif
   }
   
   inline double CfgFib_DefaultSL_ATRMult(const Settings &cfg)
   {
   #ifdef CFG_HAS_FIB_SL_ATR_MULT
      return (cfg.fib_sl_atr_mult > 0.0 ? cfg.fib_sl_atr_mult : 1.5);
   #else
      // Approx stop = k * ATR for RR estimate when hint_sl_pts is unavailable
      return 1.5;
   #endif
   }

  // ----------------------------------------------------------------------------
  // Per-symbol overrides (lightweight table)
  // ----------------------------------------------------------------------------
  struct SymOverride
  {
    string sym;
    int    max_spread_pts;  bool has_spread;
    bool   session_filter;      bool has_session;
    double liq_min_ratio;   bool has_liq;
    int    news_mask;       bool has_news_mask;
  };

  static SymOverride s_over[64];
  static int         s_over_n = 0;

  inline int _FindOverIdx(const string sym)
  { for(int i=0;i<s_over_n;i++) if(s_over[i].sym==sym) return i; return -1; }

  inline int _EnsureOver(const string sym)
  {
    int k=_FindOverIdx(sym);
    if(k>=0) return k;
    if(s_over_n<64){
      int idx = s_over_n++;
      s_over[idx].sym = sym;
      s_over[idx].has_spread=s_over[idx].has_session=s_over[idx].has_liq=s_over[idx].has_news_mask=false;
      s_over[idx].max_spread_pts=0; s_over[idx].session_filter=true; s_over[idx].liq_min_ratio=0.0; s_over[idx].news_mask=0;
      return idx;
    }
    return -1;
  }

  inline bool OverrideSetSpreadCap(const string sym, const int pts)
  { const int k=_EnsureOver(sym); if(k<0) return false; s_over[k].max_spread_pts=pts; s_over[k].has_spread=true; return true; }
  inline bool OverrideSetSession(const string sym, const bool on)
  { const int k=_EnsureOver(sym); if(k<0) return false; s_over[k].session_filter=on; s_over[k].has_session=true; return true; }
  inline bool OverrideSetLiquidityFloor(const string sym, const double ratio)
  { const int k=_EnsureOver(sym); if(k<0) return false; s_over[k].liq_min_ratio=ratio; s_over[k].has_liq=true; return true; }
  inline bool OverrideSetNewsMask(const string sym, const int mask)
  { const int k=_EnsureOver(sym); if(k<0) return false; s_over[k].news_mask=mask; s_over[k].has_news_mask=true; return true; }
  inline bool OverrideClear(const string sym)
  { const int k=_FindOverIdx(sym); if(k<0) return false; for(int i=k;i<s_over_n-1;i++) s_over[i]=s_over[i+1]; s_over_n--; return true; }
  inline void OverrideClearAll(){ s_over_n=0; }

  inline int EffMaxSpreadPts(const Settings &cfg, const string sym)
   {
     #ifdef CFG_HAS_PER_SYMBOL_OVERRIDES
       for(int i=0;i<ArraySize(cfg.sym_overrides); ++i)
       {
         const SymbolOverride ov = cfg.sym_overrides[i];
         if(!ov.enabled || ov.symbol!=sym) continue;
         if(ov.has_max_spread) return ov.max_spread_points;
       }
     #endif
     const int k=_FindOverIdx(sym);
     if(k>=0 && s_over[k].has_spread) return s_over[k].max_spread_pts;
     return CfgMaxSpreadPts(cfg);
   }

  inline bool EffSessionFilter(const Settings &cfg, const string sym)
  { const int k=_FindOverIdx(sym); if(k>=0 && s_over[k].has_session) return s_over[k].session_filter; return CfgSessionFilter(cfg); }
  inline double EffLiqMinRatio(const Settings &cfg, const string sym, const double default_floor)
  { const int k=_FindOverIdx(sym); if(k>=0 && s_over[k].has_liq) return s_over[k].liq_min_ratio; return (default_floor>0.0? default_floor : CfgLiqMinRatio(cfg)); }
  inline int EffNewsImpactMask(const Settings &cfg, const string sym)
  { const int k=_FindOverIdx(sym); if(k>=0 && s_over[k].has_news_mask) return s_over[k].news_mask; return CfgNewsImpactMask(cfg); }

  // ----------------------------------------------------------------------------
  // ATR & ADR helpers (with optional dampening)
  // ----------------------------------------------------------------------------
  inline double AtrPts(const string sym, const ENUM_TIMEFRAMES tf, const Settings &cfg, const int period, const int shift=1)
  {
    const double base = Indi::ATRPoints(sym, tf, (period>0?period:14), (shift>0?shift:1));
    return base * CfgAtrDampenF(cfg);
  }

  // ADR: average of (High-Low) over prior N *completed* D1 bars, returned in *points*
  inline double ADRPoints(const string sym, const int lookback_days)
  {
    const int lb = (lookback_days>4? lookback_days : 20);
    MqlRates rr[]; ArraySetAsSeries(rr,true);
    if(CopyRates(sym, PERIOD_D1, 1, lb, rr)!=lb) return 0.0;

    double pt = SymbolInfoDouble(sym, SYMBOL_POINT); if(pt<=0.0) pt=_Point;
    if(pt<=0.0) return 0.0;

    double sumPts=0.0;
    for(int i=0;i<lb;i++)
      sumPts += MathAbs(rr[i].high - rr[i].low)/pt;

    return (sumPts/lb);
  }

  // ADR cap gate: min/max bounds in pips; reason set to GATE_ADR if tripped
  inline bool ADRCapOK(const Settings &cfg, int &reason, double &adr_pts_out)
   {
     reason = GATE_OK; adr_pts_out = 0.0;
     const double adr_pts = ADRPoints(_Symbol, CfgADRLookbackDays(cfg));
     if(adr_pts<=0.0) return true; // neutral if cannot compute
     adr_pts_out = adr_pts;
   
     #ifdef CFG_HAS_ADR_CAP_MULT
       const double cap_mult = CfgADRCapMult(cfg);            // e.g. 2.2
       if(cap_mult > 0.0)
       {
         // Real-time D1 range so far (points)
         MqlRates d1[]; ArraySetAsSeries(d1,true);
         if(CopyRates(_Symbol, PERIOD_D1, 0, 1, d1)==1)
         {
           const double today_pts = MathAbs(d1[0].high - d1[0].low) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
           const double limit_pts = adr_pts * cap_mult;
           if(today_pts >= limit_pts){ reason=GATE_ADR; return false; }
         }
       }
       return true;
     #else
       // (Optional legacy path) keep only if still used elsewhere:
       const double min_pips = CfgADRMinPips(cfg);
       const double max_pips = CfgADRMaxPips(cfg);
       if(min_pips<=0.0 && max_pips<=0.0) return true;
   
       const double pts_per_pip = MarketData::PointsFromPips(_Symbol, 1.0);
       const double min_pts = (min_pips>0.0 ? min_pips * pts_per_pip : 0.0);
       const double max_pts = (max_pips>0.0 ? max_pips * pts_per_pip : 0.0);
       if(min_pts>0.0 && adr_pts < min_pts){ reason=GATE_ADR; return false; }
       if(max_pts>0.0 && adr_pts > max_pts){ reason=GATE_ADR; return false; }
       return true;
     #endif
   }

  // ----------------------------------------------------------------------------
  // PERSISTENT STATE (via Global Variables)
  // ----------------------------------------------------------------------------
  static bool     s_loaded          = false;
  static string   s_prefix          = "";    // "CA:POL:<login>:<magic>:"
  static long     s_login           = 0;
  static long     s_magic_cached    = 0;

  static int      s_dayKey          = -1;    // epoch-day
  static double   s_dayEqStart      =  0.0;

  // day-loss hard stop persistence
  static bool     s_dayStopHit      = false;
  static int      s_dayStopDay      = -1;
  
  // account-wide (challenge) DD persistence
  static double   s_acctEqStart    = 0.0;  // fixed baseline (challenge init equity)
  static bool     s_acctStopHit    = false; // latched once floor is breached

  static int      s_loss_streak     = 0;
  static int      s_cooldown_losses = 2;
  static int      s_cooldown_min    = 15;
  static datetime s_cooldown_until  = 0;

  static int      s_trade_cd_sec    = 0;
  static datetime s_trade_cd_until  = 0;

  // --- GV helpers ---
  inline string _Key(const string name){ return s_prefix + name; }
  inline double _GVGetD(const string k, const double defv=0.0){ return (GlobalVariableCheck(k)? GlobalVariableGet(k) : defv); }
  inline int    _GVGetI(const string k, const int defv=0){ return (int)MathRound(_GVGetD(k, (double)defv)); }
  inline bool   _GVGetB(const string k, const bool defb=false){ return (_GVGetI(k, (defb?1:0))!=0); }
  inline void   _GVSetD(const string k, const double v){ GlobalVariableSet(k, v); }
  inline void   _GVSetB(const string k, const bool v){ GlobalVariableSet(k, (v?1.0:0.0)); }
  inline void   _GVDel (const string k){ if(GlobalVariableCheck(k)) GlobalVariableDel(k); }

  inline void _BuildPrefix(const Settings &cfg)
  {
    s_login = (long)AccountInfoInteger(ACCOUNT_LOGIN);
    s_magic_cached = CfgMagicNumber(cfg);
    s_prefix = StringFormat("CA:POL:%I64d:%I64d:", s_login, s_magic_cached);
  }

  inline void _PersistCore()
  {
    _GVSetD(_Key("DAYKEY"),        (double)s_dayKey);
    _GVSetD(_Key("DAYEQ0"),        s_dayEqStart);
    _GVSetB(_Key("DAY_STOP_FLAG"), s_dayStopHit);
    _GVSetD(_Key("DAY_STOP_DAY"),  (double)s_dayStopDay);

    _GVSetD(_Key("LOSS_STREAK"),   (double)s_loss_streak);
    _GVSetD(_Key("COOL_N"),        (double)s_cooldown_losses);
    _GVSetD(_Key("COOL_MIN"),      (double)s_cooldown_min);
    _GVSetD(_Key("COOL_UNTIL"),    (double)s_cooldown_until);
    _GVSetD(_Key("TRADECD_SEC"),   (double)s_trade_cd_sec);
    _GVSetD(_Key("TRADECD_UNTIL"), (double)s_trade_cd_until);
    
    // account-wide floor
    _GVSetD(_Key("ACCT_EQ0"),          s_acctEqStart);
    _GVSetB(_Key("ACCT_DD_STOP_FLAG"), s_acctStopHit);
  }

  inline void _ResetDayStopForNewDayIfNeeded(const int curD)
  {
    const int gvD = _GVGetI(_Key("DAY_STOP_DAY"), -1);
    if(gvD!=curD){
      s_dayStopHit = false; s_dayStopDay = curD;
      _GVSetB(_Key("DAY_STOP_FLAG"), false);
      _GVSetD(_Key("DAY_STOP_DAY"),  (double)curD);
    }
  }

  inline void _EnsureDayState()
  {
    const int curD = EpochDay(TimeCurrent());
    int    storedD = _GVGetI(_Key("DAYKEY"), -1);
    double eq0     = _GVGetD(_Key("DAYEQ0"), 0.0);

    if(storedD!=curD || eq0<=0.0)
    {
      storedD = curD;
      eq0 = AccountInfoDouble(ACCOUNT_EQUITY);
      _GVSetD(_Key("DAYKEY"), (double)storedD);
      _GVSetD(_Key("DAYEQ0"), eq0);
    }
    s_dayKey     = storedD;
    s_dayEqStart = eq0;

    // sync day-stop
    s_dayStopHit = _GVGetB(_Key("DAY_STOP_FLAG"), false);
    s_dayStopDay = _GVGetI(_Key("DAY_STOP_DAY"), curD);
    _ResetDayStopForNewDayIfNeeded(curD);
  }
  
  inline void _EnsureAccountBaseline(const Settings &cfg)
   {
     if(s_acctEqStart > 0.0) return;
   
     // 1) Prefer explicit config (if provided)
     const double cfg0 = CfgChallengeInitEquity(cfg);
     if(cfg0 > 0.0)
     {
       s_acctEqStart = cfg0;
       _GVSetD(_Key("ACCT_EQ0"), s_acctEqStart);
       return;
     }
   
     // 2) Otherwise, use persisted GV if present
     const double gv0 = _GVGetD(_Key("ACCT_EQ0"), 0.0);
     if(gv0 > 0.0)
     {
       s_acctEqStart = gv0;
       return;
     }
   
     // 3) Last resort: capture current equity (first run)
     s_acctEqStart = AccountInfoDouble(ACCOUNT_EQUITY);
     if(s_acctEqStart > 0.0)
       _GVSetD(_Key("ACCT_EQ0"), s_acctEqStart);
   }

  inline void _LoadPersistent(const Settings &cfg)
  {
    _BuildPrefix(cfg);
    // Runtime knobs from cfg
    s_cooldown_losses = CfgLossCooldownN(cfg);
    s_cooldown_min    = CfgLossCooldownMin(cfg);
    s_trade_cd_sec    = CfgTradeCooldownSec(cfg);
    _GVSetD(_Key("COOL_N"),      (double)s_cooldown_losses);
    _GVSetD(_Key("COOL_MIN"),    (double)s_cooldown_min);
    _GVSetD(_Key("TRADECD_SEC"), (double)s_trade_cd_sec);

    // Restore persisted running state
    s_loss_streak    = _GVGetI(_Key("LOSS_STREAK"), 0);
    s_cooldown_until = (datetime)_GVGetD(_Key("COOL_UNTIL"), 0.0);
    s_trade_cd_until = (datetime)_GVGetD(_Key("TRADECD_UNTIL"), 0.0);
    
    // account-wide floor (challenge)
    s_acctEqStart = _GVGetD(_Key("ACCT_EQ0"), 0.0);
    s_acctStopHit = _GVGetB(_Key("ACCT_DD_STOP_FLAG"), false);

    // Daily anchors and day-stop
    _EnsureDayState();

    s_loaded = true;
  }

  inline void _EnsureLoaded(const Settings &cfg){ if(!s_loaded) _LoadPersistent(cfg); }

  // Public lifecycle (call from EA if convenient; otherwise _EnsureLoaded runs on-demand)
  inline bool Init(const Settings &cfg){ _LoadPersistent(cfg); return true; }
  inline void Deinit(){ if(StringLen(s_prefix)>0) _PersistCore(); }

  // ----------------------------------------------------------------------------
  // Daily state & realized P/L  (uses persisted dayEqStart and history)
  // ----------------------------------------------------------------------------
  inline void TodayRange(datetime &t0, datetime &t1)
  { const int d=(int)(TimeCurrent()/86400); t0=(datetime)(d*86400); t1=t0+86400; }

  inline bool DailyRealizedPL(const Settings &cfg, double &pl_money_out, int &wins_out, int &losses_out)
  {
    pl_money_out=0.0; wins_out=0; losses_out=0;
    datetime t0,t1; TodayRange(t0,t1);
    if(!HistorySelect(t0,t1)) return false;

    const long magic = CfgMagicNumber(cfg);
    const int n = HistoryDealsTotal();
    for(int i=n-1;i>=0;--i)
    {
      const ulong deal = HistoryDealGetTicket(i);
      if(deal==0) continue;
      const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(!(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT)) continue;

      if(magic>0){
        const long mn = HistoryDealGetInteger(deal, DEAL_MAGIC);
        if(mn!=magic) continue;
      }
      const double pl = HistoryDealGetDouble(deal, DEAL_PROFIT);
      pl_money_out += pl;
      if(pl>=0.0) wins_out++; else losses_out++;
    }
    return true;
  }

  // -- helper for HUD
  inline int _SecondsLeft(const datetime until)
  {
    if(until<=0) return 0;
    const datetime now = TimeCurrent();
    if(now>=until) return 0;
    return (int)(until - now);
  }

  inline bool DailyEquityDDHit(const Settings &cfg, double &dd_pct_out)
  {
    _EnsureLoaded(cfg);
    _EnsureDayState();

    dd_pct_out=0.0;
    const double limit_pct = CfgMaxDailyDDPct(cfg);
    if(limit_pct<=0.0) return false;

    const double eq0 = s_dayEqStart;
    const double eq1 = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq0<=0.0 || eq1<=0.0) return false;

    const double dd = (eq0 - eq1);
    if(dd<=0.0) return false;

    dd_pct_out = 100.0 * dd / eq0;
    return (dd_pct_out >= limit_pct);
  }
  
  // ----------------------------------------------------------------------------
   // Account-wide (challenge) equity drawdown floor
   // Measures against fixed challenge baseline (never re-anchors).
   // Latches a stop flag via GV so restarts remain blocked.
   // ----------------------------------------------------------------------------
   inline bool AccountEquityDDHit(const Settings &cfg, double &dd_pct_out)
   {
     _EnsureLoaded(cfg);
     _EnsureAccountBaseline(cfg);
   
     dd_pct_out = 0.0;
   
     // Already latched?
     if(s_acctStopHit || _GVGetB(_Key("ACCT_DD_STOP_FLAG"), false))
     {
       // If you want to show telemetry, supply floor value:
       const double lim = CfgMaxAccountDDPct(cfg);
       if(lim > 0.0) dd_pct_out = lim;  // informational
       s_acctStopHit = true;            // sync local
       return true;
     }
   
     const double limit_pct = CfgMaxAccountDDPct(cfg);
     if(limit_pct <= 0.0) return false;
   
     const double eq0 = s_acctEqStart;
     const double eq1 = AccountInfoDouble(ACCOUNT_EQUITY);
     if(eq0 <= 0.0 || eq1 <= 0.0) return false;
   
     const double dd_money = (eq0 - eq1);
     if(dd_money <= 0.0) return false;
   
     const double dd_pct = 100.0 * dd_money / eq0;
     dd_pct_out = dd_pct;
   
     if(dd_pct >= limit_pct)
     {
       s_acctStopHit = true;
       _GVSetB(_Key("ACCT_DD_STOP_FLAG"), true);
       _GVSetD(_Key("ACCT_DD_STOP_TS"), (double)TimeCurrent()); // optional audit
       return true;
     }
     return false;
   }

  inline bool DailyLossStopHit(const Settings &cfg, double &loss_money_out, double &loss_pct_out)
   {
     _EnsureLoaded(cfg); _EnsureDayState();
     loss_money_out=0.0; loss_pct_out=0.0;
   
     const double cap_money = CfgDayLossCapMoney(cfg); // money hard cap
     double cap_pct = CfgDayLossCapPct(cfg);           // percent cap
     if(cap_pct<=0.0) cap_pct = CfgMaxDailyDDPct(cfg); // optional: fallback to equity DD limit
   
     if(cap_money<=0.0 && cap_pct<=0.0) return false;
     if(s_dayStopHit && s_dayStopDay==s_dayKey) return true;
   
     double pl=0.0; int w=0,l=0; if(!DailyRealizedPL(cfg, pl, w, l)) return false;
     if(pl>=0.0) return false;
     loss_money_out = -pl;
     loss_pct_out = (s_dayEqStart>0.0 ? 100.0*loss_money_out/s_dayEqStart : 0.0);
   
     if( (cap_money>0.0 && loss_money_out >= cap_money) ||
         (cap_pct>0.0   && loss_pct_out   >= cap_pct) )
     {
       s_dayStopHit = true; s_dayStopDay = s_dayKey;
       _GVSetB(_Key("DAY_STOP_FLAG"), true);
       _GVSetD(_Key("DAY_STOP_DAY"),  (double)s_dayStopDay);
       return true;
     }
     return false;
   }

  // ----------------------------------------------------------------------------
  // Modified spread gate + ATR-adaptive scaling
  // ----------------------------------------------------------------------------
  static double s_mod_mult_outside = 0.60;
  inline void SetMoDMultiplier(const double m){ s_mod_mult_outside = Clamp(m,0.10,1.00); }

  static int    s_vb_shortP = 0;
  static int    s_vb_longP  = 100;
  static double s_spread_cap_floor = 0.60;
  static double s_spread_cap_ceil  = 1.30;

  inline void SetSpreadATRAdapt(const int shortP, const int longP,
                                const double floor_mult, const double ceil_mult)
  {
    s_vb_shortP = (shortP<0?0:shortP);
    s_vb_longP  = (longP<20?20:longP);
    s_spread_cap_floor = Clamp(floor_mult, 0.30, 1.00);
    s_spread_cap_ceil  = Clamp(ceil_mult, 1.00, 2.00);
  }

  inline double SpreadCapAdaptiveMult(const Settings &cfg)
  {
    const string sym=_Symbol;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = (s_vb_shortP>0 ? s_vb_shortP : CfgATRShort(cfg));
    const int longP  = s_vb_longP;

    const double aS = AtrPts(sym, tf, cfg, shortP, 1);
    const double aL = AtrPts(sym, tf, cfg, longP,  1);
    if(aS<=0.0 || aL<=0.0) return 1.0;

    const double ratio = aS/aL;
    double t = (ratio - 0.8) / 1.0; // 0 @0.8, 1 @1.8
    t = Clamp01(t);
    return Clamp( (1.0 + (s_spread_cap_ceil - 1.0)*t), s_spread_cap_floor, s_spread_cap_ceil );
  }
  
  // --- Weekly-open spread ramp (first hour after weekly open) -------------------
   // Adjust a spread cap expressed in *points*. Uses server time Mon 00:00–00:59.
   inline double AdjustSpreadCapWeeklyOpenPts(const Settings &/*cfg*/, const double cap_pts_in)
   {
     double cap = cap_pts_in;
     if(cap <= 0.0) return cap;                // 0/neg => no cap
   
     MqlDateTime ds; TimeToStruct(TimeCurrent(), ds); // server time
     if(ds.day_of_week == 1 /*Mon*/ && ds.hour == 0)
     {
       // ensure the effective cap is at least 8.0 pips (converted to points)
       const double ppp = MarketData::PointsFromPips(_Symbol, 1.0); // points in 1 pip
       if(ppp > 0.0){
         const double min_pts = 8.0 * ppp;
         if(cap < min_pts) cap = min_pts;
       }
     }
     return cap;
   }

  inline bool MoDSpreadOK(const Settings &cfg, int &reason)
  {
    _EnsureLoaded(cfg);

    reason = GATE_OK;
    int cap = EffMaxSpreadPts(cfg, _Symbol);
    if(cap<=0) return true;

    const double adapt = SpreadCapAdaptiveMult(cfg);
    // apply adaptive scaling first
    double eff_cap_pts = MathFloor((double)cap * adapt);
    
    // weekly-open ramp (points)
    if(CfgWeeklyRampOn(cfg))
      eff_cap_pts = AdjustSpreadCapWeeklyOpenPts(cfg, eff_cap_pts);
    cap = (int)MathFloor(eff_cap_pts);

    const double sp = MarketData::SpreadPoints(_Symbol);
    if(sp<=0.0) return true;

    if(EffSessionFilter(cfg, _Symbol))
    {
      const bool inwin = TimeUtils::InTradingWindow(cfg, TimeCurrent());
      if(!inwin)
      {
        const int tight = (int)MathFloor(s_mod_mult_outside * (double)cap);
        if(tight>0 && (int)sp>tight){ reason=GATE_MOD_SPREAD; return false; }
      }
    }

    if((int)sp>cap){ reason=GATE_SPREAD; return false; }
    return true;
  }

  // ----------------------------------------------------------------------------
  // Volatility breaker (re-uses short/long ATR config)
  // ----------------------------------------------------------------------------
  static double s_vb_limit = 2.50;
  inline void SetVolBreakerLimit(const double limit){ s_vb_limit=(limit<1.10?1.10:limit); }

  inline bool VolatilityBreaker(const Settings &cfg, double &ratio_out)
  {
    _EnsureLoaded(cfg);

    ratio_out = 0.0;
    const string sym=_Symbol;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);

    const int shortP = (s_vb_shortP>0 ? s_vb_shortP : CfgATRShort(cfg));
    const int longP  = s_vb_longP;

    const double aS = AtrPts(sym, tf, cfg, shortP, 1);
    const double aL = AtrPts(sym, tf, cfg, longP,  1);
    if(aS<=0.0 || aL<=0.0) return false;

    ratio_out = aS/aL;
    return (ratio_out > s_vb_limit);
  }

  // ----------------------------------------------------------------------------
  // Calm mode
  // ----------------------------------------------------------------------------
  inline bool CalmModeOK(const Settings &cfg, int &reason)
  {
    _EnsureLoaded(cfg);

    reason = GATE_OK;
    if(!CfgCalmEnable(cfg)) return true;

    const string sym=_Symbol;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = CfgATRShort(cfg);

    const double atr_s = AtrPts(sym, tf, cfg, shortP, 1);
    if(atr_s<=0.0) return true;

    const double minAtrPips = CfgCalmMinATRPips(cfg);
    if(minAtrPips>0.0)
    {
      const double minPts = MarketData::PointsFromPips(sym, minAtrPips);
      if(minPts>0.0 && atr_s<minPts){ reason=GATE_CALM; return false; }
    }

    const double minRatio = CfgCalmMinATRtoSpread(cfg);
    if(minRatio>0.0)
    {
      const double spr = MarketData::SpreadPoints(sym);
      if(spr>0.0 && atr_s/spr < minRatio){ reason=GATE_CALM; return false; }
    }
    return true;
  }

  // ----------------------------------------------------------------------------
  // Loss/cooldown management (PERSISTED)
  // ----------------------------------------------------------------------------
  inline void SetLossCooldownParams(const int losses, const int minutes)
  { s_cooldown_losses=(losses<1?1:losses); s_cooldown_min=(minutes<1?1:minutes); _GVSetD(_Key("COOL_N"), (double)s_cooldown_losses); _GVSetD(_Key("COOL_MIN"), (double)s_cooldown_min); }

  inline void NotifyTradeResult(const double r_multiple)
  {
    if(r_multiple<0.0) s_loss_streak++; else s_loss_streak=0;
    _GVSetD(_Key("LOSS_STREAK"), (double)s_loss_streak);
    if(s_loss_streak >= s_cooldown_losses)
    {
      s_cooldown_until = TimeCurrent() + (datetime)(s_cooldown_min*60);
      _GVSetD(_Key("COOL_UNTIL"), (double)s_cooldown_until);
      s_loss_streak = 0; _GVSetD(_Key("LOSS_STREAK"), 0.0);
    }
  }

  inline bool LossCooldownActive()
  {
    if(s_cooldown_until<=0) return false;
    if(TimeCurrent() >= s_cooldown_until){ s_cooldown_until=0; _GVSetD(_Key("COOL_UNTIL"), 0.0); return false; }
    return true;
  }

  inline void SetTradeCooldownSeconds(const int sec){ s_trade_cd_sec=(sec<0?0:sec); _GVSetD(_Key("TRADECD_SEC"), (double)s_trade_cd_sec); }
  inline void NotifyTradePlaced(){ if(s_trade_cd_sec>0){ s_trade_cd_until = TimeCurrent() + (datetime)s_trade_cd_sec; _GVSetD(_Key("TRADECD_UNTIL"), (double)s_trade_cd_until); } }
  inline bool TradeCooldownActive()
  {
    if(s_trade_cd_sec<=0 || s_trade_cd_until<=0) return false;
    if(TimeCurrent() >= s_trade_cd_until){ s_trade_cd_until=0; _GVSetD(_Key("TRADECD_UNTIL"), 0.0); return false; }
    return true;
  }
  inline int  TradeCooldownSecondsLeft(){ return _SecondsLeft(s_trade_cd_until); }
  inline int  LossCooldownSecondsLeft(){  return _SecondsLeft(s_cooldown_until); }

  // --- Hooks expected by Execution.mqh ---
  inline void TouchTradeCooldown(){ NotifyTradePlaced(); }

  inline void RecordExecutionAttempt()
  {
    _GVSetD(_Key("LAST_ATTEMPT_TS"), (double)TimeCurrent());
    // optional: increment per-day attempts counter
    int cnt = _GVGetI(_Key("ATTEMPTS_D"), 0);
    const int curD = EpochDay(TimeCurrent());
    const int dGV  = _GVGetI(_Key("ATTEMPTS_D_DAY"), -1);
    if(dGV!=curD){ _GVSetD(_Key("ATTEMPTS_D_DAY"), (double)curD); cnt=0; }
    _GVSetD(_Key("ATTEMPTS_D"), (double)(cnt+1));
  }

  inline void RecordExecutionResult(const bool ok, const uint retcode, const double filled)
  {
    _GVSetD(_Key("LAST_OK"), (ok?1.0:0.0));
    _GVSetD(_Key("LAST_RC"), (double)retcode);
    _GVSetD(_Key("LAST_FILLED"), filled);
    _GVSetD(_Key("LAST_RESULT_TS"), (double)TimeCurrent());
  }

  // ----------------------------------------------------------------------------
  // Regime consensus / correlation-style gate
  // ----------------------------------------------------------------------------
  static bool   s_regime_gate_on = false;
  static double s_reg_tq_min     = 0.10;
  static double s_reg_sg_min     = 0.10;

  inline void EnableRegimeGate(const bool on){ s_regime_gate_on = on; }
  inline void SetRegimeThresholds(const double tq_min, const double sg_min)
  { s_reg_tq_min=Clamp01(tq_min); s_reg_sg_min=Clamp01(sg_min); }

  inline bool RegimeConsensusOK(const Settings &cfg)
  {
    if(!s_regime_gate_on) return true;
    const string sym=_Symbol;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const double tq = RegimeX::TrendQuality(sym, tf, 60);
    const double sg = Corr::HysteresisSlopeGuard(sym, tf, 14,23.0,15.0);
    return (tq>=s_reg_tq_min) || (sg>=s_reg_sg_min);
  }

  // ----------------------------------------------------------------------------
  // Liquidity (ATR:Spread) floor
  // ----------------------------------------------------------------------------
  static double s_liq_min_ratio = 1.50;
  inline void   SetLiquidityParams(const double min_ratio)
  { s_liq_min_ratio = Clamp(min_ratio, 0.5, 10.0); }

  inline bool LiquidityOK(const Settings &cfg, double &ratio_out)
  {
    ratio_out = 0.0;
    const string sym=_Symbol;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = CfgATRShort(cfg);
    const double atr_s = AtrPts(sym, tf, cfg, shortP, 1);
    const double spr   = MarketData::SpreadPoints(sym);
    if(atr_s<=0.0 || spr<=0.0) return true;

    const double floorR = EffLiqMinRatio(cfg, sym, s_liq_min_ratio);
    ratio_out = atr_s / spr;
    return (ratio_out >= floorR);
  }

  // ----------------------------------------------------------------------------
  // News helpers
  // ----------------------------------------------------------------------------
  inline bool NewsBlockedNow(const Settings &cfg, int &mins_left_out)
   {
     mins_left_out=0;
     if(!CfgNewsOn(cfg)) return false;
     #ifdef NEWSFILTER_AVAILABLE
       return News::IsBlocked(TimeCurrent(), _Symbol,
                              EffNewsImpactMask(cfg, _Symbol),
                              CfgNewsBlockPreMins(cfg),
                              CfgNewsBlockPostMins(cfg),
                              mins_left_out);
     #else
       return false; // news module not present
     #endif
   }
   
   inline void ApplyNewsScaling(const Settings &cfg, const string sym,
                                StratScore &ss, ConfluenceBreakdown &bd, bool &skip_out)
   {
     skip_out=false;
     if(!CfgNewsOn(cfg)) return;
     #ifdef NEWSFILTER_AVAILABLE
       double risk_mult=1.0; bool skip=false;
       News::SurpriseRiskAdjust(TimeCurrent(), sym,
                                EffNewsImpactMask(cfg, sym),
                                CfgCalLookbackMins(cfg),
                                CfgCalHardSkip(cfg),
                                CfgCalSoftKnee(cfg),
                                CfgCalMinScale(cfg),
                                risk_mult, skip);
       if(skip){ skip_out=true; return; }
       risk_mult = Clamp(risk_mult, 0.10, 1.50);
       ss.risk_mult = Clamp01(ss.risk_mult * Clamp01(risk_mult));
       bd.score_final = ss.score;
     #else
       // pass-through when news module is absent
       (void)sym; (void)bd;
     #endif
   }

  // ----------------------------------------------------------------------------
  // Core gates: Check / CheckFull / AllowedByPolicies
  // ----------------------------------------------------------------------------
  inline bool Check(const Settings &cfg, int &reason)
  {
    _EnsureLoaded(cfg);

    // ensure runtime knobs applied even when intent builder isn’t used
    SetMoDMultiplier(CfgModSpreadMult(cfg));
    SetSpreadATRAdapt(CfgATRShort(cfg), CfgATRLong(cfg), CfgSpreadAdaptFloor(cfg), CfgSpreadAdaptCeil(cfg));
    SetVolBreakerLimit(CfgVolBreakerLimit(cfg));
    SetLiquidityParams(CfgLiqMinRatio(cfg));
    SetLossCooldownParams(CfgLossCooldownN(cfg), CfgLossCooldownMin(cfg));
    SetTradeCooldownSeconds(CfgTradeCooldownSec(cfg));

    // day-loss latch check first (cheap, persistent)
    double lossM=0.0, lossPct=0.0;
    if(DailyLossStopHit(cfg, lossM, lossPct)){ reason=GATE_DAYLOSS; return false; }

    if(!MoDSpreadOK(cfg, reason)) return false;

    // daily equity drawdown vs day anchor
    double dd=0.0;
    if(DailyEquityDDHit(cfg, dd)){ reason=GATE_DAILYDD; return false; }

    // account-wide challenge floor (never re-anchors)
    double acct_dd=0.0;
    if(AccountEquityDDHit(cfg, acct_dd)){ reason=GATE_ACCOUNT_DD; return false; }

    if(LossCooldownActive() || TradeCooldownActive()){ reason=GATE_COOLDOWN; return false; }
    
    #ifdef CFG_HAS_LONDON_LIQ_POLICY
    #ifdef CFG_HAS_LONDON_LOCAL_MINUTES
    {
      const bool in_lon =
          _WithinLocalWindowMins(cfg.london_local_open_min,
                                 cfg.london_local_close_min,
                                 TimeLocal());
 
      if(cfg.london_liquidity_policy)
      {
        // Slightly tighter liquidity ratio in London local window; slightly looser outside
        const double base = CfgLiqMinRatio(cfg);
        const double mult = (in_lon ? 0.95 : 1.05);
        SetLiquidityParams(base * mult);
      }
    }
    #endif  // CFG_HAS_LONDON_LOCAL_MINUTES
    #endif  // CFG_HAS_LONDON_LIQ_POLICY

    double vr=0.0;
    if(VolatilityBreaker(cfg, vr)){ reason=GATE_VOLATILITY; return false; }

    double adr_pts=0.0;
    if(!ADRCapOK(cfg, reason, adr_pts)) return false;

    if(!CalmModeOK(cfg, reason)) return false;

    EnableRegimeGate(CfgRegimeGateOn(cfg));
    SetRegimeThresholds(CfgRegimeTQMin(cfg), CfgRegimeSGMin(cfg));
    if(!RegimeConsensusOK(cfg)){ reason=GATE_REGIME; return false; }
    

    reason=GATE_OK; return true;
  }

  inline bool CheckFull(const Settings &cfg, int &reason, int &minutes_left_news)
  {
    minutes_left_news = 0;

    if(cfg.debug)
    {
      // Session gate
      const bool sessOn = Policies::EffSessionFilter(cfg, _Symbol);
      const bool inWin  = TimeUtils::InTradingWindow(cfg, TimeCurrent());
      const bool ok_sess = (!sessOn) || inWin;

      // Daily DD
      double ddPct = 0.0;
      const bool ok_daily_dd = !Policies::DailyEquityDDHit(cfg, ddPct);

      // Account-wide DD floor (challenge)
      double acct_dd_pct = 0.0;
      const bool ok_acct_dd = !Policies::AccountEquityDDHit(cfg, acct_dd_pct);

      const bool ok_dd = (ok_daily_dd && ok_acct_dd);

      // Day losses
      const bool ok_loss = !Policies::MaxLossesReachedToday(cfg);

      // News
      int mins_left = 0;
      const bool ok_news = !Policies::NewsBlockedNow(cfg, mins_left);

      // Router floor (no Router include to avoid cycles; mirror RouterMinScore)
      double routerMin =
      #ifdef CFG_HAS_ROUTER_MIN_SCORE
          (cfg.router_min_score>0.0 ? cfg.router_min_score : Const::SCORE_ELIGIBILITY_MIN);
      #else
          Const::SCORE_ELIGIBILITY_MIN;
      #endif

      // Router score unknown at this layer
      const double routerScore = -1.0;

      // ML compile-safe
      bool   mlEnabled = false;
      double mlScore   = 0.0;
      double mlThresh  =
      #ifdef CFG_HAS_ML_THRESHOLD
          cfg.ml_threshold;
      #else
          0.55;
      #endif

      #ifdef CFG_HAS_ROUTER_MIN_SCORE
         DbgWhyNoTrade(routerScore, routerMin, ok_sess, ok_dd, ok_loss, ok_news,
                       mlEnabled, mlScore, mlThresh);
      #endif
    }

    if(!Check(cfg, reason)) return false;

    if(EffSessionFilter(cfg, _Symbol))
    {
      const bool sess_on  = EffSessionFilter(cfg, _Symbol);
      const bool in_win   = TimeUtils::InTradingWindow(cfg, TimeCurrent());
      const bool allowed  = (!sess_on || in_win);
      if(!allowed) { reason=GATE_SESSION; return false; }
    }

    if(NewsBlockedNow(cfg, minutes_left_news))
    { reason=GATE_NEWS; return false; }

    double liqR=0.0;
    if(!LiquidityOK(cfg, liqR))
    { reason=GATE_LIQUIDITY; return false; }
    
    if(cfg.debug)
      PrintFormat("Policies | WeeklyOpenRamp=%s", (CfgWeeklyRampOn(cfg) ? "ON" : "OFF"));

    reason=GATE_OK; return true;
  }

  // ---------- Daily counters (symbol + optional magic filter) ----------
  inline void CountTodayTradesAndLosses(const string sym,
                                        const long magic_filter,  // -1 => accept all
                                        int &entries_out,
                                        int &losses_out)
  {
    entries_out = 0;
    losses_out  = 0;

    // Start of broker "today"
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    const datetime day_start = StructToTime(dt);
    const datetime now       = TimeCurrent();

    if(!HistorySelect(day_start, now))
      return;

    const int n = HistoryDealsTotal();
    for(int i=n-1; i>=0; --i)
    {
      const ulong deal = HistoryDealGetTicket(i);
      if(!deal) continue;

      string ds;  HistoryDealGetString (deal, DEAL_SYMBOL, ds);
      if(ds != sym) continue;

      long magic = 0; HistoryDealGetInteger(deal, DEAL_MAGIC, magic);
      if(magic_filter >= 0 && magic != magic_filter) continue;

      const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      const double prof = HistoryDealGetDouble(deal, DEAL_PROFIT);

      // Count entries
      if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
        entries_out++;

      // Count losing exits
      if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT) && prof < 0.0)
        losses_out++;
    }
  }

  // Guarded magic-number accessor (compile-safe)
  inline long _MagicFilterFromCfg(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAGIC_NUMBER
      if(cfg.magic_number > 0) return (long)cfg.magic_number;
    #endif
    return -1; // accept all magics
  }

  inline bool MaxLossesReachedToday(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAX_LOSSES_DAY
      if(cfg.max_losses_day <= 0) return false;
    #else
      if(cfg.max_losses_day <= 0) return false; // fallback if field exists unguarded
    #endif
    int entries=0, losses=0;
    const long mf = _MagicFilterFromCfg(cfg);
    CountTodayTradesAndLosses(_Symbol, mf, entries, losses);
    return (losses >= cfg.max_losses_day);
  }

  inline bool MaxTradesReachedToday(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAX_TRADES_DAY
      if(cfg.max_trades_day <= 0) return false;
    #else
      if(cfg.max_trades_day <= 0) return false;
    #endif
    int entries=0, losses=0;
    const long mf = _MagicFilterFromCfg(cfg);
    CountTodayTradesAndLosses(_Symbol, mf, entries, losses);
    return (entries >= cfg.max_trades_day);
  }

  // ----------------------------------------------------------------------------
  // AllowedByPolicies (legacy ABI) — unified cooldown, no duplicate helpers
  // ----------------------------------------------------------------------------
  inline bool AllowedByPolicies(const Settings &cfg, int &code_out)
  {
    if(cfg.debug)
    {
      // Session gate
      const bool sessOn = Policies::EffSessionFilter(cfg, _Symbol);
      const bool inWin  = TimeUtils::InTradingWindow(cfg, TimeCurrent());
      const bool ok_sess = (!sessOn) || inWin;

      // Daily DD
      double ddPct = 0.0;
      const bool ok_dd = !Policies::DailyEquityDDHit(cfg, ddPct);

      // Day losses
      const bool ok_loss = !Policies::MaxLossesReachedToday(cfg);

      // News
      int mins_left = 0;
      const bool ok_news = !Policies::NewsBlockedNow(cfg, mins_left);

      // Router floor (no Router include to avoid cycles)
      double routerMin =
      #ifdef CFG_HAS_ROUTER_MIN_SCORE
          (cfg.router_min_score>0.0 ? cfg.router_min_score : Const::SCORE_ELIGIBILITY_MIN);
      #else
          Const::SCORE_ELIGIBILITY_MIN;
      #endif

      const double routerScore = -1.0;

      bool   mlEnabled = false;
      double mlScore   = 0.0;
      double mlThresh  =
      #ifdef CFG_HAS_ML_THRESHOLD
          cfg.ml_threshold;
      #else
          0.55;
      #endif
      #ifdef CFG_HAS_ROUTER_MIN_SCORE
         DbgWhyNoTrade(routerScore, routerMin, ok_sess, ok_dd, ok_loss, ok_news,
                       mlEnabled, mlScore, mlThresh);
      #endif
    }

    code_out = POLICY_OK;

    // 1) Session window
    if(EffSessionFilter(cfg, _Symbol))
    {
      TimeUtils::SessionContext sc;
      TimeUtils::BuildSessionContext(cfg, TimeUtils::NowServer(), sc);
      if(!sc.in_window)
      { code_out = POLICY_SESSION_OFF; return false; }
    }

    // 2) News blocks
    if(CfgNewsOn(cfg))
    {
      int mins_left = 0;
      if(News::IsBlocked(TimeUtils::NowServer(), _Symbol,
                         EffNewsImpactMask(cfg, _Symbol),
                         CfgNewsBlockPreMins(cfg), CfgNewsBlockPostMins(cfg),
                         mins_left))
      { code_out = POLICY_NEWS_BLOCK; return false; }
    }

    // 3) Daily limits
    if(MaxLossesReachedToday(cfg)) { code_out = POLICY_MAX_LOSSES; return false; }
    if(MaxTradesReachedToday(cfg)) { code_out = POLICY_MAX_TRADES; return false; }

    // 4) Spread limit (static cap; adaptive used elsewhere)
    const int spr_pts = (int)MathRound(MarketData::SpreadPoints(_Symbol));
    int cap_pts = EffMaxSpreadPts(cfg, _Symbol);          // honor overrides
    if(cap_pts > 0)
    {
      double adj_cap = (double)cap_pts;
      if(CfgWeeklyRampOn(cfg))
        adj_cap = AdjustSpreadCapWeeklyOpenPts(cfg, adj_cap);
      cap_pts = (int)MathFloor(adj_cap);
      if(spr_pts > cap_pts){ code_out = POLICY_SPREAD_HIGH; return false; }
    }

    // 5) Unified cooldown (persisted)
    if(TradeCooldownActive()) { code_out = POLICY_COOLDOWN; return false; }

    return true;
  }

  // Legacy ABI: 3-arg signature; mirrors code_out
  inline bool AllowedByPolicies(const Settings &cfg, int &reason, int &code_out)
  {
    const bool ok = AllowedByPolicies(cfg, code_out);
    reason = code_out;
    return ok;
  }

  // ----------------------------------------------------------------------------
  // HUD / Telemetry snapshot for UI/Logs/Diagnostics
  // ----------------------------------------------------------------------------
  struct Telemetry
  {
    int      gate_reason;
    int      news_mins_left;
    int      cd_trade_sec_left;
    int      cd_loss_sec_left;
    bool     day_stop_latched;
    double   day_loss_money;
    double   day_loss_pct;
    double   day_dd_pct;
    double   day_pl;
    int      day_wins;
    int      day_losses;
    bool     acct_stop_latched;
    double   acct_dd_pct;
    double   acct_dd_limit_pct;
    double   spread_pts;
    int      spread_cap_pts;
    double   atr_short_pts;
    double   atr_long_pts;
    double   vol_ratio;
    double   liq_ratio;
    double   adr_pts;
    int      attempts_today;
    datetime last_attempt_ts;
    uint     last_retcode;
    bool     in_session_window;
    double   adr_cap_limit_pts;
    bool     adr_cap_hit;
  };

   inline void TelemetrySnapshot(const Settings &cfg, Telemetry &t)
  {
    _EnsureLoaded(cfg);
    ZeroMemory(t);

    // Session context for HUD
    t.in_session_window = TimeUtils::InTradingWindow(cfg, TimeCurrent());

    int reason=GATE_OK, mleft=0;
    // run lighter gates for snapshot; don’t mutate anything beyond day stop latch
    Check(cfg, reason);
    t.gate_reason = reason;

    // day PL & stops
    double pl=0.0; int w=0,l=0;
    if(DailyRealizedPL(cfg, pl, w, l)){ t.day_pl = pl; t.day_wins=w; t.day_losses=l; }

    double ddPct=0.0; t.day_dd_pct=0.0;
    if(DailyEquityDDHit(cfg, ddPct)) t.day_dd_pct = ddPct;

    double lossM=0.0, lossPct=0.0;
    t.day_stop_latched = DailyLossStopHit(cfg, lossM, lossPct);
    if(t.day_stop_latched){ t.day_loss_money=lossM; t.day_loss_pct=lossPct; }

    // account-wide (challenge) DD floor
    t.acct_stop_latched = false;
    t.acct_dd_pct       = 0.0;
    t.acct_dd_limit_pct = 0.0;

    double acct_dd=0.0;
    if(AccountEquityDDHit(cfg, acct_dd))
    {
      t.acct_stop_latched = true;
      t.acct_dd_pct       = acct_dd;
    }

    const double acct_lim = CfgMaxAccountDDPct(cfg);
    if(acct_lim > 0.0)
      t.acct_dd_limit_pct = acct_lim;
      
    // cooldowns
    t.cd_trade_sec_left = TradeCooldownSecondsLeft();
    t.cd_loss_sec_left  = LossCooldownSecondsLeft();

    // spreads & ATRs
    t.spread_pts = MarketData::SpreadPoints(_Symbol);
    const double mult = SpreadCapAdaptiveMult(cfg);
    double cap_eff = (double)EffMaxSpreadPts(cfg, _Symbol) * mult;
    if(CfgWeeklyRampOn(cfg))
      cap_eff = AdjustSpreadCapWeeklyOpenPts(cfg, cap_eff);     // weekly ramp
    t.spread_cap_pts = (int)MathFloor(cap_eff);

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    t.atr_short_pts = AtrPts(_Symbol, tf, cfg, CfgATRShort(cfg), 1);
    t.atr_long_pts  = AtrPts(_Symbol, tf, cfg, CfgATRLong(cfg),  1);
    t.vol_ratio     = (t.atr_long_pts>0.0 ? t.atr_short_pts/t.atr_long_pts : 0.0);

    double liqR=0.0; LiquidityOK(cfg, liqR); t.liq_ratio=liqR;

    t.adr_pts = ADRPoints(_Symbol, CfgADRLookbackDays(cfg));
    // --- ADR cap diagnostics ---
    t.adr_cap_limit_pts = 0.0;
    t.adr_cap_hit       = false;
   
    #ifdef CFG_HAS_ADR_CAP_MULT
    {
      const double cap_mult = CfgADRCapMult(cfg);
      if(cap_mult > 0.0 && t.adr_pts > 0.0)
        t.adr_cap_limit_pts = t.adr_pts * cap_mult;     // ADR * multiplier (points)
    }
    #endif
   
    // Use the actual gate function so "hit" matches runtime behavior
    {
      int    adr_reason = GATE_OK;
      double adr_pts_tmp = 0.0; // not used further; gate recomputes safely
      const bool ok = ADRCapOK(cfg, adr_reason, adr_pts_tmp);
      t.adr_cap_hit = (!ok && adr_reason == GATE_ADR);
    }

    // news & attempts
    NewsBlockedNow(cfg, mleft); t.news_mins_left = mleft;
    t.attempts_today = _GVGetI(_Key("ATTEMPTS_D"), 0);
    t.last_attempt_ts= (datetime)_GVGetD(_Key("LAST_ATTEMPT_TS"), 0.0);
    t.last_retcode   = (uint)_GVGetI(_Key("LAST_RC"), 0);
  }

  // ----------------------------------------------------------------------------
  // TradeIntent & signal conflict helpers (compatibility)
  // ----------------------------------------------------------------------------
  struct TradeIntent
  {
    bool        ok;
    string      symbol;
    Direction   dir;
    StrategyID  strat_id;
    string      strat_name;
    double      score;
    double      risk_mult;
    double      entry;
    double      sl;
    double      tp;
    double      lots;
    string      tag;
    StratScore  ss;
    ConfluenceBreakdown bd;
    int         reason;
  };

  inline void ResetIntent(TradeIntent &ti)
  {
    ZeroMemory(ti);
    ti.ok=false; ti.symbol=_Symbol; ti.dir=DIR_BUY; ti.score=0.0; ti.risk_mult=1.0;
    ti.entry=0.0; ti.sl=0.0; ti.tp=0.0; ti.lots=0.0; ti.reason=GATE_OK;
  }

  inline string MakeTag(const string sym, const string strat_name, const Direction d, const double sc)
  {
    return StringFormat("%s|%s|%s|sc=%.3f|%s", sym, strat_name, (d==DIR_BUY?"BUY":"SELL"), sc,
                        TimeToString(TimeCurrent(), TIME_SECONDS));
  }

  inline bool BuildTradeIntentFromPick(const string symbol,
                                       const Settings &cfg,
                                       const StrategyID strat_id,
                                       const string strat_name,
                                       const Direction dir,
                                       const StratScore &in_ss,
                                       const ConfluenceBreakdown &in_bd,
                                       TradeIntent &out_intent,
                                       int &gate_reason)
  {
    _EnsureLoaded(cfg);

    ResetIntent(out_intent);
    out_intent.symbol = symbol;

    SetMoDMultiplier(CfgModSpreadMult(cfg));
    SetSpreadATRAdapt(CfgATRShort(cfg), CfgATRLong(cfg), CfgSpreadAdaptFloor(cfg), CfgSpreadAdaptCeil(cfg));
    SetVolBreakerLimit(CfgVolBreakerLimit(cfg));
    SetLiquidityParams(CfgLiqMinRatio(cfg));
    SetLossCooldownParams(CfgLossCooldownN(cfg), CfgLossCooldownMin(cfg));
    SetTradeCooldownSeconds(CfgTradeCooldownSec(cfg));

    int mins_left=0;
    if(!CheckFull(cfg, gate_reason, mins_left))
    { out_intent.reason=gate_reason; return false; }

    StratScore SS = in_ss; ConfluenceBreakdown BD = in_bd;
    bool skip=false; ApplyNewsScaling(cfg, symbol, SS, BD, skip);
    if(skip){ gate_reason=GATE_NEWS; out_intent.reason=gate_reason; return false; }

    OrderPlan plan; ZeroMemory(plan);
    if(!Risk::ComputeOrder(dir, cfg, SS, plan, BD))
    { gate_reason=GATE_CONFLICT; out_intent.reason=gate_reason; return false; }

    out_intent.ok        = true;
    out_intent.dir       = dir;
    out_intent.strat_id  = strat_id;
    out_intent.strat_name= strat_name;
    out_intent.score     = SS.score;
    out_intent.risk_mult = SS.risk_mult;
    out_intent.entry     = plan.price;
    out_intent.sl        = plan.sl;
    out_intent.tp        = plan.tp;
    out_intent.lots      = plan.lots;
    out_intent.ss        = SS;
    out_intent.bd        = BD;
    out_intent.tag       = MakeTag(symbol, (StringLen(strat_name)>0?strat_name:"strategy"), dir, SS.score);
    out_intent.reason    = GATE_OK;
    return true;
  }

  struct PolicySignal
  {
    StrategyID  id;
    string      name;
    Direction   dir;
    StratScore  ss;
    ConfluenceBreakdown bd;
  };

  inline int SortByScoreDesc(PolicySignal &arr[])
  {
    const int n=ArraySize(arr);
    for(int a=0;a<n;a++)
      for(int b=a+1;b<n;b++)
        if(arr[b].ss.score > arr[a].ss.score){ PolicySignal t=arr[a]; arr[a]=arr[b]; arr[b]=t; }
    return n;
  }

  inline bool ResolveConflict(const PolicySignal &best, const PolicySignal &runner, const double min_gap)
  {
    if(runner.ss.score<=0.0) return true;
    if(best.dir==runner.dir) return true;
    return ((best.ss.score - runner.ss.score) >= (min_gap>0.0?min_gap:0.03));
  }

  inline bool BuildTradeIntentFromSignals(const string symbol,
                                          const Settings &cfg,
                                          PolicySignal &cands[],
                                          const int n,
                                          TradeIntent &out_intent,
                                          int &gate_reason,
                                          const double min_gap=0.03)
  {
    _EnsureLoaded(cfg);

    ResetIntent(out_intent);
    if(n<=0){ gate_reason=GATE_CONFLICT; out_intent.reason=gate_reason; return false; }

    SetMoDMultiplier(CfgModSpreadMult(cfg));
    SetSpreadATRAdapt(CfgATRShort(cfg), CfgATRLong(cfg), CfgSpreadAdaptFloor(cfg), CfgSpreadAdaptCeil(cfg));
    SetVolBreakerLimit(CfgVolBreakerLimit(cfg));
    SetLiquidityParams(CfgLiqMinRatio(cfg));
    SetLossCooldownParams(CfgLossCooldownN(cfg), CfgLossCooldownMin(cfg));
    SetTradeCooldownSeconds(CfgTradeCooldownSec(cfg));

    int mins_left=0;
    if(!CheckFull(cfg, gate_reason, mins_left))
    { out_intent.reason=gate_reason; return false; }

    PolicySignal tmp[]; ArrayResize(tmp, n);
    for(int i=0;i<n;i++) tmp[i]=cands[i];
    SortByScoreDesc(tmp);

    const PolicySignal best   = tmp[0];
    const PolicySignal rival  = (n>1 ? tmp[1] : tmp[0]);
    if(!ResolveConflict(best, rival, min_gap))
    { gate_reason=GATE_CONFLICT; out_intent.reason=gate_reason; return false; }

    return BuildTradeIntentFromPick(symbol, cfg, best.id, best.name, best.dir, best.ss, best.bd, out_intent, gate_reason);
  }

} // namespace Policies

#endif // CA_POLICIES_MQH
