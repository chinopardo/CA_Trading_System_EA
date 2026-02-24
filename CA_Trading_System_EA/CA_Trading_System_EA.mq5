//+------------------------------------------------------------------+
//|                  CA Trading System EA (Core)                     |
//|   Safety gates, session presets, registry router, PM & panel     |
//|   Multi-symbol scheduler (per-symbol last-bar & locks)           |
//|   Profile presets (weights/throttles) + CSV export               |
//|   Regression KPIs export + Golden-run compare                    |
//|   Carry bias integration (strict or mild) + ML blender           |
//|   Confluence blend weights per archetype (Trend/MR/Others)       |
//|   NEW: price/time gates + streak-based lot scaling               |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"   // Cleaned lifecycle; price/time gates; streak lot scaling; bug fixes

// ================= Registry Mode Switch ============================
// Uncomment to enable handle caching for indicators.
// #define CA_USE_HANDLE_REGISTRY
// ==================================================================

// ------------------- Engine & Infra includes ----------------------
#include <Trade/Trade.mqh>
#include "include/Config.mqh"
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

// Persistence & UX
#include "include/State.mqh"      // persistent day cache / last signal context
#include "include/Panel.mqh"
#include "include/Telemetry.mqh"  // HUD/Events CSV/JSON (guarded)
#include "include/ReviewUI.mqh"
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
Router   g_router;     // strategy router / dispatcher
bool     g_inited = false;

//--------------------------------------------------------------------
// Forward declarations for helper functions we add in this file
//--------------------------------------------------------------------
void BuildSettingsFromInputs(Settings &cfg);
string RuntimeSettingsHashHex(const Settings &cfg);
void   DriftAlarm_SetApproved(const string reason);
void   DriftAlarm_Check(const string where);

// Full-detail variant used from OnTick()
void PushICTTelemetryToReviewUI(const ICT_Context &ictCtx,
                                const double       classicalScore,
                                const double       ictScore,
                                const string      &armedName);

// Convenience overload: no scores / armed name
inline void PushICTTelemetryToReviewUI(const ICT_Context &ictCtx)
{
   PushICTTelemetryToReviewUI(ictCtx, 0.0, 0.0, "-");
}

void RefreshICTContext(EAState &st);

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
input double InpQualityThresholdHigh      = 0.72;

// Fine-tuned thresholds for specialized strategies
input double InpQualityThresholdCont      = 0.60;    // continuation / pullback (OB+FVG+OTE)
input double InpQualityThresholdReversal  = 0.65;    // Wyckoff Spring / UTAD style reversals

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

// Loop controls / heartbeat
input bool             InpOnlyNewBar            = true; // Loop controls / heartbeat: Only New Bar - Per-symbol last-bar gate
input int              InpTimerMS               = 150; // Loop controls / heartbeat: Timer MS
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
input double           InpRouterMinScore        = 0.22; // Registry Router & Strategy: Min Score
input int              InpRouterMaxStrats       = 4;   // Registry Router & Strategy: Max Strat

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
// STRAT_MAIN_ONLY  => ONLY MainTradingLogic + ICT/Wyckoff strategies may send orders.
//                     ICT/Wyckoff band is StrategyID [10010..19999] (see Types.mqh Strat_AllowedToTrade()).
//                     All other modules/pack strategies remain confluence-only (no order sending).
// STRAT_PACK_ONLY  => Only non-core pack strategies may send orders.
// STRAT_COMBINED   => All strategies may send orders.
input StrategyMode InpStrat_Mode                = STRAT_MAIN_ONLY; // Strategy Mode: 0=Main, 1=Pack, 2=Combined

// ---- RouterEvaluateAll execution + caps ----
// 0 = best-of-all-symbols (current behavior)
// 1 = per-symbol execution (evaluate each symbol and send eligible entries per symbol)
input int InpRouterExecMode          = 0;  // Router exec mode: 0=best-of-all, 1=per-symbol

// Position caps used by PositionMgmt/Router when "execute more than one" is enabled.
// Per-symbol: >=1 (1 preserves old behavior). Total: 0 = unlimited.
input int InpMaxPositionsPerSymbol   = 1;  // Max open/pending positions per symbol
input int InpMaxPositionsTotal       = 0;  // Max open/pending positions total (0=unlimited)

// Pack strategies runtime registration/trading (Option 2)
// Default OFF (confluence-only) unless explicitly enabled.
input bool InpEnable_PackStrategies          = false; // Allow pack strategies to register/trade in PACK_ONLY / COMBINED
input bool InpDisable_PackStrategies         = false; // Fail-safe hard disable pack strategies (overrides enable)

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

input bool InpEnable_ICT_PO3              = true;
input bool InpEnable_ICT_Continuation     = true;
input bool InpEnable_ICT_WyckoffTurn      = false;

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
input int    InpConf_MinCount       = 1;       // Confluence Gate: Min Count
input double InpConf_MinScore       = 0.35;    // Confluence Gate: Min Score
input bool   InpMain_SequentialGate = false;   // Confluence Gate: Seq Gate
input bool   InpMain_RequireChecklist = true;  // Main: require checklist (disable to prevent trade starvation)
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

input bool   InpExtra_DOMImbalance = false;      // Confluence Gate: DOM Imbalance (MarketBook)
input bool   InpExtra_News = true;              // Confluence Gate: News Filter
input double InpW_News     = 1.00;              // Confluence Gate: News Filter Weight

input bool   InpExtra_SilverBulletTZ = false;
input double InpW_SilverBulletTZ     = 0.06;

input bool   InpExtra_AMD_HTF        = false;
input double InpW_AMD_H1             = 0.06;
input double InpW_AMD_H4             = 0.08;

input bool   InpExtra_PO3_HTF       = false;
input double InpW_PO3_H1            = 0.05;
input double InpW_PO3_H4            = 0.07;

input bool   InpExtra_Wyckoff_Turn  = false;
input double InpW_Wyckoff_Turn      = 0.05;

input bool   InpExtra_MTF_Zones     = false;
input double InpW_MTFZone_H1        = 0.05;
input double InpW_MTFZone_H4        = 0.07;
input double Inp_MTFZone_MaxDistATR = 1.25;

// — Router/Confluence thresholds —
input bool   Inp_EnableHardGate            = false;  // Router/Confluence Threshold: Hard Gate
input double Inp_RouterFallbackMin         = 0.50;  // Router/Confluence Threshold: Fallback acceptance if normal gate rejects
input int    Inp_MinFeaturesMet            = 1;     // Router/Confluence Threshold: Min Feat. Met exclude NewsOK from count

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
input bool   InpAuto_Enable             = false; // Auto: master enable
input int    InpAuto_ScanIntervalSec    = 60;    // Auto: rescan cadence (sec)
input int    InpAuto_ScanLookbackBars   = 320;   // Auto: lookback bars

input bool   InpCF_AutoChart            = false; // Auto: chart patterns confluence
input bool   InpCF_AutoFib              = false; // Auto: harmonic/fib confluence
input bool   InpCF_AutoKeyLevels        = false; // Auto: key levels confluence
input bool   InpCF_AutoVolatility       = false; // Auto: volatility/range confluence

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

input bool   InpAuto_RiskScale_Enable   = false;
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
input int    InpExtra_MinScore     = 1;    // Extra Confluences: Min Needed before entry

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
input int              InpNewsBlockPreMins      = 10;     // News: Block PreMins
input int              InpNewsBlockPostMins     = 10;     // News: Block PostMins
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
input bool             InpVSA_AllowTickVolume    = true;  // VSA: allow tick volume fallback (FX-friendly)
input bool             InpStructure_Enable      = true;  // Feature: Structure Enable
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
input bool             InpUseRegistryRouting    = false; // Registry Routing
input double           InpRegimeThreshold       = 0.55; // Regime Threshold

// --------- Profiles (top-level presets) ----------
input TradingProfile   InpProfileType           = PROF_TREND; // Profile Type: Balanced/Trend/MR/Scalp
input bool             InpProfileApply          = true;   // Profile Type Apply: apply profile weights/throttles + carry + confluence defaults
input bool             InpProfileAllowManual    = true;   // Profile allow manual inputs to override after profile
input bool             InpProfileUseRouterHints = true;   // Profile use router hint's min_score/max_strats
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

// --------- Tester / Optimization ----------
enum TesterScoreMode { TESTER_SCORE_MIX=0, TESTER_SCORE_SHARPE=1, TESTER_SCORE_EXPECT=2 }; // Tester / Optimization: Score
input TesterScoreMode InpTesterScore  = TESTER_SCORE_MIX; // Tester / Optimization: Score Mode
input bool            InpTesterSnapshot = true; // Tester / Optimization: Snapshot
input string          InpTesterNote     = ""; // Tester / Optimization: Note
input string          InpTestCase      = "none";  // see TesterCases::ScenarioList()
input string          InpTesterPreset  = "";

// ================== Globals ==================
//g_cfg = canonical runtime snapshot
//S = UI mirror (read-mostly)
//After init, only OnChartEvent hotkeys may mutate S, and must immediately mirror to g_cfg
Settings S;

static bool g_show_breakdown = true;
static bool g_calm_mode      = false;
static bool g_ml_on          = false;
static bool g_is_tester      = false;   // true only in Strategy Tester / Optimization
static bool g_use_registry = false; // legacy registry routing enabled (tester only)

// ---- Runtime drift alarm (S must match g_cfg; only hotkeys may change S) ----
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

// ================== MarketScannerHub: event-driven routing trigger ==================
#define MSH_DIRTY_MAX 64

static int      g_msh_dirty_n = 0;
static string   g_msh_dirty_sym[MSH_DIRTY_MAX];
static int      g_msh_dirty_tf[MSH_DIRTY_MAX];
static datetime g_msh_dirty_ts[MSH_DIRTY_MAX];

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
}

// Price/time gates state
static bool   g_armed_by_price     = false;
static bool   g_stopped_by_price   = false;
static double g_last_mid_arm       = 0.0;
static double g_last_mid_stop      = 0.0;

// streak state (reset daily by Risk day cache or session start)
static int    g_consec_wins        = 0;
static int    g_consec_losses      = 0;

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
   if(!InpDebug)
      return;

   static datetime last_ts = 0;
   static int last_stage = 0;
   static int last_code = 0;
   static string last_sym = "";

   const datetime now = TimeCurrent();
   if(now==last_ts && stage==last_stage && code==last_code && sym==last_sym)
      return;

   last_ts = now;
   last_stage = stage;
   last_code  = code;
   last_sym   = sym;

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
   const bool in_tester = (MQLInfoInteger(MQL_TESTER) != 0) || (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
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

   // NOTE: This logger expects Exec::Outcome to include: ok, retcode, ticket, last_error, last_error_text.
   // Do not reference ex.code_text / ex.ret_text here unless you confirm they exist in your Exec::Outcome struct.
    PrintFormat("[ExecFail] %s %s retcode=%u err=%d(%s) ticket=%I64d lots=%.2f price=%.5f sl=%.5f tp=%.5f slip=%d",
                sym, side, ex.retcode,
                ex.last_error, LogX::San(ex.last_error_text),
                (long)ex.ticket,
                plan.lots, plan.price, plan.sl, plan.tp, slippage_points);
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
void ApplyRouterConfig()  // manual-input version
  {
   RouterConfig rc = StratReg::GetGlobalRouterConfig();

   if(InpRouterMode==1)
      rc.select_mode = SEL_WEIGHTED;
   else
      if(InpRouterMode==2)
         rc.select_mode = SEL_AB;
      else
         rc.select_mode = SEL_MAX;

   if(InpAB_Bucket==1)
      rc.ab_bucket = (int)AB_A;
   else
      if(InpAB_Bucket==2)
         rc.ab_bucket = (int)AB_B;
      else
         rc.ab_bucket = (int)AB_OFF;

   rc.min_score  = (InpRouterMinScore>0.0? InpRouterMinScore : Const::SCORE_ELIGIBILITY_MIN);
   rc.max_strats = (InpRouterMaxStrats>0 ? InpRouterMaxStrats : 12);

   StratReg::SetGlobalRouterConfig(rc);
   LogX::Info(StringFormat("Router policy=%d (0=max,1=w,2=ab) ab=%d min=%.2f cap=%d",
                           InpRouterMode, InpAB_Bucket, rc.min_score, rc.max_strats));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyRouterConfig_Profile(const Config::ProfileSpec &ps)  // profile-hint version
  {
   RouterConfig rc = StratReg::GetGlobalRouterConfig();

   if(InpRouterMode==1)
      rc.select_mode = SEL_WEIGHTED;
   else
      if(InpRouterMode==2)
         rc.select_mode = SEL_AB;
      else
         rc.select_mode = SEL_MAX;

   if(InpAB_Bucket==1)
      rc.ab_bucket = (int)AB_A;
   else
      if(InpAB_Bucket==2)
         rc.ab_bucket = (int)AB_B;
      else
         rc.ab_bucket = (int)AB_OFF;

   rc.min_score  = (InpProfileUseRouterHints ? ps.min_score  : (InpRouterMinScore>0.0? InpRouterMinScore : Const::SCORE_ELIGIBILITY_MIN));
   rc.max_strats = (InpProfileUseRouterHints ? ps.max_strats : (InpRouterMaxStrats>0 ? InpRouterMaxStrats : 12));

   StratReg::SetGlobalRouterConfig(rc);
   LogX::Info(StringFormat("Router policy=%d (0=max,1=w,2=ab) ab=%d min=%.2f cap=%d [via %s hints=%s]",
                           InpRouterMode, InpAB_Bucket, rc.min_score, rc.max_strats,
                           Config::ProfileName((TradingProfile)InpProfileType),
                           (InpProfileUseRouterHints?"ON":"OFF")));
  }

// ------------------------------------------------------------------
// Forward declarations (defined later in this file)
// ------------------------------------------------------------------
bool   TryMinimalPathIntent(const string sym, const Settings &cfg,
                            StratReg::RoutedPick &pick_out);

double StreakRiskScale();
void   ResetStreakCounters();
bool   AllowStreakScalingNow(const double news_risk_mult, const bool news_skip);

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
void EvaluateOneSymbol(const string sym)
  {
    Settings cur = S; // per-symbol snapshot if you later need overrides
    if(!g_is_tester) return;
   
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
      Panel::Render(S);
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
         
      Panel::Render(S);
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

   Panel::PublishBreakdown(pick.bd);
   Panel::PublishScores(ss);

// 3) Risk sizing → plan
   OrderPlan plan;
   ZeroMemory(plan);
   if(!Risk::ComputeOrder(pick.dir, trade_cfg, ss, plan, pick.bd))
     {
      Panel::Render(S);
      return;
     }

// 3.5) Enforce strat_mode gate (match ProcessSymbol behavior)
   const StrategyID sid = (StrategyID)pick.id;
   if(!Router_GateWinnerByMode(S, sid))
   {
      Panel::Render(S);
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

   Panel::Render(S);
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
    cfg.mode_enforce_killzone = (InpEnforceKillzone ? 1 : 0);
  #endif
  #ifdef CFG_HAS_MODE_USE_ICT_BIAS
    cfg.mode_use_ICT_bias = (InpUseICTBias ? 1 : 0);
  #endif

  cfg.only_new_bar = InpOnlyNewBar; cfg.timer_ms = InpTimerMS;
  cfg.server_offset_min = InpServerOffsetMinutes;

  // ---- Risk core ----
  cfg.risk_pct = InpRiskPct; cfg.risk_cap_pct = InpRiskCapPct;
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
  cfg.news_on = InpNewsOn; cfg.block_pre_m = InpNewsBlockPreMins; cfg.block_post_m = InpNewsBlockPostMins;
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
  cfg.cf_correlation      = InpCF_Correlation;
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
  cfg.extra_min_score  = MathMax(0.0, InpConf_MinScore);

  // ---- Extras toggles + weights ----
  cfg.extra_volume_footprint = InpExtra_VolumeFootprint;
  cfg.w_volume_footprint     = InpW_VolumeFootprint;

  cfg.cf_liquidity       = InpCF_Liquidity;     cfg.w_liquidity    = InpW_Liquidity;
  cfg.cf_vsa_increase    = InpCF_VSAIncrease;   cfg.w_vsa_increase = InpW_VSAIncrease;

  cfg.extra_stochrsi     = InpExtra_StochRSI;   // weight reuses base
  cfg.extra_macd         = InpExtra_MACD;       // weight reuses base
  cfg.extra_adx_regime   = InpExtra_ADXRegime;  cfg.w_adx_regime = InpW_ADXRegime;
  cfg.extra_correlation  = InpExtra_Correlation;// weight reuses base
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
  cfg.vsa_enable = InpVSA_Enable; cfg.vsa_penalty_max = InpVSA_PenaltyMax;
  cfg.structure_enable = InpStructure_Enable; cfg.liquidity_enable = InpLiquidity_Enable;

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

void _LogGateBlocked(const string origin,
                     const string sym,
                     const int reason,
                     const string detail)
  {
   if(!InpDebug)
      return;

   static datetime last_emit = 0;
   const datetime now = TimeCurrent();
   if(now == last_emit)
      return; // one line max per second-tick
   last_emit = now;

   LogX::Info(StringFormat("[WhyNoTrade] origin=%s stage=gate sym=%s reason=%d(%s) detail=%s",
                           origin, sym, reason, _GateReasonStr(reason), detail));
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

// Echo static thresholds once at startup (useful context in logs)
void _LogThresholdsOnce(const Settings &cfg)
  {
   if(!InpDebug)
      return;
   static bool done=false;
   if(done)
      return;
   done=true;

   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   LogX::Info(StringFormat(
                 "[Thresholds] router_min=%.2f max_strats=%d vwap_z_edge=%.2f vwap_z_avoidtrend=%.2f vwap_sigma=%.2f patt_lookback=%d",
                 (rc.min_score>0.0?rc.min_score:Const::SCORE_ELIGIBILITY_MIN),
                 (rc.max_strats>0?rc.max_strats:12),
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

   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   const double min_sc   = (rc.min_score>0.0 ? rc.min_score : Const::SCORE_ELIGIBILITY_MIN);
   const int    cap_top  = (rc.max_strats>0 ? rc.max_strats : 12);

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
   const double min_sc = (InpRouterMinScore>0.0 ? InpRouterMinScore : Const::SCORE_ELIGIBILITY_MIN);

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

// Router path new-bar gate (separate from DebugChecklist IsNewBar)
static datetime g_router_lastBar = 0;

bool IsNewBarRouter(const string sym, const ENUM_TIMEFRAMES tf)
{
   const datetime t0 = iTime(sym, tf, 0);
   if(t0<=0)
      return false;

   if(g_router_lastBar != t0)
   {
      g_router_lastBar = t0;
      return true;
   }
   return false;
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
   g_use_registry = InpUseRegistryRouting;

   // STRAT_MAIN_ONLY must always use RouterEvaluateAll()
   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
      g_use_registry = false;
}

// --- One-eval-per-bar dispatcher (RouterX) ---
void MaybeEvaluate()
  {
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

    if(g_use_registry)
    {
       if(!GateViaPolicies(g_cfg, _Symbol))
         return;

       ProcessSymbol(_Symbol, true);
       return;
    }

   int gate_reason = 0;
   if(!RouterGateOK_Global(_Symbol, g_cfg, now_srv, gate_reason))
      return;
   
   // Ensure State + ICT context are current before router evaluation
   StateOnTickUpdate(g_state);
   RefreshICTContext(g_state);
   ICT_Context ictCtx = StateGetICTContext(g_state);
   
   RouterEvaluateAll(g_router, g_cfg, ictCtx);
  }

//--------------------------------------------------------------------
// BuildSettingsFromInputs()
// Copy ICT / router inputs into the runtime Settings struct (g_cfg).
// This is separate from MirrorInputsToSettings(S) used for S.
//--------------------------------------------------------------------
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
      cfg.newsFilterEnabled = InpNewsOn;        // reuse NewsOn input
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
   cfg.liquidity_enable      = InpLiquidity_Enable;

   // Optional FVG defaults if you added such fields (compile-safe)
   #ifdef CFG_HAS_FVG_MIN_SCORE
      cfg.fvg_min_score = 0.35;
   #endif
   #ifdef CFG_HAS_FVG_MODE
      cfg.fvg_mode = 0;
   #endif

   // --- Session / mode flags (Smart Money runtime gates) ---
   cfg.mode_use_silverbullet =
      (InpEnable_SilverBulletMode && cfg.enable_strat_ict_silverbullet);
   cfg.mode_use_po3          =
      (InpEnable_PO3Mode && cfg.enable_strat_ict_po3);
   cfg.mode_enforce_killzone = InpEnforceKillzone;
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
                                 /*apply_router_hints=*/InpProfileUseRouterHints,
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

   // 7) Normalize exactly once
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
      g_cfg = S; // keep both identical after tester overlay
   }

   // 11) Boot registry from finalized snapshot (MOVE 2471–2475)
   if(InpProfileApply)
      BootRegistry_WithProfile(S, ps);
   else
      BootRegistry_NoProfile(S);

   // 12) Sync router + routing mode flag from finalized snapshot
   StratReg::SyncRouterFromSettings(S);
   UpdateRegistryRoutingFlag();
   DriftAlarm_SetApproved("FinalizeRuntimeSettings");
}

void UI_CommitSettings(const string reason, const bool resync_router=false)
{
   // Recompute derived flags into the UI snapshot (allowed: hotkey mutation)
   SyncRuntimeCfgFlags(S);

   // Mirror UI snapshot into canonical runtime snapshot
   g_cfg = S;

   // If a UI hotkey ever changes routing/mode/enable flags, resync router and routing flag
   if(resync_router)
   {
      StratReg::SyncRouterFromSettings(S);
      UpdateRegistryRoutingFlag();
   }

   if(InpDebug)
      LogX::Info(StringFormat("[UI] Settings committed: %s", reason));
      
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
      "DRIFT_ALARM[%s] Settings drift detected. Only UI hotkeys may mutate S. "
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

//--------------------------------------------------------------------
// PushICTTelemetryToReviewUI()
// Sends contextual state to your panel / telemetry layer so you can
// *see* what the model thinks: Wyckoff phase, bias, killzone, etc.
//--------------------------------------------------------------------
void PushICTTelemetryToReviewUI(const ICT_Context &ictCtx,
                                const double      classicalScore,
                                const double      ictScore,
                                const string     &armedName)
{
   ConfluenceBreakdown bd;
   ZeroMemory(bd);
   StratScore ss;
   ZeroMemory(ss);

   Review::ReviewUI_UpdateICTContext(ictCtx,
                                     bd,
                                     ss,
                                     armedName,
                                     classicalScore,
                                     ictScore);

   #ifdef PANEL_HAS_PUBLISH_FIB_CONTEXT
      Panel::PublishFibContext(ictCtx);
   #endif

   string j = "{";
   j += "\"sym\":\""      + Telemetry::_Esc(_Symbol)           + "\",";
   j += "\"tf\":"         + IntegerToString(Period())          + ",";
   j += "\"ict_score\":"  + DoubleToString(ictScore,3)         + ",";
   j += "\"classical_score\":" + DoubleToString(classicalScore,3) + ",";
   j += "\"armed\":\""    + Telemetry::_Esc(armedName)         + "\"";
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
   g_is_tester = (MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0);

   Sanity::SetDebug(InpDebug);
   LogX::SetMinLevel(InpDebug ? LogX::LVL_DEBUG : LogX::LVL_INFO);
   LogX::EnablePrint(true);
   LogX::EnableCSV(InpFileLog);
   if(InpFileLog)
      LogX::InitAll();
   FinalizeRuntimeSettings();
   Config::LogSettingsWithHash(S, "CFG");

   // --- Routing mode diagnostics (post-FinalizeRuntimeSettings; g_use_registry is final) ---
   if(InpUseRegistryRouting)
   {
      if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
         LogX::Warn("[Routing] Registry routing requested, but forced OFF (STRAT_MAIN_ONLY). Using RouterEvaluateAll().");
      else
         LogX::Info("[Routing] Registry routing ACTIVE (InpUseRegistryRouting=true). Using LEGACY ProcessSymbol/StratReg.");
   }
   else
   {
      LogX::Info("[Routing] RouterEvaluateAll ACTIVE (InpUseRegistryRouting=false).");
   }
   
   LogX::Info(StringFormat("Execution path: %s",
                           (g_use_registry ? "LEGACY ProcessSymbol/StratReg" : "ICT RouterEvaluateAll")));
                        
   #ifdef CA_USE_HANDLE_REGISTRY
      HR::Init();
      LogX::Info("Indicators mode: registry-cached (HandleRegistry active).");
   #else
      LogX::Info("Indicators mode: ephemeral handles (create/copy/release per call).");
   #endif
   News::ConfigureFromEA(S);
   OBI::Settings obi;
   obi.enabled = S.extra_dom_imbalance;
   OBI::EnsureSubscribed(_Symbol, obi);
   VSA::SetAllowTickVolume(InpVSA_AllowTickVolume);
   
   {
     const StrategyMode sm = Config::CfgStrategyMode(S);
     LogX::Info(StringFormat("StrategyMode = %s (%d)",
                             StrategyModeNameLocal(sm), (int)sm));
   }

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
   Panel::Init(S);
   Panel::ShowBreakdown(g_show_breakdown);
   Panel::SetCalmMode(g_calm_mode);
   Review::EnableScreenshots(InpReviewScreenshots, InpReviewSS_W, InpReviewSS_H);

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
   for(int i=0;i<g_symCount;i++)
      g_lastBarTime[i]=0;

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
      Telemetry::SetHUDBarGuardTF(S.tf_entry);  // emit HUD/snapshots once per new bar on entry TF
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
   //g_cfg.tf_entry = S.tf_entry;
   //g_cfg.tf_h1 = S.tf_h1;
   //g_cfg.tf_h4 = S.tf_h4;
   //g_cfg.tf_d1 = S.tf_d1;

   // 2. Initialize State (pair with router config)
   StateInit(g_state, g_cfg);

   MarketData::EnsureWarmup_ADX(_Symbol, g_cfg.tf_entry, g_cfg.adx_period, 1);
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Policies::CfgCorrTF(S);
   int            lb = Policies::CfgCorrLookback(S);
   MarketData::EnsureWarmup_CorrReturns(_Symbol, tf, lb, 1);

   // 3. Initialize Router strategies registry (ICT-aware)
   RouterInit(g_router, g_cfg);
   RouterSetWatchlist(g_router, g_symbols, g_symCount);
   
   // Prime MarketData caches once after watchlist is finalized (enables AutoVol warm builds)
   MarketData::OnTimerRefresh();
   
   // Scanner hub init: owns AutoC + Scan orchestration + timer
   MSH::HubOptions hub_opt;
   MSH::OptionsDefault(hub_opt);
   
   // Preserve current EA behavior: seconds timer derived from S.timer_ms
   hub_opt.use_ms_timer = false;
   hub_opt.timer_sec    = MathMax(1, (S.timer_ms <= 1000 ? 1 : S.timer_ms / 1000));
   
   // Universe cap (Hub has hard cap HUB_MAX_SYMBOLS)
   hub_opt.max_symbols  = MathMin(g_symCount, (int)MSH::HUB_MAX_SYMBOLS);
   
   // Keep hub passive initially
   hub_opt.log_events   = false;
   hub_opt.log_summary  = false;
   
   // Preserve existing OnTimer behavior: MarketData refresh is done on timer
   hub_opt.call_marketdata_refresh = true;
   
   // Avoid behavior change: EA did not call AutoVol timer here
   hub_opt.call_autovol_timer = false;
   
   if(!MSH::InitWithSymbols(S, hub_opt, g_symbols, g_symCount))
      return(INIT_FAILED);

   // 4. Initial ICT/Wyckoff context so panel not blank
   RefreshICTContext(g_state);
   PushICTTelemetryToReviewUI(StateGetICTContext(g_state));

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
   
   Telemetry_LogInit("CA_Trading_System_EA initialized.");

   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
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
      Panel::Render(S);
      return;
   }

   // Hard guarantee: STRAT_MAIN_ONLY always routes via RouterEvaluateAll()
   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
       g_use_registry = false;
       
   if(InpOnlyNewBar)
    {
       const Settings gate_cfg = (g_use_registry ? S : g_cfg);
       const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(gate_cfg);

       // Router mode must not depend on chart symbol; use a stable watchlist reference.
       const string gate_sym = (g_use_registry ? _Symbol : (g_symCount > 0 ? g_symbols[0] : _Symbol));

       if(!IsNewBarRouter(gate_sym, tf))
       {
          Panel::Render(S);
          return;
       }
    }
     
   static datetime _hb_last_bar = 0;
   const datetime _bar_time = iTime(_Symbol, g_cfg.tf_entry, 0);
   if(_bar_time != _hb_last_bar)
   {
     _hb_last_bar = _bar_time;
     if(InpDebug)
     {
        PrintFormat("[HB] %s M%d new bar %s",
                    _Symbol, (int)(PeriodSeconds(S.tf_entry)/60),
                    TimeToString(_bar_time, TIME_DATE|TIME_MINUTES));
     }
   }
   // Centralized router eval (legacy path) – disabled; RouterEvaluateAll() now owns ICT flow.
   // if(!g_use_registry)
   //    MaybeEvaluate();
   const bool single_symbol = (g_symCount<=1) || (g_symbols[0]==_Symbol && g_symCount==1);

   // Upstream truth: update State + ICT context BEFORE any strategy evaluation
   StateOnTickUpdate(g_state);
   RefreshICTContext(g_state);
   // Autochartist scanning is timer-driven (OnTimer). Do not scan here to avoid double-ups.
   ICT_Context ictCtx = StateGetICTContext(g_state);
   
   // When registry routing is ON, keep using ProcessSymbol() path.
   if(g_use_registry)
     {
      if(single_symbol)
        {
         const bool newbar = (S.only_new_bar ? NewBarFor(_Symbol, S.tf_entry) : true);
         // Existing per-symbol processing
         ProcessSymbol(_Symbol, newbar);
        }
      else
        {
         // Multi-symbol: Process every symbol as before.
         for(int i=0;i<g_symCount;i++)
           {
            const string sym   = g_symbols[i];
            const bool   newbar = (S.only_new_bar ? NewBarFor(sym, S.tf_entry) : true);
            ProcessSymbol(sym, newbar);
           }

         if(InpOnlyNewBar && !IsNewBar(_Symbol, InpEntryTF))
            return;
         } // end else (multi-symbol)
   } // end if(g_use_registry)
   
   // Router mode still needs position management every tick (safer than relying on timer only)
   PM::ManageAll(S);

   // 1. Refresh low-level market data into State.
   //    This should update things like:
   //    - g_state.bid / g_state.ask
   //    - volume/Delta (DeltaProxy)
   //    - pivots / ADR / VWAP / spreads
   //    - absorption flags (absorptionBull/absorptionBear)
   //    - emaFastHTF / emaSlowHTF

   // 3.1 Pull scores from confluence layer
   #ifdef HAS_CONFLUENCE_API
      double classicalScore = Confluence_GetLastClassicalScore();
      double ictScore       = Confluence_GetLastICTScore();
   #else
      double classicalScore = 0.0;
      double ictScore       = 0.0;
   #endif

   // 3.2 Query which strat is currently armed (last eligible)
   string armedName = "-";
   #ifdef ROUTER_HAS_LAST_ARMED_NAME
      armedName = RouterGetLastArmedName(g_router);
   #endif

   // 3.3 Push to the UI
   PushICTTelemetryToReviewUI(ictCtx, classicalScore, ictScore, armedName);

   if(!g_use_registry)
   {
   // 5. Dispatch strategies via router (ICT-aware path)
   //    - Telemetry is always updated (above).
   //    - Actual routing / order planning only runs if all gates are OK.
      int router_gate_reason = 0;
      const datetime now_srv = TimeUtils::NowServer();
      if(!WarmupGateOK())
      {
         // WarmupGateOK emits a throttled breadcrumb in InpDebug mode.
      }
      else
      {
         if(RouterGateOK_Global(_Symbol, g_cfg, now_srv, router_gate_reason))
         {
            RouterEvaluateAll(g_router, g_cfg, ictCtx);
         }
         else
         {
            if(InpDebug)
            {
               static datetime last_emit = 0;
               datetime now = TimeCurrent();
               if(now != last_emit)
               {
                  last_emit = now;
                  PrintFormat("[Router] Skipping RouterEvaluateAll; gate_reason=%d(%s)",
                              router_gate_reason, _GateReasonStr(router_gate_reason));
                  TraceNoTrade(_Symbol, TS_GATE, router_gate_reason,
                               StringFormat("RouterGateOK=false (%s)", _GateReasonStr(router_gate_reason)));
               }
            }
         }
      }
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
void OnDeinit(const int reason)
  {
   MSH::Deinit();
   Exec::Deinit();
   MarketData::Deinit();
   Panel::Deinit();
   #ifdef REVIEWUI_HAS_ICT_DEINIT
      ReviewUI_ICT_Deinit();   // optional, cleans labels
   #endif
   
   // Your cleanup / panel teardown / file flush logic.
   ReviewUI_Deinit();
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
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      TesterX::PrintSummary();
      
   return;
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now_srv = TimeUtils::NowServer();
   MSH::HubTimerTick(S);
   // MarketData::OnTimerRefresh(); // already done inside MSH::HubTimerTick(S)
   // AutoC::OnTimerScan(S, now_srv); // already done inside MSH::HubTimerTick(S)
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
   Panel::Render(S);
   MaybeResetStreaksDaily(now_srv);

   DriftAlarm_Check("OnTimer");
   if(InpOnlyNewBar)
   {
      // Allow timer-driven routing ONCE per bar (fixes sparse-tick stalls).
      const bool use_reg = (g_use_registry && g_cfg.strat_mode != STRAT_MAIN_ONLY);
      const Settings gate_cfg = (use_reg ? S : g_cfg);
      const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(gate_cfg);
   
      // Router mode should use a stable watchlist reference; registry mode uses chart symbol.
      const string gate_sym = (use_reg ? _Symbol : (g_symCount > 0 ? g_symbols[0] : _Symbol));
   
      if(!IsNewBarRouter(gate_sym, tf))
         return;
   }

   // Hard guarantee: STRAT_MAIN_ONLY always routes via RouterEvaluateAll()
   if(g_cfg.strat_mode == STRAT_MAIN_ONLY)
      g_use_registry = false;

   // Respect the chosen execution path (registry vs router) to avoid double-firing.
   if(g_use_registry)
   {
      if(!InpOnlyNewBar && g_msh_dirty_n <= 0)
         return;
      
      if(InpOnlyNewBar && g_msh_dirty_n <= 0)
      {
         const bool nb0 = (S.only_new_bar ? NewBarFor(_Symbol, S.tf_entry) : true);
         ProcessSymbol(_Symbol, nb0);
         MSH_DirtyClear();
         return;
      }

      for(int i=0; i<g_symCount; i++)
      {
         const string sym = g_symbols[i];
         if(!MSH_DirtyHasSym(sym))
            continue;
         const bool nb = (S.only_new_bar ? NewBarFor(sym, S.tf_entry) : true);
         ProcessSymbol(sym, nb);
      }
      MSH_DirtyClear();
      return;
   }   
   // Legacy centralized router eval on timer – disabled.
   // if(!g_use_registry)
   //    MaybeEvaluate();
   
   // If ticks are sparse, allow timer-driven router eval (watchlist-safe)
   int gate_reason = 0;
   
   // Router mode path (ICT RouterEvaluateAll)
   if(!WarmupGateOK())
   {
      TraceNoTrade(_Symbol, TS_GATE, GATE_WARMUP, "OnTimer blocked: WarmupGateOK=false");
      return;
   }
   
   if(!InpOnlyNewBar && g_msh_dirty_n <= 0)
      return;
   
   if(RouterGateOK_Global(_Symbol, g_cfg, now_srv, gate_reason))
   {
      StateOnTickUpdate(g_state);
      RefreshICTContext(g_state);
      ICT_Context ictCtx = StateGetICTContext(g_state);
      RouterEvaluateAll(g_router, g_cfg, ictCtx);
      MSH_DirtyClear();
   }
   else
   {
      if(InpDebug)
      {
         static datetime last_emit = 0;
         datetime now = TimeCurrent();
         if(now != last_emit)
         {
            last_emit = now;
            PrintFormat("[Router][Timer] Skipping RouterEvaluateAll; gate_reason=%d(%s)",
                        gate_reason, _GateReasonStr(gate_reason));
            TraceNoTrade(_Symbol, TS_GATE, gate_reason,
                         StringFormat("RouterGateOK=false (%s) [timer]", _GateReasonStr(gate_reason)));
         }
      }
   }
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
   
      // Force a MAIN_ONLY view of the world, but route via registry
      Settings cfg_core = cfg;
      Config::ApplyStrategyMode(cfg_core, STRAT_MAIN_ONLY);
      Config::Normalize(cfg_core);
   
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

   // --- Minimal Trading Path (MVP): intent → risk → execute ---
   bool TryMinimalPathIntent(const string sym,
                             const Settings &cfg,
                             StratReg::RoutedPick &pick_out)
     {
   
   ZeroMemory(pick_out);

   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   const double min_sc = (rc.min_score>0.0 ? rc.min_score : Const::SCORE_ELIGIBILITY_MIN);
   
   const StrategyMode sm = Config::CfgStrategyMode(cfg);
   bool okRoute = false;
   
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
            const bool main_valid =
               (!main_pick.bd.veto && main_pick.ss.eligible && main_pick.ss.score >= min_sc);
   
            if(main_valid)
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
         okRoute = (StratReg::Route(cfg_pack, pick_out) && pick_out.ok);
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
   
   // Allowlist should be enforced ONLY in StrategyRegistry + Router + Execution.
   // If we ever see a disallowed/invalid sid here, it is a wiring leak; log loudly.
   if(okRoute)
   {
      const StrategyID sid = (StrategyID)pick_out.id;
      if(((int)sid) <= 0 || !Config::IsStrategyAllowedInMode(cfg, sid))
      {
         _LogCandidateDrop("allowlist_leak", pick_out.id, pick_out.dir, pick_out.ss, pick_out.bd, min_sc);
         if(InpDebug)
            LogX::Warn(StringFormat("[ALLOWLIST_LEAK] mode=%s sid=%d pick_id=%d (should be filtered upstream; Execution will hard-reject)",
                                    StrategyModeNameLocal(cfg.strat_mode), (int)sid, (int)pick_out.id));
         // Do NOT return false here.
      }
   }

   if(pick_out.bd.veto || !pick_out.ss.eligible || pick_out.ss.score < min_sc)
   {
      _LogCandidateDrop("intent_reject", pick_out.id, pick_out.dir, pick_out.ss, pick_out.bd, min_sc);
      return false;
   }
   
   // Normal UI hooks
   Panel::PublishBreakdown(pick_out.bd);
   Panel::PublishScores(pick_out.ss);
   
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
      if(Policies::SizingResetActive())
         return false;
   #endif

   if(!InpResetStreakOnNewsDerisk)
      return true;

   if(news_skip)
      return false;

   if(news_risk_mult < 1.0)
      return false;

   return true;
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
   cfg.mode_enforce_killzone = InpEnforceKillzone;
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
      Panel::SetGate(GATE_INHIBIT);
      _LogGateBlocked("policies_gate", sym, GATE_INHIBIT, "Trading inhibited (drift alarm)");
      TraceNoTrade(sym, TS_GATE, GATE_INHIBIT, "Trading inhibited (drift alarm)");
      return false;
   }

   int pol_reason = 0;
   if(!Policies::Check(cfg, pol_reason))
   {
      Panel::SetGate(GATE_POLICIES);
      _LogGateBlocked("policies_gate", sym, GATE_POLICIES,
                      StringFormat("Policies::Check failed (pol_reason=%d)", pol_reason));
      TraceNoTrade(sym, TS_GATE, GATE_POLICIES,
                   StringFormat("Policies::Check failed (pol_reason=%d)", pol_reason));
      return false;
   }
   return true;
}

// -------- Trade environment gate (prevents pointless routing when trading is disabled) --------
bool TradeEnvGateOK(const string sym, int &gate_reason_out)
{
   gate_reason_out = 0;

   const bool in_tester = (MQLInfoInteger(MQL_TESTER) != 0) || (MQLInfoInteger(MQL_OPTIMIZATION) != 0);

   const bool acc_ok  = (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0);
   const bool mql_ok  = (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   const bool term_ok = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0);

   // In tester/optimization, ignore terminal "Algo Trading" toggles; in live, require them.
   if(!acc_ok || (!in_tester && (!mql_ok || !term_ok)))
   {
      gate_reason_out = GATE_TRADE_DISABLED;
      Panel::SetGate(gate_reason_out);

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
      Panel::SetGate(gate_reason_out);
   
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
      Panel::SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "Trading inhibited (drift alarm)");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "Trading inhibited (drift alarm)");
      return false;
   }

   if(!TradeEnvGateOK(log_sym, gate_reason_out))
      return false;
   
   // 1) Global policy/risk guard (DD, cooldown, etc.)
   int pol_reason = 0;
   if(!Policies::Check(cfg, pol_reason))
   {
      gate_reason_out = GATE_POLICIES;
      Panel::SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out,
                      StringFormat("Policies::Check failed (pol_reason=%d)", pol_reason));
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out,
                   StringFormat("Policies::Check failed (pol_reason=%d)", pol_reason));
      return false;
   }

   // 2) Hard time window (start/expiry)
   if(!TimeGateOK(now_srv))
   {
      gate_reason_out = GATE_TIMEWINDOW;
      Panel::SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "TimeGateOK blocked");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "TimeGateOK=false (start/expiry window)");
      return false;
   }

   // 3) Price gates (arm + stop) are truly global
   if(!PriceArmOK())
   {
      gate_reason_out = GATE_PRICE_ARM;
      Panel::SetGate(gate_reason_out);

      _LogGateBlocked("router_gate_global", log_sym, gate_reason_out, "PriceArmOK not armed");
      TraceNoTrade(log_sym, TS_GATE, gate_reason_out, "PriceArmOK=false (InpTradeAtPrice not armed?)");
      return false;
   }

   if(g_stopped_by_price)
   {
      gate_reason_out = GATE_PRICE_STOP;
      Panel::SetGate(gate_reason_out);

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
      Panel::SetGate(gate_reason_out);
   
      _LogGateBlocked("router_gate", sym, gate_reason_out, "Trading inhibited (drift alarm)");
      TraceNoTrade(sym, TS_GATE, gate_reason_out, "Trading inhibited (drift alarm)");
      return false;
   }

   if(!TradeEnvGateOK(sym, gate_reason_out))
      return false;
   
   // 1) Policy / risk guard (DD, spread, cooldown, etc.)
   int pol_reason = 0;
   if(!Policies::Check(cfg, pol_reason))
   {
      gate_reason_out = GATE_POLICIES;
      Panel::SetGate(gate_reason_out);

      _LogGateBlocked("router_gate", sym, gate_reason_out,
                      StringFormat("Policies::Check failed (pol_reason=%d)", pol_reason));

      TraceNoTrade(sym, TS_GATE, gate_reason_out,
                   StringFormat("Policies::Check failed (pol_reason=%d)", pol_reason));

      return false;
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
            Panel::SetGate(gate_reason_out);
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
      Panel::SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "TimeGateOK blocked");
      TraceNoTrade(sym, TS_GATE, GATE_TIMEWINDOW, "TimeGateOK=false (start/expiry window)");
      return false;
   }

   // 4) Price gates (arm + stop)
   if(!PriceArmOK())
   {
      gate_reason_out = GATE_PRICE_ARM;
      Panel::SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "PriceArmOK not armed");
      TraceNoTrade(sym, TS_GATE, GATE_PRICE_ARM, "PriceArmOK=false (InpTradeAtPrice not armed?)");
      return false;
   }

   if(g_stopped_by_price)
   {
      gate_reason_out = GATE_PRICE_STOP;
      Panel::SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "Stopped by price stop gate");
      TraceNoTrade(sym, TS_GATE, GATE_PRICE_STOP, "Stopped by price gate (InpStopAtPrice hit)");
      return false;
   }
      
   // 5) News hard block (uses cfg.* copied from inputs into g_cfg)
   if(cfg.news_on)
   {
      int mins_left = 0;
      if(News::IsBlocked(now_srv, sym, cfg.news_impact_mask, cfg.block_pre_m, cfg.block_post_m, mins_left))
      {
         gate_reason_out = GATE_NEWS;
         Panel::SetGate(gate_reason_out);
         _LogGateBlocked("router_gate", sym, gate_reason_out,
                         StringFormat("News hard block (%d mins left)", mins_left));
         TraceNoTrade(sym, TS_GATE, GATE_NEWS,
                      StringFormat("News blocked (%d mins left)", mins_left));
         return false;
      }
   }

   // 6) Execution lock (async send guard)
   if(Exec::IsLocked(sym))
   {
      gate_reason_out = GATE_EXEC_LOCK;
      Panel::SetGate(gate_reason_out);
      _LogGateBlocked("router_gate", sym, gate_reason_out, "Exec lock active");
      TraceNoTrade(sym, TS_GATE, GATE_EXEC_LOCK, "Exec::IsLocked=true (async send guard)");
      return false;
   }

   return true;
}

// Per-symbol processing unit (PM + gates + MVP pipeline)
void ProcessSymbol(const string sym, const bool new_bar_for_sym)
  {
   // 0) Unified warmup gate (single source of truth)
   if(!WarmupGateOK())
   {
      TraceNoTrade(sym, TS_GATE, GATE_WARMUP, "ProcessSymbol blocked: WarmupGateOK=false");
      PM::ManageAll(S);
      Panel::Render(S);
      return;
   }

   // Always keep managing open positions (even if we skip evaluation)
   PM::ManageAll(S);

   if(g_inhibit_trading)
   {
      Panel::SetGate(GATE_INHIBIT);
      TraceNoTrade(sym, TS_GATE, GATE_INHIBIT, "ProcessSymbol blocked: trading inhibited (drift alarm)");
      Panel::Render(S);
      return;
   }

   // Safety: in LIVE, ProcessSymbol() is allowed only when registry routing is explicitly enabled.
   if(!g_is_tester && !g_use_registry)
   {
      if(InpDebug) LogX::Warn("[LEGACY] ProcessSymbol blocked in LIVE (registry routing is OFF).");
      return;
   }

   // NOTE: current strategies rely on _Symbol internally; only evaluate on chart symbol.
   if(sym != _Symbol)
   {
      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_NO_INTENT, "sym != _Symbol; evaluation skipped");
      Panel::Render(S);
      return;
   }

   // 1) Unified gate wrapper (Policies/Session/Time/Price/News/ExecLock)
   int gate_reason = 0;
   const datetime now_srv = TimeUtils::NowServer();
   if(!RouterGateOK(sym, S, now_srv, gate_reason))
   {
      // RouterGateOK will breadcrumb; this keeps ProcessSymbol consistent too
      TraceNoTrade(sym, TS_GATE, gate_reason,
                   StringFormat("RouterGateOK=false (%s)", _GateReasonStr(gate_reason)));
      Panel::Render(S);
      return;
   }

   // Clear the gate indicator when we pass all gates
   Panel::SetGate(GATE_NONE);

   // 2) Policies::Evaluate (or router fallback) → intent/pick
   StratReg::RoutedPick pick;
   ZeroMemory(pick);
   if(!TryMinimalPathIntent(sym, S, pick))
     {
      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_NO_INTENT,
             "TryMinimalPathIntent=false (no eligible pick/intent)");
      Panel::Render(S);
      return;
     }

   // Drop ineligible / under-threshold picks (prevents the RET_UNSPEC spam)
   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   const double min_sc = (rc.min_score>0.0 ? rc.min_score : Const::SCORE_ELIGIBILITY_MIN);
   if(!pick.ss.eligible || pick.ss.score < min_sc)
     {
      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_PICK_DROP,
             StringFormat("intent_drop: eligible=%d score=%.3f min=%.2f veto=%d",
                          (int)pick.ss.eligible, pick.ss.score, min_sc, (int)pick.bd.veto),
             (int)pick.id, pick.dir, pick.ss.score);
      _LogCandidateDrop("intent_drop", pick.id, pick.dir, pick.ss, pick.bd, min_sc);
      PM::ManageAll(S);
      Panel::Render(S);
      return;
     }

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
      Panel::Render(S);
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
   
   OrderPlan plan;
   const StrategyID sid = (StrategyID)pick.id;
   
   if(!Risk::ComputeOrder(pick.dir, trade_cfg, SS, plan, pick.bd))
   {
      _LogRiskReject("risk_reject", sym, sid, pick.dir, SS);
      Panel::Render(S);
      return;
   }
   
   // Enforcement point #2 (Router gate) even for legacy harness
   if(!Router_GateWinnerByMode(S, sid))
   {
      TraceNoTrade(sym, TS_ROUTER, TR_ROUTER_MODE_BLOCK,
                   StringFormat("[LEGACY] Router gate blocked sid=%d mode=%s",
                                (int)sid, StrategyModeNameLocal(S.strat_mode)),
                   (int)sid, pick.dir, pick.ss.score);
      Panel::Render(S);
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

   Panel::Render(S);
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
   Review::OnTx(tx, rs);
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

// Menu / Hotkeys: B=Breakdown, C=Calm, M=ML, R=Routing, N=News, T=ResumeTrading, P=Screenshot, H=Benchmark
int  KeyCodeFromEvent(const long lparam) { return (int)lparam; }
void OnChartEvent(const int id, const long &lparam, const double &/*dparam*/, const string &/*sparam*/)
  {
   if(id!=CHARTEVENT_KEYDOWN)
      return;
   int K=(int)lparam;
   if(K>='a' && K<='z')
      K = 'A' + (K - 'a');

   if(K=='B')
     {
      g_show_breakdown=!g_show_breakdown;
      Panel::ShowBreakdown(g_show_breakdown);
      PrintFormat("[UI] Breakdown %s",(g_show_breakdown?"ON":"OFF"));
     }
   else
      if(K=='C')
        {
         g_calm_mode=!g_calm_mode;
         Panel::SetCalmMode(g_calm_mode);
         PrintFormat("[UI] Calm mode %s",(g_calm_mode?"ON":"OFF"));
        }
      else
         if(K=='M')
           {
            g_ml_on=!g_ml_on;
            ML::SetRuntimeOn(g_ml_on);
            PrintFormat("[UI] ML blender %s  %s",(g_ml_on?"ON":"OFF"), ML::StateString());
           }
         else
            if(K=='R')
            {
               if(!g_is_tester)
               {
                  // LIVE: routing is controlled by the input flag and finalized settings; do not toggle here.
                  PrintFormat("[UI] Routing (LIVE): %s (controlled by InpUseRegistryRouting=%s)",
                              (g_use_registry ? "REGISTRY" : "ROUTER"),
                              (InpUseRegistryRouting ? "true" : "false"));
               }
               else if(S.strat_mode == STRAT_MAIN_ONLY)
               {
                  g_use_registry = false;
                  PrintFormat("[UI] Routing locked to ROUTER in STRAT_MAIN_ONLY");
               }
               else
               {
                  g_use_registry = !g_use_registry;
                  PrintFormat("[UI] Routing: %s", (g_use_registry ? "REGISTRY (tester)" : "ROUTER"));
               }
            }
            else
               if(K=='N')
                 {
                  S.news_on = !S.news_on;
                  UI_CommitSettings("hotkey N: news_on", false);
                  PrintFormat("[HOTKEY] News hard-block: %s", (S.news_on ? "ON" : "OFF"));
                 }
                               else
                   if(K=='T')
                     {
                      if(!g_inhibit_trading)
                        {
                         PrintFormat("[HOTKEY] Trading already enabled (no inhibit active).");
                        }
                      else
                        {
                         const string hs = RuntimeSettingsHashHex(S);
                         const string hc = RuntimeSettingsHashHex(g_cfg);

                         // Safety: do NOT resume if drift is still present
                         if(hs != hc)
                           {
                            string msg = StringFormat("[HOTKEY] Resume blocked: drift still present (S_hash=%s g_cfg_hash=%s). Fix drift source first.", hs, hc);
                            Print(msg);
                            LogX::Error(msg);
                           }
                         else
                           {
                            g_inhibit_trading = false;
                            Panel::SetGate(GATE_NONE);

                            // Re-approve baseline so DriftAlarm doesn't immediately re-fire after manual resume
                            DriftAlarm_SetApproved("hotkey T: resume (operator override)");

                            string msg = "[HOTKEY] WARNING: Trading resumed by operator after drift inhibit. Confirm drift source is resolved.";
                            Print(msg);
                            LogX::Warn(msg);
                           }
                        }
                     }
                else
                  if(K=='P')
                    {
                     Review::Screenshot("CAEA_Snapshot");
                    }
                  else
                     if(K=='H')
                       {
                        RunIndicatorBenchmarks();
                       }

   Panel::Render(S);
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