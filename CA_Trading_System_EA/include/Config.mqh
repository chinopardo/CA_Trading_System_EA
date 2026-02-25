// Config.mqh  (full, consolidated & compile-safe)
// - Settings builder (signature unchanged)
// - Strong Normalize() + Validate() with clear warnings
// - CanonicalCSV + FNV-1a 64-bit hash
// - TradingProfile presets (Balanced/Trend/MR/Scalp)
// - RiskPreset presets (Conservative/Balanced/Aggressive)
// - ProfileSpec with router hints + per-strategy weights/throttles
// - Carry defaults per profile (ABI-safe; STRICT risk-only handled by EA)
// - Confluence-blend defaults per profile (Trend / MR / Others)
// - Helpers to surface profile weights/throttles by strategy NAME
// - ApplyTradingProfile() + ApplyProfileToSettings() (typed + int overload)
// - Settings CSV export/import (SaveSettingsCSV / LoadSettingsCSV)
//====================================================================
#ifndef CA_CONFIG_MQH
#define CA_CONFIG_MQH
struct Settings;

#include "Types.mqh"

// Core feature availability
#ifndef CFG_HAS_CONFLUENCE
  #define CFG_HAS_CONFLUENCE 1
#endif
#ifndef CFG_HAS_UMBRELLA
  #define CFG_HAS_UMBRELLA 1
#endif
#ifndef CFG_HAS_CONFL_BLEND_TREND
   #define CFG_HAS_CONFL_BLEND_TREND 1
#endif
#ifndef CFG_HAS_CONFL_BLEND_MR
   #define CFG_HAS_CONFL_BLEND_MR 1
#endif
#ifndef CFG_HAS_CONFL_BLEND_OTHERS
   #define CFG_HAS_CONFL_BLEND_OTHERS 1
#endif

// --- Feature flag so other files can #ifdef safely
#ifndef CFG_HAS_STRAT_TOGGLES
  #define CFG_HAS_STRAT_TOGGLES 1
#endif
#ifndef CFG_HAS_STRAT_MODE
  #define CFG_HAS_STRAT_MODE 1
#endif
#ifndef CFG_HAS_ML_THRESHOLD
   #define CFG_HAS_ML_THRESHOLD 1
#endif
#ifndef CFG_HAS_ML_SETTINGS
   #define CFG_HAS_ML_SETTINGS 1
#endif

// --- Autochartist-style internal scanner ---
#ifndef CFG_HAS_AUTOCHARTIST
  #define CFG_HAS_AUTOCHARTIST 1
#endif
#ifndef CFG_HAS_AUTOCHARTIST_SETTINGS
  #define CFG_HAS_AUTOCHARTIST_SETTINGS 1
#endif

// --- Autochartist patterns export control (single source of truth) ---
#ifndef CFG_HAS_AUTOC_PATT_SETTINGS
  #define CFG_HAS_AUTOC_PATT_SETTINGS 1
#endif
#ifndef CFG_HAS_AUTOC_PATT_EXPORT_LEVEL
  #define CFG_HAS_AUTOC_PATT_EXPORT_LEVEL 1
#endif
#ifndef CFG_HAS_AUTOC_PATT_EMIT_MODE
  #define CFG_HAS_AUTOC_PATT_EMIT_MODE 1
#endif
#ifndef CFG_HAS_AUTOC_PATT_TOPN
  #define CFG_HAS_AUTOC_PATT_TOPN 1
#endif
#ifndef CFG_HAS_AUTOC_PATT_MIN_SCORE01
  #define CFG_HAS_AUTOC_PATT_MIN_SCORE01 1
#endif

// Back-compat: AutochartistEngine.mqh currently guards patt_all using this macro name
#ifndef CFG_HAS_AUTO_PATT_ALL_SETTINGS_FIELDS
  #define CFG_HAS_AUTO_PATT_ALL_SETTINGS_FIELDS 1
#endif

// --- Support/Resistance detector (SRDet) ---
#ifndef CFG_HAS_SR_DETECTOR_SETTINGS
  #define CFG_HAS_SR_DETECTOR_SETTINGS 1
#endif

// --- Fibonacci / OTE settings (cfg-wired) ---
#ifndef CFG_HAS_FIB_SETTINGS
  #define CFG_HAS_FIB_SETTINGS 1
#endif

// --- FVG settings (cfg-wired) ---
#ifndef CFG_HAS_FVG_MIN_SCORE
  #define CFG_HAS_FVG_MIN_SCORE 1
#endif
#ifndef CFG_HAS_FVG_MODE
  #define CFG_HAS_FVG_MODE 1
#endif
#ifndef CFG_HAS_FVG_LOOKBACK_BARS
  #define CFG_HAS_FVG_LOOKBACK_BARS 1
#endif
#ifndef CFG_HAS_FVG_IMPULSE_LOOKAHEAD_BARS
  #define CFG_HAS_FVG_IMPULSE_LOOKAHEAD_BARS 1
#endif
#ifndef CFG_HAS_FVG_MIN_GAP_ATR
  #define CFG_HAS_FVG_MIN_GAP_ATR 1
#endif

// --- Scanner toggles / thresholds (non-Autochartist scanners) ---
#ifndef CFG_HAS_SCAN_FVG_SETTINGS
  #define CFG_HAS_SCAN_FVG_SETTINGS 1
#endif
#ifndef CFG_HAS_SCAN_EXTRA_SETTINGS
  #define CFG_HAS_SCAN_EXTRA_SETTINGS 1
#endif
#ifndef CFG_HAS_SCAN_TL_SETTINGS
  #define CFG_HAS_SCAN_TL_SETTINGS 1
#endif
#ifndef CFG_HAS_SCAN_CORR_DETECTOR_SETTINGS
  #define CFG_HAS_SCAN_CORR_DETECTOR_SETTINGS 1
#endif

// --- StructureSDOB / Supply-Demand (SDOB) / OB knobs -------------------------
#ifndef CFG_HAS_PATTERN_LOOKBACK
  #define CFG_HAS_PATTERN_LOOKBACK 1
#endif

// ZigZag depth: Config uses CFG_HAS_ZZ_DEPTH, StructureSDOB can also check CFG_HAS_STRUCT_ZIGZAG_DEPTH
#ifndef CFG_HAS_ZZ_DEPTH
  #define CFG_HAS_ZZ_DEPTH 1
#endif
#ifndef CFG_HAS_STRUCT_ZIGZAG_DEPTH
  #define CFG_HAS_STRUCT_ZIGZAG_DEPTH 1
#endif

#ifndef CFG_HAS_STRUCT_HTF_MULT
  #define CFG_HAS_STRUCT_HTF_MULT 1
#endif

#ifndef CFG_HAS_OB_PROX_MAX_PIPS
  #define CFG_HAS_OB_PROX_MAX_PIPS 1
#endif

#ifndef CFG_HAS_STRUCT_VETO
  #define CFG_HAS_STRUCT_VETO 1
#endif

// Optional SDOB quality gates (used once StructureSDOB selection/filter is wired)
#ifndef CFG_HAS_STRUCT_ZONE_MARGIN_PIPS
  #define CFG_HAS_STRUCT_ZONE_MARGIN_PIPS 1
#endif
#ifndef CFG_HAS_STRUCT_MIN_TOUCH_COUNT
  #define CFG_HAS_STRUCT_MIN_TOUCH_COUNT 1
#endif
#ifndef CFG_HAS_STRUCT_ZONE_MIN_SCORE
  #define CFG_HAS_STRUCT_ZONE_MIN_SCORE 1
#endif

// --- Patterns: SD base patterns (RBR/DBD/RBD/DBR) settings ---
#ifndef CFG_HAS_PATTERNS_SD_SETTINGS
  #define CFG_HAS_PATTERNS_SD_SETTINGS 1
#endif
#ifndef CFG_HAS_PATTERNS_SD_SETTINGS_FIELDS
  // Settings contains sd_* members used by Confluence->Patterns runtime mapping
  #define CFG_HAS_PATTERNS_SD_SETTINGS_FIELDS 1
#endif

// --- Universal Pattern (Patterns.mqh best-kind + risk + events) settings ---
#ifndef CFG_HAS_PATT_SETTINGS
  #define CFG_HAS_PATT_SETTINGS 1
#endif
#ifndef CFG_HAS_PATT_SETTINGS_FIELDS
  // Settings contains patt_* members used by Confluence->Patterns runtime mapping
  #define CFG_HAS_PATT_SETTINGS_FIELDS 1
#endif

#ifndef CFG_HAS_PATT_MODE
  #define CFG_HAS_PATT_MODE 1
#endif
#ifndef CFG_HAS_PATT_MIN_QUALITY01
  #define CFG_HAS_PATT_MIN_QUALITY01 1
#endif
#ifndef CFG_HAS_PATT_RETEST_WINDOW_BARS
  #define CFG_HAS_PATT_RETEST_WINDOW_BARS 1
#endif
#ifndef CFG_HAS_PATT_STOP_ATR_MULT
  #define CFG_HAS_PATT_STOP_ATR_MULT 1
#endif
#ifndef CFG_HAS_PATT_TARGET_HEIGHT_MULT
  #define CFG_HAS_PATT_TARGET_HEIGHT_MULT 1
#endif
#ifndef CFG_HAS_PATT_EMIT_CANDLES
  #define CFG_HAS_PATT_EMIT_CANDLES 1
#endif
#ifndef CFG_HAS_PATT_EMIT_CLASSIC
  #define CFG_HAS_PATT_EMIT_CLASSIC 1
#endif
#ifndef CFG_HAS_PATT_EMIT_AUTOC
  #define CFG_HAS_PATT_EMIT_AUTOC 1
#endif

// --- Universal Pattern (AMPDI inputs + thresholds) ---
#ifndef CFG_HAS_PATT_ATR_PERIOD
  #define CFG_HAS_PATT_ATR_PERIOD 1
#endif
#ifndef CFG_HAS_PATT_EMA_FAST
  #define CFG_HAS_PATT_EMA_FAST 1
#endif
#ifndef CFG_HAS_PATT_EMA_SLOW
  #define CFG_HAS_PATT_EMA_SLOW 1
#endif
#ifndef CFG_HAS_PATT_VOLUME_SMA_PERIOD
  #define CFG_HAS_PATT_VOLUME_SMA_PERIOD 1
#endif
#ifndef CFG_HAS_PATT_VOLUME_MULT
  #define CFG_HAS_PATT_VOLUME_MULT 1
#endif
#ifndef CFG_HAS_PATT_USE_VOLUME_FILTER
  #define CFG_HAS_PATT_USE_VOLUME_FILTER 1
#endif
#ifndef CFG_HAS_PATT_USE_MOMENTUM
  #define CFG_HAS_PATT_USE_MOMENTUM 1
#endif
#ifndef CFG_HAS_PATT_RSI_PERIOD
  #define CFG_HAS_PATT_RSI_PERIOD 1
#endif
#ifndef CFG_HAS_PATT_PIVOT_L
  #define CFG_HAS_PATT_PIVOT_L 1
#endif
#ifndef CFG_HAS_PATT_PIVOT_R
  #define CFG_HAS_PATT_PIVOT_R 1
#endif
#ifndef CFG_HAS_PATT_TOL_ATR_K
  #define CFG_HAS_PATT_TOL_ATR_K 1
#endif
#ifndef CFG_HAS_PATT_MIN_SCORE01
  #define CFG_HAS_PATT_MIN_SCORE01 1
#endif

#ifndef CFG_HAS_PATT_CS_HAMMER_BODY_PCT_MAX
  #define CFG_HAS_PATT_CS_HAMMER_BODY_PCT_MAX 1
#endif
#ifndef CFG_HAS_PATT_CS_HAMMER_LW_BODY_MULT
  #define CFG_HAS_PATT_CS_HAMMER_LW_BODY_MULT 1
#endif
#ifndef CFG_HAS_PATT_CS_HAMMER_UW_BODY_MULT
  #define CFG_HAS_PATT_CS_HAMMER_UW_BODY_MULT 1
#endif
#ifndef CFG_HAS_PATT_CS_SPIN_BODY_PCT_MAX
  #define CFG_HAS_PATT_CS_SPIN_BODY_PCT_MAX 1
#endif
#ifndef CFG_HAS_PATT_CS_SPIN_WICK_SYM_RNG_PCT
  #define CFG_HAS_PATT_CS_SPIN_WICK_SYM_RNG_PCT 1
#endif
#ifndef CFG_HAS_PATT_CS_DOJI_BODY_RNG_PCT
  #define CFG_HAS_PATT_CS_DOJI_BODY_RNG_PCT 1
#endif
#ifndef CFG_HAS_PATT_CS_DOJI_UW_RNG_PCT
  #define CFG_HAS_PATT_CS_DOJI_UW_RNG_PCT 1
#endif
#ifndef CFG_HAS_PATT_CS_DOJI_LW_RNG_PCT
  #define CFG_HAS_PATT_CS_DOJI_LW_RNG_PCT 1
#endif
#ifndef CFG_HAS_PATT_CS_STAR_BODY3_RNG_MIN
  #define CFG_HAS_PATT_CS_STAR_BODY3_RNG_MIN 1
#endif
#ifndef CFG_HAS_PATT_CS_STAR_RETRACE_BODY1_K
  #define CFG_HAS_PATT_CS_STAR_RETRACE_BODY1_K 1
#endif

// --- WyckoffCycle core knobs (range/BOS/manip/volume) ---
#ifndef CFG_HAS_WYCK_CYCLE_SETTINGS
  #define CFG_HAS_WYCK_CYCLE_SETTINGS 1
#endif

#ifndef CFG_HAS_MAIN_CHART_RETEST_MAX_ATR
  #define CFG_HAS_MAIN_CHART_RETEST_MAX_ATR 1
#endif
#ifndef CFG_HAS_MAIN_MIN_RR_FROM_CHART_TARGET
  #define CFG_HAS_MAIN_MIN_RR_FROM_CHART_TARGET 1
#endif
#ifndef CFG_HAS_MAIN_AUTOC_COMPLETED_DIR_VETO
  #define CFG_HAS_MAIN_AUTOC_COMPLETED_DIR_VETO 1
#endif
#ifndef CFG_HAS_MAIN_AUTOC_TIGHTEN_INVAL
  #define CFG_HAS_MAIN_AUTOC_TIGHTEN_INVAL 1
#endif
#ifndef CFG_HAS_AUTOCHART_RR_NORM
  #define CFG_HAS_AUTOCHART_RR_NORM 1
#endif
#ifndef CFG_HAS_AUTO_KEY_MIN_SIG
  #define CFG_HAS_AUTO_KEY_MIN_SIG 1
#endif

// --- Entry gating taps (PositionMgmt / Router)
#ifndef CFG_HAS_ROUTER_EVAL_ALL_MODE
  #define CFG_HAS_ROUTER_EVAL_ALL_MODE 1
#endif
#ifndef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
  #define CFG_HAS_MAX_POSITIONS_PER_SYMBOL 1
#endif
#ifndef CFG_HAS_MAX_POSITIONS_TOTAL
  #define CFG_HAS_MAX_POSITIONS_TOTAL 1
#endif
#ifndef CFG_HAS_MAX_TRADES_DAY
  #define CFG_HAS_MAX_TRADES_DAY 1
#endif

// --- Strategy enable toggles are present in Settings (compile-safe macros used across modules)
#ifndef CFG_HAS_ENABLE_STRAT_MAIN
  #define CFG_HAS_ENABLE_STRAT_MAIN 1
#endif
#ifndef CFG_HAS_ENABLE_STRAT_ICT_SILVERBULLET
  #define CFG_HAS_ENABLE_STRAT_ICT_SILVERBULLET 1
#endif
#ifndef CFG_HAS_ENABLE_STRAT_ICT_PO3
  #define CFG_HAS_ENABLE_STRAT_ICT_PO3 1
#endif
#ifndef CFG_HAS_ENABLE_STRAT_ICT_CONTINUATION
  #define CFG_HAS_ENABLE_STRAT_ICT_CONTINUATION 1
#endif
#ifndef CFG_HAS_ENABLE_STRAT_ICT_WYCKOFF_TURN
  #define CFG_HAS_ENABLE_STRAT_ICT_WYCKOFF_TURN 1
#endif

// --- Compatibility bridge (older code paths / older naming)
// Presence aliases
#ifndef CFG_HAS_ENABLE_STRAT_ICT_SB
  #define CFG_HAS_ENABLE_STRAT_ICT_SB 1
#endif
#ifndef CFG_HAS_ENABLE_STRAT_ICT_OBFVG_OTE
  #define CFG_HAS_ENABLE_STRAT_ICT_OBFVG_OTE 1
#endif
#ifndef CFG_HAS_ENABLE_STRAT_ICT_WYCKOFF
  #define CFG_HAS_ENABLE_STRAT_ICT_WYCKOFF 1
#endif

// Field-name aliases (so cfg.enable_strat_ict_* older tokens map to current fields)
#ifndef enable_strat_ict_sb
  #define enable_strat_ict_sb enable_strat_ict_silverbullet
#endif
#ifndef enable_strat_ict_obfvg_ote
  #define enable_strat_ict_obfvg_ote enable_strat_ict_continuation
#endif
#ifndef enable_strat_ict_wyckoff
  #define enable_strat_ict_wyckoff enable_strat_ict_wyckoff_turn
#endif

// --- Pack strategy registration/runtime toggles (used by StrategyRegistry/Router)
#ifndef CFG_HAS_ENABLE_PACK_STRATS
  #define CFG_HAS_ENABLE_PACK_STRATS 1
#endif

// Back-compat: some modules may use the older token name
#ifndef CFG_HAS_ENABLE_STRAT_PACKS
  #define CFG_HAS_ENABLE_STRAT_PACKS 1
#endif
#ifndef enable_strat_packs
  #define enable_strat_packs enable_pack_strats
#endif

// Optional fail-safe kill switch (prefer fail-closed naming)
#ifndef CFG_HAS_DISABLE_PACKS
  #define CFG_HAS_DISABLE_PACKS 1
#endif
#ifndef disable_pack_strats
  #define disable_pack_strats disable_packs
#endif

#ifndef CFG_HAS_PARTIAL_ENABLE
  #define CFG_HAS_PARTIAL_ENABLE 1
#endif
#ifndef CFG_HAS_P1_AT_R
  #define CFG_HAS_P1_AT_R 1
#endif
#ifndef CFG_HAS_P1_CLOSE_PCT
  #define CFG_HAS_P1_CLOSE_PCT 1
#endif
#ifndef CFG_HAS_P2_AT_R
  #define CFG_HAS_P2_AT_R 1
#endif
#ifndef CFG_HAS_P2_CLOSE_PCT
  #define CFG_HAS_P2_CLOSE_PCT 1
#endif

#ifndef NEWSFILTER_AVAILABLE
  #define NEWSFILTER_AVAILABLE 1
#endif

// --- NewsFilter runtime settings are present in Config::Settings (used by News::ConfigureFromEA)
#ifndef CFG_HAS_NEWS_BACKEND
   #define CFG_HAS_NEWS_BACKEND 1
#endif
#ifndef CFG_HAS_NEWS_MVP_NO_BLOCK
   #define CFG_HAS_NEWS_MVP_NO_BLOCK 1
#endif
#ifndef CFG_HAS_NEWS_FAILOVER_TO_CSV
   #define CFG_HAS_NEWS_FAILOVER_TO_CSV 1
#endif
#ifndef CFG_HAS_NEWS_NEUTRAL_ON_NODATA
   #define CFG_HAS_NEWS_NEUTRAL_ON_NODATA 1
#endif

#ifndef CFG_HAS_ADX_PARAMS
  #define CFG_HAS_ADX_PARAMS 1
#endif
#ifndef CFG_HAS_ADX_UPPER
  #define CFG_HAS_ADX_UPPER 1
#endif
#ifndef CFG_HAS_CORR_REF
  #define CFG_HAS_CORR_REF 1
#endif
#ifndef CFG_HAS_CORR_LOOKBACK
  #define CFG_HAS_CORR_LOOKBACK 1
#endif
#ifndef CFG_HAS_CORR_ABS_MIN
  #define CFG_HAS_CORR_ABS_MIN 1
#endif
#ifndef CFG_HAS_CORR_TF
  #define CFG_HAS_CORR_TF 1
#endif
#ifndef CFG_HAS_CORR_MAX_PEN
  #define CFG_HAS_CORR_MAX_PEN 1
#endif
#ifndef CFG_HAS_W_ADX_REGIME
  #define CFG_HAS_W_ADX_REGIME 1
#endif
#ifndef CFG_HAS_W_NEWS
  #define CFG_HAS_W_NEWS 1
#endif
#ifndef CFG_HAS_W_CORR_PEN
  #define CFG_HAS_W_CORR_PEN 1
#endif

// Optional Settings fields you want live (align with Types.mqh step 0)
#ifndef CFG_HAS_TRADE_CD_SEC
  #define CFG_HAS_TRADE_CD_SEC 1
#endif
// Legacy ICT toggle fields (define these ONLY if the legacy Settings fields exist)
// #define CFG_HAS_LEGACY_ICT_PO3
// #define CFG_HAS_LEGACY_ICT_SILVERBULLET
// #define CFG_HAS_LEGACY_ICT_WYCKOFF_UTAD
#ifndef CFG_HAS_STRATEGY_KIND
  #define CFG_HAS_STRATEGY_KIND 1
#endif
// Confluence gates and extras (these fields are always present in Settings)
#ifndef CFG_HAS_CF_MIN_NEEDED
  #define CFG_HAS_CF_MIN_NEEDED 1
#endif
#ifndef CFG_HAS_CF_MIN_SCORE
  #define CFG_HAS_CF_MIN_SCORE 1
#endif
#ifndef CFG_HAS_MAIN_SEQGATE
  #define CFG_HAS_MAIN_SEQGATE 1
#endif
#ifndef CFG_HAS_ORDERFLOW_TH
  #define CFG_HAS_ORDERFLOW_TH 1
#endif
#ifndef CFG_HAS_MAIN_REQUIRE_CHECKLIST
  #define CFG_HAS_MAIN_REQUIRE_CHECKLIST 1
#endif
#ifndef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
  #define CFG_HAS_MAIN_CONFIRM_ANY_OF_3 1
#endif
#ifndef CFG_HAS_MAIN_REQUIRE_CLASSICAL
  #define CFG_HAS_MAIN_REQUIRE_CLASSICAL 1
#endif
#ifndef CFG_HAS_VSA_ALLOW_TICK_VOLUME
  #define CFG_HAS_VSA_ALLOW_TICK_VOLUME 1
#endif
#ifndef CFG_HAS_TF_TREND_HTF
  #define CFG_HAS_TF_TREND_HTF 1
#endif

#ifndef CFG_HAS_EXTRA_VOLUME_FP
  #define CFG_HAS_EXTRA_VOLUME_FP 1
#endif
#ifndef CFG_HAS_W_VOLUME_FP
  #define CFG_HAS_W_VOLUME_FP 1
#endif

#ifndef CFG_HAS_EXTRA_DOM_IMBALANCE
  #define CFG_HAS_EXTRA_DOM_IMBALANCE 1
#endif
#ifndef CFG_HAS_W_DOM_IMBALANCE
  #define CFG_HAS_W_DOM_IMBALANCE 1
#endif
#ifndef CFG_HAS_DEBUG_DOM
  #define CFG_HAS_DEBUG_DOM 1
#endif
#ifndef CFG_HAS_DOM_ZONE_PAD_POINTS
  #define CFG_HAS_DOM_ZONE_PAD_POINTS 1
#endif
#ifndef CFG_HAS_DOM_MIN_ABS_IMB
  #define CFG_HAS_DOM_MIN_ABS_IMB 1
#endif

// --- OBI (alias of DOM imbalance knobs) ---
#ifndef CFG_HAS_EXTRA_OBI
  #define CFG_HAS_EXTRA_OBI 1
#endif
#ifndef CFG_HAS_W_OBI
  #define CFG_HAS_W_OBI 1
#endif

// Field-name aliases so downstream code can use cfg.<alias> without duplicating storage
#ifndef CFG_FIELD_EXTRA_OBI
  #define CFG_FIELD_EXTRA_OBI extra_dom_imbalance
#endif
#ifndef CFG_FIELD_W_OBI
  #define CFG_FIELD_W_OBI w_dom_imbalance
#endif

// --- Trendlines (new confluence provider) ---
#ifndef CFG_HAS_EXTRA_TRENDLINES
  #define CFG_HAS_EXTRA_TRENDLINES 1
#endif
#ifndef CFG_HAS_W_TRENDLINES
  #define CFG_HAS_W_TRENDLINES 1
#endif

#ifndef CFG_HAS_EXTRA_STOCHRSI
  #define CFG_HAS_EXTRA_STOCHRSI 1
#endif
#ifndef CFG_HAS_STOCHRSI_PARAMS
  #define CFG_HAS_STOCHRSI_PARAMS 1
#endif

#ifndef CFG_HAS_STOCHRSI_K_SMOOTH
  #define CFG_HAS_STOCHRSI_K_SMOOTH 1
#endif
#ifndef CFG_HAS_STOCHRSI_D_SMOOTH
  #define CFG_HAS_STOCHRSI_D_SMOOTH 1
#endif
#ifndef CFG_HAS_STOCHRSI_RSI_PERIOD
  #define CFG_HAS_STOCHRSI_RSI_PERIOD 1
#endif
#ifndef CFG_HAS_STOCHRSI_K_PERIOD
  #define CFG_HAS_STOCHRSI_K_PERIOD 1
#endif
#ifndef CFG_HAS_STOCHRSI_OB
  #define CFG_HAS_STOCHRSI_OB 1
#endif
#ifndef CFG_HAS_STOCHRSI_OS
  #define CFG_HAS_STOCHRSI_OS 1
#endif
#ifndef CFG_HAS_W_STOCHRSI
  #define CFG_HAS_W_STOCHRSI 1
#endif

#ifndef CFG_HAS_EXTRA_MACD
  #define CFG_HAS_EXTRA_MACD 1
#endif
#ifndef CFG_HAS_MACD_FAST
  #define CFG_HAS_MACD_FAST 1
#endif
#ifndef CFG_HAS_MACD_SLOW
  #define CFG_HAS_MACD_SLOW 1
#endif
#ifndef CFG_HAS_MACD_SIGNAL
  #define CFG_HAS_MACD_SIGNAL 1
#endif
#ifndef CFG_HAS_W_MACD
  #define CFG_HAS_W_MACD 1
#endif
#ifndef CFG_HAS_MACD_PARAMS
  #define CFG_HAS_MACD_PARAMS 1
#endif
#ifndef CFG_HAS_MACD_PRICE
  #ifdef INDI_HAS_MACD_AP
    #define CFG_HAS_MACD_PRICE 1
  #endif
#endif

#ifndef CFG_HAS_EXTRA_ADX_REGIME
  #define CFG_HAS_EXTRA_ADX_REGIME 1
#endif
#ifndef CFG_HAS_ADX_PERIOD
  #define CFG_HAS_ADX_PERIOD 1
#endif
#ifndef CFG_HAS_ADX_MIN
  #define CFG_HAS_ADX_MIN 1
#endif

#ifndef CFG_HAS_EXTRA_CORR
  #define CFG_HAS_EXTRA_CORR 1
#endif
#ifndef CFG_HAS_CORR_REF_SYMBOL
  #define CFG_HAS_CORR_REF_SYMBOL 1
#endif
#ifndef CFG_HAS_CORR_MIN_ABS
  #define CFG_HAS_CORR_MIN_ABS 1
#endif
#ifndef CFG_HAS_W_CORR
  #define CFG_HAS_W_CORR 1
#endif

#ifndef CFG_HAS_EXTRA_NEWS
  #define CFG_HAS_EXTRA_NEWS 1
#endif
#ifndef CFG_HAS_MAIN_NEWS_HARD_VETO
  #define CFG_HAS_MAIN_NEWS_HARD_VETO 1
#endif

#ifndef CFG_HAS_EXTRA_SILVERBULLET_TZ
  #define CFG_HAS_EXTRA_SILVERBULLET_TZ 1
#endif
#ifndef CFG_HAS_W_SILVERBULLET_TZ
  #define CFG_HAS_W_SILVERBULLET_TZ 1
#endif

#ifndef CFG_HAS_EXTRA_AMD_HTF
  #define CFG_HAS_EXTRA_AMD_HTF 1
#endif
#ifndef CFG_HAS_W_AMD_H1
  #define CFG_HAS_W_AMD_H1 1
#endif
#ifndef CFG_HAS_W_AMD_H4
  #define CFG_HAS_W_AMD_H4 1
#endif

#ifndef CFG_HAS_EXTRA_PO3_HTF
  #define CFG_HAS_EXTRA_PO3_HTF 1
#endif
#ifndef CFG_HAS_W_PO3_H1
  #define CFG_HAS_W_PO3_H1 1
#endif
#ifndef CFG_HAS_W_PO3_H4
  #define CFG_HAS_W_PO3_H4 1
#endif

#ifndef CFG_HAS_EXTRA_WYCKOFF_TURN
  #define CFG_HAS_EXTRA_WYCKOFF_TURN 1
#endif
#ifndef CFG_HAS_W_WYCKOFF_TURN
  #define CFG_HAS_W_WYCKOFF_TURN 1
#endif

// --- Phase context (Wyckoff/PO3 cycle alignment) ---
#ifndef CFG_HAS_EXTRA_PHASE_CTX
  #define CFG_HAS_EXTRA_PHASE_CTX 1
#endif
#ifndef CFG_HAS_W_PHASE_CTX
  #define CFG_HAS_W_PHASE_CTX 1
#endif

#ifndef CFG_HAS_EXTRA_MTF_ZONES
  #define CFG_HAS_EXTRA_MTF_ZONES 1
#endif
#ifndef CFG_HAS_W_MTF_ZONE_H1
  #define CFG_HAS_W_MTF_ZONE_H1 1
#endif
#ifndef CFG_HAS_W_MTF_ZONE_H4
  #define CFG_HAS_W_MTF_ZONE_H4 1
#endif
#ifndef CFG_HAS_MTF_ZONE_MAX_DIST_ATR
  #define CFG_HAS_MTF_ZONE_MAX_DIST_ATR 1
#endif

#ifndef CFG_HAS_EXTRA_CONFL
  #define CFG_HAS_EXTRA_CONFL 1
#endif

#ifndef CFG_HAS_LONDON_LOCAL_MINUTES
  #define CFG_HAS_LONDON_LOCAL_MINUTES 1
#endif

#ifndef CFG_HAS_CARRY_ENABLE
  #define CFG_HAS_CARRY_ENABLE 1
#endif
#ifndef CFG_HAS_CARRY_BOOST_MAX
  #define CFG_HAS_CARRY_BOOST_MAX 1
#endif
#ifndef CFG_HAS_CARRY_RISK_SPAN
  #define CFG_HAS_CARRY_RISK_SPAN 1
#endif

#ifndef PROFILE_SPEC_AVAILABLE
  #define PROFILE_SPEC_AVAILABLE 1
#endif
#ifndef CFG_HAS_ROUTER_HINTS
  #define CFG_HAS_ROUTER_HINTS 1
#endif
#ifndef CFG_HAS_LIQPOOL_FIELDS
  #define CFG_HAS_LIQPOOL_FIELDS 1
#endif

#ifndef CFG_HAS_ENABLE_HARD_GATE
  #define CFG_HAS_ENABLE_HARD_GATE 1
#endif
#ifndef CFG_HAS_MIN_FEATURES_MET
  #define CFG_HAS_MIN_FEATURES_MET 1
#endif
#ifndef CFG_HAS_REQUIRE_TREND_FILTER
  #define CFG_HAS_REQUIRE_TREND_FILTER 1
#endif
#ifndef CFG_HAS_REQUIRE_ADX_REGIME
  #define CFG_HAS_REQUIRE_ADX_REGIME 1
#endif
#ifndef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
  #define CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB 1
#endif
#ifndef CFG_HAS_SB_REQUIRE_OTE
  #define CFG_HAS_SB_REQUIRE_OTE 1
#endif
#ifndef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
  #define CFG_HAS_SB_REQUIRE_VWAP_STRETCH 1
#endif
#ifndef CFG_HAS_LONDON_LIQ_POLICY
  #define CFG_HAS_LONDON_LIQ_POLICY 1
#endif

// Router knobs (ensure both aliases exist)
#ifndef CFG_HAS_ROUTER_MIN_SCORE
  #define CFG_HAS_ROUTER_MIN_SCORE 1
#endif
#ifndef CFG_HAS_ROUTER_MAX_STRATS
  #define CFG_HAS_ROUTER_MAX_STRATS 1
#endif
#ifndef CFG_HAS_ROUTER_FALLBACK_MIN
  #define CFG_HAS_ROUTER_FALLBACK_MIN 1
#endif
#ifndef CFG_HAS_ROUTER_FB_MIN
  #define CFG_HAS_ROUTER_FB_MIN 1
#endif
// Router confluence-only pool toggles (optional)
#ifndef CFG_HAS_ROUTER_USE_CONFL_POOL
  #define CFG_HAS_ROUTER_USE_CONFL_POOL 1
#endif
#ifndef CFG_HAS_ROUTER_POOL_BLEND_W
  #define CFG_HAS_ROUTER_POOL_BLEND_W 1
#endif
#ifndef ROUTER_GUESS_CORE_ID_WHEN_MISSING
  #define ROUTER_GUESS_CORE_ID_WHEN_MISSING 1
#endif 

// --- Daily DD / profit taper feature flags (compile-safe) --------------------
#ifndef CFG_HAS_MAX_DAILY_DD_PCT
  #define CFG_HAS_MAX_DAILY_DD_PCT 1
#endif
#ifndef CFG_HAS_DAY_DD_LIMIT_PCT
  #define CFG_HAS_DAY_DD_LIMIT_PCT 1
#endif
#ifndef CFG_HAS_DAY_PROFIT_CAP_PCT
  #define CFG_HAS_DAY_PROFIT_CAP_PCT 1
#endif
#ifndef CFG_HAS_DAY_PROFIT_STOP_PCT
  #define CFG_HAS_DAY_PROFIT_STOP_PCT 1
#endif
#ifndef CFG_HAS_TAPER_FLOOR
  #define CFG_HAS_TAPER_FLOOR 1
#endif

// --- Adaptive rolling-peak DD (compile-safe) ----------------------------------
#ifndef CFG_HAS_ADAPTIVE_DD_ENABLE
  #define CFG_HAS_ADAPTIVE_DD_ENABLE 1
#endif
#ifndef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
  #define CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS 1
#endif
#ifndef CFG_HAS_ADAPTIVE_DD_PCT
  #define CFG_HAS_ADAPTIVE_DD_PCT 1
#endif

// --- Big-loss reset latch (compile-safe) --------------------------------------
#ifndef CFG_HAS_BIGLOSS_RESET_ENABLE
  #define CFG_HAS_BIGLOSS_RESET_ENABLE 1
#endif
#ifndef CFG_HAS_BIGLOSS_RESET_R
  #define CFG_HAS_BIGLOSS_RESET_R 1
#endif
#ifndef CFG_HAS_BIGLOSS_RESET_MINS
  #define CFG_HAS_BIGLOSS_RESET_MINS 1
#endif

// --- Risk multiplier max cap (compile-safe) -----------------------------------
#ifndef CFG_HAS_RISK_MULT_MAX
  #define CFG_HAS_RISK_MULT_MAX 1
#endif

// --- Position management (PM) fields ---------------------------------------
#ifndef CFG_HAS_PM_MODE
 #define CFG_HAS_PM_MODE 1
#endif

// Optional but recommended (PositionMgmt can use them if present)
#ifndef CFG_HAS_PM_ALLOW_DAILY_FLATTEN
 #define CFG_HAS_PM_ALLOW_DAILY_FLATTEN 1
#endif

#ifndef CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS
 #define CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS 1
#endif

// --- Trailing AUTO ADX regime fields (compile-safe) ----------------------------
#ifndef CFG_HAS_TRAIL_AUTO_ADX_TF
  #define CFG_HAS_TRAIL_AUTO_ADX_TF 1
#endif
#ifndef CFG_HAS_TRAIL_AUTO_ADX_PERIOD
  #define CFG_HAS_TRAIL_AUTO_ADX_PERIOD 1
#endif
#ifndef CFG_HAS_TRAIL_AUTO_ADX_MIN
  #define CFG_HAS_TRAIL_AUTO_ADX_MIN 1
#endif

// --- Monthly profit target (compile-safe) ------------------------------------
// Primary feature switch (used by Settings and Policies)
#ifndef CFG_HAS_MONTHLY_TARGET
  #define CFG_HAS_MONTHLY_TARGET 1
#endif

// Backward-compat alias for any existing CFG_HAS_MONTHLY_TARGET_PCT usage
#ifndef CFG_HAS_MONTHLY_TARGET_PCT
  #define CFG_HAS_MONTHLY_TARGET_PCT CFG_HAS_MONTHLY_TARGET
#endif

// Default monthly target: 10.0 = +10% on starting equity of the month
#ifndef CFG_MONTHLY_TARGET_PCT
  #define CFG_MONTHLY_TARGET_PCT 10.0
#endif

// --- Monthly profit target (compile-safe) ------------------------------------
// Primary feature switch (used by Settings and Policies)
#ifndef CFG_HAS_MONTHLY_TARGET
  #define CFG_HAS_MONTHLY_TARGET 1
#endif

// Settings fields exist: allow EA to load cycle/base mode from inputs
#ifndef CFG_HAS_MONTHLY_TARGET_CYCLE_MODE
  #define CFG_HAS_MONTHLY_TARGET_CYCLE_MODE 1
#endif
#ifndef CFG_HAS_MONTHLY_TARGET_BASE_MODE
  #define CFG_HAS_MONTHLY_TARGET_BASE_MODE 1
#endif

// Backward-compat alias for any existing CFG_HAS_MONTHLY_TARGET_PCT usage
#ifndef CFG_HAS_MONTHLY_TARGET_PCT
  #define CFG_HAS_MONTHLY_TARGET_PCT CFG_HAS_MONTHLY_TARGET
#endif

// Default monthly target: 10.0 = +10%
#ifndef CFG_MONTHLY_TARGET_PCT
  #define CFG_MONTHLY_TARGET_PCT 10.0
#endif

// Monthly target cycle mode (Config contract)
// 0 = calendar month, 1 = rolling 28-day cycle
#ifndef CFG_TARGET_CYCLE_CALENDAR
  #define CFG_TARGET_CYCLE_CALENDAR 0
#endif
#ifndef CFG_TARGET_CYCLE_ROLLING_28D
  #define CFG_TARGET_CYCLE_ROLLING_28D 1
#endif
#ifndef CFG_TARGET_CYCLE_DEFAULT
  #define CFG_TARGET_CYCLE_DEFAULT CFG_TARGET_CYCLE_CALENDAR
#endif

// Monthly target base mode (Config contract)
// 0 = cycle-start equity (typical compounding behavior)
// 1 = initial equity (linear target per cycle)
// 2 = initial equity (compound-style target per cycle)
#ifndef CFG_TARGET_BASE_CYCLE_START
  #define CFG_TARGET_BASE_CYCLE_START 0
#endif
#ifndef CFG_TARGET_BASE_INITIAL_LINEAR
  #define CFG_TARGET_BASE_INITIAL_LINEAR 1
#endif
#ifndef CFG_TARGET_BASE_INITIAL_COMPOUND
  #define CFG_TARGET_BASE_INITIAL_COMPOUND 2
#endif
#ifndef CFG_TARGET_BASE_DEFAULT
  // Default to INITIAL_LINEAR to meet “10% of initial equity per cycle” behavior out-of-box
  #define CFG_TARGET_BASE_DEFAULT CFG_TARGET_BASE_INITIAL_LINEAR
#endif

// --- Account-wide (challenge) DD feature flags (for Policies) ---------------
#ifndef CFG_HAS_MAX_ACCOUNT_DD_PCT
  #define CFG_HAS_MAX_ACCOUNT_DD_PCT 1
#endif
#ifndef CFG_HAS_CHALLENGE_INIT_EQUITY
  #define CFG_HAS_CHALLENGE_INIT_EQUITY 1
#endif

// (Optional/informational) news risk blending in confluence
#ifndef CONFL_NEWS_RISK_ENABLE
  #define CONFL_NEWS_RISK_ENABLE 1
#endif
#ifndef CONFL_GATE_COUNT_NEWS
  #define CONFL_GATE_COUNT_NEWS 0
#endif

#include "NewsFilter.mqh"
#include "Confluence.mqh"

#ifndef CFG_HAS_WEEKLY_OPEN_RAMP
  #define CFG_HAS_WEEKLY_OPEN_RAMP 1
#endif

//────────────────────────────────────────────────────────────────────
// Carry policy macro defaults (diagnostics-only as signal originator)
//────────────────────────────────────────────────────────────────────
#ifndef CARRY_CAN_SIGNAL
  #define CARRY_CAN_SIGNAL 0
#endif

// ===== Global convenience wrappers for session flags/preset =====
// These are used from CA_Trading_System_EA.mq5 without the Config:: qualifier.
// Keep them in the global scope to avoid verbose namespace calls.
#ifndef EA_CFG_SESSION_HELPERS_GUARD
#define EA_CFG_SESSION_HELPERS_GUARD
inline bool CfgSessionFilter(const Settings &cfg)
{
  return cfg.session_filter; // simple field pass-through
}

inline SessionPreset CfgSessionPreset(const Settings &cfg)
{
  return (SessionPreset)cfg.session_preset; // preserve enum cast
}

// ---------------------------------------------------------------------------
// ICTLiquidityConfig: thin adapter over Settings → Lux-style liquidity pools
// ---------------------------------------------------------------------------
struct ICTLiquidityConfig
{
   int    LiquiditySweepMultiTapMin;     // default 2
   double LiquidityClusterMinPools;      // default 2.0
   double LiquidityClusterSkewThreshold; // e.g. 0.5
   double LiquiditySweepMinExcursionATR; // e.g. 0.5 ATR for displacement
};

// Fill ICT liquidity tuning from Settings → ICTLiquidityConfig.
inline void FillICTLiquidityConfig(const Settings &cfg, ICTLiquidityConfig &out)
{
  // Always start from sane defaults (caller may pass a dirty struct)
  out.LiquiditySweepMultiTapMin     = 2;
  out.LiquidityClusterMinPools      = 2.0;
  out.LiquidityClusterSkewThreshold = 0.5;
  out.LiquiditySweepMinExcursionATR = 0.50;
  
  // Multi-tap requirement for a valid sweep
  out.LiquiditySweepMultiTapMin =
    (cfg.liqPoolMinTouches > 0 ? cfg.liqPoolMinTouches : 2);

  // How many distinct pools/shelves we want to see in a cluster.
  double minPools = (double)cfg.liqPoolMinTouches;
  if(minPools < 2.0) minPools = 2.0;
  out.LiquidityClusterMinPools = minPools;

  // Skew threshold: how biased the cluster must be to one side (0..1).
  out.LiquidityClusterSkewThreshold = 0.5;

  // Minimum ATR excursion to treat a move as a genuine sweep/stop-hunt
  out.LiquiditySweepMinExcursionATR =
    (cfg.liqPoolMinSweepATR > 0.0 ? cfg.liqPoolMinSweepATR : 0.50);
}

// ========= Minimal KV shim (uses Global Variables if you don't have a KV lib) =========
#ifndef CA_KV_SHIM_GUARD
#define CA_KV_SHIM_GUARD
namespace KV {
  inline bool GetDouble(const string key, double &out){
    if(GlobalVariableCheck(key)){ out = GlobalVariableGet(key); return true; }
    return false;
  }
  inline bool GetInt(const string key, int &out){
    double v=0.0; if(GetDouble(key,v)){ out=(int)MathRound(v); return true; }
    return false;
  }
}
#endif

namespace Config
{
  //──────────────────────────────────────────────────────────────────
  // Small utils
  //──────────────────────────────────────────────────────────────────
  inline string Trim(const string s){ string t=s; StringTrimLeft(t); StringTrimRight(t); return t; }
  inline string BoolStr(const bool v){ return (v?"1":"0"); }
  
  // Directional bias gating mode
  enum DirectionBiasMode
  {
     DIRM_MANUAL_SELECTOR = 0,
     DIRM_AUTO_SMARTMONEY = 1
  };
  
  // Autochartist patterns export level (single source of truth)
  enum AutoPattExportLevel
  {
     AUTOC_PATT_EXPORT_OFF  = 0, // no patterns computed/exported by AutoC
     AUTOC_PATT_EXPORT_BEST = 1, // AC best + minimal summaries
     AUTOC_PATT_EXPORT_EXT  = 2, // BEST + best CS/CH/SD
     AUTOC_PATT_EXPORT_FULL = 3  // EXT + full bank exports (patt_all)
  };

  // Autochartist pattern event emission policy (used by AutoC / scanners)
  enum AutoPattEmitMode
  {
     AUTOC_PATT_EMIT_DIGEST_CHANGE = 0,
     AUTOC_PATT_EMIT_TOP_CHANGE    = 1,
     AUTOC_PATT_EMIT_ALWAYS        = 2
  };
  
  inline string Join(const string &arr[], const string sep)
  {
    const int n=ArraySize(arr);
    if(n<=0) return "";
    string r=arr[0];
    for(int i=1;i<n;i++){ r+=sep; r+=arr[i]; }
    return r;
  }

  // split by ';' or ',' (auto-detect)
  inline int SplitCSV(const string csv, string &out[])
  {
    const int semi = StringFind(csv, ";");
    const int comm = StringFind(csv, ",");
    const ushort delim = (semi>=0 ? ';' : (comm>=0 ? ',' : ','));
    return StringSplit(csv, (ushort)delim, out);
  }

  // Basic kv splitter "k=v"
  inline bool SplitKV(const string line, string &k, string &v)
  {
    int p=StringFind(line,"=");
    if(p<=0) return false;
    k=Trim(StringSubstr(line,0,p)); v=Trim(StringSubstr(line,p+1));
    return (StringLen(k)>0);
  }

  // FNV-1a 64-bit on 16-bit code units (MQL string)
  inline ulong FNV1a64_Str(const string s)
  {
    // Safe 64-bit construction (avoids signed-literal overflow in MQL5)
    const ulong FNV_OFFSET = (((ulong)0xCBF29CE4) << 32) | 0x84222325;
    const ulong FNV_PRIME  = (((ulong)0x00000100) << 32) | 0x000001B3;
    ulong h=FNV_OFFSET;
    const int len=(int)StringLen(s);
    for(int i=0;i<len;i++)
    {
      uint ch=(uint)StringGetCharacter(s,i);
      h^=(ulong)ch; h*=FNV_PRIME;
      h^=(ulong)((ch>>8)&0xFF); h*=FNV_PRIME;
    }
    return h;
  }

  inline string U64ToHex(const ulong v)
  {
    const uint hi = (uint)(v >> 32);
    const uint lo = (uint)(v & 0xFFFFFFFF);
    return StringFormat("%08X%08X", hi, lo);
  }

  inline double ToDouble(const string s){ return StringToDouble(s); }
  inline int    ToInt(const string s){ return (int)StringToInteger(s); }
  inline long   ToLong(const string s){ return (long)StringToInteger(s); }
  inline bool   ToBool(const string s){ string t=Trim(s); StringToLower(t); return (t=="1" || t=="true" || t=="on" || t=="yes"); }

  //──────────────────────────────────────────────────────────────────
  // Friendly string mappers (for summary logs)
  //──────────────────────────────────────────────────────────────────
  inline string TradeSelToString(const TradeSelector t)
  {
    if(t==TRADE_BUY_ONLY)  return "BUY_ONLY";
    if(t==TRADE_SELL_ONLY) return "SELL_ONLY";
    return "BOTH_AUTO";
  }

  inline string SessPresetToString(const SessionPreset s)
  {
    switch(s)
    {
      case SESS_TOKYO_C3_TO_LONDON_OPEN:  return "TKY_C-3>LON_O";
      case SESS_TOKYO_C3_TO_NY_OPEN:      return "TKY_C-3>NY_O";
      case SESS_TOKYO_C3_TO_NY_CLOSE:     return "TKY_C-3>NY_C";
      case SESS_LONDON_OPEN_TO_NY_OPEN:   return "LON_O>NY_O";
      case SESS_LONDON_OPEN_TO_NY_CLOSE:  return "LON_O>NY_C";
      case SESS_LONDON_OPEN_ONLY:         return "LON_O";
      case SESS_NY_OPEN_ONLY:             return "NY_O";
      case SESS_LONDON_CLOSE_ONLY:        return "LON_C";
      case SESS_NY_CLOSE_ONLY:            return "NY_C";
      case SESS_NY_C3_TO_TOKYO_CLOSE:     return "NY_C-3>TKY_C";
      case SESS_ALL_MAJOR:                return "ALL_MAJOR";
      case SESS_OFF:
      default:                            return "OFF";
    }
  }

  //──────────────────────────────────────────────────────────────────
  // Assets parsing
  //──────────────────────────────────────────────────────────────────
  inline void ParseAssets(const string csv, string &out[])
  {
    string c=Trim(csv);
    if(c=="" || StringCompare(c,"CURRENT",false)==0){ ArrayResize(out,1); out[0]=_Symbol; return; }
    string tmp[]; const int n=SplitCSV(c,tmp);
    if(n<=0){ ArrayResize(out,1); out[0]=_Symbol; return; }
    ArrayResize(out,n);
    for(int i=0;i<n;i++) out[i]=Trim(tmp[i]);
  }
  
  // ──────────────────────────────────────────────────────────────────
   // Small time helpers (local-only; avoid hard dependency on TimeUtils)
   inline int _mod1440(int v){ int r=v%1440; return (r<0? r+1440 : r); }
   inline bool _parse_hhmm(const string s, int &out_min)
   {
     string t=s; StringTrimLeft(t); StringTrimRight(t);
     string toks[]; int n=StringSplit(t, (ushort)':', toks);
     if(n<2 || n>3) return false;
     int h=(int)StringToInteger(toks[0]), m=(int)StringToInteger(toks[1]);
     if(h<0||h>23||m<0||m>59) return false;
     out_min=_mod1440(h*60+m); return true;
   }
   
   // ──────────────────────────────────────────────────────────────────
   // One struct for all “extras” so BuildSettingsEx signature is stable
   struct BuildExtras {
     // Confluence gates
     int    conf_min_count;   double conf_min_score;  bool main_sequential_gate;
     bool   main_require_checklist;
     bool   main_confirm_any_of_3;
     #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
       bool main_require_classical;
     #endif
     double orderflow_th;
     bool   vsa_allow_tick_volume; // VSA reliability: allow tick volume fallback (FX-friendly)
     ENUM_TIMEFRAMES tf_trend_htf; // 0 (PERIOD_CURRENT) means “use cfg.tf_h4”
     
     // Strategy pack registration (runtime replacement for ENABLE_LEGACY_STRATEGIES)
     bool   enable_pack_strats;   // default false
     bool   disable_packs;        // default false (fail-safe)
   
     // Volume footprint
     bool   extra_volume_footprint;  double w_volume_footprint;
   
     // DOM (MarketBook) imbalance (optional; broker capability dependent)
     bool   extra_dom_imbalance;
     int    dom_zone_pad_points;
     double dom_min_abs_imb;
     bool   debug_dom;
     double w_dom_imbalance;
     
     // StochRSI
     bool   extra_stochrsi; int stochrsi_rsi_period; int stochrsi_k_period; int stochrsi_k_smooth; int stochrsi_d_smooth;
     double stochrsi_ob; double stochrsi_os; double w_stochrsi;
   
     // MACD
     bool extra_macd; int macd_fast; int macd_slow; int macd_signal; double w_macd;
     #ifdef CFG_HAS_MACD_PRICE
       ENUM_APPLIED_PRICE macd_price;
     #endif
   
     // ADX regime
     bool extra_adx_regime; int adx_period; double adx_min; double w_adx_regime;
   
     // Correlation
     bool extra_corr; string corr_ref_symbol; int corr_lookback; double corr_min_abs; double w_corr;
   
     bool   extra_trendlines;
     double w_trendlines;
  
     // News (weight)
     bool extra_news; double w_news;
     #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
         bool main_news_hard_veto;  // true = treat news as hard veto in Main (vs soft/score-only)
     #endif
     
     // --- NewsFilter backend control (fed into Config::Settings, then News::ConfigureFromEA)
     int  news_backend_mode;        // 0=disabled, 1=broker, 2=csv, 3=auto
     bool news_mvp_no_block;        // if true => never hard-block (MVP safety)
     bool news_failover_to_csv;     // allow broker->csv fallback
     bool news_neutral_on_no_data;  // missing data => neutral (no block)
     bool news_allow_cached;
   
     #ifdef CFG_HAS_ML_SETTINGS
        // --- MLBlender runtime & lifecycle (meta-layer)
        bool   ml_enable;
        double ml_weight;
        double ml_temperature;
        double ml_conformal_alpha;
        double ml_dampen;
      
        #ifdef CFG_HAS_ML_SLTP_MULT
         // ML-suggested SL/TP multipliers (bounds only; actual values come from StrategyRegistry)
         bool   ml_sltp_enable;
         double ml_sltp_sl_min;
         double ml_sltp_sl_max;
         double ml_sltp_tp_min;
         double ml_sltp_tp_max;
       #endif

        bool   ml_auto_calibrate;
        int    ml_model_max_age_hours;
        double ml_min_oos_auc;
        double ml_min_oos_acc;
        int    ml_min_samples_train;
        int    ml_min_samples_test;
      
        int    ml_label_horizon_bars;
        double ml_label_atr_mult;
      
        bool   ml_use_common_files;
        string ml_model_file;
        string ml_dataset_file;
      
        bool   ml_external_enable;
        int    ml_external_mode;           // 0=off, 1=file, 2=socket
        string ml_external_file;
        int    ml_external_poll_ms;
        string ml_external_socket_host;
        int    ml_external_socket_port;
     #endif

     // Silver Bullet timezone window (extra confluence)
     bool   extra_silverbullet_tz;
     double w_silverbullet_tz;
      
     // AMD HTF phases (H1/H4 intraday context)
     bool   extra_amd_htf;
     double w_amd_h1;
     double w_amd_h4;

     // PO3 HTF phases (H1/H4 intraday context)
     bool   extra_po3_htf;
     double w_po3_h1;
     double w_po3_h4;

     // Wyckoff turn context (Spring / UTAD)
     bool   extra_wyckoff_turn;
     double w_wyckoff_turn;

     bool   extra_phase_ctx;
     double w_phase_ctx;

     // Multi-TF zones (H1/H4 zone proximity as confluence)
     bool   extra_mtf_zones;
     double w_mtf_zone_h1;
     double w_mtf_zone_h4;
     double mtf_zone_max_dist_atr;   // e.g., 1.0–1.5 ATR

     // Router / gates / require toggles
     bool enable_hard_gate; double router_min_score; double router_fb_min; int min_features_met;
     #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
       bool router_use_confl_pool;
     #endif
     #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
       double router_pool_blend_w;
     #endif
     bool require_trend; bool require_adx; bool require_struct_or_pattern_ob;
     
     // Silver Bullet hard requirements (optional)
     bool require_sb_ote;
     bool require_sb_vwap_stretch;
   
     // London liquidity window
     bool london_liq_policy; string london_start_local; string london_end_local;
     
     // Liquidity Pools (Lux-style)
     int    liqPoolMinTouches;          // min contacts to form pool
     int    liqPoolGapBars;             // min bars between touches
     int    liqPoolConfirmWaitBars;     // bars to wait before confirming zone
     double liqPoolLevelEpsATR;         // price proximity threshold in ATR units
     int    liqPoolMaxLookbackBars;     // max bars to keep pool “active”
     double liqPoolMinSweepATR;         // min sweep distance in ATR for “real” stop run
   
     // ATR-as-delta & vol regime
     bool use_atr_as_delta; int atr_period_2; double atr_vol_regime_floor;
   
     // Structure / OB
     int    struct_zz_depth, struct_htf_mult;
     double ob_prox_max_pips;
      
     double struct_zone_margin_pips;
     int    struct_min_touch_count;
     double struct_zone_min_score;
   
     // ATR ST/TP & risk
     bool use_atr_stops_targets; double atr_sl_mult2; double atr_tp_mult2; double risk_per_trade_pct;
   
     // Diagnostics
     bool log_veto_details; bool weekly_open_spread_ramp;
   };
   
   class ConfigCore
   {
   public:
     // If Normalize is already implemented elsewhere as Config::Normalize,
     // just keep its declaration here (don’t duplicate the body).
     static void Normalize(Settings &cfg);
   
     // Per-strategy control:
     static void DisableAllStrategies(Settings &cfg);
     static bool IsStratEnabledByName(const Settings &cfg, string name);
     // Return true if the strategy name was recognized and toggled, false otherwise.
     static bool EnableStrategyByName(Settings &cfg, string name, const bool on=true);
   };

   // ----------------------------------------------------------------------------
   // Public API wrappers (keeps call-sites stable: Config::DisableAllStrategies, etc.)
   // ----------------------------------------------------------------------------
   inline void DisableAllStrategies(Settings &cfg)
   {
     ConfigCore::DisableAllStrategies(cfg);
   }
   
   inline bool IsStratEnabledByName(const Settings &cfg, string name)
   {
     return ConfigCore::IsStratEnabledByName(cfg, name);
   }
   
   inline bool EnableStrategyByName(Settings &cfg, string name, const bool on=true)
   {
     return ConfigCore::EnableStrategyByName(cfg, name, on);
   }

   void ConfigCore::Normalize(Settings &cfg)
   {
     // Baseline hook intentionally left minimal.
     // All current normalization logic continues to live in the
     // namespace-level inline Normalize(Settings&) below.
     // Add legacy/low-level normalization here later if needed.
   }
   
   // Turn everything off (scenarios turn specific ones back on)
   void ConfigCore::DisableAllStrategies(Settings &cfg)
   {
     cfg.enable_strat_main             = false;
   
     cfg.enable_trend_vwap_pullback    = false;
     cfg.enable_trend_bos_continuation = false;
   
     cfg.enable_mr_vwap_band           = false;
     cfg.enable_mr_range_nr7ib         = false;
   
     cfg.enable_breakout_squeeze       = false;
     cfg.enable_breakout_orb           = false;
   
     cfg.enable_reversal_sweep_choch   = false;
     cfg.enable_reversal_vsa_climax_fade = false;
   
     cfg.enable_corr_divergence        = false;
     cfg.enable_pairs_spreadlite       = false; // or _spread_lite in your codebase
   
     cfg.enable_news_deviation         = false;
     cfg.enable_news_postfade          = false;
   
     cfg.enable_strat_ict_po3          = false;
     cfg.enable_strat_ict_silverbullet = false;
     cfg.enable_strat_ict_wyckoff_turn = false; // maps to spring/UTAD internal name
     
     #ifdef CFG_HAS_STRAT_TOGGLES
        cfg.strat_toggles_seeded = true; // lock defaults so Normalize() won't re-enable
     #endif
   }
   
   enum StratToggleId
   {
     ST_NONE = 0,
     ST_MAIN,
   
     ST_TREND_VWAP_PULLBACK,
     ST_TREND_BOS_CONT,
   
     ST_MR_VWAP_BAND,
     ST_MR_RANGE_NR7IB,
   
     ST_BREAKOUT_SQUEEZE,
     ST_BREAKOUT_ORB,
   
     ST_REV_SWEEP_CHOCH,
     ST_REV_VSA_CLIMAX_FADE,
   
     ST_CORR_DIVERGENCE,
     ST_PAIRS_SPREAD_LITE,
   
     ST_NEWS_DEVIATION,
     ST_NEWS_POSTFADE,
   
     ST_ICT_PO3,
     ST_ICT_SILVERBULLET,
     ST_ICT_WYCKOFF_TURN
   };

   inline StratToggleId _StratIdByName(const string &name)
   {
     const string n = _Norm(name);
   
     // MAIN
     if(n=="maintradinglogic" || n=="main" || n=="stratmain") return ST_MAIN;
   
     // TREND
     if(n=="trendvwappullback" || n=="trendvwap" || n=="trend_vwap" || n=="trendpullback" || n=="strattrendvwappullback")
       return ST_TREND_VWAP_PULLBACK;
   
     if(n=="trendboscontinuation" || n=="boscontinuation" || n=="bos" || n=="strattrendboscontinuation")
       return ST_TREND_BOS_CONT;
   
     // MR
     if(n=="mrvwapband" || n=="meanrevvwapband" || n=="vwapband" || n=="stratmrvwapband")
       return ST_MR_VWAP_BAND;
   
     if(n=="mrrangenr7ib" || n=="mrnr7ib" || n=="nr7ib" || n=="stratmrrangenr7ib")
       return ST_MR_RANGE_NR7IB;
   
     // BREAKOUT
     if(n=="breakoutsqueeze" || n=="squeeze" || n=="stratbreakoutsqueeze")
       return ST_BREAKOUT_SQUEEZE;
   
     if(n=="breakoutorb" || n=="orb" || n=="stratbreakoutorb")
       return ST_BREAKOUT_ORB;
   
     // REVERSAL
     if(n=="reversalsweepchoch" || n=="sweepchoch" || n=="choch" || n=="stratreversalsweepchoch")
       return ST_REV_SWEEP_CHOCH;
   
     if(n=="reversalvsaclimaxfade" || n=="vsaclimaxfade" || n=="vsa" || n=="stratreversalvsaclimaxfade")
       return ST_REV_VSA_CLIMAX_FADE;
   
     // CORR/PAIRS
     if(n=="corrdivergence" || n=="corrdiv" || n=="corr" || n=="stratcorrdivergence")
       return ST_CORR_DIVERGENCE;
   
     if(n=="pairsspreadlite" || n=="pairslite" || n=="pairs" || n=="pairsspread_lite" || n=="stratpairsspreadlite")
       return ST_PAIRS_SPREAD_LITE;
   
     // NEWS
     if(n=="newsdeviation" || n=="newsdev" || n=="stratnewsdeviation")
       return ST_NEWS_DEVIATION;
   
     if(n=="newspostfade" || n=="postfade" || n=="stratnewspostfade")
       return ST_NEWS_POSTFADE;
   
     // ICT
     if(n=="stratictpo3" || n=="ictpo3" || n=="po3")
       return ST_ICT_PO3;
   
     if(n=="stratictsilverbullet" || n=="ictsilverbullet" || n=="silverbullet")
       return ST_ICT_SILVERBULLET;
   
     if(n=="stratictwyckoffspringutad" || n=="ictwyckoffturn" || n=="wyckoffturn" || n=="springutad")
       return ST_ICT_WYCKOFF_TURN;
   
     return ST_NONE;
   }

   bool ConfigCore::IsStratEnabledByName(const Settings &cfg, string name)
   {
     const StratToggleId id = _StratIdByName(name);
   
     switch(id)
     {
       case ST_MAIN:                 return cfg.enable_strat_main;
   
       case ST_TREND_VWAP_PULLBACK:  return cfg.enable_trend_vwap_pullback;
       case ST_TREND_BOS_CONT:       return cfg.enable_trend_bos_continuation;
   
       case ST_MR_VWAP_BAND:         return cfg.enable_mr_vwap_band;
       case ST_MR_RANGE_NR7IB:       return cfg.enable_mr_range_nr7ib;
   
       case ST_BREAKOUT_SQUEEZE:     return cfg.enable_breakout_squeeze;
       case ST_BREAKOUT_ORB:         return cfg.enable_breakout_orb;
   
       case ST_REV_SWEEP_CHOCH:      return cfg.enable_reversal_sweep_choch;
       case ST_REV_VSA_CLIMAX_FADE:  return cfg.enable_reversal_vsa_climax_fade;
   
       case ST_CORR_DIVERGENCE:      return cfg.enable_corr_divergence;
       case ST_PAIRS_SPREAD_LITE:    return cfg.enable_pairs_spreadlite;
   
       case ST_NEWS_DEVIATION:       return cfg.enable_news_deviation;
       case ST_NEWS_POSTFADE:        return cfg.enable_news_postfade;
   
       case ST_ICT_PO3:              return cfg.enable_strat_ict_po3;
       case ST_ICT_SILVERBULLET:     return cfg.enable_strat_ict_silverbullet;
       case ST_ICT_WYCKOFF_TURN:     return cfg.enable_strat_ict_wyckoff_turn;
   
       case ST_NONE:
       default:
         break;
     }
   
      // safer default: unknown names are NOT enabled (fail-closed)
      return false;
   }
   
   bool ConfigCore::EnableStrategyByName(Settings &cfg, string name, const bool on)
   {
     const StratToggleId id = _StratIdByName(name);
   
     switch(id)
     {
       case ST_MAIN:                 cfg.enable_strat_main = on; return true;
   
       case ST_TREND_VWAP_PULLBACK:  cfg.enable_trend_vwap_pullback = on; return true;
       case ST_TREND_BOS_CONT:       cfg.enable_trend_bos_continuation = on; return true;
   
       case ST_MR_VWAP_BAND:         cfg.enable_mr_vwap_band = on; return true;
       case ST_MR_RANGE_NR7IB:       cfg.enable_mr_range_nr7ib = on; return true;
   
       case ST_BREAKOUT_SQUEEZE:     cfg.enable_breakout_squeeze = on; return true;
       case ST_BREAKOUT_ORB:         cfg.enable_breakout_orb = on; return true;
   
       case ST_REV_SWEEP_CHOCH:      cfg.enable_reversal_sweep_choch = on; return true;
       case ST_REV_VSA_CLIMAX_FADE:  cfg.enable_reversal_vsa_climax_fade = on; return true;
   
       case ST_CORR_DIVERGENCE:      cfg.enable_corr_divergence = on; return true;
       case ST_PAIRS_SPREAD_LITE:    cfg.enable_pairs_spreadlite = on; return true;
   
       case ST_NEWS_DEVIATION:       cfg.enable_news_deviation = on; return true;
       case ST_NEWS_POSTFADE:        cfg.enable_news_postfade = on; return true;
   
       case ST_ICT_PO3:              cfg.enable_strat_ict_po3 = on; return true;
       case ST_ICT_SILVERBULLET:     cfg.enable_strat_ict_silverbullet = on; return true;
       case ST_ICT_WYCKOFF_TURN:     cfg.enable_strat_ict_wyckoff_turn = on; return true;
   
       case ST_NONE:
       default:
         return false;
     }
   }

   // ===== Moved from Types.mqh: inline helpers that require full Settings =====
   #ifdef CFG_HAS_STRAT_MODE
      inline StrategyMode GetStrategyMode(const Settings &s){
        return CfgStrategyMode(s);
      }
      inline StrategyMode CfgStrategyMode(const Settings &s)
      {
        StrategyMode v = (StrategyMode)s.strat_mode;  // explicit cast from int
        switch(v)
        {
          case STRAT_MAIN_ONLY:
          case STRAT_PACK_ONLY:
          case STRAT_COMBINED:
            return v;
          default:
            // Optional debug: invalid mode fallback
            // (avoid noisy logs unless cfg.debug is commonly on)
            return STRAT_MAIN_ONLY;
        }
      }
   #endif
   
   inline bool CfgEnablePackStrats(const Settings &cfg)
   {
     #ifdef CFG_HAS_ENABLE_PACK_STRATS
       #ifdef CFG_HAS_DISABLE_PACKS
         if(cfg.disable_packs) return false;
       #endif
       return (bool)cfg.enable_pack_strats;
     #else
       return false;
     #endif
   }
   
   inline bool CfgDisablePacks(const Settings &cfg)
   {
     #ifdef CFG_HAS_DISABLE_PACKS
       return (bool)cfg.disable_packs;
     #else
       return false;
     #endif
   }

   #ifdef CFG_HAS_PROFILE_ENUM
      inline TradingProfile GetTradingProfile(const Settings &s){
        int p = s.profile;
        if(p < 0 || p > 4) p = (int)PROF_DEFAULT;
        return (TradingProfile)p;
      }
      inline void SetTradingProfile(Settings &s, const TradingProfile p){
        int v = (int)p; if(v < 0 || v > 4) v = (int)PROF_DEFAULT;
        s.profile = v;
      }
      #endif
      
      inline bool Cfg_EnableHardGate(const Settings &cfg){
     #ifdef CFG_HAS_ENABLE_HARD_GATE
       return (bool)cfg.enable_hard_gate;
     #else
       return false;
     #endif
   }
   
   inline int Cfg_MinFeaturesMet(const Settings &cfg){
     #ifdef CFG_HAS_MIN_FEATURES_MET
       return (cfg.min_features_met > 0 ? cfg.min_features_met : 0);
     #else
       return 0;
     #endif
   }
   
   inline double CfgRouterMinScore(const Settings &cfg){
     #ifdef CFG_HAS_ROUTER_MIN_SCORE
       return (cfg.router_min_score>0.0? cfg.router_min_score : 0.55);
     #else
       return 0.55;
     #endif
   }
   
   inline int CfgRouterMaxStrats(const Settings &cfg){
     #ifdef CFG_HAS_ROUTER_MAX_STRATS
       return (cfg.router_max_strats>0 ? cfg.router_max_strats : 12);
     #else
       return 12;
     #endif
   }
   
   inline int CfgRouterEvalAllMode(const Settings &cfg)
   {
     #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
       int v = cfg.router_eval_all_mode;
       if(v < 0) v = 0;
       if(v > 1) v = 1;
       return v;
     #else
       return 0;
     #endif
   }

   inline double CfgRouterFallbackMinScore(const Settings &cfg){
     #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
       double v = (cfg.router_fallback_min_score>0.0? cfg.router_fallback_min_score : 0.0);
     #else
       double v = 0.0;
     #endif
     #ifdef CFG_HAS_ROUTER_FB_MIN
       if(v<=0.0 && cfg.router_fb_min>0.0) v = cfg.router_fb_min;
     #endif
     return (v>0.0? v : 0.50);
   }
   
   inline int CfgRouterTopKLog(const Settings &cfg){
     #ifdef CFG_HAS_ROUTER_TOPK
       return (cfg.router_topk_log>0? (int)cfg.router_topk_log : 5);
     #else
       return 5;
     #endif
   }
   
   inline bool CfgRouterDebugLog(const Settings &cfg){
     #ifdef CFG_HAS_ROUTER_DEBUG
       return (bool)cfg.router_debug_log;
     #else
       return true;
     #endif
   }
   
   inline bool CfgRouterForceOneNormalVol(const Settings &cfg){
     #ifdef CFG_HAS_ROUTER_FORCE_ONE
       return (bool)cfg.router_force_one_normal_vol;
     #else
       return true;
     #endif
   }
   
   inline bool CfgRouterUseConflPool(const Settings &cfg)
   {
     #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
       return (bool)cfg.router_use_confl_pool;
     #else
       return false;
     #endif
   }
   
   inline double CfgRouterPoolBlendW(const Settings &cfg)
   {
     #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
       double w = cfg.router_pool_blend_w;
       if(w < 0.0) w = 0.0;
       if(w > 1.0) w = 1.0;
       return w;
     #else
       return 0.0;
     #endif
   }

   // Helper: treat pack strategies as "confluence-only contributors" in MAIN_ONLY
   // ONLY when the router confluence pool is explicitly enabled.
   inline bool CfgMainOnly_AllowPackConfluencePool(const Settings &cfg)
   {
     // Pool considered "in use" if either:
     //  - the pool toggle is ON, OR
     //  - the blend weight is > 0 (even if the toggle is forgotten)
     if(CfgRouterUseConflPool(cfg)) return true;
     if(CfgRouterPoolBlendW(cfg) > 0.0) return true;
     return false;
   }
    
   inline int NewsPreMins(const Settings &c)
   {
     #ifdef CFG_HAS_NEWS_PRE_MINS
       return (c.block_pre_m>0 ? c.block_pre_m : c.news_pre_mins);
     #else
       return c.block_pre_m;
     #endif
   }
   
   inline int NewsPostMins(const Settings &c)
   {
     #ifdef CFG_HAS_NEWS_POST_MINS
       return (c.block_post_m>0 ? c.block_post_m : c.news_post_mins);
     #else
       return c.block_post_m;
     #endif
   }
   // ===== End moved helpers =====
   
   // ----------------------------------------------------------------------------
   // Risk/Taper taps used by RiskEngine (compile-safe)
   // ----------------------------------------------------------------------------
   inline double CfgDayDDLimitPct(const Settings &cfg)
   {
     #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
       return (cfg.day_dd_limit_pct > 0.0 ? cfg.day_dd_limit_pct : 0.0);
     #else
       #ifdef CFG_HAS_MAX_DAILY_DD_PCT
         return (cfg.max_daily_dd_pct > 0.0 ? cfg.max_daily_dd_pct : 0.0);
       #else
         return 0.0;
       #endif
     #endif
   }
   
   inline double CfgDayProfitCapPct(const Settings &cfg)
   {
     #ifdef CFG_HAS_DAY_PROFIT_CAP_PCT
       // Default to 2.0% if unset/non-positive (prop-friendly taper onset)
       return (cfg.day_profit_cap_pct > 0.0 ? cfg.day_profit_cap_pct : 2.0);
     #else
       return 2.0;
     #endif
   }
   
   inline double CfgDayProfitStopPct(const Settings &cfg)
   {
     #ifdef CFG_HAS_DAY_PROFIT_STOP_PCT
       // Default to 3.0% if unset/non-positive; RiskEngine enforces stop >= cap
       return (cfg.day_profit_stop_pct > 0.0 ? cfg.day_profit_stop_pct : 3.0);
     #else
       return 3.0;
     #endif
   }
   
   inline double CfgMonthlyTargetPct(const Settings &cfg)
   {
   #ifdef CFG_HAS_MONTHLY_TARGET
     // Raw value in PERCENT units (1.0 = 1%, 10.0 = 10%)
     double raw = cfg.monthly_target_pct;
   
     // Default and clamp in percent-space
     if(raw <= 0.0) raw = CFG_MONTHLY_TARGET_PCT;   // e.g. 10.0
     if(raw < 0.0)  raw = 0.0;
     if(raw > 100.0) raw = 100.0;
   
     // Expose fraction (0.10) to Policies/RiskEngine
     return raw / 100.0;
   #else
     return 0.0;
   #endif
   }
  
   inline int CfgMonthlyTargetCycleMode(const Settings &cfg)
   {
   #ifdef CFG_HAS_MONTHLY_TARGET
     const int m = (int)cfg.monthly_target_cycle_mode;
     if(m == CFG_TARGET_CYCLE_CALENDAR || m == CFG_TARGET_CYCLE_ROLLING_28D)
       return m;
     return CFG_TARGET_CYCLE_DEFAULT;
   #else
     return CFG_TARGET_CYCLE_DEFAULT;
   #endif
   }
   
   inline int CfgMonthlyTargetBaseMode(const Settings &cfg)
   {
   #ifdef CFG_HAS_MONTHLY_TARGET
     const int m = (int)cfg.monthly_target_base_mode;
     if(m >= CFG_TARGET_BASE_CYCLE_START && m <= CFG_TARGET_BASE_INITIAL_COMPOUND)
       return m;
     return CFG_TARGET_BASE_DEFAULT;
   #else
     return CFG_TARGET_BASE_DEFAULT;
   #endif
   }

   inline double CfgTaperFloor(const Settings &cfg)
   {
     #ifdef CFG_HAS_TAPER_FLOOR
       // Clamp to [0..1], default 0.35 if unset/out-of-range
       double v = cfg.taper_floor;
       if(v <= 0.0)  v = 0.35;
       if(v >  1.0)  v = 1.0;
       return v;
     #else
       return 0.35;
     #endif
   }
   
   // (Policies-only taps if you haven’t added them yet; safe no-ops otherwise)
   inline double CfgMaxAccountDDPct(const Settings &cfg)
   {
     #ifdef CFG_HAS_MAX_ACCOUNT_DD_PCT
       return (cfg.max_account_dd_pct > 0.0 ? cfg.max_account_dd_pct : 0.0);
     #else
       return 0.0;
     #endif
   }
   
   inline double CfgChallengeInitEquity(const Settings &cfg)
   {
     #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
       // 0.0 => Policies should auto-capture at runtime
       return (cfg.challenge_init_equity > 0.0 ? cfg.challenge_init_equity : 0.0);
     #else
       return 0.0;
     #endif
   }
   
   // Global trade cooldown helper (used by Policies/RiskEngine)
   inline int CfgTradeCooldownSec(const Settings &cfg)
   {
     #ifdef CFG_HAS_TRADE_CD_SEC
       return (cfg.trade_cd_sec > 0 ? cfg.trade_cd_sec : 0);
     #else
       return 0;
     #endif
   }

     // -----------------------------------------------------------------------------
     // Helper: Map ICT_Context.directionalBias → ENUM_TRADE_DIRECTION
     //
     // ICTDirectionBias (LONG_ONLY / SHORT_ONLY / BOTH / NEUTRAL)
     // becomes DIR_BUY / DIR_SELL / DIR_BOTH (our internal selector).
     // -----------------------------------------------------------------------------
     inline ENUM_TRADE_DIRECTION ComputeDirectionFromICT(const ICT_Context &ctx)
     {
         // Prefer the finalized direction gate (single source of truth)
         // Only trust it when the context is marked valid; otherwise fall back to bias.
         if(ctx.valid)
         {
            if((int)ctx.allowedDirection >= 0 && (int)ctx.allowedDirection <= 2)
               return ctx.allowedDirection;
         }
          
         switch(ctx.directionalBias)
         {
            case ICT_LONG_ONLY:
               return TDIR_BUY;
            case ICT_SHORT_ONLY:
               return TDIR_SELL;
            case ICT_BOTH:
               return TDIR_BOTH;
            case ICT_NEUTRAL:
            default:
               return TDIR_BOTH;  // neutral => allow both, but strategies still
                                  // demand decent confluence before firing
         }
     }
     
     // Manual selector (TradeSelector) -> internal direction enum (TDIR_*)
    inline ENUM_TRADE_DIRECTION TradeSelectorToDirection(const TradeSelector sel)
    {
      if(sel == TRADE_BUY_ONLY)  return TDIR_BUY;
      if(sel == TRADE_SELL_ONLY) return TDIR_SELL;
      return TDIR_BOTH; // TRADE_BOTH_AUTO
    }

     // -----------------------------------------------------------------------------
     // Helper: EffectiveDirectionSelector
     //
     // - Manual mode  → respect cfg.trade_direction_selector.
     // - SmartMoney   → ignore manual selector, use ICT_Context bias.
     // -----------------------------------------------------------------------------
     inline ENUM_TRADE_DIRECTION EffectiveDirectionSelector(const Settings &cfg,
                                                             const ICT_Context &ctx)
     {
          // Manual hard override always wins (even in AUTO mode)
          const ENUM_TRADE_DIRECTION manualDir = TradeSelectorToDirection(cfg.trade_selector);
          if(manualDir == TDIR_BUY || manualDir == TDIR_SELL)
             return manualDir;

          // Manual selector mode: respect the user's choice (BOTH_AUTO)
          if((DirectionBiasMode)cfg.direction_bias_mode == DIRM_MANUAL_SELECTOR)
          {
              return manualDir; // will be TDIR_BOTH here
          }

          // Smart Money auto mode: use ICT context gate (now prefers ctx.allowedDirection)
          return ComputeDirectionFromICT(ctx);
     }
   
#ifdef CFG_HAS_STRAT_MODE
   // StrategyMode trade eligibility:
   // - STRAT_MAIN_ONLY allows ONLY MainTradingLogic + ICT/Wyckoff (see Types.mqh Strat_AllowedToTrade).
   // - STRAT_PACK_ONLY allows only non-core strategies.
   // - STRAT_COMBINED allows all.
   // IMPORTANT: Do not re-implement allow-lists elsewhere. Change policy ONLY in Types.mqh.
   inline bool IsStrategyAllowedInMode(const Settings &cfg, const StrategyID id)
   {
      // Always reject missing/invalid strategy IDs (prevents ghost paths)
      if(((int)id) <= 0)
         return false;

      const StrategyMode mode = CfgStrategyMode(cfg);
      
      if(cfg.debug)
         PrintFormat("[Config] IsStrategyAllowedInMode: mode=%d sid=%d",
                     (int)mode, (int)id);
      return Strat_AllowedToTrade(mode, id);
   }

   #ifndef CFG_HAS_IS_STRATEGY_ALLOWED_IN_MODE
      #define CFG_HAS_IS_STRATEGY_ALLOWED_IN_MODE 1
   #endif
#else
   inline bool IsStrategyAllowedInMode(const Settings &cfg, const StrategyID sid)
   {
      // Keep behavior consistent even if CFG_HAS_STRAT_MODE is not defined:
      // This wrapper must always delegate to the single source of truth.
      if(((int)sid) <= 0)
         return false;
   
      const StrategyMode mode = (StrategyMode)cfg.strat_mode;
      return Strat_AllowedToTrade(mode, sid);
   }
   
   #ifndef CFG_HAS_IS_STRATEGY_ALLOWED_IN_MODE
      #define CFG_HAS_IS_STRATEGY_ALLOWED_IN_MODE 1
   #endif
#endif

   // ProfileSpec includes router hints + weights/throttles for known archetypes
   struct ProfileSpec
   {
     // Router hints
     double min_score; // e.g. 0.55
     int    max_strats;// e.g. 12
     // Router fallback hints (used by _SyncRouterFallbackAlias via router_profile_alias)
     double fallback_min_confluence; // 0..1, 0 = don't override
     int    fallback_max_span;       // bars, 0 = don't override

     // Weights
     double w_trend;           // Strat_Trend_VWAPPullback
     double w_trend_bos;       // Strat_Trend_BOSContinuation
     double w_mr;              // Strat_MR_VWAPBand
     double w_mr_range;        // Strat_MR_RangeNR7IB
     double w_squeeze;         // Strat_Breakout_Squeeze
     double w_orb;             // Strat_Breakout_ORB
     double w_sweepchoch;      // Strat_Reversal_SweepCHOCH
     double w_vsa;             // Strat_Reversal_VSAClimaxFade
     double w_corrdiv;         // Strat_Corr_Divergence
     double w_pairslite;       // Strat_Pairs_SpreadLite
     double w_news_dev;        // Strat_News_Deviation
     double w_news_post;       // Strat_News_PostFade
     
     // ICT Weights
     double w_ict_po3;          // Strat_ICT_PO3
     double w_ict_silverbullet; // Strat_ICT_SilverBullet
     double w_ict_wyckoff_turn; // Strat_ICT_Wyckoff_Turn

     // Throttles (seconds)
     int th_trend;
     int th_trend_bos;
     int th_mr;
     int th_mr_range;
     int th_squeeze;
     int th_orb;
     int th_sweepchoch;
     int th_vsa;
     int th_corrdiv;
     int th_pairslite;
     int th_news_dev;
     int th_news_post;
     
     // ICT Throttles (seconds)
     int th_ict_po3;
     int th_ict_silverbullet;
     int th_ict_wyckoff_turn;
   };
  
   // Keep router fallback numeric knobs, legacy aliases, and
   // profile-based router hints in sync.
   inline void _SyncRouterFallbackAlias(Settings &io)
     {
      // --------------------------------------------------------
      // 1) Normalise fallback threshold + legacy aliases
      // --------------------------------------------------------
      double primary = 0.0;
   
      // 1.1 Prefer explicit fallback knob when compiled in
      #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
         if(io.router_fallback_min_score > 0.0)
            primary = io.router_fallback_min_score;
      #endif
   
      // 1.2 Legacy alias support (if present)
      #ifdef CFG_HAS_ROUTER_FB_MIN
         if(primary <= 0.0 && io.router_fb_min > 0.0)
            primary = io.router_fb_min;
      #endif
   
      // 1.3 Derive from router_min_score with a small grace if still unset
      #ifdef CFG_HAS_ROUTER_MIN_SCORE
         if(primary <= 0.0 && io.router_min_score > 0.0)
            primary = MathMax(0.0, io.router_min_score - 0.05);
      #endif
   
      // 1.4 Final defaults & clamp
      if(primary <= 0.0)
         primary = 0.50;            // floor for router fallback
      if(primary > 1.0)
         primary = 1.0;
   
      // 1.5 Reflect back into both aliases where available
      #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
         io.router_fallback_min_score = primary;
      #endif
      #ifdef CFG_HAS_ROUTER_FB_MIN
         io.router_fb_min = primary;
      #endif
   
      // 1.6 If only the legacy alias exists, make sure it receives the derived value
      #ifndef CFG_HAS_ROUTER_FALLBACK_MIN
        #ifdef CFG_HAS_ROUTER_FB_MIN
          if(io.router_fb_min <= 0.0)
             io.router_fb_min = primary;
        #endif
      #endif
   
      // --------------------------------------------------------
      // 2) Sync profile alias → router hints (confluence/span)
      // --------------------------------------------------------
      #ifdef CFG_HAS_ROUTER_HINTS
         if(io.router_profile_alias != "")
           {
            ProfileSpec p;
            ProfileSpecDefaults(p);     // or BuildProfileSpec(PROF_DEFAULT, p);
            if(GetProfile(io.router_profile_alias, p))
              {
               // Defensive clamp on profile-provided router hints
               p.min_score = MathMin(1.0, MathMax(0.0, p.min_score));
               if(p.max_strats < 0) p.max_strats = 0;
               
               // Clamp confluence into [0,1] just in case
               io.router_fallback_min_confluence =
                  MathMin(1.0, MathMax(0.0, p.fallback_min_confluence));
   
               // Only override span when profile provides a positive value
               if(p.fallback_max_span > 0)
                  io.router_fallback_max_span = p.fallback_max_span;
              }
              
            // Apply router primary hints from the profile alias ONLY when unset
            #ifdef CFG_HAS_ROUTER_MIN_SCORE
              if(io.router_min_score <= 0.0)
                io.router_min_score = MathMin(1.0, MathMax(0.0, p.min_score));
            #endif
            #ifdef CFG_HAS_ROUTER_MAX_STRATS
              if(io.router_max_strats <= 0)
                io.router_max_strats = (p.max_strats > 0 ? p.max_strats : io.router_max_strats);
            #endif
           }
      #endif
     }

   // Map extras → Settings (compile-safe)
   inline void ApplyExtras(Settings &cfg, const BuildExtras &x)
   {
     // Pack strategy registration (StrategyRegistry consumes these)
     #ifdef CFG_HAS_ENABLE_PACK_STRATS
       cfg.enable_pack_strats = x.enable_pack_strats;
     #endif
     #ifdef CFG_HAS_DISABLE_PACKS
       cfg.disable_packs = x.disable_packs;
     #endif
     // Confluence / evaluator
     #ifdef CFG_HAS_CF_MIN_NEEDED
       cfg.cf_min_needed = MathMax(0, x.conf_min_count);
     #endif
     #ifdef CFG_HAS_CF_MIN_SCORE
       cfg.cf_min_score  = MathMax(0.0, x.conf_min_score);
     #endif
     #ifdef CFG_HAS_MAIN_SEQGATE
       cfg.main_sequential_gate = x.main_sequential_gate;
     #endif
     #ifdef CFG_HAS_MAIN_REQUIRE_CHECKLIST
       cfg.main_require_checklist = x.main_require_checklist;
     #endif
     #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
       cfg.main_confirm_any_of_3 = x.main_confirm_any_of_3;
     #endif
     #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
       cfg.main_require_classical = x.main_require_classical;
     #endif
     #ifdef CFG_HAS_ORDERFLOW_TH
       cfg.orderflow_th = x.orderflow_th;
     #endif
     #ifdef CFG_HAS_VSA_ALLOW_TICK_VOLUME
       cfg.vsa_allow_tick_volume = x.vsa_allow_tick_volume;
     #endif
     #ifdef CFG_HAS_TF_TREND_HTF
       cfg.tf_trend_htf = x.tf_trend_htf;
     #endif
   
     #ifdef CFG_HAS_ML_SETTINGS
        cfg.ml_enable          = x.ml_enable;
        cfg.ml_weight          = MathMin(1.0, MathMax(0.0, x.ml_weight));
        cfg.ml_temperature     = MathMax(0.01, x.ml_temperature);
        cfg.ml_conformal_alpha = MathMin(0.50, MathMax(0.0, x.ml_conformal_alpha));
        cfg.ml_dampen          = MathMin(1.0,  MathMax(0.0, x.ml_dampen));
      
        #ifdef CFG_HAS_ML_SLTP_MULT
         cfg.ml_sltp_enable = x.ml_sltp_enable;
         cfg.ml_sltp_sl_min = x.ml_sltp_sl_min;
         cfg.ml_sltp_sl_max = x.ml_sltp_sl_max;
         cfg.ml_sltp_tp_min = x.ml_sltp_tp_min;
         cfg.ml_sltp_tp_max = x.ml_sltp_tp_max;
        #endif

        cfg.ml_auto_calibrate     = x.ml_auto_calibrate;
        cfg.ml_model_max_age_hours= MathMax(0, x.ml_model_max_age_hours);
        cfg.ml_min_oos_auc        = MathMin(1.0, MathMax(0.0, x.ml_min_oos_auc));
        cfg.ml_min_oos_acc        = MathMin(1.0, MathMax(0.0, x.ml_min_oos_acc));
        cfg.ml_min_samples_train  = MathMax(0, x.ml_min_samples_train);
        cfg.ml_min_samples_test   = MathMax(0, x.ml_min_samples_test);
      
        cfg.ml_label_horizon_bars = MathMax(1, x.ml_label_horizon_bars);
        cfg.ml_label_atr_mult     = MathMax(0.0, x.ml_label_atr_mult);
      
        cfg.ml_use_common_files   = x.ml_use_common_files;
        cfg.ml_model_file         = x.ml_model_file;
        cfg.ml_dataset_file       = x.ml_dataset_file;
      
        cfg.ml_external_enable      = x.ml_external_enable;
        cfg.ml_external_mode        = MathMax(0, x.ml_external_mode);
        cfg.ml_external_file        = x.ml_external_file;
        cfg.ml_external_poll_ms     = MathMax(250, x.ml_external_poll_ms);
        cfg.ml_external_socket_host = x.ml_external_socket_host;
        cfg.ml_external_socket_port = MathMax(0, x.ml_external_socket_port);
     #endif

     // Volume footprint
     #ifdef CFG_HAS_EXTRA_VOLUME_FP
       cfg.extra_volume_footprint = x.extra_volume_footprint;
     #endif
     #ifdef CFG_HAS_W_VOLUME_FP
       cfg.w_volume_footprint = x.w_volume_footprint;
     #endif
   
     // DOM imbalance
     #ifdef CFG_HAS_EXTRA_DOM_IMBALANCE
       cfg.extra_dom_imbalance = x.extra_dom_imbalance;
     #endif
     #ifdef CFG_HAS_DOM_ZONE_PAD_POINTS
       cfg.dom_zone_pad_points = MathMax(0, x.dom_zone_pad_points);
     #endif
     #ifdef CFG_HAS_DOM_MIN_ABS_IMB
       cfg.dom_min_abs_imb = x.dom_min_abs_imb;
     #endif
     #ifdef CFG_HAS_DEBUG_DOM
       cfg.debug_dom = x.debug_dom;
     #endif
     #ifdef CFG_HAS_W_DOM_IMBALANCE
       cfg.w_dom_imbalance = x.w_dom_imbalance;
     #endif

     #ifdef CFG_HAS_EXTRA_TRENDLINES
       cfg.extra_trendlines = x.extra_trendlines;
     #endif
     #ifdef CFG_HAS_W_TRENDLINES
       cfg.w_trendlines = x.w_trendlines;
     #endif

    // StochRSI
    #ifdef CFG_HAS_EXTRA_STOCHRSI
      cfg.extra_stochrsi = x.extra_stochrsi;
    #endif

    // Prefer dedicated StochRSI RSI-period if available,
    // otherwise fall back to generic RSI period.
    #ifdef CFG_HAS_STOCHRSI_RSI_PERIOD
      cfg.stochrsi_rsi_period = MathMax(1, x.stochrsi_rsi_period);
    #else
      #ifdef CFG_HAS_RSI_PERIOD
        cfg.rsi_period = MathMax(1, x.stochrsi_rsi_period);
      #endif
    #endif

    #ifdef CFG_HAS_STOCHRSI_K_PERIOD
      cfg.stochrsi_k_period = MathMax(1, x.stochrsi_k_period);
    #endif
    #ifdef CFG_HAS_STOCHRSI_K_SMOOTH
      cfg.stochrsi_k_smooth = x.stochrsi_k_smooth;
      if(cfg.stochrsi_k_smooth<=0) cfg.stochrsi_k_smooth = 3;
      if(cfg.stochrsi_k_smooth>200) cfg.stochrsi_k_smooth = 200;
    #endif
    #ifdef CFG_HAS_STOCHRSI_D_SMOOTH
      cfg.stochrsi_d_smooth = x.stochrsi_d_smooth;
      if(cfg.stochrsi_d_smooth<=0) cfg.stochrsi_d_smooth = 3;
      if(cfg.stochrsi_d_smooth>200) cfg.stochrsi_d_smooth = 200;
    #endif
    #ifdef CFG_HAS_STOCHRSI_OB
      cfg.stochrsi_ob = x.stochrsi_ob;
    #endif
    #ifdef CFG_HAS_STOCHRSI_OS
      cfg.stochrsi_os = x.stochrsi_os;
    #endif
    #ifdef CFG_HAS_W_STOCHRSI
      cfg.w_stochrsi = x.w_stochrsi;
    #endif
   
     // MACD
     #ifdef CFG_HAS_EXTRA_MACD
       cfg.extra_macd = x.extra_macd;
     #endif
     #ifdef CFG_HAS_MACD_FAST
       cfg.macd_fast = MathMax(1, x.macd_fast);
     #endif
     #ifdef CFG_HAS_MACD_SLOW
       cfg.macd_slow = MathMax(1, x.macd_slow);
     #endif
     #ifdef CFG_HAS_MACD_SIGNAL
       cfg.macd_signal = MathMax(1, x.macd_signal);
     #endif
     #ifdef CFG_HAS_MACD_PRICE
       const int ap = (int)x.macd_price;
       cfg.macd_price = (ENUM_APPLIED_PRICE)MathMax(0, MathMin(6, ap));
     #endif
     #ifdef CFG_HAS_W_MACD
       cfg.w_macd = x.w_macd;
     #endif
   
     // ADX regime
     #ifdef CFG_HAS_EXTRA_ADX_REGIME
       cfg.extra_adx_regime = x.extra_adx_regime;
     #endif
     #ifdef CFG_HAS_ADX_PERIOD
       cfg.adx_period = MathMax(1, x.adx_period);
     #endif
     #ifdef CFG_HAS_ADX_MIN
       cfg.adx_min_trend = MathMax(0.0, x.adx_min);
     #endif
     #ifdef CFG_HAS_W_ADX_REGIME
       cfg.w_adx_regime = x.w_adx_regime;
     #endif
   
     // Correlation weighting
     #ifdef CFG_HAS_EXTRA_CORR
        cfg.extra_correlation = x.extra_corr;
     #endif
     #ifdef CFG_HAS_CORR_REF_SYMBOL
        cfg.corr_ref_symbol = x.corr_ref_symbol;
     #endif
     #ifdef CFG_HAS_CORR_LOOKBACK
        cfg.corr_lookback = MathMax(1, x.corr_lookback);
     #endif
     #ifdef CFG_HAS_CORR_MIN_ABS
        cfg.corr_min_abs = MathMax(0.0, x.corr_min_abs);
     #endif
     #ifdef CFG_HAS_W_CORR
        cfg.w_correlation = x.w_corr;
     #endif
   
     // News weighting
     #ifdef CFG_HAS_EXTRA_NEWS
       cfg.extra_news = x.extra_news;
     #endif
     #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
        cfg.main_news_hard_veto = x.main_news_hard_veto;
     #endif
     #ifdef CFG_HAS_W_NEWS
       cfg.w_news = x.w_news;
     #endif
     
     #ifdef CFG_HAS_NEWS_BACKEND
         cfg.news_backend_mode       = x.news_backend_mode;
         cfg.news_mvp_no_block       = x.news_mvp_no_block;
         cfg.news_failover_to_csv    = x.news_failover_to_csv;
         cfg.news_neutral_on_no_data = x.news_neutral_on_no_data;
         cfg.news_allow_cached       = x.news_allow_cached;
     #endif
     
     // Silver Bullet TZ
     #ifdef CFG_HAS_EXTRA_SILVERBULLET_TZ
       cfg.extra_silverbullet_tz = x.extra_silverbullet_tz;
     #endif
     #ifdef CFG_HAS_W_SILVERBULLET_TZ
       cfg.w_silverbullet_tz = x.w_silverbullet_tz;
     #endif
   
     // AMD HTF
     #ifdef CFG_HAS_EXTRA_AMD_HTF
       cfg.extra_amd_htf = x.extra_amd_htf;
     #endif
     #ifdef CFG_HAS_W_AMD_H1
       cfg.w_amd_h1 = x.w_amd_h1;
     #endif
     #ifdef CFG_HAS_W_AMD_H4
       cfg.w_amd_h4 = x.w_amd_h4;
     #endif
     
     // PO3 HTF
     #ifdef CFG_HAS_EXTRA_PO3_HTF
       cfg.extra_po3_htf = x.extra_po3_htf;
     #endif
     #ifdef CFG_HAS_W_PO3_H1
       cfg.w_po3_h1 = x.w_po3_h1;
     #endif
     #ifdef CFG_HAS_W_PO3_H4
       cfg.w_po3_h4 = x.w_po3_h4;
     #endif

     // Wyckoff turn
     #ifdef CFG_HAS_EXTRA_WYCKOFF_TURN
       cfg.extra_wyckoff_turn = x.extra_wyckoff_turn;
     #endif
     #ifdef CFG_HAS_W_WYCKOFF_TURN
       cfg.w_wyckoff_turn = x.w_wyckoff_turn;
     #endif

     #ifdef CFG_HAS_EXTRA_PHASE_CTX
       cfg.extra_phase_ctx = x.extra_phase_ctx;
     #endif
     #ifdef CFG_HAS_W_PHASE_CTX
       cfg.w_phase_ctx = x.w_phase_ctx;
     #endif

     // Multi-TF zones
     #ifdef CFG_HAS_EXTRA_MTF_ZONES
       cfg.extra_mtf_zones = x.extra_mtf_zones;
     #endif
     #ifdef CFG_HAS_W_MTF_ZONE_H1
       cfg.w_mtf_zone_h1 = x.w_mtf_zone_h1;
     #endif
     #ifdef CFG_HAS_W_MTF_ZONE_H4
       cfg.w_mtf_zone_h4 = x.w_mtf_zone_h4;
     #endif
     #ifdef CFG_HAS_MTF_ZONE_MAX_DIST_ATR
       cfg.mtf_zone_max_dist_atr = x.mtf_zone_max_dist_atr;
     #endif
   
     // Router + gates + requirements
     #ifdef CFG_HAS_ENABLE_HARD_GATE
       cfg.enable_hard_gate = x.enable_hard_gate;
     #endif
     #ifdef CFG_HAS_ROUTER_MIN_SCORE
       cfg.router_min_score = x.router_min_score;
     #endif
     // Some codebases name it differently — set both if present
     #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
       cfg.router_fallback_min_score = x.router_fb_min;
     #endif
     #ifdef CFG_HAS_ROUTER_FB_MIN
       cfg.router_fb_min = x.router_fb_min;
     #endif
     #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
       cfg.router_use_confl_pool = x.router_use_confl_pool;
     #endif
     #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
       cfg.router_pool_blend_w = MathMin(1.0, MathMax(0.0, x.router_pool_blend_w));
     #endif
     #ifdef CFG_HAS_MIN_FEATURES_MET
       cfg.min_features_met = MathMax(0, x.min_features_met);
     #endif
     #ifdef CFG_HAS_REQUIRE_TREND_FILTER
       cfg.require_trend_filter = x.require_trend;
     #endif
     #ifdef CFG_HAS_REQUIRE_ADX_REGIME
       cfg.require_adx_regime = x.require_adx;
     #endif
     #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
       cfg.require_struct_or_pattern_ob = x.require_struct_or_pattern_ob;
     #endif
     
     // Silver Bullet hard requirements (optional)
     #ifdef CFG_HAS_SB_REQUIRE_OTE
       cfg.sb_require_ote = x.require_sb_ote;
     #endif
     #ifdef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
       cfg.sb_require_vwap_stretch = x.require_sb_vwap_stretch;
     #endif
   
     // London window / liquidity policy
     #ifdef CFG_HAS_LONDON_LIQ_POLICY
       cfg.london_liquidity_policy = x.london_liq_policy;
     #endif
     #ifdef CFG_HAS_LONDON_LOCAL_MINUTES
       int open_m=-1, close_m=-1;
       _parse_hhmm(x.london_start_local, open_m);
       _parse_hhmm(x.london_end_local,   close_m);
       if(open_m >=0)  cfg.london_local_open_min  = open_m;
       if(close_m>=0)  cfg.london_local_close_min = close_m;
     #endif
     
     #ifdef CFG_HAS_LIQPOOL_FIELDS
        // Liquidity Pools (Lux-style)
        if(x.liqPoolMinTouches      > 0)   cfg.liqPoolMinTouches      = x.liqPoolMinTouches;
        if(x.liqPoolGapBars         > 0)   cfg.liqPoolGapBars         = x.liqPoolGapBars;
        if(x.liqPoolConfirmWaitBars > 0)   cfg.liqPoolConfirmWaitBars = x.liqPoolConfirmWaitBars;
        if(x.liqPoolLevelEpsATR     > 0.0) cfg.liqPoolLevelEpsATR     = x.liqPoolLevelEpsATR;
        if(x.liqPoolMaxLookbackBars > 0)   cfg.liqPoolMaxLookbackBars = x.liqPoolMaxLookbackBars;
        if(x.liqPoolMinSweepATR     > 0.0) cfg.liqPoolMinSweepATR     = x.liqPoolMinSweepATR;
     #endif
   
     // ATR-as-delta proxy + vol regime floor
     #ifdef CFG_HAS_USE_ATR_AS_DELTA
       cfg.use_atr_as_delta_proxy = x.use_atr_as_delta;
     #endif
     #ifdef CFG_HAS_ATR_FOR_DELTA_PERIOD
       cfg.atr_for_delta_period = MathMax(1, x.atr_period_2);
     #endif
     #ifdef CFG_HAS_ATR_VOLREGIME_FLOOR
       cfg.atr_volregime_floor = MathMax(0.0, x.atr_vol_regime_floor);
     #endif
   
     // Structure / OB
     #ifdef CFG_HAS_ZZ_DEPTH
       cfg.struct_zz_depth = MathMax(1, x.struct_zz_depth);
     #endif
     #ifdef CFG_HAS_STRUCT_HTF_MULT
       cfg.struct_htf_mult = MathMax(1, x.struct_htf_mult);
     #endif
     #ifdef CFG_HAS_OB_PROX_MAX_PIPS
       cfg.ob_prox_max_pips = MathMax(0.0, x.ob_prox_max_pips);
     #endif
     #ifdef CFG_HAS_STRUCT_ZONE_MARGIN_PIPS
       cfg.struct_zone_margin_pips = MathMax(0.0, x.struct_zone_margin_pips);
     #endif
     #ifdef CFG_HAS_STRUCT_MIN_TOUCH_COUNT
       cfg.struct_min_touch_count = MathMax(0, x.struct_min_touch_count);
     #endif
     #ifdef CFG_HAS_STRUCT_ZONE_MIN_SCORE
       cfg.struct_zone_min_score = MathMax(0.0, x.struct_zone_min_score);
     #endif
   
     // ATR stops/targets + risk-per-trade
     #ifdef CFG_HAS_USE_ATR_STOPS
       cfg.use_atr_stops_targets = x.use_atr_stops_targets;
     #endif
     #ifdef CFG_HAS_ATR_SL_MULT_2
       cfg.atr_sl_mult_2 = MathMax(0.0, x.atr_sl_mult2);
     #endif
     #ifdef CFG_HAS_ATR_TP_MULT_2
       cfg.atr_tp_mult_2 = MathMax(0.0, x.atr_tp_mult2);
     #endif
     #ifdef CFG_HAS_RISK_PER_TRADE_PCT
       cfg.risk_per_trade_pct = MathMax(0.0, x.risk_per_trade_pct);
     #endif
   
     // Diagnostics
     #ifdef CFG_HAS_LOG_VETO_DETAILS
       cfg.log_veto_details = x.log_veto_details;
     #endif
     #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
       cfg.weekly_open_spread_ramp = x.weekly_open_spread_ramp;
     #endif
     _SyncRouterFallbackAlias(cfg);
   }
   
   // Sensible defaults for extras (neutral behaviour)
   inline void BuildExtrasDefaults(BuildExtras &x)
   {
     ZeroMemory(x);                        // bools=false, numbers=0
     // Re-seat string fields (avoid “zeroed string handle” weirdness)
     x.corr_ref_symbol   = "";
     x.london_start_local= "";
     x.london_end_local  = "";
     x.require_sb_ote = false;
     x.require_sb_vwap_stretch = false;
     x.main_require_checklist = true;
     x.main_confirm_any_of_3  = true;
     
     #ifdef CFG_HAS_ML_SETTINGS
        x.ml_model_file = "";
        x.ml_dataset_file = "";
        x.ml_external_file = "";
        x.ml_external_socket_host = "";
     #endif

     // Pack strategies off by default (confluence-only unless explicitly enabled)
     x.enable_pack_strats = false;
     x.disable_packs      = false;

     // Enforce the 1→8 checklist by default (your requirement)
     x.main_sequential_gate   = true;

     // Baseline quality gates (prevents “anything passes”)
     x.conf_min_count         = 5;
     x.conf_min_score         = 0.55;
    
     #ifdef CFG_HAS_ML_SETTINGS
        x.ml_enable           = false;  // default OFF: preserves current behaviour
        x.ml_weight           = 0.0;    // neutral
        x.ml_temperature      = 1.0;
        x.ml_conformal_alpha  = 0.0;
        x.ml_dampen           = 0.0;
      
        #ifdef CFG_HAS_ML_SLTP_MULT
            x.ml_sltp_enable = false;   // default OFF: preserves current behaviour
            x.ml_sltp_sl_min = 0.85;
            x.ml_sltp_sl_max = 1.20;
            x.ml_sltp_tp_min = 0.90;
            x.ml_sltp_tp_max = 1.60;
        #endif

        x.ml_auto_calibrate     = false;
        x.ml_model_max_age_hours= 168;  // 7d
        x.ml_min_oos_auc        = 0.55;
        x.ml_min_oos_acc        = 0.52;
        x.ml_min_samples_train  = 200;
        x.ml_min_samples_test   = 100;
      
        x.ml_label_horizon_bars = 10;
        x.ml_label_atr_mult     = 0.50;
      
        x.ml_use_common_files   = true;
        x.ml_model_file         = "CAEA_MLModel.ini";
        x.ml_dataset_file       = "CAEA_MLDataset.csv";
      
        x.ml_external_enable      = false;
        x.ml_external_mode        = 1;
        x.ml_external_file        = "CAEA_MLExternal.csv";
        x.ml_external_poll_ms     = 5000;
        x.ml_external_socket_host = "127.0.0.1";
        x.ml_external_socket_port = 5050;
     #endif

     #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
       x.main_require_classical = false; // default OFF (more trades; avoids “over-filtering”)
     #endif
     x.orderflow_th           = 0.60;          // FX-friendly default threshold
     x.vsa_allow_tick_volume  = true;          // default true (FX tick volume is what you actually have)
     x.tf_trend_htf           = PERIOD_CURRENT; // means “use cfg.tf_h4”
     
     // Baseline weights for extras (features OFF by default; weights ready when enabled)
     x.w_volume_footprint = 0.05;

     x.extra_dom_imbalance = false;
     x.dom_zone_pad_points = 15;
     x.dom_min_abs_imb     = 0.15;
     x.debug_dom           = false;
     x.w_dom_imbalance     = 0.05;

     x.extra_trendlines   = false;
     x.w_trendlines       = 0.05;
  
     x.w_stochrsi   = 0.04;
     x.w_macd       = 0.04;
     x.w_adx_regime = 0.04;

     x.corr_min_abs = 0.25;
     x.w_corr       = 0.04;

     x.w_news       = 0.04;

     #ifdef CFG_HAS_NEWS_BACKEND
         // Defaults: safe + configurable. You can tighten later from EA inputs.
         x.news_backend_mode       = 1;     // broker calendar by default
         x.news_mvp_no_block       = false;  // don't accidentally sterilize trading out-of-the-box
         x.news_failover_to_csv    = true;  // allow fallback if broker calendar is missing
         x.news_neutral_on_no_data = true;  // missing data => do not block
         x.news_allow_cached = true;
     #endif
     
     x.extra_news = true;
     x.w_news     = 0.50;

     #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
         x.main_news_hard_veto = true;
     #endif
      
     x.stochrsi_rsi_period=14; x.stochrsi_k_period=14; x.stochrsi_k_smooth=3; x.stochrsi_d_smooth=3; x.stochrsi_ob=0.8; x.stochrsi_os=0.2;
     x.macd_fast=12; x.macd_slow=26; x.macd_signal=9;
     #ifdef CFG_HAS_MACD_PRICE
       x.macd_price = PRICE_CLOSE;
     #endif
    
     x.adx_period=14; x.adx_min=20.0;
     x.corr_lookback=200;
     
     // Defaults for new extras weights (features are OFF by default, but weights are ready)
     x.w_silverbullet_tz = 0.06;
     x.w_amd_h1          = 0.06;
     x.w_amd_h4          = 0.08;
     
     x.extra_phase_ctx = false;
     x.w_phase_ctx     = 0.05;

     x.w_po3_h1          = 0.05;
     x.w_po3_h4          = 0.07;
     x.w_wyckoff_turn    = 0.05;
     x.w_mtf_zone_h1     = 0.05;
     x.w_mtf_zone_h4     = 0.07;
     x.mtf_zone_max_dist_atr = 1.25;
   
     x.router_min_score=0.55; x.router_fb_min=0.50;
   
     #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
       x.router_use_confl_pool = false;   // default OFF (no behavior change)
     #endif
     #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
       x.router_pool_blend_w   = 0.0;     // default 0 (no influence)
     #endif

     x.london_start_local="08:00";
     x.london_end_local  ="17:00";
   
     x.atr_period_2=14;
   
     x.struct_zz_depth=12; x.struct_htf_mult=3;
   
     x.ob_prox_max_pips = 15.0;

     #ifdef CFG_HAS_STRUCT_ZONE_MARGIN_PIPS
       x.struct_zone_margin_pips = 0.0;
     #endif
     #ifdef CFG_HAS_STRUCT_MIN_TOUCH_COUNT
       x.struct_min_touch_count = 0;
     #endif
     #ifdef CFG_HAS_STRUCT_ZONE_MIN_SCORE
       x.struct_zone_min_score = 0.0;
     #endif

     x.weekly_open_spread_ramp=true;
   }

  //──────────────────────────────────────────────────────────────────
  // Normalization & post-wiring
  //──────────────────────────────────────────────────────────────────
  inline int ClampMinute(const int m){ if(m<0) return 0; if(m>=1440) return 1439; return m; }

  // Map feature “enable” flags → explicit veto knobs (keeps older UIs compatible)
  inline void Postwire_StrategyVetoDefaults(Settings &cfg)
  {
    #ifdef CFG_HAS_STRUCT_VETO
      if(!cfg.struct_veto_on) cfg.struct_veto_on = cfg.structure_enable;
    #endif
    #ifdef CFG_HAS_LIQUIDITY_VETO
      if(!cfg.liquidity_veto_on) cfg.liquidity_veto_on = cfg.liquidity_enable;
    #endif
    #ifdef CFG_HAS_LIQUIDITY_LIMIT
      if(cfg.liquidity_spr_atr_max<=0.0) cfg.liquidity_spr_atr_max = 0.45;
    #endif
    #ifdef CFG_HAS_CORR_VETO
      if(!cfg.corr_veto_on) cfg.corr_veto_on = cfg.corr_softveto_enable;
    #endif
    #ifdef CFG_HAS_REGIME_TQMIN
      if(cfg.regime_tq_min<=0.0) cfg.regime_tq_min = 0.10;
    #endif
    #ifdef CFG_HAS_REGIME_SGMIN
      if(cfg.regime_sg_min<=0.0) cfg.regime_sg_min = 0.10;
    #endif
  }
  
  // Apply strat_mode => enable_* toggles (no Normalize() call in here!)
  inline void EnforceStrategyModeToggles(Settings &cfg)
  {
    #ifdef CFG_HAS_STRAT_MODE
      #ifdef CFG_HAS_STRAT_TOGGLES
          const StrategyMode sm = CfgStrategyMode(cfg);
      
           if(sm == STRAT_MAIN_ONLY)
           {
             // MAIN_ONLY default posture: disable pack strategies.
             // Exception: if the router confluence-only pool is explicitly enabled,
             // keep pack toggles as-is so they can contribute confluence-only signals.
             const bool allow_pack_confl = CfgMainOnly_AllowPackConfluencePool(cfg);
             if(!allow_pack_confl)
             {
               // Disable PACK strategies (leave main + sub-ICT on)
               cfg.enable_trend_vwap_pullback      = false;
               cfg.enable_trend_bos_continuation   = false;
               cfg.enable_mr_vwap_band             = false;
               cfg.enable_mr_range_nr7ib           = false;
               cfg.enable_breakout_squeeze         = false;
               cfg.enable_breakout_orb             = false;
               cfg.enable_reversal_sweep_choch     = false;
               cfg.enable_reversal_vsa_climax_fade = false;
               cfg.enable_corr_divergence          = false;
               cfg.enable_pairs_spreadlite         = false;
               cfg.enable_news_deviation           = false;
               cfg.enable_news_postfade            = false;
             }
             // else: leave pack toggles unchanged (confluence-only pool mode)
           }
          else if(sm == STRAT_PACK_ONLY)
          {
            // Disable MAIN strategy + its sub toggles
            cfg.enable_strat_main             = false;
            cfg.enable_strat_ict_po3          = false;
            cfg.enable_strat_ict_silverbullet = false;
            cfg.enable_strat_ict_wyckoff_turn = false;
            cfg.enable_strat_ict_continuation  = false;
          }
          else
          {
            // STRAT_COMBINED: leave as-is (defaults already enable everything)
          }
      #endif 
    #endif
  }

  inline void NormalizeStrategyToggles(Settings &cfg)
  {
    #ifdef CFG_HAS_STRAT_TOGGLES
      if(cfg.strat_toggles_seeded) return;
      cfg.strat_toggles_seeded = true;
      cfg.enable_strat_main               = true;
      cfg.enable_trend_vwap_pullback      = true;
      cfg.enable_trend_bos_continuation   = true;
      cfg.enable_mr_vwap_band             = true;
      cfg.enable_mr_range_nr7ib           = true;
      cfg.enable_breakout_squeeze         = true;
      cfg.enable_breakout_orb             = true;
      cfg.enable_reversal_sweep_choch     = true;
      cfg.enable_reversal_vsa_climax_fade = true;
      cfg.enable_corr_divergence          = true;
      cfg.enable_pairs_spreadlite         = true;
      cfg.enable_news_deviation           = true;
      cfg.enable_news_postfade            = true;
      cfg.enable_strat_ict_po3            = true;
      cfg.enable_strat_ict_continuation   = true;
      cfg.enable_strat_ict_silverbullet   = true;
      cfg.enable_strat_ict_wyckoff_turn   = true;
    #endif
  }
  
  // ICT / strategy quality thresholds: clamp + sane defaults
  inline void NormalizeICTQualityThresholds(Settings &cfg)
  {
    // Global "high quality" threshold
    if(cfg.qualityThresholdHigh <= 0.0)
      cfg.qualityThresholdHigh = 0.70;
    if(cfg.qualityThresholdHigh > 1.0)
      cfg.qualityThresholdHigh = 1.0;

    // Continuation (OB/FVG/OTE pullback) threshold
    if(cfg.qualityThresholdContinuation <= 0.0)
      cfg.qualityThresholdContinuation = 0.65;
    if(cfg.qualityThresholdContinuation > 1.0)
      cfg.qualityThresholdContinuation = 1.0;

    // Reversal (Wyckoff Spring / UTAD at extremes) threshold
    if(cfg.qualityThresholdReversal <= 0.0)
      cfg.qualityThresholdReversal = 0.60;
    if(cfg.qualityThresholdReversal > 1.0)
      cfg.qualityThresholdReversal = 1.0;
  }
  
  inline bool _AnyMainConfluenceConfigured(const Settings &cfg)
  {
    // If ANY toggle is on or ANY weight is positive, assume user/profile already configured it.
    if(cfg.cf_market_structure || cfg.cf_inst_zones || cfg.cf_orderflow_delta ||
       cfg.cf_liquidity || cfg.cf_orderblock_near || cfg.cf_vsa_increase ||
       cfg.cf_candle_pattern || cfg.cf_chart_pattern || cfg.cf_trend_regime ||
       cfg.cf_autochartist_chart || cfg.cf_autochartist_fib ||
       cfg.cf_autochartist_keylevels || cfg.cf_autochartist_volatility)
      return true;

    if(cfg.w_market_structure > 0.0 || cfg.w_inst_zones > 0.0 || cfg.w_orderflow_delta > 0.0 ||
       cfg.w_liquidity > 0.0 || cfg.w_orderblock_near > 0.0 || cfg.w_vsa_increase > 0.0 ||
       cfg.w_candle_pattern > 0.0 || cfg.w_chart_pattern > 0.0 || cfg.w_trend_regime > 0.0 ||
       cfg.w_autochartist_chart > 0.0 || cfg.w_autochartist_fib > 0.0 ||
       cfg.w_autochartist_keylevels > 0.0 || cfg.w_autochartist_volatility > 0.0)
      return true;

    return false;
  }

  inline void SeedMainConfluenceDefaults(Settings &cfg)
  {
    if(_AnyMainConfluenceConfigured(cfg))
      return;

    // Enable the core categories you require
    cfg.cf_market_structure = cfg.structure_enable;
    cfg.cf_inst_zones       = true;
    cfg.cf_orderflow_delta  = true;
    cfg.cf_liquidity        = cfg.liquidity_enable;
    cfg.cf_orderblock_near  = true;
    cfg.cf_vsa_increase     = cfg.vsa_enable;
    cfg.cf_candle_pattern   = true;
    cfg.cf_chart_pattern    = true;
    cfg.cf_trend_regime     = true;

    // Weights sum ≈ 1.00 so cf_min_score behaves predictably
    cfg.w_market_structure  = 0.15;
    cfg.w_inst_zones        = 0.15;
    cfg.w_orderflow_delta   = 0.15;
    cfg.w_liquidity         = 0.10;
    cfg.w_orderblock_near   = 0.10;
    cfg.w_vsa_increase      = 0.10;
    cfg.w_candle_pattern    = 0.10;
    cfg.w_chart_pattern     = 0.10;
    cfg.w_trend_regime      = 0.05;

    // --- Autochartist-style confluence (defaults OFF to avoid unexpected double-ups) ---
    cfg.cf_autochartist_chart      = false;
    cfg.cf_autochartist_fib        = false;
    cfg.cf_autochartist_keylevels  = false;
    cfg.cf_autochartist_volatility = false;
   
    // Weights (kept non-zero so enabling later doesn’t require hunting defaults)
    cfg.w_autochartist_chart      = 0.70;
    cfg.w_autochartist_fib        = 0.65;
    cfg.w_autochartist_keylevels  = 0.55;
    cfg.w_autochartist_volatility = 0.40;
   
    // Scanner core
    cfg.auto_enable       = false;
    cfg.auto_provider     = 0;
    cfg.auto_api_base_url = "";
    cfg.auto_api_user     = "";
    cfg.auto_api_pass     = "";

    cfg.auto_tf_mask      = 0;    // 0 => tf_entry only
    cfg.scan_tf_mask      = 0;
    cfg.auto_min_quality  = 0.0;  // 0 => use per-type mins

    // alias weights default to the canonical weights
    cfg.auto_weight_chart = cfg.w_autochartist_chart;
    cfg.auto_weight_fib   = cfg.w_autochartist_fib;
    cfg.auto_weight_key   = cfg.w_autochartist_keylevels;
    cfg.auto_weight_vol   = cfg.w_autochartist_volatility;

    cfg.auto_scan_interval_sec  = 60;
    cfg.auto_scan_lookback_bars = 320;
   
    // Autochartist patterns export (single truth)
    cfg.autoc_patt_export_level = AUTOC_PATT_EXPORT_EXT;          // preserves current “EXT snapshot” behavior
    cfg.autoc_patt_emit_mode    = AUTOC_PATT_EMIT_DIGEST_CHANGE;
    cfg.autoc_patt_topN         = 24;

    cfg.autoc_patt_min_score01       = 0.50;
    cfg.autoc_patt_min_score_autoc   = -1.0; // inherit
    cfg.autoc_patt_min_score_candle  = -1.0; // inherit
    cfg.autoc_patt_min_score_classic = -1.0; // inherit
    cfg.autoc_patt_min_score_sd      = -1.0; // inherit

     #ifdef CFG_HAS_AUTO_PATT_ALL_SETTINGS_FIELDS
       // Legacy mirrors are set again in Normalize(); initialize here for clean state
       cfg.auto_patt_all_enable = false;
       cfg.auto_patt_all_emit_mode = cfg.autoc_patt_emit_mode;
       cfg.auto_patt_all_topN      = cfg.autoc_patt_topN;

       cfg.auto_patt_all_min_score01      = cfg.autoc_patt_min_score01;
       cfg.auto_patt_all_min_score_autoc  = cfg.autoc_patt_min_score01;
       cfg.auto_patt_all_min_score_candle = cfg.autoc_patt_min_score01;
       cfg.auto_patt_all_min_score_classic= cfg.autoc_patt_min_score01;
       cfg.auto_patt_all_min_score_sd     = cfg.autoc_patt_min_score01;
     #endif
     
    #ifdef CFG_HAS_SCAN_FVG_SETTINGS
     cfg.scan_fvg_enable           = false;   // keep off by default (avoids scan load surprises)
     // default ON so FVG scanner respects scan_tf_mask but can be selectively gated later
     cfg.scan_fvg_tf_5m            = true;
     cfg.scan_fvg_tf_15m           = true;
     cfg.scan_fvg_tf_1h            = true;
     cfg.scan_fvg_approach_atr     = 0.25;    // approach band = 0.25 ATR
     cfg.scan_fvg_break_margin_atr = 0.05;    // breakout margin = 0.05 ATR
   
     cfg.scan_fvg_touch_zvol_min     = 0.75;
     cfg.scan_fvg_breakout_zvol_min  = 1.50;
     cfg.scan_fvg_touch_delta_min    = 0.25;
     cfg.scan_fvg_breakout_delta_min = 0.50;
     cfg.scan_fvg_use_atr_proxy      = true;
    #endif
    
    // Footprint / Delta fallback (used by Footprint + FVG confirmation)
    // cfg.scan_fvg_use_atr_proxy = true;

    #ifdef CFG_HAS_SCAN_TL_SETTINGS
       cfg.scan_tl_enable        = false;
   
       // Default: only short bucket inherits the master scan_tf_mask to avoid bucket overlap by default
       cfg.scan_tl_tf_mask_short = cfg.scan_tf_mask;
       cfg.scan_tl_tf_mask_mid   = 0;
       cfg.scan_tl_tf_mask_long  = 0;
   
       // Short bucket (tight, responsive)
       cfg.scan_tl_short_lookback_bars          = 500;
       cfg.scan_tl_short_pivot_left             = 2;
       cfg.scan_tl_short_pivot_right            = 2;
       cfg.scan_tl_short_min_touches            = 3;
       cfg.scan_tl_short_tol_atr_mult           = 0.25;
       cfg.scan_tl_short_break_atr_mult         = 0.10;
       cfg.scan_tl_short_dev_atr_mult           = 0.40;
       cfg.scan_tl_short_min_pivot_strength_atr = 0.15;
       cfg.scan_tl_short_pivot_price_src        = 0;  // WICK
       cfg.scan_tl_short_touch_price_src        = 0;  // WICK
       cfg.scan_tl_short_break_price_src        = 2;  // CLOSE
       cfg.scan_tl_short_confirmed_only         = true;
   
       // Mid bucket (balanced)
       cfg.scan_tl_mid_lookback_bars          = 800;
       cfg.scan_tl_mid_pivot_left             = 3;
       cfg.scan_tl_mid_pivot_right            = 3;
       cfg.scan_tl_mid_min_touches            = 3;
       cfg.scan_tl_mid_tol_atr_mult           = 0.30;
       cfg.scan_tl_mid_break_atr_mult         = 0.12;
       cfg.scan_tl_mid_dev_atr_mult           = 0.45;
       cfg.scan_tl_mid_min_pivot_strength_atr = 0.18;
       cfg.scan_tl_mid_pivot_price_src        = 0;  // WICK
       cfg.scan_tl_mid_touch_price_src        = 0;  // WICK
       cfg.scan_tl_mid_break_price_src        = 2;  // CLOSE
       cfg.scan_tl_mid_confirmed_only         = true;
   
       // Long bucket (slow, structural)
       cfg.scan_tl_long_lookback_bars          = 1200;
       cfg.scan_tl_long_pivot_left             = 4;
       cfg.scan_tl_long_pivot_right            = 4;
       cfg.scan_tl_long_min_touches            = 3;
       cfg.scan_tl_long_tol_atr_mult           = 0.35;
       cfg.scan_tl_long_break_atr_mult         = 0.15;
       cfg.scan_tl_long_dev_atr_mult           = 0.50;
       cfg.scan_tl_long_min_pivot_strength_atr = 0.20;
       cfg.scan_tl_long_pivot_price_src        = 0;  // WICK
       cfg.scan_tl_long_touch_price_src        = 0;  // WICK
       cfg.scan_tl_long_break_price_src        = 2;  // CLOSE
       cfg.scan_tl_long_confirmed_only         = true;
     #endif

    #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
      // Master toggles (keep OFF by default to avoid unexpected scan load)
      cfg.scan_liq_enable  = false;
      cfg.scan_liq_tf_5m       = true;
      cfg.scan_liq_tf_15m      = true;
      cfg.scan_liq_tf_1h       = true;
      cfg.scan_liq_emit_sweeps = true;
      
      cfg.scan_wyck_enable = false;
      // 0 means: Confluence will keep defaults (H4/D1)
      cfg.scan_wyck_tf_h4 = 0;
      cfg.scan_wyck_tf_d1 = 0;
      
      cfg.scan_obi_enable  = false;
      cfg.scan_foot_enable = false;
      cfg.scan_corr_enable = false;
      cfg.scan_news_enable = false;

      cfg.scan_foot_allow_ticks        = true;
      cfg.scan_foot_ticks_max_tf_sec   = 900;
      cfg.scan_foot_min_ticks          = 50;
   
      // Tick classification (OFIS)
      cfg.scan_foot_use_bidask_rule      = true;
      cfg.scan_foot_bidask_eps_points    = 1.0;   // 0.5–1.0 typical; 1.0 safe
      
      cfg.scan_foot_bin_points         = 2;
      cfg.scan_foot_max_levels         = 32;
   
      cfg.scan_foot_value_area_pct     = 0.70;
   
      cfg.scan_foot_imb_ratio          = 3.0;
      cfg.scan_foot_imb_min_vol        = 3.0;
      cfg.scan_foot_stacked_levels     = 3;
   
      cfg.scan_foot_absorb_depth_levels = 3;
      cfg.scan_foot_absorb_min_ratio    = 1.8;
   
      cfg.scan_foot_poc_approach_atr   = 0.10;
   
      cfg.scan_foot_use_atr_proxy      = true;

      // --- Wyckoff tuning (phase + manipulation + VSA confirmation)
      cfg.scan_wyck_emit_phase     = true;
      cfg.scan_wyck_phase_zvol_min = 0.50;
      cfg.scan_wyck_manip_zvol_min = 0.75;
      cfg.scan_wyck_lb_h4          = 300;
      cfg.scan_wyck_lb_d1          = 200;

      // --- OBI tuning (preserve prior "hardcode-like" behavior)
      cfg.scan_obi_depth_points  = 25;
      cfg.scan_obi_threshold     = 0.30;
      cfg.scan_obi_vwap_enable   = true;
      cfg.scan_obi_keylevel_atr  = 0.25;
      cfg.scan_obi_cache_ms      = 250;
      cfg.scan_obi_max_levels    = 20;
      cfg.scan_obi_min_tot_vol   = 0.0;
      cfg.scan_obi_vwap_dist_atr = 0.0; // disabled by default

      // --- OBI advanced defaults (back-compat: keep OFF / symmetric)
      cfg.scan_obi_mode                    = 0;     // symmetric (mode 3 proxy-footprint exists but remains opt-in)
      cfg.scan_obi_top_levels              = 0;     // disabled
      cfg.scan_obi_weighted_enable         = false; // disabled
      cfg.scan_obi_weight_half_life_points = 0.0;   // flat weights when disabled
      cfg.scan_obi_ema_len                 = 0;     // disabled
      cfg.scan_obi_weight_ref              = 0;     // MID
      
      // --- Footprint thresholds (z-score based)
      cfg.scan_foot_use_atr_proxy = cfg.scan_fvg_use_atr_proxy;
      cfg.scan_foot_zstrong       = 1.25;
      cfg.scan_foot_zdiverge      = 0.90;
      cfg.scan_foot_zabsorb       = 1.25;

      // --- OFIS defaults (Order Flow Imbalance System)
      cfg.scan_of_delta_ema_len     = 14;
      cfg.scan_of_cvd_ema_len       = 20;
      cfg.scan_of_z_len             = 50;
      cfg.scan_of_ofpi_thr          = 40.0;

      cfg.scan_of_absorb_k_sigma    = 1.5;
      cfg.scan_of_absorb_m_atr      = 0.5;

      cfg.scan_of_exhaust_lb        = 5;
      cfg.scan_of_htf_mult          = 4;
      
      // --- Correlation tuning
      cfg.scan_corr_threshold = 0.70;
      cfg.scan_corr_recover   = 0.55;
      cfg.scan_corr_len       = 90;

      #ifdef CFG_HAS_SCAN_CORR_DETECTOR_SETTINGS
        cfg.scan_corr_secondary_symbol = "";
        cfg.scan_corr_price            = PRICE_CLOSE;
        cfg.scan_corr_use_log_returns  = true;
        cfg.scan_corr_smooth_len       = 5;
        cfg.scan_corr_div_sensitivity  = 0.30;
        cfg.scan_corr_z_len            = 200;
        cfg.scan_corr_mom_k            = 5;
        cfg.scan_corr_z_thr            = 2.0;
        cfg.scan_corr_mom_thr          = 0.20;
        cfg.scan_corr_mtf_len_enable   = false;
      #endif

      // --- News timing + optional strategy windows (scanner emits only)
      cfg.scan_news_soon_sec           = 2700; // 45 minutes
      cfg.scan_news_block_sec          = 5400; // 90 minutes
      cfg.scan_news_emit_strat_windows = false;

      cfg.scan_news_straddle_sec            = 300;  // 5m
      cfg.scan_news_fade_sec                = 600;  // 10m
      cfg.scan_news_breakout_sec            = 1800; // 30m
      cfg.scan_news_breakout_squeeze_ratio  = 0.80;
      cfg.scan_news_breakout_lookback_bars  = 20;

      // --- Volume Profile defaults
      cfg.scan_vp_enable           = false;
      cfg.scan_vp_lookback_bars    = 200;
      cfg.scan_vp_bin_points       = 10;
      cfg.scan_vp_value_area_pct   = 0.70;
      cfg.scan_vp_touch_atr        = 0.15;
      cfg.scan_vp_break_margin_atr = 0.05;
      cfg.scan_vp_poc_shift_atr    = 0.25;
      cfg.scan_vp_stale_sec        = 900;
      cfg.scan_vp_distribute_range = false;
    #endif

    // --- Liquidity pool thresholds (fields exist regardless of CFG_HAS_SCAN_EXTRA_SETTINGS)
    cfg.scan_liq_pool_approach_atr    = 0.35;
    cfg.scan_liq_confirm_bars         = 6;
    cfg.scan_liq_warmup_bars          = 600;
    cfg.scan_liq_accept_margin_atr    = 0.15;
    cfg.scan_liq_reject_margin_atr    = 0.10;
    cfg.scan_liq_struct_break_eps_atr = 0.05;
    cfg.scan_liq_min_zvol             = 1.00;
   
    #ifdef CFG_HAS_FVG_MIN_SCORE
     cfg.fvg_min_score = 0.55;
    #endif
    #ifdef CFG_HAS_FVG_MODE
     cfg.fvg_mode = FVG_ALL;
    #endif
    #ifdef CFG_HAS_FVG_LOOKBACK_BARS
     cfg.fvg_lookback_bars = 200;
    #endif
    #ifdef CFG_HAS_FVG_IMPULSE_LOOKAHEAD_BARS
     cfg.fvg_impulse_lookahead_bars = 6;
    #endif
    #ifdef CFG_HAS_FVG_MIN_GAP_ATR
     cfg.fvg_min_gap_atr = 0.25;
    #endif

    // Chart patterns (local)
    cfg.auto_chart_min_quality  = 0.60;
    cfg.auto_chart_pivot_L      = 3;
    cfg.auto_chart_pivot_R      = 3;
   
    cfg.auto_chart_rr_norm                     = 2.0;
    cfg.main_chart_retest_max_atr              = 1.0;
    cfg.main_min_rr_from_chart_target          = 1.2;
    cfg.main_autoc_completed_dir_mismatch_veto = false;
    cfg.main_autoc_tighten_invalidation        = false;

    #ifdef CFG_HAS_PATTERNS_SD_SETTINGS
      // SD base patterns (RBR/DBD/RBD/DBR) defaults (match Patterns SD spec knobs)
      cfg.sd_atr_period          = 14;
      cfg.sd_base_min_bars       = 3;
      cfg.sd_base_max_bars       = 8;
      
      cfg.sd_min_move_atr        = 1.50;
      cfg.sd_max_base_range_atr  = 0.50;
      
      cfg.sd_break_min_pips      = 0.0;
      cfg.sd_break_atr_k         = 0.0;
      cfg.sd_close_confirm_only  = true;
      
      cfg.sd_use_volume_filter   = false;
      cfg.sd_vol_spike_k         = 1.25;
    #endif

    // Fibonacci/harmonic (local)
    cfg.auto_fib_min_quality    = 0.60;   
    cfg.autofib_ratio_tolerance = 0.05;   // 0.03–0.07 typical
    cfg.auto_fib_pivot_L        = cfg.auto_chart_pivot_L;
    cfg.auto_fib_pivot_R        = cfg.auto_chart_pivot_R;
   
    cfg.auto_fib_stop_atr_mult  = 0.35;   // stop beyond PRZ
    cfg.auto_fib_target_r1      = 0.382;
    cfg.auto_fib_target_r2      = 0.618;
    cfg.auto_fib_target_r3      = 1.000;

    // Key levels (local)
    cfg.auto_keylevel_min_touches  = 3;
    cfg.auto_keylevel_cluster_atr  = 0.18;
    cfg.auto_keylevel_approach_atr = 0.22;
   
    cfg.auto_keylevel_min_pips          = 5.0;   // minimum cluster width (pips)
    cfg.auto_keylevel_break_margin_atr  = 0.15;  // breakout must clear band by this * ATR
    cfg.auto_keylevel_bounce_window     = 8;     // bars to measure post-touch bounce

    cfg.auto_keylevel_w_touches         = 0.45;
    cfg.auto_keylevel_w_recency         = 0.25;
    cfg.auto_keylevel_w_bounce          = 0.30;
    
    #ifdef CFG_HAS_AUTO_KEY_MIN_SIG
       cfg.auto_key_min_sig = 0.55; // sane baseline; tune later
    #endif
    
    #ifdef CFG_HAS_SR_DETECTOR_SETTINGS
      cfg.sr_pivot_left        = 5;
      cfg.sr_pivot_right       = 5;
      cfg.sr_use_fractals      = false;

      // Default to static/no-repaint so backtests and “opportunity events” don’t thrash
      cfg.sr_static_mode       = true;

      cfg.sr_level_expiry_bars = 1000;   // 0 => never expire
      cfg.sr_max_levels        = 12;

      // Typical institutional-ish zoning: ~0.25 ATR band
      cfg.sr_zone_width_atr    = 0.25;

      // Volume confirmation ratios (relative to average volume / zVol baseline upstream)
      cfg.sr_break_vol_ratio   = 1.50;   // ~150%
      cfg.sr_touch_vol_ratio   = 1.20;   // ~120%

      // 0 => compute only on tf_entry (same semantics as auto_tf_mask / scan_tf_mask)
      cfg.sr_mtf_mask          = 0;
    #endif

    // Volatility / movement (local)
    cfg.auto_vol_lookback_days     = 180;
    cfg.auto_vol_horizon_minutes   = 60;
    cfg.auto_vol_min_range_atr     = 0.90;
   
    // PowerStats-like knobs (default conservative)
    cfg.auto_vol_use_m15              = true;
    cfg.auto_vol_sd_mult              = 1.0;

    cfg.auto_vol_sltp_sanity_enable   = false; // OFF by default (avoid behavior shift)
    cfg.auto_vol_sl_max_mult          = 2.5;
    cfg.auto_vol_sl_min_frac          = 0.15;
    cfg.auto_vol_tp_cap_mult          = 1.75;
    cfg.auto_vol_tp_cap_breakout_mult = 2.75;
    cfg.auto_vol_breakout_adx01       = 0.60;
    cfg.auto_vol_sanity_clamp         = true;

    // Risk scaling (optional)
    cfg.auto_risk_scale_enable = false;
    cfg.auto_risk_scale_floor  = 0.70;
    cfg.auto_risk_scale_cap    = 1.20;

     // If user left thresholds unset/zero, apply sane baselines
     if(cfg.cf_min_needed <= 0) cfg.cf_min_needed = 5;
     if(cfg.cf_min_score  <= 0) cfg.cf_min_score  = 0.55;
  }

  // -----------------------------
  // Autochartist direction gating (DRY)
  // -----------------------------
  inline double AutoChartDirGateConf01(const double auto_chart_min_quality01)
  {
    double q = auto_chart_min_quality01;
    if(q < 0.0) q = 0.0;
    if(q > 1.0) q = 1.0;

    double c = q * 0.25; // keep the exact aligned formula
    if(c < 0.0) c = 0.0;
    if(c > 1.0) c = 1.0;
    return c;
  }

  inline double AutoChartDirGateDelta01(const double auto_chart_min_quality01)
  {
    const double c = AutoChartDirGateConf01(auto_chart_min_quality01);
    return (c / 3.0);
  }

  inline double AutoChartDirGateConf(const Settings &cfg)
  {
    return AutoChartDirGateConf01(cfg.auto_chart_min_quality);
  }

  inline double AutoChartDirGateDelta(const Settings &cfg)
  {
    return AutoChartDirGateDelta01(cfg.auto_chart_min_quality);
  }

  // Bridge legacy ICT toggles -> new strat toggles (one-way; non-destructive)
  inline void SyncLegacyICTToggles(Settings &cfg)
  {
    // If older flags are explicitly turned ON, make sure the new strat toggles are also ON.
    // We do NOT force them OFF if the legacy flag is false.
    #ifdef CFG_HAS_LEGACY_ICT_PO3
        if(cfg.enable_ict_po3)
          cfg.enable_strat_ict_po3 = true;
    #endif
   
    #ifdef CFG_HAS_LEGACY_ICT_SILVERBULLET
        if(cfg.enable_ict_silverbullet)
          cfg.enable_strat_ict_silverbullet = true;
    #endif
   
    #ifdef CFG_HAS_LEGACY_ICT_WYCKOFF_UTAD
        if(cfg.enable_ict_wyckoff_utad)
          cfg.enable_strat_ict_wyckoff_turn = true;
    #endif
  }

  inline void Normalize(Settings &cfg)
  {
    ConfigCore::Normalize(cfg);
    // Ensure Main confluence toggles/weights are not left uninitialized
    SeedMainConfluenceDefaults(cfg);
    
    // WyckoffCycle sanity + defaults
    #ifdef CFG_HAS_WYCK_CYCLE_SETTINGS
      // detect "unset" blocks (common after CSV load into a zeroed struct)
      bool atrUnset = (cfg.wyck_atr_len<=0 && cfg.wyck_atr_ma_len<=0);
      bool bbUnset  = (cfg.wyck_bb_len<=0 && cfg.wyck_bb_dev<=0.0);

      if(cfg.wyck_range_lookback<=0) cfg.wyck_range_lookback = 150;
      if(cfg.wyck_min_range_bars<=0) cfg.wyck_min_range_bars = 20;

      if(cfg.wyck_eq_tol_atr<=0.0)   cfg.wyck_eq_tol_atr     = 0.25;
      if(cfg.wyck_max_range_atr<=0.0)cfg.wyck_max_range_atr  = 2.5;

      if(atrUnset) cfg.wyck_use_atr_compression = true;
      if(bbUnset)  cfg.wyck_use_bb_compression  = true;

      if(cfg.wyck_atr_len<=0)        cfg.wyck_atr_len        = 14;
      if(cfg.wyck_atr_ma_len<=0)     cfg.wyck_atr_ma_len     = 50;

      if(cfg.wyck_bb_len<=0)         cfg.wyck_bb_len         = 20;
      if(cfg.wyck_bb_dev<=0.0)       cfg.wyck_bb_dev         = 2.0;
      if(cfg.wyck_bb_width_thr<=0.0) cfg.wyck_bb_width_thr   = 0.015;

      if(cfg.wyck_swingL<=0)         cfg.wyck_swingL         = 5;
      if(cfg.wyck_swingR<=0)         cfg.wyck_swingR         = 5;

      if(cfg.wyck_bos_confirm_closes<=0) cfg.wyck_bos_confirm_closes = 1;

      if(cfg.wyck_manip_min_quality<=0.0) cfg.wyck_manip_min_quality = 0.55;
      if(cfg.wyck_wick_min_ratio<=0.0)    cfg.wyck_wick_min_ratio    = 0.60;
      if(cfg.wyck_close_inside_min<=0.0)  cfg.wyck_close_inside_min  = 0.20;

      if(cfg.wyck_ar_window_bars<=0) cfg.wyck_ar_window_bars = 60;
      if(cfg.wyck_vol_len<=0)        cfg.wyck_vol_len        = 20;
      if(cfg.wyck_vol_mult<=0.0)     cfg.wyck_vol_mult       = 1.5;

      // clamps (keep bounded; prevent accidental nonsense)
      cfg.wyck_range_lookback      = MathMin(MathMax(cfg.wyck_range_lookback,      50), 200);
      cfg.wyck_min_range_bars      = MathMin(MathMax(cfg.wyck_min_range_bars,      10), 120);

      cfg.wyck_eq_tol_atr          = MathMin(MathMax(cfg.wyck_eq_tol_atr,          0.05), 1.0);
      cfg.wyck_max_range_atr       = MathMin(MathMax(cfg.wyck_max_range_atr,       0.5), 10.0);

      cfg.wyck_atr_len             = MathMin(MathMax(cfg.wyck_atr_len,             10), 21);
      cfg.wyck_atr_ma_len          = MathMin(MathMax(cfg.wyck_atr_ma_len,          20), 100);

      cfg.wyck_bb_len              = MathMin(MathMax(cfg.wyck_bb_len,              14), 50);
      cfg.wyck_bb_dev              = MathMin(MathMax(cfg.wyck_bb_dev,              1.5), 3.0);
      cfg.wyck_bb_width_thr        = MathMin(MathMax(cfg.wyck_bb_width_thr,        0.005), 0.03);

      cfg.wyck_swingL              = MathMin(MathMax(cfg.wyck_swingL,              2), 5);
      cfg.wyck_swingR              = MathMin(MathMax(cfg.wyck_swingR,              2), 5);

      cfg.wyck_bos_confirm_closes  = MathMin(MathMax(cfg.wyck_bos_confirm_closes,  1), 3);

      cfg.wyck_manip_min_quality   = MathMin(MathMax(cfg.wyck_manip_min_quality,   0.40), 0.80);
      cfg.wyck_wick_min_ratio      = MathMin(MathMax(cfg.wyck_wick_min_ratio,      0.55), 0.80);
      cfg.wyck_close_inside_min    = MathMin(MathMax(cfg.wyck_close_inside_min,    0.10), 0.40);

      cfg.wyck_ar_window_bars      = MathMin(MathMax(cfg.wyck_ar_window_bars,      40), 120);
      cfg.wyck_vol_len             = MathMin(MathMax(cfg.wyck_vol_len,             10), 50);
      cfg.wyck_vol_mult            = MathMin(MathMax(cfg.wyck_vol_mult,            1.2), 3.0);
    #endif

    #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
      // OBI scanner sanity clamps
      if(cfg.scan_obi_depth_points < 5)   cfg.scan_obi_depth_points = 5;
      if(cfg.scan_obi_depth_points > 200) cfg.scan_obi_depth_points = 200;

      if(cfg.scan_obi_threshold < 0.05) cfg.scan_obi_threshold = 0.05;
      if(cfg.scan_obi_threshold > 0.95) cfg.scan_obi_threshold = 0.95;

      if(cfg.scan_obi_keylevel_atr < 0.0) cfg.scan_obi_keylevel_atr = 0.0;
      if(cfg.scan_obi_keylevel_atr > 3.0) cfg.scan_obi_keylevel_atr = 3.0;
      
      // OBI tuning clamps
      if(cfg.scan_obi_cache_ms < 0)   cfg.scan_obi_cache_ms = 0;
      if(cfg.scan_obi_cache_ms > 5000) cfg.scan_obi_cache_ms = 5000;

      if(cfg.scan_obi_max_levels < 0)  cfg.scan_obi_max_levels = 0;
      if(cfg.scan_obi_max_levels > 200) cfg.scan_obi_max_levels = 200;

      if(cfg.scan_obi_min_tot_vol < 0.0) cfg.scan_obi_min_tot_vol = 0.0;

      if(cfg.scan_obi_vwap_dist_atr < 0.0) cfg.scan_obi_vwap_dist_atr = 0.0;
      if(cfg.scan_obi_vwap_dist_atr > 10.0) cfg.scan_obi_vwap_dist_atr = 10.0;

      // OBI advanced mode / aggregation clamps
      if(cfg.scan_obi_mode < 0) cfg.scan_obi_mode = 0;
      if(cfg.scan_obi_mode > 3) cfg.scan_obi_mode = 3; // mode 3 = proxy-footprint fallback

      if(cfg.scan_obi_top_levels < 0)  cfg.scan_obi_top_levels = 0;
      if(cfg.scan_obi_top_levels > 50) cfg.scan_obi_top_levels = 50;

      if(cfg.scan_obi_weight_half_life_points < 0.0)
         cfg.scan_obi_weight_half_life_points = 0.0;

      if(cfg.scan_obi_ema_len < 0)   cfg.scan_obi_ema_len = 0;
      if(cfg.scan_obi_ema_len > 200) cfg.scan_obi_ema_len = 200;

      // Normalize 1 => disabled (keep semantics clean: 0/1 disabled, >=2 active)
      if(cfg.scan_obi_ema_len == 1) cfg.scan_obi_ema_len = 0;

      if(cfg.scan_obi_weight_ref < 0) cfg.scan_obi_weight_ref = 0;
      if(cfg.scan_obi_weight_ref > 2) cfg.scan_obi_weight_ref = 2;
      
      // Wyckoff TF selector clamps (0 allowed; invalid -> 0)
      if(cfg.scan_wyck_tf_h4 < 0) cfg.scan_wyck_tf_h4 = 0;
      if(cfg.scan_wyck_tf_d1 < 0) cfg.scan_wyck_tf_d1 = 0;
      
      // NEWS scanner sanity clamps + defaults (seconds-based)
      if(cfg.scan_news_soon_sec < 0)  cfg.scan_news_soon_sec = 0;
      if(cfg.scan_news_block_sec < 0) cfg.scan_news_block_sec = 0;

      // If unset, tie SOON window to the effective pre-news block (Config::NewsPreMins uses block_pre_m/news_pre_mins)
      if(cfg.scan_news_soon_sec == 0)
        cfg.scan_news_soon_sec = Config::NewsPreMins(cfg) * 60;

      // Strategy windows (seconds)
      if(cfg.scan_news_straddle_sec <= 0) cfg.scan_news_straddle_sec = 300;   // 5m
      if(cfg.scan_news_fade_sec     <= 0) cfg.scan_news_fade_sec     = 600;   // 10m
      if(cfg.scan_news_breakout_sec <= 0) cfg.scan_news_breakout_sec = 1800;  // 30m

      // Keep values bounded (avoid accidental 10-year windows 😅)
      if(cfg.scan_news_soon_sec   > 86400) cfg.scan_news_soon_sec   = 86400;
      if(cfg.scan_news_block_sec  > 86400) cfg.scan_news_block_sec  = 86400;
      if(cfg.scan_news_straddle_sec > 86400) cfg.scan_news_straddle_sec = 86400;
      if(cfg.scan_news_fade_sec     > 86400) cfg.scan_news_fade_sec     = 86400;
      if(cfg.scan_news_breakout_sec > 86400) cfg.scan_news_breakout_sec = 86400;

      if(cfg.scan_news_breakout_squeeze_ratio < 0.10) cfg.scan_news_breakout_squeeze_ratio = 0.10;
      if(cfg.scan_news_breakout_squeeze_ratio > 2.00) cfg.scan_news_breakout_squeeze_ratio = 2.00;

      if(cfg.scan_news_breakout_lookback_bars < 5)   cfg.scan_news_breakout_lookback_bars = 5;
      if(cfg.scan_news_breakout_lookback_bars > 500) cfg.scan_news_breakout_lookback_bars = 500;
    #endif

    // Correlation scanner thresholds
    if(cfg.scan_corr_threshold <= 0.0) cfg.scan_corr_threshold = 0.75;
    if(cfg.scan_corr_threshold > 0.99) cfg.scan_corr_threshold = 0.99;
   
    if(cfg.scan_corr_recover <= 0.0) cfg.scan_corr_recover = 0.55;
    if(cfg.scan_corr_recover < 0.0)  cfg.scan_corr_recover = 0.0;
   
    // enforce hysteresis: recover must be below threshold
    if(cfg.scan_corr_recover >= cfg.scan_corr_threshold)
      cfg.scan_corr_recover = cfg.scan_corr_threshold * 0.80;
   
    if(cfg.scan_corr_len < 20)  cfg.scan_corr_len = 20;
    if(cfg.scan_corr_len > 500) cfg.scan_corr_len = 500;
    
    #ifdef CFG_HAS_SCAN_CORR_DETECTOR_SETTINGS
     if(cfg.scan_corr_smooth_len < 1)  cfg.scan_corr_smooth_len = 1;
     if(cfg.scan_corr_smooth_len > 50) cfg.scan_corr_smooth_len = 50;
   
     if(cfg.scan_corr_div_sensitivity <= 0.0) cfg.scan_corr_div_sensitivity = 0.30;
     if(cfg.scan_corr_div_sensitivity > 2.0)  cfg.scan_corr_div_sensitivity = 2.0;
   
     if(cfg.scan_corr_z_len < 20)  cfg.scan_corr_z_len = 20;
     if(cfg.scan_corr_z_len > 600) cfg.scan_corr_z_len = 600;
   
     if(cfg.scan_corr_mom_k < 1) cfg.scan_corr_mom_k = 1;
     if(cfg.scan_corr_mom_k >= cfg.scan_corr_z_len) cfg.scan_corr_mom_k = MathMax(1, cfg.scan_corr_z_len/4);
   
     if(cfg.scan_corr_z_thr <= 0.0) cfg.scan_corr_z_thr = 2.0;
     if(cfg.scan_corr_z_thr > 10.0) cfg.scan_corr_z_thr = 10.0;
   
     if(cfg.scan_corr_mom_thr <= 0.0) cfg.scan_corr_mom_thr = 0.20;
     if(cfg.scan_corr_mom_thr > 1.0)  cfg.scan_corr_mom_thr = 1.0;
    #endif
   
    #ifdef CFG_HAS_ML_THRESHOLD
      if(cfg.ml_threshold <= 0.0) cfg.ml_threshold = 0.55;  // keep existing fallback behavior
      if(cfg.ml_threshold < 0.0)  cfg.ml_threshold = 0.0;
      if(cfg.ml_threshold > 1.0)  cfg.ml_threshold = 1.0;
    #endif

    #ifdef CFG_HAS_ML_SETTINGS
        // --- ML lifecycle normalization (safe even when loaded from CSV)
        if(cfg.ml_weight < 0.0) cfg.ml_weight = 0.0;
        if(cfg.ml_weight > 1.0) cfg.ml_weight = 1.0;
      
        if(cfg.ml_temperature < 0.01) cfg.ml_temperature = 1.0;
      
        if(cfg.ml_conformal_alpha < 0.0) cfg.ml_conformal_alpha = 0.0;
        if(cfg.ml_conformal_alpha > 0.50) cfg.ml_conformal_alpha = 0.50;
      
        if(cfg.ml_dampen < 0.0) cfg.ml_dampen = 0.0;
        if(cfg.ml_dampen > 1.0) cfg.ml_dampen = 1.0;
      
        #ifdef CFG_HAS_ML_SLTP_MULT
            // Bounds sanity for ML SL/TP multipliers
            if(cfg.ml_sltp_sl_min < 0.50) cfg.ml_sltp_sl_min = 0.50;
            if(cfg.ml_sltp_sl_max < 0.50) cfg.ml_sltp_sl_max = 0.50;
            if(cfg.ml_sltp_sl_min > 2.50) cfg.ml_sltp_sl_min = 2.50;
            if(cfg.ml_sltp_sl_max > 2.50) cfg.ml_sltp_sl_max = 2.50;
         
            if(cfg.ml_sltp_tp_min < 0.50) cfg.ml_sltp_tp_min = 0.50;
            if(cfg.ml_sltp_tp_max < 0.50) cfg.ml_sltp_tp_max = 0.50;
            if(cfg.ml_sltp_tp_min > 5.00) cfg.ml_sltp_tp_min = 5.00;
            if(cfg.ml_sltp_tp_max > 5.00) cfg.ml_sltp_tp_max = 5.00;
         
            // Ensure min <= max
            if(cfg.ml_sltp_sl_min > cfg.ml_sltp_sl_max)
            {
               const double tmp = cfg.ml_sltp_sl_min;
               cfg.ml_sltp_sl_min = cfg.ml_sltp_sl_max;
               cfg.ml_sltp_sl_max = tmp;
            }
            if(cfg.ml_sltp_tp_min > cfg.ml_sltp_tp_max)
            {
               const double tmp = cfg.ml_sltp_tp_min;
               cfg.ml_sltp_tp_min = cfg.ml_sltp_tp_max;
               cfg.ml_sltp_tp_max = tmp;
            }
        #endif

        if(cfg.ml_model_max_age_hours < 0) cfg.ml_model_max_age_hours = 0;
      
        if(cfg.ml_min_oos_auc < 0.0) cfg.ml_min_oos_auc = 0.0;
        if(cfg.ml_min_oos_auc > 1.0) cfg.ml_min_oos_auc = 1.0;
      
        if(cfg.ml_min_oos_acc < 0.0) cfg.ml_min_oos_acc = 0.0;
        if(cfg.ml_min_oos_acc > 1.0) cfg.ml_min_oos_acc = 1.0;
      
        if(cfg.ml_min_samples_train < 0) cfg.ml_min_samples_train = 0;
        if(cfg.ml_min_samples_test  < 0) cfg.ml_min_samples_test  = 0;
      
        if(cfg.ml_label_horizon_bars < 1) cfg.ml_label_horizon_bars = 1;
        if(cfg.ml_label_atr_mult < 0.0)   cfg.ml_label_atr_mult = 0.0;
      
        // File defaults (only if empty) — keeps behavior stable
        if(cfg.ml_model_file == "")   cfg.ml_model_file   = "CAEA_MLModel.ini";
        if(cfg.ml_dataset_file == "") cfg.ml_dataset_file = "CAEA_MLDataset.csv";
      
        // External integration normalization
        if(cfg.ml_external_mode < 0) cfg.ml_external_mode = 0;
        if(cfg.ml_external_mode > 2) cfg.ml_external_mode = 2;
      
        if(cfg.ml_external_poll_ms < 250) cfg.ml_external_poll_ms = 250;
      
        if(cfg.ml_external_file == "") cfg.ml_external_file = "CAEA_MLExternal.csv";
        if(cfg.ml_external_socket_host == "") cfg.ml_external_socket_host = "127.0.0.1";
        if(cfg.ml_external_socket_port < 0) cfg.ml_external_socket_port = 0;
        if(cfg.ml_external_socket_port == 0) cfg.ml_external_socket_port = 5050;
    #endif

    // Assets & TFs
    if(ArraySize(cfg.asset_list)<=0){ ArrayResize(cfg.asset_list,1); cfg.asset_list[0]=_Symbol; }
    if(cfg.tf_entry<PERIOD_M1) cfg.tf_entry=PERIOD_M5;
    if(cfg.tf_h1  <PERIOD_M1)  cfg.tf_h1  =PERIOD_H1;
    if(cfg.tf_h4  <PERIOD_M1)  cfg.tf_h4  =PERIOD_H4;
    if(cfg.tf_d1  <PERIOD_M1)  cfg.tf_d1  =PERIOD_D1;

    // Mode (guard if not declared)
    #ifdef CFG_HAS_STRAT_MODE
      const int cur = (int)cfg.strat_mode;
      const int clamped = _ClampStratModeInt(cur);
      if(cur != clamped)
        if(cfg.debug) PrintFormat("[Config] strat_mode clamped: %d -> %d", cur, clamped);
        _SetStratModeRef(cfg.strat_mode, clamped);
    #endif
    // Pack strategies must never be active under MAIN_ONLY; and disable_packs hard-kills them.
    #ifdef CFG_HAS_ENABLE_PACK_STRATS
      #ifdef CFG_HAS_STRAT_MODE
        if(CfgStrategyMode(cfg) == STRAT_MAIN_ONLY)
        {
          // Default: packs OFF in MAIN_ONLY.
          // Exception: if the router confluence-only pool is enabled, allow packs to remain
          // registered/enabled for confluence-only computation (they still cannot trade).
          const bool allow_pack_confl = CfgMainOnly_AllowPackConfluencePool(cfg);
          if(!allow_pack_confl)
            cfg.enable_pack_strats = false;
        }
      #endif
   
      #ifdef CFG_HAS_DISABLE_PACKS
        if(cfg.disable_packs)
          cfg.enable_pack_strats = false;
      #endif
    #endif
    #ifdef CFG_HAS_MODE
      if((int)cfg.mode<0) cfg.mode=BSM_BOTH;
    #endif

     // Directional bias mode: clamp to valid enum range [0..1].
     // 0 = DIRM_MANUAL_SELECTOR, 1 = DIRM_AUTO_SMARTMONEY
     if(cfg.direction_bias_mode < (int)DIRM_MANUAL_SELECTOR ||
        cfg.direction_bias_mode > (int)DIRM_AUTO_SMARTMONEY)
     {
       cfg.direction_bias_mode = (int)DIRM_MANUAL_SELECTOR;
     }
  
    #ifdef CFG_HAS_MIN_FEATURES_MET
      if(cfg.min_features_met < 0) cfg.min_features_met = 0;
        // Optional upper bound if you consider CF__COUNT:
        // if(cfg.min_features_met > (int)CF__COUNT) cfg.min_features_met = (int)CF__COUNT;
    #endif
      
    #ifdef CFG_HAS_ENABLE_HARD_GATE
        // bool; no clamp needed
    #endif
    #ifdef CFG_HAS_REQUIRE_TREND_FILTER
        // bool
    #endif
    #ifdef CFG_HAS_REQUIRE_ADX_REGIME
        // bool
    #endif
    #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
        // bool
    #endif
    #ifdef CFG_HAS_LONDON_LIQ_POLICY
        // bool
    #endif
    #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
     // default ON if uninitialized (paranoid guard; optional)
     // (MQL5 zero-inits structs, so this only matters for partial copies)
     // if(!cfg.weekly_open_spread_ramp) cfg.weekly_open_spread_ramp = true;
    #endif

    // Trade selector
    if((int)cfg.trade_selector<0 || (int)cfg.trade_selector>2) cfg.trade_selector=TRADE_BOTH_AUTO;
    
     // Keep cached direction selector coherent (manual overrides must survive AUTO mode)
     const ENUM_TRADE_DIRECTION manualDir = TradeSelectorToDirection(cfg.trade_selector);
     if(manualDir == TDIR_BUY || manualDir == TDIR_SELL)
       cfg.trade_direction_selector = manualDir;
     else if((DirectionBiasMode)cfg.direction_bias_mode == DIRM_MANUAL_SELECTOR)
       cfg.trade_direction_selector = manualDir; // TDIR_BOTH
     else
       cfg.trade_direction_selector = TDIR_BOTH; // AUTO mode uses ICT gate at runtime

    // Defensive clamp (covers bad imports / external overrides)
    if((int)cfg.trade_direction_selector < 0 || (int)cfg.trade_direction_selector > 2)
      cfg.trade_direction_selector = TDIR_BOTH;
      
    // Risk (cfg.* are in PERCENT units, e.g., 1.0 = 1%)
    if(cfg.risk_pct<0.0001) cfg.risk_pct=0.0001;
    #ifdef CFG_HAS_RISK_MULT_MAX
      if(cfg.risk_mult_max <= 0.0) cfg.risk_mult_max = 1.0;
      if(cfg.risk_mult_max > 5.0)  cfg.risk_mult_max = 5.0;
    #endif
    
    if(cfg.min_sl_pips<0.0) cfg.min_sl_pips=0.0;
    if(cfg.min_tp_pips<0.0) cfg.min_tp_pips=0.0;
    if(cfg.max_sl_ceiling_pips<cfg.min_sl_pips) cfg.max_sl_ceiling_pips=cfg.min_sl_pips;
    if(cfg.max_daily_dd_pct <= 0.0) cfg.max_daily_dd_pct = 2.0;
    // Broker-enforced SL floor: use StopsLevel + FreezeLevel (in points).
    // We treat min_sl_pips as "points" here to avoid double-guessing your pip math.
    // If your pipeline already treats it as true pips, you can scale accordingly.
    int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    if(point > 0.0)
    {
      int total_pts      = stops_level + freeze_level;
      // If broker exposes 0 (some do), don't accidentally zero out your floor.
      if(total_pts > 0)
      {
        double broker_min = (double)total_pts;   // "points" floor

        if(cfg.min_sl_pips < broker_min)
          cfg.min_sl_pips = broker_min;

        if(cfg.max_sl_ceiling_pips < cfg.min_sl_pips)
          cfg.max_sl_ceiling_pips = cfg.min_sl_pips;
      }
    }
    
    #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
      if(cfg.day_dd_limit_pct<0.0) cfg.day_dd_limit_pct=0.0;
    #endif
    
    #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
      if(cfg.adaptive_dd_window_days < 2)   cfg.adaptive_dd_window_days = 30;
      if(cfg.adaptive_dd_window_days > 365) cfg.adaptive_dd_window_days = 365;
    #endif
   
    #ifdef CFG_HAS_ADAPTIVE_DD_PCT
      if(cfg.adaptive_dd_pct <= 0.0)
        cfg.adaptive_dd_pct = cfg.max_daily_dd_pct;
    #endif
   
    #ifdef CFG_HAS_BIGLOSS_RESET_R
      if(cfg.bigloss_reset_r <= 0.0) cfg.bigloss_reset_r = 2.0;
    #endif
   
    #ifdef CFG_HAS_BIGLOSS_RESET_MINS
      if(cfg.bigloss_reset_mins < 0)      cfg.bigloss_reset_mins = 0;
      if(cfg.bigloss_reset_mins > 24*60)  cfg.bigloss_reset_mins = 24*60;
    #endif

    // Legacy aliases / HTF slot
    if(cfg.risk_per_trade <= 0.0)
      cfg.risk_per_trade = cfg.risk_pct;
      
    #ifdef CFG_HAS_TRADE_CD_SEC
        if(cfg.trade_cd_sec < 0) cfg.trade_cd_sec = 0;
        if(cfg.trade_cd_sec > 86400) cfg.trade_cd_sec = 86400; // cap at 24h
    #endif

    // Default HTF reference to D1 if unset
    if(cfg.tf_htf < PERIOD_M1)
      cfg.tf_htf = cfg.tf_d1;

    // Keep NewsFilter toggle coherent with news_on and compile flag
    cfg.newsFilterEnabled = (cfg.news_on && (NEWSFILTER_AVAILABLE != 0));
    
    #ifdef CFG_HAS_NEWS_BACKEND
      // Keep within NewsFilter's expected range (0..3)
       if(cfg.news_backend_mode < 0) cfg.news_backend_mode = 0;
      if(cfg.news_backend_mode > 3) cfg.news_backend_mode = 3;
    #endif

    if(cfg.max_losses_day<0) cfg.max_losses_day=0;
    if(cfg.max_trades_day<0) cfg.max_trades_day=0;
    if(cfg.max_spread_points<0) cfg.max_spread_points=0;
    
    // AutoVol cache (MarketData 5.6) clamps
    if(cfg.auto_vol_cache_hours < 1) cfg.auto_vol_cache_hours = 1;
   
    // Preserve "daily aligned" meaning at exactly 24.
    // Any other value is treated as N-hour cadence by MarketData.
    if(cfg.auto_vol_cache_hours > 168) cfg.auto_vol_cache_hours = 168; // 7 days cap (sane upper bound)
   
    if(cfg.auto_vol_adr_lookback_days < 5) cfg.auto_vol_adr_lookback_days = 5;
    if(cfg.auto_vol_adr_lookback_days > 200) cfg.auto_vol_adr_lookback_days = 200;
   
    if(cfg.auto_vol_ret_lookback_d1 < 20) cfg.auto_vol_ret_lookback_d1 = 20;
    if(cfg.auto_vol_ret_lookback_d1 > 400) cfg.auto_vol_ret_lookback_d1 = 400;
    
    #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
      if(cfg.max_positions_per_symbol < 1 || cfg.max_positions_per_symbol > 50) // Fail-safe: if garbage/unset, revert to legacy behavior (1)
        cfg.max_positions_per_symbol = 1;
    #endif
   
    #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
      if(cfg.max_positions_total < 0 || cfg.max_positions_total > 500) // 0 = unlimited. If garbage/unset, disable total cap (0).
        cfg.max_positions_total = 0; // 0 = unlimited
    #endif
    // Slippage: give the first attempt a generous budget.
    //  - rc=0 rejections are common when slippage is too tight.
    //  - 300–500 points on 5-digit FX is prop-friendly (30–50 pips),
    //    and later attempts can taper via BaseDeviationPoints/SpreadAwareBumpPts.
    if(cfg.slippage_points <= 0)
      cfg.slippage_points = 300;     // default if unset
    else if(cfg.slippage_points < 100)
      cfg.slippage_points = 100;     // enforce a sane minimu
    
    // Fibonacci / OTE clamps
    if(cfg.fibDepth < 2)     cfg.fibDepth = 2;
    if(cfg.fibDepth > 50)    cfg.fibDepth = 50;

    if(cfg.fibATRPeriod < 5)   cfg.fibATRPeriod = 5;
    if(cfg.fibATRPeriod > 100) cfg.fibATRPeriod = 100;

    if(cfg.fibDevATRMult < 0.5)  cfg.fibDevATRMult = 0.5;
    if(cfg.fibDevATRMult > 10.0) cfg.fibDevATRMult = 10.0;

    if(cfg.fibMaxBarsBack < 100)  cfg.fibMaxBarsBack = 100;
    if(cfg.fibMaxBarsBack > 5000) cfg.fibMaxBarsBack = 5000;

    #ifdef CFG_HAS_FIB_SETTINGS
      // CanonicalCSV uses ',' between k=v pairs → values MUST NOT contain commas.
      // Convert commas to ';' so SplitCSV() still works (it auto-detects ';' first).
      StringReplace(cfg.fibRetraceRatiosCSV, ",", ";");
      StringReplace(cfg.fibExtensionRatiosCSV, ",", ";");
      cfg.fibRetraceRatiosCSV   = Trim(cfg.fibRetraceRatiosCSV);
      cfg.fibExtensionRatiosCSV = Trim(cfg.fibExtensionRatiosCSV);

      // OTE tolerance sanity
      if(cfg.fibOTEToleranceATR < 0.0) cfg.fibOTEToleranceATR = 0.0;
      if(cfg.fibOTEToleranceATR > 5.0) cfg.fibOTEToleranceATR = 5.0;

      // OTE band sanity (ratio space)
      if(cfg.fibOTE_Low  < 0.0)  cfg.fibOTE_Low  = 0.0;
      if(cfg.fibOTE_Low  > 0.99) cfg.fibOTE_Low  = 0.99;
      if(cfg.fibOTE_High < 0.0)  cfg.fibOTE_High = 0.0;
      if(cfg.fibOTE_High > 1.0)  cfg.fibOTE_High = 1.0;

      if(cfg.fibOTE_Low >= cfg.fibOTE_High)
      {
        // reset to canonical OTE band
        cfg.fibOTE_Low  = 0.618;
        cfg.fibOTE_High = 0.786;
      }

      // Range-defense leg filters
      if(cfg.fibMinLegHeightATR < 0.0)  cfg.fibMinLegHeightATR = 0.0;
      if(cfg.fibMinLegHeightATR > 10.0) cfg.fibMinLegHeightATR = 10.0;

      if(cfg.fibMinLegBars < 1)   cfg.fibMinLegBars = 1;
      if(cfg.fibMinLegBars > 500) cfg.fibMinLegBars = 500;

      // "Near level" threshold
      if(cfg.fibApproachATRMult < 0.01) cfg.fibApproachATRMult = 0.01;
      if(cfg.fibApproachATRMult > 5.0)  cfg.fibApproachATRMult = 5.0;
    #endif

    if(cfg.fibMinConfluenceScore < 0.0) cfg.fibMinConfluenceScore = 0.0;
    if(cfg.fibMinConfluenceScore > 1.0) cfg.fibMinConfluenceScore = 1.0;

    if(cfg.fibOTEQualityBonusReversal < 0.0)
      cfg.fibOTEQualityBonusReversal = 0.0;
    if(cfg.fibOTEQualityBonusReversal > 0.5)
      cfg.fibOTEQualityBonusReversal = 0.5;

    // Fib RR gating: keep in a sane band (0..5R) on the canonical field
    if(cfg.minRRFibAllowed < 0.0) cfg.minRRFibAllowed = 0.0;
    if(cfg.minRRFibAllowed > 5.0) cfg.minRRFibAllowed = 5.0;

    #ifdef CFG_HAS_FIB_MIN_RR_ALLOWED
      // Sync optional alias <-> canonical field.
      // 1) If only the alias is set, propagate into canonical.
      if(cfg.fib_min_rr_allowed > 0.0 && cfg.minRRFibAllowed <= 0.0)
        cfg.minRRFibAllowed = cfg.fib_min_rr_allowed;

      // 2) If only the canonical is set, reflect it into the alias.
      if(cfg.minRRFibAllowed > 0.0 && cfg.fib_min_rr_allowed <= 0.0)
        cfg.fib_min_rr_allowed = cfg.minRRFibAllowed;

      // 3) Clamp the alias as well, so both live in [0..5].
      if(cfg.fib_min_rr_allowed < 0.0) cfg.fib_min_rr_allowed = 0.0;
      if(cfg.fib_min_rr_allowed > 5.0) cfg.fib_min_rr_allowed = 5.0;
    #endif
    // fibRRHardReject is a bool; no clamp needed
    
    // ---- DOM / footprint clamps (not part of CFG_HAS_CF_WEIGHTS)
    #ifdef CFG_HAS_W_VOLUME_FP
      cfg.w_volume_footprint = MathMax(0.0, cfg.w_volume_footprint);
    #endif

    #ifdef CFG_HAS_W_DOM_IMBALANCE
      cfg.w_dom_imbalance = MathMax(0.0, cfg.w_dom_imbalance);
    #endif

    #ifdef CFG_HAS_W_TRENDLINES
      cfg.w_trendlines = MathMax(0.0, cfg.w_trendlines);
    #endif

    #ifdef CFG_HAS_DOM_ZONE_PAD_POINTS
      if(cfg.dom_zone_pad_points < 0) cfg.dom_zone_pad_points = 0;
      if(cfg.dom_zone_pad_points > 500) cfg.dom_zone_pad_points = 500; // sanity cap
    #endif

    #ifdef CFG_HAS_DOM_MIN_ABS_IMB
      if(cfg.dom_min_abs_imb <= 0.0) cfg.dom_min_abs_imb = 0.15;
      if(cfg.dom_min_abs_imb < 0.01) cfg.dom_min_abs_imb = 0.01;
      if(cfg.dom_min_abs_imb > 1.00) cfg.dom_min_abs_imb = 1.00;
    #endif

    // Loop
    if(cfg.timer_ms<25) cfg.timer_ms=25;

    // Sessions (legacy UTC minutes)
    cfg.london_open_utc  = ClampMinute(cfg.london_open_utc);
    cfg.london_close_utc = ClampMinute(cfg.london_close_utc);
    cfg.ny_open_utc      = ClampMinute(cfg.ny_open_utc);
    cfg.ny_close_utc     = ClampMinute(cfg.ny_close_utc);

    // Anchors/presets
    if((int)cfg.session_preset<0) cfg.session_preset=SESS_OFF;
    if(cfg.tokyo_close_utc<=0) cfg.tokyo_close_utc=6*60;      // 06:00 UTC
    if(cfg.sydney_open_utc<=0) cfg.sydney_open_utc=21*60;     // 21:00 UTC
    cfg.tokyo_close_utc=ClampMinute(cfg.tokyo_close_utc);
    cfg.sydney_open_utc=ClampMinute(cfg.sydney_open_utc);

    // News
    if(cfg.block_pre_m<0) cfg.block_pre_m=0;
    if(cfg.block_post_m<0) cfg.block_post_m=0;

    // ATR/TP/SL
    if(cfg.atr_period<2) cfg.atr_period=14;
    if(cfg.tp_quantile<0.0) cfg.tp_quantile=0.0; if(cfg.tp_quantile>1.0) cfg.tp_quantile=1.0;
    if(cfg.tp_minr_floor<0.0) cfg.tp_minr_floor=0.0;
    if(cfg.atr_sl_mult<0.0) cfg.atr_sl_mult=0.0;

    // Day profit-based taper defaults (prop-friendly)
    // If unset, use 2% start, 3% stop, floor 0.35. Stop is always >= start.
    if(cfg.day_profit_cap_pct <= 0.0)  cfg.day_profit_cap_pct  = 2.0;
    if(cfg.day_profit_stop_pct <= 0.0) cfg.day_profit_stop_pct = 3.0;
    if(cfg.day_profit_stop_pct < cfg.day_profit_cap_pct)
       cfg.day_profit_stop_pct = cfg.day_profit_cap_pct;

    // Monthly target: only forbid negatives; defaulting is done via CfgMonthlyTargetPct.
    #ifdef CFG_HAS_MONTHLY_TARGET
      if(cfg.monthly_target_pct < 0.0)
        cfg.monthly_target_pct = 0.0;
      // Clamp monthly target cycle/base modes to known constants
      if(cfg.monthly_target_cycle_mode != CFG_TARGET_CYCLE_CALENDAR &&
         cfg.monthly_target_cycle_mode != CFG_TARGET_CYCLE_ROLLING_28D)
      {
        cfg.monthly_target_cycle_mode = CFG_TARGET_CYCLE_DEFAULT;
      }
      
      if(cfg.monthly_target_base_mode < CFG_TARGET_BASE_CYCLE_START ||
         cfg.monthly_target_base_mode > CFG_TARGET_BASE_INITIAL_COMPOUND)
      {
        cfg.monthly_target_base_mode = CFG_TARGET_BASE_DEFAULT;
      }
    #endif
     
    if(cfg.taper_floor <= 0.0) cfg.taper_floor = 0.35;
    if(cfg.taper_floor > 1.0)  cfg.taper_floor = 1.0;

    // Account-wide DD: clamp non-negative; 0.0 keeps it disabled until set
    #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
        if(cfg.challenge_init_equity < 0.0) cfg.challenge_init_equity = 0.0;
    #endif

    // Position mgmt
    #ifdef CFG_HAS_PM_MODE
      if(cfg.pm_mode < 0) cfg.pm_mode = 0;
      else if(cfg.pm_mode > 2) cfg.pm_mode = 2;
    #endif

    if(cfg.be_at_R<0.0) cfg.be_at_R=0.0;
    if(cfg.be_lock_pips<0.0) cfg.be_lock_pips=0.0;
    if((int)cfg.trail_type < 0) cfg.trail_type = (TrailType)0;
    if((int)cfg.trail_type > 5) cfg.trail_type = (TrailType)5;
    if(cfg.trail_pips<0.0) cfg.trail_pips=0.0;
    if(cfg.trail_atr_mult<0.0) cfg.trail_atr_mult=0.0;
    
    #ifdef CFG_HAS_TRAIL_AUTO_ADX_TF
      if((int)cfg.trail_auto_adx_tf < (int)PERIOD_M1)
        cfg.trail_auto_adx_tf = cfg.tf_h1;
    #endif
   
    #ifdef CFG_HAS_TRAIL_AUTO_ADX_PERIOD
      if(cfg.trail_auto_adx_period < 2)
        cfg.trail_auto_adx_period = 14;
    #endif
   
    #ifdef CFG_HAS_TRAIL_AUTO_ADX_MIN
      if(cfg.trail_auto_adx_min <= 0.0)
        cfg.trail_auto_adx_min = 25.0;
      if(cfg.trail_auto_adx_min > 80.0)
        cfg.trail_auto_adx_min = 80.0;
    #endif

    if(cfg.p1_at_R<0.0) cfg.p1_at_R=0.0;
    if(cfg.p2_at_R<0.0) cfg.p2_at_R=0.0;
    if(cfg.p1_close_pct<0.0) cfg.p1_close_pct=0.0; if(cfg.p1_close_pct>100.0) cfg.p1_close_pct=100.0;
    if(cfg.p2_close_pct<0.0) cfg.p2_close_pct=0.0; if(cfg.p2_close_pct>100.0) cfg.p2_close_pct=100.0;

    // Calendar
    if(cfg.cal_lookback_mins<5) cfg.cal_lookback_mins=5;
    if(cfg.cal_hard_skip<0.0) cfg.cal_hard_skip=0.0;
    if(cfg.cal_soft_knee<0.0) cfg.cal_soft_knee=0.0;
    if(cfg.cal_soft_knee>=cfg.cal_hard_skip && cfg.cal_hard_skip>0.0) cfg.cal_soft_knee=cfg.cal_hard_skip*0.5;
    if(cfg.cal_min_scale<0.0) cfg.cal_min_scale=0.0; if(cfg.cal_min_scale>1.0) cfg.cal_min_scale=1.0;
    
    // ---- Confluence gates & indicator clamps (new)
    #ifdef CFG_HAS_CF_MIN_NEEDED
      cfg.cf_min_needed = MathMax(0, cfg.cf_min_needed);
    #endif
    #ifdef CFG_HAS_CF_MIN_SCORE
      cfg.cf_min_score  = MathMin(MathMax(cfg.cf_min_score, 0.0), 1.0);
    #endif

    #ifdef CFG_HAS_ORDERFLOW_TH
      if(cfg.orderflow_th <= 0.0) cfg.orderflow_th = 0.60;
      if(cfg.orderflow_th < 0.10) cfg.orderflow_th = 0.10;
      if(cfg.orderflow_th > 5.00) cfg.orderflow_th = 5.00;
    #endif
   
    #ifdef CFG_HAS_TF_TREND_HTF
      if((int)cfg.tf_trend_htf < (int)PERIOD_M1) cfg.tf_trend_htf = cfg.tf_h4; // PERIOD_CURRENT(0) falls here
    #endif

    #ifdef CFG_HAS_CF_WEIGHTS
      cfg.w_inst_zones       = MathMax(0.0, cfg.w_inst_zones);
      cfg.w_orderflow_delta  = MathMax(0.0, cfg.w_orderflow_delta);
      cfg.w_orderblock_near  = MathMax(0.0, cfg.w_orderblock_near);
      cfg.w_candle_pattern   = MathMax(0.0, cfg.w_candle_pattern);
      cfg.w_chart_pattern    = MathMax(0.0, cfg.w_chart_pattern);
      cfg.w_market_structure = MathMax(0.0, cfg.w_market_structure);
      cfg.w_trend_regime     = MathMax(0.0, cfg.w_trend_regime);
      cfg.w_stochrsi         = MathMax(0.0, cfg.w_stochrsi);
      cfg.w_macd             = MathMax(0.0, cfg.w_macd);
      cfg.w_correlation      = MathMax(0.0, cfg.w_correlation);
      cfg.w_news             = MathMax(0.0, cfg.w_news);
      // --- Autochartist-style weights ---
      cfg.w_autochartist_chart      = MathMin(MathMax(cfg.w_autochartist_chart,      0.0), 2.0);
      cfg.w_autochartist_fib        = MathMin(MathMax(cfg.w_autochartist_fib,        0.0), 2.0);
      cfg.w_autochartist_keylevels  = MathMin(MathMax(cfg.w_autochartist_keylevels,  0.0), 2.0);
      cfg.w_autochartist_volatility = MathMin(MathMax(cfg.w_autochartist_volatility, 0.0), 2.0);
      
      // Avoid double-ups: Autochartist chart patterns replace legacy chart-pattern confluence
      if(cfg.cf_autochartist_chart)
      {
        cfg.cf_chart_pattern = false;
        cfg.w_chart_pattern  = 0.0;
      }
    #endif

     // ---- Autochartist-style scanner clamps ----
     // Scan cadence / lookback
     if(cfg.auto_scan_interval_sec < 5)   cfg.auto_scan_interval_sec = 5;
     if(cfg.auto_scan_interval_sec > 900) cfg.auto_scan_interval_sec = 900;
      
     if(cfg.auto_scan_lookback_bars < 120)  cfg.auto_scan_lookback_bars = 120;
     if(cfg.auto_scan_lookback_bars > 2000) cfg.auto_scan_lookback_bars = 2000;
      
     // ---- Autochartist patterns export clamps (single truth) ----
     cfg.autoc_patt_export_level = MathMax(0, MathMin(cfg.autoc_patt_export_level, (int)AUTOC_PATT_EXPORT_FULL));
     cfg.autoc_patt_emit_mode    = MathMax(0, MathMin(cfg.autoc_patt_emit_mode,    (int)AUTOC_PATT_EMIT_ALWAYS));

     if(cfg.autoc_patt_topN < 0)  cfg.autoc_patt_topN = 0;
     if(cfg.autoc_patt_topN > 64) cfg.autoc_patt_topN = 64;

     cfg.autoc_patt_min_score01 = MathMin(MathMax(cfg.autoc_patt_min_score01, 0.0), 1.0);

     if(cfg.autoc_patt_min_score_autoc < 0.0) cfg.autoc_patt_min_score_autoc = cfg.autoc_patt_min_score01;
     else cfg.autoc_patt_min_score_autoc = MathMin(MathMax(cfg.autoc_patt_min_score_autoc, 0.0), 1.0);

     if(cfg.autoc_patt_min_score_candle < 0.0) cfg.autoc_patt_min_score_candle = cfg.autoc_patt_min_score01;
     else cfg.autoc_patt_min_score_candle = MathMin(MathMax(cfg.autoc_patt_min_score_candle, 0.0), 1.0);

     if(cfg.autoc_patt_min_score_classic < 0.0) cfg.autoc_patt_min_score_classic = cfg.autoc_patt_min_score01;
     else cfg.autoc_patt_min_score_classic = MathMin(MathMax(cfg.autoc_patt_min_score_classic, 0.0), 1.0);

     if(cfg.autoc_patt_min_score_sd < 0.0) cfg.autoc_patt_min_score_sd = cfg.autoc_patt_min_score01;
     else cfg.autoc_patt_min_score_sd = MathMin(MathMax(cfg.autoc_patt_min_score_sd, 0.0), 1.0);

     #ifdef CFG_HAS_AUTO_PATT_ALL_SETTINGS_FIELDS
       // Legacy mirrors (read-only): keep old AutochartistEngine paths stable
       cfg.auto_patt_all_enable = (cfg.autoc_patt_export_level >= (int)AUTOC_PATT_EXPORT_FULL);

       cfg.auto_patt_all_emit_mode = cfg.autoc_patt_emit_mode;
       cfg.auto_patt_all_topN      = cfg.autoc_patt_topN;

       cfg.auto_patt_all_min_score01      = cfg.autoc_patt_min_score01;
       cfg.auto_patt_all_min_score_autoc  = cfg.autoc_patt_min_score_autoc;
       cfg.auto_patt_all_min_score_candle = cfg.autoc_patt_min_score_candle;
       cfg.auto_patt_all_min_score_classic= cfg.autoc_patt_min_score_classic;
       cfg.auto_patt_all_min_score_sd     = cfg.autoc_patt_min_score_sd;
     #endif
     
      #ifdef CFG_HAS_SCAN_FVG_SETTINGS
        cfg.scan_fvg_approach_atr     = MathMin(MathMax(cfg.scan_fvg_approach_atr,     0.05), 3.0);
        cfg.scan_fvg_break_margin_atr = MathMin(MathMax(cfg.scan_fvg_break_margin_atr, 0.00), 1.0);
      
        cfg.scan_fvg_touch_zvol_min     = MathMin(MathMax(cfg.scan_fvg_touch_zvol_min,     0.0), 5.0);
        cfg.scan_fvg_breakout_zvol_min  = MathMin(MathMax(cfg.scan_fvg_breakout_zvol_min,  0.0), 8.0);
        cfg.scan_fvg_touch_delta_min    = MathMin(MathMax(cfg.scan_fvg_touch_delta_min,    0.0), 5.0);
        cfg.scan_fvg_breakout_delta_min = MathMin(MathMax(cfg.scan_fvg_breakout_delta_min, 0.0), 8.0);
      #endif
      
      cfg.scan_news_soon_sec  = MathMax(60,  cfg.scan_news_soon_sec);
      cfg.scan_news_block_sec = MathMax(cfg.scan_news_soon_sec, cfg.scan_news_block_sec);
      
      #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
         #ifdef CFG_HAS_SCAN_TL_SETTINGS
         // Trendlines scan: enforce sane ranges
         if(cfg.scan_tl_tf_mask_short < 0) cfg.scan_tl_tf_mask_short = 0;
         if(cfg.scan_tl_tf_mask_mid   < 0) cfg.scan_tl_tf_mask_mid   = 0;
         if(cfg.scan_tl_tf_mask_long  < 0) cfg.scan_tl_tf_mask_long  = 0;
         
         // If enabled but no TFs selected, fall back to master scan_tf_mask
         if(cfg.scan_tl_enable)
         {
           const int m = (cfg.scan_tl_tf_mask_short | cfg.scan_tl_tf_mask_mid | cfg.scan_tl_tf_mask_long);
           if(m == 0) cfg.scan_tl_tf_mask_short = cfg.scan_tf_mask;
         }
         
         // Helper-style clamping without introducing new helpers
         if(cfg.scan_tl_short_lookback_bars < 50) cfg.scan_tl_short_lookback_bars = 50;
         if(cfg.scan_tl_mid_lookback_bars   < 50) cfg.scan_tl_mid_lookback_bars   = 50;
         if(cfg.scan_tl_long_lookback_bars  < 50) cfg.scan_tl_long_lookback_bars  = 50;
         
         if(cfg.scan_tl_short_pivot_left  < 1) cfg.scan_tl_short_pivot_left  = 1;
         if(cfg.scan_tl_short_pivot_right < 0) cfg.scan_tl_short_pivot_right = 0;
         if(cfg.scan_tl_mid_pivot_left    < 1) cfg.scan_tl_mid_pivot_left    = 1;
         if(cfg.scan_tl_mid_pivot_right   < 0) cfg.scan_tl_mid_pivot_right   = 0;
         if(cfg.scan_tl_long_pivot_left   < 1) cfg.scan_tl_long_pivot_left   = 1;
         if(cfg.scan_tl_long_pivot_right  < 0) cfg.scan_tl_long_pivot_right  = 0;
         
         if(cfg.scan_tl_short_min_touches < 2) cfg.scan_tl_short_min_touches = 2;
         if(cfg.scan_tl_mid_min_touches   < 2) cfg.scan_tl_mid_min_touches   = 2;
         if(cfg.scan_tl_long_min_touches  < 2) cfg.scan_tl_long_min_touches  = 2;
         
         if(cfg.scan_tl_short_tol_atr_mult < 0.0) cfg.scan_tl_short_tol_atr_mult = 0.0;
         if(cfg.scan_tl_short_break_atr_mult     < 0.0) cfg.scan_tl_short_break_atr_mult     = 0.0;
         if(cfg.scan_tl_short_dev_atr_mult       < 0.0) cfg.scan_tl_short_dev_atr_mult       = 0.0;
         if(cfg.scan_tl_short_min_pivot_strength_atr < 0.0) cfg.scan_tl_short_min_pivot_strength_atr = 0.0;
         
         if(cfg.scan_tl_mid_tol_atr_mult < 0.0) cfg.scan_tl_mid_tol_atr_mult = 0.0;
         if(cfg.scan_tl_mid_break_atr_mult     < 0.0) cfg.scan_tl_mid_break_atr_mult     = 0.0;
         if(cfg.scan_tl_mid_dev_atr_mult       < 0.0) cfg.scan_tl_mid_dev_atr_mult       = 0.0;
         if(cfg.scan_tl_mid_min_pivot_strength_atr < 0.0) cfg.scan_tl_mid_min_pivot_strength_atr = 0.0;
         
         if(cfg.scan_tl_long_tol_atr_mult < 0.0) cfg.scan_tl_long_tol_atr_mult = 0.0;
         if(cfg.scan_tl_long_break_atr_mult     < 0.0) cfg.scan_tl_long_break_atr_mult     = 0.0;
         if(cfg.scan_tl_long_dev_atr_mult       < 0.0) cfg.scan_tl_long_dev_atr_mult       = 0.0;
         if(cfg.scan_tl_long_min_pivot_strength_atr < 0.0) cfg.scan_tl_long_min_pivot_strength_atr = 0.0;
         
         // Price source clamps: 0..2
         if(cfg.scan_tl_short_pivot_price_src < 0) cfg.scan_tl_short_pivot_price_src = 0;
         if(cfg.scan_tl_short_pivot_price_src > 2) cfg.scan_tl_short_pivot_price_src = 2;
         if(cfg.scan_tl_short_touch_price_src < 0) cfg.scan_tl_short_touch_price_src = 0;
         if(cfg.scan_tl_short_touch_price_src > 2) cfg.scan_tl_short_touch_price_src = 2;
         if(cfg.scan_tl_short_break_price_src < 0) cfg.scan_tl_short_break_price_src = 0;
         if(cfg.scan_tl_short_break_price_src > 2) cfg.scan_tl_short_break_price_src = 2;
         
         if(cfg.scan_tl_mid_pivot_price_src < 0) cfg.scan_tl_mid_pivot_price_src = 0;
         if(cfg.scan_tl_mid_pivot_price_src > 2) cfg.scan_tl_mid_pivot_price_src = 2;
         if(cfg.scan_tl_mid_touch_price_src < 0) cfg.scan_tl_mid_touch_price_src = 0;
         if(cfg.scan_tl_mid_touch_price_src > 2) cfg.scan_tl_mid_touch_price_src = 2;
         if(cfg.scan_tl_mid_break_price_src < 0) cfg.scan_tl_mid_break_price_src = 0;
         if(cfg.scan_tl_mid_break_price_src > 2) cfg.scan_tl_mid_break_price_src = 2;
         
         if(cfg.scan_tl_long_pivot_price_src < 0) cfg.scan_tl_long_pivot_price_src = 0;
         if(cfg.scan_tl_long_pivot_price_src > 2) cfg.scan_tl_long_pivot_price_src = 2;
         if(cfg.scan_tl_long_touch_price_src < 0) cfg.scan_tl_long_touch_price_src = 0;
         if(cfg.scan_tl_long_touch_price_src > 2) cfg.scan_tl_long_touch_price_src = 2;
         if(cfg.scan_tl_long_break_price_src < 0) cfg.scan_tl_long_break_price_src = 0;
         if(cfg.scan_tl_long_break_price_src > 2) cfg.scan_tl_long_break_price_src = 2;
         #endif

        // Footprint z-score thresholds (defensive clamps)
        cfg.scan_foot_zstrong  = MathMin(MathMax(cfg.scan_foot_zstrong,  0.25), 8.0);
        cfg.scan_foot_zdiverge = MathMin(MathMax(cfg.scan_foot_zdiverge, 0.10), 8.0);

        // Absorption should never be easier than "strong"
        if(cfg.scan_foot_zabsorb < cfg.scan_foot_zstrong)
          cfg.scan_foot_zabsorb = cfg.scan_foot_zstrong;

        cfg.scan_foot_zabsorb  = MathMin(MathMax(cfg.scan_foot_zabsorb,  cfg.scan_foot_zstrong), 10.0);
      #endif
      #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
          cfg.scan_foot_ticks_max_tf_sec    = MathMax(60, cfg.scan_foot_ticks_max_tf_sec);
          cfg.scan_foot_min_ticks           = MathMax(0,  cfg.scan_foot_min_ticks);
      
          cfg.scan_foot_bin_points          = MathMax(1,  cfg.scan_foot_bin_points);
          cfg.scan_foot_max_levels          = MathMax(8,  cfg.scan_foot_max_levels);
      
          cfg.scan_foot_value_area_pct      = MathMin(0.95, MathMax(0.50, cfg.scan_foot_value_area_pct));
      
          cfg.scan_foot_imb_ratio           = MathMin(10.0, MathMax(1.2, cfg.scan_foot_imb_ratio));
          cfg.scan_foot_imb_min_vol         = MathMax(0.0, cfg.scan_foot_imb_min_vol);
          cfg.scan_foot_stacked_levels      = MathMin(10, MathMax(2, cfg.scan_foot_stacked_levels));
      
          cfg.scan_foot_absorb_depth_levels = MathMin(10, MathMax(1, cfg.scan_foot_absorb_depth_levels));
          cfg.scan_foot_absorb_min_ratio    = MathMin(10.0, MathMax(1.2, cfg.scan_foot_absorb_min_ratio));
      
          cfg.scan_foot_poc_approach_atr    = MathMin(2.0, MathMax(0.01, cfg.scan_foot_poc_approach_atr));
          
          // Tick classification clamps (eps in POINTS)
          cfg.scan_foot_bidask_eps_points = MathMin(5.0, MathMax(0.0, cfg.scan_foot_bidask_eps_points));

          // OFIS clamps (defensive)
          cfg.scan_of_delta_ema_len  = MathMin(200, MathMax(2,  cfg.scan_of_delta_ema_len));   // EMA lens 2..200
          cfg.scan_of_cvd_ema_len    = MathMin(200, MathMax(2,  cfg.scan_of_cvd_ema_len));     // EMA lens 2..200
          cfg.scan_of_z_len          = MathMin(500, MathMax(10, cfg.scan_of_z_len));           // z window (safe)

          cfg.scan_of_ofpi_thr       = MathMin(95.0, MathMax(5.0,  cfg.scan_of_ofpi_thr));     // OFPI thr 5..95

          cfg.scan_of_absorb_k_sigma = MathMin(5.0,  MathMax(0.5,  cfg.scan_of_absorb_k_sigma)); // sigma 0.5..5
          cfg.scan_of_absorb_m_atr   = MathMin(2.0,  MathMax(0.05, cfg.scan_of_absorb_m_atr));   // ATR mult 0.05..2

          cfg.scan_of_exhaust_lb     = MathMin(50, MathMax(2, cfg.scan_of_exhaust_lb));        // 2..50
          cfg.scan_of_htf_mult       = MathMin(24, MathMax(1, cfg.scan_of_htf_mult));          // practical cap
      #endif

      // --- Liquidity pool clamps (always-present fields)
      cfg.scan_liq_pool_approach_atr    = MathMin(MathMax(cfg.scan_liq_pool_approach_atr,    0.05), 5.0);
      cfg.scan_liq_confirm_bars         = MathMin(MathMax(cfg.scan_liq_confirm_bars,         1),    50);
      cfg.scan_liq_warmup_bars          = MathMin(MathMax(cfg.scan_liq_warmup_bars,          0),    20000);
      cfg.scan_liq_accept_margin_atr    = MathMin(MathMax(cfg.scan_liq_accept_margin_atr,    0.00), 1.0);
      cfg.scan_liq_reject_margin_atr    = MathMin(MathMax(cfg.scan_liq_reject_margin_atr,    0.00), 1.0);
      cfg.scan_liq_struct_break_eps_atr = MathMin(MathMax(cfg.scan_liq_struct_break_eps_atr, 0.00), 1.0);
      cfg.scan_liq_min_zvol             = MathMin(MathMax(cfg.scan_liq_min_zvol,             0.00), 10.0);

      #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
        // --- OBI clamps
        cfg.scan_obi_depth_points = MathMin(MathMax(cfg.scan_obi_depth_points, 1), 250);
        cfg.scan_obi_threshold    = MathMin(MathMax(cfg.scan_obi_threshold,    0.00), 1.00);
        cfg.scan_obi_keylevel_atr = MathMin(MathMax(cfg.scan_obi_keylevel_atr, 0.05), 5.0);

        // --- Wyckoff clamps
        cfg.scan_wyck_phase_zvol_min = MathMin(MathMax(cfg.scan_wyck_phase_zvol_min, 0.00), 8.0);
        cfg.scan_wyck_manip_zvol_min = MathMin(MathMax(cfg.scan_wyck_manip_zvol_min, 0.00), 10.0);
        cfg.scan_wyck_lb_h4          = MathMin(MathMax(cfg.scan_wyck_lb_h4,          50), 5000);
        cfg.scan_wyck_lb_d1          = MathMin(MathMax(cfg.scan_wyck_lb_d1,          50), 5000);

        // --- Correlation clamps (hysteresis: recover <= threshold)
        cfg.scan_corr_threshold = MathMin(MathMax(cfg.scan_corr_threshold, 0.00), 0.999);
        cfg.scan_corr_recover   = MathMin(MathMax(cfg.scan_corr_recover,   0.00), cfg.scan_corr_threshold);
        cfg.scan_corr_len       = MathMin(MathMax(cfg.scan_corr_len,       20),   600);

        // --- News strategy-window clamps (seconds)
        cfg.scan_news_straddle_sec = MathMin(MathMax(cfg.scan_news_straddle_sec, 0), 86400);
        cfg.scan_news_fade_sec     = MathMin(MathMax(cfg.scan_news_fade_sec,     0), 86400);
        cfg.scan_news_breakout_sec = MathMin(MathMax(cfg.scan_news_breakout_sec, 0), 86400);

        cfg.scan_news_breakout_squeeze_ratio = MathMin(MathMax(cfg.scan_news_breakout_squeeze_ratio, 0.10), 2.00);
        cfg.scan_news_breakout_lookback_bars = MathMin(MathMax(cfg.scan_news_breakout_lookback_bars, 5),    500);

        // --- Volume Profile clamps
        cfg.scan_vp_lookback_bars    = MathMin(MathMax(cfg.scan_vp_lookback_bars,    50),  5000);
        cfg.scan_vp_bin_points       = MathMin(MathMax(cfg.scan_vp_bin_points,       1),   2000);
        cfg.scan_vp_value_area_pct   = MathMin(MathMax(cfg.scan_vp_value_area_pct,   0.50), 0.95);

        cfg.scan_vp_touch_atr        = MathMin(MathMax(cfg.scan_vp_touch_atr,        0.01), 3.0);
        cfg.scan_vp_break_margin_atr = MathMin(MathMax(cfg.scan_vp_break_margin_atr, 0.00), 1.0);
        cfg.scan_vp_poc_shift_atr    = MathMin(MathMax(cfg.scan_vp_poc_shift_atr,    0.01), 5.0);

        cfg.scan_vp_stale_sec        = MathMin(MathMax(cfg.scan_vp_stale_sec,        60),  86400);
      #endif

      #ifdef CFG_HAS_FVG_LOOKBACK_BARS
        cfg.fvg_lookback_bars = MathMin(MathMax(cfg.fvg_lookback_bars, 50), 3000);
      #endif
      #ifdef CFG_HAS_FVG_IMPULSE_LOOKAHEAD_BARS
        cfg.fvg_impulse_lookahead_bars = MathMin(MathMax(cfg.fvg_impulse_lookahead_bars, 1), 50);
      #endif
      #ifdef CFG_HAS_FVG_MIN_GAP_ATR
        cfg.fvg_min_gap_atr = MathMin(MathMax(cfg.fvg_min_gap_atr, 0.0), 5.0);
      #endif

      // Provider / API (fail-safe to local)
      if(cfg.auto_provider < 0 || cfg.auto_provider > 2) cfg.auto_provider = 0;
      if(cfg.auto_provider != 0 && cfg.auto_api_base_url == "") cfg.auto_provider = 0;

      // TF mask (keep bits 0..6 only => M1..D1)
      if(cfg.auto_tf_mask < 0) cfg.auto_tf_mask = 0;
      cfg.auto_tf_mask = (cfg.auto_tf_mask & 0x7F);

      // --- StructureSDOB / Supply-Demand knobs ---------------------------------
      if(cfg.struct_zz_depth <= 0) cfg.struct_zz_depth = 12;
      cfg.struct_zz_depth = MathMin(MathMax(cfg.struct_zz_depth, 5), 100);
      
      if(cfg.struct_htf_mult <= 0) cfg.struct_htf_mult = 3;
      cfg.struct_htf_mult = MathMin(MathMax(cfg.struct_htf_mult, 1), 12);
      
      if(cfg.ob_prox_max_pips <= 0.0) cfg.ob_prox_max_pips = 15.0;
      cfg.ob_prox_max_pips = MathMin(MathMax(cfg.ob_prox_max_pips, 0.0), 200.0);
      
      #ifdef CFG_HAS_STRUCT_ZONE_MARGIN_PIPS
        if(cfg.struct_zone_margin_pips < 0.0) cfg.struct_zone_margin_pips = 0.0;
        cfg.struct_zone_margin_pips = MathMin(MathMax(cfg.struct_zone_margin_pips, 0.0), 50.0);
      #endif
      
      #ifdef CFG_HAS_STRUCT_MIN_TOUCH_COUNT
        if(cfg.struct_min_touch_count < 0) cfg.struct_min_touch_count = 0;
        cfg.struct_min_touch_count = MathMin(MathMax(cfg.struct_min_touch_count, 0), 10);
      #endif
      
      #ifdef CFG_HAS_STRUCT_ZONE_MIN_SCORE
        if(cfg.struct_zone_min_score < 0.0) cfg.struct_zone_min_score = 0.0;
        cfg.struct_zone_min_score = MathMin(MathMax(cfg.struct_zone_min_score, 0.0), 1.0);
      #endif

      // Master min quality: fallback only (does not override explicit per-type mins)
      cfg.auto_min_quality = MathMin(MathMax(cfg.auto_min_quality, 0.0), 1.0);
      if(cfg.auto_min_quality > 0.0)
      {
         if(cfg.auto_chart_min_quality <= 0.0) cfg.auto_chart_min_quality = cfg.auto_min_quality;
         if(cfg.auto_fib_min_quality   <= 0.0) cfg.auto_fib_min_quality   = cfg.auto_min_quality;
      }
      
      // Autofib tolerance
      if(cfg.autofib_ratio_tolerance <= 0.0) cfg.autofib_ratio_tolerance = 0.05;
      cfg.autofib_ratio_tolerance = MathMin(MathMax(cfg.autofib_ratio_tolerance, 0.01), 0.15);
      
      // Dedicated harmonic pivots
      if(cfg.auto_fib_pivot_L < 1) cfg.auto_fib_pivot_L = cfg.auto_chart_pivot_L;
      if(cfg.auto_fib_pivot_R < 1) cfg.auto_fib_pivot_R = cfg.auto_chart_pivot_R;
      
      // Stops/targets
      if(cfg.auto_fib_stop_atr_mult <= 0.0) cfg.auto_fib_stop_atr_mult = 0.35;
      cfg.auto_fib_stop_atr_mult = MathMin(MathMax(cfg.auto_fib_stop_atr_mult, 0.05), 5.0);
      
      if(cfg.auto_fib_target_r1 <= 0.0) cfg.auto_fib_target_r1 = 0.382;
      if(cfg.auto_fib_target_r2 <= 0.0) cfg.auto_fib_target_r2 = 0.618;
      if(cfg.auto_fib_target_r3 <= 0.0) cfg.auto_fib_target_r3 = 1.000;

     #ifdef CFG_HAS_CF_WEIGHTS
      // Alias weight mirroring (avoid “two sources of truth” drift)
      cfg.auto_weight_chart = MathMin(MathMax(cfg.auto_weight_chart, 0.0), 2.0);
      cfg.auto_weight_fib   = MathMin(MathMax(cfg.auto_weight_fib,   0.0), 2.0);
      cfg.auto_weight_key   = MathMin(MathMax(cfg.auto_weight_key,   0.0), 2.0);
      cfg.auto_weight_vol   = MathMin(MathMax(cfg.auto_weight_vol,   0.0), 2.0);

      // Precedence rule:
      // - if alias > 0 => push into canonical
      // - else pull canonical into alias
      if(cfg.auto_weight_chart > 0.0) cfg.w_autochartist_chart = cfg.auto_weight_chart; else cfg.auto_weight_chart = cfg.w_autochartist_chart;
      if(cfg.auto_weight_fib   > 0.0) cfg.w_autochartist_fib   = cfg.auto_weight_fib;   else cfg.auto_weight_fib   = cfg.w_autochartist_fib;
      if(cfg.auto_weight_key   > 0.0) cfg.w_autochartist_keylevels  = cfg.auto_weight_key; else cfg.auto_weight_key = cfg.w_autochartist_keylevels;
      if(cfg.auto_weight_vol   > 0.0) cfg.w_autochartist_volatility = cfg.auto_weight_vol; else cfg.auto_weight_vol = cfg.w_autochartist_volatility;
     #endif

      // Chart pattern params
      cfg.auto_chart_min_quality = MathMin(MathMax(cfg.auto_chart_min_quality, 0.0), 1.0);
      
      if(cfg.auto_chart_pivot_L < 2)  cfg.auto_chart_pivot_L = 2;
      if(cfg.auto_chart_pivot_L > 10) cfg.auto_chart_pivot_L = 10;
      
      if(cfg.auto_chart_pivot_R < 2)  cfg.auto_chart_pivot_R = 2;
      if(cfg.auto_chart_pivot_R > 10) cfg.auto_chart_pivot_R = 10;
      
      #ifdef CFG_HAS_PATTERNS_SD_SETTINGS
        // SD base patterns clamps
        cfg.sd_atr_period = MathMin(MathMax(cfg.sd_atr_period, 5), 200);
      
        cfg.sd_base_min_bars = MathMin(MathMax(cfg.sd_base_min_bars, 1), 20);
      
        // ensure max >= min and keep bounded
        if(cfg.sd_base_max_bars < cfg.sd_base_min_bars)
          cfg.sd_base_max_bars = cfg.sd_base_min_bars;
        cfg.sd_base_max_bars = MathMin(MathMax(cfg.sd_base_max_bars, cfg.sd_base_min_bars), 50);
      
        cfg.sd_min_move_atr       = MathMin(MathMax(cfg.sd_min_move_atr,       0.10), 10.0);
        cfg.sd_max_base_range_atr = MathMin(MathMax(cfg.sd_max_base_range_atr, 0.05), 5.0);
      
        cfg.sd_break_min_pips = MathMin(MathMax(cfg.sd_break_min_pips, 0.0), 200.0);
        cfg.sd_break_atr_k    = MathMin(MathMax(cfg.sd_break_atr_k,    0.0), 2.0);
      
        // volume spike ratio is only meaningful >= 1.0
        if(cfg.sd_vol_spike_k < 1.0) cfg.sd_vol_spike_k = 1.0;
        cfg.sd_vol_spike_k = MathMin(cfg.sd_vol_spike_k, 10.0);
      #endif

      // Fib params
      cfg.auto_fib_min_quality = MathMin(MathMax(cfg.auto_fib_min_quality, 0.0), 1.0);
      
      // Key levels params
      cfg.auto_keylevel_min_touches  = MathMin(MathMax(cfg.auto_keylevel_min_touches,  3), 8);
      cfg.auto_keylevel_cluster_atr  = MathMin(MathMax(cfg.auto_keylevel_cluster_atr,  0.05), 0.80);
      cfg.auto_keylevel_approach_atr = MathMin(MathMax(cfg.auto_keylevel_approach_atr, 0.05), 0.80);
      
      cfg.auto_keylevel_min_pips         = MathMin(MathMax(cfg.auto_keylevel_min_pips,         1.0), 200.0);
      cfg.auto_keylevel_break_margin_atr = MathMin(MathMax(cfg.auto_keylevel_break_margin_atr, 0.02), 0.50);
      if(cfg.auto_keylevel_bounce_window < 3)  cfg.auto_keylevel_bounce_window = 3;
      if(cfg.auto_keylevel_bounce_window > 25) cfg.auto_keylevel_bounce_window = 25;

      cfg.auto_keylevel_w_touches = MathMin(MathMax(cfg.auto_keylevel_w_touches, 0.0), 2.0);
      cfg.auto_keylevel_w_recency = MathMin(MathMax(cfg.auto_keylevel_w_recency, 0.0), 2.0);
      cfg.auto_keylevel_w_bounce  = MathMin(MathMax(cfg.auto_keylevel_w_bounce,  0.0), 2.0);
      
      #ifdef CFG_HAS_AUTO_KEY_MIN_SIG
         cfg.auto_key_min_sig = MathMin(MathMax(cfg.auto_key_min_sig, 0.0), 1.0);
      #endif
      
      #ifdef CFG_HAS_SR_DETECTOR_SETTINGS
        // If unset (common after CSV into a zeroed struct), seed sane defaults
        if(cfg.sr_pivot_left  <= 0) cfg.sr_pivot_left  = 5;
        if(cfg.sr_pivot_right <= 0) cfg.sr_pivot_right = 5;

        // Pivot bounds
        if(cfg.sr_pivot_left  < 2)  cfg.sr_pivot_left  = 2;
        if(cfg.sr_pivot_left  > 20) cfg.sr_pivot_left  = 20;

        if(cfg.sr_pivot_right < 2)  cfg.sr_pivot_right = 2;
        if(cfg.sr_pivot_right > 20) cfg.sr_pivot_right = 20;

        // Expiry: 0 allowed (never expire)
        if(cfg.sr_level_expiry_bars < 0) cfg.sr_level_expiry_bars = 0;

        // Max levels: 0 allowed (disable emitting/keeping levels)
        if(cfg.sr_max_levels < 0)   cfg.sr_max_levels = 0;
        if(cfg.sr_max_levels > 200) cfg.sr_max_levels = 200;

        // Zone width in ATR
        if(cfg.sr_zone_width_atr <= 0.0) cfg.sr_zone_width_atr = 0.25;
        cfg.sr_zone_width_atr = MathMin(MathMax(cfg.sr_zone_width_atr, 0.05), 2.0);

        // Volume ratios
        if(cfg.sr_break_vol_ratio <= 0.0) cfg.sr_break_vol_ratio = 1.50;
        if(cfg.sr_touch_vol_ratio <= 0.0) cfg.sr_touch_vol_ratio = 1.20;

        cfg.sr_break_vol_ratio = MathMin(MathMax(cfg.sr_break_vol_ratio, 0.50), 5.0);
        cfg.sr_touch_vol_ratio = MathMin(MathMax(cfg.sr_touch_vol_ratio, 0.50), 5.0);

        // MTF mask: keep non-negative; 0 allowed
        if(cfg.sr_mtf_mask < 0) cfg.sr_mtf_mask = 0;
      #endif

      // Volatility params
      if(cfg.auto_vol_lookback_days < 30)  cfg.auto_vol_lookback_days = 30;
      if(cfg.auto_vol_lookback_days > 365) cfg.auto_vol_lookback_days = 365;
      
      if(cfg.auto_vol_horizon_minutes < 15)  cfg.auto_vol_horizon_minutes = 15;
      if(cfg.auto_vol_horizon_minutes > 240) cfg.auto_vol_horizon_minutes = 240;
      
      cfg.auto_vol_min_range_atr = MathMin(MathMax(cfg.auto_vol_min_range_atr, 0.25), 3.00);
      
      // PowerStats-like clamps
      cfg.auto_vol_sd_mult = MathMin(MathMax(cfg.auto_vol_sd_mult, 0.5), 3.0);

      cfg.auto_vol_sl_max_mult          = MathMin(MathMax(cfg.auto_vol_sl_max_mult,          0.5), 6.0);
      cfg.auto_vol_tp_cap_mult          = MathMin(MathMax(cfg.auto_vol_tp_cap_mult,          0.5), 6.0);
      cfg.auto_vol_tp_cap_breakout_mult = MathMin(MathMax(cfg.auto_vol_tp_cap_breakout_mult, 0.5), 6.0);

      // Fractional floor (not really a "multiplier"—keep it sane)
      cfg.auto_vol_sl_min_frac = MathMin(MathMax(cfg.auto_vol_sl_min_frac, 0.01), 1.0);

      // Normalized 0..1
      cfg.auto_vol_breakout_adx01 = MathMin(MathMax(cfg.auto_vol_breakout_adx01, 0.0), 1.0);

      // Ensure breakout cap is not accidentally tighter than non-breakout cap
      if(cfg.auto_vol_tp_cap_breakout_mult < cfg.auto_vol_tp_cap_mult)
        cfg.auto_vol_tp_cap_breakout_mult = cfg.auto_vol_tp_cap_mult;

      // Risk scaling params
      cfg.auto_risk_scale_floor = MathMin(MathMax(cfg.auto_risk_scale_floor, 0.10), 2.00);
      cfg.auto_risk_scale_cap   = MathMin(MathMax(cfg.auto_risk_scale_cap,   0.10), 3.00);
      
      if(cfg.auto_risk_scale_cap < cfg.auto_risk_scale_floor)
      {
        double t = cfg.auto_risk_scale_floor;
        cfg.auto_risk_scale_floor = cfg.auto_risk_scale_cap;
        cfg.auto_risk_scale_cap = t;
      }

    // (Toggles are bools—no clamp needed)
    #ifdef CFG_HAS_EXTRA_CONFL
      cfg.extra_min_needed = MathMax(0,   cfg.extra_min_needed);
      cfg.extra_min_score  = MathMin(MathMax(cfg.extra_min_score, 0.0), 1.0);
    #endif

    #ifdef CFG_HAS_W_SILVERBULLET_TZ
      if(cfg.w_silverbullet_tz < 0.0) cfg.w_silverbullet_tz = 0.0;
    #endif
    
    #ifdef CFG_HAS_W_AMD_H1
      if(cfg.w_amd_h1 < 0.0) cfg.w_amd_h1 = 0.0;
    #endif
    
    #ifdef CFG_HAS_W_AMD_H4
      if(cfg.w_amd_h4 < 0.0) cfg.w_amd_h4 = 0.0;
    #endif
    
    #ifdef CFG_HAS_W_PO3_H1
      if(cfg.w_po3_h1 < 0.0) cfg.w_po3_h1 = 0.0;
    #endif
    #ifdef CFG_HAS_W_PO3_H4
      if(cfg.w_po3_h4 < 0.0) cfg.w_po3_h4 = 0.0;
    #endif

    #ifdef CFG_HAS_W_WYCKOFF_TURN
      if(cfg.w_wyckoff_turn < 0.0) cfg.w_wyckoff_turn = 0.0;
    #endif

    #ifdef CFG_HAS_W_PHASE_CTX
      cfg.w_phase_ctx = MathMax(0.0, cfg.w_phase_ctx);
    #endif

    #ifdef CFG_HAS_W_MTF_ZONE_H1
      if(cfg.w_mtf_zone_h1 < 0.0) cfg.w_mtf_zone_h1 = 0.0;
    #endif
    #ifdef CFG_HAS_W_MTF_ZONE_H4
      if(cfg.w_mtf_zone_h4 < 0.0) cfg.w_mtf_zone_h4 = 0.0;
    #endif

    #ifdef CFG_HAS_MTF_ZONE_MAX_DIST_ATR
      if(cfg.mtf_zone_max_dist_atr <= 0.0) cfg.mtf_zone_max_dist_atr = 1.25;
      if(cfg.mtf_zone_max_dist_atr > 5.0)  cfg.mtf_zone_max_dist_atr = 5.0;
    #endif

    #ifdef CFG_HAS_ADX_PARAMS
      cfg.adx_period     = MathMax(1,   cfg.adx_period);
      cfg.adx_min_trend  = MathMax(0.0, cfg.adx_min_trend);
    #endif
   
    #ifdef CFG_HAS_ADX_UPPER
      if(cfg.adx_upper<=0.0) cfg.adx_upper = 35.0;
      if(cfg.adx_upper < cfg.adx_min_trend + 5.0)
         cfg.adx_upper = cfg.adx_min_trend + 5.0;
    #endif
   
    #ifdef CFG_HAS_CORR_MAX_PEN
      // default 0.25, clamp to [0..1]
      if(cfg.corr_max_pen<=0.0) cfg.corr_max_pen=0.25;
      if(cfg.corr_max_pen>1.0)  cfg.corr_max_pen=1.0;
    #endif
   
    #ifdef CFG_HAS_W_CORR_PEN
      cfg.w_corr_pen = MathMax(0.0, cfg.w_corr_pen);
    #endif

    #ifdef CFG_HAS_STOCHRSI_PARAMS
      // Preserve "0 = unset" behavior by seeding canonical defaults
      if(cfg.rsi_period<=0)     cfg.rsi_period     = 14;
      if(cfg.stoch_k<=0)        cfg.stoch_k        = 14;
      if(cfg.stoch_k_smooth<=0) cfg.stoch_k_smooth = 3;
      if(cfg.stoch_d<=0)        cfg.stoch_d        = 3;
   
      // Clamp to sane ranges
      cfg.rsi_period     = MathMax(2, MathMin(cfg.rsi_period, 200));
      cfg.stoch_k        = MathMax(1, MathMin(cfg.stoch_k, 200));
      cfg.stoch_k_smooth = MathMax(1, MathMin(cfg.stoch_k_smooth, 200));
      cfg.stoch_d        = MathMax(1, MathMin(cfg.stoch_d, 200));
   
      cfg.stoch_ob = MathMin(MathMax(cfg.stoch_ob, 0.0), 1.0);
      cfg.stoch_os = MathMin(MathMax(cfg.stoch_os, 0.0), 1.0);
    #endif

    #ifdef CFG_HAS_MACD_PARAMS
      cfg.macd_fast   = MathMax(1,              cfg.macd_fast);
      cfg.macd_slow   = MathMax(cfg.macd_fast+1,cfg.macd_slow);
      cfg.macd_signal = MathMax(1,              cfg.macd_signal);
    #endif

    #ifdef CFG_HAS_MACD_PRICE
      cfg.macd_price = (ENUM_APPLIED_PRICE)MathMax(0, MathMin(6, (int)cfg.macd_price));
    #endif
    
    // Confluence safety
    if(cfg.vwap_z_edge<0.0) cfg.vwap_z_edge=0.0;
    if(cfg.vwap_z_avoidtrend<0.0) cfg.vwap_z_avoidtrend=0.0;
    if(cfg.pattern_lookback<5) cfg.pattern_lookback=5;
    if(cfg.pattern_tau<0.05) cfg.pattern_tau=0.05;

    #ifdef CFG_HAS_PATT_SETTINGS_FIELDS
      // Universal Pattern clamps
      #ifdef CFG_HAS_PATT_MODE
        if(cfg.patt_mode < 0) cfg.patt_mode = 0;
        if(cfg.patt_mode > 1) cfg.patt_mode = 1;
      #endif

      #ifdef CFG_HAS_PATT_MIN_QUALITY01
        cfg.patt_min_quality01 = MathMin(1.0, MathMax(0.0, cfg.patt_min_quality01));
      #endif

      #ifdef CFG_HAS_PATT_RETEST_WINDOW_BARS
        if(cfg.patt_retest_window_bars < 3)  cfg.patt_retest_window_bars = 3;
        if(cfg.patt_retest_window_bars > 50) cfg.patt_retest_window_bars = 50;
      #endif

      #ifdef CFG_HAS_PATT_STOP_ATR_MULT
        cfg.patt_stop_atr_mult = MathMin(5.0, MathMax(0.5, cfg.patt_stop_atr_mult));
      #endif

      #ifdef CFG_HAS_PATT_TARGET_HEIGHT_MULT
        cfg.patt_target_height_mult = MathMin(5.0, MathMax(0.25, cfg.patt_target_height_mult));
      #endif
    #endif
    
    // Aliases for backward compatibility
    cfg.patt_lookback=cfg.pattern_lookback;
    cfg.patt_tau     =cfg.pattern_tau;
    cfg.vwap_z_avoid =cfg.vwap_z_avoidtrend;

    // VWAP engine
    if(cfg.vwap_lookback<10) cfg.vwap_lookback=60;
    if(cfg.vwap_sigma<0.1)   cfg.vwap_sigma=2.0;

    // Feature toggle bounds
    if(cfg.vsa_penalty_max<0.0)  cfg.vsa_penalty_max=0.0;
    if(cfg.vsa_penalty_max>0.80) cfg.vsa_penalty_max=0.80;
    if(cfg.vsa_lookback < 10)  cfg.vsa_lookback = 60;   // default lookback
    if(cfg.vsa_lookback > 500) cfg.vsa_lookback = 500;  // safety ceiling

    // Carry knobs (compile-safe)
    #ifdef CFG_HAS_CARRY_ENABLE
      // keep as-is (bool)
    #endif
    #ifdef CFG_HAS_CARRY_BOOST_MAX
      if(cfg.carry_boost_max<0.0) cfg.carry_boost_max=0.0;
      if(cfg.carry_boost_max>0.20) cfg.carry_boost_max=0.20;   // safety ceiling
    #endif
    #ifdef CFG_HAS_CARRY_RISK_SPAN
      if(cfg.carry_risk_span<0.0) cfg.carry_risk_span=0.0;
      if(cfg.carry_risk_span>0.50) cfg.carry_risk_span=0.50;   // mild
    #endif

    // Confluence blend clamps
    #ifdef CFG_HAS_CONFL_BLEND_TREND
      if(cfg.confl_blend_trend<0.0) cfg.confl_blend_trend=0.0;
      if(cfg.confl_blend_trend>0.50) cfg.confl_blend_trend=0.50;
    #endif
    #ifdef CFG_HAS_CONFL_BLEND_MR
      if(cfg.confl_blend_mr<0.0) cfg.confl_blend_mr=0.0;
      if(cfg.confl_blend_mr>0.50) cfg.confl_blend_mr=0.50;
    #endif
    #ifdef CFG_HAS_CONFL_BLEND_OTHERS
      if(cfg.confl_blend_others<0.0) cfg.confl_blend_others=0.0;
      if(cfg.confl_blend_others>0.50) cfg.confl_blend_others=0.50;
    #endif

    // Router hint defaults (compile-safe)
    #ifdef CFG_HAS_ROUTER_MIN_SCORE
      //if(cfg.router_min_score<=0.0) cfg.router_min_score = 0.55;
      if(cfg.router_min_score < 0.0) cfg.router_min_score = 0.0;
      if(cfg.router_min_score > 1.0) cfg.router_min_score = 1.0;
    #endif
    #ifdef CFG_HAS_ROUTER_MAX_STRATS
      if(cfg.router_max_strats<=0)  cfg.router_max_strats = 12;
    #endif
    #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
      if(cfg.max_positions_per_symbol < 0) cfg.max_positions_per_symbol = 0;
    #endif
    #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
      if(cfg.max_positions_total < 0) cfg.max_positions_total = 0;
    #endif
    #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
      if(cfg.router_eval_all_mode < 0) cfg.router_eval_all_mode = 0;
      if(cfg.router_eval_all_mode > 1) cfg.router_eval_all_mode = 1;
    #endif
   
    #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
       if(cfg.router_fallback_min_score < 0.0) cfg.router_fallback_min_score = 0.0;
       if(cfg.router_fallback_min_score > 1.0) cfg.router_fallback_min_score = 1.0;
    #endif
   
    #ifdef CFG_HAS_ROUTER_FB_MIN
       if(cfg.router_fb_min < 0.0) cfg.router_fb_min = 0.0;
       if(cfg.router_fb_min > 1.0) cfg.router_fb_min = 1.0;
    #endif
    #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
      if(cfg.router_pool_blend_w < 0.0) cfg.router_pool_blend_w = 0.0;
      if(cfg.router_pool_blend_w > 1.0) cfg.router_pool_blend_w = 1.0;
    #endif
   
    #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
      int pu = 0;
      if(KV::GetInt("router.pool_use", pu))
        cfg.router_use_confl_pool = (pu != 0);
    #endif
      
    #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
      double pw = 0.0;
      if(KV::GetDouble("router.pool_blend_w", pw))
      {
        if(pw < 0.0) pw = 0.0;
        if(pw > 1.0) pw = 1.0;
        cfg.router_pool_blend_w = pw;
      }
    #endif
    #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
      // If pool use is OFF, force blend weight to 0 to avoid hidden effects
      #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
        if(!cfg.router_use_confl_pool && cfg.router_pool_blend_w > 0.0)
          cfg.router_pool_blend_w = 0.0;
      #endif
    #endif

    // Keep router fallback threshold and legacy alias in sync
    _SyncRouterFallbackAlias(cfg);
    // Strategy toggles & ICT-specific thresholds
    NormalizeStrategyToggles(cfg);
    NormalizeICTQualityThresholds(cfg);
    SyncLegacyICTToggles(cfg);
   
    // IMPORTANT: enforce strat_mode AFTER defaults + legacy sync,
    // so MAIN_ONLY/PACK_ONLY can't be undone by NormalizeStrategyToggles().
    EnforceStrategyModeToggles(cfg);
   
    Postwire_StrategyVetoDefaults(cfg);
  }
  //──────────────────────────────────────────────────────────────────
  // Validation (auto-fix warn; engine clamps at runtime where needed)
  //──────────────────────────────────────────────────────────────────
  inline bool LoadInputs(Settings &cfg, const double monthly_target_pct)
   {
     #ifdef CFG_HAS_MONTHLY_TARGET
       // Store raw in PERCENT units; CfgMonthlyTargetPct will convert to fraction.
       cfg.monthly_target_pct = monthly_target_pct;
     #endif
     return true;
   }

  // Apply lightweight runtime overrides (e.g., from KV/GVs). Call ONCE in OnInit,
  // or periodically if you want dynamic behavior.
  inline void ApplyKVOverrides(Settings &cfg)
  {
    string warns = "";
    #ifdef CFG_HAS_ROUTER_MIN_SCORE
      double v=0.0;
      if(KV::GetDouble("router.min_score", v))
       cfg.router_min_score = MathMin(MathMax(v, 0.0), 1.0);
    #endif
    #ifdef CFG_HAS_ROUTER_MAX_STRATS
      int k=0;
      if(KV::GetInt("router.max_strats", k))
      {
        if(k > 0) cfg.router_max_strats = k;
      }
    #endif
    #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
      int b = 0;
      if(KV::GetInt("router.pool_use", b))
        cfg.router_use_confl_pool = (b != 0);
    #endif
   
    #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
      double w = 0.0;
      if(KV::GetDouble("router.pool_blend_w", w))
      {
        if(w < 0.0) w = 0.0;
        if(w > 1.0) w = 1.0;
        cfg.router_pool_blend_w = w;
      }
    #endif
   
    #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
      #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
        if(!cfg.router_use_confl_pool && cfg.router_pool_blend_w > 0.0)
          cfg.router_pool_blend_w = 0.0;
      #endif
    #endif

    #ifdef CFG_HAS_STRAT_MODE
      const StrategyMode sm = CfgStrategyMode(cfg);
      if(sm == STRAT_PACK_ONLY || sm == STRAT_COMBINED)
      {
        #ifdef CFG_HAS_ENABLE_PACK_STRATS
          if(!cfg.enable_pack_strats)
            warns += "PACK_ONLY/COMBINED selected but enable_pack_strats=false; pack strategies will not be registered/traded.\\n";
        #endif
        #ifdef CFG_HAS_DISABLE_PACKS
          if(cfg.disable_packs)
            warns += "disable_packs=true; pack strategies are globally disabled (PACK_ONLY/COMBINED may produce no trades).\\n";
        #endif
      }
    #endif
  
    #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
      // router.fb_min should feed both aliases if present
       {
         double fb = 0.0;
         if(KV::GetDouble("router.fb_min", fb))
         {
           fb = MathMin(MathMax(fb, 0.0), 1.0);
           #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
             cfg.router_fallback_min_score = fb;
           #endif
           #ifdef CFG_HAS_ROUTER_FB_MIN
             cfg.router_fb_min = fb;
           #endif
         }
       }
    #ifdef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
      if(cfg.sb_require_vwap_stretch && cfg.vwap_lookback < 20)
        warns += "sb_require_vwap_stretch ON but vwap_lookback<20; SB may rarely qualify.\n";
    #endif
    #endif
    #ifdef CFG_HAS_ENABLE_HARD_GATE
      int h=0; if(KV::GetInt("router.hard_gate", h)) cfg.enable_hard_gate = (h!=0);
    #endif
    #ifdef CFG_HAS_MIN_FEATURES_MET
      int m=0; if(KV::GetInt("confl.min_features", m)) cfg.min_features_met = m;
    #endif
    #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
      int wr = 0;
      if(KV::GetInt("pol.weekly_open_ramp", wr))
        cfg.weekly_open_spread_ramp = (wr != 0);
    #endif
    #ifdef CFG_HAS_MONTHLY_TARGET
      double mt = 0.0;
      if(KV::GetDouble("risk.monthly_target_pct", mt))
      {
        cfg.monthly_target_pct = mt; // Store raw; accessor will clamp/default.
      }
    #endif
    if(StringLen(warns) > 0)
      Print("[Config] KV override warnings:\n", warns);
    // KV can override only one side; keep aliases coherent
    _SyncRouterFallbackAlias(cfg);
  }
  
  // -- Normalize/alias inputs for telemetry without mutating effective floors ----
   inline void FinalizeThresholds(Settings &io)
   {
     // Keep the user-visible alias in sync for KV/insights if only one side was set.
     #ifdef CFG_HAS_ROUTER_FB_MIN
       const double primary = io.router_min_score;
       const double fb      = io.router_fb_min;
   
       // Reflect whichever one the user set so both show consistently in KV output.
       if ((primary > 0.0 && fb <= 0.0) || (fb > 0.0 && primary <= 0.0))
         {
           _SyncRouterFallbackAlias(io);   // or just _SyncRouterFallbackAlias(io) if already in scope
         }
     #endif
   
     // DO NOT modify io.router_min_score here.
     // The effective runtime floor is computed by RouterMinScore(cfg), purely.
   }
  
  inline bool Validate(const Settings &cfg, string &warns)
  {
     warns="";
     bool ok=true;

     #ifdef CFG_HAS_STRAT_MODE
      const StrategyMode sm = CfgStrategyMode(cfg);
      if(sm == STRAT_PACK_ONLY || sm == STRAT_COMBINED)
      {
        #ifdef CFG_HAS_ENABLE_PACK_STRATS
          if(!cfg.enable_pack_strats)
            warns += "PACK_ONLY/COMBINED selected but enable_pack_strats=false; pack strategies will not be registered/traded.\\n";
        #endif
        #ifdef CFG_HAS_DISABLE_PACKS
          if(cfg.disable_packs)
            warns += "disable_packs=true; pack strategies are globally disabled (PACK_ONLY/COMBINED may produce no trades).\\n";
        #endif
      }
      
      if(sm == STRAT_MAIN_ONLY)
      {
        const bool poolWanted = CfgMainOnly_AllowPackConfluencePool(cfg);

        #ifdef CFG_HAS_ENABLE_PACK_STRATS
          if(poolWanted && !cfg.enable_pack_strats)
            warns += "MAIN_ONLY with router confluence pool enabled but enable_pack_strats=false; confluence-only pool from disallowed strategies will be empty.\\n";
        #endif

        #ifdef CFG_HAS_DISABLE_PACKS
          if(poolWanted && cfg.disable_packs)
            warns += "MAIN_ONLY with router confluence pool enabled but disable_packs=true; pack confluence pool is hard-disabled.\\n";
        #endif
      }
    #endif
    
    #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
      if(cfg.max_positions_per_symbol < 1)
        warns += "max_positions_per_symbol < 1; Normalize() will clamp to 1.\n";
    #endif
    #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
      if(cfg.max_positions_total < 0)
        warns += "max_positions_total < 0; Normalize() will clamp to 0 (unlimited).\n";
    #endif
    #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
      if(cfg.router_eval_all_mode < 0 || cfg.router_eval_all_mode > 1)
        warns += "router_eval_all_mode out of range; Normalize() will clamp to 0..1.\n";
    #endif
    #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
      if(cfg.router_eval_all_mode == 1)
      {
        #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
          if(cfg.max_positions_total == 0)
            warns += "router_eval_all_mode=1 (per-symbol) with max_positions_total=0 (unlimited). Consider setting caps to avoid runaway entries.\n";
        #endif
      }
    #endif

    // Risk sanity
    if(cfg.risk_pct > cfg.risk_cap_pct && cfg.risk_cap_pct>0.0)
      warns += "risk_pct>risk_cap_pct; capped by engine.\n";

    if(cfg.max_sl_ceiling_pips>0.0 && cfg.min_sl_pips>cfg.max_sl_ceiling_pips)
      warns += "min_sl_pips>max_sl_ceiling_pips; engine will lift ceiling.\n";

    // News/Calendar
    if(cfg.news_on && (cfg.block_pre_m==0 && cfg.block_post_m==0))
      warns += "news_on but pre/post blocks are zero.\n";

    if(cfg.cal_hard_skip>0.0 && cfg.cal_min_scale<=0.0)
      warns += "cal_hard_skip set but cal_min_scale==0; risk may scale to 0.\n";

    // VWAP
    if(cfg.vwap_lookback<20) warns += "vwap_lookback<20; z-score stability may be poor.\n";

    // Partials
    if(cfg.partial_enable)
    {
      if(cfg.p1_at_R<=0.0 && cfg.p2_at_R<=0.0) warns+="partials enabled but R triggers are <=0.\n";
      if(cfg.p1_close_pct+cfg.p2_close_pct>100.5) warns+="partials close % sum > 100%; engine will clamp.\n";
    }

    #ifdef CFG_HAS_FIB_SETTINGS
      if(cfg.fibOTE_Low >= cfg.fibOTE_High)
        warns += "fibOTE_Low >= fibOTE_High; Normalize() will reset to 0.618/0.786.\n";
      if(cfg.fibApproachATRMult < 0.05)
        warns += "fibApproachATRMult < 0.05; near-level detection may rarely trigger.\n";
      if(cfg.fibMinLegBars > 150)
        warns += "fibMinLegBars very high; impulse legs may never qualify.\n";
    #endif

    // Veto knobs sanity
    #ifdef CFG_HAS_LIQUIDITY_LIMIT
      if(cfg.liquidity_veto_on && cfg.liquidity_spr_atr_max<0.10)
        warns+="liquidity_spr_atr_max < 0.10; may veto almost always.\n";
    #endif
    #ifdef CFG_HAS_REGIME_TQMIN
      if(cfg.corr_veto_on && cfg.regime_tq_min>0.60)
        warns+="regime_tq_min > 0.60; squeeze/trend may rarely qualify.\n";
    #endif
    
    // SDOB sanity (warnings only)
    if(cfg.struct_zz_depth < 5)
      warns += "struct_zz_depth < 5; SDOB zones may be noisy.\n";
   
    if(cfg.ob_prox_max_pips < 2.0)
      warns += "ob_prox_max_pips < 2; SDOB approach/touch detection may be too tight.\n";
   
    #ifdef CFG_HAS_PATTERNS_SD_SETTINGS
      // SD base patterns sanity (warnings only)
      if(cfg.sd_base_min_bars < 2)
        warns += "sd_base_min_bars < 2; SD base detection may be noisy/overfit.\n";
      
      if(cfg.sd_max_base_range_atr < 0.10)
        warns += "sd_max_base_range_atr < 0.10; bases may rarely qualify.\n";
      
      if(cfg.sd_min_move_atr > 3.0)
        warns += "sd_min_move_atr > 3.0; prior-move gate may rarely qualify.\n";
      
      if(cfg.sd_use_volume_filter && cfg.sd_vol_spike_k <= 1.0)
        warns += "sd_use_volume_filter=true but sd_vol_spike_k<=1; filter is effectively off.\n";
    #endif

    #ifdef CFG_HAS_STRUCT_ZONE_MIN_SCORE
      if(cfg.struct_zone_min_score > 0.0 && cfg.struct_zone_min_score < 0.10)
        warns += "struct_zone_min_score is very low; filter may be ineffective.\n";
    #endif

    #ifdef CFG_HAS_ORDERFLOW_TH
      if(cfg.orderflow_th < 0.10) warns += "orderflow_th < 0.10; likely too permissive or unstable.\n";
    #endif
  
    // DOM sanity warnings (won't block; just tells you why it may be ineffective)
    #ifdef CFG_HAS_EXTRA_DOM_IMBALANCE
      if(cfg.extra_dom_imbalance)
      {
        #ifdef CFG_HAS_W_DOM_IMBALANCE
          if(cfg.w_dom_imbalance <= 0.0)
            warns += "DOM enabled but w_dom_imbalance<=0 (DOM contributes no score).\\n";
        #endif
        #ifdef CFG_HAS_DOM_MIN_ABS_IMB
          if(cfg.dom_min_abs_imb <= 0.0 || cfg.dom_min_abs_imb > 1.0)
            warns += "DOM dom_min_abs_imb out of range; Normalize() will clamp.\\n";
        #endif
      }
    #endif

    // Trendlines sanity
    #ifdef CFG_HAS_EXTRA_TRENDLINES
      if(cfg.extra_trendlines)
      {
        #ifdef CFG_HAS_W_TRENDLINES
          if(cfg.w_trendlines <= 0.0)
            warns += "- Trendlines enabled but w_trendlines<=0 (no effect)\n";
        #endif
      }
    #endif

    // Phase context sanity
    #ifdef CFG_HAS_EXTRA_PHASE_CTX
      if(cfg.extra_phase_ctx)
      {
        #ifdef CFG_HAS_W_PHASE_CTX
          if(cfg.w_phase_ctx <= 0.0)
            warns += "- PhaseCtx enabled but w_phase_ctx<=0 (no effect)\n";
        #endif
      }
    #endif

    // Correlation warnings (helps catch 'enabled but empty basket' cases)
    #ifdef CFG_HAS_EXTRA_CORR
      if(cfg.extra_correlation && StringLen(cfg.corr_ref_symbol)==0)
        warns += "Correlation enabled but corr_ref_symbol empty (strategy should auto-basket, otherwise correlation may be neutral).\\n";
    #endif

    // If news_on is set but NEWSFILTER_AVAILABLE == 0, warn that blocks are ignored.
    if(cfg.news_on && (NEWSFILTER_AVAILABLE==0))
      warns += "news_on set but NEWSFILTER_AVAILABLE==0; news blocks will be ignored.\n";

    #ifdef CFG_HAS_ENABLE_HARD_GATE
      #ifdef CFG_HAS_MIN_FEATURES_MET
        if(cfg.enable_hard_gate && cfg.min_features_met==0)
          warns += "enable_hard_gate ON but min_features_met==0; gate will act like OFF.\n";
      #endif
    #endif
    
    #ifdef CFG_HAS_MONTHLY_TARGET
      const double mt = CfgMonthlyTargetPct(cfg);
      if(mt > 0.50)
        warns += "monthly target > 50%; monthly gate may never trigger in realistic conditions.\n";
    #endif

    // Sessions
    if(cfg.session_filter)
    {
      if(cfg.london_open_utc==cfg.london_close_utc && cfg.ny_open_utc==cfg.ny_close_utc)
        warns+="session_filter ON but both windows are zero-width.\n";
    }

    // Slippage/spread sanity
    if(cfg.max_spread_points > 0 && cfg.slippage_points > 0)
    {
      if(cfg.slippage_points < cfg.max_spread_points / 2)
        warns += "slippage_points very tight vs max_spread_points; broker may reject in fast moves (rc=0).\n";
      if(cfg.slippage_points < 100)
        warns += "slippage_points < 100; consider 300–500 for prop FX (first attempt), then taper.\n";
    }

    // Carry
    #ifdef CFG_HAS_CARRY_BOOST_MAX
      if(cfg.carry_boost_max>0.12)
        warns+="carry_boost_max > 0.12; consider 0.06–0.08.\n";
    #endif
    #ifdef CFG_HAS_CARRY_RISK_SPAN
      if(cfg.carry_risk_span>0.40)
        warns+="carry_risk_span > 0.40; consider ≤0.30 for mild behavior.\n";
    #endif

    return ok;
  }

   //──────────────────────────────────────────────────────────────────
   // Builder (signature)
   //──────────────────────────────────────────────────────────────────
   #ifndef CONFIG_BUILDSETTINGSEX_DECL
   #define CONFIG_BUILDSETTINGSEX_DECL
   bool BuildSettingsEx(
     Settings &cfg,
   
     // ── Existing “base” params (unchanged order) ──
     const string asset_csv, const ENUM_TIMEFRAMES tf_entry, const ENUM_TIMEFRAMES tf_h1,
     const ENUM_TIMEFRAMES tf_h4, const ENUM_TIMEFRAMES tf_d1,
     const double risk_pct, const double risk_cap_pct, const double min_sl_pips,
     const double min_tp_pips, const double max_sl_ceiling_pips,
     const double max_dd_day_pct, const int max_losses_day, const int max_trades_day, const int max_spread_points,
     const bool only_new_bar, const int timer_ms, const int server_offset_min,
     const bool session_filter, const int lon_open, const int lon_close, const int ny_open, const int ny_close,
     const bool news_on, const int block_pre, const int block_post, const int impact_mask,
     const bool debug, const bool filelog, const bool profile,
     const int atr_period, const double tp_quantile, const double tp_minr_floor, const double atr_sl_mult,
     const int slippage_points,
     const bool be_enable, const double be_at_R, const double be_lock_pips,
     const TrailType trail_type, const double trail_pips, const double trail_atr_mult,
     const bool partial_enable, const double p1_at_R, const double p1_close_pct, const double p2_at_R, const double p2_close_pct,
     const int cal_lookback_mins, const double cal_hard_skip, const double cal_soft_knee, const double cal_min_scale,
     const double vwap_z_edge, const double vwap_z_avoidtrend, const int pattern_lookback, const double pattern_tau,
     const int vwap_lookback, const double vwap_sigma,
     const bool vsa_enable, const double vsa_penalty_max, const bool structure_enable, const bool liquidity_enable, const bool corr_softveto_enable,
   
     // ── New: all extras carried in one struct ──
     const BuildExtras &extra
   )
   {
     // ===== Existing block (unchanged) =====
     // Assets/TF
     ParseAssets(asset_csv, cfg.asset_list);
     cfg.tf_entry = tf_entry;
     cfg.tf_h1   = tf_h1;
     cfg.tf_h4   = tf_h4;
     cfg.tf_d1   = tf_d1;
     // HTF reference slot: default to D1 unless you choose otherwise upstream
     cfg.tf_htf  = tf_d1;
   
     // Mode seed (guard)
     #ifdef CFG_HAS_STRAT_MODE
       _SetStratModeRef(cfg.strat_mode, (int)STRAT_MAIN_ONLY);
     #endif
     #ifdef CFG_HAS_MODE
       cfg.mode=BSM_BOTH;
     #endif
     // Pack strategies default OFF unless explicitly enabled by EA inputs / profile / CSV
     #ifdef CFG_HAS_ENABLE_PACK_STRATS
       cfg.enable_pack_strats = false;
     #endif
     #ifdef CFG_HAS_DISABLE_PACKS
       cfg.disable_packs = false;
     #endif
   
     // Baseline new fields (ABI-safe defaults)
     cfg.trade_selector = TRADE_BOTH_AUTO;
     cfg.trade_direction_selector = TradeSelectorToDirection(cfg.trade_selector);
     cfg.session_preset  = SESS_OFF;
     cfg.tokyo_close_utc = 6*60;   // 06:00 UTC
     cfg.sydney_open_utc = 21*60;  // 21:00 UTC
     // If you have an enum profile, prefer a guard in Types.mqh; otherwise this is fine as bool.
     #ifdef CFG_HAS_PROFILE_ENUM
        cfg.profile = (int)PROF_DEFAULT;
     #else
        cfg.profile = profile;
     #endif
     
     // Directional bias:
     // default = manual so older behavior (trade_selector) remains unchanged
     cfg.direction_bias_mode = (int)DIRM_MANUAL_SELECTOR;
     
     #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
       cfg.router_fallback_min_score = 0.0;
     #endif
     #ifdef CFG_HAS_ROUTER_FB_MIN
       cfg.router_fb_min = 0.0;
     #endif
     #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
      cfg.router_eval_all_mode = 0; // default: current behavior (best-of-all-symbols)
     #endif
     // Router profile hint fields: start clean (extras may override)
     #ifdef CFG_HAS_ROUTER_HINTS
       cfg.router_profile_alias          = "";
       cfg.router_fallback_min_confluence= 0.0;
       cfg.router_fallback_max_span      = 0;
     #endif

     // ICT strategy kind profile: default "core" until a given strategy
     // (Silver Bullet / PO3 / Continuation / Wyckoff Turn) overrides it.
     #ifdef CFG_HAS_STRATEGY_KIND
       cfg.strategyKind = ICT_STRAT_CORE;
     #endif
     
      // WyckoffCycle defaults (keep close to previously hardcoded behavior)
      #ifdef CFG_HAS_WYCK_CYCLE_SETTINGS
        cfg.wyck_range_lookback      = 150;
        cfg.wyck_min_range_bars      = 20;

        cfg.wyck_eq_tol_atr          = 0.25;
        cfg.wyck_max_range_atr       = 2.5;

        cfg.wyck_use_atr_compression = true;
        cfg.wyck_atr_len             = 14;
        cfg.wyck_atr_ma_len          = 50;

        cfg.wyck_use_bb_compression  = true;
        cfg.wyck_bb_len              = 20;
        cfg.wyck_bb_dev              = 2.0;
        cfg.wyck_bb_width_thr        = 0.015;

        cfg.wyck_swingL              = 5;
        cfg.wyck_swingR              = 5;

        cfg.wyck_bos_confirm_closes  = 1;

        cfg.wyck_manip_min_quality   = 0.55;
        cfg.wyck_wick_min_ratio      = 0.60;
        cfg.wyck_close_inside_min    = 0.20;

        cfg.wyck_ar_window_bars      = 60;
        cfg.wyck_vol_len             = 20;
        cfg.wyck_vol_mult            = 1.5;
      #endif

     // Silver Bullet hard requirements: default OFF unless extras enable them
     #ifdef CFG_HAS_SB_REQUIRE_OTE
       cfg.sb_require_ote = false;
     #endif
     #ifdef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
       cfg.sb_require_vwap_stretch = false;
     #endif
   
     // Risk (percent)
     cfg.risk_pct            = risk_pct;
     cfg.risk_cap_pct        = risk_cap_pct;
     #ifdef CFG_HAS_RISK_MULT_MAX
       cfg.risk_mult_max = 1.0;
     #endif
     
     cfg.min_sl_pips         = min_sl_pips;
     cfg.min_tp_pips         = min_tp_pips;
     cfg.max_sl_ceiling_pips = max_sl_ceiling_pips;
     cfg.max_daily_dd_pct    = max_dd_day_pct;
     
     #ifdef CFG_HAS_ADAPTIVE_DD_ENABLE
       cfg.adaptive_dd_enable = false;
     #endif
     #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
       cfg.adaptive_dd_window_days = 30;
     #endif
     #ifdef CFG_HAS_ADAPTIVE_DD_PCT
       cfg.adaptive_dd_pct = cfg.max_daily_dd_pct;
     #endif

     #ifdef CFG_HAS_BIGLOSS_RESET_ENABLE
       cfg.bigloss_reset_enable = true;
     #endif
     #ifdef CFG_HAS_BIGLOSS_RESET_R
       cfg.bigloss_reset_r = 2.0;
     #endif
     #ifdef CFG_HAS_BIGLOSS_RESET_MINS
       cfg.bigloss_reset_mins = 60;
     #endif
   
     // Legacy alias: keep risk_per_trade in sync with risk_pct
     cfg.risk_per_trade      = risk_pct;

     #ifdef CFG_HAS_MONTHLY_TARGET
        // Store raw target in PERCENT units, using compile-time default.
        cfg.monthly_target_pct    = CFG_MONTHLY_TARGET_PCT; // e.g. 10.0
      
        // Runtime state is always reset at EA init; Policies will re-capture on month boundary.
        cfg.monthly_baseline_equity = 0.0;
        cfg.monthly_peak_equity     = 0.0;
        cfg.monthly_target_hit      = false;
     #endif

     cfg.max_losses_day      = max_losses_day;
     cfg.max_trades_day      = max_trades_day;
     cfg.max_spread_points   = max_spread_points;
     #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
        cfg.max_positions_per_symbol = 1; // safe default (preserves old "one entry per symbol" expectations)
     #endif
     #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
        cfg.max_positions_total = 0; // 0 = unlimited (use with care; Router/PositionMgmt should still gate)
     #endif
     cfg.slippage_points     = slippage_points;
     // Guard against dangerously small slippage coming from EA inputs
     if(cfg.slippage_points <= 0)
       cfg.slippage_points = 300;   // default
     else if(cfg.slippage_points < 100)
       cfg.slippage_points = 100;
   
     // Loop/timing
     cfg.only_new_bar      = only_new_bar;
     cfg.timer_ms          = timer_ms;
     cfg.server_offset_min = server_offset_min;
   
     // Sessions (legacy minutes)
     cfg.session_filter   = session_filter;
     cfg.london_open_utc  = lon_open;
     cfg.london_close_utc = lon_close;
     cfg.ny_open_utc      = ny_open;
     cfg.ny_close_utc     = ny_close;
   
     // News
     cfg.news_on          = news_on;
     cfg.block_pre_m      = block_pre;
     cfg.block_post_m     = block_post;
     cfg.news_impact_mask = impact_mask;
     
     // Diagnostics
     cfg.debug   = debug;
     cfg.filelog = filelog;
   
     // Convenience alias for the NewsFilter module (if compiled)
     cfg.newsFilterEnabled = (news_on && (NEWSFILTER_AVAILABLE != 0));
   
     // ATR/TP/SL
     cfg.atr_period    = atr_period;
     cfg.tp_quantile   = tp_quantile;
     cfg.tp_minr_floor = tp_minr_floor;
     cfg.atr_sl_mult   = atr_sl_mult;
     
     // Liquidity Pools (Lux-style)
      #ifdef CFG_HAS_LIQPOOL_FIELDS
           // Liquidity Pools (Lux-style)
           cfg.liqPoolMinTouches          = 2;
           cfg.liqPoolGapBars             = 5;
           cfg.liqPoolConfirmWaitBars     = 10;
           cfg.liqPoolLevelEpsATR         = 0.10;
           cfg.liqPoolMaxLookbackBars     = 200;
           cfg.liqPoolMinSweepATR         = 0.25;
      #endif
     // Fibonacci / OTE defaults (can be overridden by EA inputs / profiles)
     cfg.fibDepth              = 5;
     cfg.fibATRPeriod          = 14;
     cfg.fibDevATRMult         = 3.0;
     cfg.fibMaxBarsBack        = 500;
     
     #ifdef CFG_HAS_FIB_SETTINGS
       cfg.fibUseLogScale          = false;
       cfg.fibOTE_Low              = 0.618;
       cfg.fibOTE_High             = 0.786;
   
       // Use ';' separator to keep CanonicalCSV parseable (',' is reserved for KV separation)
       cfg.fibRetraceRatiosCSV     = "0;0.236;0.382;0.5;0.618;0.786;0.886;1";
       cfg.fibExtensionRatiosCSV = "1;1.272;1.618;2;2.24;2.618;3.618;4.236";
   
       cfg.fibExpansionEnable      = false;  // safe default unless you explicitly wire/use ABC
       cfg.fibMinLegHeightATR      = 0.50;   // range-defense (impulse must be meaningful)
       cfg.fibMinLegBars           = 8;
       cfg.fibApproachATRMult      = 0.25;   // approach threshold
     #endif

     cfg.fibUseConfluence      = true;
     cfg.fibMinConfluenceScore = 0.35;   // mid of 0.30–0.40
     cfg.fibOTEToleranceATR    = 0.25;   // 0.25x ATR from band
     cfg.fibOTEQualityBonusReversal = 0.10;
     cfg.minRRFibAllowed       = 1.5;    // e.g. require at least 1.5R to TP1
     cfg.fibRRHardReject       = true;   // default: hard gate
   
     // Position mgmt
     #ifdef CFG_HAS_PM_MODE
        cfg.pm_mode = 0; // preserve current behavior; EA/CSV can override
     #endif
     #ifdef CFG_HAS_PM_ALLOW_DAILY_FLATTEN
        cfg.pm_allow_daily_flatten = false;
     #endif
     #ifdef CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS
        cfg.pm_post_dd_cooldown_seconds = 0;
     #endif

     cfg.be_enable      = be_enable;
     cfg.be_at_R        = be_at_R;
     cfg.be_lock_pips   = be_lock_pips;
     cfg.trail_type     = (TrailType)trail_type;
     cfg.trail_pips     = trail_pips;
     cfg.trail_atr_mult = trail_atr_mult;
     
     #ifdef CFG_HAS_TRAIL_AUTO_ADX_TF
       cfg.trail_auto_adx_tf = PERIOD_H1;
     #endif
     #ifdef CFG_HAS_TRAIL_AUTO_ADX_PERIOD
       cfg.trail_auto_adx_period = 14;
     #endif
     #ifdef CFG_HAS_TRAIL_AUTO_ADX_MIN
       cfg.trail_auto_adx_min = 25.0;
     #endif
     
     cfg.partial_enable = partial_enable;
     cfg.p1_at_R        = p1_at_R;
     cfg.p1_close_pct   = p1_close_pct;
     cfg.p2_at_R        = p2_at_R;
     cfg.p2_close_pct   = p2_close_pct;
   
     // Calendar
     cfg.cal_lookback_mins = cal_lookback_mins;
     cfg.cal_hard_skip     = cal_hard_skip;
     cfg.cal_soft_knee     = cal_soft_knee;
     cfg.cal_min_scale     = cal_min_scale;
   
     // Confluence/VWAP
     cfg.vwap_z_edge       = vwap_z_edge;
     cfg.vwap_z_avoidtrend = vwap_z_avoidtrend;
     cfg.pattern_lookback  = pattern_lookback;
     cfg.pattern_tau       = pattern_tau;
     #ifdef CFG_HAS_PATT_SETTINGS_FIELDS
       // Defaults chosen to preserve non-spam, non-repaint behavior:
       // confirmed scanning by default, no global quality gate unless user sets one.
       cfg.patt_mode               = 0;     // confirmed
       cfg.patt_min_quality01      = 0.0;   // disabled gate by default
       cfg.patt_retest_window_bars = 12;    // reasonable default
       cfg.patt_stop_atr_mult      = 1.5;   // aligns with Patterns.mqh runtime defaults
       cfg.patt_target_height_mult = 1.0;   // classic measured move = 1x height

       cfg.patt_emit_candles       = true;
       cfg.patt_emit_classic       = true;
       cfg.patt_emit_autoc         = false; // avoid duplicates with AutoC events by default
        
        // AMPDI defaults (spec)
        cfg.patt_atr_period        = 14;
        cfg.patt_ema_fast          = 50;
        cfg.patt_ema_slow          = 200;

        cfg.patt_volume_sma_period = 20;
        cfg.patt_volume_mult       = 1.5;
        cfg.patt_use_volume_filter = false;

        cfg.patt_use_momentum      = false;
        cfg.patt_rsi_period        = 14;

        cfg.patt_pivot_L           = 3;
        cfg.patt_pivot_R           = 3;

        cfg.patt_tol_atr_k         = 1.0;
        cfg.patt_min_score01       = 0.70;

        // Candlestick thresholds (AMPDI spec)
        cfg.patt_cs_hammer_body_pct_max   = 0.40;
        cfg.patt_cs_hammer_lw_body_mult   = 2.0;
        cfg.patt_cs_hammer_uw_body_mult   = 0.25;

        cfg.patt_cs_spin_body_pct_max     = 0.30;
        cfg.patt_cs_spin_wick_sym_rng_pct = 0.20;

        cfg.patt_cs_doji_body_rng_pct     = 0.05;
        cfg.patt_cs_doji_uw_rng_pct       = 0.10;
        cfg.patt_cs_doji_lw_rng_pct       = 0.60;

        cfg.patt_cs_star_body3_rng_min    = 0.60;
        cfg.patt_cs_star_retrace_body1_k  = 0.50;
     #endif
      
     cfg.vwap_lookback     = vwap_lookback;
     cfg.vwap_sigma        = vwap_sigma;
   
     // AutoVol cache (MarketData 5.6)
     cfg.auto_vol_cache_hours       = 24;
     cfg.auto_vol_adr_lookback_days = 20;
     cfg.auto_vol_ret_lookback_d1   = 60;
  
     // Feature toggles
     cfg.vsa_enable           = vsa_enable;
     cfg.vsa_penalty_max      = vsa_penalty_max;
     cfg.structure_enable     = structure_enable;
     cfg.liquidity_enable     = liquidity_enable;
     cfg.corr_softveto_enable = corr_softveto_enable;
   
     // >>> Only this line applies all “extras”
     ApplyExtras(cfg, extra);
   
     // Normalise / validate / optional logging
     Normalize(cfg);
     FinalizeThresholds(cfg);
     
     if(ArraySize(cfg.asset_list)<1){ Print("Config error: empty asset list"); return false; }
   
     string warns=""; Validate(cfg, warns);
     if(warns!="") Print("Config warnings:\n", warns);
   
     return true;
   }
   #endif // CONFIG_BUILDSETTINGSEX_DECL
   
   // Legacy ABI wrapper (matches the original, shorter prototype used elsewhere)
   bool BuildSettings(
     Settings &cfg,
     // original short block (unchanged)
     const string asset_csv, const ENUM_TIMEFRAMES tf_entry, const ENUM_TIMEFRAMES tf_h1,
     const ENUM_TIMEFRAMES tf_h4, const ENUM_TIMEFRAMES tf_d1,
     const double risk_pct, const double risk_cap_pct, const double min_sl_pips,
     const double min_tp_pips, const double max_sl_ceiling_pips,
     const double max_dd_day_pct, const int max_losses_day, const int max_trades_day, const int max_spread_points,
     const bool only_new_bar, const int timer_ms, const int server_offset_min,
     const bool session_filter, const int lon_open, const int lon_close, const int ny_open, const int ny_close,
     const bool news_on, const int block_pre, const int block_post, const int impact_mask,
     const bool debug, const bool filelog, const bool profile,
     const int atr_period, const double tp_quantile, const double tp_minr_floor, const double atr_sl_mult,
     const int slippage_points,
     const bool be_enable, const double be_at_R, const double be_lock_pips,
     const TrailType trail_type, const double trail_pips, const double trail_atr_mult,
     const bool partial_enable, const double p1_at_R, const double p1_close_pct, const double p2_at_R, const double p2_close_pct,
     const int cal_lookback_mins, const double cal_hard_skip, const double cal_soft_knee, const double cal_min_scale,
     const double vwap_z_edge, const double vwap_z_avoidtrend, const int pattern_lookback, const double pattern_tau,
     const int vwap_lookback, const double vwap_sigma,
     const bool vsa_enable, const double vsa_penalty_max, const bool structure_enable, const bool liquidity_enable, const bool corr_softveto_enable
   )
   {
     BuildExtras ex; BuildExtrasDefaults(ex);
     // Defaults already mirror neutral behaviour; tweak a couple of sensible baselines:
     ex.router_min_score        = 0.55;
     ex.router_fb_min           = 0.50;
     ex.london_start_local      = "08:00";
     ex.london_end_local        = "17:00";
     ex.atr_period_2            = 14;
     ex.struct_zz_depth         = 12;
     ex.struct_htf_mult         = 3;
     ex.ob_prox_max_pips        = 15.0;

     // SDOB quality gates (0 = disabled)
     ex.struct_zone_margin_pips = 0.0;
     ex.struct_min_touch_count  = 0;
     ex.struct_zone_min_score   = 0.0;

     ex.weekly_open_spread_ramp = true;
   
     return BuildSettingsEx(
       cfg,
       // pass-through of original short block
       asset_csv, tf_entry, tf_h1, tf_h4, tf_d1, risk_pct, risk_cap_pct, min_sl_pips, min_tp_pips, max_sl_ceiling_pips,
       max_dd_day_pct, max_losses_day, max_trades_day, max_spread_points, only_new_bar, timer_ms, server_offset_min,
       session_filter, lon_open, lon_close, ny_open, ny_close, news_on, block_pre, block_post, impact_mask,
       debug, filelog, profile, atr_period, tp_quantile, tp_minr_floor, atr_sl_mult, slippage_points,
       be_enable, be_at_R, be_lock_pips, trail_type, trail_pips, trail_atr_mult,
       partial_enable, p1_at_R, p1_close_pct, p2_at_R, p2_close_pct, cal_lookback_mins, cal_hard_skip, cal_soft_knee, cal_min_scale,
       vwap_z_edge, vwap_z_avoidtrend, pattern_lookback, pattern_tau, vwap_lookback, vwap_sigma,
       vsa_enable, vsa_penalty_max, structure_enable, liquidity_enable, corr_softveto_enable,
       // new extras bundle
       ex
     );
   }

  #ifdef CFG_HAS_STRAT_MODE
   // Clamp to valid StrategyMode codes: 0..2 (MAIN_ONLY, PACK_ONLY, COMBINED)
   inline int _ClampStratModeInt(const int v)
   {
     if(v < 0 || v > 2) return (int)STRAT_MAIN_ONLY;
     return v;
   }
   
   // Overloads let this compile whether Settings::strat_mode is int OR StrategyMode.
   inline void _SetStratModeRef(int &dst, const int v)
   {
     dst = _ClampStratModeInt(v);
   }
   inline void _SetStratModeRef(StrategyMode &dst, const int v)
   {
     dst = (StrategyMode)_ClampStratModeInt(v);
   }
   #endif

  //──────────────────────────────────────────────────────────────────
  // ABI-safe helpers
  //──────────────────────────────────────────────────────────────────
  inline void ApplyStrategyMode(Settings &cfg, const int mode)
   {
     #ifdef CFG_HAS_STRAT_MODE
       const int mi = _ClampStratModeInt(mode);
       _SetStratModeRef(cfg.strat_mode, mi);
     #endif
   
     Normalize(cfg); // Normalize now enforces strat_mode toggles internally
   }

  inline void ApplyTradeSelector(Settings &cfg, const TradeSelector sel)
  {
     cfg.trade_selector = ((int)sel<0 || (int)sel>2 ? TRADE_BOTH_AUTO : sel);

     const ENUM_TRADE_DIRECTION manualDir = TradeSelectorToDirection(cfg.trade_selector);
     if(manualDir == TDIR_BUY || manualDir == TDIR_SELL)
       cfg.trade_direction_selector = manualDir;
     else if((DirectionBiasMode)cfg.direction_bias_mode == DIRM_MANUAL_SELECTOR)
       cfg.trade_direction_selector = manualDir; // TDIR_BOTH
     else
       cfg.trade_direction_selector = TDIR_BOTH;
  }

  inline void ApplySessionPreset(Settings &cfg,
                                 const SessionPreset preset,
                                 const int tokyo_close_utc=6*60,
                                 const int sydney_open_utc=21*60)
  {
    cfg.session_preset  = preset;
    cfg.tokyo_close_utc = ClampMinute(tokyo_close_utc);
    cfg.sydney_open_utc = ClampMinute(sydney_open_utc);
    Normalize(cfg);
  }

  inline void ApplyStrategyVetoKnobs(Settings &cfg,
                                     const bool   struct_on,
                                     const bool   liq_on,
                                     const double liq_spr_atr_max,   // e.g., 0.45
                                     const bool   corr_on,
                                     const double regime_tq_min,     // 0..1
                                     const double regime_sg_min)     // 0..1
  {
    #ifdef CFG_HAS_STRUCT_VETO
      cfg.struct_veto_on = struct_on;
    #endif
    #ifdef CFG_HAS_LIQUIDITY_VETO
      cfg.liquidity_veto_on = liq_on;
    #endif
    #ifdef CFG_HAS_LIQUIDITY_LIMIT
      if(liq_spr_atr_max>0.0) cfg.liquidity_spr_atr_max = liq_spr_atr_max;
    #endif
    #ifdef CFG_HAS_CORR_VETO
      cfg.corr_veto_on = corr_on;
    #endif
    #ifdef CFG_HAS_REGIME_TQMIN
      if(regime_tq_min>0.0) cfg.regime_tq_min = regime_tq_min;
    #endif
    #ifdef CFG_HAS_REGIME_SGMIN
      if(regime_sg_min>0.0) cfg.regime_sg_min = regime_sg_min;
    #endif
    Normalize(cfg);
  }

  //──────────────────────────────────────────────────────────────────
  // Canonical serializer + hash
  //──────────────────────────────────────────────────────────────────
  inline string CanonicalCSV(const Settings &c)
  {
    string assets=Join(c.asset_list,"|");

    string s="";
    s+="assets="+assets;
    s+=",tf="+IntegerToString((int)c.tf_entry);
    s+=",h1="+IntegerToString((int)c.tf_h1);
    s+=",h4="+IntegerToString((int)c.tf_h4);
    s+=",d1="+IntegerToString((int)c.tf_d1);
    #ifdef CFG_HAS_TF_TREND_HTF
      s+=",tfTrend="+IntegerToString((int)c.tf_trend_htf);
    #endif
    s+=",tradeSel="+IntegerToString((int)c.trade_selector);
    #ifdef CFG_HAS_TRADE_CD_SEC
        s+=",cd="+IntegerToString((int)c.trade_cd_sec);
    #endif

    s+=",risk="+DoubleToString(c.risk_pct,6);
    s+=",cap="+DoubleToString(c.risk_cap_pct,6);
    s+=",minsl="+DoubleToString(c.min_sl_pips,3);
    s+=",mintp="+DoubleToString(c.min_tp_pips,3);
    s+=",slceil="+DoubleToString(c.max_sl_ceiling_pips,3);

    s+=",dd="+DoubleToString(c.max_daily_dd_pct,3);
    #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
      s+=",ddlim="+DoubleToString(c.day_dd_limit_pct,3);
    #endif

    // Profit taper / floor
    #ifdef CFG_HAS_DAY_PROFIT_CAP_PCT
      s+=",dayCap="+DoubleToString(c.day_profit_cap_pct,3);
    #endif
    #ifdef CFG_HAS_DAY_PROFIT_STOP_PCT
      s+=",dayStop="+DoubleToString(c.day_profit_stop_pct,3);
    #endif
    #ifdef CFG_HAS_TAPER_FLOOR
      s+=",taper="+DoubleToString(c.taper_floor,3);
    #endif
    
    // Monthly profit target (serialized using effective accessor)
    #ifdef CFG_HAS_MONTHLY_TARGET
      // Store raw PERCENT units for human readability / round-tripping
      s+=",monthTarget="+DoubleToString(c.monthly_target_pct,3);
    #endif
    
    #ifdef CFG_HAS_MONTHLY_TARGET_CYCLE_MODE
      s+=",monthCycle="+IntegerToString(c.monthly_target_cycle_mode);
    #endif
    #ifdef CFG_HAS_MONTHLY_TARGET_BASE_MODE
      s+=",monthBase="+IntegerToString(c.monthly_target_base_mode);
    #endif

    // Account-wide DD & challenge baseline
    #ifdef CFG_HAS_MAX_ACCOUNT_DD_PCT
      s+=",acctDD="+DoubleToString(c.max_account_dd_pct,3);
    #endif
    #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
      s+=",acctInit="+DoubleToString(c.challenge_init_equity,2);
    #endif

    s+=",loss="+IntegerToString(c.max_losses_day);
    s+=",trades="+IntegerToString(c.max_trades_day);
    
    #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
      s+=",posSym="+IntegerToString(c.max_positions_per_symbol);
    #endif
    #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
      s+=",posTot="+IntegerToString(c.max_positions_total);
    #endif
    #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
      s += ",rEvalAll=" + IntegerToString(c.router_eval_all_mode);
    #endif
    s+=",spr="+IntegerToString(c.max_spread_points);
    s+=",slip="+IntegerToString(c.slippage_points);

    s+=",newbar="+BoolStr(c.only_new_bar);
    s+=",timer="+IntegerToString(c.timer_ms);
    s+=",srvOff="+IntegerToString(c.server_offset_min);

    s+=",sess="+BoolStr(c.session_filter);
    s+=",lond="+IntegerToString(c.london_open_utc)+"-"+IntegerToString(c.london_close_utc);
    s+=",ny="+IntegerToString(c.ny_open_utc)+"-"+IntegerToString(c.ny_close_utc);

    s+=",preset="+IntegerToString((int)c.session_preset);
    s+=",tkyC="+IntegerToString(c.tokyo_close_utc);
    s+=",sydO="+IntegerToString(c.sydney_open_utc);
    
    #ifdef CFG_HAS_STRAT_MODE
      s+=",sMode="+IntegerToString((int)CfgStrategyMode(c));
    #endif
    #ifdef CFG_HAS_ENABLE_PACK_STRATS
      s += ",packOn=" + BoolStr(c.enable_pack_strats);
    #endif
    #ifdef CFG_HAS_DISABLE_PACKS
      s += ",packsOff=" + BoolStr(c.disable_packs);
    #endif

    #ifdef CFG_HAS_PROFILE_ENUM
      s+=",profile="+IntegerToString((int)c.profile); // when enum profile exists
    #endif

    // Directional bias mode (manual vs ICT auto)
    s+=",dirBias="+IntegerToString((int)c.direction_bias_mode);

    s+=",acOn="+BoolStr(c.auto_enable);
    s+=",acTF="+IntegerToString(c.auto_tf_mask);
    
    // Autochartist patterns export (single truth)
    s+=",acPLev="+IntegerToString(c.autoc_patt_export_level);
    s+=",acPEm="+IntegerToString(c.autoc_patt_emit_mode);
    s+=",acPTop="+IntegerToString(c.autoc_patt_topN);

    s+=",acPMin="+DoubleToString(c.autoc_patt_min_score01,3);
    s+=",acPMinAC="+DoubleToString(c.autoc_patt_min_score_autoc,3);
    s+=",acPMinCS="+DoubleToString(c.autoc_patt_min_score_candle,3);
    s+=",acPMinCH="+DoubleToString(c.autoc_patt_min_score_classic,3);
    s+=",acPMinSD="+DoubleToString(c.autoc_patt_min_score_sd,3);
     
    #ifdef CFG_HAS_PATTERNS_SD_SETTINGS
      s+=",sdAtrP="+IntegerToString(c.sd_atr_period);
      s+=",sdBaseMin="+IntegerToString(c.sd_base_min_bars);
      s+=",sdBaseMax="+IntegerToString(c.sd_base_max_bars);
   
      s+=",sdMinMoveATR="+DoubleToString(c.sd_min_move_atr,2);
      s+=",sdMaxBaseATR="+DoubleToString(c.sd_max_base_range_atr,2);
   
      s+=",sdBrkPips="+DoubleToString(c.sd_break_min_pips,1);
      s+=",sdBrkK="+DoubleToString(c.sd_break_atr_k,3);
      s+=",sdCloseOnly="+BoolStr(c.sd_close_confirm_only);
   
      s+=",sdVolOn="+BoolStr(c.sd_use_volume_filter);
      s+=",sdVolK="+DoubleToString(c.sd_vol_spike_k,2);
    #endif
    
    s+=",acChartQ="+DoubleToString(c.auto_chart_min_quality,3);
    s+=",acFibQ="+DoubleToString(c.auto_fib_min_quality,3);
    s+=",acFibTol="+DoubleToString(c.autofib_ratio_tolerance,4);
    s+=",acFibPL="+IntegerToString(c.auto_fib_pivot_L);
    s+=",acFibPR="+IntegerToString(c.auto_fib_pivot_R);
    s+=",acFibStopATR="+DoubleToString(c.auto_fib_stop_atr_mult,3);
    s+=",acFibT1="+DoubleToString(c.auto_fib_target_r1,3);
    s+=",acFibT2="+DoubleToString(c.auto_fib_target_r2,3);
    s+=",acFibT3="+DoubleToString(c.auto_fib_target_r3,3);

    // Key levels (local)
    s+=",acKeyTouches="+IntegerToString(c.auto_keylevel_min_touches);
    s+=",acKeyClustATR="+DoubleToString(c.auto_keylevel_cluster_atr,3);
    s+=",acKeyApprATR="+DoubleToString(c.auto_keylevel_approach_atr,3);

    s+=",acKeyMinPips="+DoubleToString(c.auto_keylevel_min_pips,1);
    s+=",acKeyBrkATR="+DoubleToString(c.auto_keylevel_break_margin_atr,3);
    s+=",acKeyBW="+IntegerToString(c.auto_keylevel_bounce_window);

    s+=",acKeyWT="+DoubleToString(c.auto_keylevel_w_touches,3);
    s+=",acKeyWR="+DoubleToString(c.auto_keylevel_w_recency,3);
    s+=",acKeyWB="+DoubleToString(c.auto_keylevel_w_bounce,3);
    
    // ICT strategy kind profile (for FVG settings)
    #ifdef CFG_HAS_SR_DETECTOR_SETTINGS
      s+=",srPL="+IntegerToString(c.sr_pivot_left);
      s+=",srPR="+IntegerToString(c.sr_pivot_right);
      s+=",srFrac="+BoolStr(c.sr_use_fractals);
      s+=",srStatic="+BoolStr(c.sr_static_mode);
      s+=",srExp="+IntegerToString(c.sr_level_expiry_bars);
      s+=",srMax="+IntegerToString(c.sr_max_levels);
      s+=",srZwATR="+DoubleToString(c.sr_zone_width_atr,3);
      s+=",srBrVol="+DoubleToString(c.sr_break_vol_ratio,3);
      s+=",srTv="+DoubleToString(c.sr_touch_vol_ratio,3);
      s+=",srMtf="+IntegerToString(c.sr_mtf_mask);
    #endif

    #ifdef CFG_HAS_STRATEGY_KIND
      s+=",ictStrat="+IntegerToString((int)c.strategyKind);
    #endif

    #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
      s+=",wkRamp="+BoolStr(c.weekly_open_spread_ramp);
    #endif

    s+=",news="+BoolStr(c.news_on);
    s+=",pre="+IntegerToString(c.block_pre_m);
    s+=",post="+IntegerToString(c.block_post_m);
    s+=",mask="+IntegerToString(c.news_impact_mask);
    
    #ifdef CFG_HAS_NEWS_BACKEND
       s += ",nb="  + IntegerToString(c.news_backend_mode);
       s += ",mvp=" + BoolStr(c.news_mvp_no_block);
       s += ",csv=" + BoolStr(c.news_failover_to_csv);
       s += ",nod=" + BoolStr(c.news_neutral_on_no_data);
       s += ",nac=" + BoolStr(c.news_allow_cached);
    #endif

    s+=",dbg="+BoolStr(c.debug);
    s+=",fl="+BoolStr(c.filelog);
    #ifndef CFG_HAS_PROFILE_ENUM
      s+=",prof="+BoolStr(c.profile); // diagnostics flag (bool build only)
    #endif

    s+=",atrp="+IntegerToString(c.atr_period);
    s+=",tpq="+DoubleToString(c.tp_quantile,3);
    s+=",tpr="+DoubleToString(c.tp_minr_floor,3);
    s+=",slm="+DoubleToString(c.atr_sl_mult,3);

    #ifdef CFG_HAS_PM_MODE
       s+=",pm="+IntegerToString(c.pm_mode);
    #endif
    #ifdef CFG_HAS_PM_ALLOW_DAILY_FLATTEN
       s+=",pmFlat="+BoolStr(c.pm_allow_daily_flatten);
    #endif
    #ifdef CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS
       s+=",pmCd="+IntegerToString(c.pm_post_dd_cooldown_seconds);
    #endif

    s+=",be="+BoolStr(c.be_enable);
    s+=",beat="+DoubleToString(c.be_at_R,3);
    s+=",bel="+DoubleToString(c.be_lock_pips,3);
    s+=",trt="+IntegerToString((int)c.trail_type);
    s+=",trp="+DoubleToString(c.trail_pips,3);
    s+=",trat="+DoubleToString(c.trail_atr_mult,3);

    s+=",pe="+BoolStr(c.partial_enable);
    s+=",p1r="+DoubleToString(c.p1_at_R,3);
    s+=",p1p="+DoubleToString(c.p1_close_pct,3);
    s+=",p2r="+DoubleToString(c.p2_at_R,3);
    s+=",p2p="+DoubleToString(c.p2_close_pct,3);

    s+=",calLb="+IntegerToString(c.cal_lookback_mins);
    s+=",calH="+DoubleToString(c.cal_hard_skip,3);
    s+=",calK="+DoubleToString(c.cal_soft_knee,3);
    s+=",calMin="+DoubleToString(c.cal_min_scale,3);

    // ICT quality thresholds
    s+=",qHigh="+DoubleToString(c.qualityThresholdHigh,3);
    s+=",qCont="+DoubleToString(c.qualityThresholdContinuation,3);
    s+=",qRev="+DoubleToString(c.qualityThresholdReversal,3);

    // Fib / OTE configuration
    s+=",fibDepth="+IntegerToString(c.fibDepth);
    s+=",fibATR="+IntegerToString(c.fibATRPeriod);
    s+=",fibDev="+DoubleToString(c.fibDevATRMult,3);
    s+=",fibBack="+IntegerToString(c.fibMaxBarsBack);
    s+=",fibUseConf="+BoolStr(c.fibUseConfluence);
    s+=",fibMinConf="+DoubleToString(c.fibMinConfluenceScore,3);
    s+=",fibOTETol="+DoubleToString(c.fibOTEToleranceATR,3);
    s+=",fibBonusRev="+DoubleToString(c.fibOTEQualityBonusReversal,3);
    s+=",fibMinRR="+DoubleToString(c.minRRFibAllowed,3);
    s+=",fibRRHard="+BoolStr(c.fibRRHardReject);

    #ifdef CFG_HAS_FIB_SETTINGS
      s+=",fibLog="+BoolStr(c.fibUseLogScale);
      s+=",fibOTEL="+DoubleToString(c.fibOTE_Low,4);
      s+=",fibOTEH="+DoubleToString(c.fibOTE_High,4);
      s+=",fibRetr="+c.fibRetraceRatiosCSV;
      s+=",fibExt="+c.fibExtensionRatiosCSV;
      s+=",fibABC="+BoolStr(c.fibExpansionEnable);
      s+=",fibLegATR="+DoubleToString(c.fibMinLegHeightATR,3);
      s+=",fibLegBars="+IntegerToString(c.fibMinLegBars);
      s+=",fibAppATR="+DoubleToString(c.fibApproachATRMult,3);
    #endif

    s+=",zEdge="+DoubleToString(c.vwap_z_edge,3);
    s+=",zAvoid="+DoubleToString(c.vwap_z_avoidtrend,3);
    s+=",pLook="+IntegerToString(c.pattern_lookback);
    s+=",pTau="+DoubleToString(c.pattern_tau,3);

    #ifdef CFG_HAS_PATT_SETTINGS_FIELDS
      s+=",pattMode="+IntegerToString(c.patt_mode);
      s+=",pattMinQ="+DoubleToString(c.patt_min_quality01,3);
      s+=",pattRet="+IntegerToString(c.patt_retest_window_bars);
      s+=",pattStopATR="+DoubleToString(c.patt_stop_atr_mult,3);
      s+=",pattTH="+DoubleToString(c.patt_target_height_mult,3);
      s+=",pattC="+BoolStr(c.patt_emit_candles);
      s+=",pattCh="+BoolStr(c.patt_emit_classic);
      s+=",pattAC="+BoolStr(c.patt_emit_autoc);
      
      s+=",pattATR="+IntegerToString(c.patt_atr_period);
      s+=",pattEMAf="+IntegerToString(c.patt_ema_fast);
      s+=",pattEMAs="+IntegerToString(c.patt_ema_slow);

      s+=",pattVolSMA="+IntegerToString(c.patt_volume_sma_period);
      s+=",pattVolM="+DoubleToString(c.patt_volume_mult,3);
      s+=",pattUseVol="+BoolStr(c.patt_use_volume_filter);

      s+=",pattUseMom="+BoolStr(c.patt_use_momentum);
      s+=",pattRSI="+IntegerToString(c.patt_rsi_period);

      s+=",pattPvL="+IntegerToString(c.patt_pivot_L);
      s+=",pattPvR="+IntegerToString(c.patt_pivot_R);

      s+=",pattTolK="+DoubleToString(c.patt_tol_atr_k,3);
      s+=",pattMinS="+DoubleToString(c.patt_min_score01,3);

      s+=",pattHamBP="+DoubleToString(c.patt_cs_hammer_body_pct_max,3);
      s+=",pattHamLW="+DoubleToString(c.patt_cs_hammer_lw_body_mult,3);
      s+=",pattHamUW="+DoubleToString(c.patt_cs_hammer_uw_body_mult,3);

      s+=",pattSpinBP="+DoubleToString(c.patt_cs_spin_body_pct_max,3);
      s+=",pattSpinSym="+DoubleToString(c.patt_cs_spin_wick_sym_rng_pct,3);

      s+=",pattDojiBP="+DoubleToString(c.patt_cs_doji_body_rng_pct,3);
      s+=",pattDojiUW="+DoubleToString(c.patt_cs_doji_uw_rng_pct,3);
      s+=",pattDojiLW="+DoubleToString(c.patt_cs_doji_lw_rng_pct,3);

      s+=",pattStarB3="+DoubleToString(c.patt_cs_star_body3_rng_min,3);
      s+=",pattStarRet="+DoubleToString(c.patt_cs_star_retrace_body1_k,3);
    #endif
    
    s+=",vwL="+IntegerToString(c.vwap_lookback);
    s+=",vwSig="+DoubleToString(c.vwap_sigma,3);
    #ifdef CFG_HAS_MAIN_REQUIRE_CHECKLIST
      s+=",mainReq="+BoolStr(c.main_require_checklist);
    #endif
    #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
      s+=",mainAny3="+BoolStr(c.main_confirm_any_of_3);
    #endif
    #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
      s+=",mainCls="+BoolStr(c.main_require_classical);
    #endif
    #ifdef CFG_HAS_ORDERFLOW_TH
      s+=",ofTh="+DoubleToString(c.orderflow_th,3);
    #endif
    
    #ifdef CFG_HAS_SB_REQUIRE_OTE
      s+=",sbReqOTE="+BoolStr(c.sb_require_ote);
    #endif
    #ifdef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
      s+=",sbReqVWAP="+BoolStr(c.sb_require_vwap_stretch);
    #endif
    
    s+=",xSBtz="+BoolStr(c.extra_silverbullet_tz);
    s+=",wSBtz="+DoubleToString(c.w_silverbullet_tz,3);

    s+=",xAMD="+BoolStr(c.extra_amd_htf);
    s+=",wAMDh1="+DoubleToString(c.w_amd_h1,3);
    s+=",wAMDh4="+DoubleToString(c.w_amd_h4,3);

    s+=",xPO3="+BoolStr(c.extra_po3_htf);
    s+=",wPO3h1="+DoubleToString(c.w_po3_h1,3);
    s+=",wPO3h4="+DoubleToString(c.w_po3_h4,3);

    s+=",xWYT="+BoolStr(c.extra_wyckoff_turn);
    s+=",wWYT="+DoubleToString(c.w_wyckoff_turn,3);
    
    #ifdef CFG_HAS_WYCK_CYCLE_SETTINGS
      s+=",wyRLB="+IntegerToString(c.wyck_range_lookback);
      s+=",wyMinRB="+IntegerToString(c.wyck_min_range_bars);
      s+=",wyEqATR="+DoubleToString(c.wyck_eq_tol_atr,3);
      s+=",wyMaxATR="+DoubleToString(c.wyck_max_range_atr,3);

      s+=",wyATRc="+BoolStr(c.wyck_use_atr_compression);
      s+=",wyATRn="+IntegerToString(c.wyck_atr_len);
      s+=",wyATRm="+IntegerToString(c.wyck_atr_ma_len);

      s+=",wyBBc="+BoolStr(c.wyck_use_bb_compression);
      s+=",wyBBn="+IntegerToString(c.wyck_bb_len);
      s+=",wyBBd="+DoubleToString(c.wyck_bb_dev,3);
      s+=",wyBBw="+DoubleToString(c.wyck_bb_width_thr,5);

      s+=",wySwL="+IntegerToString(c.wyck_swingL);
      s+=",wySwR="+IntegerToString(c.wyck_swingR);

      s+=",wyBosC="+IntegerToString(c.wyck_bos_confirm_closes);

      s+=",wyManQ="+DoubleToString(c.wyck_manip_min_quality,3);
      s+=",wyWick="+DoubleToString(c.wyck_wick_min_ratio,3);
      s+=",wyClsIn="+DoubleToString(c.wyck_close_inside_min,3);

      s+=",wyARw="+IntegerToString(c.wyck_ar_window_bars);
      s+=",wyVolN="+IntegerToString(c.wyck_vol_len);
      s+=",wyVolM="+DoubleToString(c.wyck_vol_mult,3);
    #endif

    #ifdef CFG_HAS_EXTRA_PHASE_CTX
      s+=",xPH="+BoolStr(c.extra_phase_ctx);
    #endif
    #ifdef CFG_HAS_W_PHASE_CTX
      s+=",wPH="+DoubleToString(c.w_phase_ctx,3);
    #endif

    s+=",xMTFZ="+BoolStr(c.extra_mtf_zones);
    s+=",wZ1="+DoubleToString(c.w_mtf_zone_h1,3);
    s+=",wZ4="+DoubleToString(c.w_mtf_zone_h4,3);
    s+=",zMaxATR="+DoubleToString(c.mtf_zone_max_dist_atr,3);

    s+=",vsa="+BoolStr(c.vsa_enable);
    s+=",vsaMax="+DoubleToString(c.vsa_penalty_max,3);
    #ifdef CFG_HAS_VSA_ALLOW_TICK_VOLUME
      s+=",vsaTick="+BoolStr(c.vsa_allow_tick_volume);
    #endif
    s+=",struct="+BoolStr(c.structure_enable);
    s+=",liq="+BoolStr(c.liquidity_enable);
    s+=",corrS="+BoolStr(c.corr_softveto_enable);

    // Post-confirm extras (DOM / correlation)
    #ifdef CFG_HAS_EXTRA_DOM_IMBALANCE
      s+=",xDOM="+BoolStr(c.extra_dom_imbalance);
    #endif
    #ifdef CFG_HAS_W_DOM_IMBALANCE
      s+=",wDOM="+DoubleToString(c.w_dom_imbalance,3);
    #endif
    #ifdef CFG_HAS_DOM_ZONE_PAD_POINTS
      s+=",domPad="+IntegerToString(c.dom_zone_pad_points);
    #endif
    #ifdef CFG_HAS_DOM_MIN_ABS_IMB
      s+=",domMin="+DoubleToString(c.dom_min_abs_imb,3);
    #endif
    #ifdef CFG_HAS_DEBUG_DOM
      s+=",domDbg="+BoolStr(c.debug_dom);
    #endif

    // OBI aliases (same storage as DOM imbalance)
    #ifdef CFG_HAS_EXTRA_OBI
      s+=",xOBI="+BoolStr(c.extra_dom_imbalance);
    #endif
    #ifdef CFG_HAS_W_OBI
      s+=",wOBI="+DoubleToString(c.w_dom_imbalance,3);
    #endif

    // Trendlines
    #ifdef CFG_HAS_EXTRA_TRENDLINES
      s+=",xTL="+BoolStr(c.extra_trendlines);
    #endif
    #ifdef CFG_HAS_W_TRENDLINES
      s+=",wTL="+DoubleToString(c.w_trendlines,3);
    #endif

    #ifdef CFG_HAS_EXTRA_CORR
      s+=",xCorr="+BoolStr(c.extra_correlation);
    #endif
    #ifdef CFG_HAS_W_CORR
      s+=",wCorr="+DoubleToString(c.w_correlation,3);
    #endif
    #ifdef CFG_HAS_CORR_LOOKBACK
      s+=",corrLb="+IntegerToString(c.corr_lookback);
    #endif
    #ifdef CFG_HAS_CORR_MIN_ABS
      s+=",corrAbs="+DoubleToString(c.corr_min_abs,3);
    #endif
    #ifdef CFG_HAS_CORR_REF_SYMBOL
      if(StringLen(c.corr_ref_symbol)>0) s+=",corrRef="+c.corr_ref_symbol;
    #endif

    // ---- Structured scanners (MarketScannerHub) ----
    s+=",scTF="+IntegerToString(c.scan_tf_mask);
    s+=",scInt="+IntegerToString(c.auto_scan_interval_sec);
    s+=",scLB="+IntegerToString(c.auto_scan_lookback_bars);

    #ifdef CFG_HAS_SCAN_FVG_SETTINGS
      s+=",scFVGOn="+BoolStr(c.scan_fvg_enable);
      s+=",scFVG5="+BoolStr(c.scan_fvg_tf_5m);
      s+=",scFVG15="+BoolStr(c.scan_fvg_tf_15m);
      s+=",scFVG1h="+BoolStr(c.scan_fvg_tf_1h);

      s+=",scFVGAppr="+DoubleToString(c.scan_fvg_approach_atr,3);
      s+=",scFVGBrk="+DoubleToString(c.scan_fvg_break_margin_atr,3);

      s+=",scFVGtZv="+DoubleToString(c.scan_fvg_touch_zvol_min,3);
      s+=",scFVGbZv="+DoubleToString(c.scan_fvg_breakout_zvol_min,3);
      s+=",scFVGtDz="+DoubleToString(c.scan_fvg_touch_delta_min,3);
      s+=",scFVGbDz="+DoubleToString(c.scan_fvg_breakout_delta_min,3);

      s+=",scFVGATR="+BoolStr(c.scan_fvg_use_atr_proxy);
    #endif

    #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
      #ifdef CFG_HAS_SCAN_TL_SETTINGS
        // Trendlines scan (3 buckets)
        s+=",scTLOn="+BoolStr(c.scan_tl_enable);
        s+=",scTLMskS="+IntegerToString(c.scan_tl_tf_mask_short);
        s+=",scTLMskM="+IntegerToString(c.scan_tl_tf_mask_mid);
        s+=",scTLMskL="+IntegerToString(c.scan_tl_tf_mask_long);

        // Short bucket
        s+=",scTLSLB="+IntegerToString(c.scan_tl_short_lookback_bars);
        s+=",scTLSPL="+IntegerToString(c.scan_tl_short_pivot_left);
        s+=",scTLSPR="+IntegerToString(c.scan_tl_short_pivot_right);
        s+=",scTLSTch="+IntegerToString(c.scan_tl_short_min_touches);
        s+=",scTLSTol="+DoubleToString(c.scan_tl_short_tol_atr_mult,3);
        s+=",scTLSBrk="+DoubleToString(c.scan_tl_short_break_atr_mult,3);
        s+=",scTLSDev="+DoubleToString(c.scan_tl_short_dev_atr_mult,3);
        s+=",scTLSMinPV="+DoubleToString(c.scan_tl_short_min_pivot_strength_atr,3);
        s+=",scTLSSrcP="+IntegerToString(c.scan_tl_short_pivot_price_src);
        s+=",scTLSSrcT="+IntegerToString(c.scan_tl_short_touch_price_src);
        s+=",scTLSSrcB="+IntegerToString(c.scan_tl_short_break_price_src);
        s+=",scTLSConf="+BoolStr(c.scan_tl_short_confirmed_only);

        // Mid bucket
        s+=",scTLMLB="+IntegerToString(c.scan_tl_mid_lookback_bars);
        s+=",scTLMPL="+IntegerToString(c.scan_tl_mid_pivot_left);
        s+=",scTLMPR="+IntegerToString(c.scan_tl_mid_pivot_right);
        s+=",scTLMTch="+IntegerToString(c.scan_tl_mid_min_touches);
        s+=",scTLMTol="+DoubleToString(c.scan_tl_mid_tol_atr_mult,3);
        s+=",scTLMBrk="+DoubleToString(c.scan_tl_mid_break_atr_mult,3);
        s+=",scTLMDev="+DoubleToString(c.scan_tl_mid_dev_atr_mult,3);
        s+=",scTLMMinPV="+DoubleToString(c.scan_tl_mid_min_pivot_strength_atr,3);
        s+=",scTLMSrcP="+IntegerToString(c.scan_tl_mid_pivot_price_src);
        s+=",scTLMSrcT="+IntegerToString(c.scan_tl_mid_touch_price_src);
        s+=",scTLMSrcB="+IntegerToString(c.scan_tl_mid_break_price_src);
        s+=",scTLMConf="+BoolStr(c.scan_tl_mid_confirmed_only);

        // Long bucket
        s+=",scTLLLB="+IntegerToString(c.scan_tl_long_lookback_bars);
        s+=",scTLLPL="+IntegerToString(c.scan_tl_long_pivot_left);
        s+=",scTLLPR="+IntegerToString(c.scan_tl_long_pivot_right);
        s+=",scTLLTch="+IntegerToString(c.scan_tl_long_min_touches);
        s+=",scTLLTol="+DoubleToString(c.scan_tl_long_tol_atr_mult,3);
        s+=",scTLLBrk="+DoubleToString(c.scan_tl_long_break_atr_mult,3);
        s+=",scTLLDev="+DoubleToString(c.scan_tl_long_dev_atr_mult,3);
        s+=",scTLLMinPV="+DoubleToString(c.scan_tl_long_min_pivot_strength_atr,3);
        s+=",scTLLSrcP="+IntegerToString(c.scan_tl_long_pivot_price_src);
        s+=",scTLLSrcT="+IntegerToString(c.scan_tl_long_touch_price_src);
        s+=",scTLLSrcB="+IntegerToString(c.scan_tl_long_break_price_src);
        s+=",scTLLConf="+BoolStr(c.scan_tl_long_confirmed_only);
      #endif

      // Liquidity scan
      s+=",scLiqOn="+BoolStr(c.scan_liq_enable);
      s+=",scLiq5="+BoolStr(c.scan_liq_tf_5m);
      s+=",scLiq15="+BoolStr(c.scan_liq_tf_15m);
      s+=",scLiq1h="+BoolStr(c.scan_liq_tf_1h);
      s+=",scLiqSw="+BoolStr(c.scan_liq_emit_sweeps);

      // Wyckoff scan
      s+=",scWyOn="+BoolStr(c.scan_wyck_enable);
      s+=",scWyH4="+IntegerToString(c.scan_wyck_tf_h4);
      s+=",scWyD1="+IntegerToString(c.scan_wyck_tf_d1);
      s+=",scWyPh="+BoolStr(c.scan_wyck_emit_phase);
      s+=",scWyPhZv="+DoubleToString(c.scan_wyck_phase_zvol_min,3);
      s+=",scWyMnZv="+DoubleToString(c.scan_wyck_manip_zvol_min,3);
      s+=",scWyLB4="+IntegerToString(c.scan_wyck_lb_h4);
      s+=",scWyLBD1="+IntegerToString(c.scan_wyck_lb_d1);

      // OBI scan
      s+=",scOBIOn="+BoolStr(c.scan_obi_enable);
      s+=",scOBID="+IntegerToString(c.scan_obi_depth_points);
      s+=",scOBIThr="+DoubleToString(c.scan_obi_threshold,3);
      s+=",scOBIVW="+BoolStr(c.scan_obi_vwap_enable);
      s+=",scOBIKL="+DoubleToString(c.scan_obi_keylevel_atr,3);

      s+=",scOBICms="+IntegerToString(c.scan_obi_cache_ms);
      s+=",scOBIMax="+IntegerToString(c.scan_obi_max_levels);
      s+=",scOBIMinV="+DoubleToString(c.scan_obi_min_tot_vol,2);
      s+=",scOBIVWDist="+DoubleToString(c.scan_obi_vwap_dist_atr,3);

      s+=",scOBIMode="+IntegerToString(c.scan_obi_mode);
      s+=",scOBITop="+IntegerToString(c.scan_obi_top_levels);
      s+=",scOBIWOn="+BoolStr(c.scan_obi_weighted_enable);
      s+=",scOBIWHL="+DoubleToString(c.scan_obi_weight_half_life_points,3);
      s+=",scOBIEMA="+IntegerToString(c.scan_obi_ema_len);
      s+=",scOBIWRef="+IntegerToString(c.scan_obi_weight_ref);
      
      // Footprint scan
      s+=",scFootOn="+BoolStr(c.scan_foot_enable);
      s+=",scFootATR="+BoolStr(c.scan_foot_use_atr_proxy);
      s+=",scFootZs="+DoubleToString(c.scan_foot_zstrong,3);
      s+=",scFootZa="+DoubleToString(c.scan_foot_zabsorb,3);
      s+=",scFootZd="+DoubleToString(c.scan_foot_zdiverge,3);

      // OFIS
      s+=",scOFdE="+IntegerToString(c.scan_of_delta_ema_len);
      s+=",scOFcE="+IntegerToString(c.scan_of_cvd_ema_len);
      s+=",scOFzL="+IntegerToString(c.scan_of_z_len);

      s+=",scOFthr="+DoubleToString(c.scan_of_ofpi_thr,1);
      s+=",scOFk="+DoubleToString(c.scan_of_absorb_k_sigma,3);
      s+=",scOFm="+DoubleToString(c.scan_of_absorb_m_atr,3);

      s+=",scOFex="+IntegerToString(c.scan_of_exhaust_lb);
      s+=",scOFhtf="+IntegerToString(c.scan_of_htf_mult);
      
      s+=",scFTickOn="+BoolStr(c.scan_foot_allow_ticks);
      s+=",scFTickMax="+IntegerToString(c.scan_foot_ticks_max_tf_sec);
      s+=",scFMinTk="+IntegerToString(c.scan_foot_min_ticks);

      // Tick classification (FootprintProxy)
      s+=",scFBA="+BoolStr(c.scan_foot_use_bidask_rule);
      s+=",scFBAeps="+DoubleToString(c.scan_foot_bidask_eps_points,2);
      
      s+=",scFBin="+IntegerToString(c.scan_foot_bin_points);
      s+=",scFMaxL="+IntegerToString(c.scan_foot_max_levels);
      s+=",scFVA="+DoubleToString(c.scan_foot_value_area_pct,3);

      s+=",scFImbR="+DoubleToString(c.scan_foot_imb_ratio,3);
      s+=",scFImbV="+DoubleToString(c.scan_foot_imb_min_vol,2);
      s+=",scFStk="+IntegerToString(c.scan_foot_stacked_levels);

      s+=",scFAbsD="+IntegerToString(c.scan_foot_absorb_depth_levels);
      s+=",scFAbsR="+DoubleToString(c.scan_foot_absorb_min_ratio,3);
      s+=",scFPOCap="+DoubleToString(c.scan_foot_poc_approach_atr,3);

      // Correlation scan (existing keys preserved)
      s+=",scCorrOn="+BoolStr(c.scan_corr_enable);
      s+=",scCorrThr="+DoubleToString(c.scan_corr_threshold,3);
      s+=",scCorrRec="+DoubleToString(c.scan_corr_recover,3);
      s+=",scCorrLen="+IntegerToString(c.scan_corr_len);
      
      #ifdef CFG_HAS_SCAN_CORR_DETECTOR_SETTINGS
        if(StringLen(c.scan_corr_secondary_symbol)>0) s+=",scCorrSym="+c.scan_corr_secondary_symbol;
        s+=",scCorrPx="+IntegerToString((int)c.scan_corr_price);
        s+=",scCorrLog="+BoolStr(c.scan_corr_use_log_returns);
        s+=",scCorrSm="+IntegerToString(c.scan_corr_smooth_len);
        s+=",scCorrSens="+DoubleToString(c.scan_corr_div_sensitivity,3);
        s+=",scCorrZL="+IntegerToString(c.scan_corr_z_len);
        s+=",scCorrZt="+DoubleToString(c.scan_corr_z_thr,2);
        s+=",scCorrMk="+IntegerToString(c.scan_corr_mom_k);
        s+=",scCorrMt="+DoubleToString(c.scan_corr_mom_thr,2);
        s+=",scCorrML="+BoolStr(c.scan_corr_mtf_len_enable);
      #endif

      // News scan
      s+=",scNewsOn="+BoolStr(c.scan_news_enable);
      s+=",scNewsSoon="+IntegerToString(c.scan_news_soon_sec);
      s+=",scNewsBlk="+IntegerToString(c.scan_news_block_sec);
      s+=",scNewsWin="+BoolStr(c.scan_news_emit_strat_windows);

      s+=",scNewsStr="+IntegerToString(c.scan_news_straddle_sec);
      s+=",scNewsFade="+IntegerToString(c.scan_news_fade_sec);
      s+=",scNewsBrk="+IntegerToString(c.scan_news_breakout_sec);
      s+=",scNewsSqz="+DoubleToString(c.scan_news_breakout_squeeze_ratio,3);
      s+=",scNewsLB="+IntegerToString(c.scan_news_breakout_lookback_bars);

      // Volume Profile scan
      s+=",scVPOn="+BoolStr(c.scan_vp_enable);
      s+=",scVPLB="+IntegerToString(c.scan_vp_lookback_bars);
      s+=",scVPBin="+IntegerToString(c.scan_vp_bin_points);
      s+=",scVPVA="+DoubleToString(c.scan_vp_value_area_pct,3);
      s+=",scVPTch="+DoubleToString(c.scan_vp_touch_atr,3);
      s+=",scVPBrk="+DoubleToString(c.scan_vp_break_margin_atr,3);
      s+=",scVPPoc="+DoubleToString(c.scan_vp_poc_shift_atr,3);
      s+=",scVPStale="+IntegerToString(c.scan_vp_stale_sec);
      s+=",scVPDist="+BoolStr(c.scan_vp_distribute_range);
    #endif

    // Liquidity pool thresholds (scanner behavior tuning)
    s+=",scLPAppr="+DoubleToString(c.scan_liq_pool_approach_atr,3);
    s+=",scLPConf="+IntegerToString(c.scan_liq_confirm_bars);
    s+=",scLPWarm="+IntegerToString(c.scan_liq_warmup_bars);
    s+=",scLPAcc="+DoubleToString(c.scan_liq_accept_margin_atr,3);
    s+=",scLPRej="+DoubleToString(c.scan_liq_reject_margin_atr,3);
    s+=",scLPStr="+DoubleToString(c.scan_liq_struct_break_eps_atr,3);
    s+=",scLPZv="+DoubleToString(c.scan_liq_min_zvol,3);

    // Liquidity Pools (Lux-style)
    #ifdef CFG_HAS_LIQPOOL_FIELDS
       s+=",liqMinTouch="+IntegerToString(c.liqPoolMinTouches);
       s+=",liqGap="+IntegerToString(c.liqPoolGapBars);
       s+=",liqWait="+IntegerToString(c.liqPoolConfirmWaitBars);
       s+=",liqEpsATR="+DoubleToString(c.liqPoolLevelEpsATR,3);
       s+=",liqLookback="+IntegerToString(c.liqPoolMaxLookbackBars);
       s+=",liqSweepATR="+DoubleToString(c.liqPoolMinSweepATR,3);
    #endif

    // Carry knobs (if present)
    #ifdef CFG_HAS_CARRY_ENABLE
      s+=",carry="+BoolStr(c.carry_enable);
    #endif
    #ifdef CFG_HAS_CARRY_BOOST_MAX
      s+=",carryBoost="+DoubleToString(c.carry_boost_max,3);
    #endif
    #ifdef CFG_HAS_CARRY_RISK_SPAN
      s+=",carrySpan="+DoubleToString(c.carry_risk_span,3);
    #endif

    // Confluence blend weights (if present)
    #ifdef CFG_HAS_CONFL_BLEND_TREND
      s+=",cbTrend="+DoubleToString(c.confl_blend_trend,3);
    #endif
    #ifdef CFG_HAS_CONFL_BLEND_MR
      s+=",cbMR="+DoubleToString(c.confl_blend_mr,3);
    #endif
    #ifdef CFG_HAS_CONFL_BLEND_OTHERS
      s+=",cbOther="+DoubleToString(c.confl_blend_others,3);
    #endif
    #ifdef CFG_HAS_ML_THRESHOLD
      s+=",mlTh="+DoubleToString(c.ml_threshold,3);
    #endif
    #ifdef CFG_HAS_ML_SETTINGS
      s+=",mlOn="+BoolStr(c.ml_enable);
      s+=",mlW="+DoubleToString(c.ml_weight,3);
      s+=",mlT="+DoubleToString(c.ml_temperature,3);
      s+=",mlCA="+DoubleToString(c.ml_conformal_alpha,3);
      s+=",mlD="+DoubleToString(c.ml_dampen,3);
   
      #ifdef CFG_HAS_ML_SLTP_MULT
         s+=",mlSltpOn="+BoolStr(c.ml_sltp_enable);
         s+=",mlSltpSLmin="+DoubleToString(c.ml_sltp_sl_min,3);
         s+=",mlSltpSLmax="+DoubleToString(c.ml_sltp_sl_max,3);
         s+=",mlSltpTPmin="+DoubleToString(c.ml_sltp_tp_min,3);
         s+=",mlSltpTPmax="+DoubleToString(c.ml_sltp_tp_max,3);
      #endif

      s+=",mlAuto="+BoolStr(c.ml_auto_calibrate);
      s+=",mlAgeH="+IntegerToString(c.ml_model_max_age_hours);
      s+=",mlAUC="+DoubleToString(c.ml_min_oos_auc,3);
      s+=",mlACC="+DoubleToString(c.ml_min_oos_acc,3);
      s+=",mlTrN="+IntegerToString(c.ml_min_samples_train);
      s+=",mlTeN="+IntegerToString(c.ml_min_samples_test);
   
      s+=",mlHor="+IntegerToString(c.ml_label_horizon_bars);
      s+=",mlATR="+DoubleToString(c.ml_label_atr_mult,3);
   
      s+=",mlCom="+BoolStr(c.ml_use_common_files);
      s+=",mlFile="+c.ml_model_file;
      s+=",mlData="+c.ml_dataset_file;
   
      s+=",mlExt="+BoolStr(c.ml_external_enable);
      s+=",mlExtM="+IntegerToString(c.ml_external_mode);
      s+=",mlExtF="+c.ml_external_file;
      s+=",mlExtMs="+IntegerToString(c.ml_external_poll_ms);
      s+=",mlHost="+c.ml_external_socket_host;
      s+=",mlPort="+IntegerToString(c.ml_external_socket_port);
    #endif

    // Optional router hints (if Settings declares them)
    #ifdef CFG_HAS_ROUTER_MIN_SCORE
      s+=",routerMin="+DoubleToString(c.router_min_score,3);
    #endif
    #ifdef CFG_HAS_ROUTER_MAX_STRATS
      s+=",routerCap="+IntegerToString(c.router_max_strats);
    #endif
    #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
      s+=",routerPool="+BoolStr(c.router_use_confl_pool);
    #endif
    #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
      s+=",routerPoolW="+DoubleToString(c.router_pool_blend_w,3);
    #endif
    
    #ifdef CFG_HAS_ENABLE_HARD_GATE
      s+=",hardGate="+BoolStr(c.enable_hard_gate);
    #endif
    #ifdef CFG_HAS_MIN_FEATURES_MET
      s+=",minFeat="+IntegerToString(c.min_features_met);
    #endif
   #ifdef CFG_HAS_REQUIRE_TREND_FILTER
     s+=",reqTrend="+BoolStr(c.require_trend_filter);
   #endif
   #ifdef CFG_HAS_REQUIRE_ADX_REGIME
     s+=",reqADX="+BoolStr(c.require_adx_regime);
   #endif
   #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
     s+=",reqStructOrOB="+BoolStr(c.require_struct_or_pattern_ob);
   #endif
   #ifdef CFG_HAS_LONDON_LIQ_POLICY
     s+=",lonPolicy="+BoolStr(c.london_liquidity_policy);
   #endif
   
   #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
     s+=",routerFBMin="+DoubleToString(c.router_fallback_min_score,3);
   #else
      #ifdef CFG_HAS_ROUTER_FB_MIN
        s+=",routerFBMin="+DoubleToString(c.router_fb_min,3);
      #endif
   #endif
   #ifdef CFG_HAS_ROUTER_HINTS
     s+=",fbConf="+DoubleToString(c.router_fallback_min_confluence,3);
     s+=",fbSpan="+IntegerToString(c.router_fallback_max_span);
     s+=",routerAlias="+c.router_profile_alias;
   #endif

    // Optional magic number (GV key prefix)
    #ifdef CFG_HAS_MAGIC_NUMBER
      s+=",magic="+StringFormat("%I64d",(long)c.magic_number);
    #endif

    return s;
  }

  inline ulong  SettingsHash64(const Settings &cfg){ return FNV1a64_Str(CanonicalCSV(cfg)); }
  inline string SettingsHashHex(const Settings &cfg){ return U64ToHex(SettingsHash64(cfg)); }

  inline void LogSettingsWithHash(const Settings &cfg, const string prefix="CFG")
  {
    const string csv=CanonicalCSV(cfg);
    const string hx=SettingsHashHex(cfg);
    PrintFormat("%s | hash=%s | %s", prefix, hx, csv);
  }

  inline bool BuildAndHash(Settings &cfg, const string tag = "")
   {
     // Stub kept for backward compatibility.
     // (No-op; 'cfg' and 'tag' intentionally unused.)
     if(false) Print(tag); // prevents “unused” nags without (void)
     return true;
   }

  //──────────────────────────────────────────────────────────────────
  // Trading Profiles (router hints + per-strategy tuning)
  //──────────────────────────────────────────────────────────────────
  inline string ProfileName(const TradingProfile p)
  {
    switch(p)
    {
      case PROF_TREND: return "Trend";
      case PROF_MR:    return "MeanReversion";
      case PROF_SCALP: return "ScalpFast";
      case PROF_PROP_SAFE: return "PropSafe";
      case PROF_DEFAULT:
      default:         return "Balanced";
    }
    return "Balanced";
  }
  
  inline string StrategyModeNameLocal(const int m){
     switch(m){
       case 0: return "MAIN_ONLY";
       case 1: return "PACK_ONLY";
       default: return "COMBINED";
     }
   }

  // Carry defaults (compile-safe)
  inline void ApplyCarryDefaultsForProfile(Settings &cfg, const TradingProfile prof)
  {
    #ifdef CFG_HAS_CARRY_ENABLE
    #ifdef CFG_HAS_CARRY_BOOST_MAX
    #ifdef CFG_HAS_CARRY_RISK_SPAN
      cfg.carry_enable = true;
      if(prof==PROF_TREND)       { cfg.carry_boost_max=0.08; cfg.carry_risk_span=0.30; }
      else if(prof==PROF_MR)     { cfg.carry_boost_max=0.04; cfg.carry_risk_span=0.20; }
      else if(prof==PROF_SCALP)  { cfg.carry_boost_max=0.06; cfg.carry_risk_span=0.20; }
      else /*DEFAULT*/           { cfg.carry_boost_max=0.06; cfg.carry_risk_span=0.25; }
    #endif
    #endif
    #endif
  }

  // Confluence blend defaults (compile-safe, profile-aware)
  inline void ApplyConfluenceBlendDefaultsForProfile(Settings &cfg,
                                                     const TradingProfile prof)
  {
    // Trend blend
    #ifdef CFG_HAS_CONFL_BLEND_TREND
    if(cfg.confl_blend_trend<=0.0)
    {
      double v = 0.15; // Balanced default
      switch(prof)
      {
        case PROF_TREND:  v = 0.10; break;
        case PROF_MR:     v = 0.12; break;
        case PROF_SCALP:  v = 0.12; break;
        case PROF_DEFAULT:
        default:          v = 0.15; break;
      }
      cfg.confl_blend_trend = v;
    }
    #endif

    // Mean-Reversion blend
    #ifdef CFG_HAS_CONFL_BLEND_MR
    if(cfg.confl_blend_mr<=0.0)
    {
      double v = 0.20; // Balanced default
      switch(prof)
      {
        case PROF_TREND:  v = 0.22; break;
        case PROF_MR:     v = 0.25; break;
        case PROF_SCALP:  v = 0.22; break;
        case PROF_DEFAULT:
        default:          v = 0.20; break;
      }
      cfg.confl_blend_mr = v;
    }
    #endif

    // Optional “others” blend
    #ifdef CFG_HAS_CONFL_BLEND_OTHERS
    if(cfg.confl_blend_others<=0.0)
    {
      double v = 0.20; // Baseline for most
      switch(prof)
      {
        case PROF_SCALP:  v = 0.18; break;
        default:          v = 0.20; break;
      }
      cfg.confl_blend_others = v;
    }
    #endif
  }

  inline void ProfileSpecDefaults(ProfileSpec &p)
  {
    p.min_score = 0.55; p.max_strats=12;
    p.fallback_min_confluence = 0.0;
    p.fallback_max_span       = 0;

    p.w_trend=1.0; p.w_trend_bos=1.0; p.w_mr=1.0; p.w_mr_range=1.0;
    p.w_squeeze=1.0; p.w_orb=0.8; p.w_sweepchoch=0.8; p.w_vsa=0.8;
    p.w_corrdiv=0.8; p.w_pairslite=0.8; p.w_news_dev=0.5; p.w_news_post=0.5;

    p.th_trend=0; p.th_trend_bos=0; p.th_mr=0; p.th_mr_range=0;
    p.th_squeeze=300; p.th_orb=1800; p.th_sweepchoch=900; p.th_vsa=900;
    p.th_corrdiv=600; p.th_pairslite=600; p.th_news_dev=0; p.th_news_post=0;
    
    // ICT defaults (balanced)
    p.w_ict_po3          = 1.00;
    p.w_ict_silverbullet = 1.00;
    p.w_ict_wyckoff_turn = 1.00;

    p.th_ict_po3          = 0;
    p.th_ict_silverbullet = 0;
    p.th_ict_wyckoff_turn = 0;
  }

  inline void BuildProfileSpec(const TradingProfile prof, ProfileSpec &out)
  {
    ProfileSpecDefaults(out);
    if(prof==PROF_TREND)
    {
      out.fallback_min_confluence = 0.55;
      out.fallback_max_span       = 6;
      out.w_trend=1.30; out.w_trend_bos=1.20;
      out.w_mr=0.70; out.w_mr_range=0.70;
      out.w_squeeze=1.10; out.w_orb=1.00;
      out.min_score = 0.58;
      out.th_trend=60; out.th_trend_bos=120; out.th_mr=180; out.th_mr_range=300;
      
      // ICT: trend profile de-emphasizes reversals, keeps SB moderate
      out.w_ict_po3          = 0.90;
      out.w_ict_silverbullet = 1.00;
      out.w_ict_wyckoff_turn = 0.70;

      out.th_ict_po3          = 120;
      out.th_ict_silverbullet = 90;
      out.th_ict_wyckoff_turn = 300;
    }
    else if(prof==PROF_MR)
    {
      out.fallback_min_confluence = 0.52;
      out.fallback_max_span       = 6;
      out.w_trend=0.70; out.w_trend_bos=0.70;
      out.w_mr=1.25; out.w_mr_range=1.20;
      out.w_squeeze=1.05; out.w_orb=0.70;
      out.min_score = 0.56;
      out.th_trend=240; out.th_trend_bos=300; out.th_mr=60; out.th_mr_range=90;
      
      // ICT: MR profile leans into Wyckoff turns
      out.w_ict_po3          = 0.95;
      out.w_ict_silverbullet = 0.90;
      out.w_ict_wyckoff_turn = 1.15;

      out.th_ict_po3          = 180;
      out.th_ict_silverbullet = 180;
      out.th_ict_wyckoff_turn = 120;
    }
    else if(prof==PROF_SCALP)
    {
      out.fallback_min_confluence = 0.50;
      out.fallback_max_span       = 4;
      out.w_trend=1.05; out.w_trend_bos=0.90;
      out.w_mr=1.10; out.w_mr_range=1.10;
      out.w_squeeze=1.10; out.w_orb=0.60;
      out.min_score = 0.53;
      out.th_trend=30; out.th_trend_bos=45; out.th_mr=30; out.th_mr_range=45;
      out.th_squeeze=180; out.th_orb=900; out.th_sweepchoch=300; out.th_vsa=300;
      out.th_corrdiv=300; out.th_pairslite=300;
      
      // ICT: scalp profile favors Silver Bullet style entries
      out.w_ict_po3          = 0.90;
      out.w_ict_silverbullet = 1.25;
      out.w_ict_wyckoff_turn = 0.85;

      out.th_ict_po3          = 90;
      out.th_ict_silverbullet = 30;
      out.th_ict_wyckoff_turn = 180;
    }
    else if(prof==PROF_PROP_SAFE)
    {
     // Router hints: narrow & strict
     out.min_score  = 0.65;
     out.max_strats = 1;
     out.fallback_min_confluence = 0.70;
     out.fallback_max_span       = 3;
   
     // Weights bias:
     // continuation > main > silver-bullet-ish (map via breakout), reversals small
     out.w_trend        = 1.05;  // main trend pullback
     out.w_trend_bos    = 1.20;  // continuation gets priority
     out.w_squeeze      = 1.00;  // neutral
     out.w_orb          = 0.90;  // treat as a proxy for "silver bullet"-style entries
     out.w_mr           = 0.85;  // de-emphasize mean reversion in challenge mode
     out.w_mr_range     = 0.85;
     out.w_sweepchoch   = 0.60;  // reversals small
     out.w_vsa          = 0.60;
   
     // Throttles (sec)
     // Keep most defaults; we only enforce a meaningful news post-fade.
     // (Global trade cooldown is set directly on Settings in ApplyTradingProfile.)
     out.th_news_post   = 900;   // 15 minutes post high-impact news
     
     // ICT: PropSafe is picky. Prefer SB/Continuation-like, downweight turns.
     out.w_ict_po3          = 0.85;
     out.w_ict_silverbullet = 1.05;
     out.w_ict_wyckoff_turn = 0.60;

     // Throttle ICT attempts to avoid overtrading in challenge mode
     out.th_ict_po3          = 300;
     out.th_ict_silverbullet = 120;
     out.th_ict_wyckoff_turn = 600;
    }
    // PROF_DEFAULT via defaults
  }

  // Lookup profile spec by string alias (for router_profile_alias)
   inline bool GetProfile(const string alias, ProfileSpec &out)
   {
     const string n = _Norm(alias);
   
     if(n=="trend" || n=="proftrend")
     { BuildProfileSpec(PROF_TREND, out); return true; }
   
     if(n=="meanreversion" || n=="mr" || n=="profmr")
     { BuildProfileSpec(PROF_MR, out); return true; }
   
     if(n=="scalp" || n=="scalpfast" || n=="profscalp")
     { BuildProfileSpec(PROF_SCALP, out); return true; }
   
     if(n=="propsafe" || n=="prop" || n=="challenge" || n=="prop_safe")
     { BuildProfileSpec(PROF_PROP_SAFE, out); return true; }
   
     // Default fallback
     BuildProfileSpec(PROF_DEFAULT, out);
     return true;
   }

  // Router hints accessors
  inline void GetRouterHints(const ProfileSpec &p, double &min_score, int &max_strats)
  { min_score=p.min_score; max_strats=p.max_strats; }

  // Optional: apply router hints into Settings (if fields exist)
  inline void ApplyProfileHintsToSettings(Settings &cfg, const ProfileSpec &p, const bool overwrite=true)
  {
    #ifdef CFG_HAS_ROUTER_MIN_SCORE
      if(overwrite || cfg.router_min_score<=0.0) cfg.router_min_score=p.min_score;
    #endif
    #ifdef CFG_HAS_ROUTER_MAX_STRATS
      if(overwrite || cfg.router_max_strats<=0)  cfg.router_max_strats=p.max_strats;
    #endif
    #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
      if(overwrite || cfg.router_fallback_min_score<=0.0)
        cfg.router_fallback_min_score = MathMax(0.0, p.min_score - 0.05);
    #endif
    #ifdef CFG_HAS_ROUTER_FB_MIN
      if(overwrite || cfg.router_fb_min<=0.0)
        cfg.router_fb_min = MathMax(0.0, p.min_score - 0.05);
    #endif
    #ifdef CFG_HAS_ROUTER_HINTS
       if(overwrite || cfg.router_fallback_min_confluence <= 0.0)
         cfg.router_fallback_min_confluence = MathMin(1.0, MathMax(0.0, p.fallback_min_confluence));
   
       if(overwrite || cfg.router_fallback_max_span <= 0)
         cfg.router_fallback_max_span = (p.fallback_max_span > 0 ? p.fallback_max_span : cfg.router_fallback_max_span);
    #endif
  }

  // Name normalization for lookup
  inline string _Norm(const string s)
  {
    string t = s;
    StringReplace(t, " ", "");
    StringReplace(t, "_", "");
    StringReplace(t, "/", "");
    StringReplace(t, "-", "");
    StringToLower(t);
    return t;
  }

  inline bool ProfileWeightByName(const ProfileSpec &p, const string strategy_name, double &weight_out)
  {
    const string n=_Norm(strategy_name);
    // trend
    if(n=="trendvwappullback" || n=="trendpullback" || n=="trend") { weight_out=p.w_trend; return true; }
    if(n=="trendboscontinuation" || n=="boscontinuation" || n=="bos") { weight_out=p.w_trend_bos; return true; }
    // MR
    if(n=="mrvwapband" || n=="vwapband" || n=="mr") { weight_out=p.w_mr; return true; }
    if(n=="mrrangenr7ib" || n=="nr7ib" || n=="mrrange") { weight_out=p.w_mr_range; return true; }
    // Breakout
    if(n=="breakoutsqueeze" || n=="squeeze") { weight_out=p.w_squeeze; return true; }
    if(n=="breakoutorb" || n=="orb") { weight_out=p.w_orb; return true; }
    // Reversal
    if(n=="reversalsweepchoch" || n=="sweepchoch" || n=="choch") { weight_out=p.w_sweepchoch; return true; }
    if(n=="reversalvsaclimaxfade" || n=="vsaclimaxfade" || n=="vsa") { weight_out=p.w_vsa; return true; }
    // Corr/Pairs
    if(n=="corrdivergence" || n=="corrdiv" || n=="corr") { weight_out=p.w_corrdiv; return true; }
    if(n=="pairsspreadlite" || n=="pairslite" || n=="pairs") { weight_out=p.w_pairslite; return true; }
    // News
    if(n=="newsdeviation" || n=="newsdev") { weight_out=p.w_news_dev; return true; }
    if(n=="newspostfade"  || n=="postfade") { weight_out=p.w_news_post; return true; }
    
    // ICT
    if(n=="ictpo3" || n=="po3" || n=="stratictpo3") { weight_out=p.w_ict_po3; return true; }
    if(n=="ictsilverbullet" || n=="silverbullet" || n=="stratictsilverbullet") { weight_out=p.w_ict_silverbullet; return true; }
    if(n=="ictwyckoffturn" || n=="wyckoffturn" || n=="springutad" || n=="stratictwyckoffspringutad") { weight_out=p.w_ict_wyckoff_turn; return true; }

    return false;
  }

  inline bool ProfileThrottleByName(const ProfileSpec &p, const string strategy_name, int &throttle_s_out)
  {
    const string n=_Norm(strategy_name);
    // trend
    if(n=="trendvwappullback" || n=="trendpullback" || n=="trend") { throttle_s_out=p.th_trend; return true; }
    if(n=="trendboscontinuation" || n=="boscontinuation" || n=="bos") { throttle_s_out=p.th_trend_bos; return true; }
    // MR
    if(n=="mrvwapband" || n=="vwapband" || n=="mr") { throttle_s_out=p.th_mr; return true; }
    if(n=="mrrangenr7ib" || n=="nr7ib" || n=="mrrange") { throttle_s_out=p.th_mr_range; return true; }
    // Breakout
    if(n=="breakoutsqueeze" || n=="squeeze") { throttle_s_out=p.th_squeeze; return true; }
    if(n=="breakoutorb" || n=="orb") { throttle_s_out=p.th_orb; return true; }
    // Reversal
    if(n=="reversalsweepchoch" || n=="sweepchoch" || n=="choch") { throttle_s_out=p.th_sweepchoch; return true; }
    if(n=="reversalvsaclimaxfade" || n=="vsaclimaxfade" || n=="vsa") { throttle_s_out=p.th_vsa; return true; }
    // Corr/Pairs
    if(n=="corrdivergence" || n=="corrdiv" || n=="corr") { throttle_s_out=p.th_corrdiv; return true; }
    if(n=="pairsspreadlite" || n=="pairslite" || n=="pairs") { throttle_s_out=p.th_pairslite; return true; }
    // News
    if(n=="newsdeviation" || n=="newsdev") { throttle_s_out=p.th_news_dev; return true; }
    if(n=="newspostfade"  || n=="postfade") { throttle_s_out=p.th_news_post; return true; }
    // ICT
    if(n=="ictpo3" || n=="po3" || n=="stratictpo3") { throttle_s_out=p.th_ict_po3; return true; }
    if(n=="ictsilverbullet" || n=="silverbullet" || n=="stratictsilverbullet") { throttle_s_out=p.th_ict_silverbullet; return true; }
    if(n=="ictwyckoffturn" || n=="wyckoffturn" || n=="springutad" || n=="stratictwyckoffspringutad") { throttle_s_out=p.th_ict_wyckoff_turn; return true; }
    return false;
  }

  // ---------------------------------------------------------------------------
   // Settings-level wrappers (so Router/Registry can query weight/throttle directly)
   // ---------------------------------------------------------------------------
   inline bool GetProfileSpecForSettings(const Settings &cfg, ProfileSpec &out)
   {
     // If profile is an enum field, use it; otherwise fall back to defaults.
     #ifdef CFG_HAS_PROFILE_ENUM
       BuildProfileSpec((TradingProfile)cfg.profile, out);
       return true;
     #else
       BuildProfileSpec(PROF_DEFAULT, out);
       return true;
     #endif
   }
   
   inline double ProfileWeightForSettings(const Settings &cfg,
                                         const string strategy_name,
                                         const double fallback=1.0)
   {
     ProfileSpec p; GetProfileSpecForSettings(cfg, p);
     double w=0.0;
     if(ProfileWeightByName(p, strategy_name, w)) return w;
     return fallback;
   }
   
   inline int ProfileThrottleForSettings(const Settings &cfg,
                                        const string strategy_name,
                                        const int fallback_sec=0)
   {
     ProfileSpec p; GetProfileSpecForSettings(cfg, p);
     int th=0;
     if(ProfileThrottleByName(p, strategy_name, th)) return th;
     return fallback_sec;
   }

  // CSV & save helpers for ProfileSpec (auditability)
  inline string ProfileSpecCSV(const TradingProfile prof, const ProfileSpec &p)
  {
    string s="";
    s+="profile="+ProfileName(prof);
    s+=",min_score="+DoubleToString(p.min_score,2);
    s+=",max_strats="+IntegerToString(p.max_strats);

    s+=",w_trend="+DoubleToString(p.w_trend,2);
    s+=",w_trend_bos="+DoubleToString(p.w_trend_bos,2);
    s+=",w_mr="+DoubleToString(p.w_mr,2);
    s+=",w_mr_range="+DoubleToString(p.w_mr_range,2);
    s+=",w_squeeze="+DoubleToString(p.w_squeeze,2);
    s+=",w_orb="+DoubleToString(p.w_orb,2);
    s+=",w_sweepchoch="+DoubleToString(p.w_sweepchoch,2);
    s+=",w_vsa="+DoubleToString(p.w_vsa,2);
    s+=",w_corrdiv="+DoubleToString(p.w_corrdiv,2);
    s+=",w_pairslite="+DoubleToString(p.w_pairslite,2);
    s+=",w_news_dev="+DoubleToString(p.w_news_dev,2);
    s+=",w_news_post="+DoubleToString(p.w_news_post,2);
    
    s+=",w_ict_po3="+DoubleToString(p.w_ict_po3,2);
    s+=",w_ict_silverbullet="+DoubleToString(p.w_ict_silverbullet,2);
    s+=",w_ict_wyckoff_turn="+DoubleToString(p.w_ict_wyckoff_turn,2);

    s+=",th_trend="+IntegerToString(p.th_trend);
    s+=",th_trend_bos="+IntegerToString(p.th_trend_bos);
    s+=",th_mr="+IntegerToString(p.th_mr);
    s+=",th_mr_range="+IntegerToString(p.th_mr_range);
    s+=",th_squeeze="+IntegerToString(p.th_squeeze);
    s+=",th_orb="+IntegerToString(p.th_orb);
    s+=",th_sweepchoch="+IntegerToString(p.th_sweepchoch);
    s+=",th_vsa="+IntegerToString(p.th_vsa);
    s+=",th_corrdiv="+IntegerToString(p.th_corrdiv);
    s+=",th_pairslite="+IntegerToString(p.th_pairslite);
    s+=",th_news_dev="+IntegerToString(p.th_news_dev);
    s+=",th_news_post="+IntegerToString(p.th_news_post);
    
    s+=",th_ict_po3="+IntegerToString(p.th_ict_po3);
    s+=",th_ict_silverbullet="+IntegerToString(p.th_ict_silverbullet);
    s+=",th_ict_wyckoff_turn="+IntegerToString(p.th_ict_wyckoff_turn);
    return s;
  }

  inline string _SanitizeFileStem(const string stem)
  {
    string s=stem;
    StringReplace(s,"/","_"); StringReplace(s,"\\","_");
    StringReplace(s,":","_"); StringReplace(s,"*","_");
    StringReplace(s,"?","_"); StringReplace(s,"\"","_");
    StringReplace(s,"<","_"); StringReplace(s,">","_");
    StringReplace(s,"|","_");
    if(StringLen(s)==0) s="profile";
    return s;
  }

  inline bool SaveProfileSpecCSV(const TradingProfile prof,
                                 const ProfileSpec &p,
                                 const string custom_name="",
                                 const bool to_common=false)
  {
    const string base = (StringLen(custom_name)>0 ? _SanitizeFileStem(custom_name) : ProfileName(prof));
    const string fn = "Profile_"+base+".csv";
    const int flags = FILE_WRITE | FILE_TXT | (to_common?FILE_COMMON:0);
    const int h = FileOpen(fn, flags, ';');
    if(h==INVALID_HANDLE){ PrintFormat("SaveProfileSpecCSV: failed to open '%s'", fn); return false; }
    FileWriteString(h, "CA Profile Spec CSV\n");
    FileWriteString(h, ProfileSpecCSV(prof, p)+"\n");
    FileClose(h);
    PrintFormat("Profile spec saved: %s", fn);
    return true;
  }

  //──────────────────────────────────────────────────────────────────
  // Apply/Wrap: Trading profile → Settings (carry + confluence + hints)
  //──────────────────────────────────────────────────────────────────
  inline void ApplyTradingProfile(Settings &cfg,
                                  const TradingProfile prof,
                                  const bool apply_router_hints=true,
                                  const bool apply_carry_defaults=true,
                                  const bool log_summary=true)
  {
    #ifdef CFG_HAS_PROFILE_ENUM
      cfg.profile = (int)prof;
    #endif

    if(apply_carry_defaults)
      ApplyCarryDefaultsForProfile(cfg, prof);

    // Seed confluence blend defaults (only if user didn't set them)
    ApplyConfluenceBlendDefaultsForProfile(cfg, prof);
    
    // ---- PropSafe profile: global confluence & cooldown ------------------------
   if(prof==PROF_PROP_SAFE)
   {
     // Confluence base gates (compile-safe: these fields already exist in Settings)
     cfg.cf_min_score  = 0.62;  // min aggregate score
     cfg.cf_min_needed = 2;     // min features required
   
     // Global trade cooldown (Policies will read via CfgTradeCooldownSec)
     #ifdef CFG_HAS_TRADE_CD_SEC
       cfg.trade_cd_sec = 900;  // 15 minutes
     #endif
     
     // Prefer ICT-driven direction in PropSafe (less manual overtrading)
     cfg.direction_bias_mode = (int)DIRM_AUTO_SMARTMONEY;
     // Preserve manual BUY/SELL overrides; otherwise leave BOTH (AUTO gate applies at runtime)
     const ENUM_TRADE_DIRECTION manualDir = TradeSelectorToDirection(cfg.trade_selector);
     if(manualDir == TDIR_BUY || manualDir == TDIR_SELL)
         cfg.trade_direction_selector = manualDir;
     else
         cfg.trade_direction_selector = TDIR_BOTH;

     // Hard gate and minimum features (only if those fields exist)
     #ifdef CFG_HAS_ENABLE_HARD_GATE
       cfg.enable_hard_gate = true;
     #endif
     #ifdef CFG_HAS_MIN_FEATURES_MET
       if(cfg.min_features_met <= 0) cfg.min_features_met = 2;
     #endif

     // Require filters (compile-safe)
     #ifdef CFG_HAS_REQUIRE_TREND_FILTER
       cfg.require_trend_filter = true;
     #endif
     #ifdef CFG_HAS_REQUIRE_ADX_REGIME
       cfg.require_adx_regime = true;
     #endif
     #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
       cfg.require_struct_or_pattern_ob = true;
     #endif
   }

    ProfileSpec p; BuildProfileSpec(prof, p);
    if(apply_router_hints)
      ApplyProfileHintsToSettings(cfg, p, /*overwrite*/true);

    Normalize(cfg);

    if(log_summary)
      PrintFormat("Config::ApplyTradingProfile | profile=%s | min_score=%.2f | max_strats=%d"
                  #ifdef CFG_HAS_CARRY_BOOST_MAX
                    " | carry_boost_max=%.3f"
                  #endif
                  #ifdef CFG_HAS_CARRY_RISK_SPAN
                    " | carry_risk_span=%.3f"
                  #endif
                  #ifdef CFG_HAS_CONFL_BLEND_TREND
                    " | cbTrend=%.2f"
                  #endif
                  #ifdef CFG_HAS_CONFL_BLEND_MR
                    " | cbMR=%.2f"
                  #endif
                  #ifdef CFG_HAS_CONFL_BLEND_OTHERS
                    " | cbOther=%.2f"
                  #endif
                  ,
                  ProfileName(prof), p.min_score, p.max_strats
                  #ifdef CFG_HAS_CARRY_BOOST_MAX
                    , cfg.carry_boost_max
                  #endif
                  #ifdef CFG_HAS_CARRY_RISK_SPAN
                    , cfg.carry_risk_span
                  #endif
                  #ifdef CFG_HAS_CONFL_BLEND_TREND
                    , cfg.confl_blend_trend
                  #endif
                  #ifdef CFG_HAS_CONFL_BLEND_MR
                    , cfg.confl_blend_mr
                  #endif
                  #ifdef CFG_HAS_CONFL_BLEND_OTHERS
                    , cfg.confl_blend_others
                  #endif
                  );
  }

  // Convenience wrapper: full profile apply (router hints + carry + confluence), typed enum
  inline void ApplyProfileToSettings(Settings &cfg,
                                     const TradingProfile prof,
                                     const bool apply_router=true,
                                     const bool apply_weights=true,
                                     const bool apply_throttles=true)
  {
    if(apply_weights || apply_throttles) { /* registry-level concern; no-op here */ }
    ApplyTradingProfile(cfg, prof, apply_router, /*apply_carry_defaults=*/true, /*log_summary=*/true);
  }

  // Overload: int code (handy for EA Inputs)
  inline void ApplyProfileToSettings(Settings &cfg,
                                     const int prof_code,
                                     const bool apply_router=true,
                                     const bool apply_weights=true,
                                     const bool apply_throttles=true)
  {
    ApplyProfileToSettings(cfg, (TradingProfile)prof_code, apply_router, apply_weights, apply_throttles);
  }

  //──────────────────────────────────────────────────────────────────
  // Risk Preset (Conservative / Balanced / Aggressive)
  //──────────────────────────────────────────────────────────────────
  inline string RiskPresetName(const RiskPreset r)
  {
    switch(r){
      case RISK_CONSERVATIVE: return "Conservative";
      case RISK_AGGRESSIVE:   return "Aggressive";
      case RISK_BALANCED:
      default:                return "Balanced";
    }
  }

  inline void ApplyRiskPreset(Settings &cfg, const RiskPreset r, const bool log_summary=true)
  {
    if(r==RISK_CONSERVATIVE)
    {
      cfg.risk_pct=0.50; cfg.risk_cap_pct=1.00;
      #ifdef CFG_HAS_CARRY_ENABLE
        cfg.carry_enable=true;
      #endif
      #ifdef CFG_HAS_CARRY_BOOST_MAX
        cfg.carry_boost_max=0.04;
      #endif
      #ifdef CFG_HAS_CARRY_RISK_SPAN
        cfg.carry_risk_span=0.20;
      #endif
    }
    else if(r==RISK_AGGRESSIVE)
    {
      cfg.risk_pct=2.00; cfg.risk_cap_pct=4.00;
      #ifdef CFG_HAS_CARRY_ENABLE
        cfg.carry_enable=true;
      #endif
      #ifdef CFG_HAS_CARRY_BOOST_MAX
        cfg.carry_boost_max=0.10;
      #endif
      #ifdef CFG_HAS_CARRY_RISK_SPAN
        cfg.carry_risk_span=0.35;
      #endif
    }
    else // Balanced
    {
      cfg.risk_pct=1.00; cfg.risk_cap_pct=3.00;
      #ifdef CFG_HAS_CARRY_ENABLE
        cfg.carry_enable=true;
      #endif
      #ifdef CFG_HAS_CARRY_BOOST_MAX
        cfg.carry_boost_max=0.06;
      #endif
      #ifdef CFG_HAS_CARRY_RISK_SPAN
        cfg.carry_risk_span=0.25;
      #endif
    }
    Normalize(cfg);
    if(log_summary)
      PrintFormat("Config::ApplyRiskPreset | %s | risk=%.2f%% cap=%.2f%%"
                  #ifdef CFG_HAS_CARRY_BOOST_MAX
                    " | carry_boost_max=%.3f"
                  #endif
                  #ifdef CFG_HAS_CARRY_RISK_SPAN
                    " | carry_risk_span=%.3f"
                  #endif
                  ,
                  RiskPresetName(r), cfg.risk_pct, cfg.risk_cap_pct
                  #ifdef CFG_HAS_CARRY_BOOST_MAX
                    , cfg.carry_boost_max
                  #endif
                  #ifdef CFG_HAS_CARRY_RISK_SPAN
                    , cfg.carry_risk_span
                  #endif
                  );
  }

  // Apply both (handy one-liner)
  inline void ApplyPresetProfileTriplet(Settings &cfg, const TradingProfile tp, const RiskPreset rp)
  {
    ApplyTradingProfile(cfg, tp, /*router*/true, /*carry*/true, /*log*/true);
    ApplyRiskPreset(cfg, rp, /*log*/true);
  }

  //──────────────────────────────────────────────────────────────────
  // Settings CSV export / import
  //  - Export uses CanonicalCSV (single-line; portable).
  //  - Import is tolerant: only recognized tokens are applied.
  //──────────────────────────────────────────────────────────────────
  inline bool SaveSettingsCSV(const Settings &cfg, const string stem="Settings", const bool to_common=true)
  {
    const string fn = _SanitizeFileStem(stem) + ".csv";
    const int flags = FILE_WRITE | FILE_TXT | (to_common?FILE_COMMON:0);
    int h = FileOpen(fn, flags, ';');
    if(h==INVALID_HANDLE){ PrintFormat("SaveSettingsCSV: failed to open '%s'", fn); return false; }
    FileWriteString(h, "CA Settings Canonical CSV\n");
    FileWriteString(h, CanonicalCSV(cfg) + "\n");
    FileWriteString(h, "hash=" + SettingsHashHex(cfg) + "\n");
    FileClose(h);
    PrintFormat("Settings saved: %s", fn);
    return true;
  }

  inline bool LoadSettingsCSV(Settings &cfg, const string stem="Settings", const bool from_common=true)
  {
    const string fn = _SanitizeFileStem(stem) + ".csv";
    const int flags = FILE_READ | FILE_TXT | (from_common?FILE_COMMON:0);
    int h = FileOpen(fn, flags, ';');
    if(h==INVALID_HANDLE){ PrintFormat("LoadSettingsCSV: not found '%s'", fn); return false; }

    // read lines and pick the longest CSV-ish line
    string best=""; int bestLen=0;
    while(!FileIsEnding(h))
    {
      string line = Trim(FileReadString(h));
      if(StringLen(line)>bestLen && StringFind(line,"=")>=0 && StringFind(line,",")>=0)
      { best=line; bestLen=StringLen(line); }
    }
    FileClose(h);
    if(bestLen<=0){ Print("LoadSettingsCSV: no CSV payload"); return false; }

    // tokenization by ','
    string tok[]; int n=StringSplit(best, ',', tok);
    bool seenMainReq=false, seenMainAny3=false, seenMainCls=false, seenVsaTick=false;
    for(int i=0;i<n;i++)
    {
      string k,v; if(!SplitKV(tok[i],k,v)) continue;
      // map
      if(k=="assets"){ ParseAssets(v, cfg.asset_list); }
      else if(k=="tf") cfg.tf_entry=(ENUM_TIMEFRAMES)ToInt(v);
      else if(k=="h1") cfg.tf_h1=(ENUM_TIMEFRAMES)ToInt(v);
      else if(k=="h4") cfg.tf_h4=(ENUM_TIMEFRAMES)ToInt(v);
      else if(k=="d1") cfg.tf_d1=(ENUM_TIMEFRAMES)ToInt(v);
      #ifdef CFG_HAS_TF_TREND_HTF
        else if(k=="trendtf") cfg.tf_trend_htf=(ENUM_TIMEFRAMES)ToInt(v);
      #endif
      #ifdef CFG_HAS_TF_TREND_HTF
        else if(k=="tfTrend") cfg.tf_trend_htf=(ENUM_TIMEFRAMES)ToInt(v);
      #endif
      else if(k=="tradeSel") cfg.trade_selector=(TradeSelector)ToInt(v);
      #ifdef CFG_HAS_TRADE_CD_SEC
            else if(k=="cd") cfg.trade_cd_sec = ToInt(v);
      #endif

      else if(k=="risk") cfg.risk_pct=ToDouble(v);
      else if(k=="cap") cfg.risk_cap_pct=ToDouble(v);
      #ifdef CFG_HAS_RISK_MULT_MAX
        else if(k=="rmmax") cfg.risk_mult_max = ToDouble(v);
      #endif
      
      else if(k=="minsl") cfg.min_sl_pips=ToDouble(v);
      else if(k=="mintp") cfg.min_tp_pips=ToDouble(v);
      else if(k=="slceil") cfg.max_sl_ceiling_pips=ToDouble(v);

      else if(k=="dd")     cfg.max_daily_dd_pct=ToDouble(v);
      #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
        else if(k=="ddlim")  cfg.day_dd_limit_pct=ToDouble(v);
      #endif
      
      #ifdef CFG_HAS_ADAPTIVE_DD_ENABLE
        else if(k=="adOn") cfg.adaptive_dd_enable = ToBool(v);
      #endif
      #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
        else if(k=="adWin") cfg.adaptive_dd_window_days = ToInt(v);
      #endif
      #ifdef CFG_HAS_ADAPTIVE_DD_PCT
        else if(k=="adPct") cfg.adaptive_dd_pct = ToDouble(v);
      #endif
      
      #ifdef CFG_HAS_BIGLOSS_RESET_ENABLE
        else if(k=="blOn") cfg.bigloss_reset_enable = ToBool(v);
      #endif
      #ifdef CFG_HAS_BIGLOSS_RESET_R
        else if(k=="blR") cfg.bigloss_reset_r = ToDouble(v);
      #endif
      #ifdef CFG_HAS_BIGLOSS_RESET_MINS
        else if(k=="blMin") cfg.bigloss_reset_mins = ToInt(v);
      #endif

      #ifdef CFG_HAS_MAX_ACCOUNT_DD_PCT
        else if(k=="acctDD")  cfg.max_account_dd_pct = ToDouble(v);
      #endif
      #ifdef CFG_HAS_CHALLENGE_INIT_EQUITY
        else if(k=="acctInit") cfg.challenge_init_equity = ToDouble(v);
      #endif

      #ifdef CFG_HAS_DAY_PROFIT_CAP_PCT
        else if(k=="dayCap")  cfg.day_profit_cap_pct = ToDouble(v);
      #endif
      #ifdef CFG_HAS_DAY_PROFIT_STOP_PCT
        else if(k=="dayStop") cfg.day_profit_stop_pct = ToDouble(v);
      #endif
      #ifdef CFG_HAS_TAPER_FLOOR
        else if(k=="taper")   cfg.taper_floor = ToDouble(v);
      #endif
      #ifdef CFG_HAS_MONTHLY_TARGET
        else if(k=="monthTarget")
          cfg.monthly_target_pct = ToDouble(v);
      #endif

      #ifdef CFG_HAS_MONTHLY_TARGET_CYCLE_MODE
        else if(k=="monthCycle")
          cfg.monthly_target_cycle_mode = ToInt(v);
      #endif
      #ifdef CFG_HAS_MONTHLY_TARGET_BASE_MODE
        else if(k=="monthBase")
          cfg.monthly_target_base_mode = ToInt(v);
      #endif

      else if(k=="loss") cfg.max_losses_day=ToInt(v);
      else if(k=="trades") cfg.max_trades_day=ToInt(v);
      
      #ifdef CFG_HAS_MAX_POSITIONS_PER_SYMBOL
        else if(k=="posSym") cfg.max_positions_per_symbol = ToInt(v);
      #endif
      #ifdef CFG_HAS_MAX_POSITIONS_TOTAL
        else if(k=="posTot") cfg.max_positions_total = ToInt(v);
      #endif
      #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
        else if(k=="rEvalAll") cfg.router_eval_all_mode = ToInt(v);
      #endif
      
      else if(k=="spr") cfg.max_spread_points=ToInt(v);
      else if(k=="slip") cfg.slippage_points=ToInt(v);

      else if(k=="newbar") cfg.only_new_bar=ToBool(v);
      else if(k=="timer") cfg.timer_ms=ToInt(v);
      else if(k=="srvOff") cfg.server_offset_min=ToInt(v);

      else if(k=="sess") cfg.session_filter=ToBool(v);
      else if(k=="lond"){ string ab[]; if(StringSplit(v,'-',ab)==2){ cfg.london_open_utc=ToInt(ab[0]); cfg.london_close_utc=ToInt(ab[1]); } }
      else if(k=="ny"){ string ab[]; if(StringSplit(v,'-',ab)==2){ cfg.ny_open_utc=ToInt(ab[0]); cfg.ny_close_utc=ToInt(ab[1]); } }

      else if(k=="preset") cfg.session_preset=(SessionPreset)ToInt(v);
      
      #ifdef CFG_HAS_PROFILE_ENUM
            else if(k=="profile")
              cfg.profile = (int)ToInt(v);
      #endif
      else if(k=="tkyC") cfg.tokyo_close_utc=ToInt(v);
      else if(k=="sydO") cfg.sydney_open_utc=ToInt(v);

      // Directional bias mode (manual vs ICT auto)
      else if(k=="dirBias")
         cfg.direction_bias_mode = ToInt(v);

      else if(k=="acOn") cfg.auto_enable = ToBool(v);
      else if(k=="acTF") cfg.auto_tf_mask = ToInt(v);
      
      // Autochartist patterns export (single truth)
      else if(k=="acPLev")   cfg.autoc_patt_export_level = ToInt(v);
      else if(k=="acPEm")    cfg.autoc_patt_emit_mode    = ToInt(v);
      else if(k=="acPTop")   cfg.autoc_patt_topN         = ToInt(v);

      else if(k=="acPMin")   cfg.autoc_patt_min_score01  = ToDouble(v);
      else if(k=="acPMinAC") cfg.autoc_patt_min_score_autoc   = ToDouble(v);
      else if(k=="acPMinCS") cfg.autoc_patt_min_score_candle  = ToDouble(v);
      else if(k=="acPMinCH") cfg.autoc_patt_min_score_classic = ToDouble(v);
      else if(k=="acPMinSD") cfg.autoc_patt_min_score_sd      = ToDouble(v);
      
      #ifdef CFG_HAS_PATTERNS_SD_SETTINGS
        else if(k=="sdAtrP")      cfg.sd_atr_period = ToInt(v);
        else if(k=="sdBaseMin")   cfg.sd_base_min_bars = ToInt(v);
        else if(k=="sdBaseMax")   cfg.sd_base_max_bars = ToInt(v);
      
        else if(k=="sdMinMoveATR") cfg.sd_min_move_atr = ToDouble(v);
        else if(k=="sdMaxBaseATR") cfg.sd_max_base_range_atr = ToDouble(v);
      
        else if(k=="sdBrkPips")   cfg.sd_break_min_pips = ToDouble(v);
        else if(k=="sdBrkK")      cfg.sd_break_atr_k = ToDouble(v);
        else if(k=="sdCloseOnly") cfg.sd_close_confirm_only = ToBool(v);
      
        else if(k=="sdVolOn")     cfg.sd_use_volume_filter = ToBool(v);
        else if(k=="sdVolK")      cfg.sd_vol_spike_k = ToDouble(v);
      #endif
      
      else if(k=="acChartQ") cfg.auto_chart_min_quality = ToDouble(v);
      else if(k=="acFibQ") cfg.auto_fib_min_quality = ToDouble(v);
      
      else if(k=="acFibTol") cfg.autofib_ratio_tolerance = ToDouble(v);
      else if(k=="acFibPL") cfg.auto_fib_pivot_L = ToInt(v);
      else if(k=="acFibPR") cfg.auto_fib_pivot_R = ToInt(v);
      
      else if(k=="acFibStopATR") cfg.auto_fib_stop_atr_mult = ToDouble(v);
      else if(k=="acFibT1") cfg.auto_fib_target_r1 = ToDouble(v);
      else if(k=="acFibT2") cfg.auto_fib_target_r2 = ToDouble(v);
      else if(k=="acFibT3") cfg.auto_fib_target_r3 = ToDouble(v);

      // Key levels (local)
      else if(k=="acKeyTouches")  cfg.auto_keylevel_min_touches = ToInt(v);
      else if(k=="acKeyClustATR") cfg.auto_keylevel_cluster_atr = ToDouble(v);
      else if(k=="acKeyApprATR")  cfg.auto_keylevel_approach_atr = ToDouble(v);

      else if(k=="acKeyMinPips")  cfg.auto_keylevel_min_pips = ToDouble(v);
      else if(k=="acKeyBrkATR")   cfg.auto_keylevel_break_margin_atr = ToDouble(v);
      else if(k=="acKeyBW")       cfg.auto_keylevel_bounce_window = ToInt(v);

      else if(k=="acKeyWT")       cfg.auto_keylevel_w_touches = ToDouble(v);
      else if(k=="acKeyWR")       cfg.auto_keylevel_w_recency = ToDouble(v);
      else if(k=="acKeyWB")       cfg.auto_keylevel_w_bounce = ToDouble(v);

      // ICT strategy kind profile (for FVG strictness per-playbook)
      #ifdef CFG_HAS_SR_DETECTOR_SETTINGS
        else if(k=="srPL")     cfg.sr_pivot_left = ToInt(v);
        else if(k=="srPR")     cfg.sr_pivot_right = ToInt(v);
        else if(k=="srFrac")   cfg.sr_use_fractals = ToBool(v);
        else if(k=="srStatic") cfg.sr_static_mode = ToBool(v);
        else if(k=="srExp")    cfg.sr_level_expiry_bars = ToInt(v);
        else if(k=="srMax")    cfg.sr_max_levels = ToInt(v);
        else if(k=="srZwATR")  cfg.sr_zone_width_atr = ToDouble(v);
        else if(k=="srBrVol")  cfg.sr_break_vol_ratio = ToDouble(v);
        else if(k=="srTv")     cfg.sr_touch_vol_ratio = ToDouble(v);
        else if(k=="srMtf")    cfg.sr_mtf_mask = ToInt(v);

        // Optional human-friendly aliases (non-breaking)
        else if(k=="srPivotL") cfg.sr_pivot_left = ToInt(v);
        else if(k=="srPivotR") cfg.sr_pivot_right = ToInt(v);
      #endif

      #ifdef CFG_HAS_STRATEGY_KIND
        else if(k=="ictStrat")
          cfg.strategyKind = (ICTStrategyKind)ToInt(v);
      #endif
      
      #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
         else if(k=="wkRamp") cfg.weekly_open_spread_ramp = ToBool(v);
      #endif

      else if(k=="news") cfg.news_on=ToBool(v);
      else if(k=="pre") cfg.block_pre_m=ToInt(v);
      else if(k=="post") cfg.block_post_m=ToInt(v);
      else if(k=="mask") cfg.news_impact_mask=ToInt(v);
      
      #ifdef CFG_HAS_NEWS_BACKEND
         else if(k=="nb")  cfg.news_backend_mode = ToInt(v);
         else if(k=="mvp") cfg.news_mvp_no_block = ToBool(v);
         else if(k=="nbm") cfg.news_backend_mode   = ToInt(v);   // legacy key
         else if(k=="nnb") cfg.news_mvp_no_block   = ToBool(v);  // legacy key
         else if(k=="csv") cfg.news_failover_to_csv = ToBool(v);
         else if(k=="nod") cfg.news_neutral_on_no_data = ToBool(v);
         else if(k=="nac") cfg.news_allow_cached = ToBool(v);
      #endif

      else if(k=="dbg") cfg.debug=ToBool(v);
      else if(k=="fl") cfg.filelog=ToBool(v);
      #ifndef CFG_HAS_PROFILE_ENUM
            else if(k=="prof") cfg.profile=ToBool(v); // diagnostic flag (bool build only)
      #endif

      else if(k=="atrp") cfg.atr_period=ToInt(v);
      else if(k=="tpq") cfg.tp_quantile=ToDouble(v);
      else if(k=="tpr") cfg.tp_minr_floor=ToDouble(v);
      else if(k=="slm") cfg.atr_sl_mult=ToDouble(v);

      #ifdef CFG_HAS_PM_MODE
         else if(k=="pm") cfg.pm_mode = ToInt(v);
      #endif
      #ifdef CFG_HAS_PM_ALLOW_DAILY_FLATTEN
         else if(k=="pmFlat") cfg.pm_allow_daily_flatten = ToBool(v);
      #endif
      #ifdef CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS
         else if(k=="pmCd") cfg.pm_post_dd_cooldown_seconds = ToInt(v);
      #endif

      else if(k=="be") cfg.be_enable=ToBool(v);
      else if(k=="beat") cfg.be_at_R=ToDouble(v);
      else if(k=="bel") cfg.be_lock_pips=ToDouble(v);
      else if(k=="trt") cfg.trail_type=(TrailType)ToInt(v);
      else if(k=="trp") cfg.trail_pips=ToDouble(v);
      else if(k=="trat") cfg.trail_atr_mult=ToDouble(v);
      
      #ifdef CFG_HAS_TRAIL_AUTO_ADX_TF
        else if(k=="tAdxTf") cfg.trail_auto_adx_tf = (ENUM_TIMEFRAMES)ToInt(v);
      #endif
      #ifdef CFG_HAS_TRAIL_AUTO_ADX_PERIOD
        else if(k=="tAdxPer") cfg.trail_auto_adx_period = ToInt(v);
      #endif
      #ifdef CFG_HAS_TRAIL_AUTO_ADX_MIN
        else if(k=="tAdxMin") cfg.trail_auto_adx_min = ToDouble(v);
      #endif

      else if(k=="pe") cfg.partial_enable=ToBool(v);
      else if(k=="p1r") cfg.p1_at_R=ToDouble(v);
      else if(k=="p1p") cfg.p1_close_pct=ToDouble(v);
      else if(k=="p2r") cfg.p2_at_R=ToDouble(v);
      else if(k=="p2p") cfg.p2_close_pct=ToDouble(v);

      else if(k=="calLb") cfg.cal_lookback_mins = ToInt(v);
      else if(k=="calH")  cfg.cal_hard_skip     = ToDouble(v);
      else if(k=="calK")  cfg.cal_soft_knee     = ToDouble(v);
      else if(k=="calMin") cfg.cal_min_scale    = ToDouble(v);

      // ICT quality thresholds
      else if(k=="qHigh") cfg.qualityThresholdHigh = ToDouble(v);
      else if(k=="qCont") cfg.qualityThresholdContinuation = ToDouble(v);
      else if(k=="qRev")  cfg.qualityThresholdReversal = ToDouble(v);

      // Fib / OTE config
      else if(k=="fibDepth")   cfg.fibDepth = ToInt(v);
      else if(k=="fibATR")     cfg.fibATRPeriod = ToInt(v);
      else if(k=="fibDev")     cfg.fibDevATRMult = ToDouble(v);
      else if(k=="fibBack")    cfg.fibMaxBarsBack = ToInt(v);
      else if(k=="fibUseConf") cfg.fibUseConfluence = ToBool(v);
      else if(k=="fibMinConf") cfg.fibMinConfluenceScore = ToDouble(v);
      else if(k=="fibOTETol")  cfg.fibOTEToleranceATR = ToDouble(v);
      else if(k=="fibBonusRev") cfg.fibOTEQualityBonusReversal = ToDouble(v);
      else if(k=="fibMinRR")   cfg.minRRFibAllowed = ToDouble(v);
      else if(k=="fibRRHard")  cfg.fibRRHardReject = ToBool(v);

      #ifdef CFG_HAS_FIB_SETTINGS
        else if(k=="fibLog")     cfg.fibUseLogScale        = ToBool(v);
        else if(k=="fibOTEL")    cfg.fibOTE_Low            = ToDouble(v);
        else if(k=="fibOTEH")    cfg.fibOTE_High           = ToDouble(v);
        else if(k=="fibRetr")    cfg.fibRetraceRatiosCSV   = v;
        else if(k=="fibExt")     cfg.fibExtensionRatiosCSV = v;
        else if(k=="fibABC")     cfg.fibExpansionEnable    = ToBool(v);
        else if(k=="fibLegATR")  cfg.fibMinLegHeightATR    = ToDouble(v);
        else if(k=="fibLegBars") cfg.fibMinLegBars         = ToInt(v);
        else if(k=="fibAppATR")  cfg.fibApproachATRMult    = ToDouble(v);
      #endif

      // Confluence / VWAP / pattern
      else if(k=="zEdge")  cfg.vwap_z_edge = ToDouble(v);
      else if(k=="zAvoid") cfg.vwap_z_avoidtrend = ToDouble(v);
      else if(k=="pLook")  cfg.pattern_lookback = ToInt(v);
      else if(k=="pTau")   cfg.pattern_tau = ToDouble(v);
      else if(k=="vwL")    cfg.vwap_lookback = ToInt(v);
      
      #ifdef CFG_HAS_PATT_SETTINGS_FIELDS
        else if(k=="pattMode")   cfg.patt_mode               = ToInt(v);
        else if(k=="pattMinQ")   cfg.patt_min_quality01      = ToDouble(v);
        else if(k=="pattRet")    cfg.patt_retest_window_bars = ToInt(v);
        else if(k=="pattStopATR")cfg.patt_stop_atr_mult      = ToDouble(v);
        else if(k=="pattTH")     cfg.patt_target_height_mult = ToDouble(v);
        else if(k=="pattC")      cfg.patt_emit_candles       = ToBool(v);
        else if(k=="pattCh")     cfg.patt_emit_classic       = ToBool(v);
        else if(k=="pattAC")     cfg.patt_emit_autoc         = ToBool(v);
        
        else if(k=="pattATR")    cfg.patt_atr_period        = ToInt(v);
        else if(k=="pattEMAf")   cfg.patt_ema_fast          = ToInt(v);
        else if(k=="pattEMAs")   cfg.patt_ema_slow          = ToInt(v);

        else if(k=="pattVolSMA") cfg.patt_volume_sma_period = ToInt(v);
        else if(k=="pattVolM")   cfg.patt_volume_mult       = ToDouble(v);
        else if(k=="pattUseVol") cfg.patt_use_volume_filter = ToBool(v);

        else if(k=="pattUseMom") cfg.patt_use_momentum      = ToBool(v);
        else if(k=="pattRSI")    cfg.patt_rsi_period        = ToInt(v);

        else if(k=="pattPvL")    cfg.patt_pivot_L           = ToInt(v);
        else if(k=="pattPvR")    cfg.patt_pivot_R           = ToInt(v);

        else if(k=="pattTolK")   cfg.patt_tol_atr_k         = ToDouble(v);
        else if(k=="pattMinS")   cfg.patt_min_score01       = ToDouble(v);

        else if(k=="pattHamBP")  cfg.patt_cs_hammer_body_pct_max   = ToDouble(v);
        else if(k=="pattHamLW")  cfg.patt_cs_hammer_lw_body_mult   = ToDouble(v);
        else if(k=="pattHamUW")  cfg.patt_cs_hammer_uw_body_mult   = ToDouble(v);

        else if(k=="pattSpinBP") cfg.patt_cs_spin_body_pct_max     = ToDouble(v);
        else if(k=="pattSpinSym")cfg.patt_cs_spin_wick_sym_rng_pct = ToDouble(v);

        else if(k=="pattDojiBP") cfg.patt_cs_doji_body_rng_pct     = ToDouble(v);
        else if(k=="pattDojiUW") cfg.patt_cs_doji_uw_rng_pct       = ToDouble(v);
        else if(k=="pattDojiLW") cfg.patt_cs_doji_lw_rng_pct       = ToDouble(v);

        else if(k=="pattStarB3") cfg.patt_cs_star_body3_rng_min    = ToDouble(v);
        else if(k=="pattStarRet")cfg.patt_cs_star_retrace_body1_k  = ToDouble(v);
      #endif
      
      else if(k=="vwSig")  cfg.vwap_sigma = ToDouble(v);
      
      // Structure / SDOB knobs
      else if(k=="zzDepth" || k=="structZZ") cfg.struct_zz_depth = ToInt(v);
      else if(k=="htfMult" || k=="structHTF") cfg.struct_htf_mult = ToInt(v);
      else if(k=="obProx"  || k=="obPx")      cfg.ob_prox_max_pips = ToDouble(v);
      
      #ifdef CFG_HAS_STRUCT_ZONE_MARGIN_PIPS
        else if(k=="sdMargin" || k=="sdMarginPips") cfg.struct_zone_margin_pips = ToDouble(v);
      #endif
      #ifdef CFG_HAS_STRUCT_MIN_TOUCH_COUNT
        else if(k=="sdMinTouches" || k=="sdTouches") cfg.struct_min_touch_count = ToInt(v);
      #endif
      #ifdef CFG_HAS_STRUCT_ZONE_MIN_SCORE
        else if(k=="sdMinScore" || k=="sdScore") cfg.struct_zone_min_score = ToDouble(v);
      #endif

      #ifdef CFG_HAS_MAIN_REQUIRE_CHECKLIST
        else if(k=="mainReq"){ cfg.main_require_checklist=ToBool(v); seenMainReq=true; }
      #endif
      #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
        else if(k=="mainAny3"){ cfg.main_confirm_any_of_3=ToBool(v); seenMainAny3=true; }
      #endif
      #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
        else if(k=="mainCls"){ cfg.main_require_classical=ToBool(v); seenMainCls=true; }
      #endif
      #ifdef CFG_HAS_ORDERFLOW_TH
        else if(k=="ofTh") cfg.orderflow_th=ToDouble(v);
      #endif
      
      #ifdef CFG_HAS_SB_REQUIRE_OTE
        else if(k=="sbReqOTE") cfg.sb_require_ote = ToBool(v);
      #endif
      #ifdef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
        else if(k=="sbReqVWAP") cfg.sb_require_vwap_stretch = ToBool(v);
      #endif
      
      else if(k=="xPH") cfg.extra_phase_ctx = ToBool(v);
      else if(k=="wPH") cfg.w_phase_ctx = ToDouble(v);
      
      else if(k=="xSBtz") cfg.extra_silverbullet_tz = ToBool(v);
      else if(k=="wSBtz") cfg.w_silverbullet_tz = ToDouble(v);

      else if(k=="xAMD")  cfg.extra_amd_htf = ToBool(v);
      else if(k=="wAMDh1") cfg.w_amd_h1 = ToDouble(v);
      else if(k=="wAMDh4") cfg.w_amd_h4 = ToDouble(v);

      else if(k=="xPO3")   cfg.extra_po3_htf = ToBool(v);
      else if(k=="wPO3h1") cfg.w_po3_h1 = ToDouble(v);
      else if(k=="wPO3h4") cfg.w_po3_h4 = ToDouble(v);

      else if(k=="xWYT") cfg.extra_wyckoff_turn = ToBool(v);
      else if(k=="wWYT") cfg.w_wyckoff_turn = ToDouble(v);

      #ifdef CFG_HAS_WYCK_CYCLE_SETTINGS
        else if(k=="wyRLB")   cfg.wyck_range_lookback = ToInt(v);
        else if(k=="wyMinRB") cfg.wyck_min_range_bars = ToInt(v);
        else if(k=="wyEqATR") cfg.wyck_eq_tol_atr = ToDouble(v);
        else if(k=="wyMaxATR")cfg.wyck_max_range_atr = ToDouble(v);

        else if(k=="wyATRc")  cfg.wyck_use_atr_compression = ToBool(v);
        else if(k=="wyATRn")  cfg.wyck_atr_len = ToInt(v);
        else if(k=="wyATRm")  cfg.wyck_atr_ma_len = ToInt(v);

        else if(k=="wyBBc")   cfg.wyck_use_bb_compression = ToBool(v);
        else if(k=="wyBBn")   cfg.wyck_bb_len = ToInt(v);
        else if(k=="wyBBd")   cfg.wyck_bb_dev = ToDouble(v);
        else if(k=="wyBBw")   cfg.wyck_bb_width_thr = ToDouble(v);

        else if(k=="wySwL")   cfg.wyck_swingL = ToInt(v);
        else if(k=="wySwR")   cfg.wyck_swingR = ToInt(v);

        else if(k=="wyBosC")  cfg.wyck_bos_confirm_closes = ToInt(v);

        else if(k=="wyManQ")  cfg.wyck_manip_min_quality = ToDouble(v);
        else if(k=="wyWick")  cfg.wyck_wick_min_ratio = ToDouble(v);
        else if(k=="wyClsIn") cfg.wyck_close_inside_min = ToDouble(v);

        else if(k=="wyARw")   cfg.wyck_ar_window_bars = ToInt(v);
        else if(k=="wyVolN")  cfg.wyck_vol_len = ToInt(v);
        else if(k=="wyVolM")  cfg.wyck_vol_mult = ToDouble(v);
      #endif

      else if(k=="xMTFZ")  cfg.extra_mtf_zones = ToBool(v);
      else if(k=="wZ1")    cfg.w_mtf_zone_h1 = ToDouble(v);
      else if(k=="wZ4")    cfg.w_mtf_zone_h4 = ToDouble(v);
      else if(k=="zMaxATR") cfg.mtf_zone_max_dist_atr = ToDouble(v);

      // Feature toggles
      else if(k=="vsa")    cfg.vsa_enable = ToBool(v);
      else if(k=="vsaMax") cfg.vsa_penalty_max = ToDouble(v);
      #ifdef CFG_HAS_VSA_ALLOW_TICK_VOLUME
        else if(k=="vsaTick"){ cfg.vsa_allow_tick_volume = ToBool(v); seenVsaTick=true; }
      #endif
      else if(k=="struct") cfg.structure_enable = ToBool(v);
      else if(k=="liq")    cfg.liquidity_enable = ToBool(v);
      else if(k=="corrS")  cfg.corr_softveto_enable = ToBool(v);

      // Post-confirm extras (DOM / correlation)
      else if(k=="xDOM")    cfg.extra_dom_imbalance = ToBool(v);
      else if(k=="wDOM")    cfg.w_dom_imbalance = ToDouble(v);
      else if(k=="domPad")  cfg.dom_zone_pad_points = ToInt(v);
      else if(k=="domMin")  cfg.dom_min_abs_imb = ToDouble(v);
      else if(k=="domDbg")  cfg.debug_dom = ToBool(v);
      
      // OBI aliases (same meaning as xDOM/wDOM)
      else if(k=="xOBI") cfg.extra_dom_imbalance = ToBool(v);
      else if(k=="wOBI") cfg.w_dom_imbalance = ToDouble(v);

      // Trendlines
      else if(k=="xTL") cfg.extra_trendlines = ToBool(v);
      else if(k=="wTL") cfg.w_trendlines = ToDouble(v);

      else if(k=="xCorr")    cfg.extra_correlation = ToBool(v);
      else if(k=="wCorr")    cfg.w_correlation = ToDouble(v);
      else if(k=="corrLb")   cfg.corr_lookback = ToInt(v);
      else if(k=="corrAbs")  cfg.corr_min_abs = ToDouble(v);
      else if(k=="corrRef")  cfg.corr_ref_symbol = v;
      
      else if(k=="scTF")  cfg.scan_tf_mask = ToInt(v);
      else if(k=="scInt") cfg.auto_scan_interval_sec = ToInt(v);
      else if(k=="scLB")  cfg.auto_scan_lookback_bars = ToInt(v);

      #ifdef CFG_HAS_SCAN_FVG_SETTINGS
        else if(k=="scFVGOn")   cfg.scan_fvg_enable = ToBool(v);
        else if(k=="scFVG5")    cfg.scan_fvg_tf_5m = ToBool(v);
        else if(k=="scFVG15")   cfg.scan_fvg_tf_15m = ToBool(v);
        else if(k=="scFVG1h")   cfg.scan_fvg_tf_1h = ToBool(v);

        else if(k=="scFVGAppr") cfg.scan_fvg_approach_atr = ToDouble(v);
        else if(k=="scFVGBrk")  cfg.scan_fvg_break_margin_atr = ToDouble(v);

        else if(k=="scFVGtZv")  cfg.scan_fvg_touch_zvol_min = ToDouble(v);
        else if(k=="scFVGbZv")  cfg.scan_fvg_breakout_zvol_min = ToDouble(v);
        else if(k=="scFVGtDz")  cfg.scan_fvg_touch_delta_min = ToDouble(v);
        else if(k=="scFVGbDz")  cfg.scan_fvg_breakout_delta_min = ToDouble(v);

        else if(k=="scFVGATR")  cfg.scan_fvg_use_atr_proxy = ToBool(v);
      #endif

      #ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
        #ifdef CFG_HAS_SCAN_TL_SETTINGS
          else if(k=="scTLOn")   cfg.scan_tl_enable = ToBool(v);
          else if(k=="scTLMskS") cfg.scan_tl_tf_mask_short = ToInt(v);
          else if(k=="scTLMskM") cfg.scan_tl_tf_mask_mid   = ToInt(v);
          else if(k=="scTLMskL") cfg.scan_tl_tf_mask_long  = ToInt(v);

          // Short bucket
          else if(k=="scTLSLB")    cfg.scan_tl_short_lookback_bars = ToInt(v);
          else if(k=="scTLSPL")    cfg.scan_tl_short_pivot_left    = ToInt(v);
          else if(k=="scTLSPR")    cfg.scan_tl_short_pivot_right   = ToInt(v);
          else if(k=="scTLSTch")   cfg.scan_tl_short_min_touches   = ToInt(v);
          else if(k=="scTLSTol")   cfg.scan_tl_short_tol_atr_mult = ToDouble(v);
          else if(k=="scTLSBrk")   cfg.scan_tl_short_break_atr_mult = ToDouble(v);
          else if(k=="scTLSDev")   cfg.scan_tl_short_dev_atr_mult   = ToDouble(v);
          else if(k=="scTLSMinPV") cfg.scan_tl_short_min_pivot_strength_atr = ToDouble(v);
          else if(k=="scTLSSrcP")  cfg.scan_tl_short_pivot_price_src = ToInt(v);
          else if(k=="scTLSSrcT")  cfg.scan_tl_short_touch_price_src = ToInt(v);
          else if(k=="scTLSSrcB")  cfg.scan_tl_short_break_price_src = ToInt(v);
          else if(k=="scTLSConf")  cfg.scan_tl_short_confirmed_only  = ToBool(v);

          // Mid bucket
          else if(k=="scTLMLB")    cfg.scan_tl_mid_lookback_bars = ToInt(v);
          else if(k=="scTLMPL")    cfg.scan_tl_mid_pivot_left    = ToInt(v);
          else if(k=="scTLMPR")    cfg.scan_tl_mid_pivot_right   = ToInt(v);
          else if(k=="scTLMTch")   cfg.scan_tl_mid_min_touches   = ToInt(v);
          else if(k=="scTLMTol")   cfg.scan_tl_mid_tol_atr_mult = ToDouble(v);
          else if(k=="scTLMBrk")   cfg.scan_tl_mid_break_atr_mult = ToDouble(v);
          else if(k=="scTLMDev")   cfg.scan_tl_mid_dev_atr_mult   = ToDouble(v);
          else if(k=="scTLMMinPV") cfg.scan_tl_mid_min_pivot_strength_atr = ToDouble(v);
          else if(k=="scTLMSrcP")  cfg.scan_tl_mid_pivot_price_src = ToInt(v);
          else if(k=="scTLMSrcT")  cfg.scan_tl_mid_touch_price_src = ToInt(v);
          else if(k=="scTLMSrcB")  cfg.scan_tl_mid_break_price_src = ToInt(v);
          else if(k=="scTLMConf")  cfg.scan_tl_mid_confirmed_only  = ToBool(v);

          // Long bucket
          else if(k=="scTLLLB")    cfg.scan_tl_long_lookback_bars = ToInt(v);
          else if(k=="scTLLPL")    cfg.scan_tl_long_pivot_left    = ToInt(v);
          else if(k=="scTLLPR")    cfg.scan_tl_long_pivot_right   = ToInt(v);
          else if(k=="scTLLTch")   cfg.scan_tl_long_min_touches   = ToInt(v);
          else if(k=="scTLLTol")   cfg.scan_tl_long_tol_atr_mult = ToDouble(v);
          else if(k=="scTLLBrk")   cfg.scan_tl_long_break_atr_mult = ToDouble(v);
          else if(k=="scTLLDev")   cfg.scan_tl_long_dev_atr_mult   = ToDouble(v);
          else if(k=="scTLLMinPV") cfg.scan_tl_long_min_pivot_strength_atr = ToDouble(v);
          else if(k=="scTLLSrcP")  cfg.scan_tl_long_pivot_price_src = ToInt(v);
          else if(k=="scTLLSrcT")  cfg.scan_tl_long_touch_price_src = ToInt(v);
          else if(k=="scTLLSrcB")  cfg.scan_tl_long_break_price_src = ToInt(v);
          else if(k=="scTLLConf")  cfg.scan_tl_long_confirmed_only  = ToBool(v);
        #endif

        else if(k=="scLiqOn") cfg.scan_liq_enable = ToBool(v);
        else if(k=="scLiq5")  cfg.scan_liq_tf_5m = ToBool(v);
        else if(k=="scLiq15") cfg.scan_liq_tf_15m = ToBool(v);
        else if(k=="scLiq1h") cfg.scan_liq_tf_1h = ToBool(v);
        else if(k=="scLiqSw") cfg.scan_liq_emit_sweeps = ToBool(v);

        else if(k=="scWyOn")    cfg.scan_wyck_enable = ToBool(v);
        else if(k=="scWyH4")    cfg.scan_wyck_tf_h4 = ToInt(v);
        else if(k=="scWyD1")    cfg.scan_wyck_tf_d1 = ToInt(v);
        else if(k=="scWyPh")    cfg.scan_wyck_emit_phase = ToBool(v);
        else if(k=="scWyPhZv")  cfg.scan_wyck_phase_zvol_min = ToDouble(v);
        else if(k=="scWyMnZv")  cfg.scan_wyck_manip_zvol_min = ToDouble(v);
        else if(k=="scWyLB4")   cfg.scan_wyck_lb_h4 = ToInt(v);
        else if(k=="scWyLBD1")  cfg.scan_wyck_lb_d1 = ToInt(v);

        else if(k=="scOBIOn")   cfg.scan_obi_enable = ToBool(v);
        else if(k=="scOBID")    cfg.scan_obi_depth_points = ToInt(v);
        else if(k=="scOBIThr")  cfg.scan_obi_threshold = ToDouble(v);
        else if(k=="scOBIVW")   cfg.scan_obi_vwap_enable = ToBool(v);
        else if(k=="scOBIKL")   cfg.scan_obi_keylevel_atr = ToDouble(v);

        else if(k=="scOBICms")  cfg.scan_obi_cache_ms = ToInt(v);
        else if(k=="scOBIMax")  cfg.scan_obi_max_levels = ToInt(v);
        else if(k=="scOBIMinV") cfg.scan_obi_min_tot_vol = ToDouble(v);
        else if(k=="scOBIVWDist") cfg.scan_obi_vwap_dist_atr = ToDouble(v);
        
        else if(k=="scOBIMode") cfg.scan_obi_mode = ToInt(v);
        else if(k=="scOBITop")  cfg.scan_obi_top_levels = ToInt(v);
        else if(k=="scOBIWOn")  cfg.scan_obi_weighted_enable = ToBool(v);
        else if(k=="scOBIWHL")  cfg.scan_obi_weight_half_life_points = ToDouble(v);
        else if(k=="scOBIEMA")  cfg.scan_obi_ema_len = ToInt(v);
        else if(k=="scOBIWRef") cfg.scan_obi_weight_ref = ToInt(v);
        
        else if(k=="scFootOn")  cfg.scan_foot_enable = ToBool(v);
        else if(k=="scFootATR") cfg.scan_foot_use_atr_proxy = ToBool(v);
        else if(k=="scFootZs")  cfg.scan_foot_zstrong = ToDouble(v);
        else if(k=="scFootZa")  cfg.scan_foot_zabsorb = ToDouble(v);
        else if(k=="scFootZd")  cfg.scan_foot_zdiverge = ToDouble(v);

        // OFIS
        else if(k=="scOFdE")  cfg.scan_of_delta_ema_len = ToInt(v);
        else if(k=="scOFcE")  cfg.scan_of_cvd_ema_len   = ToInt(v);
        else if(k=="scOFzL")  cfg.scan_of_z_len         = ToInt(v);

        else if(k=="scOFthr") cfg.scan_of_ofpi_thr      = ToDouble(v);
        else if(k=="scOFk")   cfg.scan_of_absorb_k_sigma= ToDouble(v);
        else if(k=="scOFm")   cfg.scan_of_absorb_m_atr  = ToDouble(v);

        else if(k=="scOFex")  cfg.scan_of_exhaust_lb    = ToInt(v);
        else if(k=="scOFhtf") cfg.scan_of_htf_mult      = ToInt(v);
        
        else if(k=="scFTickOn")  cfg.scan_foot_allow_ticks = ToBool(v);
        else if(k=="scFTickMax") cfg.scan_foot_ticks_max_tf_sec = ToInt(v);
        else if(k=="scFMinTk")   cfg.scan_foot_min_ticks = ToInt(v);

        // Tick classification (FootprintProxy)
        else if(k=="scFBA")    cfg.scan_foot_use_bidask_rule   = ToBool(v);
        else if(k=="scFBAeps") cfg.scan_foot_bidask_eps_points = ToDouble(v);
        
        else if(k=="scFBin")   cfg.scan_foot_bin_points = ToInt(v);
        else if(k=="scFMaxL")  cfg.scan_foot_max_levels = ToInt(v);
        else if(k=="scFVA")    cfg.scan_foot_value_area_pct = ToDouble(v);

        else if(k=="scFImbR")  cfg.scan_foot_imb_ratio = ToDouble(v);
        else if(k=="scFImbV")  cfg.scan_foot_imb_min_vol = ToDouble(v);
        else if(k=="scFStk")   cfg.scan_foot_stacked_levels = ToInt(v);

        else if(k=="scFAbsD")  cfg.scan_foot_absorb_depth_levels = ToInt(v);
        else if(k=="scFAbsR")  cfg.scan_foot_absorb_min_ratio = ToDouble(v);
        else if(k=="scFPOCap") cfg.scan_foot_poc_approach_atr = ToDouble(v);

        // Correlation (existing)
        else if(k=="scCorrOn")  cfg.scan_corr_enable    = ToBool(v);
        else if(k=="scCorrThr") cfg.scan_corr_threshold = ToDouble(v);
        else if(k=="scCorrRec") cfg.scan_corr_recover   = ToDouble(v);
        else if(k=="scCorrLen") cfg.scan_corr_len       = ToInt(v);
        
        #ifdef CFG_HAS_SCAN_CORR_DETECTOR_SETTINGS
           else if(k=="scCorrSym")  cfg.scan_corr_secondary_symbol = v;
           else if(k=="scCorrPx")   cfg.scan_corr_price            = (ENUM_APPLIED_PRICE)ToInt(v);
           else if(k=="scCorrLog")  cfg.scan_corr_use_log_returns  = ToBool(v);
           else if(k=="scCorrSm")   cfg.scan_corr_smooth_len       = ToInt(v);
           else if(k=="scCorrSens") cfg.scan_corr_div_sensitivity  = ToDouble(v);
           else if(k=="scCorrZL")   cfg.scan_corr_z_len            = ToInt(v);
           else if(k=="scCorrZt")   cfg.scan_corr_z_thr            = ToDouble(v);
           else if(k=="scCorrMk")   cfg.scan_corr_mom_k            = ToInt(v);
           else if(k=="scCorrMt")   cfg.scan_corr_mom_thr          = ToDouble(v);
           else if(k=="scCorrML")   cfg.scan_corr_mtf_len_enable   = ToBool(v);
        #endif

        else if(k=="scNewsOn")   cfg.scan_news_enable = ToBool(v);
        else if(k=="scNewsSoon") cfg.scan_news_soon_sec = ToInt(v);
        else if(k=="scNewsBlk")  cfg.scan_news_block_sec = ToInt(v);
        else if(k=="scNewsWin")  cfg.scan_news_emit_strat_windows = ToBool(v);

        else if(k=="scNewsStr")  cfg.scan_news_straddle_sec = ToInt(v);
        else if(k=="scNewsFade") cfg.scan_news_fade_sec = ToInt(v);
        else if(k=="scNewsBrk")  cfg.scan_news_breakout_sec = ToInt(v);
        else if(k=="scNewsSqz")  cfg.scan_news_breakout_squeeze_ratio = ToDouble(v);
        else if(k=="scNewsLB")   cfg.scan_news_breakout_lookback_bars = ToInt(v);

        else if(k=="scVPOn")    cfg.scan_vp_enable = ToBool(v);
        else if(k=="scVPLB")    cfg.scan_vp_lookback_bars = ToInt(v);
        else if(k=="scVPBin")   cfg.scan_vp_bin_points = ToInt(v);
        else if(k=="scVPVA")    cfg.scan_vp_value_area_pct = ToDouble(v);
        else if(k=="scVPTch")   cfg.scan_vp_touch_atr = ToDouble(v);
        else if(k=="scVPBrk")   cfg.scan_vp_break_margin_atr = ToDouble(v);
        else if(k=="scVPPoc")   cfg.scan_vp_poc_shift_atr = ToDouble(v);
        else if(k=="scVPStale") cfg.scan_vp_stale_sec = ToInt(v);
        else if(k=="scVPDist")  cfg.scan_vp_distribute_range = ToBool(v);
      #endif

      else if(k=="scLPAppr") cfg.scan_liq_pool_approach_atr = ToDouble(v);
      else if(k=="scLPConf") cfg.scan_liq_confirm_bars = ToInt(v);
      else if(k=="scLPWarm") cfg.scan_liq_warmup_bars = ToInt(v);
      else if(k=="scLPAcc")  cfg.scan_liq_accept_margin_atr = ToDouble(v);
      else if(k=="scLPRej")  cfg.scan_liq_reject_margin_atr = ToDouble(v);
      else if(k=="scLPStr")  cfg.scan_liq_struct_break_eps_atr = ToDouble(v);
      else if(k=="scLPZv")   cfg.scan_liq_min_zvol = ToDouble(v);

      // Liquidity Pools (Lux-style)
      else if(k=="liqMinTouch") cfg.liqPoolMinTouches = ToInt(v);
      else if(k=="liqGap")      cfg.liqPoolGapBars = ToInt(v);
      else if(k=="liqWait")     cfg.liqPoolConfirmWaitBars = ToInt(v);
      else if(k=="liqEpsATR")   cfg.liqPoolLevelEpsATR = ToDouble(v);
      else if(k=="liqLookback") cfg.liqPoolMaxLookbackBars = ToInt(v);
      else if(k=="liqSweepATR") cfg.liqPoolMinSweepATR = ToDouble(v);

      // Confluence blends
      #ifdef CFG_HAS_CONFL_BLEND_TREND
        else if(k=="cbTrend") cfg.confl_blend_trend = ToDouble(v);
      #endif
      #ifdef CFG_HAS_CONFL_BLEND_MR
        else if(k=="cbMR") cfg.confl_blend_mr = ToDouble(v);
      #endif
      #ifdef CFG_HAS_CONFL_BLEND_OTHERS
        else if(k=="cbOther") cfg.confl_blend_others = ToDouble(v);
      #endif
      #ifdef CFG_HAS_ML_THRESHOLD
        else if(k=="mlTh") cfg.ml_threshold = ToDouble(v);
      #endif

      #ifdef CFG_HAS_ML_SETTINGS
        else if(k=="mlOn")   cfg.ml_enable = ToBool(v);
        else if(k=="mlW")    cfg.ml_weight = ToDouble(v);
        else if(k=="mlT")    cfg.ml_temperature = ToDouble(v);
        else if(k=="mlCA")   cfg.ml_conformal_alpha = ToDouble(v);
        else if(k=="mlD")    cfg.ml_dampen = ToDouble(v);
      
        #ifdef CFG_HAS_ML_SLTP_MULT
         else if(k=="mlSltpOn")    cfg.ml_sltp_enable = ToBool(v);
         else if(k=="mlSltpSLmin") cfg.ml_sltp_sl_min = ToDouble(v);
         else if(k=="mlSltpSLmax") cfg.ml_sltp_sl_max = ToDouble(v);
         else if(k=="mlSltpTPmin") cfg.ml_sltp_tp_min = ToDouble(v);
         else if(k=="mlSltpTPmax") cfg.ml_sltp_tp_max = ToDouble(v);
        #endif

        else if(k=="mlAuto") cfg.ml_auto_calibrate = ToBool(v);
        else if(k=="mlAgeH") cfg.ml_model_max_age_hours = ToInt(v);
        else if(k=="mlAUC")  cfg.ml_min_oos_auc = ToDouble(v);
        else if(k=="mlACC")  cfg.ml_min_oos_acc = ToDouble(v);
        else if(k=="mlTrN")  cfg.ml_min_samples_train = ToInt(v);
        else if(k=="mlTeN")  cfg.ml_min_samples_test  = ToInt(v);
      
        else if(k=="mlHor")  cfg.ml_label_horizon_bars = ToInt(v);
        else if(k=="mlATR")  cfg.ml_label_atr_mult = ToDouble(v);
      
        else if(k=="mlCom")  cfg.ml_use_common_files = ToBool(v);
        else if(k=="mlFile") cfg.ml_model_file = v;
        else if(k=="mlData") cfg.ml_dataset_file = v;
      
        else if(k=="mlExt")  cfg.ml_external_enable = ToBool(v);
        else if(k=="mlExtM") cfg.ml_external_mode = ToInt(v);
        else if(k=="mlExtF") cfg.ml_external_file = v;
        else if(k=="mlExtMs")cfg.ml_external_poll_ms = ToInt(v);
        else if(k=="mlHost") cfg.ml_external_socket_host = v;
        else if(k=="mlPort") cfg.ml_external_socket_port = ToInt(v);
      #endif

      // Carry knobs
      #ifdef CFG_HAS_CARRY_ENABLE
        else if(k=="carry") cfg.carry_enable = ToBool(v);
      #endif
      #ifdef CFG_HAS_CARRY_BOOST_MAX
        else if(k=="carryBoost") cfg.carry_boost_max = ToDouble(v);
      #endif
      #ifdef CFG_HAS_CARRY_RISK_SPAN
        else if(k=="carrySpan") cfg.carry_risk_span = ToDouble(v);
      #endif
      #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
        else if(k=="mainAny3") cfg.main_confirm_any_of_3 = ToBool(v);
      #endif
      #ifdef CFG_HAS_ORDERFLOW_TH
        else if(k=="ofTh") cfg.orderflow_th = ToDouble(v);
      #endif

      // Router hints / gates
      #ifdef CFG_HAS_ROUTER_MIN_SCORE
        else if(k=="routerMin") cfg.router_min_score = ToDouble(v);
      #endif
      #ifdef CFG_HAS_ROUTER_MAX_STRATS
        else if(k=="routerCap") cfg.router_max_strats = ToInt(v);
      #endif

      #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
        else if(k=="routerPool") cfg.router_use_confl_pool = ToBool(v);
      #endif
      #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
        else if(k=="routerPoolW") cfg.router_pool_blend_w = ToDouble(v);
      #endif

      // hard gate + required features
      #ifdef CFG_HAS_ENABLE_HARD_GATE
        else if(k=="hardGate") cfg.enable_hard_gate = ToBool(v);
      #endif
      #ifdef CFG_HAS_MIN_FEATURES_MET
        else if(k=="minFeat") cfg.min_features_met = ToInt(v);
      #endif
      #ifdef CFG_HAS_REQUIRE_TREND_FILTER
        else if(k=="reqTrend") cfg.require_trend_filter = ToBool(v);
      #endif
      #ifdef CFG_HAS_REQUIRE_ADX_REGIME
        else if(k=="reqADX") cfg.require_adx_regime = ToBool(v);
      #endif
      #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
        else if(k=="reqStructOrOB") cfg.require_struct_or_pattern_ob = ToBool(v);
      #endif
      #ifdef CFG_HAS_LONDON_LIQ_POLICY
        else if(k=="lonPolicy") cfg.london_liquidity_policy = ToBool(v);
      #endif

      // Router fallback min key (serializer writes routerFBMin no matter which alias exists)
      else if(k=="routerFBMin")
      {
        const double fb = ToDouble(v);
        #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
          cfg.router_fallback_min_score = fb;
        #endif
        #ifdef CFG_HAS_ROUTER_FB_MIN
          cfg.router_fb_min = fb;
        #endif
      }

      #ifdef CFG_HAS_ROUTER_HINTS
        else if(k=="fbConf") cfg.router_fallback_min_confluence = ToDouble(v);
        else if(k=="fbSpan") cfg.router_fallback_max_span = ToInt(v);
        else if(k=="routerAlias") cfg.router_profile_alias = v;
      #endif

      // Strategy mode (if serialized)
      #ifdef CFG_HAS_STRAT_MODE
        else if(k=="sMode")
          _SetStratModeRef(cfg.strat_mode, ToInt(v));
      #endif
      #ifdef CFG_HAS_ENABLE_PACK_STRATS
        else if(k=="packOn") cfg.enable_pack_strats = ToBool(v);
      #endif
      #ifdef CFG_HAS_DISABLE_PACKS
        else if(k=="packsOff") cfg.disable_packs = ToBool(v);
      #endif

      // Optional magic number
      #ifdef CFG_HAS_MAGIC_NUMBER
        else if(k=="magic")
          cfg.magic_number = (long)ToLong(v);
      #endif
      
      #ifdef CFG_HAS_ENABLE_HARD_GATE
         else if(k=="hardGate") cfg.enable_hard_gate = ToBool(v);
      #endif
      #ifdef CFG_HAS_MIN_FEATURES_MET
         else if(k=="minFeat")  cfg.min_features_met  = ToInt(v);
      #endif
      #ifdef CFG_HAS_REQUIRE_TREND_FILTER
         else if(k=="reqTrend") cfg.require_trend_filter = ToBool(v);
      #endif
      #ifdef CFG_HAS_REQUIRE_ADX_REGIME
         else if(k=="reqADX")   cfg.require_adx_regime   = ToBool(v);
      #endif
      #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
         else if(k=="reqStructOrOB") cfg.require_struct_or_pattern_ob = ToBool(v);
      #endif
      #ifdef CFG_HAS_LONDON_LIQ_POLICY
         else if(k=="lonPolicy") cfg.london_liquidity_policy = ToBool(v);
      #endif
      #ifdef CFG_HAS_ROUTER_HINTS
        else if(k=="fbConf") cfg.router_fallback_min_confluence = ToDouble(v);
        else if(k=="fbSpan") cfg.router_fallback_max_span = ToInt(v);
      #endif
    }
    
    #ifdef CFG_HAS_MAIN_REQUIRE_CHECKLIST
      if(!seenMainReq) cfg.main_require_checklist = true;
    #endif
    #ifdef CFG_HAS_MAIN_CONFIRM_ANY_OF_3
      if(!seenMainAny3) cfg.main_confirm_any_of_3 = true;
    #endif
    #ifdef CFG_HAS_MAIN_REQUIRE_CLASSICAL
      if(!seenMainCls) cfg.main_require_classical = false;
    #endif
    #ifdef CFG_HAS_VSA_ALLOW_TICK_VOLUME
      if(!seenVsaTick) cfg.vsa_allow_tick_volume = true;
    #endif

    Normalize(cfg);
    _SyncRouterFallbackAlias(cfg);
    FinalizeThresholds(cfg);
    string warns=""; Validate(cfg, warns); if(warns!="") Print("LoadSettingsCSV warnings:\n", warns); if(warns!="") Print("Config warnings:\n", warns);
    Print("Settings loaded from CSV: ", fn);
    return true;
  }
} // namespace Config

// -----------------------------------------------------------------------------
// Settings
//
// This struct is passed everywhere (Router -> Strategy -> Execution).
// If any module needs to understand config, it must include Config.mqh
// and use this struct.
//
// NOTE: If you had an older struct Settings in Types.mqh, delete it and
// migrate those fields here to avoid duplicate definitions.
//
// Sections below:
//   1. Existing core fields (keep your originals here)
//   2. Bias / direction control
//   3. Strategy enable toggles
//   4. Magic bases & risk multipliers
//   5. Quality thresholds
//   6. Runtime overrides (Router fills per strategy)
// -----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Optional confluence breakdown capture (Router "Top-N with reason")
// ----------------------------------------------------------------------------
#ifndef CFG_HAS_CONFLUENCE_BREAKDOWN
  #define CFG_HAS_CONFLUENCE_BREAKDOWN 1
#endif

#ifdef CFG_HAS_CONFLUENCE_BREAKDOWN
inline void ConfluenceBreakdown_Reset(ConfluenceBreakdown &b)
{
  b.obi_signed = 0.0; b.obi_score = 0.0;
  b.tl_signed  = 0.0; b.tl_score  = 0.0; b.tl_dist_atr = 0.0;
  b.ph_signed  = 0.0; b.ph_score  = 0.0;
}
#endif

// ================================ SETTINGS ==================================
/*
  Mutable runtime configuration used by Policies/Router/Risk/PM/Strategies.
  Fields are grouped; many are always present. Optional knobs appear under
  CFG_HAS_* for compile safety with legacy codebases.
*/
struct Settings
{
  // -------------------------------------------------
  // 1. EXISTING CORE FIELDS
  // -------------------------------------------------
  // --- Assets / TFs ---------------------------------------------------------
  string            asset_list[];        // parsed from CSV or {"CURRENT"}
  ENUM_TIMEFRAMES   tf_entry;            // primary evaluation TF
  ENUM_TIMEFRAMES   tf_h1;
  ENUM_TIMEFRAMES   tf_h4;
  ENUM_TIMEFRAMES   tf_d1;
  ENUM_TIMEFRAMES   tf_htf;              // higher timeframe reference
  ENUM_TIMEFRAMES   tf_trend_htf;        // HTF used for trend filters (0 => use tf_h4)
  double            risk_per_trade;      // base %/bp or lot logic
  bool              newsFilterEnabled;   // block entries near high-impact news

  // --- Mode & selection -----------------------------------------------------
  ENUM_TRADE_DIRECTION  trade_direction_selector;
  BasketMode            mode;
  TradeSelector         trade_selector;
  #ifdef CFG_HAS_UMBRELLA
    int                 umbrella_mode;      // UmbrellaMode (0=ALL,1=TREND,2=MEAN)
  #endif
  // Directional bias gating (manual vs ICT auto; see Config::DirectionBiasMode)
  int                   direction_bias_mode; // 0=manual, 1=smart money

  // --- Risk core (RiskEngine) ----------------------------------------------
  double            risk_pct;            // % balance per trade (e.g., 1.00 = 1%)
  double            risk_cap_pct;        // hard cap per trade (% balance)
  #ifdef CFG_HAS_RISK_MULT_MAX
  double            risk_mult_max;       // cap for any risk multiplier scaling
  #endif
  
  double            min_sl_pips;         // SL floor (pips)
  double            min_tp_pips;         // TP floor (pips)
  double            max_sl_ceiling_pips; // SL ceiling (pips)
  int               atr_period;          // ATR period for sizing/filters
  double            atr_sl_mult;         // SL = ATR * mult
  double            tp_quantile;         // 0..1 ATRQ to target
  double            tp_minr_floor;       // TP ≥ R*SL
  
  #ifdef CFG_HAS_FIB_MIN_RR_ALLOWED
  double            fib_min_rr_allowed;  // e.g. 1.5 → require ≥1.5R to fib TP
  #endif
  
  // --- Fib / OTE configuration ----------------------------------------------
  int                fibDepth;              // zigzag depth for swing detection
  int                fibATRPeriod;          // ATR period used for OTE tolerance
  double             fibDevATRMult;         // how many ATRs from mean for swing dev
  int                fibMaxBarsBack;        // how far we search swings
  
  #ifdef CFG_HAS_FIB_SETTINGS
  bool               fibUseLogScale;          // compute in log(price) space (optional; big % swings)
  double             fibOTE_Low;              // OTE band low  (default 0.618)
  double             fibOTE_High;             // OTE band high (default 0.786)

  // IMPORTANT: must NOT contain commas because CanonicalCSV uses ',' as KV separator.
  // Use ';' separated ratios: "0;0.236;0.382;0.5;0.618;0.786;0.886;1"
  string             fibRetraceRatiosCSV;     // retracement ratios list
  string             fibExtensionRatiosCSV;   // extension ratios list (targets)

  bool               fibExpansionEnable;      // ABC expansion (3-point extension) enable
  double             fibMinLegHeightATR;      // minimum impulse leg height in ATR
  int                fibMinLegBars;           // minimum bars in impulse leg
  double             fibApproachATRMult;      // "near level" threshold = ATR * mult
  #endif

  bool               fibUseConfluence;      // combine with OB/FVG/liquidity
  double             fibMinConfluenceScore; // 0..1 confluence floor
  double             fibOTEToleranceATR;    // max distance from ideal OTE band (in ATR)
  double             fibOTEQualityBonusReversal; // extra bump for reversal setups

  // --- Fib RR gating ---
  double             minRRFibAllowed;   // minimum allowed R:R from fib TP1 to SL
  bool               fibRRHardReject;   // if true, block trade when below threshold

  // --- Day limits / taper ------------------------------------------å---------
  double            max_daily_dd_pct;    // DAILY hard-stop (% of INITIAL equity; money-based cap enforced in Policies)
  #ifdef CFG_HAS_DAY_DD_LIMIT_PCT
  double            day_dd_limit_pct;    // onset of risk taper (RiskEngine), e.g., 2.0
  #endif
  
  // --- Adaptive DD (rolling peak) ---------------------------------------------
  #ifdef CFG_HAS_ADAPTIVE_DD_ENABLE
  bool              adaptive_dd_enable;
  #endif
  #ifdef CFG_HAS_ADAPTIVE_DD_WINDOW_DAYS
  int               adaptive_dd_window_days;
  #endif
  #ifdef CFG_HAS_ADAPTIVE_DD_PCT
  double            adaptive_dd_pct;     // percent of rolling peak
  #endif

  // --- Big-loss reset latch ---------------------------------------------------
  #ifdef CFG_HAS_BIGLOSS_RESET_ENABLE
  bool              bigloss_reset_enable;
  #endif
  #ifdef CFG_HAS_BIGLOSS_RESET_R
  double            bigloss_reset_r;     // reset trigger at or below -R
  #endif
  #ifdef CFG_HAS_BIGLOSS_RESET_MINS
  int               bigloss_reset_mins;  // cooldown after big loss
  #endif
  
  int               max_losses_day;      // legacy (count)
  int               max_trades_day;      // trades/day cap (RiskEngine)
  
  int               max_positions_per_symbol; // <=0 treated as 1 (safe default)
  int               max_positions_total;      // <=0 treated as 0 (0 = unlimited)

  double            day_loss_cap_pct;    // realized P/L cap (% of start eq)
  double            day_loss_cap_money;  // realized P/L cap (money)

  double            day_profit_cap_pct;  // start tapering profits
  double            day_profit_stop_pct; // max profit (after which taper floor)
  double            taper_floor;         // min risk scale during taper
  
  // --- Monthly profit target (vs month-start equity) ------------------------
  #ifdef CFG_HAS_MONTHLY_TARGET
    // Configured target in PERCENT units (1.0 = 1%, 10.0 = 10%)
    double monthly_target_pct;

    // Monthly target cycle/base modes (Config contract)
    // NOTE: Policies decides how to apply these; Config only clamps/standardizes values.
    int monthly_target_cycle_mode; // CFG_TARGET_CYCLE_* (0=calendar, 1=rolling_28d)
    int monthly_target_base_mode;  // CFG_TARGET_BASE_*  (0=cycle_start, 1=initial_linear, 2=initial_compound)

    // Runtime state managed by Policies::_EnsureMonthState():
    // - baseline: equity snapshot at first detection of this calendar month
    // - peak:     highest observed equity since baseline
    // - hit:      once true, Policies gate new trades for the remainder of the month
    double monthly_baseline_equity;
    double monthly_peak_equity;
    bool   monthly_target_hit;
  #endif
  
  // --- ICT context / strategy quality thresholds (0..1) ---------------------
  double            qualityThresholdHigh;          // "high conviction" setups
  double            qualityThresholdContinuation;  // trend / continuation models
  double            qualityThresholdReversal;      // Wyckoff Spring/UTAD reversals
  
  // --- Challenge protection (account-wide) -----------------------------------
  double          challenge_init_equity;  // 0.0 => auto-capture at first run
  double          max_account_dd_pct;     // e.g., 5.0 => stop trading at -5% from baseline

  #ifdef CFG_HAS_DAILY_DD_HARDSTOP
    bool            daily_dd_hardstop;   // kill-switch when DD breach
  #endif
  
  // --- ATR dampening / ADR caps --------------------------------------------
  #ifdef CFG_HAS_ATR_DAMPEN
    double          atr_dampen_k;        // 0..1 dampening strength
    double          atr_dampen_floor;    // 0..1 floor for scaler
  #endif
  #ifdef CFG_HAS_ADR_CAP_MULT
    double          adr_cap_mult;        // e.g., 2.2 → veto/scale above ADR*2.2
  #endif
  #ifdef CFG_HAS_ADR_LOOKBACK
    int             adr_lookback_days;   // ADR lookback
  #endif

  // --- Carry bias risk scaler (optional) ------------------------------------
  #ifdef CFG_HAS_CARRY_BIAS_ENABLE
    bool            carry_bias_enable;
  #endif
  #ifdef CFG_HAS_CARRY_BIAS_MAX
    double          carry_bias_max;      // max swing (0..1), e.g., 0.15
  #endif

  // --- Carry knobs (profiles & router defaults) -----------------------------
  #ifdef CFG_HAS_CARRY_ENABLE
    bool            carry_enable;        // master carry feature toggle
  #endif
  #ifdef CFG_HAS_CARRY_BOOST_MAX
    double          carry_boost_max;     // max boost for pro-carry signals
  #endif
  #ifdef CFG_HAS_CARRY_RISK_SPAN
    double          carry_risk_span;     // span for risk modulation
  #endif

  // --- Broker/exec frictions ------------------------------------------------
  int               max_spread_points;
  int               slippage_points;
  long              magic_number;
  
  // --- AutoVol cache (MarketData 5.6) ---
  int               auto_vol_cache_hours;        // 24 = daily (aligned to closed D1); otherwise N-hour cadence
  int               auto_vol_adr_lookback_days;  // ADR range distribution lookback (days)
  int               auto_vol_ret_lookback_d1;    // D1 return sigma lookback (bars)

  // --- Loop / timing --------------------------------------------------------
  bool              only_new_bar;
  int               timer_ms;
  int               server_offset_min;

  // --- Sessions (manual windows in UTC minutes) -----------------------------
  bool              session_filter;
  int               london_open_utc;
  int               london_close_utc;
  int               ny_open_utc;
  int               ny_close_utc;

  // Preset & regional anchors
  SessionPreset     session_preset;      // OFF or one of the presets
  int               tokyo_close_utc;     // minutes-of-day UTC
  int               sydney_open_utc;     // minutes-of-day UTC
  
  // ===== Base Confluence Gate =====
   int    cf_min_needed;     // how many checks must pass
   double cf_min_score;      // weighted min-score (0..1)
   bool   main_sequential_gate;
   bool   main_require_checklist;  // default true: enforce checklist scoring
   bool   main_confirm_any_of_3;   // default true: allow any-of-3 confirmation rule
   bool   main_require_classical;  // optional: require “classical confirm” rule if enabled
   double orderflow_th;            // threshold for orderflow/Δ gate (z or accel threshold)
   
   // ===== Base Confluence Toggles =====
   bool cf_inst_zones;       // Institutional zones
   bool cf_orderflow_delta;  // Δ volume
   bool cf_orderblock_near;  // OB near SD
   bool cf_candle_pattern;   // Candle patterns
   bool cf_chart_pattern;    // Chart patterns
   bool cf_market_structure; // HH/HL/LH/LL, pivots
   bool cf_trend_regime;     // trend vs mean + ADX
   bool cf_stochrsi;         // StochRSI confirm
   bool cf_macd;             // MACD confirm
   bool cf_correlation;      // Cross-symbol confirm
   bool cf_news_ok;          // News filter as confluence
   
   // ===== Base Confluence Weights =====
   double w_inst_zones;
   double w_orderflow_delta;
   double w_orderblock_near;
   double w_candle_pattern;
   double w_chart_pattern;
   double w_market_structure;
   double w_trend_regime;
   double w_stochrsi;
   double w_macd;
   double w_correlation;
   double w_news;
   
   // --- Autochartist-style internal scanner (local computation) ---
   bool   auto_enable;
   int    auto_provider;       // 0=local, 1=API, 2=hybrid (API+local fallback)
   string auto_api_base_url;   // API base URL (empty => local-only)
   string auto_api_user;
   string auto_api_pass;

   int    auto_tf_mask;        // bitmask (0 => use tf_entry)
   int    scan_tf_mask;
   double auto_min_quality;    // master fallback [0..1] (0 => disabled)

   // compat aliases (keep w_autochartist_* as canonical)
   double auto_weight_chart;
   double auto_weight_fib;
   double auto_weight_key;
   double auto_weight_vol;

   int    auto_scan_interval_sec;
   int    auto_scan_lookback_bars;
   
   // --- Autochartist patterns export (single source of truth) ---
   int    autoc_patt_export_level;   // Config::AutoPattExportLevel (0..3)
   int    autoc_patt_emit_mode;      // Config::AutoPattEmitMode (0..2)
   int    autoc_patt_topN;           // cap for flattened bank (FULL only)

   double autoc_patt_min_score01;        // global min score [0..1]
   double autoc_patt_min_score_autoc;    // <0 => inherit global
   double autoc_patt_min_score_candle;   // <0 => inherit global
   double autoc_patt_min_score_classic;  // <0 => inherit global
   double autoc_patt_min_score_sd;       // <0 => inherit global

   // --- Legacy AutoPattAll knobs (DEPRECATED; derived from autoc_patt_* in Normalize()) ---
   #ifdef CFG_HAS_AUTO_PATT_ALL_SETTINGS_FIELDS
     bool   auto_patt_all_enable;
     int    auto_patt_all_emit_mode;
     int    auto_patt_all_topN;

     double auto_patt_all_min_score01;
     double auto_patt_all_min_score_autoc;
     double auto_patt_all_min_score_candle;
     double auto_patt_all_min_score_classic;
     double auto_patt_all_min_score_sd;
   #endif
   
   // --- Additional scanners (structured scans) ---
#ifdef CFG_HAS_SCAN_FVG_SETTINGS
  bool   scan_fvg_enable;              // master toggle for FVG scanner events
  // Per-TF gating for FVG scanner
  bool scan_fvg_tf_5m;
  bool scan_fvg_tf_15m;
  bool scan_fvg_tf_1h;
  double scan_fvg_approach_atr;         // ATR-multiple proximity band (approach emit)
  double scan_fvg_break_margin_atr;     // ATR-multiple beyond boundary to qualify breakout

  // Volume confirmation thresholds (reuse VSA zVol + DeltaProxy alignment)
  double scan_fvg_touch_zvol_min;       // min zVol for "confirmed" touch/mitigation
  double scan_fvg_breakout_zvol_min;    // min zVol for breakout emit
  double scan_fvg_touch_delta_min;      // min |delta z| alignment threshold for touch
  double scan_fvg_breakout_delta_min;   // min |delta z| alignment threshold for breakout
  bool   scan_fvg_use_atr_proxy;        // allow ATR-based proxy when real delta/session delta isn't reliable
#endif
#ifdef CFG_HAS_SCAN_EXTRA_SETTINGS
   // Reserved toggles (no logic wired in this response; keeps IDs stable later)
   #ifdef CFG_HAS_SCAN_TL_SETTINGS
   // Trendlines scanner (3 independent buckets: short / mid / long)
   bool scan_tl_enable;
   int  scan_tl_tf_mask_short;
   int  scan_tl_tf_mask_mid;
   int  scan_tl_tf_mask_long;
   
   // Short bucket
   int    scan_tl_short_lookback_bars;
   int    scan_tl_short_pivot_left;
   int    scan_tl_short_pivot_right;
   int    scan_tl_short_min_touches;
   double scan_tl_short_tol_atr_mult;
   double scan_tl_short_break_atr_mult;
   double scan_tl_short_dev_atr_mult;
   double scan_tl_short_min_pivot_strength_atr;
   int    scan_tl_short_pivot_price_src;   // 0=WICK, 1=BODY, 2=CLOSE (matches TL_PriceSource)
   int    scan_tl_short_touch_price_src;   // 0=WICK, 1=BODY, 2=CLOSE
   int    scan_tl_short_break_price_src;   // 0=WICK, 1=BODY, 2=CLOSE
   bool   scan_tl_short_confirmed_only;
   
   // Mid bucket
   int    scan_tl_mid_lookback_bars;
   int    scan_tl_mid_pivot_left;
   int    scan_tl_mid_pivot_right;
   int    scan_tl_mid_min_touches;
   double scan_tl_mid_tol_atr_mult;
   double scan_tl_mid_break_atr_mult;
   double scan_tl_mid_dev_atr_mult;
   double scan_tl_mid_min_pivot_strength_atr;
   int    scan_tl_mid_pivot_price_src;
   int    scan_tl_mid_touch_price_src;
   int    scan_tl_mid_break_price_src;
   bool   scan_tl_mid_confirmed_only;
   
   // Long bucket
   int    scan_tl_long_lookback_bars;
   int    scan_tl_long_pivot_left;
   int    scan_tl_long_pivot_right;
   int    scan_tl_long_min_touches;
   double scan_tl_long_tol_atr_mult;
   double scan_tl_long_break_atr_mult;
   double scan_tl_long_dev_atr_mult;
   double scan_tl_long_min_pivot_strength_atr;
   int    scan_tl_long_pivot_price_src;
   int    scan_tl_long_touch_price_src;
   int    scan_tl_long_break_price_src;
   bool   scan_tl_long_confirmed_only;
   #endif

   bool scan_liq_enable;
   // Liquidity per-TF gating + emit controls
   bool scan_liq_tf_5m;
   bool scan_liq_tf_15m;
   bool scan_liq_tf_1h;
   bool scan_liq_emit_sweeps;

   bool scan_wyck_enable;
   
   // Optional TF override (0 = use defaults in Confluence: H4/D1)
   int scan_wyck_tf_h4;
   int scan_wyck_tf_d1;

   // Wyckoff scanner semantics (phase + manipulation + VSA confirmation)
   bool   scan_wyck_emit_phase;        // emit SC_WYCK_ACCUM / SC_WYCK_DISTRIB on phase change; emit SC_WYCK_MANIP on spring/UTAD
   double scan_wyck_phase_zvol_min;    // min VSA zVol to treat phase-change / breakout as "confirmed"
   double scan_wyck_manip_zvol_min;    // min VSA zVol (or climax) to boost/confirm manipulation (spring/UTAD)
   int    scan_wyck_lb_h4;             // lookback bars for H4 phase detect (WyckoffCycle)
   int    scan_wyck_lb_d1;             // lookback bars for D1 phase detect (WyckoffCycle)

   bool scan_obi_enable;
   
   // OBI scanner (config-driven)
   int    scan_obi_depth_points;   // DOM band depth in points (e.g. 25)
   double scan_obi_threshold;      // imbalance threshold (e.g. 0.30)
   bool   scan_obi_vwap_enable;    // enable VWAP-filtered OBI emits
   double scan_obi_keylevel_atr;   // gating distance: within X * ATR of key level
   
   // OBI compute tuning (wired into OrderBookImbalance::Settings)
   int    scan_obi_cache_ms;
   int    scan_obi_max_levels;
   double scan_obi_min_tot_vol;
   
   // Optional VWAP distance gating (ATR multiples; 0 disables)
   double scan_obi_vwap_dist_atr;

   // OBI advanced metric mode / aggregation (Option A: explicit, clean)
   int    scan_obi_mode;                    // 0=symmetric, 1=ratio-1, 2=log-ratio, 3=proxy-footprint fallback
   int    scan_obi_top_levels;              // 0=disabled; else true Top-N price levels per side
   bool   scan_obi_weighted_enable;         // enable near-price weighted aggregation
   double scan_obi_weight_half_life_points; // half-life for exp weighting in points
   int    scan_obi_ema_len;                 // 0/1=disabled; >=2 enables EMA over selected OBI metric
   int    scan_obi_weight_ref;              // 0=MID, 1=CENTER, 2=BEST (default 0)
   bool scan_foot_enable;
   
   // Footprint / delta (orderflow-lite) tuning
   bool   scan_foot_use_atr_proxy;  // use ATR proxy when session delta isn't reliable
   double scan_foot_zstrong;        // strong delta threshold (|z|)
   double scan_foot_zabsorb;        // absorption threshold (|z|)
   double scan_foot_zdiverge;       // divergence threshold (|z|)

   // ---------------- OFIS (Order Flow Imbalance System) tuning ----------------
   int    scan_of_delta_ema_len;       // delta smoothing EMA length (spec: 14)
   int    scan_of_cvd_ema_len;         // CVD EMA length (spec: 20)
   int    scan_of_z_len;               // z-score window for OFIS (spec: 50)
   double scan_of_ofpi_thr;            // OFPI threshold in [-100..+100] (spec: 40)

   double scan_of_absorb_k_sigma;      // k * sigma threshold (spec: 1.5)
   double scan_of_absorb_m_atr;        // price move < m * ATR (spec: 0.5)

   int    scan_of_exhaust_lb;          // exhaustion lookback (spec: 5)
   int    scan_of_htf_mult;            // HTF multiplier (spec: 4)
    
   bool scan_corr_enable;
   double scan_corr_threshold;   // abs(corr) threshold to classify "strong"
   double scan_corr_recover;     // abs(corr) <= this => "weak" (hysteresis)
   int    scan_corr_len;         // lookback bars for Pearson returns + zscore sample
   
   string            scan_corr_secondary_symbol; // optional hard override; else uses corrRef/auto basket
   ENUM_APPLIED_PRICE scan_corr_price;           // PRICE_CLOSE / PRICE_OPEN / PRICE_MEDIAN / PRICE_TYPICAL / PRICE_WEIGHTED
   bool              scan_corr_use_log_returns;  // default true
   int               scan_corr_smooth_len;       // default 5 (EMA on corr stream)
   double            scan_corr_div_sensitivity;  // default 0.30
   int               scan_corr_z_len;            // default 200 (rolling window for corr-z)
   int               scan_corr_mom_k;            // default 5
   double            scan_corr_z_thr;            // default 2.0  (|z| trigger)
   double            scan_corr_mom_thr;          // default 0.20 (|mom| trigger)
   bool              scan_corr_mtf_len_enable;   // optional: enable multi-length check

   bool scan_news_enable;
   int scan_news_soon_sec;
   int scan_news_block_sec;
   bool scan_news_emit_strat_windows;
   int scan_news_straddle_sec;
   int scan_news_fade_sec;
   int scan_news_breakout_sec;
   double scan_news_breakout_squeeze_ratio;
   int scan_news_breakout_lookback_bars;

    // --- Footprint proxy (backend-only) ---
    bool   scan_foot_allow_ticks;
    int    scan_foot_ticks_max_tf_sec;
    int    scan_foot_min_ticks;

    // Tick classification (OFIS preferred path)
    bool   scan_foot_use_bidask_rule;     // prefer last>=ask / last<=bid classification when quotes exist
    double scan_foot_bidask_eps_points;   // eps in POINTS for bid/ask rule comparisons (0..5 typical)
     
    int    scan_foot_bin_points;
    int    scan_foot_max_levels;

    double scan_foot_value_area_pct;

    double scan_foot_imb_ratio;
    double scan_foot_imb_min_vol;
    int    scan_foot_stacked_levels;

    int    scan_foot_absorb_depth_levels;
    double scan_foot_absorb_min_ratio;

    double scan_foot_poc_approach_atr;

   // Volume Profile scanner
   bool   scan_vp_enable;
   int    scan_vp_lookback_bars;       // histogram build lookback (closed bars)
   int    scan_vp_bin_points;          // bin size in points (auto-adjusts if too many bins)
   double scan_vp_value_area_pct;      // 0.70 = 70% VA
   double scan_vp_touch_atr;           // touch band in ATR multiples
   double scan_vp_break_margin_atr;    // breakout margin beyond VAH/VAL in ATR multiples
   double scan_vp_poc_shift_atr;       // emit POC shift if moves > X * ATR
   int    scan_vp_stale_sec;           // rebuild if cache older than this
   bool   scan_vp_distribute_range;    // distribute bar weight over range (slower)
#endif
   
   double scan_liq_pool_approach_atr;      // e.g. 0.35
   int    scan_liq_confirm_bars;           // e.g. 6
   int    scan_liq_warmup_bars;            // e.g. 600
   double scan_liq_accept_margin_atr;      // e.g. 0.15
   double scan_liq_reject_margin_atr;      // e.g. 0.10
   double scan_liq_struct_break_eps_atr;   // e.g. 0.05
   double scan_liq_min_zvol;               // e.g. 1.0 (reuse VSA zVol)

   // Main confluence toggles
   bool   cf_autochartist_chart;
   bool   cf_autochartist_fib;
   bool   cf_autochartist_keylevels;
   bool   cf_autochartist_volatility;
   
   // Main confluence weights
   double w_autochartist_chart;
   double w_autochartist_fib;
   double w_autochartist_keylevels;
   double w_autochartist_volatility;
   
   // Chart patterns (local)
   double auto_chart_min_quality;
   int    auto_chart_pivot_L;
   int    auto_chart_pivot_R;
   
   // SD base patterns (RBR/DBD/RBD/DBR) detector tuning
   #ifdef CFG_HAS_PATTERNS_SD_SETTINGS
     int    sd_atr_period;           // ATR lookback for base/range sizing
     int    sd_base_min_bars;        // minimum base bars (consolidation width)
     int    sd_base_max_bars;        // maximum base bars (cap for base window)
     double sd_min_move_atr;         // prior leg size threshold (ATR multiples)
     double sd_max_base_range_atr;   // base range ceiling (ATR multiples)
   
     double sd_break_min_pips;       // extra breakout margin in pips (optional)
     double sd_break_atr_k;          // extra breakout margin in ATR (optional)
     bool   sd_close_confirm_only;   // true=close beyond base; false=wick ok
   
     bool   sd_use_volume_filter;    // optional: breakout volume spike vs base avg
     double sd_vol_spike_k;          // required spike ratio (e.g., 1.25)
   #endif

   #ifdef CFG_HAS_AUTOCHART_RR_NORM
       double auto_chart_rr_norm; // RR normalization for target scoring (ATR multiples)
   #endif
   #ifdef CFG_HAS_MAIN_CHART_RETEST_MAX_ATR
       double main_chart_retest_max_atr; // entry must be within X*ATR of breakout level (completed)
   #endif
   #ifdef CFG_HAS_MAIN_MIN_RR_FROM_CHART_TARGET
       double main_min_rr_from_chart_target; // require >= X R:R to use chart target as target1
   #endif
   #ifdef CFG_HAS_MAIN_AUTOC_COMPLETED_DIR_VETO
       bool   main_autoc_completed_dir_mismatch_veto; // veto if completed chart opposes trade dir
   #endif
   #ifdef CFG_HAS_MAIN_AUTOC_TIGHTEN_INVAL
       bool   main_autoc_tighten_invalidation; // optional invalidation tightening using break_level
   #endif

   // Fibonacci/harmonic (local)
   double auto_fib_min_quality;
   double autofib_ratio_tolerance;
   int    auto_fib_pivot_L;
   int    auto_fib_pivot_R;
   
   double auto_fib_stop_atr_mult;
   double auto_fib_target_r1;
   double auto_fib_target_r2;
   double auto_fib_target_r3;
   
   // Key levels (local)
   int    auto_keylevel_min_touches;
   double auto_keylevel_cluster_atr;
   double auto_keylevel_approach_atr;
   
   double auto_keylevel_min_pips;
   double auto_keylevel_break_margin_atr;
   int    auto_keylevel_bounce_window;

   double auto_keylevel_w_touches;
   double auto_keylevel_w_recency;
   double auto_keylevel_w_bounce;
   
   #ifdef CFG_HAS_AUTO_KEY_MIN_SIG
      double auto_key_min_sig; // min significance (0..1) for keylevel confluence
   #endif
   
   // Support/Resistance detector (SRDet) — canonical S/R engine for SR scan + key-level reuse
   #ifdef CFG_HAS_SR_DETECTOR_SETTINGS
     int    sr_pivot_left;          // swing validation (left bars)
     int    sr_pivot_right;         // swing validation (right bars)
     bool   sr_use_fractals;        // optional fractal logic (Bill Williams style)
     bool   sr_static_mode;         // true=no repaint (static), false=dynamic updates
     int    sr_level_expiry_bars;   // 0 => never expire
     int    sr_max_levels;          // hard cap to control CPU/noise
     double sr_zone_width_atr;      // zone half-width in ATR units (banded levels)
     double sr_break_vol_ratio;     // breakout volume confirmation ratio
     double sr_touch_vol_ratio;     // validation/touch volume confirmation ratio
     int    sr_mtf_mask;            // bitmask; use same bit layout as scan_tf_mask
   #endif

   // Volatility / movement (local)
   // NOTE: compute cadence lives in Settings::auto_vol_cache_hours (see AutoVol cache block above).
   int    auto_vol_lookback_days;
   int    auto_vol_horizon_minutes;
   double auto_vol_min_range_atr;
   
   // PowerStats-like extensions (used by Autochartist vol + RiskEngine sanity)
   bool   auto_vol_use_m15;                 // true => include 15m/30m bands (more realism)
   double auto_vol_sd_mult;                 // k for mean + k*sd bands

   bool   auto_vol_sltp_sanity_enable;      // default false (avoid surprise behavior changes)
   double auto_vol_sl_max_mult;             // cap SL vs expected range
   double auto_vol_sl_min_frac;             // floor SL vs expected range (fraction)
   double auto_vol_tp_cap_mult;             // cap TP vs expected range (non-breakout)
   double auto_vol_tp_cap_breakout_mult;    // cap TP vs expected range (breakout regime)
   double auto_vol_breakout_adx01;          // breakout threshold in normalized 0..1 space

   bool   auto_vol_sanity_clamp;            // true => clamp instead of veto

   // Optional risk scaling
   bool   auto_risk_scale_enable;
   double auto_risk_scale_floor;
   double auto_risk_scale_cap;

   // ===== Extra Confluences (gated, after main) =====
   bool   extra_enable;      // enable the extra stage
   int    extra_min_needed;  // how many extras must pass
   double extra_min_score;   // optional min extra score
   
   // ===== Extra indicator controls (volume footprint + StochRSI) ============
   // Volume footprint “extra” gate
   bool   extra_volume_footprint;   // if true, use volume footprint as extra
   double w_volume_footprint;       // weight for volume footprint extra
   bool extra_dom_imbalance;
   double w_dom_imbalance;
   bool debug_dom;
   int dom_zone_pad_points;
   double dom_min_abs_imb;

   // Trendlines (Market-Structure swing trendlines) - confluence-only
   bool   extra_trendlines;
   double w_trendlines;
   
   // StochRSI “extra” gate (distinct from base cf_stochrsi flag/weights)
   bool   extra_stochrsi;           // enable StochRSI as an extra gate
   int    stochrsi_rsi_period;      // inner RSI period for StochRSI
   int    stochrsi_k_period;        // %K period for StochRSI
   int    stochrsi_k_smooth;        // %K smoothing (default 3)
   int    stochrsi_d_smooth;        // %D smoothing (default 3)
   double stochrsi_ob;              // StochRSI overbought level (0..1)
   double stochrsi_os;              // StochRSI oversold level (0..1)

   // ------------------------------------------------------------
   // Liquidity Pools (Lux-style, from Lux Liquidity Pools script)
   // ------------------------------------------------------------
   int    liqPoolMinTouches;          // Lux cNum – min contacts to form pool
   int    liqPoolGapBars;             // Lux gapCount – bars between touches
   int    liqPoolConfirmWaitBars;     // Lux wait – bars before confirming zone
   double liqPoolLevelEpsATR;         // distance threshold in ATR (e.g. 0.10 = 10% ATR)
   int    liqPoolMaxLookbackBars;     // max bars to keep pool “active”
   double liqPoolMinSweepATR;         // intensity: min ATR move for a “real sweep”
   
   #ifdef CFG_HAS_TRADE_CD_SEC
     int    trade_cd_sec;    // global per-trade cooldown seconds (Policies::CfgTradeCooldownSec)
   #endif

   #ifdef CFG_HAS_ENABLE_HARD_GATE
     bool   enable_hard_gate;        // router hard gate switch
   #endif
   #ifdef CFG_HAS_MIN_FEATURES_MET
     int    min_features_met;        // minimum #features required (independent from cf_min_needed)
   #endif
   #ifdef CFG_HAS_REQUIRE_TREND_FILTER
     bool   require_trend_filter;    // extra require: trend filter must pass
   #endif
   #ifdef CFG_HAS_REQUIRE_ADX_REGIME
     bool   require_adx_regime;      // extra require: ADX regime must pass
   #endif
   #ifdef CFG_HAS_REQUIRE_STRUCT_OR_PATTERN_OB
     bool   require_struct_or_pattern_ob; // extra require: Structure OR Pattern/OB must pass
   #endif
   #ifdef CFG_HAS_LONDON_LIQ_POLICY
     bool   london_liquidity_policy; // optional policy guard for London session
   #endif
   #ifdef CFG_HAS_LONDON_LOCAL_MINUTES
     int london_local_open_min;
     int london_local_close_min;
   #endif
   
   // ===== Oscillator / Trend Params =====
   int    adx_period;
   double adx_min_trend;
   double adx_upper;        // NEW: shaping upper band for ADX ramp

   // ===== Correlation penalty =====
   double corr_max_pen;     // NEW: max bounded penalty (0..1), default 0.25
   double w_corr_pen;       // NEW: optional weight knob when shaping final use
   
   int    rsi_period;
   int    stoch_k;
   int    stoch_k_smooth;    // %K smoothing for StochRSI (default 3)
   int    stoch_d;
   double stoch_ob;          // 0..1
   double stoch_os;          // 0..1
   
   int    macd_fast;
   int    macd_slow;         // must be > fast
   int    macd_signal;
   
   #ifdef CFG_HAS_MACD_PRICE
     ENUM_APPLIED_PRICE macd_price;
   #endif

  // --- News: hard block + surprise risk scaling -----------------------------
  bool              news_on;
  int               block_pre_m;
  int               block_post_m;
  double            cal_hard_skip;       // ≥ this → skip (legacy)
  
  #ifdef CFG_HAS_NEWS_BACKEND
      int  news_backend_mode;        // 0=disabled, 1=broker, 2=csv, 3=auto
      bool news_mvp_no_block;        // MVP safety: if true => never hard-block
      bool news_failover_to_csv;     // allow broker->csv fallback
      bool news_neutral_on_no_data;  // missing data => neutral (no block)
      bool news_allow_cached; // allow using cached broker-calendar data when fresh fetch is unavailable
  #endif
  
  // Extra: Correlation gate
  string             corr_ref_symbol;     // e.g., "DXY" / "USTEC" / "XAUUSD"
  int                corr_lookback;       // e.g., 120..300 bars
  double             corr_min_abs;        // e.g., 0.30..0.50 | abs(r)
  ENUM_TIMEFRAMES    corr_ema_tf;         // e.g., PERIOD_H1
  int                corr_ema_fast;       // e.g., 21
  int                corr_ema_slow;       // e.g., 50
  
  // Core confluences (used by MainTradingLogic)
  bool    cf_liquidity;       double w_liquidity;
  bool    cf_vsa_increase;    double w_vsa_increase;
  
  // Silver Bullet timezone / session entry confluence
  bool   extra_silverbullet_tz;
  double w_silverbullet_tz;
   
  // AMD HTF phases (H1/H4)
  bool   extra_amd_htf;
  double w_amd_h1;
  double w_amd_h4;
  
  // PO3 HTF phases (H1/H4 intraday context)
  bool   extra_po3_htf;
  double w_po3_h1;
  double w_po3_h4;

  // Wyckoff turn context (Spring / UTAD)
  bool   extra_wyckoff_turn;
  double w_wyckoff_turn;

  // Phase context (WyckoffCycle / PO3 alignment) - confluence-only
  bool   extra_phase_ctx;
  double w_phase_ctx;
  
  // ──────────────────────────────────────────────────────────────
  // WyckoffCycle core knobs (range / BOS / manipulation / volume)
  // These are used by WyckoffCycle.mqh so it doesn't hardcode tuning.
  // ──────────────────────────────────────────────────────────────
  #ifdef CFG_HAS_WYCK_CYCLE_SETTINGS
    int    wyck_range_lookback;        // range scan window (bars)
    int    wyck_min_range_bars;        // min bars to accept a trading range

    double wyck_eq_tol_atr;            // equal-high/low tolerance (ATR multiple)
    double wyck_max_range_atr;         // reject ranges wider than this (ATR multiple)

    bool   wyck_use_atr_compression;   // range filter: ATR compression
    int    wyck_atr_len;               // ATR period
    int    wyck_atr_ma_len;            // ATR MA period

    bool   wyck_use_bb_compression;    // range filter: BB width compression
    int    wyck_bb_len;                // BB period
    double wyck_bb_dev;                // BB deviation
    double wyck_bb_width_thr;          // BB width threshold (fraction, e.g. 0.015)

    int    wyck_swingL;                // swing pivot left
    int    wyck_swingR;                // swing pivot right

    int    wyck_bos_confirm_closes;    // BOS confirm closes (1..N)

    double wyck_manip_min_quality;     // min quality score for Spring/UTAD
    double wyck_wick_min_ratio;        // wick ratio threshold for sweep bar
    double wyck_close_inside_min;      // reclaim threshold into range (0..1)

    int    wyck_ar_window_bars;        // AR/SC window
    int    wyck_vol_len;               // volume MA length
    double wyck_vol_mult;              // volume spike multiplier (e.g. 1.5)
  #endif

  // Multi-TF zones (H1/H4 zone proximity)
  bool   extra_mtf_zones;
  double w_mtf_zone_h1;
  double w_mtf_zone_h4;
  double mtf_zone_max_dist_atr;

  // Extras (applied only after main logic confirms)
  bool    extra_macd;
  bool    extra_adx_regime;        double w_adx_regime;
  bool    extra_correlation;
  bool    extra_news;

  #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
    bool main_news_hard_veto;
  #endif

  // (Optional) news parameters if NewsFilter is wired
  int    news_impact_mask;
  int    news_block_pre_mins;
  int    news_block_post_mins;
  int    cal_lookback_mins;
  double cal_soft_knee, cal_min_scale;

  // Strategy helpers expect these explicit names (mirrors of the above)
  #ifdef CFG_HAS_NEWS_PRE_MINS
    int             news_pre_mins;       // alias to block_pre_m (not auto-synced)
  #endif
  #ifdef CFG_HAS_NEWS_POST_MINS
    int             news_post_mins;      // alias to block_post_m (not auto-synced)
  #endif
  #ifdef CFG_HAS_NEWS_LOOKBACK_MINS
    int             news_lookback_mins;  // preferred explicit
  #endif
  #ifdef CFG_HAS_NEWS_SOFT_KNEE
    double          news_soft_knee;
  #endif
  #ifdef CFG_HAS_NEWS_HARD_SKIP
    double          news_hard_skip;
  #endif
  #ifdef CFG_HAS_NEWS_MIN_SCALE
    double          news_min_scale;
  #endif
  #ifdef CFG_HAS_NEWS_HALFLIFE
    int             news_half_life_mins;
  #endif
  #ifdef CFG_HAS_NEWS_MAX_BLOCK
    double          news_max_block;
  #endif
  #ifdef CFG_HAS_NEWS_MIN_DECAY_MULT
    double          news_min_decay_mult;
  #endif
  
  // --- Position management (PM) ---------------------------------------------
  #ifdef CFG_HAS_PM_MODE
    int               pm_mode;                   // 0=off, 1=basic, 2=full
  #endif

  #ifdef CFG_HAS_PM_ALLOW_DAILY_FLATTEN
    bool              pm_allow_daily_flatten;    // optional
  #endif

  #ifdef CFG_HAS_PM_POST_DD_COOLDOWN_SECONDS
    int               pm_post_dd_cooldown_seconds; // optional
  #endif

  bool              be_enable;
  double            be_at_R;
  double            be_lock_pips;

  TrailType         trail_type;
  double            trail_pips;
  double            trail_atr_mult;

  // AUTO trailing regime inputs (ADX-based)
  #ifdef CFG_HAS_TRAIL_AUTO_ADX_TF
  ENUM_TIMEFRAMES    trail_auto_adx_tf;
  #endif
  #ifdef CFG_HAS_TRAIL_AUTO_ADX_PERIOD
  int               trail_auto_adx_period;
  #endif
  #ifdef CFG_HAS_TRAIL_AUTO_ADX_MIN
  double            trail_auto_adx_min;
  #endif
  
  bool              partial_enable;
  double            p1_at_R;
  double            p1_close_pct;
  double            p2_at_R;
  double            p2_close_pct;

  // --- Calm / Liquidity guard -----------------------------------------------
  bool              calm_mode;
  double            calm_min_atr_pips;
  double            calm_min_atr_to_spread;
  #ifdef CFG_HAS_WEEKLY_OPEN_RAMP
    bool weekly_open_spread_ramp; // ON = relax spread cap in first hour of Monday open
  #endif

  // --- Confluence & VWAP params ---------------------------------------------
  double            vwap_z_edge;         // |z| significance for MR
  double            vwap_z_avoidtrend;   // avoid deep against trend
  double            vwap_z_avoid;        // legacy alias

  int               pattern_lookback;    // preferred name
  double            pattern_tau;         // preferred name
  int               patt_lookback;       // legacy alias
  double            patt_tau;            // legacy alias

  #ifdef CFG_HAS_PATT_SETTINGS_FIELDS
    // --- Universal Pattern (candles + classic charts) ---
    int               patt_mode;               // 0=confirmed, 1=aggressive
    double            patt_min_quality01;      // global PQSS/quality threshold
    int               patt_retest_window_bars; // breakout->retest window (bars)
    double            patt_stop_atr_mult;      // ATR stop multiple
    double            patt_target_height_mult; // classic measured-move scale (default 1.0)

    bool              patt_emit_candles;       // emit candle events
    bool              patt_emit_classic;       // emit classic chart events
    bool              patt_emit_autoc;         // optionally mirror autochartist-class patterns (usually false)
    
    // --- AMPDI required inputs / gates (Patterns.mqh) ---
    int               patt_atr_period;
    int               patt_ema_fast;
    int               patt_ema_slow;

    int               patt_volume_sma_period;
    double            patt_volume_mult;
    bool              patt_use_volume_filter;

    bool              patt_use_momentum;
    int               patt_rsi_period;

    int               patt_pivot_L;
    int               patt_pivot_R;

    double            patt_tol_atr_k;
    double            patt_min_score01; // AMPDI score gate (default 0.70)

    // --- AMPDI candlestick thresholds (spec-aligned) ---
    double            patt_cs_hammer_body_pct_max;
    double            patt_cs_hammer_lw_body_mult;
    double            patt_cs_hammer_uw_body_mult;

    double            patt_cs_spin_body_pct_max;
    double            patt_cs_spin_wick_sym_rng_pct;

    double            patt_cs_doji_body_rng_pct;
    double            patt_cs_doji_uw_rng_pct;
    double            patt_cs_doji_lw_rng_pct;

    double            patt_cs_star_body3_rng_min;
    double            patt_cs_star_retrace_body1_k;
  #endif
  
  bool              useVWAPFilter;       // require VWAP alignment?
  bool              useEMAFilter;        // require EMA alignment?

  int               vwap_lookback;       // session VWAP lookback
  double            vwap_sigma;          // sigma for deviation (if used)
  double            vwap_pullback_min_pts;
  double            vwap_pullback_max_pts;
  
  // -----------------------------------------------------------------
  // FVG gating / quality knobs (backed by CFG_HAS_FVG_* flags)       
  // -----------------------------------------------------------------
  #ifdef CFG_HAS_FVG_MIN_SCORE
     double fvg_min_score;   // baseline FVG quality floor (0..1)
  #endif
   
  #ifdef CFG_HAS_FVG_MODE
     int    fvg_mode;        // stores FVGMode as int (FVG_ALL/FVG_TREND_ONLY/...)
     // if Config.mqh already includes Types.mqh at this point and you
     // prefer strong typing, you can instead use:
     // FVGMode fvg_mode;
  #endif

  #ifdef CFG_HAS_FVG_LOOKBACK_BARS
     int fvg_lookback_bars;              // bars scanned to detect FVGs
  #endif
  #ifdef CFG_HAS_FVG_IMPULSE_LOOKAHEAD_BARS
     int fvg_impulse_lookahead_bars;     // bars to validate impulse continuation
  #endif
  #ifdef CFG_HAS_FVG_MIN_GAP_ATR
     double fvg_min_gap_atr;             // minimum gap size in ATR multiples (filter)
  #endif

  // Confluence blending weights (0..0.50 typical)
  double            confl_blend_trend;
  double            confl_blend_mr;
  double            confl_blend_others;
  
  #ifdef CFG_HAS_ML_THRESHOLD
     double ml_threshold;   // 0..1 ML probability threshold (debug + gating consistency)
  #endif
  
  #ifdef CFG_HAS_ML_SETTINGS
     bool   ml_enable;
     double ml_weight;
     double ml_temperature;
     double ml_conformal_alpha;
     double ml_dampen;
   
     #ifdef CFG_HAS_ML_SLTP_MULT
         // ML-suggested SL/TP multipliers (bounds only; actual values come from StrategyRegistry)
         bool   ml_sltp_enable;
         double ml_sltp_sl_min;
         double ml_sltp_sl_max;
         double ml_sltp_tp_min;
         double ml_sltp_tp_max;
     #endif

     bool   ml_auto_calibrate;
     int    ml_model_max_age_hours;
     double ml_min_oos_auc;
     double ml_min_oos_acc;
     int    ml_min_samples_train;
     int    ml_min_samples_test;
   
     int    ml_label_horizon_bars;
     double ml_label_atr_mult;
   
     bool   ml_use_common_files;
     string ml_model_file;
     string ml_dataset_file;
   
     bool   ml_external_enable;
     int    ml_external_mode;
     string ml_external_file;
     int    ml_external_poll_ms;
     string ml_external_socket_host;
     int    ml_external_socket_port;
  #endif
  
  StrategyMode      strat_mode;
  #ifdef CFG_HAS_ENABLE_PACK_STRATS
    bool enable_pack_strats;   // runtime gate: allow pack strategies to be registered/tradable
  #endif
  #ifdef CFG_HAS_DISABLE_PACKS
    bool disable_packs;        // fail-safe kill switch for pack strategies
  #endif

  // --- Feature toggles / vetoes used by strategies --------------------------
  bool              vsa_enable;
  double            vsa_penalty_max;
  int               vsa_lookback;     // VSA scan lookback bars (0/<=0 => fall back to internal default)
  #ifdef CFG_HAS_VSA_ALLOW_TICK_VOLUME
    bool              vsa_allow_tick_volume; // allow tick volume in VSA when real volume unavailable
  #endif

  bool              structure_enable;
  bool              liquidity_enable;
  bool              corr_softveto_enable;

  // Explicit veto knobs honored by Policies / RegimeCorr / LiquidityCues
  bool              struct_veto_on;
  bool              liquidity_veto_on;
  double            liquidity_spr_atr_max; // e.g., 0.45
  bool              corr_veto_on;
  double            regime_tq_min;       // 0..1
  double            regime_sg_min;       // 0..1

  // --- Archetype enables -----------------------------------------------------
  bool              enable_main;        // "main_trading_logic"
  bool              enable_trend_pullback;
  bool              enable_mr_range;
  bool              enable_news_fade;
  bool              enable_breakout_squeeze;
  bool              enable_breakout_orb;

  // Legacy granular toggles (kept for BC)
  bool              enable_trend_vwap_pullback;
  bool              enable_trend_bos_continuation;
  bool              enable_mr_range_nr7ib;
  bool              enable_mr_vwap_band;
  bool              enable_news_postfade;
  bool              enable_news_deviation;
  bool              enable_reversal_vsa_climax_fade;
  bool              enable_reversal_sweep_choch;
  bool              enable_corr_divergence;
  bool              enable_pairs_spreadlite;
  int               max_archetypes;
  bool              enable_ict_po3;              // "strat_ict_po3"
  bool              enable_ict_silverbullet;     // "strat_ict_silverbullet"
  bool              enable_ict_wyckoff_utad;     // "strat_ict_wyckoff_springutad"
  
  int     magic_trend_base;
  int     magic_mr_base;
  int     magic_breakout_base;
  int     magic_reversal_base;
  int     magic_alt_base;
  int     magic_news_base;
   
  double  risk_mult_trend;
  double  risk_mult_mr;
  double  risk_mult_breakout;
  double  risk_mult_reversal;
  double  risk_mult_alt;
  double  risk_mult_news;

  // Non-overlap & router sanity ----------------------------------------------
  bool              nonoverlap_enable;   // allow strategies to politely yield

  #ifdef CFG_HAS_ROUTER_EVAL_ALL_MODE
    int               router_eval_all_mode; // 0=best-of-all-symbols, 1=per-symbol execution
  #endif
  #ifdef CFG_HAS_ROUTER_MIN_SCORE
    double          router_min_score;            // default ~0.55
  #endif
  #ifdef CFG_HAS_ROUTER_MAX_STRATS
    int             router_max_strats;
  #endif
  #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
    double          router_fallback_min_score;   // default ~0.50
  #endif
  #ifdef CFG_HAS_ROUTER_TOPK
    int             router_topk_log;             // default 5
  #endif
  #ifdef CFG_HAS_ROUTER_DEBUG
    bool            router_debug_log;            // default true
  #endif
  #ifdef CFG_HAS_ROUTER_FORCE_ONE
    bool            router_force_one_normal_vol; // default true
  #endif
  #ifdef CFG_HAS_ROUTER_USE_CONFL_POOL
    bool            router_use_confl_pool;      // enable Router use of confluence-only pool
  #endif
  #ifdef CFG_HAS_ROUTER_POOL_BLEND_W
    double          router_pool_blend_w;        // 0..1 blend weight for pool score into candidate ranking
  #endif
  #ifdef CFG_HAS_ROUTER_FB_MIN
    double           router_fb_min; // alias for older writers; same meaning as router_fallback_min_score
  #endif
  #ifdef CFG_HAS_ROUTER_HINTS
     string router_profile_alias;           // profile alias used for fallback hinting ("trend", "mr", ...)
     double router_fallback_min_confluence; // 0..1; 0 = ignore / unused
     int    router_fallback_max_span;       // bars; 0 = ignore / unused
   #endif

  // --- Pairs / correlation (pairs-lite) -------------------------------------
  #ifdef CFG_HAS_PAIRS_Z_EDGE
    double          pairs_z_edge;
  #endif
  #ifdef CFG_HAS_PAIRS_LOOKBACK
    int             pairs_lookback;
  #endif
  #ifdef CFG_HAS_PAIRS_MIN_R
    double          pairs_min_r_abs;
  #endif
  #ifdef CFG_HAS_PAIRS_MATE
    string          pairs_mate;
  #endif
  #ifdef CFG_HAS_PAIRS_INVERT
    bool            pairs_invert_mate;
  #endif
  
  // Silver Bullet additional hard requirements (optional)
  #ifdef CFG_HAS_SB_REQUIRE_OTE
    bool sb_require_ote;
  #endif
  #ifdef CFG_HAS_SB_REQUIRE_VWAP_STRETCH
    bool sb_require_vwap_stretch;
  #endif

  // --- Per-symbol overrides payload -----------------------------------------
  #ifdef CFG_HAS_PER_SYMBOL_OVERRIDES
    string          per_symbol_overrides_csv; // raw CSV; parsed at Normalize()
    SymbolOverride  sym_overrides[];          // concrete overrides
  #endif

  // --- Diagnostics / misc ----------------------------------------------------
  int               profile;             // profile code (or bool-like in legacy UIs)
  bool              debug;
  bool              filelog;
  
  // Ob/SD structure & zigzag heuristics
  int        struct_zz_depth;
  int        struct_htf_mult;
  double     ob_prox_max_pips;

  #ifdef CFG_HAS_STRUCT_ZONE_MARGIN_PIPS
    double     struct_zone_margin_pips;
  #endif
  #ifdef CFG_HAS_STRUCT_MIN_TOUCH_COUNT
    int        struct_min_touch_count;
  #endif
  #ifdef CFG_HAS_STRUCT_ZONE_MIN_SCORE
    double     struct_zone_min_score;
  #endif

  // -------------------------------------------------
   // 2. BIAS / DIRECTION CONTROL
   // -------------------------------------------------
   // DIRM_MANUAL_SELECTOR
   //   Use the manual buy/sell/both selector from the user.
   // DIRM_AUTO_SMARTMONEY
   //   Derive allowed direction from ICT_Context.directionalBias, which comes
   //   from Wyckoff phase + HTF structure.
   // -----------------------------------------------------------------------------
   
   // ICT playbook profile for FVG/OB strictness, used by ICTWyckoffModel
   #ifdef CFG_HAS_STRATEGY_KIND
     ICTStrategyKind             strategyKind;
   #endif

   // We'll compute final allowed direction each tick using
   // EffectiveDirectionSelector(cfg, ctx), which merges manual vs auto.
   //
   // Auto-bias pipeline:
   //   Wyckoff on H4/D1 + HTF structure ->
   //   ICT_Context.directionalBias (ICT_LONG_ONLY, ICT_SHORT_ONLY, etc.) ->
   //   mapped to DIR_BUY / DIR_SELL / DIR_BOTH.

   // -------------------------------------------------
   // 3. STRATEGY ENABLE TOGGLES
   // -------------------------------------------------
   // These let you switch individual sub-strategies on/off from inputs.
   // Router / StrategyRegistry respect these, and won't even attempt Evaluate()
   // if one is disabled.
   bool strat_toggles_seeded;             // defaults applied once; prevents Normalize() from undoing user choices
   bool enable_strat_main;                // legacy main logic
   bool enable_strat_ict_silverbullet;    // ICT_SilverBullet intraday raid scalp
   bool enable_strat_ict_po3;             // ICT_PO3 session model
   bool enable_strat_ict_continuation;    // ICT_OBFVG_OTE continuation pullback
   bool enable_strat_ict_wyckoff_turn;    // ICT_Wyckoff_SpringUTAD reversal at extremes

   // -------------------------------------------------
   // 4. PER-STRATEGY MAGIC BASES & RISK MULTIPLIERS
   // -------------------------------------------------
   // Each strategy will get its own magic number base and risk multiplier.
   // Router injects these into cfg.magic_base / cfg.risk_mult_current before
   // calling that strategy's Evaluate().
   //
   // Magic bases -> unique magic ranges to track PnL per strategy.
   // Risk multipliers -> aggressiveness / lot scaling per strategy.

   // Base magic numbers (input-configured)
   int magic_main_base;
   int magic_sb_base;
   int magic_po3_base;
   int magic_cont_base;
   int magic_wyck_base;

   // Base risk multipliers (input-configured)
   double risk_mult_main;
   double risk_mult_sb;
   double risk_mult_po3;
   double risk_mult_cont;
   double risk_mult_wyck;

   // Runtime overrides (Router writes these JUST BEFORE Evaluate())
   // so that Execution can size and tag positions correctly.
   int    magic_base;          // current strategy's magic base in effect right now
   double risk_mult_current;   // current strategy's active risk multiplier

   // -------------------------------------------------
   // 5. MODE FLAGS
   // -------------------------------------------------
   bool mode_use_po3;
   bool mode_use_silverbullet;
   bool mode_enforce_killzone;
   bool mode_use_ICT_bias;
   bool mode_use_continuation;
   bool mode_use_wyckoff_turn;
}; // END Struct Settings

extern Settings g_cfg;
// ---------------------------------------------------------------------
// Router alias sync (global wrapper).
// For external callers, forward to the canonical implementation in
// namespace Config (which already handles all compile guards).
// ---------------------------------------------------------------------
#ifdef CFG_ROUTER_ALIAS_SYNC_GUARD
#define CFG_ROUTER_ALIAS_SYNC_GUARD 1
inline void _SyncRouterFallbackAlias(Settings &cfg)
{
  Config::_SyncRouterFallbackAlias(cfg);
}
#endif // CFG_ROUTER_ALIAS_SYNC_GUARD

#endif // EA_CFG_SESSION_HELPERS_GUARD

#endif // CA_CONFIG_MQH