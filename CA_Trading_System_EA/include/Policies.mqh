#ifndef CA_POLICIES_MQH
#define CA_POLICIES_MQH
#property strict

// Make Execution.mqh compile-safe: it checks this macro for persistence hooks.
#define CA_POLICIES_AVAILABLE 1
#ifndef POLICIES_UNIFY_ALLOWED_WITH_CHECKFULL
#define POLICIES_UNIFY_ALLOWED_WITH_CHECKFULL 1
#endif
#ifndef POLICIES_HAS_ALLOW_SILVERBULLET_ENTRY
#define POLICIES_HAS_ALLOW_SILVERBULLET_ENTRY 1
#endif

#ifndef POLICIES_HAS_RECORD_EXECUTION_ATTEMPT_SID
#define POLICIES_HAS_RECORD_EXECUTION_ATTEMPT_SID 1
#endif

#ifndef POLICIES_HAS_RECORD_EXECUTION_RESULT_SID
#define POLICIES_HAS_RECORD_EXECUTION_RESULT_SID 1
#endif
//=============================================================================
// Policies.mqh - Core gates, filters & orchestration (Persistent)
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
#include "ICTSessionModel.mqh"
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

  if(open_min == close_min)   // degenerate: treat as always allowed (or return false if you prefer)
    return true;

  if(close_min > open_min)    // normal window: [open, close)
    return (mm >= open_min && mm < close_min);

  // wrap-around window: e.g., 23:00 to 02:00
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
  POLICY_COOLDOWN      = 6,
  POLICY_MONTH_TARGET  = 7,
  POLICY_SB_NOT_IN_WINDOW = 20,
  POLICY_SB_ALREADY_USED  = 21,
  POLICY_BLOCKED_OTHER = 99
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
    GATE_ACCOUNT_DD = 23,
    GATE_MONTH_TARGET = 24,
    GATE_MAX_LOSSES_DAY = 25,
    GATE_MAX_TRADES_DAY = 26
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
      case GATE_MONTH_TARGET: return "MONTH_TARGET";
      case GATE_MAX_LOSSES_DAY: return "MAX_LOSSES_DAY";
      case GATE_MAX_TRADES_DAY: return "MAX_TRADES_DAY";
      default:              return "UNKNOWN";
    }
  }
  
  inline string GateReasonToString(const int r){ return ReasonString(r); }
  
    // ----------------------------------------------------------------------------
  // Structured policy decision result (single source of truth)
  // ----------------------------------------------------------------------------

  // Bitmask constants (ulong) - stable ordering
  #define CA_POLMASK_DAYLOSS         (((ulong)1) << 0)
  #define CA_POLMASK_DAILYDD         (((ulong)1) << 1)
  #define CA_POLMASK_ACCOUNT_DD      (((ulong)1) << 2)
  #define CA_POLMASK_MONTH_TARGET    (((ulong)1) << 3)
  #define CA_POLMASK_COOLDOWN        (((ulong)1) << 4)
  #define CA_POLMASK_MOD_SPREAD      (((ulong)1) << 5)
  #define CA_POLMASK_SPREAD          (((ulong)1) << 6)
  #define CA_POLMASK_VOLATILITY      (((ulong)1) << 7)
  #define CA_POLMASK_ADR             (((ulong)1) << 8)
  #define CA_POLMASK_CALM            (((ulong)1) << 9)
  #define CA_POLMASK_REGIME          (((ulong)1) << 10)
  #define CA_POLMASK_MAX_LOSSES_DAY  (((ulong)1) << 11)
  #define CA_POLMASK_MAX_TRADES_DAY  (((ulong)1) << 12)
  #define CA_POLMASK_SESSION         (((ulong)1) << 13)
  #define CA_POLMASK_NEWS            (((ulong)1) << 14)
  #define CA_POLMASK_LIQUIDITY       (((ulong)1) << 15)

  struct PolicyResult
  {
    bool   allowed;
    int    primary_reason; // GateReason
    ulong  veto_mask;

    // Common / context
    datetime ts;

    // Spread
    double spread_pts;
    int    spread_cap_pts;
    double spread_adapt_mult;
    bool   weekly_ramp_on;
    double mod_spread_mult;
    int    mod_spread_cap_pts;

    // Session
    bool   session_filter_on;
    bool   in_session_window;

    // News
    bool   news_blocked;
    int    news_mins_left;
    int    news_impact_mask;
    int    news_pre_mins;
    int    news_post_mins;

    // Cooldowns
    int    cd_trade_left_sec;
    int    cd_loss_left_sec;
    int    trade_cd_sec;
    int    loss_cd_min;

    // Daily loss stop
    bool   day_stop_latched;
    double day_loss_money;
    double day_loss_pct;
    double day_loss_cap_money;
    double day_loss_cap_pct;
    double day_eq0;

    // Daily DD
    double day_dd_pct;
    double day_dd_limit_pct;

    // Account DD
    bool   acct_stop_latched;
    double acct_dd_pct;
    double acct_dd_limit_pct;
    double acct_eq0;

    // Monthly target
    bool   month_target_hit;
    double month_profit_pct;
    double month_target_pct;
    double month_eq0;

    // ATR / Volatility
    double atr_short_pts;
    double atr_long_pts;
    double vol_ratio;
    double vol_limit;
    
    // Regime (exact veto values)
    double regime_tq;
    double regime_sg;
    double regime_tq_min;
    double regime_sg_min;

    // ADR cap
    bool   adr_cap_hit;
    double adr_pts;
    double adr_today_range_pts;
    double adr_cap_limit_pts;

    // Calm
    double calm_min_atr_pips;
    double calm_min_atr_pts;
    double calm_min_ratio;
    double calm_atr_to_spread;

    // Liquidity
    double liq_ratio;
    double liq_floor;

    // Daily counters (for veto print precision)
    int    entries_today;
    int    losses_today;
    int    max_trades_day;
    int    max_losses_day;
  };

  inline void _PolicyReset(PolicyResult &r)
  {
    ZeroMemory(r);
    r.allowed        = true;
    r.primary_reason = GATE_OK;
    r.veto_mask      = 0;
    r.ts             = TimeCurrent();
  }

  inline void _PolicyVeto(PolicyResult &r, const int gate_reason, const ulong mask_bit)
  {
    if(r.allowed)
    {
      r.allowed        = false;
      r.primary_reason = gate_reason;
    }
    r.veto_mask |= mask_bit;
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

  inline double CfgMonthlyTargetPct(const Settings &cfg)
  {
    #ifdef CFG_HAS_MONTHLY_TARGET_PCT
      // 0–100 %, 0 => disabled
      return (cfg.monthly_target_pct > 0.0 ? cfg.monthly_target_pct : 0.0);
    #else
      return 0.0; // compile-safe: feature off if not wired in Config.mqh
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
  
  // --- Gate debug (compile-safe) ---------------------------------------------
  inline bool CfgDebugGates(const Settings &cfg)
  {
    #ifdef CFG_HAS_DEBUG_GATES
      return (bool)cfg.debug_gates;
    #else
      return (bool)cfg.debug;   // fallback
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
     #ifdef NEWSFILTER_AVAILABLE
       return (cfg.news_on && (NEWSFILTER_AVAILABLE != 0));
     #else
       return false;
     #endif
   }
   inline int CfgNewsImpactMask(const Settings &cfg)
   {
     const int m = cfg.news_impact_mask;
     if(m != 0) return m;
     return (1<<1) | (1<<2); // MED+HIGH default
   }
   inline int CfgNewsBlockPreMins(const Settings &cfg)
   {
     return (cfg.block_pre_m > 0 ? cfg.block_pre_m : 0);
   }
   
   inline int CfgNewsBlockPostMins(const Settings &cfg)
   {
     return (cfg.block_post_m > 0 ? cfg.block_post_m : 0);
   }
  inline int CfgCalLookbackMins(const Settings &cfg)
   {
     return (cfg.cal_lookback_mins > 0 ? cfg.cal_lookback_mins : 60);
   }
   
   inline double CfgCalHardSkip(const Settings &cfg)
   {
     return (cfg.cal_hard_skip > 0.0 ? cfg.cal_hard_skip : 2.0);
   }
   
   inline double CfgCalSoftKnee(const Settings &cfg)
   {
     return (cfg.cal_soft_knee > 0.0 ? cfg.cal_soft_knee : 0.6);
   }
   
   inline double CfgCalMinScale(const Settings &cfg)
   {
     return (cfg.cal_min_scale > 0.0 ? cfg.cal_min_scale : 0.6);
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
    return (bool)cfg.enable_news_fade;
  }

  // --- Volatility breaker & spread adapt knobs -------------------------------
  inline double CfgVolBreakerLimit(const Settings &cfg)
  {
    #ifdef CFG_HAS_VOL_BREAKER_LIMIT
      // <=0 => disabled
      if(cfg.vol_breaker_limit <= 0.0) return 0.0;
      return Clamp(cfg.vol_breaker_limit, 1.10, 10.0);
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
     // Compile-safe: only touch cfg.minRRFibAllowed if the macro is defined.
     // Fallback default keeps behaviour sensible if the field/macros are absent.
     #ifdef CFG_HAS_FIB_MIN_RR_ALLOWED
       return (cfg.minRRFibAllowed > 0.0 ? cfg.minRRFibAllowed : 1.5);
     #else
       // Default minimum RR for fib-based plays when not explicitly configured.
       return 1.5;
     #endif
   }
   
   inline bool CfgFib_HardReject(const Settings &cfg)
   {
     // Compile-safe: only use hard-reject flag when explicitly enabled in Config.
     #ifdef CFG_HAS_FIB_RR_HARD_REJECT
       return (bool)cfg.fibRRHardReject;
     #else
       // No hard reject when fib RR config is not wired in.
       return false;
     #endif
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
           if(today_pts >= limit_pts)
           {
             reason=GATE_ADR;
             _GateDetail(cfg, reason, _Symbol,
                         StringFormat("adr_pts=%.1f cap_mult=%.3f today_pts=%.1f limit_pts=%.1f",
                                      adr_pts, cap_mult, today_pts, limit_pts));
             return false;
           }
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
  
  // month-level profit target persistence
  static int      s_monthKey        = -1;    // YYYYMM (e.g. 202512)
  static double   s_monthStartEq    = 0.0;   // equity at start of month
  static bool     s_monthTargetHit  = false; // latched once target reached

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

  // --- Silver Bullet (SB) persistent keys (per-symbol / per-day / per-slot) ---
  inline string _SymKey(const string sym)
  {
    string s = sym;
    // Keep GV names safe across brokers (suffixes, dots, etc.)
    StringReplace(s, ".", "_");
    StringReplace(s, "#", "_");
    StringReplace(s, " ", "_");
    StringReplace(s, "-", "_");
    StringReplace(s, "/", "_");
    StringReplace(s, "\\", "_");
    StringReplace(s, ":", "_");
    return s;
  }

  inline string _SBDoneKey(const string symk, const int day, const int slot)
  {
    return _Key(StringFormat("SB_DONE_%s_%d_%d", symk, day, slot));
  }

  inline string _SBLastDayKey(const string symk)  { return _Key("SB_LAST_DAY_"  + symk); }
  inline string _SBLastSlotKey(const string symk) { return _Key("SB_LAST_SLOT_" + symk); }

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
    
    // monthly profit target baseline & latch
    _GVSetD(_Key("MONTH_KEY"),         (double)s_monthKey);
    _GVSetD(_Key("MONTH_EQ0"),         s_monthStartEq);
    _GVSetB(_Key("MONTH_TARGET_HIT"),  s_monthTargetHit);
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
  
  inline void _EnsureMonthState()
  {
    // Compute current month as YYYYMM (e.g. 202512)
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    const int curM = dt.year * 100 + dt.mon;

    int    storedM = _GVGetI(_Key("MONTH_KEY"), -1);
    double eq0     = _GVGetD(_Key("MONTH_EQ0"), 0.0);
    bool   tgtHit  = _GVGetB(_Key("MONTH_TARGET_HIT"), false);

    // If month changed or no valid baseline yet, re-anchor
    if(storedM != curM || eq0 <= 0.0)
    {
      storedM = curM;
      eq0     = AccountInfoDouble(ACCOUNT_EQUITY);
      tgtHit  = false;

      _GVSetD(_Key("MONTH_KEY"),        (double)storedM);
      _GVSetD(_Key("MONTH_EQ0"),        eq0);
      _GVSetB(_Key("MONTH_TARGET_HIT"), tgtHit);
    }

    s_monthKey       = storedM;
    s_monthStartEq   = eq0;
    s_monthTargetHit = tgtHit;
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
    
    // Monthly baseline / latch (YYYYMM)
    // (helper defined in next step)
    _EnsureMonthState();

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

   inline void MonthlyProfitStats(const Settings &cfg,
                                 double &profit_pct_out,
                                 bool   &target_hit_out)
  {
    _EnsureLoaded(cfg);
    _EnsureMonthState();

    profit_pct_out  = 0.0;
    target_hit_out  = false;

    const double eq0 = s_monthStartEq;
    const double eq1 = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq0 <= 0.0 || eq1 <= 0.0)
      return;

    const double profit = (eq1 - eq0);
    profit_pct_out      = 100.0 * profit / eq0;  // 0–100 %

    const double target_pct = CfgMonthlyTargetPct(cfg);
    if(target_pct > 0.0 && profit_pct_out >= target_pct)
    {
      // latch once per month
      s_monthTargetHit = true;
      target_hit_out   = true;

      _GVSetB(_Key("MONTH_TARGET_HIT"), true);
    }
    else
    {
      // if target already latched from earlier run, respect it
      if(_GVGetB(_Key("MONTH_TARGET_HIT"), false))
      {
        s_monthTargetHit = true;
        target_hit_out   = true;
      }
    }
  }
 
  inline bool MonthlyProfitTargetHit(const Settings &cfg, double &profit_pct_out)
  {
    bool hit = false;
    MonthlyProfitStats(cfg, profit_pct_out, hit);
    return hit;
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
        if(tight>0 && (int)sp>tight)
        {
          reason=GATE_MOD_SPREAD;
          _GateDetail(cfg, reason, _Symbol,
                      StringFormat("sp=%.1f tight=%d cap=%d adapt=%.3f eff_cap_pts=%.1f inwin=%s weeklyRamp=%s",
                                   sp, tight, cap, adapt, eff_cap_pts,
                                   (inwin?"YES":"NO"), (CfgWeeklyRampOn(cfg)?"ON":"OFF")));
          return false;
        }
      }
    }

    if((int)sp>cap)
    {
      reason=GATE_SPREAD;
      _GateDetail(cfg, reason, _Symbol,
                  StringFormat("sp=%.1f cap=%d adapt=%.3f eff_cap_pts=%.1f weeklyRamp=%s",
                               sp, cap, adapt, eff_cap_pts, (CfgWeeklyRampOn(cfg)?"ON":"OFF")));
      return false;
    }
    return true;
  }

  // ----------------------------------------------------------------------------
  // Volatility breaker (re-uses short/long ATR config)
  // ----------------------------------------------------------------------------
  static double s_vb_limit = 2.50;
  inline void SetVolBreakerLimit(const double limit)
  {
    if(limit <= 0.0){ s_vb_limit = 0.0; return; }   // disabled
    s_vb_limit = (limit < 1.10 ? 1.10 : limit);
  }

  inline bool VolatilityBreaker(const Settings &cfg, double &ratio_out)
  {
    _EnsureLoaded(cfg);

    if(s_vb_limit <= 0.0) return false; // disabled
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
      if(minPts>0.0 && atr_s<minPts)
      {
        reason=GATE_CALM;
        _GateDetail(cfg, reason, _Symbol,
                    StringFormat("atr_s_pts=%.1f minAtrPips=%.2f minPts=%.1f",
                                 atr_s, minAtrPips, minPts));
        return false;
      }
    }

    const double minRatio = CfgCalmMinATRtoSpread(cfg);
    if(minRatio>0.0)
    {
      const double spr = MarketData::SpreadPoints(sym);
      if(spr>0.0 && atr_s/spr < minRatio)
      {
        reason=GATE_CALM;
        _GateDetail(cfg, reason, _Symbol,
                    StringFormat("atr_s_pts=%.1f spr_pts=%.1f ratio=%.3f minRatio=%.3f",
                                 atr_s, spr, (spr>0.0?atr_s/spr:0.0), minRatio));
        return false;
      }
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

  // ----------------------------------------------------------------------------
  // Gate debug logger (throttled): prints only when CfgDebugGates(cfg) is true
  // ----------------------------------------------------------------------------
  inline bool _ShouldGateLog(const Settings &cfg, const int reason)
  {
    if(!CfgDebugGates(cfg)) return false;
    static datetime last_ts = 0;
    static int      last_reason = -999;
    const datetime now = TimeCurrent();
    if(now==last_ts && reason==last_reason) return false;
    last_ts = now; last_reason = reason;
    return true;
  }

  inline void _GateDetail(const Settings &cfg,
                          const int reason,
                          const string sym,
                          const string msg)
  {
    if(!_ShouldGateLog(cfg, reason)) return;
    PrintFormat("[GateDetail] %s reason=%d (%s) %s",
                sym, reason, GateReasonToString(reason), msg);
  }
  
  // ----------------------------------------------------------------------------
  // Guaranteed veto logger (NOT debug-gated) — prevents silent vetoing.
  // Throttles identical veto spam to once per second per (reason+mask).
  // ----------------------------------------------------------------------------
  inline bool _ShouldVetoLogOncePerSec(const string sym, const int reason, const ulong mask)
  {
    static datetime s_last_ts    = 0;
    static int      s_last_reason= -999;
    static ulong    s_last_mask  = 0;
    static string   s_last_sym   = "";

    const datetime now = TimeCurrent();
    if(sym == s_last_sym && reason == s_last_reason && mask == s_last_mask && (now - s_last_ts) < 1)
      return false;

    s_last_ts     = now;
    s_last_reason = reason;
    s_last_mask   = mask;
    s_last_sym    = sym;
    return true;
  }

  inline void PolicyVetoLog(const PolicyResult &r)
   {
     const string sym = _Symbol;
   
     if(_ShouldVetoLogOncePerSec(sym, r.primary_reason, r.veto_mask) == false)
       return;

    // Gate-specific “exact values” prints
    switch(r.primary_reason)
    {
      case GATE_SPREAD:
      case GATE_MOD_SPREAD:
        Print("[Policy][VETO] reason=", GateReasonToString(r.primary_reason),
              " sym=", sym,
              " spread=", DoubleToString(r.spread_pts,1),
              " cap=", (string)r.spread_cap_pts,
              " adapt=", DoubleToString(r.spread_adapt_mult,3),
              " modMult=", DoubleToString(r.mod_spread_mult,3),
              " modCap=", (string)r.mod_spread_cap_pts,
              " inSession=", (r.in_session_window?"1":"0"),
              " weeklyRamp=", (r.weekly_ramp_on?"1":"0"),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_NEWS:
        Print("[Policy][VETO] reason=NEWS sym=", sym,
              " block=", (r.news_blocked?"1":"0"),
              " minutes=", (string)r.news_mins_left,
              " impactMask=", (string)r.news_impact_mask,
              " pre=", (string)r.news_pre_mins,
              " post=", (string)r.news_post_mins,
              " mask=", (string)r.veto_mask);
        break;

      case GATE_SESSION:
        Print("[Policy][VETO] reason=SESSION sym=", sym,
              " sessionFilter=", (r.session_filter_on?"1":"0"),
              " inWindow=", (r.in_session_window?"1":"0"),
              " server=", TimeToString(TimeCurrent(), TIME_SECONDS),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_COOLDOWN:
        Print("[Policy][VETO] reason=COOLDOWN sym=", sym,
              " trade_left_sec=", (string)r.cd_trade_left_sec,
              " loss_left_sec=", (string)r.cd_loss_left_sec,
              " trade_cd_sec=", (string)r.trade_cd_sec,
              " loss_cd_min=", (string)r.loss_cd_min,
              " mask=", (string)r.veto_mask);
        break;

      case GATE_DAILYDD:
        Print("[Policy][VETO] reason=DAILY_DD sym=", sym,
              " dd_pct=", DoubleToString(r.day_dd_pct,3),
              " limit=", DoubleToString(r.day_dd_limit_pct,3),
              " dayEq0=", DoubleToString(r.day_eq0,2),
              " eq=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_DAYLOSS:
        Print("[Policy][VETO] reason=DAY_LOSS_STOP sym=", sym,
              " loss_money=", DoubleToString(r.day_loss_money,2),
              " loss_pct=", DoubleToString(r.day_loss_pct,3),
              " cap_money=", DoubleToString(r.day_loss_cap_money,2),
              " cap_pct=", DoubleToString(r.day_loss_cap_pct,3),
              " dayEq0=", DoubleToString(r.day_eq0,2),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_ACCOUNT_DD:
        Print("[Policy][VETO] reason=ACCOUNT_DD_FLOOR sym=", sym,
              " dd_pct=", DoubleToString(r.acct_dd_pct,3),
              " limit=", DoubleToString(r.acct_dd_limit_pct,3),
              " acctEq0=", DoubleToString(r.acct_eq0,2),
              " eq=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
              " latched=", (r.acct_stop_latched?"1":"0"),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MONTH_TARGET:
        Print("[Policy][VETO] reason=MONTH_TARGET sym=", sym,
              " month_pct=", DoubleToString(r.month_profit_pct,3),
              " target=", DoubleToString(r.month_target_pct,3),
              " monthEq0=", DoubleToString(r.month_eq0,2),
              " eq=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
              " latched=", (r.month_target_hit?"1":"0"),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_VOLATILITY:
        Print("[Policy][VETO] reason=VOLATILITY_BREAKER sym=", sym,
              " atr_s=", DoubleToString(r.atr_short_pts,1),
              " atr_l=", DoubleToString(r.atr_long_pts,1),
              " ratio=", DoubleToString(r.vol_ratio,3),
              " limit=", DoubleToString(r.vol_limit,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_ADR:
        Print("[Policy][VETO] reason=ADR_CAP sym=", sym,
              " adr_pts=", DoubleToString(r.adr_pts,1),
              " today_pts=", DoubleToString(r.adr_today_range_pts,1),
              " limit_pts=", DoubleToString(r.adr_cap_limit_pts,1),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_CALM:
        Print("[Policy][VETO] reason=CALM sym=", sym,
              " atr_s=", DoubleToString(r.atr_short_pts,1),
              " spread=", DoubleToString(r.spread_pts,1),
              " atr_to_spread=", DoubleToString(r.calm_atr_to_spread,3),
              " min_atr_pips=", DoubleToString(r.calm_min_atr_pips,2),
              " min_atr_pts=", DoubleToString(r.calm_min_atr_pts,1),
              " min_ratio=", DoubleToString(r.calm_min_ratio,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_LIQUIDITY:
        Print("[Policy][VETO] reason=LIQUIDITY sym=", sym,
              " ratio=", DoubleToString(r.liq_ratio,3),
              " floor=", DoubleToString(r.liq_floor,3),
              " atr_s=", DoubleToString(r.atr_short_pts,1),
              " spread=", DoubleToString(r.spread_pts,1),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MAX_LOSSES_DAY:
        Print("[Policy][VETO] reason=MAX_LOSSES_DAY sym=", sym,
              " losses=", (string)r.losses_today,
              " max=", (string)r.max_losses_day,
              " entries=", (string)r.entries_today,
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MAX_TRADES_DAY:
        Print("[Policy][VETO] reason=MAX_TRADES_DAY sym=", sym,
              " entries=", (string)r.entries_today,
              " max=", (string)r.max_trades_day,
              " losses=", (string)r.losses_today,
              " mask=", (string)r.veto_mask);
        break;

      case GATE_REGIME:
        Print("[Policy][VETO] reason=REGIME sym=", sym,
              " tq=", DoubleToString(r.regime_tq,3),
              " sg=", DoubleToString(r.regime_sg,3),
              " tq_min=", DoubleToString(r.regime_tq_min,3),
              " sg_min=", DoubleToString(r.regime_sg_min,3),
              " mask=", (string)r.veto_mask);
        break;
        
      default:
        Print("[Policy][VETO] reason=", GateReasonToString(r.primary_reason),
              " sym=", sym, " mask=", (string)r.veto_mask);
        break;
    }
  }

    // ----------------------------------------------------------------------------
  // Unified evaluators (Fast + Audit)
  // ----------------------------------------------------------------------------

  inline void _ApplyRuntimeKnobsFromCfg(const Settings &cfg)
  {
    SetMoDMultiplier       (CfgModSpreadMult(cfg));
    SetSpreadATRAdapt      (CfgATRShort(cfg), CfgATRLong(cfg),
                            CfgSpreadAdaptFloor(cfg), CfgSpreadAdaptCeil(cfg));
    SetVolBreakerLimit     (CfgVolBreakerLimit(cfg));
    SetLiquidityParams     (CfgLiqMinRatio(cfg));
    SetLossCooldownParams  (CfgLossCooldownN(cfg), CfgLossCooldownMin(cfg));
    SetTradeCooldownSeconds(CfgTradeCooldownSec(cfg));
  }

  inline void _FillSpreadDiag(const Settings &cfg, PolicyResult &r)
  {
    r.weekly_ramp_on     = CfgWeeklyRampOn(cfg);
    r.mod_spread_mult    = s_mod_mult_outside;

    const int cap_base   = EffMaxSpreadPts(cfg, _Symbol);
    const double adapt   = SpreadCapAdaptiveMult(cfg);
    r.spread_adapt_mult  = adapt;

    double cap_eff = (double)cap_base * adapt;
    if(r.weekly_ramp_on)
      cap_eff = AdjustSpreadCapWeeklyOpenPts(cfg, cap_eff);

    r.spread_cap_pts     = (int)MathFloor(cap_eff);
    r.mod_spread_cap_pts = (int)MathFloor(r.mod_spread_mult * (double)r.spread_cap_pts);
    r.spread_pts         = MarketData::SpreadPoints(_Symbol);
  }

  inline void _FillATRDiag(const Settings &cfg, PolicyResult &r)
  {
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    r.atr_short_pts = AtrPts(_Symbol, tf, cfg, CfgATRShort(cfg), 1);
    r.atr_long_pts  = AtrPts(_Symbol, tf, cfg, CfgATRLong(cfg),  1);
    r.vol_ratio     = (r.atr_long_pts > 0.0 ? (r.atr_short_pts / r.atr_long_pts) : 0.0);
    r.vol_limit     = s_vb_limit;
  }

  inline void _FillADRCapDiag(const Settings &cfg, PolicyResult &r)
  {
    r.adr_cap_hit = false;
    r.adr_pts     = ADRPoints(_Symbol, CfgADRLookbackDays(cfg));

    r.adr_today_range_pts = 0.0;
    r.adr_cap_limit_pts   = 0.0;

    #ifdef CFG_HAS_ADR_CAP_MULT
    const double cap_mult = CfgADRCapMult(cfg);
    if(cap_mult > 0.0 && r.adr_pts > 0.0)
    {
      r.adr_cap_limit_pts = r.adr_pts * cap_mult;

      MqlRates d1[]; ArraySetAsSeries(d1,true);
      if(CopyRates(_Symbol, PERIOD_D1, 0, 1, d1) == 1)
      {
        double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        if(pt <= 0.0) pt = _Point;
        if(pt > 0.0)
          r.adr_today_range_pts = MathAbs(d1[0].high - d1[0].low) / pt;
      }
    }
    #endif
  }

  inline void _FillCalmDiag(const Settings &cfg, PolicyResult &r)
  {
    r.calm_min_atr_pips    = CfgCalmMinATRPips(cfg);
    r.calm_min_ratio       = CfgCalmMinATRtoSpread(cfg);
    r.calm_min_atr_pts     = 0.0;

    const string sym=_Symbol;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    r.atr_short_pts = AtrPts(sym, tf, cfg, CfgATRShort(cfg), 1);
    r.spread_pts    = MarketData::SpreadPoints(sym);

    if(r.calm_min_atr_pips > 0.0)
      r.calm_min_atr_pts = MarketData::PointsFromPips(sym, r.calm_min_atr_pips);

    r.calm_atr_to_spread = (r.spread_pts > 0.0 ? r.atr_short_pts / r.spread_pts : 0.0);
  }

  inline void _FillLiquidityDiag(const Settings &cfg, PolicyResult &r)
  {
    _FillATRDiag(cfg, r); // ensures atr_short_pts available
    r.spread_pts = MarketData::SpreadPoints(_Symbol);

    const double floorR = EffLiqMinRatio(cfg, _Symbol, s_liq_min_ratio);
    r.liq_floor  = floorR;

    if(r.spread_pts > 0.0)
      r.liq_ratio = (r.atr_short_pts / r.spread_pts);
    else
      r.liq_ratio = 0.0;
  }

  inline bool _EvaluateCoreEx(const Settings &cfg, PolicyResult &out, const bool audit)
  {
    _EnsureLoaded(cfg);
    _EnsureMonthState();
    _EnsureDayState();
    _EnsureAccountBaseline(cfg);

    _PolicyReset(out);
    _ApplyRuntimeKnobsFromCfg(cfg);

    out.session_filter_on = EffSessionFilter(cfg, _Symbol);
    out.in_session_window = TimeUtils::InTradingWindow(cfg, TimeCurrent());

    out.trade_cd_sec      = s_trade_cd_sec;
    out.loss_cd_min       = s_cooldown_min;
    out.cd_trade_left_sec = TradeCooldownSecondsLeft();
    out.cd_loss_left_sec  = LossCooldownSecondsLeft();

    out.day_eq0           = s_dayEqStart;
    out.day_dd_limit_pct  = CfgMaxDailyDDPct(cfg);

    out.acct_eq0          = s_acctEqStart;
    out.acct_dd_limit_pct = CfgMaxAccountDDPct(cfg);

    out.month_eq0         = s_monthStartEq;
    out.month_target_pct  = CfgMonthlyTargetPct(cfg);

    // 1) Realised day-loss stop
    {
      double loss_money=0.0, loss_pct=0.0;
      if(DailyLossStopHit(cfg, loss_money, loss_pct))
      {
        out.day_stop_latched  = true;
        out.day_loss_money    = loss_money;
        out.day_loss_pct      = loss_pct;
        out.day_loss_cap_money= CfgDayLossCapMoney(cfg);

        double cap_pct = CfgDayLossCapPct(cfg);
        const double dd_cap = CfgMaxDailyDDPct(cfg);
        if(cap_pct <= 0.0) cap_pct = dd_cap;
        else if(dd_cap > 0.0) cap_pct = MathMax(cap_pct, dd_cap);
        out.day_loss_cap_pct = cap_pct;

        _PolicyVeto(out, GATE_DAYLOSS, CA_POLMASK_DAYLOSS);
        if(!audit) return false;
      }
    }

    // 2) Daily equity DD
    {
      double dd_pct=0.0;
      if(DailyEquityDDHit(cfg, dd_pct))
      {
        out.day_dd_pct = dd_pct;
        _PolicyVeto(out, GATE_DAILYDD, CA_POLMASK_DAILYDD);
        if(!audit) return false;
      }
    }

    // 3) Account DD floor
    {
      double acct_dd=0.0;
      if(AccountEquityDDHit(cfg, acct_dd))
      {
        out.acct_stop_latched = true;
        out.acct_dd_pct       = acct_dd;
        _PolicyVeto(out, GATE_ACCOUNT_DD, CA_POLMASK_ACCOUNT_DD);
        if(!audit) return false;
      }
    }

    // 4) Monthly target
    {
      double month_pct=0.0;
      if(MonthlyProfitTargetHit(cfg, month_pct))
      {
        out.month_target_hit = true;
        out.month_profit_pct = month_pct;
        _PolicyVeto(out, GATE_MONTH_TARGET, CA_POLMASK_MONTH_TARGET);
        if(!audit) return false;
      }
    }

    // 5) Cooldowns
    if(LossCooldownActive() || TradeCooldownActive())
    {
      out.cd_trade_left_sec = TradeCooldownSecondsLeft();
      out.cd_loss_left_sec  = LossCooldownSecondsLeft();
      _PolicyVeto(out, GATE_COOLDOWN, CA_POLMASK_COOLDOWN);
      if(!audit) return false;
    }

    // 6) Spread / MoD spread
    {
      int spread_reason=GATE_OK;
      if(!MoDSpreadOK(cfg, spread_reason))
      {
        _FillSpreadDiag(cfg, out);
        if(spread_reason == GATE_MOD_SPREAD)
          _PolicyVeto(out, GATE_MOD_SPREAD, CA_POLMASK_MOD_SPREAD);
        else
          _PolicyVeto(out, GATE_SPREAD, CA_POLMASK_SPREAD);

        if(!audit) return false;
      }
    }

    // 7) London-local liquidity policy tweak (kept identical to your Check())
    #ifdef CFG_HAS_LONDON_LIQ_POLICY
    #ifdef CFG_HAS_LONDON_LOCAL_MINUTES
    {
      const bool in_lon =
          _WithinLocalWindowMins(cfg.london_local_open_min,
                                 cfg.london_local_close_min,
                                 TimeLocal());

      if(cfg.london_liquidity_policy)
      {
        const double base = CfgLiqMinRatio(cfg);
        const double mult = (in_lon ? 0.95 : 1.05);
        SetLiquidityParams(base * mult);
      }
    }
    #endif
    #endif

    // 8) Volatility breaker
    {
      double vb_ratio=0.0;
      if(VolatilityBreaker(cfg, vb_ratio))
      {
        _FillATRDiag(cfg, out);
        out.vol_ratio = vb_ratio;
        _PolicyVeto(out, GATE_VOLATILITY, CA_POLMASK_VOLATILITY);
        if(!audit) return false;
      }
    }

    // 9) ADR cap
    {
      double adr_pts=0.0; int adr_reason=GATE_OK;
      if(!ADRCapOK(cfg, adr_reason, adr_pts))
      {
        _FillADRCapDiag(cfg, out);
        out.adr_cap_hit = true;
        _PolicyVeto(out, GATE_ADR, CA_POLMASK_ADR);
        if(!audit) return false;
      }
    }

    // 10) Calm
    {
      int calm_reason=GATE_OK;
      if(!CalmModeOK(cfg, calm_reason))
      {
        _FillCalmDiag(cfg, out);
        _PolicyVeto(out, GATE_CALM, CA_POLMASK_CALM);
        if(!audit) return false;
      }
    }

    // 11) Regime
    EnableRegimeGate(CfgRegimeGateOn(cfg));
    SetRegimeThresholds(CfgRegimeTQMin(cfg), CfgRegimeSGMin(cfg));
    if(!RegimeConsensusOK(cfg))
    {
      // Capture exact values for guaranteed veto logs (NOT debug gated)
      out.regime_tq_min = s_reg_tq_min;
      out.regime_sg_min = s_reg_sg_min;

      const string sym=_Symbol;
      const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
      out.regime_tq = RegimeX::TrendQuality(sym, tf, 60);
      out.regime_sg = Corr::HysteresisSlopeGuard(sym, tf, 14, 23.0, 15.0);

      _PolicyVeto(out, GATE_REGIME, CA_POLMASK_REGIME);
      if(!audit) return false;
    }

    return out.allowed;
  }

  inline bool _EvaluateFullEx(const Settings &cfg, PolicyResult &out, const bool audit)
  {
    const bool ok_core = _EvaluateCoreEx(cfg, out, audit);
    if(!audit && !ok_core) return false;

    // A) Day max-losses
    if(MaxLossesReachedToday(cfg))
    {
      out.max_losses_day = 0;
      out.entries_today  = 0;
      out.losses_today   = 0;

      #ifdef CFG_HAS_MAX_LOSSES_DAY
        out.max_losses_day = cfg.max_losses_day;
        int entries=0, losses=0;
        const long mf = _MagicFilterFromCfg(cfg);
        CountTodayTradesAndLosses(_Symbol, mf, entries, losses);
        out.entries_today = entries;
        out.losses_today  = losses;
      #endif

      _PolicyVeto(out, GATE_MAX_LOSSES_DAY, CA_POLMASK_MAX_LOSSES_DAY);
      if(!audit) return false;
    }

    // B) Day max-trades
    if(MaxTradesReachedToday(cfg))
    {
      out.max_trades_day = 0;
      out.entries_today  = 0;
      out.losses_today   = 0;

      #ifdef CFG_HAS_MAX_TRADES_DAY
        out.max_trades_day = cfg.max_trades_day;
        int entries=0, losses=0;
        const long mf = _MagicFilterFromCfg(cfg);
        CountTodayTradesAndLosses(_Symbol, mf, entries, losses);
        out.entries_today = entries;
        out.losses_today  = losses;
      #endif

      _PolicyVeto(out, GATE_MAX_TRADES_DAY, CA_POLMASK_MAX_TRADES_DAY);
      if(!audit) return false;
    }

    // C) Session veto (full)
    if(out.session_filter_on && !out.in_session_window)
    {
      _PolicyVeto(out, GATE_SESSION, CA_POLMASK_SESSION);
      if(!audit) return false;
    }

    // D) News veto
    out.news_blocked     = false;
    out.news_mins_left   = 0;
    out.news_impact_mask = EffNewsImpactMask(cfg, _Symbol);
    out.news_pre_mins    = CfgNewsBlockPreMins(cfg);
    out.news_post_mins   = CfgNewsBlockPostMins(cfg);

    {
      int mins_left=0;
      if(NewsBlockedNow(cfg, mins_left))
      {
        out.news_blocked   = true;
        out.news_mins_left = mins_left;
        _PolicyVeto(out, GATE_NEWS, CA_POLMASK_NEWS);
        if(!audit) return false;
      }
    }

    // E) Liquidity veto
    {
      double liqR=0.0;
      if(!LiquidityOK(cfg, liqR))
      {
        _FillLiquidityDiag(cfg, out);
        out.liq_ratio = liqR;
        _PolicyVeto(out, GATE_LIQUIDITY, CA_POLMASK_LIQUIDITY);
        if(!audit) return false;
      }
    }

    return out.allowed;
  }

  // Public API
  inline bool EvaluateCore(const Settings &cfg, PolicyResult &out)      { return _EvaluateCoreEx(cfg, out, false); }
  inline bool EvaluateCoreAudit(const Settings &cfg, PolicyResult &out) { return _EvaluateCoreEx(cfg, out, true);  }
  inline bool EvaluateFull(const Settings &cfg, PolicyResult &out)      { return _EvaluateFullEx(cfg, out, false); }
  inline bool EvaluateFullAudit(const Settings &cfg, PolicyResult &out) { return _EvaluateFullEx(cfg, out, true);  }
  inline bool CheckFull(const Settings &cfg, int &reason, int &minutes_left_news);

  // ---------------------------------------------------------------------------
  // Central gate used by Execution.mqh  → Policies::Check(cfg, reason)
  // ---------------------------------------------------------------------------
  inline bool Check(const Settings &cfg, int &reason)
  {
    int mins_left_news = 0;
    return CheckFull(cfg, reason, mins_left_news);
  }

  // --- Hooks expected by Execution.mqh ---
  inline void TouchTradeCooldown(){ NotifyTradePlaced(); }
  
    // --- Silver Bullet: centralized "one bullet" gate --------------------------
  inline bool AllowSilverBulletEntry(const Settings &cfg,
                                    const string sym,
                                    const StrategyID sid,
                                    int &reason_out,
                                    string &text_out)
  {
    reason_out = POLICY_OK;
    text_out   = "";

    if((int)sid != (int)STRAT_ICT_SILVER_BULLET_ID)
      return true;

    _EnsureLoaded(cfg);

    datetime now = TimeTradeServer();
    if(now <= 0) now = TimeCurrent();

    _ICTSessionWindows win;
    ZeroMemory(win);
    ICTSession_BuildWindowsFromSettings(cfg, win);

    _ICTSilverBulletInfo sb;
    ZeroMemory(sb);
    ICTSession_GetSilverBulletInfo(now, win, sb);

    if(!sb.inSilverBullet)
    {
      reason_out = POLICY_SB_NOT_IN_WINDOW;
      text_out   = "Not in Silver Bullet window";
      return false;
    }

    const datetime ws = sb.windowStart;
    const int day     = EpochDay(ws > 0 ? ws : now);
    MqlDateTime dt; 
    TimeToStruct(ws, dt);
    const int slot = (sb.sbSlot >= 0 ? sb.sbSlot : dt.hour);

    if(slot < 0)
    {
      reason_out = POLICY_BLOCKED_OTHER;
      text_out   = "SB slot invalid";
      return false;
    }

    const string symk = _SymKey(sym);

    if(_GVGetB(_SBDoneKey(symk, day, slot), false))
    {
      reason_out = POLICY_SB_ALREADY_USED;
      text_out   = "Silver Bullet already used for this window";
      return false;
    }

    // Store last SB window identity for this symbol so we can mark-used on success
    _GVSetD(_SBLastDayKey(symk),  (double)day);
    _GVSetD(_SBLastSlotKey(symk), (double)slot);

    return true;
  }

    inline void MarkSilverBulletUsed(const Settings &cfg,
                                  const string sym,
                                  const StrategyID sid)
  {
    if((int)sid != (int)STRAT_ICT_SILVER_BULLET_ID)
      return;

    _EnsureLoaded(cfg);

    const string symk = _SymKey(sym);
    const int day  = _GVGetI(_SBLastDayKey(symk),  -1);
    const int slot = _GVGetI(_SBLastSlotKey(symk), -1);
    if(day < 0 || slot < 0) return;

    _GVSetB(_SBDoneKey(symk, day, slot), true);
  }

  inline void RecordExecutionAttempt(const StrategyID sid)
  {
    _GVSetD(_Key("LAST_ATTEMPT_TS"), (double)TimeCurrent());
    _GVSetD(_Key("LAST_ATTEMPT_SID"), (double)((int)sid));

    // Optional: simple per-day attempts counter for telemetry
    int        cnt  = _GVGetI(_Key("ATTEMPTS_D"), 0);
    const int  curD = EpochDay(TimeCurrent());
    const int  dGV  = _GVGetI(_Key("ATTEMPTS_D_DAY"), -1);

    if(dGV != curD)
    {
      // New day → reset counter and day key
      _GVSetD(_Key("ATTEMPTS_D_DAY"), (double)curD);
      cnt = 0;
    }

    cnt++;
    _GVSetD(_Key("ATTEMPTS_D"), (double)cnt);
  }

  inline void RecordExecutionAttempt()
  {
    RecordExecutionAttempt((StrategyID)0);
  }
  
  inline void RecordExecutionResult(const StrategyID sid, const bool ok, const uint retcode, const double filled_volume)
  {
    // If Policies::Init(...) was never called, s_prefix may be empty.
    // In that case we still work, but the keys are shared per-login.
    _GVSetD(_Key("LAST_EXEC_SID"), (double)((int)sid));
    const datetime now = TimeCurrent();

    // Basic last-result telemetry
    if(StringLen(s_prefix)>0)
    {
      _GVSetB(_Key("LAST_EXEC_OK"),      ok);
      _GVSetD(_Key("LAST_EXEC_RC"),      (double)retcode);
      _GVSetD(_Key("LAST_RC"),           (double)retcode);
      _GVSetD(_Key("LAST_EXEC_FILLED"),  filled_volume);
      _GVSetD(_Key("LAST_EXEC_TS"),      (double)now);
    }

    // Per-day success/fail counters (for HUD / diagnostics)
    const int curD   = EpochDay(now);
    const int d_tr   = _GVGetI(_Key("TRADES_D_DAY"), -1);
    int       succ_d = _GVGetI(_Key("SUCC_TRADES_D"), 0);
    int       fail_d = _GVGetI(_Key("FAIL_TRADES_D"), 0);

    if(d_tr!=curD)
    {
      // New day → reset counters
      succ_d = 0;
      fail_d = 0;
      _GVSetD(_Key("TRADES_D_DAY"), (double)curD);
    }

    if(ok) succ_d++; else fail_d++;

    _GVSetD(_Key("SUCC_TRADES_D"), (double)succ_d);
    _GVSetD(_Key("FAIL_TRADES_D"), (double)fail_d);
  }

  inline void RecordExecutionResult(const bool ok, const uint retcode, const double filled_volume)
  {
    RecordExecutionResult((StrategyID)0, ok, retcode, filled_volume);
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
    const bool ok = (tq>=s_reg_tq_min) || (sg>=s_reg_sg_min);
    if(!ok)
      _GateDetail(cfg, GATE_REGIME, _Symbol,
                  StringFormat("tq=%.3f sg=%.3f tq_min=%.3f sg_min=%.3f",
                               tq, sg, s_reg_tq_min, s_reg_sg_min));
    return ok;
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
    const bool ok = (ratio_out >= floorR);
    if(!ok)
      _GateDetail(cfg, GATE_LIQUIDITY, sym,
                  StringFormat("atr_s_pts=%.1f spr_pts=%.1f ratio=%.3f floor=%.3f",
                               atr_s, spr, ratio_out, floorR));
    return ok;
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
       if(false) { Print(sym); Print(bd.score_final); }
     #endif
   }

  // ----------------------------------------------------------------------------
  // Core gates: Check / CheckFull / AllowedByPolicies
  // ----------------------------------------------------------------------------
  inline bool CheckFull(const Settings &cfg, int &reason, int &minutes_left_news)
  {
    minutes_left_news = 0;

    if(CfgDebugGates(cfg))
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

    PolicyResult r;
    const bool ok = EvaluateFull(cfg, r);

    reason = r.primary_reason;
    minutes_left_news = r.news_mins_left;

    if(!ok) PolicyVetoLog(r);
    return ok;
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
      // Config field is compiled in and guarded → safe to use.
      if(cfg.max_losses_day <= 0)
        return false;

      int entries = 0;
      int losses  = 0;
      const long mf = _MagicFilterFromCfg(cfg);
      CountTodayTradesAndLosses(_Symbol, mf, entries, losses);
      return (losses >= cfg.max_losses_day);
    #else
      // Field not compiled in → no daily losses cap.
      return false;
    #endif
  }

  inline bool MaxTradesReachedToday(const Settings &cfg)
  {
    #ifdef CFG_HAS_MAX_TRADES_DAY
      // Config field is compiled in and guarded → safe to use.
      if(cfg.max_trades_day <= 0)
        return false;

      int entries = 0;
      int losses  = 0;
      const long mf = _MagicFilterFromCfg(cfg);
      CountTodayTradesAndLosses(_Symbol, mf, entries, losses);
      return (entries >= cfg.max_trades_day);
    #else
      // Field not compiled in → no daily trade-count cap.
      if(false) Print((long)CfgMagicNumber(cfg));
      return false;
    #endif
  }

  // ----------------------------------------------------------------------------
  // AllowedByPolicies (legacy ABI) — unified cooldown, no duplicate helpers
  // ----------------------------------------------------------------------------
  inline bool AllowedByPolicies(const Settings &cfg, int &code_out)
  {
    #ifdef POLICIES_UNIFY_ALLOWED_WITH_CHECKFULL
      int gr=GATE_OK, mins=0;
      if(!CheckFull(cfg, gr, mins))
      {
        // Map gate reason to legacy policy codes (best-effort)
        if(gr==GATE_SESSION)      { code_out = POLICY_SESSION_OFF; return false; }
        if(gr==GATE_NEWS)         { code_out = POLICY_NEWS_BLOCK;  return false; }
        if(gr==GATE_COOLDOWN)     { code_out = POLICY_COOLDOWN;    return false; }
        if(gr==GATE_MONTH_TARGET) { code_out = POLICY_MONTH_TARGET;return false; }
        if(gr==GATE_SPREAD || gr==GATE_MOD_SPREAD)
                                { code_out = POLICY_SPREAD_HIGH;  return false; }

        // Max losses vs max trades are both GATE_MAX_LOSSES_DAY & GATE_MAX_TRADES_DAY in CheckFull; disambiguate cheaply:
        if(gr==GATE_MAX_LOSSES_DAY) { code_out = POLICY_MAX_LOSSES; return false; }
        if(gr==GATE_MAX_TRADES_DAY) { code_out = POLICY_MAX_TRADES; return false; }

        // True day-loss stop is not “max losses” — treat as generic block in legacy ABI
        if(gr==GATE_DAYLOSS)        { code_out = POLICY_BLOCKED_OTHER; return false; }

        code_out = POLICY_BLOCKED_OTHER;
        return false;
      }
      code_out = POLICY_OK;
      return true;
    #else
    
    if(CfgDebugGates(cfg))
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
    #endif

    _EnsureLoaded(cfg);
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
      if(NewsBlockedNow(cfg, mins_left))
      { code_out = POLICY_NEWS_BLOCK; return false; }
    }

    // 3) Daily limits
    if(MaxLossesReachedToday(cfg)) { code_out = POLICY_MAX_LOSSES; return false; }
    if(MaxTradesReachedToday(cfg)) { code_out = POLICY_MAX_TRADES; return false; }

    // 3b) Monthly profit target (legacy ABI view)
    {
      double month_pct = 0.0;
      if(MonthlyProfitTargetHit(cfg, month_pct))
      {
        code_out = POLICY_MONTH_TARGET;
        return false;
      }
    }
    
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
    if(LossCooldownActive() || TradeCooldownActive())
    { code_out = POLICY_COOLDOWN; return false; }

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
    
    // Monthly profit target HUD
    bool     month_target_hit;
    double   month_start_equity;
    double   month_profit_pct;  // 0–100 %, +10.0 == +10 %
  };

   inline void TelemetrySnapshot(const Settings &cfg, Telemetry &t)
  {
    _EnsureLoaded(cfg);
    ZeroMemory(t);

    PolicyResult pr;
    EvaluateFullAudit(cfg, pr);

    t.gate_reason        = pr.primary_reason;
    t.news_mins_left     = pr.news_mins_left;
    t.cd_trade_sec_left  = pr.cd_trade_left_sec;
    t.cd_loss_sec_left   = pr.cd_loss_left_sec;

    t.day_stop_latched   = pr.day_stop_latched;
    t.day_loss_money     = pr.day_loss_money;
    t.day_loss_pct       = pr.day_loss_pct;
    t.day_dd_pct         = pr.day_dd_pct;

    t.acct_stop_latched  = pr.acct_stop_latched;
    t.acct_dd_pct        = pr.acct_dd_pct;
    t.acct_dd_limit_pct  = pr.acct_dd_limit_pct;

    t.spread_pts         = pr.spread_pts;
    t.spread_cap_pts     = pr.spread_cap_pts;

    t.atr_short_pts      = pr.atr_short_pts;
    t.atr_long_pts       = pr.atr_long_pts;
    t.vol_ratio          = pr.vol_ratio;

    t.liq_ratio          = pr.liq_ratio;

    t.adr_pts            = pr.adr_pts;
    t.adr_cap_limit_pts  = pr.adr_cap_limit_pts;
    t.adr_cap_hit        = pr.adr_cap_hit;

    t.in_session_window  = pr.in_session_window;

    t.month_target_hit   = pr.month_target_hit;
    t.month_start_equity = pr.month_eq0;
    t.month_profit_pct   = pr.month_profit_pct;


    // day PL & stops
    double pl=0.0; int w=0,l=0;
    if(DailyRealizedPL(cfg, pl, w, l)){ t.day_pl = pl; t.day_wins=w; t.day_losses=l; }

    // attempts + last attempt + last retcode
    t.attempts_today = _GVGetI(_Key("ATTEMPTS_D"), 0);
    t.last_attempt_ts= (datetime)_GVGetD(_Key("LAST_ATTEMPT_TS"), 0.0);
    t.last_retcode   = (uint)_GVGetI(_Key("LAST_EXEC_RC"), 0);
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
