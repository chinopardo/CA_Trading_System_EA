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
#ifndef POLICIES_HAS_SIZING_RESET_ACTIVE
#define POLICIES_HAS_SIZING_RESET_ACTIVE 1
#endif
#ifndef POLICIES_HAS_POOL_TELEMETRY_FRAME
#define POLICIES_HAS_POOL_TELEMETRY_FRAME 1
#endif
#ifndef POLICIES_HAS_POOL_TELEMETRY_FRAME_EX
#define POLICIES_HAS_POOL_TELEMETRY_FRAME_EX 1
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
  POLICY_MOD_SPREAD_HIGH = 8,
  POLICY_DAILY_DD        = 9,
  POLICY_ACCOUNT_DD      = 10,
  POLICY_VOLATILITY      = 11,
  POLICY_REGIME_FAIL     = 12,
  POLICY_CALM_MARKET     = 13,
  POLICY_DAYLOSS_STOP    = 14,
  POLICY_LIQUIDITY_FAIL  = 15,
  POLICY_CONFLICT        = 16,
  POLICY_ADR_CAP         = 17,
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
  
  inline int GateReasonToPolicyCode(const int gr)
   {
     switch(gr)
     {
       case GATE_OK:            return POLICY_OK;
       case GATE_SESSION:       return POLICY_SESSION_OFF;
       case GATE_NEWS:          return POLICY_NEWS_BLOCK;
       case GATE_COOLDOWN:      return POLICY_COOLDOWN;
       case GATE_MONTH_TARGET:  return POLICY_MONTH_TARGET;
   
       case GATE_SPREAD:        return POLICY_SPREAD_HIGH;
       case GATE_MOD_SPREAD:    return POLICY_MOD_SPREAD_HIGH;
   
       case GATE_MAX_LOSSES_DAY:return POLICY_MAX_LOSSES;
       case GATE_MAX_TRADES_DAY:return POLICY_MAX_TRADES;
   
       case GATE_DAYLOSS:       return POLICY_DAYLOSS_STOP;
       case GATE_DAILYDD:       return POLICY_DAILY_DD;
       case GATE_ACCOUNT_DD:    return POLICY_ACCOUNT_DD;
       case GATE_VOLATILITY:    return POLICY_VOLATILITY;
       case GATE_REGIME:        return POLICY_REGIME_FAIL;
       case GATE_CALM:          return POLICY_CALM_MARKET;
       case GATE_LIQUIDITY:     return POLICY_LIQUIDITY_FAIL;
       case GATE_CONFLICT:      return POLICY_CONFLICT;
       case GATE_ADR:           return POLICY_ADR_CAP;
   
       default:                 return POLICY_BLOCKED_OTHER;
     }
   }
   
   inline string SessionReasonFromFlags(const bool session_filter_on, const bool in_session_window)
   {
     if(!session_filter_on) return "FILTER_OFF";
     if(in_session_window)  return "IN_WINDOW";
     return "OUT_OF_WINDOW";
   }

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
  inline int EpochDay(datetime t)
   {
     if(t <= 0) t = TimeCurrent();
     MqlDateTime dt;
     TimeToStruct(t, dt);
     return (dt.year * 10000 + dt.mon * 100 + dt.day); // YYYYMMDD in server time
   }

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
  
  // 0 = calendar month, 1 = rolling 28 days (compile-safe default is calendar)
  inline bool CfgMonthlyTargetRolling28D(const Settings &cfg)
  {
    #ifdef CFG_HAS_MONTHLY_TARGET_CYCLE_MODE
      return (cfg.monthly_target_cycle_mode == 1);
    #else
      return false;
    #endif
  }

  // 0 = cycle-start equity, 1 = initial equity (linear), 2 = initial equity (compound; reserved)
  inline int CfgMonthlyTargetBaseMode(const Settings &cfg)
  {
    #ifdef CFG_HAS_MONTHLY_TARGET_BASE_MODE
      const int m = (int)cfg.monthly_target_base_mode;
      if(m >= CFG_TARGET_BASE_CYCLE_START && m <= CFG_TARGET_BASE_INITIAL_COMPOUND)
        return m;
      return CFG_TARGET_BASE_DEFAULT;
    #else
      return CFG_TARGET_BASE_DEFAULT;
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
       #ifdef CFG_HAS_NEWS_ON
         return (bool)cfg.news_on;
       #else
         return false;
       #endif
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
  inline int EffNewsPreMins(const Settings &cfg)
   {
     return (int)cfg.news_pre_mins;
   }
   
   inline int EffNewsPostMins(const Settings &cfg)
   {
     return (int)cfg.news_post_mins;
   }

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
  inline bool ADRCapOK(const Settings &cfg, const string sym, int &reason, double &adr_pts_out)
   {
     reason = GATE_OK; adr_pts_out = 0.0;
     const double adr_pts = ADRPoints(sym, CfgADRLookbackDays(cfg));
     if(adr_pts<=0.0) return true; // neutral if cannot compute
     adr_pts_out = adr_pts;
   
     #ifdef CFG_HAS_ADR_CAP_MULT
       const double cap_mult = CfgADRCapMult(cfg);            // e.g. 2.2
       if(cap_mult > 0.0)
       {
         // Real-time D1 range so far (points)
         MqlRates d1[]; ArraySetAsSeries(d1,true);
         if(CopyRates(sym, PERIOD_D1, 0, 1, d1)==1)
         {
           double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
           if(pt <= 0.0) pt = _Point;
           if(pt <= 0.0) return true; // can't compute safely, don't block trades
           const double today_pts = MathAbs(d1[0].high - d1[0].low) / pt;
           const double limit_pts = adr_pts * cap_mult;
           if(today_pts >= limit_pts)
           {
             reason=GATE_ADR;
             _GateDetail(cfg, reason, sym,
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
   
       const double pts_per_pip = MarketData::PointsFromPips(sym, 1.0);
       const double min_pts = (min_pips>0.0 ? min_pips * pts_per_pip : 0.0);
       const double max_pts = (max_pips>0.0 ? max_pips * pts_per_pip : 0.0);
       if(min_pts>0.0 && adr_pts < min_pts){ reason=GATE_ADR; return false; }
       if(max_pts>0.0 && adr_pts > max_pts){ reason=GATE_ADR; return false; }
       return true;
     #endif
   }

  inline bool ADRCapOK(const Settings &cfg, int &reason, double &adr_pts_out)
   { return ADRCapOK(cfg, _Symbol, reason, adr_pts_out); }

  // ----------------------------------------------------------------------------
  // PERSISTENT STATE (via Global Variables)
  // ----------------------------------------------------------------------------
  static bool     s_loaded          = false;
  static string   s_prefix          = "";    // "CA:POL:<login>:<magic>:"
  static string   s_last_eval_sym   = "";    // last symbol passed to _EvaluateCoreEx/_EvaluateFullEx (telemetry)
  static long     s_login           = 0;
  static long     s_magic_cached    = 0;

  // ----------------------------------------------------------------------------
  // Router confluence-pool telemetry frame (non-persistent; set by Router)
  // ----------------------------------------------------------------------------
  static bool     s_pool_valid      = false;
  static double   s_pool_score_buy  = 0.0;
  static double   s_pool_score_sell = 0.0;
  static string   s_pool_sym        = "";
  static datetime s_pool_ts         = 0;
  
  static int      s_pool_feat_buy   = 0;
  static int      s_pool_feat_sell  = 0;
  static ulong    s_pool_veto_buy   = 0;
  static ulong    s_pool_veto_sell  = 0;
    
  inline void ClearPoolTelemetryFrame()
  {
    s_pool_valid=false;
    s_pool_score_buy=0.0;
    s_pool_score_sell=0.0;
    s_pool_sym="";
    s_pool_ts=0;
    
    s_pool_feat_buy=0;
    s_pool_feat_sell=0;
    s_pool_veto_buy=0;
    s_pool_veto_sell=0;
  }

  inline void SetPoolTelemetryFrameEx(const string sym,
                                      const double score_buy,
                                      const double score_sell,
                                      const int feat_buy,
                                      const int feat_sell,
                                      const ulong veto_buy,
                                      const ulong veto_sell)
  {
    s_pool_valid      = true;
    s_pool_score_buy  = Clamp01(score_buy);
    s_pool_score_sell = Clamp01(score_sell);
    s_pool_feat_buy   = (feat_buy  > 0 ? feat_buy  : 0);
    s_pool_feat_sell  = (feat_sell > 0 ? feat_sell : 0);
    s_pool_veto_buy   = veto_buy;
    s_pool_veto_sell  = veto_sell;
    s_pool_sym        = sym;
    s_pool_ts         = TimeCurrent();
  }

  inline void SetPoolTelemetryFrame(const string sym,
                                    const double score_buy,
                                    const double score_sell)
  {
    SetPoolTelemetryFrameEx(sym, score_buy, score_sell, 0, 0, 0, 0);
  }

  inline bool GetPoolTelemetryFrame(double &buy_out, double &sell_out)
  {
    buy_out  = s_pool_score_buy;
    sell_out = s_pool_score_sell;
    return s_pool_valid;
  }

  inline bool GetPoolTelemetryFrameEx(double &buy_out, double &sell_out,
                                      int &feat_buy_out, int &feat_sell_out,
                                      ulong &veto_buy_out, ulong &veto_sell_out)
  {
    buy_out       = s_pool_score_buy;
    sell_out      = s_pool_score_sell;
    feat_buy_out  = s_pool_feat_buy;
    feat_sell_out = s_pool_feat_sell;
    veto_buy_out  = s_pool_veto_buy;
    veto_sell_out = s_pool_veto_sell;
    return s_pool_valid;
  }

  static int      s_dayKey          = -1;    // epoch-day
  static double   s_dayEqStart      =  0.0;
  static double   s_dayEqPeak       =  0.0;  // intraday peak equity (persisted)
  static int const DDPK_MAX         =  40;   // ring buffer capacity (days)
  static int      s_ddpk_idx        =  0;    // ring index (persisted)

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
  
  static datetime s_cycleStartTs   = 0;
  static double   s_cycleStartEq   = 0.0;
  static bool     s_cycleTargetHit = false;

  static int      s_loss_streak     = 0;
  static int      s_cooldown_losses = 2;
  static int      s_cooldown_min    = 15;
  static datetime s_cooldown_until  = 0;

  static int      s_trade_cd_sec    = 0;
  static datetime s_trade_cd_until  = 0;
  static datetime s_sizing_reset_until   = 0;     // big-loss sizing reset latch (persisted)

  // Big-loss sizing reset knobs (loaded from cfg in _LoadPersistent)
  static bool     s_bigloss_reset_enable = false;
  static double   s_bigloss_reset_r      = 2.0;
  static int      s_bigloss_reset_mins   = 120;

  // --- GV helpers ---
  inline string _Key(const string name){ return s_prefix + name; }
  inline double _GVGetD(const string k, const double defv=0.0){ return (GlobalVariableCheck(k)? GlobalVariableGet(k) : defv); }
  inline int    _GVGetI(const string k, const int defv=0){ return (int)MathRound(_GVGetD(k, (double)defv)); }
  inline bool   _GVGetB(const string k, const bool defb=false){ return (_GVGetI(k, (defb?1:0))!=0); }
  inline void   _GVSetD(const string k, const double v){ GlobalVariableSet(k, v); }
  inline void   _GVSetB(const string k, const bool v){ GlobalVariableSet(k, (v?1.0:0.0)); }
  inline void   _GVDel (const string k){ if(GlobalVariableCheck(k)) GlobalVariableDel(k); }
  
  // --- Adaptive DD rolling peak ring buffer (persisted) ---
  inline string _DDPkDayKey(const int i){ return _Key(StringFormat("DDPK_DAY_%d", i)); }
  inline string _DDPkEqKey (const int i){ return _Key(StringFormat("DDPK_EQ_%d",  i)); }

  inline void _DDPkSetIdx(const int i)
  {
    s_ddpk_idx = i;
    _GVSetD(_Key("DDPK_IDX"), (double)s_ddpk_idx);
  }

  inline void _PushDailyPeak(const int day, const double peak_eq)
  {
    if(day < 0) return;
    if(peak_eq <= 0.0) return;

    int idx = s_ddpk_idx;
    if(idx < 0) idx = 0;
    if(idx >= DDPK_MAX) idx = 0;

    _GVSetD(_DDPkDayKey(idx), (double)day);
    _GVSetD(_DDPkEqKey(idx),  peak_eq);

    idx++;
    if(idx >= DDPK_MAX) idx = 0;
    _DDPkSetIdx(idx);
  }


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
    _GVSetD(_Key("DAYEQ_PEAK"),     s_dayEqPeak);
    _GVSetD(_Key("DDPK_IDX"),       (double)s_ddpk_idx);
    _GVSetD(_Key("SIZRST_UNTIL"),   (double)s_sizing_reset_until);

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
    
    _GVSetD(_Key("C28_TS"),          (double)s_cycleStartTs);
    _GVSetD(_Key("C28_EQ0"),         s_cycleStartEq);
    _GVSetB(_Key("C28_TARGET_HIT"),  s_cycleTargetHit);
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
    double peak0   = _GVGetD(_Key("DAYEQ_PEAK"), 0.0);

    const double eqNow = AccountInfoDouble(ACCOUNT_EQUITY);

    // New day (or missing baseline): push prior day's peak into ring, then re-anchor
    if(storedD != curD || eq0 <= 0.0)
    {
      if(storedD >= 0 && storedD != curD)
      {
        double oldPeak = peak0;
        if(oldPeak <= 0.0) oldPeak = eq0;
        if(oldPeak > 0.0) _PushDailyPeak(storedD, oldPeak);
      }

      storedD = curD;
      eq0     = eqNow;
      peak0   = eqNow;

      _GVSetD(_Key("DAYKEY"),      (double)storedD);
      _GVSetD(_Key("DAYEQ0"),      eq0);
      _GVSetD(_Key("DAYEQ_PEAK"),  peak0);
    }
    else
    {
      // Same day: update intraday peak if needed
      if(eqNow > peak0)
      {
        peak0 = eqNow;
        _GVSetD(_Key("DAYEQ_PEAK"), peak0);
      }
    }

    s_dayKey     = storedD;
    s_dayEqStart = eq0;
    s_dayEqPeak  = peak0;

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
  
  inline void _EnsureCycle28DState(const Settings &cfg)
  {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    const datetime day0 = StructToTime(dt);

    datetime ts0 = (datetime)_GVGetD(_Key("C28_TS"), 0.0);
    double   eq0 = _GVGetD(_Key("C28_EQ0"), 0.0);
    bool     hit = _GVGetB(_Key("C28_TARGET_HIT"), false);

    const int cycle_sec = 28 * 86400;
    if(ts0 <= 0 || eq0 <= 0.0 || (day0 - ts0) >= (datetime)cycle_sec)
    {
      ts0 = day0;
      eq0 = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq0 <= 0.0) eq0 = _GVGetD(_Key("ACCT_EQ0"), 0.0);

      hit = false;

      _GVSetD(_Key("C28_TS"), (double)ts0);
      _GVSetD(_Key("C28_EQ0"), eq0);
      _GVSetB(_Key("C28_TARGET_HIT"), hit);
    }

    s_cycleStartTs   = ts0;
    s_cycleStartEq   = eq0;
    s_cycleTargetHit = hit;
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
    
    // Big-loss sizing reset knobs (compile-safe)
    #ifdef CFG_HAS_BIGLOSS_RESET_ENABLE
      s_bigloss_reset_enable = cfg.bigloss_reset_enable;
    #else
      s_bigloss_reset_enable = false;
    #endif

    #ifdef CFG_HAS_BIGLOSS_RESET_R
      s_bigloss_reset_r = cfg.bigloss_reset_r;
    #else
      s_bigloss_reset_r = 2.0;
    #endif
    if(s_bigloss_reset_r < 0.0) s_bigloss_reset_r = 0.0;

    #ifdef CFG_HAS_BIGLOSS_RESET_MINS
      s_bigloss_reset_mins = cfg.bigloss_reset_mins;
    #else
      s_bigloss_reset_mins = 120;
    #endif
    if(s_bigloss_reset_mins < 0) s_bigloss_reset_mins = 0;

    // Restore persisted running state
    s_loss_streak    = _GVGetI(_Key("LOSS_STREAK"), 0);
    s_cooldown_until = (datetime)_GVGetD(_Key("COOL_UNTIL"), 0.0);
    s_trade_cd_until = (datetime)_GVGetD(_Key("TRADECD_UNTIL"), 0.0);
    
    // Adaptive DD ring index + day peak + sizing reset latch
    s_ddpk_idx = _GVGetI(_Key("DDPK_IDX"), 0);
    if(s_ddpk_idx < 0) s_ddpk_idx = 0;
    if(s_ddpk_idx >= DDPK_MAX) s_ddpk_idx = 0;

    s_dayEqPeak = _GVGetD(_Key("DAYEQ_PEAK"), 0.0);
    s_sizing_reset_until = (datetime)_GVGetD(_Key("SIZRST_UNTIL"), 0.0);

    
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
  {
     MqlDateTime dt;
     TimeToStruct(TimeCurrent(), dt);
     dt.hour = 0; dt.min = 0; dt.sec = 0;
     t0 = StructToTime(dt);
     t1 = t0 + 86400;
  }

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

  inline double _RollingPeakEq(const int curD, const int window_days)
  {
    int win = window_days;
    if(win < 1) win = 30;

    double peak = s_dayEqPeak;
    if(peak <= 0.0) peak = s_dayEqStart;

    const int minD = curD - (win - 1);
    for(int i=0; i<DDPK_MAX; i++)
    {
      const int d = _GVGetI(_DDPkDayKey(i), -1);
      if(d < minD) continue;

      const double e = _GVGetD(_DDPkEqKey(i), 0.0);
      if(e > peak) peak = e;
    }
    return peak;
  }

  inline bool DailyEquityDDHit(const Settings &cfg, double &dd_pct_out)
  {
    _EnsureLoaded(cfg);
    _EnsureDayState();
    _EnsureAccountBaseline(cfg);

    dd_pct_out = 0.0;

    double limit_pct = CfgMaxDailyDDPct(cfg);
    if(limit_pct <= 0.0) return false;

    bool   adaptive_on  = false;
    int    window_days  = 30;
    double adaptive_pct = 0.0;

    #ifdef CFG_HAS_ADAPTIVE_DD_ENABLE
      adaptive_on = cfg.adaptive_dd_enable;
    #endif
    #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
      window_days = cfg.adaptive_dd_window_days;
    #endif
    #ifdef CFG_HAS_ADAPTIVE_DD_PCT
      adaptive_pct = cfg.adaptive_dd_pct;
    #endif
    if(window_days < 1) window_days = 30;
    if(adaptive_pct <= 0.0) adaptive_pct = limit_pct;

    const double eq_now = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq_now <= 0.0) return false;

    // keep intraday peak fresh
    if(eq_now > s_dayEqPeak)
    {
      s_dayEqPeak = eq_now;
      _GVSetD(_Key("DAYEQ_PEAK"), s_dayEqPeak);
    }

    // 1) Fixed-base daily DD:
    //    loss measured from day start, limit amount based on initial equity
    const double base_init = (s_acctEqStart > 0.0 ? s_acctEqStart : s_dayEqStart);
    if(base_init <= 0.0) return false;

    const double day_loss_money = (s_dayEqStart - eq_now);
    const double limit_money    = base_init * (limit_pct / 100.0);

    const bool fixed_hit = (day_loss_money >= limit_money);

    double fixed_pct = 0.0;
    if(day_loss_money > 0.0)
      fixed_pct = 100.0 * day_loss_money / base_init;

    // 2) Adaptive DD: rolling peak over window_days, compared to adaptive_pct
    bool   adaptive_hit     = false;
    double adaptive_now_pct = 0.0;

    if(adaptive_on)
    {
      double rp = _RollingPeakEq(s_dayKey, window_days);
      if(rp < s_dayEqStart) rp = s_dayEqStart;

      if(rp > 0.0)
      {
        const double dd_from_peak = (rp - eq_now);
        if(dd_from_peak > 0.0)
        {
          adaptive_now_pct = 100.0 * dd_from_peak / rp;
          adaptive_hit     = (adaptive_now_pct >= adaptive_pct);
        }
      }
    }

   // For logs/diagnostics: report the ACTIVE mode (adaptive when enabled, else fixed)
   dd_pct_out = (adaptive_on ? adaptive_now_pct : fixed_pct);
   
   // (Optional) strictest dd% (debug/telemetry only)
   const double dd_pct_strict = MathMax(fixed_pct, adaptive_now_pct);
   if(false) { Print(dd_pct_strict); } // placeholder to silence unused warnings if you later log it
   
   // Option B: when adaptive is enabled, it REPLACES fixed-base DD for the daily equity stop.
   return (adaptive_on ? adaptive_hit : fixed_hit);
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
   
     const bool roll28 = CfgMonthlyTargetRolling28D(cfg);
     if(roll28) _EnsureCycle28DState(cfg);
     else       _EnsureMonthState();
   
     profit_pct_out = 0.0;
     target_hit_out = false;
   
     const double eq_cycle0 = (roll28 ? s_cycleStartEq : s_monthStartEq);
     const double eq_now    = AccountInfoDouble(ACCOUNT_EQUITY);
     if(eq_cycle0 <= 0.0 || eq_now <= 0.0)
       return;
   
     // Profit is always measured vs cycle-start equity (so cycle P/L is true “this cycle” performance)
     const double profit_money = (eq_now - eq_cycle0);
   
     // Target size can be based on cycle-start equity OR initial equity (your requirement)
     int base_mode = CfgMonthlyTargetBaseMode(cfg);
     if(base_mode == CFG_TARGET_BASE_INITIAL_COMPOUND)
       base_mode = CFG_TARGET_BASE_INITIAL_LINEAR; // compound reserved; keep behavior deterministic
   
     double eq_base = eq_cycle0; // default: cycle-start
     if(base_mode != CFG_TARGET_BASE_CYCLE_START)
     {
       _EnsureAccountBaseline(cfg);
       if(s_acctEqStart > 0.0)
         eq_base = s_acctEqStart;
     }
   
     const double target_pct = CfgMonthlyTargetPct(cfg);
     if(eq_base > 0.0)
       profit_pct_out = 100.0 * profit_money / eq_base;
   
     // Use money comparison for exactness and to avoid percent drift
     const double target_money = (target_pct > 0.0 ? (eq_base * (target_pct / 100.0)) : 0.0);
     const bool hit_now = (target_pct > 0.0 && target_money > 0.0 && profit_money >= target_money);
   
     if(hit_now)
     {
       if(roll28)
       {
         s_cycleTargetHit = true;
         target_hit_out   = true;
         _GVSetB(_Key("C28_TARGET_HIT"), true);
       }
       else
       {
         s_monthTargetHit = true;
         target_hit_out   = true;
         _GVSetB(_Key("MONTH_TARGET_HIT"), true);
       }
     }
     else
     {
       // If target already latched from earlier run, respect it
       if(roll28)
       {
         if(_GVGetB(_Key("C28_TARGET_HIT"), false))
         {
           s_cycleTargetHit = true;
           target_hit_out   = true;
         }
       }
       else
       {
         if(_GVGetB(_Key("MONTH_TARGET_HIT"), false))
         {
           s_monthTargetHit = true;
           target_hit_out   = true;
         }
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

  inline double SpreadCapAdaptiveMult(const Settings &cfg, const string sym)
  {
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
  
  inline double SpreadCapAdaptiveMult(const Settings &cfg)
   { return SpreadCapAdaptiveMult(cfg, _Symbol); }
  
  // --- Weekly-open spread ramp (first hour after weekly open) -------------------
  // Adjust a spread cap expressed in *points*. Uses server time Mon 00:00–00:59.
  inline double AdjustSpreadCapWeeklyOpenPts(const Settings &cfg, const string sym, const double cap_pts_in)
  {
    double cap = cap_pts_in;
    if(cap <= 0.0) return cap;

    MqlDateTime ds; TimeToStruct(TimeCurrent(), ds); // server time
    if(ds.day_of_week == 1 /*Mon*/ && ds.hour == 0)
    {
      const double ppp = MarketData::PointsFromPips(sym, 1.0);
      if(ppp > 0.0)
      {
        const double min_pts = 8.0 * ppp;
        if(cap < min_pts) cap = min_pts;
      }
    }
    return cap;
  }

  inline double AdjustSpreadCapWeeklyOpenPts(const Settings &cfg, const double cap_pts_in)
  { return AdjustSpreadCapWeeklyOpenPts(cfg, _Symbol, cap_pts_in); }

  inline bool MoDSpreadOK(const Settings &cfg, const string sym, int &reason)
  {
    _EnsureLoaded(cfg);

    reason = GATE_OK;
    int cap = EffMaxSpreadPts(cfg, sym);
    if(cap<=0) return true;

    const double adapt = SpreadCapAdaptiveMult(cfg, sym);
    // apply adaptive scaling first
    double eff_cap_pts = MathFloor((double)cap * adapt);
    
    // weekly-open ramp (points)
    if(CfgWeeklyRampOn(cfg))
      eff_cap_pts = AdjustSpreadCapWeeklyOpenPts(cfg, sym, eff_cap_pts);
    cap = (int)MathFloor(eff_cap_pts);

    const double sp = MarketData::SpreadPoints(sym);
    if(sp<=0.0) return true;

    if(EffSessionFilter(cfg, sym))
    {
      const bool inwin = TimeUtils::InTradingWindow(cfg, TimeCurrent());
      if(!inwin)
      {
        const int tight = (int)MathFloor(s_mod_mult_outside * (double)cap);
        if(tight>0 && (int)sp>tight)
        {
          reason=GATE_MOD_SPREAD;
          _GateDetail(cfg, reason, sym,
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
      _GateDetail(cfg, reason, sym,
                  StringFormat("sp=%.1f cap=%d adapt=%.3f eff_cap_pts=%.1f weeklyRamp=%s",
                               sp, cap, adapt, eff_cap_pts, (CfgWeeklyRampOn(cfg)?"ON":"OFF")));
      return false;
    }
    return true;
  }

  inline bool MoDSpreadOK(const Settings &cfg, int &reason)
   { return MoDSpreadOK(cfg, _Symbol, reason); }
   
  // ----------------------------------------------------------------------------
  // Volatility breaker (re-uses short/long ATR config)
  // ----------------------------------------------------------------------------
  static double s_vb_limit = 2.50;
  inline void SetVolBreakerLimit(const double limit)
  {
    if(limit <= 0.0){ s_vb_limit = 0.0; return; }   // disabled
    s_vb_limit = (limit < 1.10 ? 1.10 : limit);
  }

  inline bool VolatilityBreaker(const Settings &cfg, const string sym, double &ratio_out)
  {
    _EnsureLoaded(cfg);

    ratio_out = 0.0;
    if(s_vb_limit <= 0.0) return false; // disabled

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = (s_vb_shortP>0 ? s_vb_shortP : CfgATRShort(cfg));
    const int longP  = s_vb_longP;

    const double aS = AtrPts(sym, tf, cfg, shortP, 1);
    const double aL = AtrPts(sym, tf, cfg, longP,  1);
    if(aS<=0.0 || aL<=0.0) return false;

    ratio_out = aS/aL;
    return (ratio_out > s_vb_limit);
  }

  inline bool VolatilityBreaker(const Settings &cfg, double &ratio_out)
  { return VolatilityBreaker(cfg, _Symbol, ratio_out); }

  // ----------------------------------------------------------------------------
  // Calm mode
  // ----------------------------------------------------------------------------
  inline bool CalmModeOK(const Settings &cfg, const string sym, int &reason)
  {
    _EnsureLoaded(cfg);

    reason = GATE_OK;
    if(!CfgCalmEnable(cfg)) return true;

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
        _GateDetail(cfg, reason, sym,
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
        _GateDetail(cfg, reason, sym,
                    StringFormat("atr_s_pts=%.1f spr_pts=%.1f ratio=%.3f minRatio=%.3f",
                                 atr_s, spr, (spr>0.0?atr_s/spr:0.0), minRatio));
        return false;
      }
    }
    return true;
  }

  inline bool CalmModeOK(const Settings &cfg, int &reason)
   { return CalmModeOK(cfg, _Symbol, reason); }
  // ----------------------------------------------------------------------------
  // Loss/cooldown management (PERSISTED)
  // ----------------------------------------------------------------------------
  inline void SetLossCooldownParams(const int losses, const int minutes)
  { s_cooldown_losses=(losses<1?1:losses); s_cooldown_min=(minutes<1?1:minutes); _GVSetD(_Key("COOL_N"), (double)s_cooldown_losses); _GVSetD(_Key("COOL_MIN"), (double)s_cooldown_min); }

  inline void ArmSizingResetForMins(const int mins)
  {
    if(mins <= 0) return;

    const datetime until_ts = TimeCurrent() + (datetime)(mins * 60);
    if(until_ts > s_sizing_reset_until)
    {
      s_sizing_reset_until = until_ts;
      _GVSetD(_Key("SIZRST_UNTIL"), (double)s_sizing_reset_until);
    }
  }
  
inline void NotifyTradeResult(const double r_multiple)
{
  // Big-loss sizing reset latch:
  // Only arm the reset window when the loss is <= -R (e.g., -2.0R or worse).
  if(s_bigloss_reset_enable && s_bigloss_reset_mins > 0 && s_bigloss_reset_r > 0.0)
  {
    if(r_multiple <= -s_bigloss_reset_r)
      ArmSizingResetForMins(s_bigloss_reset_mins);
  }

  // Loss streak tracking (unchanged behavior)
  if(r_multiple < 0.0) s_loss_streak++;
  else                s_loss_streak = 0;

  _GVSetD(_Key("LOSS_STREAK"), (double)s_loss_streak);

  if(s_loss_streak >= s_cooldown_losses)
  {
    s_cooldown_until = TimeCurrent() + (datetime)(s_cooldown_min * 60);
    _GVSetD(_Key("COOL_UNTIL"), (double)s_cooldown_until);
    s_loss_streak = 0;
    _GVSetD(_Key("LOSS_STREAK"), 0.0);
  }
}

  inline bool SizingResetActive()
  {
    if(s_sizing_reset_until <= 0) return false;
    if(TimeCurrent() >= s_sizing_reset_until)
    {
      s_sizing_reset_until = 0;
      _GVSetD(_Key("SIZRST_UNTIL"), 0.0);
      return false;
    }
    return true;
  }

  inline int SizingResetSecondsLeft(){ return _SecondsLeft(s_sizing_reset_until); }

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
    PrintFormat("[GateDetail] %s reason=%d (%s) %s%s",
            sym, reason, GateReasonToString(reason), msg, _FmtPoolTag(sym));
  }
  
  // ----------------------------------------------------------------------------
  // Guaranteed veto logger (NOT debug-gated) — prevents silent vetoing.
  // Throttles identical veto spam to once per second per (reason+mask).
  // ----------------------------------------------------------------------------
  #ifdef NEWSFILTER_AVAILABLE
   inline string _FmtNewsVeto(const int mins_left,
                              const int impact_mask,
                              const int pre_m,
                              const int post_m)
   {
      News::Health h; 
      News::GetHealth(h);
   
      string note = h.note;
      if(StringLen(note) > 80) note = StringSubstr(note, 0, 80);
   
      if(note != "")
         return StringFormat("News block mins_left=%d impact_mask=%d pre=%d post=%d backend=%d broker=%d csv=%d health=%d note=%s",
                             mins_left, impact_mask, pre_m, post_m,
                             h.backend_effective, (h.broker_available ? 1 : 0), h.csv_events, h.data_health, note);
   
      return StringFormat("News block mins_left=%d impact_mask=%d pre=%d post=%d backend=%d broker=%d csv=%d health=%d",
                          mins_left, impact_mask, pre_m, post_m,
                          h.backend_effective, (h.broker_available ? 1 : 0), h.csv_events, h.data_health);
   }
   #endif
   
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

  inline string _FmtSpreadVeto(const double spread_pts, const double max_spread_pts)
   {
     return StringFormat("spread=%.1f pts > max=%.1f pts", spread_pts, max_spread_pts);
   }
   
  inline string _FmtSessionVeto(const string session_reason)
   {
     return StringFormat("session_block (%s)", session_reason);
   }
   
  inline string _FmtCooldownVeto(const int left_sec, const int total_sec)
   {
     return StringFormat("cooldown_left=%ds total=%ds", left_sec, total_sec);
   }

  inline string _FmtPoolTag(const string sym)
   {
     if(!s_pool_valid)
       return " pool=na";
   
     int age = -1;
     if(s_pool_ts > 0)
       age = (int)(TimeCurrent() - s_pool_ts);
   
     string sym_note = "";
     if(s_pool_sym != "" && s_pool_sym != sym)
       sym_note = StringFormat(" poolSym=%s", s_pool_sym);
   
     string feat_note = "";
     if(s_pool_feat_buy > 0 || s_pool_feat_sell > 0)
       feat_note = StringFormat(" fbB=%d fbS=%d", s_pool_feat_buy, s_pool_feat_sell);
   
     string veto_note = "";
     if(s_pool_veto_buy != 0 || s_pool_veto_sell != 0)
       veto_note = StringFormat(" vmB=%s vmS=%s", (string)s_pool_veto_buy, (string)s_pool_veto_sell);
   
     if(age >= 0)
       return StringFormat("%s poolB=%.3f poolS=%.3f poolAge=%ds%s%s",
                           sym_note, s_pool_score_buy, s_pool_score_sell, age, feat_note, veto_note);
   
     return StringFormat("%s poolB=%.3f poolS=%.3f%s%s",
                         sym_note, s_pool_score_buy, s_pool_score_sell, feat_note, veto_note);
   }

  inline string FormatPrimaryVetoDetail(const PolicyResult &r)
   {
     const string sym = (StringLen(s_last_eval_sym) > 0 ? s_last_eval_sym : _Symbol);
     const string pool_tag = _FmtPoolTag(sym);
     switch(r.primary_reason)
     {
       case GATE_SPREAD:
       case GATE_MOD_SPREAD:
         return _FmtSpreadVeto(r.spread_pts, (double)r.spread_cap_pts) + pool_tag;;
   
       case GATE_SESSION:
         return _FmtSessionVeto(SessionReasonFromFlags(r.session_filter_on, r.in_session_window)) + pool_tag;;
   
       case GATE_COOLDOWN:
       {
         const int left_sec = (r.cd_trade_left_sec > r.cd_loss_left_sec ? r.cd_trade_left_sec : r.cd_loss_left_sec);
         const int total_sec = (int)(r.loss_cd_min * 60);
         return _FmtCooldownVeto(left_sec, total_sec) + pool_tag;;
       }
   
       case GATE_DAILYDD:
         return StringFormat("DailyDD dd=%.3f%% limit=%.3f%%",
                             r.day_dd_pct, r.day_dd_limit_pct) + pool_tag;
   
       case GATE_DAYLOSS:
         return StringFormat("DayLoss loss=%.2f (%.3f%%) cap=%.2f (%.3f%%)",
                             r.day_loss_money, r.day_loss_pct,
                             r.day_loss_cap_money, r.day_loss_cap_pct) + pool_tag;
   
       case GATE_ACCOUNT_DD:
         return StringFormat("AccountDD dd=%.3f%% limit=%.3f%% latched=%d",
                             r.acct_dd_pct, r.acct_dd_limit_pct,
                             (r.acct_stop_latched?1:0)) + pool_tag;
   
       case GATE_MONTH_TARGET:
         return StringFormat("MonthTarget hit=%d profit=%.3f%% target=%.3f%%",
                             (r.month_target_hit?1:0),
                             r.month_profit_pct, r.month_target_pct) + pool_tag;
   
       case GATE_VOLATILITY:
         return StringFormat("VolBreaker ratio=%.3f limit=%.3f atrS=%.1f atrL=%.1f",
                             r.vol_ratio, r.vol_limit, r.atr_short_pts, r.atr_long_pts) + pool_tag;
   
       case GATE_ADR:
         return StringFormat("ADRCap today=%.1f cap=%.1f adr=%.1f",
                             r.adr_today_range_pts, r.adr_cap_limit_pts, r.adr_pts) + pool_tag;
   
       case GATE_CALM:
         return StringFormat("Calm atrS=%.1f spread=%.1f atr/spread=%.3f minRatio=%.3f",
                             r.atr_short_pts, r.spread_pts, r.calm_atr_to_spread, r.calm_min_ratio) + pool_tag;
   
       case GATE_LIQUIDITY:
         return StringFormat("Liquidity ratio=%.3f floor=%.3f atrS=%.1f spread=%.1f",
                             r.liq_ratio, r.liq_floor, r.atr_short_pts, r.spread_pts) + pool_tag;
   
       case GATE_REGIME:
         return StringFormat("Regime tq=%.3f sg=%.3f minTQ=%.3f minSG=%.3f",
                             r.regime_tq, r.regime_sg, r.regime_tq_min, r.regime_sg_min) + pool_tag;

       case GATE_NEWS:
         #ifdef NEWSFILTER_AVAILABLE
           return _FmtNewsVeto(r.news_mins_left, r.news_impact_mask, r.news_pre_mins, r.news_post_mins) + _FmtPoolTag(sym);
         #else
           return StringFormat("news_block mins_left=%d", r.news_mins_left) + _FmtPoolTag(sym);
         #endif
   
       default:
         return _FmtPoolTag(sym); // or "" + _FmtPoolTag(sym) if you want consistent presence
     }
   }

  inline void PolicyVetoLog(const PolicyResult &r)
   {
     const string sym = (StringLen(s_last_eval_sym) > 0 ? s_last_eval_sym : _Symbol);
     string gate_log = "";
     const string pool_tag = _FmtPoolTag(sym);
   
     if(_ShouldVetoLogOncePerSec(sym, r.primary_reason, r.veto_mask) == false)
       return;

    // Gate-specific “exact values” prints
    switch(r.primary_reason)
    {
      case GATE_SPREAD:
      case GATE_MOD_SPREAD:
        gate_log = _FmtSpreadVeto(r.spread_pts, (double)r.spread_cap_pts);
        Print("[Policy][VETO] reason=", GateReasonToString(r.primary_reason),
              " sym=", sym,
              " spread=", DoubleToString(r.spread_pts,1),
              " cap=", (string)r.spread_cap_pts,
              " adapt=", DoubleToString(r.spread_adapt_mult,3),
              " modMult=", DoubleToString(r.mod_spread_mult,3),
              " modCap=", (string)r.mod_spread_cap_pts,
              " inSession=", (r.in_session_window?"1":"0"),
              " weeklyRamp=", (r.weekly_ramp_on?"1":"0"),
              " mask=", (string)r.veto_mask, gate_log, pool_tag);
        break;

      case GATE_NEWS:
        #ifdef NEWSFILTER_AVAILABLE
            gate_log = _FmtNewsVeto(r.news_mins_left, r.news_impact_mask, r.news_pre_mins, r.news_post_mins);
        #else
            gate_log = StringFormat("News block. mins_left=%d impact_mask=%d pre=%d post=%d",
                               r.news_mins_left, r.news_impact_mask, r.news_pre_mins, r.news_post_mins);
        #endif
        Print("[Policy][VETO] reason=NEWS sym=", sym,
              " block=", (r.news_blocked?"1":"0"),
              " minutes=", (string)r.news_mins_left,
              " impactMask=", (string)r.news_impact_mask,
              " pre=", (string)r.news_pre_mins,
              " post=", (string)r.news_post_mins,
              " mask=", (string)r.veto_mask, gate_log, pool_tag);
        break;

      case GATE_SESSION:
        gate_log = _FmtSessionVeto(SessionReasonFromFlags(r.session_filter_on, r.in_session_window));
        Print("[Policy][VETO] reason=SESSION sym=", sym,
              " sessionFilter=", (r.session_filter_on?"1":"0"),
              " inWindow=", (r.in_session_window?"1":"0"),
              " server=", TimeToString(TimeCurrent(), TIME_SECONDS),
              " mask=", (string)r.veto_mask, gate_log, pool_tag);
        break;

      case GATE_COOLDOWN:
        gate_log = _FmtCooldownVeto(r.cd_loss_left_sec, (int)(r.loss_cd_min * 60));
        Print("[Policy][VETO] reason=COOLDOWN sym=", sym,
              " trade_left_sec=", (string)r.cd_trade_left_sec,
              " loss_left_sec=", (string)r.cd_loss_left_sec,
              " trade_cd_sec=", (string)r.trade_cd_sec,
              " loss_cd_min=", (string)r.loss_cd_min,
              " mask=", (string)r.veto_mask, gate_log, pool_tag);
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

  inline void _FillSpreadDiag(const Settings &cfg, const string sym, PolicyResult &r)
  {
    r.weekly_ramp_on     = CfgWeeklyRampOn(cfg);
    r.mod_spread_mult    = s_mod_mult_outside;

    const int cap_base   = EffMaxSpreadPts(cfg, sym);
    const double adapt   = SpreadCapAdaptiveMult(cfg, sym);
    r.spread_adapt_mult  = adapt;

    double cap_eff = (double)cap_base * adapt;
    if(r.weekly_ramp_on)
      cap_eff = AdjustSpreadCapWeeklyOpenPts(cfg, sym, cap_eff);

    r.spread_cap_pts     = (int)MathFloor(cap_eff);
    r.mod_spread_cap_pts = (int)MathFloor(r.mod_spread_mult * (double)r.spread_cap_pts);
    r.spread_pts         = MarketData::SpreadPoints(sym);
  }

  inline void _FillSpreadDiag(const Settings &cfg, PolicyResult &r)
   { _FillSpreadDiag(cfg, _Symbol, r); }

  inline void _FillATRDiag(const Settings &cfg, const string sym, PolicyResult &r)
  {
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    r.atr_short_pts = AtrPts(sym, tf, cfg, CfgATRShort(cfg), 1);
    r.atr_long_pts  = AtrPts(sym, tf, cfg, CfgATRLong(cfg),  1);
    r.vol_ratio     = (r.atr_long_pts > 0.0 ? (r.atr_short_pts / r.atr_long_pts) : 0.0);
    r.vol_limit     = s_vb_limit;
  }

  inline void _FillADRCapDiag(const Settings &cfg, const string sym, PolicyResult &r)
  {
    r.adr_cap_hit = false;
    r.adr_pts     = ADRPoints(sym, CfgADRLookbackDays(cfg));

    r.adr_today_range_pts = 0.0;
    r.adr_cap_limit_pts   = 0.0;

    #ifdef CFG_HAS_ADR_CAP_MULT
    const double cap_mult = CfgADRCapMult(cfg);
    if(cap_mult > 0.0 && r.adr_pts > 0.0)
    {
      r.adr_cap_limit_pts = r.adr_pts * cap_mult;

      MqlRates d1[]; ArraySetAsSeries(d1,true);
      if(CopyRates(sym, PERIOD_D1, 0, 1, d1) == 1)
      {
        double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
        if(pt <= 0.0) pt = _Point;
        if(pt > 0.0)
          r.adr_today_range_pts = MathAbs(d1[0].high - d1[0].low) / pt;
      }
    }
    #endif
  }

  inline void _FillCalmDiag(const Settings &cfg, const string sym, PolicyResult &r)
  {
    r.calm_min_atr_pips    = CfgCalmMinATRPips(cfg);
    r.calm_min_ratio       = CfgCalmMinATRtoSpread(cfg);
    r.calm_min_atr_pts     = 0.0;

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    r.atr_short_pts = AtrPts(sym, tf, cfg, CfgATRShort(cfg), 1);
    r.spread_pts    = MarketData::SpreadPoints(sym);

    if(r.calm_min_atr_pips > 0.0)
      r.calm_min_atr_pts = MarketData::PointsFromPips(sym, r.calm_min_atr_pips);

    r.calm_atr_to_spread = (r.spread_pts > 0.0 ? r.atr_short_pts / r.spread_pts : 0.0);
  }

  inline void _FillLiquidityDiag(const Settings &cfg, const string sym, PolicyResult &r)
  {
    _FillATRDiag(cfg, sym, r); // ensures atr_short_pts available
    r.spread_pts = MarketData::SpreadPoints(sym);

    const double floorR = EffLiqMinRatio(cfg, sym, s_liq_min_ratio);
    r.liq_floor  = floorR;

    if(r.spread_pts > 0.0)
      r.liq_ratio = (r.atr_short_pts / r.spread_pts);
    else
      r.liq_ratio = 0.0;
  }

  inline bool _EvaluateCoreEx(const Settings &cfg, const string sym, PolicyResult &out, const bool audit)
  {
    s_last_eval_sym = sym;
    _EnsureLoaded(cfg);
    _EnsureMonthState();
    _EnsureDayState();
    _EnsureAccountBaseline(cfg);

    _PolicyReset(out);
    _ApplyRuntimeKnobsFromCfg(cfg);

    out.session_filter_on = EffSessionFilter(cfg, sym);
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
      if(!MoDSpreadOK(cfg, sym, spread_reason))
      {
        _FillSpreadDiag(cfg, sym, out);
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
      if(VolatilityBreaker(cfg, sym, vb_ratio))
      {
        _FillATRDiag(cfg, sym, out);
        out.vol_ratio = vb_ratio;
        _PolicyVeto(out, GATE_VOLATILITY, CA_POLMASK_VOLATILITY);
        if(!audit) return false;
      }
    }

    // 9) ADR cap
    {
      double adr_pts=0.0; int adr_reason=GATE_OK;
      if(!ADRCapOK(cfg, sym, adr_reason, adr_pts))
      {
        _FillADRCapDiag(cfg, sym, out);
        out.adr_cap_hit = true;
        _PolicyVeto(out, GATE_ADR, CA_POLMASK_ADR);
        if(!audit) return false;
      }
    }

    // 10) Calm
    {
      int calm_reason=GATE_OK;
      if(!CalmModeOK(cfg, sym, calm_reason))
      {
        _FillCalmDiag(cfg, sym, out);
        _PolicyVeto(out, GATE_CALM, CA_POLMASK_CALM);
        if(!audit) return false;
      }
    }

    // 11) Regime
    EnableRegimeGate(CfgRegimeGateOn(cfg));
    SetRegimeThresholds(CfgRegimeTQMin(cfg), CfgRegimeSGMin(cfg));
    if(!RegimeConsensusOK(cfg, sym))
    {
      // Capture exact values for guaranteed veto logs (NOT debug gated)
      out.regime_tq_min = s_reg_tq_min;
      out.regime_sg_min = s_reg_sg_min;

      const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
      out.regime_tq = RegimeX::TrendQuality(sym, tf, 60);
      out.regime_sg = Corr::HysteresisSlopeGuard(sym, tf, 14, 23.0, 15.0);

      _PolicyVeto(out, GATE_REGIME, CA_POLMASK_REGIME);
      if(!audit) return false;
    }

    return out.allowed;
  }

  inline bool _EvaluateFullEx(const Settings &cfg, const string sym, PolicyResult &out, const bool audit)
  {
    const bool ok_core = _EvaluateCoreEx(cfg, sym, out, audit);
    if(!audit && !ok_core) return false;
    
    // A) Day max-losses
    if(MaxLossesReachedToday(cfg, sym))
    {
      out.max_losses_day = 0;
      out.entries_today  = 0;
      out.losses_today   = 0;

      #ifdef CFG_HAS_MAX_LOSSES_DAY
        out.max_losses_day = cfg.max_losses_day;
        int entries=0, losses=0;
        const long mf = _MagicFilterFromCfg(cfg);
        CountTodayTradesAndLosses(sym, mf, entries, losses);
        out.entries_today = entries;
        out.losses_today  = losses;
      #endif

      _PolicyVeto(out, GATE_MAX_LOSSES_DAY, CA_POLMASK_MAX_LOSSES_DAY);
      if(!audit) return false;
    }

    // B) Day max-trades
    if(MaxTradesReachedToday(cfg, sym))
    {
      out.max_trades_day = 0;
      out.entries_today  = 0;
      out.losses_today   = 0;

      #ifdef CFG_HAS_MAX_TRADES_DAY
        out.max_trades_day = cfg.max_trades_day;
        int entries=0, losses=0;
        const long mf = _MagicFilterFromCfg(cfg);
        CountTodayTradesAndLosses(sym, mf, entries, losses);
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
    out.news_impact_mask = EffNewsImpactMask(cfg, sym);
    out.news_pre_mins    = CfgNewsBlockPreMins(cfg);
    out.news_post_mins   = CfgNewsBlockPostMins(cfg);

    {
      int mins_left=0;
      const datetime now_srv = TimeUtils::NowServer();
      if(NewsBlockedNow(cfg, sym, now_srv, mins_left))
      {
        out.news_blocked   = true;
        out.news_mins_left = mins_left;
        if(s_bigloss_reset_enable && mins_left > 0)
         ArmSizingResetForMins(mins_left);
        _PolicyVeto(out, GATE_NEWS, CA_POLMASK_NEWS);
        if(!audit) return false;
      }
    }

    // E) Liquidity veto
    {
      double liqR=0.0;
      if(!LiquidityOK(cfg, sym, liqR))
      {
        _FillLiquidityDiag(cfg, sym, out);
        out.liq_ratio = liqR;
        _PolicyVeto(out, GATE_LIQUIDITY, CA_POLMASK_LIQUIDITY);
        if(!audit) return false;
      }
    }

    return out.allowed;
  }

  // Public API
  inline bool EvaluateCore(const Settings &cfg, PolicyResult &out)      { return _EvaluateCoreEx(cfg, _Symbol, out, false); }
  inline bool EvaluateCoreAudit(const Settings &cfg, PolicyResult &out) { return _EvaluateCoreEx(cfg, _Symbol, out, true);  }
  inline bool EvaluateFull(const Settings &cfg, PolicyResult &out)      { return _EvaluateFullEx(cfg, _Symbol, out, false); }
  inline bool EvaluateFullAudit(const Settings &cfg, PolicyResult &out) { return _EvaluateFullEx(cfg, _Symbol, out, true);  }
  
  inline bool EvaluateCore(const Settings &cfg, const string sym, PolicyResult &out)      { return _EvaluateCoreEx(cfg, sym, out, false); }
  inline bool EvaluateCoreAudit(const Settings &cfg, const string sym, PolicyResult &out) { return _EvaluateCoreEx(cfg, sym, out, true);  }
  inline bool EvaluateFull(const Settings &cfg, const string sym, PolicyResult &out)      { return _EvaluateFullEx(cfg, sym, out, false); }
  inline bool EvaluateFullAudit(const Settings &cfg, const string sym, PolicyResult &out) { return _EvaluateFullEx(cfg, sym, out, true);  }

  // ---------------------------------------------------------------------------
  // Central gate used by Execution.mqh  → Policies::Check(cfg, reason)
  // ---------------------------------------------------------------------------
  inline bool Check(const Settings &cfg, int &reason)
  {
    int mins_left_news = 0;
    return CheckFull(cfg, reason, mins_left_news);
  }

  inline bool Check(const Settings &cfg, const string sym, int &reason)
   {
     int mins_left_news = 0;
     return CheckFull(cfg, sym, reason, mins_left_news);
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
    // Legacy overload: prefer RecordExecutionAttempt(sid)
    if(!MQLInfoInteger(MQL_TESTER))
      Print("[Policy] WARNING: RecordExecutionAttempt() called without StrategyID (sid=0). Check caller wiring.");
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
    // Legacy overload: prefer RecordExecutionResult(sid, ok, retcode, filled_volume)
    if(!MQLInfoInteger(MQL_TESTER))
      Print("[Policy] WARNING: RecordExecutionResult() called without StrategyID (sid=0). Check caller wiring.");
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

  inline bool RegimeConsensusOK(const Settings &cfg, const string sym)
  {
    if(!s_regime_gate_on) return true;
    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const double tq = RegimeX::TrendQuality(sym, tf, 60);
    const double sg = Corr::HysteresisSlopeGuard(sym, tf, 14,23.0,15.0);
    const bool ok = (tq>=s_reg_tq_min) || (sg>=s_reg_sg_min);
    if(!ok)
      _GateDetail(cfg, GATE_REGIME, sym,
                  StringFormat("tq=%.3f sg=%.3f tq_min=%.3f sg_min=%.3f",
                               tq, sg, s_reg_tq_min, s_reg_sg_min));
    return ok;
  }

  inline bool RegimeConsensusOK(const Settings &cfg)
   { return RegimeConsensusOK(cfg, _Symbol); }
   
  // ----------------------------------------------------------------------------
  // Liquidity (ATR:Spread) floor
  // ----------------------------------------------------------------------------
  static double s_liq_min_ratio = 1.50;
  inline void   SetLiquidityParams(const double min_ratio)
  { s_liq_min_ratio = Clamp(min_ratio, 0.5, 10.0); }

  inline bool LiquidityOK(const Settings &cfg, const string sym, double &ratio_out)
  {
    ratio_out = 0.0;

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = CfgATRShort(cfg);

    const double atr_s = AtrPts(sym, tf, cfg, shortP, 1);
    const double spr   = MarketData::SpreadPoints(sym);
    if(atr_s<=0.0 || spr<=0.0) return true; // can't compute safely → don't block

    const double floorR = EffLiqMinRatio(cfg, sym, s_liq_min_ratio);
    ratio_out = atr_s / spr;

    const bool ok = (ratio_out >= floorR);
    if(!ok)
      _GateDetail(cfg, GATE_LIQUIDITY, sym,
                  StringFormat("atr_s_pts=%.1f spr_pts=%.1f ratio=%.3f floor=%.3f",
                               atr_s, spr, ratio_out, floorR));
    return ok;
  }

  inline bool LiquidityOK(const Settings &cfg, double &ratio_out)
  { return LiquidityOK(cfg, _Symbol, ratio_out); }

  // ----------------------------------------------------------------------------
  // News helpers
  // ----------------------------------------------------------------------------
   inline bool NewsBlockedNow(const Settings &cfg, const string sym, const datetime now_srv, int &mins_left)
   {
     mins_left = -1;
     if(!CfgNewsOn(cfg)) return false;
   
     #ifdef NEWSFILTER_AVAILABLE
       const int impact_mask = EffNewsImpactMask(cfg, sym);
       const int pre_m       = EffNewsPreMins(cfg);
       const int post_m      = EffNewsPostMins(cfg);
   
       return News::IsBlocked(now_srv, sym, impact_mask, pre_m, post_m, mins_left);
     #else
       mins_left = 0;
       return false;
     #endif
   }
   
   inline bool NewsBlockedNow(const Settings &cfg, const datetime now_srv, int &mins_left)
   { return NewsBlockedNow(cfg, _Symbol, now_srv, mins_left); }

   inline bool NewsBlockedNow(const Settings &cfg, int &out_mins_left)
   { return NewsBlockedNow(cfg, TimeUtils::NowServer(), out_mins_left); }

   inline bool NewsBlockedNow(const Settings &cfg, const string sym, int &out_mins_left)
   { return NewsBlockedNow(cfg, sym, TimeUtils::NowServer(), out_mins_left); }

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
  { return CheckFull(cfg, _Symbol, reason, minutes_left_news); }

  inline bool CheckFull(const Settings &cfg, const string sym, int &reason, int &minutes_left_news)
   {
     PolicyResult r; ZeroMemory(r);
     if(!EvaluateFull(cfg, sym, r))
     {
       PolicyVetoLog(r); // ✅ guaranteed veto log (throttled)
       reason = r.primary_reason;
       minutes_left_news = r.news_mins_left;
       return false;
     }
   
     // keep your existing debug block, but replace any EffSessionFilter(cfg,_Symbol)
     // with EffSessionFilter(cfg, sym), and NewsBlockedNow(cfg, mins_left) with NewsBlockedNow(cfg, sym, mins_left)
     reason = GATE_OK;
     minutes_left_news = r.news_mins_left;
     return true;
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

  inline bool MaxLossesReachedToday(const Settings &cfg, const string sym)
  {
    #ifdef CFG_HAS_MAX_LOSSES_DAY
      // Config field is compiled in and guarded → safe to use.
      if(cfg.max_losses_day <= 0)
        return false;

      int entries = 0;
      int losses  = 0;
      const long mf = _MagicFilterFromCfg(cfg);
      CountTodayTradesAndLosses(sym, mf, entries, losses);
      return (losses >= cfg.max_losses_day);
    #else
      // Field not compiled in → no daily losses cap.
      return false;
    #endif
  }

  inline bool MaxLossesReachedToday(const Settings &cfg)
   { return MaxLossesReachedToday(cfg, _Symbol); }

  inline bool MaxTradesReachedToday(const Settings &cfg, const string sym)
  {
    #ifdef CFG_HAS_MAX_TRADES_DAY
      // Config field is compiled in and guarded → safe to use.
      if(cfg.max_trades_day <= 0)
        return false;

      int entries = 0;
      int losses  = 0;
      const long mf = _MagicFilterFromCfg(cfg);
      CountTodayTradesAndLosses(sym, mf, entries, losses);
      return (entries >= cfg.max_trades_day);
    #else
      // Field not compiled in → no daily trade-count cap.
      if(false) Print((long)CfgMagicNumber(cfg));
      return false;
    #endif
  }

  inline bool MaxTradesReachedToday(const Settings &cfg)
  { return MaxTradesReachedToday(cfg, _Symbol); }
  
  // ----------------------------------------------------------------------------
  // AllowedByPolicies (legacy ABI) — unified cooldown, no duplicate helpers
  // ----------------------------------------------------------------------------
  // Convenience overload used by Execution/Router paths (chart-symbol)
  inline bool AllowedByPolicies(const Settings &cfg, int &code_out)
  { return AllowedByPolicies(cfg, _Symbol, code_out); }

  inline bool AllowedByPolicies(const Settings &cfg, const string sym, int &code_out)
  {
    #ifdef POLICIES_UNIFY_ALLOWED_WITH_CHECKFULL
      int gr=GATE_OK, mins=0;
      if(!CheckFull(cfg, sym, gr, mins))
      {
        code_out = GateReasonToPolicyCode(gr);
        return false;
      }
      code_out = POLICY_OK;
      return true;
    #else
    
    if(CfgDebugGates(cfg))
    {
      // Session gate
      const bool sessOn = Policies::EffSessionFilter(cfg, sym);
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

    _EnsureLoaded(cfg);
    code_out = POLICY_OK;
    const datetime now_srv = TimeUtils::NowServer();

    // 1) Session window
    if(EffSessionFilter(cfg, sym))
    {
      TimeUtils::SessionContext sc;
      TimeUtils::BuildSessionContext(cfg, now_srv, sc);
      if(!sc.in_window)
      { code_out = POLICY_SESSION_OFF; return false; }
    }

    // 2) News blocks
    if(CfgNewsOn(cfg))
    {
      int mins_left = 0;
      if(NewsBlockedNow(cfg, now_srv, mins_left))
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
    const int spr_pts = (int)MathRound(MarketData::SpreadPoints(sym));
    int cap_pts = EffMaxSpreadPts(cfg, sym);          // honor overrides
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
  #endif
  }

  // Legacy ABI: 3-arg signature; mirrors code_out
  inline bool AllowedByPolicies(const Settings &cfg, int &reason, int &code_out)
  {
    const bool ok = AllowedByPolicies(cfg, code_out);
    reason = code_out;
    return ok;
  }

  inline bool AllowedByPoliciesDiag(const Settings &cfg,
                                    int &policy_code_out,
                                    int &gate_reason_out,
                                    int &aux_out,
                                    string &detail_out)
   {
     PolicyResult r;
     const bool ok = EvaluateFull(cfg, r);
   
     gate_reason_out = r.primary_reason;
     policy_code_out = ok ? POLICY_OK : GateReasonToPolicyCode(r.primary_reason);
   
     if(ok)
     {
       aux_out = 0;
       detail_out = "";
       return true;
     }
   
     // aux_out: something numeric that helps logs without parsing strings
     aux_out = 0;
     if(r.primary_reason == GATE_NEWS)
       aux_out = r.news_mins_left;
     else if(r.primary_reason == GATE_COOLDOWN)
       aux_out = (r.cd_trade_left_sec > r.cd_loss_left_sec ? r.cd_trade_left_sec : r.cd_loss_left_sec);
   
     detail_out = FormatPrimaryVetoDetail(r);
     return false;
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
    ti.ok=false; ti.symbol=""; ti.dir=DIR_BUY; ti.score=0.0; ti.risk_mult=1.0;
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
    
    if(!CheckFull(cfg, symbol, gate_reason, mins_left))
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
    out_intent.symbol = symbol;
    if(n<=0){ gate_reason=GATE_CONFLICT; out_intent.reason=gate_reason; return false; }

    int mins_left=0;
    if(!CheckFull(cfg, symbol, gate_reason, mins_left))
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
