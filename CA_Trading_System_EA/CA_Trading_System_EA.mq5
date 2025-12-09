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
#include "include/LiquidityCues.mqh"
#include "include/RegimeCorr.mqh"
#include "include/NewsFilter.mqh"
#define CONFLUENCE_API_BYNAME
//#define UNIT_TEST_ROUTER_GATE
#include "include/Confluence.mqh"      // <-- Must come before strategies

// Optional meta-layers
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

#ifndef ROUTER_TRACE_FLOW
#define ROUTER_TRACE_FLOW 0   // set to 1 to enable #F breadcrumbs
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

// -------- Strategy ID compatibility shims (keep last among includes) -------
#ifndef STRAT_TREND_VWAP
#define STRAT_TREND_VWAP (StrategyID)0
#endif
#ifndef STRAT_MR_VWAPBAND
#define STRAT_MR_VWAPBAND STRAT_TREND_VWAP
#endif
#ifndef ST_SQUEEZE_ID
#define ST_SQUEEZE_ID (int)STRAT_TREND_VWAP
#endif
#ifndef STRAT_TREND_BOSCONTINUATION
#define STRAT_TREND_BOSCONTINUATION STRAT_TREND_VWAP
#endif
#ifndef STRAT_BREAKOUT_ORB
#define STRAT_BREAKOUT_ORB STRAT_TREND_VWAP
#endif
#ifndef ST_RANGENR7IB_ID
#define ST_RANGENR7IB_ID STRAT_MR_VWAPBAND
#endif
#ifndef ST_SWEEPCHOCH_ID
#define ST_SWEEPCHOCH_ID STRAT_MR_VWAPBAND
#endif
#ifndef ST_VSACLIMAXFADE_ID
#define ST_VSACLIMAXFADE_ID STRAT_MR_VWAPBAND
#endif
#ifndef ST_CORRDIV_ID
#define ST_CORRDIV_ID STRAT_TREND_VWAP
#endif
#ifndef ST_PAIRSLITE_ID
#define ST_PAIRSLITE_ID STRAT_TREND_VWAP
#endif
#ifndef ST_NEWS_DEV_ID
#define ST_NEWS_DEV_ID STRAT_TREND_VWAP
#endif
#ifndef ST_NEWS_POSTFADE_ID
#define ST_NEWS_POSTFADE_ID STRAT_TREND_VWAP
#endif

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
input ENUM_TIMEFRAMES InpTfEntry          = PERIOD_M15; // ICT: Entry TF
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
input Config::DirectionBiasMode InpDirectionBiasMode = Config::DIRM_AUTO_SMARTMONEY;

// Risk core
input double           InpRiskPct               = 0.40; // Risk Percentage
input double           InpRiskCapPct            = 1.00; // Risk Cap Percentage
input double           InpMinSL_Pips            = 10.0; // Min SL (Pips)
input double           InpMinTP_Pips            = 15.0; // Min TP (Pips)
input double           InpMaxSLCeiling_Pips     = 2500.0; // Max Ceiling (Pips)
input double           InpMaxDailyDD_Pct        = 2.0; // Max Daily DD Percentage
input double           InpDayDD_LimitPct        = 2.0; // Max Daily DD taper onset (%); scales risk down from here
input int              InpMaxLossesDay          = 4; // Max Daily Losses
input int              InpMaxTradesDay          = 10; // Max Daily Trades
input int              InpMaxSpreadPoints       = 100; // Max Spread Points
input int              InpSlippagePoints        = 100; // Max Slippage Points

// Loop controls / heartbeat
input bool             InpOnlyNewBar            = true; // Loop controls / heartbeat: Only New Bar - Per-symbol last-bar gate
input int              InpTimerMS               = 150; // Loop controls / heartbeat: Timer MS
input int              InpServerOffsetMinutes   = 0; // Loop controls / heartbeat: Server Offset Mins

// -------- Session windows (UTC minutes) — legacy union (London/NY) --------
input bool             InpSessionFilter         = true; // Sessions: Filter Enable
input SessionPreset    InpSessionPreset         = SESS_TOKYO_C3_TO_NY_CLOSE; // Sessions: Preset
input int              InpLondonOpenUTC         = 7*60; // Sessions: Ldn Open UTC Time
input int              InpLondonCloseUTC        = 11*60; // Sessions: Ldn Close UTC Time
input int              InpNYOpenUTC             = 12*60 + 30; // Sessions: NY Open UTC Time
input int              InpNYCloseUTC            = 16*60; // Sessions: NY Close UTC Time
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

// -------- Registry Router & Strategy knobs --------
input int              InpRouterMode            = 0;    // Registry Router & Strategy: Mode - 0=MAX,1=WEIGHTED,2=AB
input int              InpAB_Bucket             = 0;    // Registry Router & Strategy: AB_Bucket - 0=OFF,1=A,2=B
input double           InpRouterMinScore        = 0.60; // Registry Router & Strategy: Min Score
input int              InpRouterMaxStrats       = 2;   // Registry Router & Strategy: Max Strat

// Position management
input bool             InpBE_Enable             = true;  // Position Mgnt: BE Enable
input double           InpBE_At_R               = 0.80;  // Position Mgnt: BE ATR
input double           InpBE_Lock_Pips          = 2.0;   // Position Mgnt: BE Lock pips

input TrailType        InpTrailType             = TRAIL_ATR;   // Position Mgnt: Trail Type - 0=None 1=Fixed 2=ATR 3=PSAR
input double           InpTrailPips             = 10.0;          // Position Mgnt: Trail Pips
input double           InpTrailATR_Mult         = 1.7;           // Position Mgnt: Trail ATR Mult

input bool             InpPartial_Enable        = true;          // Position Mgnt: Partial TP Enable
input double           InpP1_At_R               = 1.50;           // Position Mgnt: Partial 1 TP ATR
input double           InpP1_ClosePct           = 50.0;          // Position Mgnt: Partial 1 Close Pct
input double           InpP2_At_R               = 3.00;           // Position Mgnt: Partial 2 TP ATR
input double           InpP2_ClosePct           = 25.0;          // Position Mgnt: Partial 2 Close Pct

// ================= Strategy family selector =================
input StrategyMode InpStrat_Mode                = STRAT_PACK_ONLY; // Strategy Mode: 0=Main, 1=Pack, 2=Combined

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
input double InpConf_MinScore       = 0.55;    // Confluence Gate: Min Score
input bool   InpMain_SequentialGate = false;   // Confluence Gate: Seq Gate

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

input bool   InpExtra_News = true;              // Confluence Gate: News Filter
input double InpW_News     = 1.00;              // Confluence Gate: News Filter Weight

// — Router/Confluence thresholds —
input bool   Inp_EnableHardGate            = false;  // Router/Confluence Threshold: Hard Gate
input double Inp_RouterFallbackMin         = 0.58;  // Router/Confluence Threshold: Fallback acceptance if normal gate rejects
input int    Inp_MinFeaturesMet            = 1;     // Router/Confluence Threshold: Min Feat. Met exclude NewsOK from count

// Hard-gate recipe: Trend + ADX + (Struct || Candle || OB_Prox)
input bool   Inp_RequireTrendFilter        = false; // Market Structure: Required Trend Filter 
input bool   Inp_RequireADXRegime         = true; // Market Structure: Required ADX Reg
input bool   Inp_RequireStructOrPatternOB = true; // Market Structure: Required Struct Pattern OB

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
input bool InpCF_OrderBlockNear        = true; // OB near SD zone
input bool InpCF_CndlPattern           = true; // Candlestick patterns
input bool InpCF_ChartPattern          = true; // Chart patterns
input bool InpCF_MarketStructure       = true; // Market Struct: HH/HL/LH/LL bias, pivots
input bool InpCF_TrendRegime           = true; // Trend Regime (trend vs mean) + ADX strength
input bool InpCF_StochRSI              = true; // Stoch RSI OB/OS confirmation
input bool InpCF_MACD                  = true; // MACD crosses/confirmation
input bool InpCF_Correlation           = true; // Cross-pair confirmation
input bool InpCF_News                  = true; // News calendar filter (soft/pass as confluence)

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
input bool             InpNewsOn                = true;  // News: Enable
input int              InpNewsBlockPreMins      = 10;     // News: Block PreMins
input int              InpNewsBlockPostMins     = 10;     // News: Block PostMins
input int              InpNewsImpactMask        = 6;     // News: Impact Mask

// Calendar surprise thresholds (scale/skip)
input int              InpCal_LookbackMins      = 90;    // Calendar Thresholds: Lookback Mins
input double           InpCal_HardSkip          = 2.0;   // Calendar Thresholds: Hard Skip
input double           InpCal_SoftKnee          = 0.6;   // Calendar Thresholds: Soft Knee
input double           InpCal_MinScale          = 0.6;   // Calendar Thresholds: Min Scale

// ATR & quantile TP / SL
input int              InpATR_Period            = 14;    // ATR & Quantile TP/SL: Period
input double           InpTP_Quantile           = 0.6;   // ATR & Quantile TP/SL: TP Quantile
input double           InpTP_MinR_Floor         = 1.40;  // ATR & Quantile TP/SL: TP MinR Floor
input double           InpATR_SlMult            = 1.70;  // ATR & Quantile TP/SL: ATR SL Mult

// Feature toggles
input bool             InpVSA_Enable            = true;  // Feature: VSA Enable
input double           InpVSA_PenaltyMax        = 0.25;  // Feature: VSA Max Penalty
input bool             InpStructure_Enable      = true;  // Feature: Structure Enable
input bool             InpLiquidity_Enable      = true;  // Feature: Liquidity Enable
input bool             InpCorrSoftVeto_Enable   = true;  // Feature: Corr Soft Veto Enable

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
input bool             InpUseRegistryRouting    = true; // Registry Routing
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
input bool             InpProfile               = false; // Diagnostics / UX: Profile

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
Settings S;

static bool g_show_breakdown = true;
static bool g_calm_mode      = false;
static bool g_ml_on          = false;
static bool g_use_registry   = true;

// Multi-symbol scheduler
string   g_symbols[];              // parsed watchlist
int      g_symCount = 0;
static datetime g_lastBarTime[];   // per-symbol last closed-bar time on entry TF

// NEW: price/time gates state
static bool   g_armed_by_price     = false;
static bool   g_stopped_by_price   = false;
static double g_last_mid           = 0.0;

// NEW: streak state (reset daily by Risk day cache or session start)
static int    g_consec_wins        = 0;
static int    g_consec_losses      = 0;

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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EvaluateOneSymbol(const string sym)
  {
   Settings cur = S; // per-symbol snapshot if you later need overrides

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

   News::CompositeRiskAtBarClose(cur, sym, /*shift*/1, risk_mult, skip, mins_left);
   News::SurpriseRiskAdjust(now_srv, sym, cur.news_impact_mask, cur.cal_lookback_mins,
                            cur.cal_hard_skip, cur.cal_soft_knee, cur.cal_min_scale,
                            risk_mult, skip);
   if(skip)
     {
      Panel::Render(S);
      return;
     }

   StratScore ss = pick.ss;
   ss.risk_mult *= risk_mult;
   ss.risk_mult *= StreakRiskScale();

   ApplyMetaLayers(pick.dir, ss, pick.bd);

   if(cur.carry_enable && InpCarry_StrictRiskOnly)
      StrategiesCarry::RiskMod01(pick.dir, cur, ss.risk_mult);

   Panel::PublishBreakdown(pick.bd);
   Panel::PublishScores(ss);

// 3) Risk sizing → plan
   OrderPlan plan;
   ZeroMemory(plan);
   if(!Risk::ComputeOrder(pick.dir, cur, ss, plan, pick.bd))
     {
      Panel::Render(S);
      return;
     }

// 4) Execute
   Exec::Outcome ex = Exec::SendAsyncSymEx(sym, plan, cur);
   if(ex.ok)
      Policies::NotifyTradePlaced();

   LogX::Exec(sym, pick.dir, plan.lots, plan.price, plan.sl, plan.tp,
              ex.ok, ex.retcode, ex.ticket, cur.slippage_points);
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
   cfg.profile = InpProfile;

   #ifdef CFG_HAS_LONDON_LOCAL_MINUTES
     int mm_open=-1, mm_close=-1;
     if(!Config::_parse_hhmm(Inp_LondonStartLocal, mm_open))  mm_open  = 6*60;
     if(!Config::_parse_hhmm(Inp_LondonEndLocal,   mm_close)) mm_close = 10*60;
     cfg.london_local_open_min  = mm_open;
     cfg.london_local_close_min = mm_close;
   #endif

  // ---- Assets / TFs / cadence ----
  cfg.tf_entry = InpEntryTF; cfg.tf_h1=InpHTF_H1; cfg.tf_h4=InpHTF_H4; cfg.tf_d1=InpHTF_D1;
  cfg.only_new_bar = InpOnlyNewBar; cfg.timer_ms = InpTimerMS;
  cfg.server_offset_min = InpServerOffsetMinutes;

  // ---- Risk core ----
  cfg.risk_pct = InpRiskPct; cfg.risk_cap_pct = InpRiskCapPct;
  cfg.min_sl_pips = InpMinSL_Pips; cfg.min_tp_pips = InpMinTP_Pips; cfg.max_sl_ceiling_pips = InpMaxSLCeiling_Pips;
  #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
    cfg.day_dd_limit_pct = InpDayDD_LimitPct;
  #endif
  cfg.max_losses_day = InpMaxLossesDay; cfg.max_trades_day = InpMaxTradesDay;
  cfg.max_spread_points = InpMaxSpreadPoints; cfg.slippage_points = InpSlippagePoints;

  // ---- Sessions (legacy union) + Preset ----
  cfg.session_filter = InpSessionFilter;
  cfg.london_open_utc = InpLondonOpenUTC; cfg.london_close_utc = InpLondonCloseUTC;
  cfg.ny_open_utc = InpNYOpenUTC; cfg.ny_close_utc = InpNYCloseUTC;
  cfg.session_preset = InpSessionPreset;
  cfg.tokyo_close_utc = InpTokyoCloseUTC; cfg.sydney_open_utc = InpSydneyOpenUTC;

  // ---- News block + calendar scaling ----
  cfg.news_on = InpNewsOn; cfg.block_pre_m = InpNewsBlockPreMins; cfg.block_post_m = InpNewsBlockPostMins;
  cfg.news_impact_mask = InpNewsImpactMask;
  cfg.cal_lookback_mins = InpCal_LookbackMins; cfg.cal_hard_skip = InpCal_HardSkip;
  cfg.cal_soft_knee = InpCal_SoftKnee; cfg.cal_min_scale = InpCal_MinScale;

  // ---- ATR / TP-SL (quantile) ----
  cfg.atr_period = InpATR_Period;
  cfg.tp_quantile = InpTP_Quantile;
  cfg.atr_sl_mult = InpATR_SlMult;
  cfg.tp_minr_floor = InpTP_MinR_Floor;

  // ---- Position mgmt ----
  cfg.be_enable = InpBE_Enable; cfg.be_at_R = InpBE_At_R; cfg.be_lock_pips = InpBE_Lock_Pips;
  cfg.trail_type = InpTrailType; cfg.trail_pips = InpTrailPips; cfg.trail_atr_mult = InpTrailATR_Mult;
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
  cfg.extra_min_score  = MathMax(0.0, InpExtra_MinScore);

  // ---- Extras toggles + weights ----
  cfg.extra_volume_footprint = InpExtra_VolumeFootprint;
  cfg.w_volume_footprint     = InpW_VolumeFootprint;

  cfg.cf_liquidity       = InpCF_Liquidity;     cfg.w_liquidity    = InpW_Liquidity;
  cfg.cf_vsa_increase    = InpCF_VSAIncrease;   cfg.w_vsa_increase = InpW_VSAIncrease;

  cfg.extra_stochrsi     = InpExtra_StochRSI;   // weight reuses base
  cfg.extra_macd         = InpExtra_MACD;       // weight reuses base
  cfg.extra_adx_regime   = InpExtra_ADXRegime;  cfg.w_adx_regime = InpW_ADXRegime;
  cfg.extra_correlation  = InpExtra_Correlation;// weight reuses base
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
void BootRegistry_NoProfile()
  {
   StratReg::Init();
   StratReg::AutoRegisterBuiltins();
   
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
void BootRegistry_WithProfile(const Config::ProfileSpec &ps)
  {
   StratReg::Init();
   StratReg::AutoRegisterBuiltins();

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

   LogX::Info(StringFormat(
                 "[WhyNoTrade] origin=%s id=%d dir=%s eligible=%d score=%.3f min=%.2f veto=%d mask=%d | meta=%s",
                 origin, (int)id, _DirStr(dir), (int)ss.eligible, ss.score, min_sc, (int)bd.veto, (int)bd.veto_mask, bd.meta));
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
      return false;

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
   if(g_ml_on)
     {
      double blended=bd.score_final, p=0.0;
      bool acc=false;
      if(ML::BlendFull(dir, S, bd, ss, bd.score_final, p, acc, blended))
        {
         ML::HookScore(bd, p);
         bd.score_final = blended;
         ss.score       = blended;
        }
     }
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

// --- One-eval-per-bar dispatcher (RouterX) ---
void MaybeEvaluate()
  {
   // History gate(s)
   if(!Warmup::GateReadyOnce(InpDebug))
      return;
   // Short series gate for VWAP/patterns/ATR (from Warmup.mqh patch)
   if(!Warmup::DataReadyForEntry(S))
      return;

   static datetime last_bar = 0;
   const datetime bt = iTime(_Symbol, Warmup::TF_Entry(S), 0);

   if(InpOnlyNewBar && bt == last_bar)
      return;

   if(InpOnlyNewBar)
      last_bar = bt;

   // Run router once (direct router mode)
   ICT_Context ictCtx;
   ZeroMemory(ictCtx);                 // stub context: fibTargets etc. default to "off"

   Routing::RouteResult rr;
   ZeroMemory(rr);

   Routing::RouteOnce(S, ictCtx, rr);
  }

//--------------------------------------------------------------------
// BuildSettingsFromInputs()
// Copy ICT / router inputs into the runtime Settings struct (g_cfg).
// This is separate from MirrorInputsToSettings(S) used for S.
//--------------------------------------------------------------------
void BuildSettingsFromInputs(Settings &cfg)
{
   // --- Core / generic ICT config ---
   cfg.tf_entry                  = InpTfEntry;          // ICT entry TF
   cfg.tf_htf                    = InpTfHTF;            // ICT HTF
   cfg.risk_per_trade            = InpRiskPerTradePct;  // ICT risk slider
   cfg.newsFilterEnabled         = InpNewsOn;           // reuse NewsOn input
   cfg.trade_direction_selector  = InpTradeDirectionSelector;

   // Direction bias mode:
   cfg.direction_bias_mode       = InpDirectionBiasMode;

   // --- Strategy enable toggles ---
   cfg.enable_strat_main             = InpEnable_MainLogic;
   cfg.enable_strat_ict_silverbullet = InpEnable_ICT_SilverBullet;
   cfg.enable_strat_ict_po3          = InpEnable_ICT_PO3;
   cfg.enable_strat_ict_continuation = InpEnable_ICT_Continuation;
   cfg.enable_strat_ict_wyckoff_turn = InpEnable_ICT_WyckoffTurn;

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

   Panel::PublishFibContext(ictCtx);

   string j = "{";
   j += "\"sym\":\""      + Telemetry::_Esc(_Symbol)           + "\",";
   j += "\"tf\":"         + IntegerToString(Period())          + ",";
   j += "\"ict_score\":"  + DoubleToString(ictScore,3)         + ",";
   j += "\"classical_score\":" + DoubleToString(classicalScore,3) + ",";
   j += "\"armed\":\""    + Telemetry::_Esc(armedName)         + "\"";
   j += "}";

   Telemetry::KV("ict.ctx", j);
}

// ================== Lifecycle ==================
int OnInit()
  {
   ZeroMemory(S);
   // 1) Build base (short signature only)
   MirrorInputsToSettings(S); 
   
   // 2) Apply any appended/extended knobs via one struct (keeps ABI safe)
   Config::BuildExtras ex; Config::BuildExtrasDefaults(ex);
   ex.conf_min_count        = InpConf_MinCount;
   ex.conf_min_score        = InpConf_MinScore;
   ex.main_sequential_gate  = InpMain_SequentialGate;
   ex.extra_volume_footprint = InpExtra_VolumeFootprint;
   ex.w_volume_footprint     = InpW_VolumeFootprint;
   
   // Liquidity Pools (Lux-style)
   ex.liqPoolMinTouches      = InpLiqPoolMinTouches;
   ex.liqPoolGapBars         = InpLiqPoolGapBars;
   ex.liqPoolConfirmWaitBars = InpLiqPoolConfirmWaitBars;
   ex.liqPoolLevelEpsATR     = InpLiqPoolLevelEpsATR;
   ex.liqPoolMaxLookbackBars = InpLiqPoolMaxLookbackBars;
   ex.liqPoolMinSweepATR     = InpLiqPoolMinSweepATR;
   
   ex.extra_stochrsi         = InpExtra_StochRSI;
   ex.stochrsi_rsi_period    = InpStochRSI_RSI_Period;
   ex.stochrsi_k_period      = InpStochRSI_K_Period;
   ex.stochrsi_ob            = InpStochRSI_OB;
   ex.stochrsi_os            = InpStochRSI_OS;
   ex.w_stochrsi             = InpW_StochRSI;
   
   ex.extra_macd             = InpExtra_MACD;
   ex.macd_fast              = InpMACD_Fast;
   ex.macd_slow              = InpMACD_Slow;
   ex.macd_signal            = InpMACD_Signal;
   ex.w_macd                 = InpW_MACD;
   
   ex.extra_adx_regime       = InpExtra_ADXRegime;
   ex.adx_period             = InpADX_Period;
   ex.adx_min                = InpADX_Min;
   ex.w_adx_regime           = InpW_ADXRegime;
   
   ex.extra_corr             = InpExtra_Correlation;
   ex.corr_ref_symbol        = InpCorr_RefSymbol;
   ex.corr_lookback          = InpCorr_Lookback;
   ex.corr_min_abs           = InpCorr_MinAbs;
   ex.w_corr                 = InpW_Correlation;
   
   ex.extra_news             = InpExtra_News;
   ex.w_news                 = InpW_News;
   
   ex.enable_hard_gate       = Inp_EnableHardGate;
   ex.router_min_score       = InpRouterMinScore;
   ex.router_fb_min          = Inp_RouterFallbackMin;
   ex.min_features_met       = Inp_MinFeaturesMet;
   
   ex.require_trend                = Inp_RequireTrendFilter;
   ex.require_adx                  = Inp_RequireADXRegime;
   ex.require_struct_or_pattern_ob = Inp_RequireStructOrPatternOB;
   
   ex.london_liq_policy      = Inp_LondonLiquidityPolicy;
   ex.london_start_local     = Inp_LondonStartLocal;
   ex.london_end_local       = Inp_LondonEndLocal;
   
   ex.use_atr_as_delta       = Inp_UseATRasDeltaProxy;
   ex.atr_period_2           = InpATR_Period_Delta;          // or Inp_ATR_Period_2 if you have one
   ex.atr_vol_regime_floor   = Inp_ATR_VolRegimeFloor;
   
   ex.struct_zz_depth        = Inp_Struct_ZigZagDepth;
   ex.struct_htf_mult        = Inp_Struct_HTF_Multiplier;
   ex.ob_prox_max_pips       = Inp_OB_ProxMaxPips;
   
   ex.use_atr_stops_targets  = Inp_Use_ATR_StopsTargets;
   ex.atr_sl_mult2           = InpATR_SlMult;
   ex.atr_tp_mult2           = Inp_ATR_TP_Mult;
   ex.risk_per_trade_pct     = Inp_RiskPerTradePct;
   
   ex.log_veto_details       = Inp_LogVetoDetails;
   // ex.weekly_open_spread_ramp = InpWeeklyOpenRamp;  // if you expose it as input
   
   Config::ApplyExtras(S, ex);
   Config::FinalizeThresholds(S);

   Config::ApplyStrategyMode(S, InpStrat_Mode);

   Config::LoadInputs(S);
   Config::ApplyKVOverrides(S);
   Config::FinalizeThresholds(S);

   g_show_breakdown = true;
   g_calm_mode      = false;
   g_ml_on          = InpML_Enable;
   g_use_registry   = InpUseRegistryRouting;

   Sanity::SetDebug(InpDebug);
   LogX::SetMinLevel(InpDebug ? LogX::LVL_DEBUG : LogX::LVL_INFO);
   LogX::EnablePrint(true);
   LogX::EnableCSV(InpFileLog);
   if(InpFileLog)
      LogX::InitAll();
   Config::LogSettingsWithHash(S, "CFG");

   #ifdef CA_USE_HANDLE_REGISTRY
      HR::Init();
      LogX::Info("Indicators mode: registry-cached (HandleRegistry active).");
   #else
      LogX::Info("Indicators mode: ephemeral handles (create/copy/release per call).");
   #endif
   News::ConfigureFromEA(S);
   
   // Choose a base magic number by StrategyMode
   #ifdef CFG_HAS_MAGIC_NUMBER
     const StrategyMode sm = Config::CfgStrategyMode(S);
     switch(sm)
     {
       case STRAT_MAIN_ONLY: S.magic_number = MagicBase_Main; break;
       case STRAT_PACK_ONLY: S.magic_number = MagicBase_Pack; break;
       default:              S.magic_number = MagicBase_Combined; break;
     }
   #endif
   
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
   if(S.news_on)
   {
      News::Init();
   }
   Risk::InitDayCache();
   Panel::Init(S);
   Panel::ShowBreakdown(g_show_breakdown);
   Panel::SetCalmMode(g_calm_mode);
   Review::EnableScreenshots(InpReviewScreenshots, InpReviewSS_W, InpReviewSS_H);

   // ----- Persistent state load (guarded) -----
   #ifdef STATE_HAS_LOAD_SAVE
      if(!State::Load(S))
         LogX::Warn("[STATE] Load failed or empty; starting fresh.");
   #endif
   
   #ifdef POLICIES_HAS_SESSION_CTX
     SessionContext sc;
     Policies::BuildSessionContext(S, sc);  // populates sc.has_any_window (or similar)
   
     if (S.session_filter && CfgSessionPreset(S) != SESS_OFF && !sc.has_any_window)
     {
       if (InpDebug)
         Print("[Session] preset resolved to empty window; disabling session filter for this run.");
       S.session_filter = false;
     }
   #else
     // Fallback guard if you don’t have a session context object
     if (S.session_filter && CfgSessionPreset(S) != SESS_OFF)
     {
       const bool lon_empty = (S.london_open_utc == S.london_close_utc);
       const bool ny_empty  = (S.ny_open_utc     == S.ny_close_utc);
       if (lon_empty && ny_empty)
       {
         if (InpDebug)
           Print("[Session] LON/NY windows degenerate; disabling session filter for this run.");
         S.session_filter = false;
       }
     }
   #endif

   // ----- Build profile spec (weights/throttles) & optionally persist -----
   const TradingProfile prof = (TradingProfile)InpProfileType;
   Config::ProfileSpec ps;
   Config::BuildProfileSpec(prof, ps);
   if(InpProfileApply)
      Config::ApplyProfileHintsToSettings(S, ps, /*overwrite=*/true);
   Config::ApplyCarryDefaultsForProfile(S, prof);
   if(InpProfileSaveCSV)
      Config::SaveProfileSpecCSV(prof, ps, InpProfileCSVName, false);

   // ----- Apply profile to Settings (carry + confluence + router hints) -----
   if(InpProfileApply)
     {
      Config::ApplyTradingProfile(S, prof, /*apply_router_hints=*/InpProfileUseRouterHints,
                                  /*apply_carry_defaults=*/true,
                                  /*log_summary=*/true);

      if(InpProfileAllowManual)
        {
         S.carry_enable    = InpCarry_Enable;
   #ifdef CFG_HAS_CARRY_BOOST_MAX
         S.carry_boost_max = MathMin(MathMax(InpCarry_BoostMax, 0.0), 0.20);
   #endif
   #ifdef CFG_HAS_CARRY_RISK_SPAN
         S.carry_risk_span = MathMin(MathMax(InpCarry_RiskSpan, 0.0), 0.50);
   #endif
   #ifdef CFG_HAS_CONFL_BLEND_TREND
         if(InpConflBlend_Trend  >0.0)
            S.confl_blend_trend  = MathMin(InpConflBlend_Trend, 0.50);
   #endif
   #ifdef CFG_HAS_CONFL_BLEND_MR
         if(InpConflBlend_MR     >0.0)
            S.confl_blend_mr     = MathMin(InpConflBlend_MR, 0.50);
   #endif
   #ifdef CFG_HAS_CONFL_BLEND_OTHERS
         if(InpConflBlend_Others >0.0)
            S.confl_blend_others = MathMin(InpConflBlend_Others, 0.50);
   #endif
           }
        }
      else
        {
         S.carry_enable    = InpCarry_Enable;
   #ifdef CFG_HAS_CARRY_BOOST_MAX
      S.carry_boost_max = MathMin(MathMax(InpCarry_BoostMax, 0.0), 0.20);
   #endif
   #ifdef CFG_HAS_CARRY_RISK_SPAN
      S.carry_risk_span = MathMin(MathMax(InpCarry_RiskSpan, 0.0), 0.50);
   #endif

      Config::ApplyConfluenceBlendDefaultsForProfile(S, prof);
   #ifdef CFG_HAS_CONFL_BLEND_TREND
      if(InpConflBlend_Trend  >0.0)
         S.confl_blend_trend  = MathMin(InpConflBlend_Trend, 0.50);
   #endif
   #ifdef CFG_HAS_CONFL_BLEND_MR
      if(InpConflBlend_MR     >0.0)
         S.confl_blend_mr     = MathMin(InpConflBlend_MR, 0.50);
   #endif
   #ifdef CFG_HAS_CONFL_BLEND_OTHERS
      if(InpConflBlend_Others >0.0)
         S.confl_blend_others = MathMin(InpConflBlend_Others, 0.50);
   #endif
     }

   if(InpCarry_StrictRiskOnly)
   #ifdef CFG_HAS_CARRY_RISK_SPAN
         S.carry_risk_span = 0.0;
   #endif

   // ----- Boot strategy registry with/without profile -----
   if(InpProfileApply)
      BootRegistry_WithProfile(ps);
   else
      BootRegistry_NoProfile();

   // Optional tester preset overlay
   TesterPresets::ApplyPresetByName(S, InpTesterPreset);
   TesterCases::ApplyTestCase(S, InpTestCase);
   
   // Housekeeping post-apply
   Config::Normalize(S);
   StratReg::SyncRouterFromSettings(S);
   
   // Trade policy cooldown
   Policies::SetTradeCooldownSeconds(MathMax(0, InpTradeCooldown_Sec));
   ML::Configure(S, InpML_Temperature, InpML_Threshold, InpML_Weight, InpML_Conformal, InpML_Dampen);

   // Watchlist parse
   ParseAssetList(InpAssetList, g_symbols);
   g_symCount = ArraySize(g_symbols);
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

   // Timer (seconds; EventSetTimer is seconds granularity)
   int sec = (S.timer_ms <= 1000 ? 1 : S.timer_ms / 1000);
   EventSetTimer(MathMax(1, sec));

   // Optional benchmark
   RunIndicatorBenchmarks();

   // --- Telemetry wiring (new) ---
   Telemetry::Configure(512*1024, /*to_common*/true, /*gv_breadcrumbs*/true, "CA_TEL", /*weekly*/false);
   Telemetry::SetHUDBarGuardTF(S.tf_entry);  // emit HUD/snapshots once per new bar on entry TF

   #ifdef TELEMETRY_HAS_INIT
      Telemetry::Init(S);
   #endif

   DebugChecklist::Init(_Symbol, InpDbgChkMinScore, InpDbgChkZoneProxATR, InpDbgChkOBProxATR);

   // init price gates
   g_last_mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK))*0.5;
   g_armed_by_price   = (InpTradeAtPrice<=0.0); // if no arming price, we are armed by default
   g_stopped_by_price = false;

   // Streak state (fresh day)
   g_consec_wins   = 0;
   g_consec_losses = 0;
   
   #ifdef HAS_ICT_WYCKOFF_PLAYBOOK
      // g_playbook.InitDefaults(/*useSummerNY=*/false);
   #endif
   
   // 1. Copy all extern/input params into g_cfg
   BuildSettingsFromInputs(g_cfg);

   g_cfg.adx_period     = InpADX_Period;
   g_cfg.adx_min_trend  = InpADX_Min;
   g_cfg.adx_upper      = InpADX_Upper;

   g_cfg.corr_ref_symbol= InpCorr_RefSymbol;
   g_cfg.corr_lookback  = InpCorr_Lookback;
   g_cfg.corr_min_abs   = InpCorr_MinAbs;
   g_cfg.corr_max_pen   = InpCorr_MaxPen;
   g_cfg.corr_ema_tf    = InpCorr_TF;

   g_cfg.block_pre_m    = InpNewsBlockPreMins;
   g_cfg.block_post_m   = InpNewsBlockPostMins;
   g_cfg.news_impact_mask = InpNewsImpactMask;

   g_cfg.w_adx_regime   = InpW_ADXRegime;
   g_cfg.w_corr_pen     = InpW_CorrPen;
   g_cfg.w_news         = InpW_News;

   // 2. Initialize State
   StateInit(g_state, S);

   MarketData::EnsureWarmup_ADX(_Symbol, g_cfg.tf_entry, g_cfg.adx_period, 1);
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Policies::CfgCorrTF(S);
   int            lb = Policies::CfgCorrLookback(S);
   MarketData::EnsureWarmup_CorrReturns(_Symbol, tf, lb, 1);

   // 3. Initialize Router strategies registry (ICT-aware)
   RouterInit(g_router, g_cfg);

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
   // ── Warm-up with soft latch (prevents permanent stall in tester) ──
   static int  _wu_ticks  = 0;
   static uint _wu_t0_ms  = 0;
   
   // Legacy router tick hook; RouterEvaluateAll() below now owns eval.
   // Router::OnTickRoute(g_cfg, g_state, _Symbol, g_strategies);
   
   if(_wu_t0_ms == 0) _wu_t0_ms = GetTickCount();
   const uint _wu_elapsed = GetTickCount() - _wu_t0_ms;
   
   bool _ready = Warmup::GateReadyOnce(InpDebug);
   
   // If not ready after a while, soft-latch to proceed (tester-safe)
   if(!_ready)
   {
     _wu_ticks++;
     // 5 seconds or 250 ticks – whichever comes first
     if(_wu_elapsed > 5000 || _wu_ticks > 250)
     {
       if(InpDebug) Print("[Warmup] soft-latch engaged; proceeding.");
       _ready = true;
     }
   }
   
   if(!_ready) return;

   // Lower-TF/HTF history must be present before any Evaluate()
   if(!Warmup::DataReadyForEntry(S))
     {
      Panel::Render(S);
      return;
     }

   if(InpOnlyNewBar)
     {
      const ENUM_TIMEFRAMES tf = Warmup::TF_Entry(S);
      if(!IsNewBar(_Symbol, tf))
         return;
     }
     
   static datetime _hb_last_bar = 0;
   const datetime _bar_time = iTime(_Symbol, S.tf_entry, 0);
   if(_bar_time != _hb_last_bar)
   {
     _hb_last_bar = _bar_time;
     PrintFormat("[HB] %s M%d new bar %s",
                 _Symbol, (int)(PeriodSeconds(S.tf_entry)/60),
                 TimeToString(_bar_time, TIME_DATE|TIME_MINUTES));
   }
   // Centralized router eval (only when NOT using registry path)
   if(!g_use_registry)
      MaybeEvaluate();

   const bool single_symbol = (g_symCount<=1) || (g_symbols[0]==_Symbol && g_symCount==1);

   if(single_symbol)
     {
      const bool newbar = (S.only_new_bar ? NewBarFor(_Symbol, S.tf_entry) : true);
      // Keep your existing per-symbol processing
      ProcessSymbol(_Symbol, newbar);
     }
   else
     {
      // Multi-symbol: Process every symbol as before.
      for(int i=0;i<g_symCount;i++)
        {
         const string sym = g_symbols[i];
         const bool newbar = (S.only_new_bar ? NewBarFor(sym, S.tf_entry) : true);
         ProcessSymbol(sym, newbar);
        }
      if(InpOnlyNewBar && !IsNewBar(_Symbol, InpEntryTF))
         return;

      // [WARMUP GATE]
      // ── Warm-up with soft latch (prevents permanent stall in tester) ──
      static int  _wu_ticks  = 0;
      static uint _wu_t0_ms  = 0;
      
      if(_wu_t0_ms == 0) _wu_t0_ms = GetTickCount();
      const uint _wu_elapsed = GetTickCount() - _wu_t0_ms;
      
      bool _ready = Warmup::GateReadyOnce(InpDebug);
      
      // If not ready after a while, soft-latch to proceed (tester-safe)
      if(!_ready)
      {
        _wu_ticks++;
        // 5 seconds or 250 ticks – whichever comes first
        if(_wu_elapsed > 5000 || _wu_ticks > 250)
        {
          if(InpDebug) Print("[Warmup] soft-latch engaged; proceeding.");
          _ready = true;
        }
      }
      
      if(!_ready) return;
     }

   // 1. Refresh low-level market data into State.
   //    This should update things like:
   //    - g_state.bid / g_state.ask
   //    - volume/Delta (DeltaProxy)
   //    - pivots / ADR / VWAP / spreads
   //    - absorption flags (absorptionBull/absorptionBear)
   //    - emaFastHTF / emaSlowHTF
   //
   // StateOnTickUpdate() should *not* touch ictContext.
   StateOnTickUpdate(g_state);

   // 2. Recompute Smart Money / Wyckoff model into g_state.ictContext.
   RefreshICTContext(g_state);
   ICT_Context ictCtx = StateGetICTContext(g_state);

   // 3.1 Pull scores from confluence layer
   #ifdef HAS_CONFLUENCE_API
      double classicalScore = Confluence_GetLastClassicalScore();
      double ictScore       = Confluence_GetLastICTScore();
   #else
      double classicalScore = 0.0;
      double ictScore       = 0.0;
   #endif

   // 3.2 Query which strat is currently armed (last eligible)
   string armedName =
   #ifdef ROUTER_HAS_LAST_ARMED_NAME
      RouterGetLastArmedName(g_router);
   #else
      "-";
   #endif

   // 3.3 Push to the UI
   PushICTTelemetryToReviewUI(ictCtx, classicalScore, ictScore, armedName);

   // 4. Sync runtime execution policies into g_cfg each tick.
   g_cfg.mode_use_silverbullet =
      (InpEnable_SilverBulletMode && g_cfg.enable_strat_ict_silverbullet);

   g_cfg.mode_use_po3 =
      (InpEnable_PO3Mode && g_cfg.enable_strat_ict_po3);

   g_cfg.mode_enforce_killzone = InpEnforceKillzone;
   g_cfg.mode_use_ICT_bias     = InpUseICTBias;

   if(InpUseICTBias)
      g_cfg.direction_bias_mode = Config::DIRM_AUTO_SMARTMONEY;
   else
      g_cfg.direction_bias_mode = Config::DIRM_MANUAL_SELECTOR;

   // 5. Dispatch strategies via router (ICT-aware path)
   RouterEvaluateAll(g_router, g_state, g_cfg, ictCtx);

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
   EventKillTimer();
   Exec::Deinit();
   MarketData::Deinit();
   Panel::Deinit();
   ReviewUI_ICT_Deinit();   // optional, cleans labels
   
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
   MarketData::OnTimerRefresh();
   Risk::Heartbeat(TimeUtils::NowServer());
   PM::ManageAll(S);
   Panel::Render(S);

   // [WARMUP GATE]
   // ── Warm-up with soft latch (prevents permanent stall in tester) ──
   static int  _wu_ticks  = 0;
   static uint _wu_t0_ms  = 0;
   
   if(_wu_t0_ms == 0) _wu_t0_ms = GetTickCount();
   const uint _wu_elapsed = GetTickCount() - _wu_t0_ms;
   
   bool _ready = Warmup::GateReadyOnce(InpDebug);
   
   // If not ready after a while, soft-latch to proceed (tester-safe)
   if(!_ready)
   {
     _wu_ticks++;
     // 5 seconds or 250 ticks – whichever comes first
     if(_wu_elapsed > 5000 || _wu_ticks > 250)
     {
       if(InpDebug) Print("[Warmup] soft-latch engaged; proceeding.");
       _ready = true;
     }
   }
   
   if(!_ready) return;

   if(InpOnlyNewBar)
      return;
   if(!g_use_registry)
      MaybeEvaluate();
  }

   // --- Minimal Trading Path (MVP): intent → risk → execute ---
   bool TryMinimalPathIntent(const string sym,
                             const Settings &cfg,
                             StratReg::RoutedPick &pick_out)
     {
      ZeroMemory(pick_out);
   
   // 1) Single call into the registry router (no direct MainTradingLogic usage)
   //    Prefer StratReg::Route(...). If your registry exposes only EvaluateMany/SelectBest,
   //    you can keep your RouteRegistryAll/RouteRegistryPick fallback (see note below).
      bool okRoute = false;
      RouterConfig rc = StratReg::GetGlobalRouterConfig();
   
   // Primary path: one-shot route
   #ifdef STRATREG_HAS_ROUTE
      okRoute = (StratReg::Route(cfg, pick_out) && pick_out.ok);
   #else
   // Fallback to your existing helpers (kept exactly as-is)
      if(g_use_registry)
        {
         string top;
         okRoute = RouteRegistryAll(cfg, pick_out, top);
         if(okRoute)
            LogX::Info(StringFormat("Router.Top: %s", top));
         if(!okRoute)
            okRoute = RouteRegistryPick(cfg, pick_out);
        }
      else
        {
         okRoute = RouteManualRegimePick(cfg, pick_out);
        }
   #endif

   if(!okRoute)
      return false;

   // 2) Enforce eligibility/threshold here (single place)
   const double min_sc = (rc.min_score>0.0 ? rc.min_score : Const::SCORE_ELIGIBILITY_MIN);
   if(pick_out.bd.veto || !pick_out.ss.eligible || pick_out.ss.score < min_sc)
      return false;

   // 3) Normal UI hooks
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
   bool crossed = ((g_last_mid < InpTradeAtPrice && mid >= InpTradeAtPrice) ||
                   (g_last_mid > InpTradeAtPrice && mid <= InpTradeAtPrice));
   g_last_mid = mid;
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
   bool crossed = ((g_last_mid < InpStopTradeAtPrice && mid >= InpStopTradeAtPrice) ||
                   (g_last_mid > InpStopTradeAtPrice && mid <= InpStopTradeAtPrice));
   g_last_mid = mid;
   if(crossed)
     {
      g_stopped_by_price = true;
      LogX::Warn(StringFormat("[GATE] Stop-Trade price %.5f reached; new entries disabled.", InpStopTradeAtPrice));
     }
  }

// -------- NEW: streak lot multiplier (applied to risk_mult safely) ------
double StreakRiskScale()
  {
   double mult = 1.0;

   if(InpStreakWinsToDouble>0 && g_consec_wins >= InpStreakWinsToDouble)
      mult = MathMin(InpStreakMaxBoost, 2.0);

   if(InpStreakLossesToHalve>0 && g_consec_losses >= InpStreakLossesToHalve)
      mult = MathMax(InpStreakMinScale, mult*0.5);

   return mult;
  }

// Per-symbol processing unit (PM + gates + MVP pipeline)
void ProcessSymbol(const string sym, const bool new_bar_for_sym)
  {
   if(new_bar_for_sym)
     {
      double atr_pts = Indi::ATRPoints(sym, S.tf_entry, S.atr_period, 1);
      if(atr_pts>0.0)
         Risk::OnEntryBarATR(atr_pts);
     }

   // 1) Guard rails and gates (spread cap, daily DD, volatility breaker, cooldowns)
   int gate_reason=0;
   if(!Policies::Check(S, gate_reason))
     {
      if(InpDebug) PrintFormat("[Gate] Blocked at Policies::Check (reason=%d)", gate_reason);
      Panel::SetGate(gate_reason);
      PM::ManageAll(S);
      return;
     }
   Panel::SetGate(gate_reason);

   const datetime now_srv = TimeUtils::NowServer();

   // Session filter (legacy union or preset)
   if (CfgSessionFilter(S))
   {
     const bool sess_on = Policies::EffSessionFilter(S, _Symbol);
     if (sess_on)
     {
       TimeUtils::SessionContext sc;
       TimeUtils::BuildSessionContext(S, now_srv, sc);
       const bool allowed = (CfgSessionPreset(S) != SESS_OFF ? sc.preset_in_window : sc.in_window);
       if (!allowed)
       {
         if (InpDebug)
           PrintFormat("[EA] Session gate: session_on=1 in_window=0 → skip %s", _Symbol);
         PM::ManageAll(S);
         return;
       }
     }
   }

   // Time window (hard start/expiry in server time)
   if(!TimeGateOK(now_srv))
     {
      PM::ManageAll(S);
      Panel::Render(S);
      return;
     }

   // Price gates
   if(!PriceArmOK())
     {
      PM::ManageAll(S);
      Panel::Render(S);
      return;
     }
   CheckStopTradeAtPrice();
   if(g_stopped_by_price)
     {
      PM::ManageAll(S);
      Panel::Render(S);
      return;
     }
   // News hard-block window
   int mins_left=0;
   if(S.news_on && News::IsBlocked(now_srv, sym, S.news_impact_mask, S.block_pre_m, S.block_post_m, mins_left))
     {
      PM::ManageAll(S);
      return;
     }

   // Always keep managing open positions
   PM::ManageAll(S);

   // NOTE: current strategies rely on _Symbol internally; only evaluate on chart symbol.
   if(sym != _Symbol)
      return;

   if(Exec::IsLocked(sym))
     {
      Panel::Render(S);
      return;
     }

   // Runtime gate: wait for history warmup
     {
      const int need = Warmup::NeededBars(S);
      if(!Warmup::Ready(sym, S.tf_entry, need)
         || !Warmup::Ready(sym, Warmup::TF_H1(S),  MathMax(need, 300))
         || !Warmup::Ready(sym, Warmup::TF_H4(S),  MathMax(need/2, 250))
         || !Warmup::Ready(sym, Warmup::TF_D1(S),  200))
        {
         PM::ManageAll(S);
         Panel::Render(S);
         return;
        }
     }

   // 2) Policies::Evaluate (or router fallback) → intent/pick
   StratReg::RoutedPick pick;
   ZeroMemory(pick);
   if(!TryMinimalPathIntent(sym, S, pick))
     {
      Panel::Render(S);
      return;
     }

   // Drop ineligible / under-threshold picks (prevents the RET_UNSPEC spam)
   RouterConfig rc = StratReg::GetGlobalRouterConfig();
   const double min_sc = (rc.min_score>0.0 ? rc.min_score : Const::SCORE_ELIGIBILITY_MIN);
   if(!pick.ss.eligible || pick.ss.score < min_sc)
     {
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
      const int mask = (pick.bd.veto_mask & 15);
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
   double risk_mult=1.0;
   bool skip=false;
   News::CompositeRiskAtBarClose(S, sym, /*shift*/1, risk_mult, skip, mins_left);
   News::SurpriseRiskAdjust(now_srv, sym, S.news_impact_mask, S.cal_lookback_mins,
                            S.cal_hard_skip, S.cal_soft_knee, S.cal_min_scale,
                            risk_mult, skip);
   if(skip)
     {
      PM::ManageAll(S);
      Panel::Render(S);
      return;
     }

   StratScore SS = pick.ss;
   SS.risk_mult *= risk_mult;

   // NEW: streak scaling (before ML so downstream can log final)
   SS.risk_mult *= StreakRiskScale();

   ApplyMetaLayers(pick.dir, SS, pick.bd);
   // -------- Carry integration (strict or mild) ----------
   if(S.carry_enable && InpCarry_StrictRiskOnly)
      StrategiesCarry::RiskMod01(pick.dir, S, SS.risk_mult);

   Panel::PublishBreakdown(pick.bd);
   Panel::PublishScores(SS);

   // 4) Risk sizing → SL/TP & lot size
   OrderPlan plan;
   if(!Risk::ComputeOrder(pick.dir, S, SS, plan, pick.bd))
     {
      Panel::Render(S);
      return;
     }

   // 5) Execution
   Exec::Outcome ex = Exec::SendAsyncSymEx(sym, plan, S);
   if(ex.ok)
      Policies::NotifyTradePlaced();

   LogX::Exec(sym, pick.dir, plan.lots, plan.price, plan.sl, plan.tp,
              ex.ok, ex.retcode, ex.ticket, S.slippage_points);

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
   static datetime last = 0;
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
      long   deal_type = 0;
      HistoryDealGetInteger(tx.deal, DEAL_TYPE, deal_type);
      double profit    = 0.0;
      HistoryDealGetDouble(tx.deal, DEAL_PROFIT, profit);

      // Count only closes (outcome known)
      if(deal_type==DEAL_TYPE_SELL || deal_type==DEAL_TYPE_BUY ||
         deal_type==DEAL_TYPE_BALANCE)
        {
         if(profit > 0.0)
           {
            g_consec_wins++;
            g_consec_losses=0;
           }
         else if(profit < 0.0)
           {
            g_consec_losses++;
            g_consec_wins=0;
           }
        }
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
      // Optional: plain confirmation line (no duplication, correct data)
      if(tx.type==TRADE_TRANSACTION_DEAL_ADD)
        {
         long dType=0;
         HistoryDealGetInteger(tx.deal, DEAL_TYPE, dType);
         const bool buy = (dType==DEAL_TYPE_BUY || rq.type==ORDER_TYPE_BUY);
         const string tag = FlowTag(tx.symbol, (ENUM_TIMEFRAMES)S.tf_entry, buy);

         const int dg = (int)SymbolInfoInteger(tx.symbol, SYMBOL_DIGITS);
         double dPrice=0.0;
         HistoryDealGetDouble(tx.deal, DEAL_PRICE,  dPrice);
         double dVol  =0.0;
         HistoryDealGetDouble(tx.deal, DEAL_VOLUME, dVol);

         PrintFormat("%s DEAL fill symbol=%s type=%d price=%s vol=%.2f ticket=%I64d",
                     tag, tx.symbol, (int)dType, DoubleToString(dPrice, dg), dVol, (long)tx.deal);
        }
     }

// Telemetry (guarded)
#ifdef TELEMETRY_HAS_TX
   Telemetry::OnTx(tx, rs);
#endif
  }

// Menu / Hotkeys: B=Breakdown, C=Calm, M=ML, R=Routing, N=News, P=Screenshot, H=Benchmark
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
            PrintFormat("[UI] ML blender %s  %s",(g_ml_on?"ON":"OFF"), ML::StateString());
           }
         else
            if(K=='R')
              {
               g_use_registry=!g_use_registry;
               PrintFormat("[UI] Routing: %s",(g_use_registry?"REGISTRY-ALL":"MANUAL-REGIME"));
              }
            else
               if(K=='N')
                 {
                  S.news_on=!S.news_on;
                  PrintFormat("[UI] News hard-block %s",(S.news_on?"ON":"OFF"));
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
   return score;
  }
//+------------------------------------------------------------------+
