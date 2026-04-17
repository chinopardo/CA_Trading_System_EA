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
#include "State.mqh"
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

#ifndef POLICIES_HAS_RISKENGINE_DIAG_BRIDGE
  #ifdef RISKENGINE_HAS_GETLASTDIAG_API
    #define POLICIES_HAS_RISKENGINE_DIAG_BRIDGE 1
  #endif
#endif

#ifndef POLICIES_HAS_RISKENGINE_DIAG_SYMBOL_BRIDGE
  #ifdef RISKENGINE_HAS_GETLASTDIAG_SYMBOL_API
    #define POLICIES_HAS_RISKENGINE_DIAG_SYMBOL_BRIDGE 1
  #endif
#endif

#ifndef POLICIES_HAS_CAEA_DBG_BRIDGE
  #ifdef CAEA_DBG_AVAILABLE
    #define POLICIES_HAS_CAEA_DBG_BRIDGE 1
  #endif
#endif

#ifndef POLICIES_HAS_POLICY_RISK_SCALING
  #define POLICIES_HAS_POLICY_RISK_SCALING 1
#endif

#ifndef POLICIES_HAS_INSTITUTIONAL_STATE_GATE
  #define POLICIES_HAS_INSTITUTIONAL_STATE_GATE 1
#endif

#ifndef POLICY_TESTER_RELAX
  #define POLICY_TESTER_RELAX 1
#endif

#ifndef NEWS_ENABLED
  #define NEWS_ENABLED 1
#endif

#ifndef VOL_BREAKER_ENABLED
  #define VOL_BREAKER_ENABLED 1
#endif

#ifndef SESSION_GATING_ENABLED
  #define SESSION_GATING_ENABLED 1
#endif

#ifndef POLICIES_INST_MIN_STATE_QUALITY01
  #define POLICIES_INST_MIN_STATE_QUALITY01 0.35
#endif

#ifndef POLICIES_INST_MIN_OBSERVABILITY01
  #define POLICIES_INST_MIN_OBSERVABILITY01 0.35
#endif

#ifndef POLICIES_INST_MIN_VENUE_COVERAGE01
  #define POLICIES_INST_MIN_VENUE_COVERAGE01 0.30
#endif

#ifndef POLICIES_INST_DELAY_EXECUTION_SCORE01
  #define POLICIES_INST_DELAY_EXECUTION_SCORE01 0.35
#endif

#ifndef POLICIES_INST_DERISK_RISK_SCORE01
  #define POLICIES_INST_DERISK_RISK_SCORE01 0.60
#endif

#ifndef POLICIES_INST_VETO_RISK_SCORE01
  #define POLICIES_INST_VETO_RISK_SCORE01 0.20
#endif

#ifndef POLICIES_INST_VETO_XVENUE_DISLOCATION01
  #define POLICIES_INST_VETO_XVENUE_DISLOCATION01 0.75
#endif

#ifndef POLICIES_INST_ENABLE_OBSERVABILITY_GATE
  #define POLICIES_INST_ENABLE_OBSERVABILITY_GATE 1
#endif

#ifndef POLICIES_INST_ENABLE_VENUE_COVERAGE_GATE
  #define POLICIES_INST_ENABLE_VENUE_COVERAGE_GATE 1
#endif

#ifndef POLICIES_INST_ENABLE_XVENUE_DISLOCATION_VETO
  #define POLICIES_INST_ENABLE_XVENUE_DISLOCATION_VETO 1
#endif

// Neutral defaults for optional downstream diagnostics.
// Policies must not fabricate these from unrelated fields.
#ifndef POLICIES_INST_DEFAULT_OBSERVABILITY01
  #define POLICIES_INST_DEFAULT_OBSERVABILITY01 1.0
#endif

#ifndef POLICIES_INST_DEFAULT_VENUE_COVERAGE01
  #define POLICIES_INST_DEFAULT_VENUE_COVERAGE01 1.0
#endif

#ifndef POLICIES_INST_DEFAULT_XVENUE_DISLOCATION01
  #define POLICIES_INST_DEFAULT_XVENUE_DISLOCATION01 0.0
#endif

#ifndef POLICIES_INST_MAX_IMPACT_BETA01
  #define POLICIES_INST_MAX_IMPACT_BETA01 0.75
#endif

#ifndef POLICIES_INST_MAX_IMPACT_LAMBDA01
  #define POLICIES_INST_MAX_IMPACT_LAMBDA01 0.75
#endif

#ifndef POLICIES_INST_MIN_DARKPOOL01
  #define POLICIES_INST_MIN_DARKPOOL01 0.20
#endif

#ifndef POLICIES_INST_MAX_DARKPOOL_CONTRADICTION01
  #define POLICIES_INST_MAX_DARKPOOL_CONTRADICTION01 0.65
#endif

#ifndef POLICIES_INST_MAX_SD_OB_INVALIDATION_PROXIMITY01
  #define POLICIES_INST_MAX_SD_OB_INVALIDATION_PROXIMITY01 0.80
#endif

#ifndef POLICIES_INST_MAX_LIQUIDITY_VACUUM01
  #define POLICIES_INST_MAX_LIQUIDITY_VACUUM01 0.70
#endif

#ifndef POLICIES_INST_MAX_LIQUIDITY_HUNT01
  #define POLICIES_INST_MAX_LIQUIDITY_HUNT01 0.70
#endif

#ifndef POLICIES_INST_ENABLE_IMPACT_VETO
  #define POLICIES_INST_ENABLE_IMPACT_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_DARKPOOL_VETO
  #define POLICIES_INST_ENABLE_DARKPOOL_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_SD_OB_INVALIDATION_VETO
  #define POLICIES_INST_ENABLE_SD_OB_INVALIDATION_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_LIQUIDITY_TRAP_VETO
  #define POLICIES_INST_ENABLE_LIQUIDITY_TRAP_VETO 1
#endif

#ifndef POLICIES_INST_DEFAULT_IMPACT_BETA01
  #define POLICIES_INST_DEFAULT_IMPACT_BETA01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_IMPACT_LAMBDA01
  #define POLICIES_INST_DEFAULT_IMPACT_LAMBDA01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_DARKPOOL01
  #define POLICIES_INST_DEFAULT_DARKPOOL01 1.0
#endif

#ifndef POLICIES_INST_DEFAULT_DARKPOOL_CONTRADICTION01
  #define POLICIES_INST_DEFAULT_DARKPOOL_CONTRADICTION01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_SD_OB_INVALIDATION_PROXIMITY01
  #define POLICIES_INST_DEFAULT_SD_OB_INVALIDATION_PROXIMITY01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_LIQUIDITY_VACUUM01
  #define POLICIES_INST_DEFAULT_LIQUIDITY_VACUUM01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_LIQUIDITY_HUNT01
  #define POLICIES_INST_DEFAULT_LIQUIDITY_HUNT01 0.0
#endif

// Optional transport field bridges.
// These stay OFF unless Confluence transport explicitly exposes the fields.
#ifndef POLICIES_HAS_INST_TRANSPORT_OBSERVABILITY01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OBSERVABILITY01
    #define POLICIES_HAS_INST_TRANSPORT_OBSERVABILITY01 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_VENUE_COVERAGE01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VENUE_COVERAGE01
    #define POLICIES_HAS_INST_TRANSPORT_VENUE_COVERAGE01 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_XVENUE_DISLOCATION01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_XVENUE_DISLOCATION01
    #define POLICIES_HAS_INST_TRANSPORT_XVENUE_DISLOCATION01 1
  #endif
#endif

#ifndef POLICIES_INST_ENABLE_VPIN_VETO
  #define POLICIES_INST_ENABLE_VPIN_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_RESILIENCY_VETO
  #define POLICIES_INST_ENABLE_RESILIENCY_VETO 1
#endif

#ifndef POLICIES_INST_DEFAULT_VPIN01
  #define POLICIES_INST_DEFAULT_VPIN01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_RESILIENCY01
  #define POLICIES_INST_DEFAULT_RESILIENCY01 1.0
#endif

#ifndef POLICIES_INST_ENABLE_TOXICITY_VETO
  #define POLICIES_INST_ENABLE_TOXICITY_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_SPREAD_STRESS_VETO
  #define POLICIES_INST_ENABLE_SPREAD_STRESS_VETO 1
#endif

#ifndef POLICIES_INST_DEFAULT_TOXICITY01
  #define POLICIES_INST_DEFAULT_TOXICITY01 0.0
#endif

#ifndef POLICIES_INST_DEFAULT_SPREAD_STRESS01
  #define POLICIES_INST_DEFAULT_SPREAD_STRESS01 0.0
#endif

#ifndef POLICIES_INST_MAX_TOXICITY01
  #define POLICIES_INST_MAX_TOXICITY01 0.65
#endif

#ifndef POLICIES_INST_MAX_SPREAD_STRESS01
  #define POLICIES_INST_MAX_SPREAD_STRESS01 0.60
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_TOXICITY01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_TOXICITY01
    #define POLICIES_HAS_INST_TRANSPORT_TOXICITY01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_TOXICITY_SCORE01
      #define POLICIES_HAS_INST_TRANSPORT_TOXICITY01 1
    #else
      #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MS_TOXICITY
        #define POLICIES_HAS_INST_TRANSPORT_TOXICITY01 1
      #endif
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_SPREAD_STRESS01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SPREAD_STRESS01
    #define POLICIES_HAS_INST_TRANSPORT_SPREAD_STRESS01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VOLATILITY_STRESS01
      #define POLICIES_HAS_INST_TRANSPORT_SPREAD_STRESS01 1
    #else
      #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ICT_SPREAD_STRESS_SCORE01
        #define POLICIES_HAS_INST_TRANSPORT_SPREAD_STRESS01 1
      #endif
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_VPIN01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VPIN01
    #define POLICIES_HAS_INST_TRANSPORT_VPIN01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MS_VPIN
      #define POLICIES_HAS_INST_TRANSPORT_VPIN01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_RESILIENCY01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_RESILIENCY01
    #define POLICIES_HAS_INST_TRANSPORT_RESILIENCY01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MS_RESIL
      #define POLICIES_HAS_INST_TRANSPORT_RESILIENCY01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_IMPACT_BETA01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_IMPACT_BETA01
    #define POLICIES_HAS_INST_TRANSPORT_IMPACT_BETA01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_IMPACT_BETA01
      #define POLICIES_HAS_INST_TRANSPORT_IMPACT_BETA01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_IMPACT_LAMBDA01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_IMPACT_LAMBDA01
    #define POLICIES_HAS_INST_TRANSPORT_IMPACT_LAMBDA01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_IMPACT_LAMBDA01
      #define POLICIES_HAS_INST_TRANSPORT_IMPACT_LAMBDA01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_DARKPOOL01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARKPOOL01
    #define POLICIES_HAS_INST_TRANSPORT_DARKPOOL01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARK_POOL_CONFIDENCE01
      #define POLICIES_HAS_INST_TRANSPORT_DARKPOOL01 1
    #else
      #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_DARKPOOL01
        #define POLICIES_HAS_INST_TRANSPORT_DARKPOOL01 1
      #endif
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_DARKPOOL_CONTRADICTION01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARKPOOL_CONTRADICTION01
    #define POLICIES_HAS_INST_TRANSPORT_DARKPOOL_CONTRADICTION01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARK_POOL_CONTRADICTION01
      #define POLICIES_HAS_INST_TRANSPORT_DARKPOOL_CONTRADICTION01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_SD_OB_INVALIDATION_PROXIMITY01
  #ifdef CONFL_MS_HAS_SDOB_INV_PROX01
    #define POLICIES_HAS_INST_TRANSPORT_SD_OB_INVALIDATION_PROXIMITY01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SM_INVALIDATION_PROXIMITY01
      #define POLICIES_HAS_INST_TRANSPORT_SD_OB_INVALIDATION_PROXIMITY01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_VACUUM01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_VACUUM01
    #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_VACUUM01 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_HUNT01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_HUNT01
    #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_HUNT01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_SWEEP_TRAP01
      #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_HUNT01 1
    #endif
  #endif
#endif

#ifndef POLICIES_INST_MIN_RESILIENCY01
  #define POLICIES_INST_MIN_RESILIENCY01 0.30
#endif

#ifndef POLICIES_INST_ENABLE_TRUTH_POSTURE_VETO
  #define POLICIES_INST_ENABLE_TRUTH_POSTURE_VETO 1
#endif

#ifndef POLICIES_INST_MIN_TRUTH_TIER01_AGGRESSIVE
  #define POLICIES_INST_MIN_TRUTH_TIER01_AGGRESSIVE 0.70
#endif

#ifndef POLICIES_INST_ENABLE_INVALIDATION_EVENT_VETO
  #define POLICIES_INST_ENABLE_INVALIDATION_EVENT_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_LIQUIDITY_TRAP_EVENT_VETO
  #define POLICIES_INST_ENABLE_LIQUIDITY_TRAP_EVENT_VETO 1
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_TRUTH_TIER01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_TRUTH_TIER01
    #define POLICIES_HAS_INST_TRANSPORT_TRUTH_TIER01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_TRUTH_TIER
      #define POLICIES_HAS_INST_TRANSPORT_TRUTH_TIER01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_EXECUTION_POSTURE_MODE
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_EXECUTION_POSTURE_MODE
    #define POLICIES_HAS_INST_TRANSPORT_EXECUTION_POSTURE_MODE 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_EXECUTION_POSTURE_MODE
      #define POLICIES_HAS_INST_TRANSPORT_EXECUTION_POSTURE_MODE 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_REDUCED_ONLY
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_REDUCED_ONLY
    #define POLICIES_HAS_INST_TRANSPORT_REDUCED_ONLY 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ICT_EXECUTION_REDUCED_ONLY
      #define POLICIES_HAS_INST_TRANSPORT_REDUCED_ONLY 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_INVALIDATION_EVENT01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SD_OB_INVALIDATION_EVENT01
    #define POLICIES_HAS_INST_TRANSPORT_INVALIDATION_EVENT01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SM_INVALIDATION_EVENT01
      #define POLICIES_HAS_INST_TRANSPORT_INVALIDATION_EVENT01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_TRAP_EVENT01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_TRAP_EVENT01
    #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_TRAP_EVENT01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_SWEEP_TRAP_EVENT01
      #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_TRAP_EVENT01 1
    #endif
  #endif
#endif

#ifndef POLICIES_INST_FLOW_MODE_DIRECT
  #define POLICIES_INST_FLOW_MODE_DIRECT 0
#endif

#ifndef POLICIES_INST_FLOW_MODE_PROXY
  #define POLICIES_INST_FLOW_MODE_PROXY 1
#endif

#ifndef POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY
  #define POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY 2
#endif

#ifndef POLICIES_INST_PROXY_DERISK_MULT01
  #define POLICIES_INST_PROXY_DERISK_MULT01 0.70
#endif

#ifndef POLICIES_INST_STRUCTURE_ONLY_DERISK_MULT01
  #define POLICIES_INST_STRUCTURE_ONLY_DERISK_MULT01 0.45
#endif

#ifndef POLICIES_INST_ENABLE_STRUCTURE_ONLY_AGGRESSIVE_VETO
  #define POLICIES_INST_ENABLE_STRUCTURE_ONLY_AGGRESSIVE_VETO 1
#endif

#ifndef POLICIES_INST_ENABLE_PROXY_FORCE_REDUCED_ONLY
  #define POLICIES_INST_ENABLE_PROXY_FORCE_REDUCED_ONLY 1
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_OBSERVABILITY_PENALTY01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OBSERVABILITY_PENALTY01
    #define POLICIES_HAS_INST_TRANSPORT_OBSERVABILITY_PENALTY01 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_FLOW_MODE
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_FLOW_MODE
    #define POLICIES_HAS_INST_TRANSPORT_FLOW_MODE 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MICRO_MODE
      #define POLICIES_HAS_INST_TRANSPORT_FLOW_MODE 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_DIRECT_MICRO_AVAILABLE
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DIRECT_MICRO_AVAILABLE
    #define POLICIES_HAS_INST_TRANSPORT_DIRECT_MICRO_AVAILABLE 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_PROXY_MICRO_AVAILABLE
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_PROXY_MICRO_AVAILABLE
    #define POLICIES_HAS_INST_TRANSPORT_PROXY_MICRO_AVAILABLE 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_OFI01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_OFI01
    #define POLICIES_HAS_INST_TRANSPORT_OFI01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OFI01
      #define POLICIES_HAS_INST_TRANSPORT_OFI01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_OBI01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_OBI01
    #define POLICIES_HAS_INST_TRANSPORT_OBI01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OBI01
      #define POLICIES_HAS_INST_TRANSPORT_OBI01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_CVD01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_CVD01
    #define POLICIES_HAS_INST_TRANSPORT_CVD01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_CVD01
      #define POLICIES_HAS_INST_TRANSPORT_CVD01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_DELTA_PROXY01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_DELTA_PROXY01
    #define POLICIES_HAS_INST_TRANSPORT_DELTA_PROXY01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DELTA_PROXY01
      #define POLICIES_HAS_INST_TRANSPORT_DELTA_PROXY01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_FOOTPRINT01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_FOOTPRINT01
    #define POLICIES_HAS_INST_TRANSPORT_FOOTPRINT01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_FOOTPRINT01
      #define POLICIES_HAS_INST_TRANSPORT_FOOTPRINT01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_PROFILE01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_PROFILE01
    #define POLICIES_HAS_INST_TRANSPORT_PROFILE01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_PROFILE01
      #define POLICIES_HAS_INST_TRANSPORT_PROFILE01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_ABSORPTION01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_ABSORPTION01
    #define POLICIES_HAS_INST_TRANSPORT_ABSORPTION01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ABSORPTION01
      #define POLICIES_HAS_INST_TRANSPORT_ABSORPTION01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_REPLENISHMENT01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_REPLENISHMENT01
    #define POLICIES_HAS_INST_TRANSPORT_REPLENISHMENT01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_REPLENISHMENT01
      #define POLICIES_HAS_INST_TRANSPORT_REPLENISHMENT01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_VWAP_LOCATION01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_VWAP_LOCATION01
    #define POLICIES_HAS_INST_TRANSPORT_VWAP_LOCATION01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VWAP_LOCATION01
      #define POLICIES_HAS_INST_TRANSPORT_VWAP_LOCATION01 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_REJECT01
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_LIQUIDITY_REJECT01
    #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_REJECT01 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_REJECT01
      #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_REJECT01 1
    #else
      #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_REJECTION01
        #define POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_REJECT01 1
      #endif
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_CONFLUENCE_VETO_MASK
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_CONFLUENCE_VETO_MASK
    #define POLICIES_HAS_INST_TRANSPORT_CONFLUENCE_VETO_MASK 1
  #else
    #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_CONFLUENCE_VETO_MASK
      #define POLICIES_HAS_INST_TRANSPORT_CONFLUENCE_VETO_MASK 1
    #endif
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_ROUTE_REASON
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ROUTE_REASON
    #define POLICIES_HAS_INST_TRANSPORT_ROUTE_REASON 1
  #endif
#endif

#ifndef POLICIES_HAS_INST_TRANSPORT_VETO_REASON
  #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VETO_REASON
    #define POLICIES_HAS_INST_TRANSPORT_VETO_REASON 1
  #endif
#endif

#ifndef POLICIES_SIZING_RESET_MULT_DEFAULT
  #define POLICIES_SIZING_RESET_MULT_DEFAULT 0.50
#endif

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
  POLICY_OK                      = 0,
  POLICY_SESSION_OFF             = 1,
  POLICY_NEWS_BLOCK              = 2,
  POLICY_MAX_LOSSES              = 3,
  POLICY_MAX_TRADES              = 4,
  POLICY_SPREAD_HIGH             = 5,
  POLICY_COOLDOWN                = 6,
  POLICY_MONTH_TARGET            = 7,
  POLICY_MOD_SPREAD_HIGH         = 8,
  POLICY_DAILY_DD                = 9,
  POLICY_ACCOUNT_DD              = 10,
  POLICY_VOLATILITY              = 11,
  POLICY_REGIME_FAIL             = 12,
  POLICY_CALM_MARKET             = 13,
  POLICY_DAYLOSS_STOP            = 14,
  POLICY_LIQUIDITY_FAIL          = 15,
  POLICY_CONFLICT                = 16,
  POLICY_ADR_CAP                 = 17,
  POLICY_INSTITUTIONAL_GATE      = 18,
  POLICY_MICRO_VPIN              = 19,
  POLICY_SB_NOT_IN_WINDOW        = 20,
  POLICY_SB_ALREADY_USED         = 21,
  POLICY_MICRO_RESILIENCY        = 22,
  POLICY_MICRO_OBSERVABILITY     = 23,
  POLICY_MICRO_VENUE             = 24,
  POLICY_MICRO_IMPACT            = 25,
  POLICY_MICRO_DARKPOOL          = 26,
  POLICY_SM_INVALIDATION         = 27,
  POLICY_LIQUIDITY_TRAP          = 28,
  POLICY_MICRO_QUOTE_INSTABILITY = 29,
  POLICY_MICRO_THIN_LIQUIDITY    = 30,
  POLICY_MICRO_TOXICITY          = 31,
  POLICY_MICRO_SPREAD_STRESS     = 32,
  POLICY_MICRO_TRUTH             = 33,
  POLICY_INST_HARD_BLOCK         = 34,
  POLICY_BLOCKED_OTHER           = 99
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
    GATE_MAX_TRADES_DAY = 26,
    GATE_INSTITUTIONAL       = 27,
    GATE_MICRO_VPIN          = 28,
    GATE_MICRO_RESILIENCY    = 29,
    GATE_MICRO_OBSERVABILITY = 30,
    GATE_MICRO_VENUE         = 31,
    GATE_MICRO_IMPACT        = 32,
    GATE_MICRO_DARKPOOL      = 33,
    GATE_SM_INVALIDATION     = 34,
    GATE_LIQUIDITY_TRAP      = 35,
    GATE_MICRO_QUOTE_INSTABILITY = 36,
    GATE_MICRO_THIN_LIQUIDITY    = 37,
    GATE_MICRO_TOXICITY          = 38,
    GATE_MICRO_SPREAD_STRESS     = 39,
    GATE_MICRO_TRUTH             = 40,
    GATE_INST_HARD_BLOCK         = 41
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
      case GATE_INSTITUTIONAL:       return "INSTITUTIONAL_STATE";
      case GATE_MICRO_VPIN:          return "MICRO_VPIN";
      case GATE_MICRO_RESILIENCY:    return "MICRO_RESILIENCY";
      case GATE_MICRO_OBSERVABILITY: return "MICRO_OBSERVABILITY";
      case GATE_MICRO_VENUE:         return "MICRO_VENUE";
      case GATE_MICRO_IMPACT:        return "MICRO_IMPACT";
      case GATE_MICRO_DARKPOOL:      return "MICRO_DARKPOOL";
      case GATE_SM_INVALIDATION:     return "SMARTMONEY_INVALIDATION";
      case GATE_LIQUIDITY_TRAP:      return "LIQUIDITY_TRAP";
      case GATE_MICRO_QUOTE_INSTABILITY: return "MICRO_QUOTE_INSTABILITY";
      case GATE_MICRO_THIN_LIQUIDITY:    return "MICRO_THIN_LIQUIDITY";
      case GATE_MICRO_TOXICITY:          return "MICRO_TOXICITY";
      case GATE_MICRO_SPREAD_STRESS:     return "MICRO_SPREAD_STRESS";
      case GATE_MICRO_TRUTH:             return "MICRO_TRUTH";
      case GATE_INST_HARD_BLOCK:         return "INST_HARD_BLOCK";
      default: return "UNKNOWN";
    }
  }
  
  inline string GateReasonToString(const int r){ return ReasonString(r); }

  // --------------------------------------------------------------------------
  // Signal-stack / location-gate transport boundary
  //
  // Policies.mqh may CONSUME upstream canonical gate outcomes for orchestration,
  // cooldown semantics, and telemetry.
  //
  // It must NOT rebuild:
  //   - RawSignalBank_t
  //   - CategorySelectedVector_t
  //   - CategoryPassVector_t
  //   - SignalStackGate_t
  //   - LocationPass_t
  //   - HardInstBlock_t
  //   - FinalIntegratedStateVector_t
  //
  // Ownership of those layers remains upstream in:
  //   InstitutionalStateVector.mqh / CategorySelector.mqh
  // --------------------------------------------------------------------------
  inline bool UpstreamSignalStackAllows(const bool pre_filter_pass,
                                        const bool signal_stack_gate_pass,
                                        const bool location_pass,
                                        const bool execution_gate_pass,
                                        const bool risk_gate_pass,
                                        const bool hard_inst_block)
  {
    return (!hard_inst_block &&
            pre_filter_pass &&
            signal_stack_gate_pass &&
            location_pass &&
            execution_gate_pass &&
            risk_gate_pass);
  }

  inline string UpstreamSignalStackGateSummary(const bool pre_filter_pass,
                                               const bool signal_stack_gate_pass,
                                               const bool location_pass,
                                               const bool execution_gate_pass,
                                               const bool risk_gate_pass,
                                               const bool hard_inst_block)
  {
    return StringFormat("pf=%d ssg=%d loc=%d exg=%d rkg=%d hib=%d",
                        (pre_filter_pass ? 1 : 0),
                        (signal_stack_gate_pass ? 1 : 0),
                        (location_pass ? 1 : 0),
                        (execution_gate_pass ? 1 : 0),
                        (risk_gate_pass ? 1 : 0),
                        (hard_inst_block ? 1 : 0));
  }

  inline bool ReasonTextHasTokenI(const string text,
                                  const string token)
  {
    string a = text;
    string b = token;
    StringToLower(a);
    StringToLower(b);
    return (StringFind(a, b, 0) >= 0);
  }

  inline bool GateReasonTextHasTokenI(const string route_reason,
                                      const string veto_reason,
                                      const string token)
  {
    return (ReasonTextHasTokenI(route_reason, token) ||
            ReasonTextHasTokenI(veto_reason, token));
  }

  inline int GateReasonToPolicyCode(const int gr)
   {
     switch(gr)
     {
       case GATE_OK:                 return POLICY_OK;
       case GATE_SESSION:            return POLICY_SESSION_OFF;
       case GATE_NEWS:               return POLICY_NEWS_BLOCK;
       case GATE_COOLDOWN:           return POLICY_COOLDOWN;
       case GATE_MONTH_TARGET:       return POLICY_MONTH_TARGET;

       case GATE_SPREAD:             return POLICY_SPREAD_HIGH;
       case GATE_MOD_SPREAD:         return POLICY_MOD_SPREAD_HIGH;

       case GATE_MAX_LOSSES_DAY:     return POLICY_MAX_LOSSES;
       case GATE_MAX_TRADES_DAY:     return POLICY_MAX_TRADES;

       case GATE_DAYLOSS:            return POLICY_DAYLOSS_STOP;
       case GATE_DAILYDD:            return POLICY_DAILY_DD;
       case GATE_ACCOUNT_DD:         return POLICY_ACCOUNT_DD;
       case GATE_VOLATILITY:         return POLICY_VOLATILITY;
       case GATE_REGIME:             return POLICY_REGIME_FAIL;
       case GATE_CALM:               return POLICY_CALM_MARKET;
       case GATE_LIQUIDITY:          return POLICY_LIQUIDITY_FAIL;
       case GATE_CONFLICT:           return POLICY_CONFLICT;
       case GATE_ADR:                return POLICY_ADR_CAP;
       case GATE_INSTITUTIONAL:      return POLICY_INSTITUTIONAL_GATE;
       case GATE_MICRO_VPIN:         return POLICY_MICRO_VPIN;
       case GATE_MICRO_RESILIENCY:   return POLICY_MICRO_RESILIENCY;
       case GATE_MICRO_OBSERVABILITY:return POLICY_MICRO_OBSERVABILITY;
       case GATE_MICRO_VENUE:        return POLICY_MICRO_VENUE;
       case GATE_MICRO_IMPACT:       return POLICY_MICRO_IMPACT;
       case GATE_MICRO_DARKPOOL:     return POLICY_MICRO_DARKPOOL;
       case GATE_SM_INVALIDATION:    return POLICY_SM_INVALIDATION;
       case GATE_LIQUIDITY_TRAP:     return POLICY_LIQUIDITY_TRAP;
       case GATE_MICRO_QUOTE_INSTABILITY: return POLICY_MICRO_QUOTE_INSTABILITY;
       case GATE_MICRO_THIN_LIQUIDITY:    return POLICY_MICRO_THIN_LIQUIDITY;
       case GATE_MICRO_TOXICITY:          return POLICY_MICRO_TOXICITY;
       case GATE_MICRO_SPREAD_STRESS:     return POLICY_MICRO_SPREAD_STRESS;
       case GATE_MICRO_TRUTH:             return POLICY_MICRO_TRUTH;
       case GATE_INST_HARD_BLOCK:         return POLICY_INST_HARD_BLOCK;

       default: return POLICY_BLOCKED_OTHER;
     }
   }
   
   inline string SessionReasonFromFlags(const bool session_filter_on, const bool in_session_window)
   {
     if(!session_filter_on) return "FILTER_OFF";
     if(in_session_window)  return "IN_WINDOW";
     return "OUT_OF_WINDOW";
   }

  // ----------------------------------------------------------------------------
  // Tester loose-mode / micro-disable mirrors
  // Mirror the EA-level tester flags through setters from OnInit().
  // ----------------------------------------------------------------------------
  static bool s_tester_loose_gate_mode = false;
  static bool s_disable_microstructure_gates = false;

  inline void SetTesterLooseGateMode(const bool on)
  {
    s_tester_loose_gate_mode = on;
  }

  inline void SetDisableMicrostructureGates(const bool on)
  {
    s_disable_microstructure_gates = on;
  }

  inline bool PolicyTesterLooseModeActive(const Settings &cfg)
  {
    if(s_tester_loose_gate_mode)
      return true;

    #ifdef CFG_HAS_TESTER_LOOSE_GATE_MODE
      if(cfg.tester_loose_gate_mode)
        return true;
    #endif

    return false;
  }

  inline bool PolicyDisableMicrostructureGatesActive(const Settings &cfg)
  {
    if(s_disable_microstructure_gates)
      return true;

    #ifdef CFG_HAS_DISABLE_MICROSTRUCTURE_GATES
      if(cfg.disable_microstructure_gates)
        return true;
    #endif

    if(PolicyTesterLooseModeActive(cfg))
      return true;

    return false;
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
  #define CA_POLMASK_LIQUIDITY          (((ulong)1) << 15)
  #define CA_POLMASK_MICRO_VPIN         (((ulong)1) << 16)
  #define CA_POLMASK_MICRO_RESILIENCY   (((ulong)1) << 17)
  #define CA_POLMASK_MICRO_QUOTE_INSTABILITY (((ulong)1) << 25)
  #define CA_POLMASK_MICRO_THIN_LIQUIDITY    (((ulong)1) << 26)
  #define CA_POLMASK_MICRO_TOXICITY          (((ulong)1) << 27)
  #define CA_POLMASK_MICRO_SPREAD_STRESS     (((ulong)1) << 28)
  #define CA_POLMASK_MICRO_TRUTH            (((ulong)1) << 29)
  #define CA_POLMASK_INSTITUTIONAL      (((ulong)1) << 18)
  #define CA_POLMASK_MICRO_OBSERVABILITY (((ulong)1) << 19)
  #define CA_POLMASK_MICRO_VENUE         (((ulong)1) << 20)
  #define CA_POLMASK_MICRO_IMPACT        (((ulong)1) << 21)
  #define CA_POLMASK_MICRO_DARKPOOL      (((ulong)1) << 22)
  #define CA_POLMASK_SM_INVALIDATION     (((ulong)1) << 23)
  #define CA_POLMASK_LIQUIDITY_TRAP      (((ulong)1) << 24)
  #define CA_POLMASK_MICRO_QUOTE_INSTABILITY (((ulong)1) << 25)
  #define CA_POLMASK_MICRO_THIN_LIQUIDITY    (((ulong)1) << 26)

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
    double day_dd_strict_pct;
    bool   sizing_reset_active;
    int    sizing_reset_sec_left;

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
    string liq_floor_source;

    // Institutional / microstructure hard gate
    bool   institutional_state_loaded;
    bool   institutional_gate_pass;
    bool   institutional_delay_recommended;
    bool   institutional_derisk_recommended;

    double alpha_score;
    double execution_score;
    double risk_score;
    double state_quality01;

    double vpin01;
    double vpin_limit01;
    double resiliency01;
    double resiliency_min01;

    double toxicity01;
    double toxicity_max01;
    double spread_stress01;
    double spread_stress_max01;

    double observability_confidence01;
    double flow_confidence01;
    double observability_min01;
    double venue_coverage01;
    double venue_coverage_min01;
    double cross_venue_dislocation01;
    double cross_venue_dislocation_max01;

    double impact_beta01;
    double impact_beta_max01;
    double impact_lambda01;
    double impact_lambda_max01;

    double truth_tier01;
    double truth_tier_aggressive_min01;
    int    execution_posture_mode;
    bool   reduced_only;
    bool   invalidation_event01;
    bool   liquidity_trap_event01;

    double darkpool01;
    double darkpool_min01;
    double darkpool_contradiction01;
    double darkpool_contradiction_max01;

    double sd_ob_invalidation_proximity01;
    double sd_ob_invalidation_max01;

    double liquidity_vacuum01;
    double liquidity_vacuum_max01;
    double liquidity_hunt01;
    double liquidity_hunt_max01;

    double observability_penalty01;

    bool   direct_micro_available;
    bool   proxy_micro_available;
    int    flow_mode;

    double inst_ofi01;
    double inst_obi01;
    double inst_cvd01;

    double inst_delta_proxy01;
    double inst_footprint01;
    double inst_profile01;
    double inst_absorption01;
    double inst_replenishment01;
    double inst_vwap_location01;
    double inst_liquidity_reject01;

    int    confluence_veto_mask;
    string route_reason;
    string veto_reason;

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

    r.institutional_state_loaded       = false;
    r.institutional_gate_pass          = true;
    r.institutional_delay_recommended  = false;
    r.institutional_derisk_recommended = false;

    r.alpha_score      = 0.0;
    r.execution_score  = 1.0;
    r.risk_score       = 1.0;
    r.state_quality01  = 1.0;

    r.vpin01           = (double)POLICIES_INST_DEFAULT_VPIN01;
    r.vpin_limit01     = 1.0;
    r.resiliency01     = (double)POLICIES_INST_DEFAULT_RESILIENCY01;
    r.resiliency_min01 = 0.0;

    r.toxicity01       = (double)POLICIES_INST_DEFAULT_TOXICITY01;
    r.toxicity_max01   = (double)POLICIES_INST_MAX_TOXICITY01;
    r.spread_stress01  = (double)POLICIES_INST_DEFAULT_SPREAD_STRESS01;
    r.spread_stress_max01 = (double)POLICIES_INST_MAX_SPREAD_STRESS01;

    r.observability_confidence01 = (double)POLICIES_INST_DEFAULT_OBSERVABILITY01;
    r.flow_confidence01         = (double)POLICIES_INST_DEFAULT_OBSERVABILITY01;
    r.observability_min01        = (double)POLICIES_INST_MIN_OBSERVABILITY01;
    r.venue_coverage01           = (double)POLICIES_INST_DEFAULT_VENUE_COVERAGE01;
    r.venue_coverage_min01       = (double)POLICIES_INST_MIN_VENUE_COVERAGE01;
    r.cross_venue_dislocation01  = (double)POLICIES_INST_DEFAULT_XVENUE_DISLOCATION01;
    r.cross_venue_dislocation_max01 = (double)POLICIES_INST_VETO_XVENUE_DISLOCATION01;

    r.impact_beta01       = (double)POLICIES_INST_DEFAULT_IMPACT_BETA01;
    r.impact_beta_max01   = (double)POLICIES_INST_MAX_IMPACT_BETA01;
    r.impact_lambda01     = (double)POLICIES_INST_DEFAULT_IMPACT_LAMBDA01;
    r.impact_lambda_max01 = (double)POLICIES_INST_MAX_IMPACT_LAMBDA01;

    r.truth_tier01                 = 1.0;
    r.truth_tier_aggressive_min01  = PolicyTruthTierAggressiveMin01();
    r.execution_posture_mode       = 0;
    r.reduced_only                 = false;
    r.invalidation_event01         = false;
    r.liquidity_trap_event01       = false;

    r.darkpool01                    = (double)POLICIES_INST_DEFAULT_DARKPOOL01;
    r.darkpool_min01                = (double)POLICIES_INST_MIN_DARKPOOL01;
    r.darkpool_contradiction01      = (double)POLICIES_INST_DEFAULT_DARKPOOL_CONTRADICTION01;
    r.darkpool_contradiction_max01  = (double)POLICIES_INST_MAX_DARKPOOL_CONTRADICTION01;

    r.sd_ob_invalidation_proximity01= (double)POLICIES_INST_DEFAULT_SD_OB_INVALIDATION_PROXIMITY01;
    r.sd_ob_invalidation_max01      = (double)POLICIES_INST_MAX_SD_OB_INVALIDATION_PROXIMITY01;

    r.liquidity_vacuum01            = (double)POLICIES_INST_DEFAULT_LIQUIDITY_VACUUM01;
    r.liquidity_vacuum_max01        = (double)POLICIES_INST_MAX_LIQUIDITY_VACUUM01;
    r.liquidity_hunt01              = (double)POLICIES_INST_DEFAULT_LIQUIDITY_HUNT01;
    r.liquidity_hunt_max01          = (double)POLICIES_INST_MAX_LIQUIDITY_HUNT01;

    r.observability_penalty01       = Clamp01(1.0 - r.observability_confidence01);

    r.direct_micro_available        = false;
    r.proxy_micro_available         = false;
    r.flow_mode                     = POLICIES_INST_FLOW_MODE_PROXY;

    r.inst_ofi01                    = 0.5;
    r.inst_obi01                    = 0.5;
    r.inst_cvd01                    = 0.5;

    r.inst_delta_proxy01            = 0.5;
    r.inst_footprint01              = 0.5;
    r.inst_profile01                = 0.5;
    r.inst_absorption01             = 0.5;
    r.inst_replenishment01          = 0.5;
    r.inst_vwap_location01          = 0.5;
    r.inst_liquidity_reject01       = 0.0;

    r.confluence_veto_mask          = 0;
    r.route_reason                  = "";
    r.veto_reason                   = "none";
    r.liq_floor_source             = "default";
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

  inline double PolicyQuoteInstability01(const PolicyResult &r)
  {
    return Clamp01(MathMax(Clamp01(1.0 - r.venue_coverage01),
                           r.cross_venue_dislocation01));
  }

  inline double PolicyThinLiquidity01(const PolicyResult &r)
  {
    return Clamp01(MathMax(r.liquidity_vacuum01,
                           r.liquidity_hunt01));
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
  inline bool PolicyTesterRelaxActive()
  {
    if(s_tester_loose_gate_mode)
      return true;

    if(POLICY_TESTER_RELAX == 0)
      return false;

    if(MQLInfoInteger(MQL_TESTER) != 0)
      return true;

    if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return true;

    return false;
  }

  inline bool PolicyTesterRuntime()
  {
    if(MQLInfoInteger(MQL_TESTER) != 0)
      return true;

    if(MQLInfoInteger(MQL_OPTIMIZATION) != 0)
      return true;

    return false;
  }

  inline double PolicyStateQualityMin01()
  {
    if(PolicyTesterRelaxActive())
      return 0.0;

    return (double)POLICIES_INST_MIN_STATE_QUALITY01;
  }

  inline double PolicyTruthTierAggressiveMin01()
  {
    if(PolicyTesterRelaxActive())
      return 0.0;

    return (double)POLICIES_INST_MIN_TRUTH_TIER01_AGGRESSIVE;
  }

  inline bool PolicySessionGateEnabled()
  {
    if(SESSION_GATING_ENABLED == 0)
      return false;

    if(PolicyTesterRelaxActive())
      return false;

    return true;
  }

  inline bool PolicyNewsGateEnabled()
  {
    if(NEWS_ENABLED == 0)
      return false;

    if(PolicyTesterRelaxActive())
      return false;

    return true;
  }

  inline bool PolicyVolBreakerGateEnabled()
  {
    if(VOL_BREAKER_ENABLED == 0)
      return false;

    if(PolicyTesterRelaxActive())
      return false;

    return true;
  }

  inline bool PolicyTesterDegradedActive(const Settings &cfg)
  {
    if(PolicyTesterRuntime())
      return true;

    if(Config::CfgTesterDegradedModeActive(cfg))
      return true;

    return false;
  }

  inline bool PolicyMicroRelaxActive(const Settings &cfg)
  {
    if(PolicyDisableMicrostructureGatesActive(cfg))
      return true;

    if(PolicyTesterDegradedActive(cfg))
      return true;

    return false;
  }

  inline double PolicyRelaxMinThreshold01(const double base_value)
  {
    return Clamp01(base_value * 0.5);
  }

  inline double PolicyRelaxMaxThreshold01(const double base_value)
  {
    return Clamp01(base_value + (1.0 - base_value) * 0.5);
  }

  inline double PolicyHalfMinThreshold(const double base_value)
  {
    if(base_value <= 0.0)
      return 0.0;

    return base_value * 0.5;
  }

  inline double PolicyLooseCapThreshold(const double base_value)
  {
    if(base_value <= 0.0)
      return 0.0;

    return base_value * 2.0;
  }

  inline bool PolicySessionBypassActive(const Settings &cfg)
  {
    if(PolicyTesterDegradedActive(cfg))
      return true;

    return false;
  }

  inline bool PolicyNewsBypassActive(const Settings &cfg)
  {
    if(PolicyTesterDegradedActive(cfg))
      return true;

    if(!Config::CfgNewsBlockEnabled(cfg))
      return true;

    return false;
  }

  inline bool PolicyRegimeBypassActive(const Settings &cfg)
  {
    if(PolicyTesterDegradedActive(cfg))
      return true;

    if(!Config::CfgRegimeGateEnabled(cfg))
      return true;

    return false;
  }

  inline bool PolicyLiquidityBypassActive(const Settings &cfg)
  {
    if(PolicyTesterDegradedActive(cfg))
      return true;

    if(!Config::CfgLiquidityGateEnabled(cfg))
      return true;

    return false;
  }

  inline bool PolicyRiskCapsRelaxActive(const Settings &cfg)
  {
    if(PolicyTesterDegradedActive(cfg))
      return true;

    return false;
  }

  inline bool PolicyInstitutionalBypassActive(const Settings &cfg)
  {
    if(PolicyTesterDegradedActive(cfg))
      return true;

    return false;
  }

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
     if(!PolicySessionGateEnabled())
       return false;

     if(PolicySessionBypassActive(cfg))
       return false;

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

  inline double CfgSizingResetMult(const Settings &cfg)
   {
     #ifdef CFG_HAS_BIGLOSS_RESET_MULT
       const double m = cfg.bigloss_reset_mult;
       return Clamp((m > 0.0 ? m : POLICIES_SIZING_RESET_MULT_DEFAULT), 0.05, 1.0);
     #else
       #ifdef CFG_HAS_SIZING_RESET_MULT
         const double m = cfg.sizing_reset_mult;
         return Clamp((m > 0.0 ? m : POLICIES_SIZING_RESET_MULT_DEFAULT), 0.05, 1.0);
       #else
         return POLICIES_SIZING_RESET_MULT_DEFAULT;
       #endif
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
    double threshold = 0.0;

    #ifdef CFG_HAS_CALM_MIN_ATR_PIPS
      threshold = (cfg.calm_min_atr_pips > 0.0 ? cfg.calm_min_atr_pips : 0.0);
    #else
      threshold = 0.0;
    #endif

    if(PolicyTesterRelaxActive())
      threshold = PolicyHalfMinThreshold(threshold);

    return threshold;
  }
  
  inline double CfgCalmMinATRtoSpread(const Settings &cfg)
  {
    double threshold = 0.0;

    #ifdef CFG_HAS_CALM_MIN_ATR_TO_SPREAD
      threshold = (cfg.calm_min_atr_to_spread > 0.0 ? cfg.calm_min_atr_to_spread : 0.0);
    #else
      threshold = 0.0;
    #endif

    if(PolicyTesterRelaxActive())
      threshold = PolicyHalfMinThreshold(threshold);

    return threshold;
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

   inline bool CfgNewsPolicyEnabled(const Settings &cfg)
   {
     if(!PolicyNewsGateEnabled())
       return false;

     if(PolicyNewsBypassActive(cfg))
       return false;

     return CfgNewsOn(cfg);
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
      if(cfg.liq_min_ratio > 0.0)
        return Clamp(cfg.liq_min_ratio, 0.50, 10.0);
    #endif
    return 1.50;
  }

  inline double CfgLiqMinRatioTester(const Settings &cfg)
  {
    #ifdef CFG_HAS_LIQ_MIN_RATIO_TESTER
      if(cfg.liq_min_ratio_tester > 0.0)
        return Clamp(cfg.liq_min_ratio_tester, 0.50, 10.0);
    #endif
    return 0.0;
  }

  inline bool CfgLiqInvalidHardFail(const Settings &cfg)
  {
    #ifdef CFG_HAS_LIQ_INVALID_HARDFAIL
      return (bool)cfg.liq_hard_fail_on_invalid_metrics;
    #else
      return false;
    #endif
  }

  inline bool CfgLiqFloorAdapted(const Settings &cfg)
  {
    const bool in_tester =
       (MQLInfoInteger(MQL_TESTER) != 0) ||
       (MQLInfoInteger(MQL_OPTIMIZATION) != 0);

    if(!in_tester)
      return false;

    const double tester_floor = CfgLiqMinRatioTester(cfg);
    if(tester_floor <= 0.0)
      return false;

    return (MathAbs(tester_floor - CfgLiqMinRatio(cfg)) > 0.000001);
  }

  inline double CfgLiqMinRatioEffective(const Settings &cfg)
  {
    const bool in_tester =
       (MQLInfoInteger(MQL_TESTER) != 0) ||
       (MQLInfoInteger(MQL_OPTIMIZATION) != 0);

    if(in_tester)
    {
      const double tester_floor = CfgLiqMinRatioTester(cfg);
      if(tester_floor > 0.0)
        return tester_floor;
    }

    return CfgLiqMinRatio(cfg);
  }

  inline bool CfgRegimeGateOn(const Settings &cfg)
  {
    if(PolicyRegimeBypassActive(cfg))
      return false;

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

  inline bool CfgMicroVPINGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_VPIN_GATE_ON
      return (bool)cfg.ms_vpin_gate_on;
    #else
      #ifdef CFG_HAS_VPIN_GATE_ON
        return (bool)cfg.vpin_gate_on;
      #else
        return false;
      #endif
    #endif
  }

  inline double CfgMicroVPINMax01(const Settings &cfg)
  {
    double threshold = 1.0;

    #ifdef CFG_HAS_MS_VPIN_THRESHOLD
      threshold = Clamp01(cfg.ms_vpin_threshold);
    #else
      #ifdef CFG_HAS_VPIN_THRESHOLD
        threshold = Clamp01(cfg.vpin_threshold);
      #else
        threshold = 1.0;
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline bool CfgMicroToxicityGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_TOXICITY_GATE_ON
      return (bool)cfg.ms_toxicity_gate_on;
    #else
      #ifdef CFG_HAS_INST_TOXICITY_GATE_ON
        return (bool)cfg.inst_toxicity_gate_on;
      #else
        #ifdef CFG_HAS_TOXICITY_GATE_ON
          return (bool)cfg.toxicity_gate_on;
        #else
          return true;
        #endif
      #endif
    #endif
  }

  inline double CfgMicroToxicityMax01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MAX_TOXICITY01;

    #ifdef CFG_HAS_MS_TOXICITY_THRESHOLD
      threshold = Clamp01(cfg.ms_toxicity_threshold);
    #else
      #ifdef CFG_HAS_INST_MAX_TOXICITY01
        threshold = Clamp01(cfg.inst_max_toxicity01);
      #else
        #ifdef CFG_HAS_TOXICITY_THRESHOLD
          threshold = Clamp01(cfg.toxicity_threshold);
        #else
          threshold = (double)POLICIES_INST_MAX_TOXICITY01;
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline bool CfgMicroSpreadStressGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_SPREAD_STRESS_GATE_ON
      return (bool)cfg.ms_spread_stress_gate_on;
    #else
      #ifdef CFG_HAS_INST_SPREAD_STRESS_GATE_ON
        return (bool)cfg.inst_spread_stress_gate_on;
      #else
        #ifdef CFG_HAS_SPREAD_STRESS_GATE_ON
          return (bool)cfg.spread_stress_gate_on;
        #else
          return true;
        #endif
      #endif
    #endif
  }

  inline double CfgMicroSpreadStressMax01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MAX_SPREAD_STRESS01;

    #ifdef CFG_HAS_MS_MAX_SPREAD_STRESS01
      threshold = Clamp01(cfg.ms_max_spread_stress01);
    #else
      #ifdef CFG_HAS_INST_SPREAD_STRESS_MAX01
        threshold = Clamp01(cfg.inst_spread_stress_max01);
      #else
        #ifdef CFG_HAS_SPREAD_STRESS_MAX01
          threshold = Clamp01(cfg.spread_stress_max01);
        #else
          threshold = (double)POLICIES_INST_MAX_SPREAD_STRESS01;
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline bool CfgMicroResiliencyGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_RESILIENCY_GATE_ON
      return (bool)cfg.ms_resiliency_gate_on;
    #else
      #ifdef CFG_HAS_MS_RESIL_GATE_ON
        return (bool)cfg.ms_resil_gate_on;
      #else
        #ifdef CFG_HAS_RESILIENCY_GATE_ON
          return (bool)cfg.resiliency_gate_on;
        #else
          return false;
        #endif
      #endif
    #endif
  }

  inline double CfgMicroResiliencyMin01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MIN_RESILIENCY01;

    #ifdef CFG_HAS_MS_RESILIENCY_THRESHOLD
      threshold = Clamp01(cfg.ms_resiliency_threshold);
    #else
      #ifdef CFG_HAS_MS_RESIL_THRESHOLD
        threshold = Clamp01(cfg.ms_resil_threshold);
      #else
        #ifdef CFG_HAS_RESILIENCY_THRESHOLD
          threshold = Clamp01(cfg.resiliency_threshold);
        #else
          threshold = (double)POLICIES_INST_MIN_RESILIENCY01;
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMinThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline double CfgMicroObservabilityMin01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MIN_OBSERVABILITY01;

    #ifdef CFG_HAS_MS_MIN_OBSERVABILITY01
      threshold = Clamp01(cfg.ms_min_observability01);
    #else
      #ifdef CFG_HAS_INST_MIN_OBSERVABILITY01
        threshold = Clamp01(cfg.inst_min_observability01);
      #else
        #ifdef CFG_HAS_MIN_OBSERVABILITY01
          threshold = Clamp01(cfg.min_observability01);
        #else
          threshold = (double)POLICIES_INST_MIN_OBSERVABILITY01;
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMinThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline double CfgMicroVenueCoverageMin01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MIN_VENUE_COVERAGE01;

    #ifdef CFG_HAS_MS_MIN_VENUE_COVERAGE01
      threshold = Clamp01(cfg.ms_min_venue_coverage01);
    #else
      #ifdef CFG_HAS_INST_MIN_VENUE_COVERAGE01
        threshold = Clamp01(cfg.inst_min_venue_coverage01);
      #else
        #ifdef CFG_HAS_MIN_VENUE_COVERAGE01
          threshold = Clamp01(cfg.min_venue_coverage01);
        #else
          threshold = (double)POLICIES_INST_MIN_VENUE_COVERAGE01;
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMinThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline double CfgMicroXVenueDislocationMax01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_VETO_XVENUE_DISLOCATION01;

    #ifdef CFG_HAS_MS_MAX_XVENUE_DISLOCATION01
      threshold = Clamp01(cfg.ms_max_xvenue_dislocation01);
    #else
      #ifdef CFG_HAS_INST_MAX_XVENUE_DISLOCATION01
        threshold = Clamp01(cfg.inst_max_xvenue_dislocation01);
      #else
        #ifdef CFG_HAS_XVENUE_DISLOCATION_MAX01
          threshold = Clamp01(cfg.xvenue_dislocation_max01);
        #else
          #ifdef CFG_HAS_MAX_XVENUE_DISLOCATION01
            threshold = Clamp01(cfg.max_xvenue_dislocation01);
          #else
            threshold = (double)POLICIES_INST_VETO_XVENUE_DISLOCATION01;
          #endif
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline bool CfgMicroImpactGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_IMPACT_GATE_ON
      return (bool)cfg.ms_impact_gate_on;
    #else
      #ifdef CFG_HAS_IMPACT_GATE_ON
        return (bool)cfg.impact_gate_on;
      #else
        #ifdef CFG_HAS_INST_IMPACT_GATE_ON
          return (bool)cfg.inst_impact_gate_on;
        #else
          return true;
        #endif
      #endif
    #endif
  }

  inline double CfgMicroImpactBetaMax01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MAX_IMPACT_BETA01;

    #ifdef CFG_HAS_MS_MAX_IMPACT_BETA01
      threshold = Clamp01(cfg.ms_max_impact_beta01);
    #else
      #ifdef CFG_HAS_INST_IMPACT_BETA_MAX01
        threshold = Clamp01(cfg.inst_impact_beta_max01);
      #else
        #ifdef CFG_HAS_IMPACT_BETA_MAX01
          threshold = Clamp01(cfg.impact_beta_max01);
        #else
          #ifdef CFG_HAS_MAX_IMPACT_BETA01
            threshold = Clamp01(cfg.max_impact_beta01);
          #else
            threshold = (double)POLICIES_INST_MAX_IMPACT_BETA01;
          #endif
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline double CfgMicroImpactLambdaMax01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MAX_IMPACT_LAMBDA01;

    #ifdef CFG_HAS_MS_MAX_IMPACT_LAMBDA01
      threshold = Clamp01(cfg.ms_max_impact_lambda01);
    #else
      #ifdef CFG_HAS_INST_IMPACT_LAMBDA_MAX01
        threshold = Clamp01(cfg.inst_impact_lambda_max01);
      #else
        #ifdef CFG_HAS_IMPACT_LAMBDA_MAX01
          threshold = Clamp01(cfg.impact_lambda_max01);
        #else
          #ifdef CFG_HAS_MAX_IMPACT_LAMBDA01
            threshold = Clamp01(cfg.max_impact_lambda01);
          #else
            threshold = (double)POLICIES_INST_MAX_IMPACT_LAMBDA01;
          #endif
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline bool CfgMicroDarkPoolGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_DARKPOOL_GATE_ON
      return (bool)cfg.ms_darkpool_gate_on;
    #else
      #ifdef CFG_HAS_DARKPOOL_GATE_ON
        return (bool)cfg.darkpool_gate_on;
      #else
        #ifdef CFG_HAS_DARK_POOL_GATE_ON
          return (bool)cfg.dark_pool_gate_on;
        #else
          #ifdef CFG_HAS_INST_DARKPOOL_GATE_ON
            return (bool)cfg.inst_darkpool_gate_on;
          #else
            return true;
          #endif
        #endif
      #endif
    #endif
  }

  inline double CfgMicroDarkPoolMin01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MIN_DARKPOOL01;

    #ifdef CFG_HAS_MS_MIN_DARKPOOL01
      threshold = Clamp01(cfg.ms_min_darkpool01);
    #else
      #ifdef CFG_HAS_INST_DARKPOOL_MIN01
        threshold = Clamp01(cfg.inst_darkpool_min01);
      #else
        #ifdef CFG_HAS_DARKPOOL_MIN01
          threshold = Clamp01(cfg.darkpool_min01);
        #else
          #ifdef CFG_HAS_DARK_POOL_CONFIDENCE_MIN01
            threshold = Clamp01(cfg.dark_pool_confidence_min01);
          #else
            threshold = (double)POLICIES_INST_MIN_DARKPOOL01;
          #endif
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMinThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline double CfgMicroDarkPoolContradictionMax01(const Settings &cfg)
  {
    double threshold = (double)POLICIES_INST_MAX_DARKPOOL_CONTRADICTION01;

    #ifdef CFG_HAS_MS_MAX_DARKPOOL_CONTRADICTION01
      threshold = Clamp01(cfg.ms_max_darkpool_contradiction01);
    #else
      #ifdef CFG_HAS_INST_DARKPOOL_CONTRADICTION_MAX01
        threshold = Clamp01(cfg.inst_darkpool_contradiction_max01);
      #else
        #ifdef CFG_HAS_DARKPOOL_CONTRADICTION_MAX01
          threshold = Clamp01(cfg.darkpool_contradiction_max01);
        #else
          #ifdef CFG_HAS_DARK_POOL_CONTRADICTION_MAX01
            threshold = Clamp01(cfg.dark_pool_contradiction_max01);
          #else
            threshold = (double)POLICIES_INST_MAX_DARKPOOL_CONTRADICTION01;
          #endif
        #endif
      #endif
    #endif

    if(PolicyMicroRelaxActive(cfg))
      threshold = PolicyRelaxMaxThreshold01(threshold);

    return Clamp01(threshold);
  }

  inline bool CfgSmartMoneyInvalidationGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_SD_OB_INVALIDATION_GATE_ON
      return (bool)cfg.ms_sd_ob_invalidation_gate_on;
    #else
      #ifdef CFG_HAS_SD_OB_INVALIDATION_GATE_ON
        return (bool)cfg.sd_ob_invalidation_gate_on;
      #else
        #ifdef CFG_HAS_SM_INVALIDATION_GATE_ON
          return (bool)cfg.sm_invalidation_gate_on;
        #else
          return true;
        #endif
      #endif
    #endif
  }

  inline double CfgSmartMoneyInvalidationMax01(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_SD_OB_INVALIDATION_MAX01
      return Clamp01(cfg.ms_sd_ob_invalidation_max01);
    #else
      #ifdef CFG_HAS_SD_OB_INVALIDATION_MAX01
        return Clamp01(cfg.sd_ob_invalidation_max01);
      #else
        #ifdef CFG_HAS_SM_INVALIDATION_MAX01
          return Clamp01(cfg.sm_invalidation_max01);
        #else
          return (double)POLICIES_INST_MAX_SD_OB_INVALIDATION_PROXIMITY01;
        #endif
      #endif
    #endif
  }

  inline bool CfgLiquidityTrapGateOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_LIQUIDITY_TRAP_GATE_ON
      return (bool)cfg.ms_liquidity_trap_gate_on;
    #else
      #ifdef CFG_HAS_LIQUIDITY_TRAP_GATE_ON
        return (bool)cfg.liquidity_trap_gate_on;
      #else
        #ifdef CFG_HAS_LIQUIDITY_HUNT_GATE_ON
          return (bool)cfg.liquidity_hunt_gate_on;
        #else
          return true;
        #endif
      #endif
    #endif
  }

  inline double CfgLiquidityVacuumMax01(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_LIQUIDITY_VACUUM_MAX01
      return Clamp01(cfg.ms_liquidity_vacuum_max01);
    #else
      #ifdef CFG_HAS_INST_LIQUIDITY_VACUUM_MAX01
        return Clamp01(cfg.inst_liquidity_vacuum_max01);
      #else
        #ifdef CFG_HAS_LIQUIDITY_VACUUM_MAX01
          return Clamp01(cfg.liquidity_vacuum_max01);
        #else
          return (double)POLICIES_INST_MAX_LIQUIDITY_VACUUM01;
        #endif
      #endif
    #endif
  }

  inline double CfgLiquidityHuntMax01(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_LIQUIDITY_HUNT_MAX01
      return Clamp01(cfg.ms_liquidity_hunt_max01);
    #else
      #ifdef CFG_HAS_INST_LIQUIDITY_HUNT_MAX01
        return Clamp01(cfg.inst_liquidity_hunt_max01);
      #else
        #ifdef CFG_HAS_LIQUIDITY_HUNT_MAX01
          return Clamp01(cfg.liquidity_hunt_max01);
        #else
          return (double)POLICIES_INST_MAX_LIQUIDITY_HUNT01;
        #endif
      #endif
    #endif
  }

  inline double CfgMicroContinuationObservabilityMin01(const Settings &cfg)
  {
    double baseMin = CfgMicroObservabilityMin01(cfg);

    #ifdef CFG_HAS_MS_MODE_OBSERVABILITY_THRESHOLDS
      const double pxy = Clamp01(cfg.ms_observability_proxy_min01);
      if(pxy > baseMin)
        baseMin = pxy;
    #endif

    return baseMin;
  }

   inline double CfgMicroTruthTierAggressiveMin01(const Settings &cfg)
   {
     #ifdef CFG_HAS_MS_ARCHETYPE_TRUTH_THRESHOLDS
       if(cfg.ms_truth_min_breakout01 > 0.0)
         return Clamp01(cfg.ms_truth_min_breakout01);
     #endif
   
     return PolicyTruthTierAggressiveMin01();
   }

  inline double CfgMicroProxyDeriskMult01(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_PROXY_DERISK_MULT01
      return Clamp(cfg.ms_proxy_derisk_mult01, 0.10, 1.00);
    #else
      #ifdef CFG_HAS_INST_PROXY_DERISK_MULT01
        return Clamp(cfg.inst_proxy_derisk_mult01, 0.10, 1.00);
      #else
        return (double)POLICIES_INST_PROXY_DERISK_MULT01;
      #endif
    #endif
  }

  inline double CfgMicroStructureOnlyDeriskMult01(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_STRUCTURE_ONLY_DERISK_MULT01
      return Clamp(cfg.ms_structure_only_derisk_mult01, 0.05, 1.00);
    #else
      #ifdef CFG_HAS_INST_STRUCTURE_ONLY_DERISK_MULT01
        return Clamp(cfg.inst_structure_only_derisk_mult01, 0.05, 1.00);
      #else
        return (double)POLICIES_INST_STRUCTURE_ONLY_DERISK_MULT01;
      #endif
    #endif
  }

  inline bool CfgMicroStructureOnlyAggressiveVetoOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_STRUCTURE_ONLY_AGGRESSIVE_VETO
      return (bool)cfg.ms_structure_only_aggressive_veto;
    #else
      #ifdef CFG_HAS_INST_STRUCTURE_ONLY_AGGRESSIVE_VETO
        return (bool)cfg.inst_structure_only_aggressive_veto;
      #else
        return (bool)POLICIES_INST_ENABLE_STRUCTURE_ONLY_AGGRESSIVE_VETO;
      #endif
    #endif
  }

  inline bool CfgMicroProxyForceReducedOnlyOn(const Settings &cfg)
  {
    #ifdef CFG_HAS_MS_PROXY_FORCE_REDUCED_ONLY
      return (bool)cfg.ms_proxy_force_reduced_only;
    #else
      #ifdef CFG_HAS_INST_PROXY_FORCE_REDUCED_ONLY
        return (bool)cfg.inst_proxy_force_reduced_only;
      #else
        return (bool)POLICIES_INST_ENABLE_PROXY_FORCE_REDUCED_ONLY;
      #endif
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
    double threshold = 0.0;

    #ifdef CFG_HAS_ADR_CAP_MULT
      threshold = (cfg.adr_cap_mult > 0.0 ? cfg.adr_cap_mult : 0.0);
    #else
      threshold = 0.0;
    #endif

    if(PolicyTesterRelaxActive())
      threshold = PolicyLooseCapThreshold(threshold);

    return threshold;
  }
  inline double CfgADRMinPips(const Settings &cfg)
  {
    double threshold = 0.0;

    #ifdef CFG_HAS_ADR_MIN_PIPS
      threshold = (cfg.adr_min_pips > 0.0 ? cfg.adr_min_pips : 0.0);
    #else
      threshold = 0.0;
    #endif

    if(PolicyTesterRelaxActive())
      threshold = PolicyHalfMinThreshold(threshold);

    return threshold;
  }
  inline double CfgADRMaxPips(const Settings &cfg)
  {
    double threshold = 0.0;

    #ifdef CFG_HAS_ADR_MAX_PIPS
      threshold = (cfg.adr_max_pips > 0.0 ? cfg.adr_max_pips : 0.0);
    #else
      threshold = 0.0;
    #endif

    if(PolicyTesterRelaxActive())
      threshold = PolicyLooseCapThreshold(threshold);

    return threshold;
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

  inline bool AllowRuntimePolicyOverrides()
  {
    if(MQLInfoInteger(MQL_TESTER) != 0)       return true;
    if(MQLInfoInteger(MQL_OPTIMIZATION) != 0) return true;

    #ifdef POLICIES_ALLOW_RUNTIME_OVERRIDES_LIVE
      return true;
    #endif

    return false;
  }

  inline bool OverrideSetSpreadCap(const string sym, const int pts)
  {
    if(!AllowRuntimePolicyOverrides()) return false;
    const int k=_EnsureOver(sym);
    if(k<0) return false;
    s_over[k].max_spread_pts=pts;
    s_over[k].has_spread=true;
    return true;
  }

  inline bool OverrideSetSession(const string sym, const bool on)
  {
    if(!AllowRuntimePolicyOverrides()) return false;
    const int k=_EnsureOver(sym);
    if(k<0) return false;
    s_over[k].session_filter=on;
    s_over[k].has_session=true;
    return true;
  }

  inline bool OverrideSetLiquidityFloor(const string sym, const double ratio)
  {
    if(!AllowRuntimePolicyOverrides()) return false;
    const int k=_EnsureOver(sym);
    if(k<0) return false;
    s_over[k].liq_min_ratio=ratio;
    s_over[k].has_liq=true;
    return true;
  }

  inline bool OverrideSetNewsMask(const string sym, const int mask)
  {
    if(!AllowRuntimePolicyOverrides()) return false;
    const int k=_EnsureOver(sym);
    if(k<0) return false;
    s_over[k].news_mask=mask;
    s_over[k].has_news_mask=true;
    return true;
  }

  inline bool OverrideClear(const string sym)
  {
    if(!AllowRuntimePolicyOverrides()) return false;
    const int k=_FindOverIdx(sym);
    if(k<0) return false;
    for(int i=k;i<s_over_n-1;i++) s_over[i]=s_over[i+1];
    s_over_n--;
    return true;
  }

  inline void OverrideClearAll()
  {
    if(!AllowRuntimePolicyOverrides()) return;
    s_over_n=0;
  }

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
  {
    if(PolicySessionBypassActive(cfg))
      return false;

    const int k = _FindOverIdx(sym);
    if(k >= 0 && s_over[k].has_session)
      return s_over[k].session_filter;

    return CfgSessionFilter(cfg);
  }
  
  inline double EffLiqMinRatio(const Settings &cfg, const string sym, const double default_floor)
  { const int k=_FindOverIdx(sym); if(k>=0 && s_over[k].has_liq) return s_over[k].liq_min_ratio; return (default_floor>0.0? default_floor : CfgLiqMinRatio(cfg)); }

  inline bool _HasExplicitConfiguredLiqFloor(const Settings &cfg)
  {
    #ifdef CFG_HAS_LIQ_MIN_RATIO
      if(cfg.liq_min_ratio > 0.0)
        return true;
    #endif

    #ifdef CFG_HAS_LIQ_MIN_RATIO_TESTER
      const bool in_tester =
         (MQLInfoInteger(MQL_TESTER) != 0) ||
         (MQLInfoInteger(MQL_OPTIMIZATION) != 0);

      if(in_tester && cfg.liq_min_ratio_tester > 0.0)
        return true;
    #endif

    return false;
  }

  inline string EffLiqMinRatioSource(const Settings &cfg,
                                     const string sym,
                                     const double default_floor)
  {
    const int k = _FindOverIdx(sym);
    if(k >= 0 && s_over[k].has_liq)
      return "override";

    const double cfg_floor = CfgLiqMinRatioEffective(cfg);
    const double active_floor = (default_floor > 0.0 ? default_floor : cfg_floor);

    if(MathAbs(active_floor - cfg_floor) > 0.000001)
      return "session-adjusted";

    if(_HasExplicitConfiguredLiqFloor(cfg))
      return "config";

    return "default";
  }

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

     if(PolicyRiskCapsRelaxActive(cfg))
     {
       _GateDetail(cfg, GATE_ADR, sym, "tester_bypass=1 adr_cap_relaxed=1");
       return true;
     }

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
  static double   s_last_day_dd_active_pct = 0.0;
  static double   s_last_day_dd_strict_pct = 0.0;

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

    if(PolicyRiskCapsRelaxActive(cfg))
    {
      s_last_day_dd_active_pct = 0.0;
      s_last_day_dd_strict_pct = 0.0;
      return false;
    }

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

   // Centralized telemetry for HUD / policy consumers.
   s_last_day_dd_active_pct = dd_pct_out;
   s_last_day_dd_strict_pct = MathMax(fixed_pct, adaptive_now_pct);
   
   // Option B: when adaptive is enabled, it REPLACES fixed-base DD for the daily equity stop.
   return (adaptive_on ? adaptive_hit : fixed_hit);
  }

  inline double LastDailyDDActivePct(){ return s_last_day_dd_active_pct; }
  inline double LastDailyDDStrictPct(){ return s_last_day_dd_strict_pct; }

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

     if(PolicyRiskCapsRelaxActive(cfg))
       return false;
   
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

    if(PolicyRiskCapsRelaxActive(cfg))
    {
      const double sp_now = MarketData::SpreadPoints(sym);
      const double tester_cap_pts = MarketData::PointsFromPips(sym, 100.0);

      if(tester_cap_pts > 0.0 && sp_now > tester_cap_pts)
      {
        reason = GATE_SPREAD;
        _GateDetail(cfg, reason, sym,
                    StringFormat("tester_relax=1 sp=%.1f tester_cap_pts=%.1f",
                                 sp_now, tester_cap_pts));
        return false;
      }

      _GateDetail(cfg, GATE_SPREAD, sym, "tester_bypass=1 spread_gate_relaxed=1");
      return true;
    }

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

    if(PolicyRiskCapsRelaxActive(cfg))
      return false;

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

    if(PolicyRiskCapsRelaxActive(cfg))
    {
      _GateDetail(cfg, GATE_CALM, sym, "tester_bypass=1 calm_gate_relaxed=1");
      return true;
    }

    if(!CfgCalmEnable(cfg)) return true;

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = CfgATRShort(cfg);

    const double atr_s = AtrPts(sym, tf, cfg, shortP, 1);
    if(atr_s<=0.0)
    {
      if(CfgLiqInvalidHardFail(cfg))
      {
        reason = GATE_CALM;
        _GateDetail(cfg, reason, sym,
                    StringFormat("invalid_atr atr_s=%.1f hard_fail=1", atr_s));
        return false;
      }
      return true;
    }

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
      if(spr<=0.0)
      {
        if(CfgLiqInvalidHardFail(cfg))
        {
          reason = GATE_CALM;
          _GateDetail(cfg, reason, sym,
                      StringFormat("invalid_spread atr_s=%.1f spr=%.1f hard_fail=1",
                                   atr_s, spr));
          return false;
        }
        return true;
      }

      if(atr_s/spr < minRatio)
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
         return StringFormat("EventRisk block mins_left=%d impact_mask=%d pre=%d post=%d backend=%d broker=%d csv=%d health=%d note=%s",
                             mins_left, impact_mask, pre_m, post_m,
                             h.backend_effective, (h.broker_available ? 1 : 0), h.csv_events, h.data_health, note);

      return StringFormat("EventRisk block mins_left=%d impact_mask=%d pre=%d post=%d backend=%d broker=%d csv=%d health=%d",
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
     return StringFormat("SpreadStress spread=%.1f pts > cap=%.1f pts", spread_pts, max_spread_pts);
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
         return StringFormat("Liquidity ratio=%.3f floor=%.3f source=%s atrS=%.1f spread=%.1f",
                             r.liq_ratio, r.liq_floor, r.liq_floor_source, r.atr_short_pts, r.spread_pts) + pool_tag;
   
       case GATE_REGIME:
         return StringFormat("Regime tq=%.3f sg=%.3f minTQ=%.3f minSG=%.3f",
                             r.regime_tq, r.regime_sg, r.regime_tq_min, r.regime_sg_min) + pool_tag;

       case GATE_NEWS:
         #ifdef NEWSFILTER_AVAILABLE
           return _FmtNewsVeto(r.news_mins_left, r.news_impact_mask, r.news_pre_mins, r.news_post_mins) + _FmtPoolTag(sym);
         #else
           return StringFormat("news_block mins_left=%d", r.news_mins_left) + _FmtPoolTag(sym);
         #endif

       case GATE_MICRO_VPIN:
         return StringFormat("MicroVPIN vpin=%.3f limit=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.vpin01, r.vpin_limit01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_TOXICITY:
         return StringFormat("MicroToxicity tox=%.3f max=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.toxicity01, r.toxicity_max01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_SPREAD_STRESS:
         return StringFormat("MicroSpreadStress stress=%.3f max=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.spread_stress01, r.spread_stress_max01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_RESILIENCY:
         return StringFormat("MicroResiliency resil=%.3f min=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.resiliency01, r.resiliency_min01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_OBSERVABILITY:
         return StringFormat("MicroObservability obs=%.3f flow=%.3f min=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.observability_confidence01, r.flow_confidence01, r.observability_min01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_VENUE:
         return StringFormat("MicroVenue venue=%.3f min=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.venue_coverage01, r.venue_coverage_min01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_QUOTE_INSTABILITY:
         return StringFormat("QuoteInstability venue=%.3f minVenue=%.3f xvenue=%.3f maxXVenue=%.3f qinst=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.venue_coverage01, r.venue_coverage_min01,
                             r.cross_venue_dislocation01, r.cross_venue_dislocation_max01,
                             PolicyQuoteInstability01(r),
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_IMPACT:
         return StringFormat("MicroImpact beta=%.3f maxB=%.3f lambda=%.3f maxL=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.impact_beta01, r.impact_beta_max01,
                             r.impact_lambda01, r.impact_lambda_max01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_TRUTH:
         return StringFormat("MicroTruth truth=%.3f min=%.3f posture=%d reduced=%d alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.truth_tier01, r.truth_tier_aggressive_min01,
                             r.execution_posture_mode, (r.reduced_only ? 1 : 0),
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_DARKPOOL:
         return StringFormat("MicroDarkPool dark=%.3f min=%.3f contra=%.3f maxContra=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.darkpool01, r.darkpool_min01,
                             r.darkpool_contradiction01, r.darkpool_contradiction_max01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_SM_INVALIDATION:
         return StringFormat("SmartMoneyInvalidation prox=%.3f max=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.sd_ob_invalidation_proximity01, r.sd_ob_invalidation_max01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_MICRO_THIN_LIQUIDITY:
         return StringFormat("ThinLiquidity vacuum=%.3f maxVac=%.3f hunt=%.3f maxHunt=%.3f thin=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.liquidity_vacuum01, r.liquidity_vacuum_max01,
                             r.liquidity_hunt01, r.liquidity_hunt_max01,
                             PolicyThinLiquidity01(r),
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_LIQUIDITY_TRAP:
         return StringFormat("LiquidityTrap hunt=%.3f maxHunt=%.3f vacuum=%.3f maxVac=%.3f alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                             r.liquidity_hunt01, r.liquidity_hunt_max01,
                             r.liquidity_vacuum01, r.liquidity_vacuum_max01,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01) + pool_tag;

       case GATE_INSTITUTIONAL:
         return StringFormat("Institutional gate=%d flow=%s route=%s veto=%s alpha=%.3f exec=%.3f risk=%.3f q=%.3f obs=%.3f venue=%.3f xvenue=%.3f posture=%d reduced=%d",
                             (r.institutional_gate_pass?1:0),
                             InstitutionalFlowModeText(r.flow_mode),
                             r.route_reason,
                             r.veto_reason,
                             r.alpha_score, r.execution_score, r.risk_score, r.state_quality01,
                             r.observability_confidence01, r.venue_coverage01, r.cross_venue_dislocation01,
                             r.execution_posture_mode, (r.reduced_only ? 1 : 0)) + pool_tag;

       default:
         return _FmtPoolTag(sym); // or "" + _FmtPoolTag(sym) if you want consistent presence
     }
   }

  inline string PolicyPrimaryVetoTag(const PolicyResult &r)
  {
     return GateReasonToString(r.primary_reason);
  }

  inline void PolicyApplyResultToIntegratedState(const PolicyResult &r,
                                                 FinalStrategyIntegratedStateVector_t &io_state)
  {
     io_state.policy_pass = r.allowed;

     if(!r.allowed)
     {
        io_state.veto_code   = r.primary_reason;
        io_state.veto_tag    = PolicyPrimaryVetoTag(r);
        io_state.veto_reason = FormatPrimaryVetoDetail(r);
     }
     else
     {
        if(StringLen(io_state.veto_tag) <= 0)
           io_state.veto_tag = "none";

        if(StringLen(io_state.veto_reason) <= 0)
           io_state.veto_reason = "none";
     }
  }

  inline string PolicyVetoKV(const PolicyResult &r)
  {
     const string sym = (StringLen(s_last_eval_sym) > 0 ? s_last_eval_sym : _Symbol);

     return StringFormat("sym=%s reason=%s reason_code=%d veto_mask=%s route=\"%s\" veto=\"%s\" liq_ratio=%.3f liq_floor=%.3f liq_floor_source=%s spread_pts=%.1f news_mins_left=%d cd_trade_left_sec=%d cd_loss_left_sec=%d alpha=%.3f exec=%.3f risk=%.3f q=%.3f",
                         sym,
                         GateReasonToString(r.primary_reason),
                         r.primary_reason,
                         (string)r.veto_mask,
                         r.route_reason,
                         r.veto_reason,
                         r.liq_ratio,
                         r.liq_floor,
                         r.liq_floor_source,
                         r.spread_pts,
                         r.news_mins_left,
                         r.cd_trade_left_sec,
                         r.cd_loss_left_sec,
                         r.alpha_score,
                         r.execution_score,
                         r.risk_score,
                         r.state_quality01);
  }

  inline void PolicyVetoLog(const PolicyResult &r)
   {
     const string sym = (StringLen(s_last_eval_sym) > 0 ? s_last_eval_sym : _Symbol);
     string gate_log = "";
     const string pool_tag = _FmtPoolTag(sym);
   
     if(_ShouldVetoLogOncePerSec(sym, r.primary_reason, r.veto_mask) == false)
       return;

     Print("[Policy][VETO_KV] ", PolicyVetoKV(r));

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
              " floor_source=", r.liq_floor_source,
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


      case GATE_MICRO_VPIN:
        Print("[Policy][VETO] reason=MICRO_VPIN sym=", sym,
              " vpin=", DoubleToString(r.vpin01,3),
              " limit=", DoubleToString(r.vpin_limit01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_TOXICITY:
        Print("[Policy][VETO] reason=MICRO_TOXICITY sym=", sym,
              " tox=", DoubleToString(r.toxicity01,3),
              " max=", DoubleToString(r.toxicity_max01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_SPREAD_STRESS:
        Print("[Policy][VETO] reason=MICRO_SPREAD_STRESS sym=", sym,
              " stress=", DoubleToString(r.spread_stress01,3),
              " max=", DoubleToString(r.spread_stress_max01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_RESILIENCY:
        Print("[Policy][VETO] reason=MICRO_RESILIENCY sym=", sym,
              " resil=", DoubleToString(r.resiliency01,3),
              " min=", DoubleToString(r.resiliency_min01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_OBSERVABILITY:
        Print("[Policy][VETO] reason=MICRO_OBSERVABILITY sym=", sym,
              " obs=", DoubleToString(r.observability_confidence01,3),
              " min=", DoubleToString(r.observability_min01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_VENUE:
        Print("[Policy][VETO] reason=MICRO_VENUE sym=", sym,
              " venue=", DoubleToString(r.venue_coverage01,3),
              " min=", DoubleToString(r.venue_coverage_min01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_QUOTE_INSTABILITY:
        Print("[Policy][VETO] reason=MICRO_QUOTE_INSTABILITY sym=", sym,
              " venue=", DoubleToString(r.venue_coverage01,3),
              " minVenue=", DoubleToString(r.venue_coverage_min01,3),
              " xvenue=", DoubleToString(r.cross_venue_dislocation01,3),
              " maxXVenue=", DoubleToString(r.cross_venue_dislocation_max01,3),
              " qinst=", DoubleToString(PolicyQuoteInstability01(r),3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_IMPACT:
        Print("[Policy][VETO] reason=MICRO_IMPACT sym=", sym,
              " beta=", DoubleToString(r.impact_beta01,3),
              " betaMax=", DoubleToString(r.impact_beta_max01,3),
              " lambda=", DoubleToString(r.impact_lambda01,3),
              " lambdaMax=", DoubleToString(r.impact_lambda_max01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_TRUTH:
        Print("[Policy][VETO] reason=MICRO_TRUTH sym=", sym,
              " truth=", DoubleToString(r.truth_tier01,3),
              " min=", DoubleToString(r.truth_tier_aggressive_min01,3),
              " posture=", IntegerToString(r.execution_posture_mode),
              " reduced=", IntegerToString((int)r.reduced_only),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_DARKPOOL:
        Print("[Policy][VETO] reason=MICRO_DARKPOOL sym=", sym,
              " dark=", DoubleToString(r.darkpool01,3),
              " min=", DoubleToString(r.darkpool_min01,3),
              " contra=", DoubleToString(r.darkpool_contradiction01,3),
              " contraMax=", DoubleToString(r.darkpool_contradiction_max01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_SM_INVALIDATION:
        Print("[Policy][VETO] reason=SMARTMONEY_INVALIDATION sym=", sym,
              " prox=", DoubleToString(r.sd_ob_invalidation_proximity01,3),
              " max=", DoubleToString(r.sd_ob_invalidation_max01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_MICRO_THIN_LIQUIDITY:
        Print("[Policy][VETO] reason=MICRO_THIN_LIQUIDITY sym=", sym,
              " vacuum=", DoubleToString(r.liquidity_vacuum01,3),
              " vacMax=", DoubleToString(r.liquidity_vacuum_max01,3),
              " hunt=", DoubleToString(r.liquidity_hunt01,3),
              " huntMax=", DoubleToString(r.liquidity_hunt_max01,3),
              " thin=", DoubleToString(PolicyThinLiquidity01(r),3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_LIQUIDITY_TRAP:
        Print("[Policy][VETO] reason=LIQUIDITY_TRAP sym=", sym,
              " hunt=", DoubleToString(r.liquidity_hunt01,3),
              " huntMax=", DoubleToString(r.liquidity_hunt_max01,3),
              " vacuum=", DoubleToString(r.liquidity_vacuum01,3),
              " vacMax=", DoubleToString(r.liquidity_vacuum_max01,3),
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " mask=", (string)r.veto_mask);
        break;

      case GATE_INSTITUTIONAL:
        Print("[Policy][VETO] reason=INSTITUTIONAL_STATE sym=", sym,
              " gate=", (r.institutional_gate_pass?"1":"0"),
              " flow=", InstitutionalFlowModeText(r.flow_mode),
              " route=", r.route_reason,
              " veto=", r.veto_reason,
              " alpha=", DoubleToString(r.alpha_score,3),
              " exec=", DoubleToString(r.execution_score,3),
              " risk=", DoubleToString(r.risk_score,3),
              " q=", DoubleToString(r.state_quality01,3),
              " obs=", DoubleToString(r.observability_confidence01,3),
              " venue=", DoubleToString(r.venue_coverage01,3),
              " xvenue=", DoubleToString(r.cross_venue_dislocation01,3),
              " posture=", IntegerToString(r.execution_posture_mode),
              " reduced=", IntegerToString((int)r.reduced_only),
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
  inline void _LogLiqFloorMode(const Settings &cfg,
                               const double strict_floor,
                               const double active_floor)
  {
    if(!CfgDebugGates(cfg))
      return;

    static datetime s_last_ts      = 0;
    static double   s_last_strict  = -1.0;
    static double   s_last_active  = -1.0;

    const datetime now = TimeCurrent();

    if(MathAbs(strict_floor - s_last_strict) < 0.000001 &&
       MathAbs(active_floor - s_last_active) < 0.000001 &&
       (now - s_last_ts) < 60)
      return;

    s_last_ts     = now;
    s_last_strict = strict_floor;
    s_last_active = active_floor;

    if(CfgLiqFloorAdapted(cfg))
      Print("[Policy][LIQ] floor_source=tester_adapted strict=",
            DoubleToString(strict_floor,3),
            " active=",
            DoubleToString(active_floor,3));
    else
      Print("[Policy][LIQ] floor_source=policy_strict strict=",
            DoubleToString(strict_floor,3),
            " active=",
            DoubleToString(active_floor,3));
  }

  inline void _ApplyRuntimeKnobsFromCfg(const Settings &cfg)
  {
    SetMoDMultiplier       (CfgModSpreadMult(cfg));
    SetSpreadATRAdapt      (CfgATRShort(cfg), CfgATRLong(cfg),
                            CfgSpreadAdaptFloor(cfg), CfgSpreadAdaptCeil(cfg));
    SetVolBreakerLimit     (CfgVolBreakerLimit(cfg));

    const double liq_floor_strict = CfgLiqMinRatio(cfg);
    const double liq_floor_active = CfgLiqMinRatioEffective(cfg);
    SetLiquidityParams(liq_floor_active);
    _LogLiqFloorMode(cfg, liq_floor_strict, liq_floor_active);

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
    r.liq_floor        = floorR;
    r.liq_floor_source = EffLiqMinRatioSource(cfg, sym, s_liq_min_ratio);

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
    const bool tester_loose_mode = PolicyTesterLooseModeActive(cfg);

    out.session_filter_on = (tester_loose_mode ? false : EffSessionFilter(cfg, sym));
    out.in_session_window = (tester_loose_mode ? true  : TimeUtils::InTradingWindow(cfg, TimeCurrent()));

    out.trade_cd_sec      = s_trade_cd_sec;
    out.loss_cd_min       = s_cooldown_min;
    out.cd_trade_left_sec = TradeCooldownSecondsLeft();
    out.cd_loss_left_sec  = LossCooldownSecondsLeft();

    out.day_eq0           = s_dayEqStart;
    out.day_dd_limit_pct  = CfgMaxDailyDDPct(cfg);
    out.day_dd_pct          = LastDailyDDActivePct();
    out.day_dd_strict_pct   = LastDailyDDStrictPct();
    out.sizing_reset_active = SizingResetActive();
    out.sizing_reset_sec_left = SizingResetSecondsLeft();

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
      const bool dd_hit = DailyEquityDDHit(cfg, dd_pct);

      out.day_dd_pct        = dd_pct;
      out.day_dd_strict_pct = LastDailyDDStrictPct();

      if(dd_hit)
      {
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
        const double base = CfgLiqMinRatioEffective(cfg);
        const double mult = (in_lon ? 0.95 : 1.05);
        SetLiquidityParams(Clamp(base * mult, 0.50, 10.0));
      }
    }
    #endif
    #endif

   // 8) Volatility breaker
   if(PolicyVolBreakerGateEnabled())
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
    if(!tester_loose_mode)
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
    if(!tester_loose_mode)
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
    if(!tester_loose_mode)
    {
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
    }

    return out.allowed;
  }

  inline bool _EvaluateFullEx(const Settings &cfg, const string sym, PolicyResult &out, const bool audit)
  {
    const bool ok_core = _EvaluateCoreEx(cfg, sym, out, audit);
    if(!audit && !ok_core) return false;

    const bool tester_loose_mode = PolicyTesterLooseModeActive(cfg);

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
    if(!tester_loose_mode && out.session_filter_on && !out.in_session_window)
    {
      _PolicyVeto(out, GATE_SESSION, CA_POLMASK_SESSION);
      if(!audit) return false;
    }

    // D) News veto
    out.news_blocked     = false;
    out.news_mins_left   = 0;
    out.news_impact_mask = 0;
    out.news_pre_mins    = 0;
    out.news_post_mins   = 0;

    if(!tester_loose_mode && CfgNewsPolicyEnabled(cfg))
    {
      out.news_impact_mask = EffNewsImpactMask(cfg, sym);
      out.news_pre_mins    = CfgNewsBlockPreMins(cfg);
      out.news_post_mins   = CfgNewsBlockPostMins(cfg);

      int mins_left = 0;
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
    if(PolicyRegimeBypassActive(cfg))
    {
      _GateDetail(cfg, GATE_REGIME, sym, "tester_bypass=1 regime_gate_relaxed=1");
      return true;
    }

    if(!s_regime_gate_on)
      return true;

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const double tq = RegimeX::TrendQuality(sym, tf, 60);
    const double sg = Corr::HysteresisSlopeGuard(sym, tf, 14, 23.0, 15.0);
    const bool ok = (tq >= s_reg_tq_min) || (sg >= s_reg_sg_min);

    if(!ok)
      _GateDetail(cfg, GATE_REGIME, sym,
                  StringFormat("tq=%.3f sg=%.3f tq_min=%.3f sg_min=%.3f",
                               tq, sg, s_reg_tq_min, s_reg_sg_min));
    return ok;
  }

  inline bool RegimeConsensusOK(const Settings &cfg)
   { return RegimeConsensusOK(cfg, _Symbol); }


  inline ENUM_TIMEFRAMES CfgTFH4Safe(const Settings &cfg)
  {
    #ifdef CFG_HAS_TF_H4
      if((int)cfg.tf_h4 >= (int)PERIOD_M1)
        return cfg.tf_h4;
    #endif
    return PERIOD_H4;
  }

  inline double PolicyRegimeRiskMultiplier(const Settings &cfg, const string sym)
  {
    const ENUM_TIMEFRAMES tfEntry = CfgTFEntry(cfg);
    const ENUM_TIMEFRAMES tfH4    = CfgTFH4Safe(cfg);

    const double tqMin = CfgRegimeTQMin(cfg);
    const double sgMin = CfgRegimeSGMin(cfg);

    const double tqEntry = RegimeX::TrendQuality(sym, tfEntry, 60);
    const double sgEntry = Corr::HysteresisSlopeGuard(sym, tfEntry, 14, 23.0, 15.0);

    double mult = 1.0;

    // Entry-TF regime quality
    if(tqEntry < tqMin && sgEntry < sgMin)
      mult = 0.75;
    else if(tqEntry < tqMin || sgEntry < sgMin)
      mult = 0.90;

    // H4 confirmation can only tighten, never loosen
    if(tfH4 != tfEntry)
    {
      const double tqH4 = RegimeX::TrendQuality(sym, tfH4, 60);
      const double sgH4 = Corr::HysteresisSlopeGuard(sym, tfH4, 14, 23.0, 15.0);

      if(tqH4 < tqMin && sgH4 < sgMin)
        mult = MathMin(mult, 0.85);
      else if(tqH4 < tqMin || sgH4 < sgMin)
        mult = MathMin(mult, 0.95);
    }

    return Clamp(mult, 0.10, 1.0);
  }
  
  // ----------------------------------------------------------------------------
  // Liquidity (ATR:Spread) floor
  // ----------------------------------------------------------------------------
  static double s_liq_min_ratio = 1.50;
  inline void   SetLiquidityParams(const double min_ratio)
  { s_liq_min_ratio = Clamp(min_ratio, 0.5, 10.0); }

  inline bool LiquidityOK(const Settings &cfg, const string sym, double &ratio_out)
  {
    ratio_out = 0.0;

    if(PolicyLiquidityBypassActive(cfg))
    {
      _GateDetail(cfg, GATE_LIQUIDITY, sym, "tester_bypass=1 liquidity_gate_relaxed=1");
      return true;
    }

    const ENUM_TIMEFRAMES tf = CfgTFEntry(cfg);
    const int shortP = CfgATRShort(cfg);

    const double atr_s = AtrPts(sym, tf, cfg, shortP, 1);
    const double spr   = MarketData::SpreadPoints(sym);

    if(atr_s<=0.0 || spr<=0.0)
    {
      if(CfgLiqInvalidHardFail(cfg))
      {
        _GateDetail(cfg, GATE_LIQUIDITY, sym,
                    StringFormat("invalid_metrics atr_s=%.1f spr=%.1f hard_fail=1",
                                 atr_s, spr));
        return false;
      }
      return true; // preserve legacy safe no-block on missing data
    }

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
     mins_left = 0;

     if(!CfgNewsOn(cfg))
       return false;

     if(PolicyNewsBypassActive(cfg))
     {
       _GateDetail(cfg, GATE_NEWS, sym, "tester_bypass=1 news_gate_relaxed=1");
       return false;
     }

     if(!CfgNewsPolicyEnabled(cfg)) return false;

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
     if(!CfgNewsPolicyEnabled(cfg)) return;
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

  inline void ApplyPolicyRiskOverlays(const Settings &cfg, const string sym,
                                      StratScore &ss, ConfluenceBreakdown &bd, bool &skip_out)
  {
    skip_out = false;

    if(PolicyTesterRuntime())
    {
      bd.score_final = ss.score;
      return;
    }

    // 1) News remains a veto / risk modifier only.
    ApplyNewsScaling(cfg, sym, ss, bd, skip_out);
    if(skip_out) return;

    // 2) Big-loss sizing reset latch — shrink sizing centrally, do not clone this in strategies.
    if(SizingResetActive())
    {
      const double reset_mult = CfgSizingResetMult(cfg);
      ss.risk_mult = Clamp01(ss.risk_mult * Clamp(reset_mult, 0.05, 1.0));
    }

    // 3) Regime derisk — context/risk only, not signal ownership.
    if(CfgRegimeGateOn(cfg))
    {
      const double regime_mult = PolicyRegimeRiskMultiplier(cfg, sym);
      ss.risk_mult = Clamp01(ss.risk_mult * regime_mult);
    }

    bd.score_final = ss.score;
  }

  // ----------------------------------------------------------------------------
  // Canonical institutional-state consumer helpers
  //
  // Boundary:
  // - Policies consumes the final state transport from Confluence.
  // - Policies decides allow/veto, derisk/full-size, and delay/no-delay.
  // - Policies does NOT infer pseudo-state from scattered upstream fields.
  // - Policies does NOT rebuild alpha / execution / risk heads locally.
  // - Policies does NOT replace or absorb the independent news policy lane.
  // ----------------------------------------------------------------------------
  struct InstitutionalStatePolicyView
  {
    bool   valid;
    bool   trade_gate_pass;

    bool   upstream_pre_filter_pass;
    bool   upstream_signal_stack_gate_pass;
    bool   upstream_location_pass;
    bool   upstream_execution_gate_pass;
    bool   upstream_risk_gate_pass;
    bool   upstream_hard_inst_block;

    bool   delay_recommended;
    bool   derisk_recommended;

    double alpha_score;
    double execution_score;
    double risk_score;
    double state_quality01;

    double observability_confidence01;
    double flow_confidence01;
    double venue_coverage01;
    double cross_venue_dislocation01;

    double impact_beta01;
    double impact_lambda01;

    double truth_tier01;
    int    execution_posture_mode;
    bool   reduced_only;

    double darkpool01;
    double darkpool_contradiction01;

    double sd_ob_invalidation_proximity01;

    double liquidity_vacuum01;
    double liquidity_hunt01;

    int    gate_reason;
    double vpin01;
    double resiliency01;

    double toxicity01;
    double spread_stress01;

    bool   invalidation_event01;
    bool   liquidity_trap_event01;

    double observability_penalty01;

    bool   direct_micro_available;
    bool   proxy_micro_available;
    int    flow_mode;

    double inst_ofi01;
    double inst_obi01;
    double inst_cvd01;

    double inst_delta_proxy01;
    double inst_footprint01;
    double inst_profile01;
    double inst_absorption01;
    double inst_replenishment01;
    double inst_vwap_location01;
    double inst_liquidity_reject01;

    int    confluence_veto_mask;
    string route_reason;
    string veto_reason;
  };

  inline void ResetInstitutionalStatePolicyView(InstitutionalStatePolicyView &v)
  {
    ZeroMemory(v);
    v.trade_gate_pass                = true;  // neutral compat default until canonical transport is present

    v.upstream_pre_filter_pass       = true;
    v.upstream_signal_stack_gate_pass= true;
    v.upstream_location_pass         = true;
    v.upstream_execution_gate_pass   = true;
    v.upstream_risk_gate_pass        = true;
    v.upstream_hard_inst_block       = false;

    v.observability_confidence01 = (double)POLICIES_INST_DEFAULT_OBSERVABILITY01;
    v.flow_confidence01          = (double)POLICIES_INST_DEFAULT_OBSERVABILITY01;
    v.venue_coverage01           = (double)POLICIES_INST_DEFAULT_VENUE_COVERAGE01;
    v.cross_venue_dislocation01  = (double)POLICIES_INST_DEFAULT_XVENUE_DISLOCATION01;

    v.gate_reason                = GATE_OK;
    v.vpin01                     = (double)POLICIES_INST_DEFAULT_VPIN01;
    v.resiliency01               = (double)POLICIES_INST_DEFAULT_RESILIENCY01;

    v.toxicity01                 = (double)POLICIES_INST_DEFAULT_TOXICITY01;
    v.spread_stress01            = (double)POLICIES_INST_DEFAULT_SPREAD_STRESS01;

    v.impact_beta01              = (double)POLICIES_INST_DEFAULT_IMPACT_BETA01;
    v.impact_lambda01            = (double)POLICIES_INST_DEFAULT_IMPACT_LAMBDA01;

    v.truth_tier01               = 1.0;
    v.execution_posture_mode     = 0;
    v.reduced_only               = false;
    v.invalidation_event01       = false;
    v.liquidity_trap_event01     = false;

    v.darkpool01                 = (double)POLICIES_INST_DEFAULT_DARKPOOL01;
    v.darkpool_contradiction01   = (double)POLICIES_INST_DEFAULT_DARKPOOL_CONTRADICTION01;

    v.sd_ob_invalidation_proximity01 = (double)POLICIES_INST_DEFAULT_SD_OB_INVALIDATION_PROXIMITY01;

    v.liquidity_vacuum01         = (double)POLICIES_INST_DEFAULT_LIQUIDITY_VACUUM01;
    v.liquidity_hunt01           = (double)POLICIES_INST_DEFAULT_LIQUIDITY_HUNT01;

    v.observability_penalty01    = Clamp01(1.0 - v.observability_confidence01);

    v.direct_micro_available     = false;
    v.proxy_micro_available      = false;
    v.flow_mode                  = POLICIES_INST_FLOW_MODE_PROXY;

    v.inst_ofi01                 = 0.5;
    v.inst_obi01                 = 0.5;
    v.inst_cvd01                 = 0.5;

    v.inst_delta_proxy01         = 0.5;
    v.inst_footprint01           = 0.5;
    v.inst_profile01             = 0.5;
    v.inst_absorption01          = 0.5;
    v.inst_replenishment01       = 0.5;
    v.inst_vwap_location01       = 0.5;
    v.inst_liquidity_reject01    = 0.0;

    v.confluence_veto_mask       = 0;
    v.route_reason               = "";
    v.veto_reason                = "none";
  }

  inline void ApplyNeutralInstitutionalStatePolicyView(InstitutionalStatePolicyView &v,
                                                       const string reason_text)
  {
    ResetInstitutionalStatePolicyView(v);

    v.valid               = true;
    v.trade_gate_pass     = true;
    v.delay_recommended   = false;
    v.derisk_recommended  = false;

    v.alpha_score         = 0.5;
    v.execution_score     = 0.5;
    v.risk_score          = 0.5;
    v.state_quality01     = 0.5;

    v.observability_confidence01 = 0.5;
    v.venue_coverage01           = 0.5;
    v.cross_venue_dislocation01  = 0.0;
    v.observability_penalty01    = 0.5;

    v.vpin01                     = 0.5;
    v.resiliency01               = 0.5;
    v.toxicity01                 = 0.5;
    v.spread_stress01            = 0.5;
    v.impact_beta01              = 0.5;
    v.impact_lambda01            = 0.5;
    v.truth_tier01               = 0.5;

    v.darkpool01                     = 0.5;
    v.darkpool_contradiction01       = 0.0;
    v.sd_ob_invalidation_proximity01 = 0.0;
    v.liquidity_vacuum01             = 0.0;
    v.liquidity_hunt01               = 0.0;

    v.execution_posture_mode     = 0;
    v.reduced_only               = false;
    v.invalidation_event01       = false;
    v.liquidity_trap_event01     = false;

    v.direct_micro_available     = false;
    v.proxy_micro_available      = true;
    v.flow_mode                  = POLICIES_INST_FLOW_MODE_PROXY;

    v.inst_ofi01                 = 0.5;
    v.inst_obi01                 = 0.5;
    v.inst_cvd01                 = 0.5;
    v.inst_delta_proxy01         = 0.5;
    v.inst_footprint01           = 0.5;
    v.inst_profile01             = 0.5;
    v.inst_absorption01          = 0.5;
    v.inst_replenishment01       = 0.5;
    v.inst_vwap_location01       = 0.5;
    v.inst_liquidity_reject01    = 0.5;

    v.gate_reason                = GATE_OK;
    v.confluence_veto_mask       = 0;
    v.route_reason               = reason_text;
    v.veto_reason                = reason_text;
  }

  inline void ApplyUpstreamGateReasonHints(InstitutionalStatePolicyView &v)
  {
    v.upstream_pre_filter_pass        = true;
    v.upstream_signal_stack_gate_pass = true;
    v.upstream_location_pass          = true;
    v.upstream_execution_gate_pass    = true;
    v.upstream_risk_gate_pass         = true;
    v.upstream_hard_inst_block        = false;

    if(GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "hard_inst_block") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "inst_hard_block") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "hard institutional block"))
    {
      v.upstream_hard_inst_block = true;
      v.trade_gate_pass = false;
    }

    if(GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "signal_stack_gate_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "signal_stack_gate=0") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "stack_gate_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "signal stack gate"))
    {
      v.upstream_signal_stack_gate_pass = false;
      v.trade_gate_pass = false;
    }

    if(GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "location_pass_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "location_pass=0") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "location_gate_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "location gate"))
    {
      v.upstream_location_pass = false;
      v.trade_gate_pass = false;
    }

    if(GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "pre_filter_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "pre_filter=0") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "prefilter_fail"))
    {
      v.upstream_pre_filter_pass = false;
      v.trade_gate_pass = false;
    }

    if(GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "execution_gate_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "execution_gate=0") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "exec_gate_fail"))
    {
      v.upstream_execution_gate_pass = false;
      v.trade_gate_pass = false;
    }

    if(GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "risk_gate_fail") ||
       GateReasonTextHasTokenI(v.route_reason, v.veto_reason, "risk_gate=0"))
    {
      v.upstream_risk_gate_pass = false;
      v.trade_gate_pass = false;
    }

    if(v.upstream_hard_inst_block ||
       !v.upstream_signal_stack_gate_pass ||
       !v.upstream_location_pass ||
       !v.upstream_execution_gate_pass ||
       !v.upstream_risk_gate_pass)
    {
      v.upstream_pre_filter_pass = false;
    }
  }

  inline int UpstreamInstitutionalGateReasonFromView(const InstitutionalStatePolicyView &v)
  {
    if(v.upstream_hard_inst_block)
      return GATE_INST_HARD_BLOCK;

    return GATE_INSTITUTIONAL;
  }

  inline bool InstitutionalUpstreamDegradeVeto(const InstitutionalStatePolicyView &v)
  {
    if(v.upstream_hard_inst_block)
      return true;
    if(!v.upstream_pre_filter_pass)
      return true;
    if(!v.upstream_signal_stack_gate_pass)
      return true;
    if(!v.upstream_location_pass)
      return true;
    return false;
  }

  inline double InstitutionalQuoteInstability01(const InstitutionalStatePolicyView &v)
  {
    return Clamp01(MathMax(Clamp01(1.0 - v.venue_coverage01),
                           v.cross_venue_dislocation01));
  }

  inline double InstitutionalThinLiquidity01(const InstitutionalStatePolicyView &v)
  {
    return Clamp01(MathMax(v.liquidity_vacuum01,
                           v.liquidity_hunt01));
  }

  inline double PolicyTruthTierOrdinalTo01(const int truthTier)
  {
    if(truthTier >= 4) return 1.00;
    if(truthTier == 3) return 0.75;
    if(truthTier == 2) return 0.55;
    if(truthTier == 1) return 0.45;
    return 0.35;
  }

  inline bool InstitutionalAggressivePosture(const InstitutionalStatePolicyView &v)
  {
    #ifdef TYPES_HAS_EXECUTION_POSTURE_ENUM
      return (v.execution_posture_mode == EXEC_POSTURE_URGENT);
    #else
      return (v.execution_posture_mode == 3);
    #endif
  }

  inline bool InstitutionalNeedsStrongObservability(const InstitutionalStatePolicyView &v)
  {
    #ifdef TYPES_HAS_EXECUTION_POSTURE_ENUM
      if(v.execution_posture_mode == EXEC_POSTURE_URGENT)
        return true;

      if(v.execution_posture_mode == EXEC_POSTURE_NORMAL && !v.reduced_only)
        return true;
    #else
      if(v.execution_posture_mode == 3)
        return true;

      if(v.execution_posture_mode == 2 && !v.reduced_only)
        return true;
    #endif

    return false;
  }

  inline int InstitutionalFlowModeFromObservability01(const double obs01)
  {
    if(obs01 >= 0.95)
      return POLICIES_INST_FLOW_MODE_DIRECT;

    if(obs01 >= 0.60)
      return POLICIES_INST_FLOW_MODE_PROXY;

    return POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY;
  }

  inline string InstitutionalFlowModeText(const int mode)
  {
    if(mode == POLICIES_INST_FLOW_MODE_DIRECT)         return "direct";
    if(mode == POLICIES_INST_FLOW_MODE_PROXY)          return "proxy";
    if(mode == POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY) return "structure_only";
    return "unknown";
  }

  inline bool InstitutionalStructureOnlyPostureTooAggressive(const InstitutionalStatePolicyView &v)
  {
    if(v.flow_mode != POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
      return false;

    #ifdef TYPES_HAS_EXECUTION_POSTURE_ENUM
      return (v.execution_posture_mode == EXEC_POSTURE_URGENT);
    #else
      return (v.execution_posture_mode >= 3);
    #endif
  }

   inline bool LoadInstitutionalStateFromStateCache(const string sym,
                                                    const ENUM_TIMEFRAMES tf,
                                                    InstitutionalStatePolicyView &out_view)
   {
      ResetInstitutionalStatePolicyView(out_view);
   
   #ifdef CA_STATE_MQH
      if(g_state.symbol != sym)
         return false;
   
      datetime required_bar_time = iTime(sym, tf, 1);
      if(required_bar_time <= 0)
         required_bar_time = iTime(sym, tf, 0);
   
      if(!StateInstitutionalStrategyReady(g_state, required_bar_time))
         return false;
   
   #ifdef STATE_HAS_INSTITUTIONAL_TRANSPORT_DIAG_CACHE
      StateInstitutionalTransportDiagCache sdc;
      StateGetInstitutionalTransportDiagCache(g_state, sdc);
   
      if(!sdc.valid)
         return false;
   
      out_view.valid                       = true;
      out_view.trade_gate_pass             = (sdc.confluence_veto_mask == 0);
      out_view.alpha_score                 = Clamp01(sdc.alpha01);
      out_view.execution_score             = Clamp01(sdc.execution01);
      out_view.risk_score                  = Clamp01(sdc.risk01);
      out_view.state_quality01             = Clamp01(StateInstitutionalStateQuality01(g_state));
   
      out_view.observability_confidence01  = Clamp01(sdc.observability01);
      out_view.flow_confidence01           = Clamp01(sdc.flow_confidence01);
      out_view.venue_coverage01            = Clamp01(sdc.venue_scope01);
      out_view.cross_venue_dislocation01   = Clamp01(StateInstitutionalCrossVenueDislocation01(g_state));
   
      out_view.impact_beta01               = Clamp01(StateInstitutionalImpactBeta01(g_state));
      out_view.impact_lambda01             = Clamp01(StateInstitutionalImpactLambda01(g_state));
   
      out_view.truth_tier01                = Clamp01(sdc.truth_tier01);
      out_view.execution_posture_mode      = sdc.execution_posture_mode;
      out_view.reduced_only                = StateInstitutionalReducedOnly(g_state);
   
      out_view.darkpool01                  = Clamp01(StateInstitutionalDarkpool01(g_state));
      out_view.darkpool_contradiction01    = 0.0;
   
      out_view.sd_ob_invalidation_proximity01 = 0.0;
   
      out_view.liquidity_vacuum01          = Clamp01(StateInstitutionalLiquidityStress01(g_state));
      out_view.liquidity_hunt01            = Clamp01(StateInstitutionalLiquidityEventScore01(g_state));
   
      out_view.vpin01                      = Clamp01(StateInstitutionalVPIN01(g_state));
      out_view.resiliency01                = Clamp01(StateInstitutionalResiliency01(g_state));
   
      out_view.toxicity01                  = Clamp01(sdc.toxicity01);
      out_view.spread_stress01             = Clamp01(StateInstitutionalVolatilityStress01(g_state));
   
      out_view.invalidation_event01        = false;
      out_view.liquidity_trap_event01      = false;
   
      out_view.observability_penalty01     = Clamp01(sdc.observability_penalty01);
   
      out_view.direct_micro_available      = sdc.direct_micro_available;
      out_view.proxy_micro_available       = sdc.proxy_micro_available;
      out_view.flow_mode                   = sdc.micro_mode;
   
      out_view.inst_ofi01                  = Clamp01(sdc.ofi01);
      out_view.inst_obi01                  = Clamp01(sdc.obi01);
      out_view.inst_cvd01                  = Clamp01(sdc.cvd01);
   
      out_view.inst_delta_proxy01          = Clamp01(sdc.delta_proxy01);
      out_view.inst_footprint01            = Clamp01(sdc.footprint01);
      out_view.inst_profile01              = Clamp01(sdc.profile01);
      out_view.inst_absorption01           = Clamp01(sdc.absorption01);
      out_view.inst_replenishment01        = Clamp01(sdc.replenishment01);
      out_view.inst_vwap_location01        = Clamp01(sdc.vwap_location01);
      out_view.inst_liquidity_reject01     = Clamp01(sdc.liquidity_reject01);
   
      out_view.confluence_veto_mask        = sdc.confluence_veto_mask;
      out_view.route_reason                = StateInstitutionalFreshnessSourceTag(g_state, required_bar_time);
      out_view.veto_reason                 = (sdc.confluence_veto_mask != 0 ? "state_confluence_veto" : "none");
   
      if(out_view.flow_mode != POLICIES_INST_FLOW_MODE_DIRECT &&
         out_view.flow_mode != POLICIES_INST_FLOW_MODE_PROXY &&
         out_view.flow_mode != POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
      {
         out_view.flow_mode = InstitutionalFlowModeFromObservability01(out_view.observability_confidence01);
      }
   
      if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_DIRECT)
         out_view.direct_micro_available = true;
   
      if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_PROXY)
         out_view.proxy_micro_available = true;
   
      if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
         out_view.reduced_only = true;
   
      return true;
   #endif
   #endif
   
      return false;
   }

  inline bool LoadInstitutionalStateFromSymbolState(const Settings &cfg,
                                                    const string sym,
                                                    const ENUM_TIMEFRAMES tf,
                                                    InstitutionalStatePolicyView &out_view)
  {
    ResetInstitutionalStatePolicyView(out_view);

    datetime required_bar_time = iTime(sym, tf, 1);
    if(required_bar_time <= 0)
       required_bar_time = iTime(sym, tf, 0);

    StateInstitutionalSymbolView sv;
    sv.Reset();

    if(!State::GetInstitutionalSymbolViewBySymbolWithFallback(cfg, sym, sv, required_bar_time))
      return false;

    out_view.valid                       = true;
    out_view.trade_gate_pass             = sv.trade_gate_pass;
    out_view.alpha_score                 = Clamp01(sv.alpha01);
    out_view.execution_score             = Clamp01(sv.execution01);
    out_view.risk_score                  = Clamp01(sv.risk01);
    out_view.state_quality01             = Clamp01(sv.state_quality01);

    out_view.observability_confidence01  = Clamp01(sv.observability01);
    out_view.flow_confidence01           = Clamp01(sv.flow_confidence01);
    out_view.observability_penalty01     = Clamp01(sv.observability_penalty01);
    out_view.truth_tier01                = Clamp01(sv.truth_tier01);
    out_view.venue_coverage01            = Clamp01(sv.venue_coverage01);

    out_view.vpin01                      = Clamp01(sv.vpin01);
    out_view.resiliency01                = Clamp01(sv.resiliency01);
    out_view.impact_beta01               = Clamp01(sv.impact_beta01);
    out_view.impact_lambda01             = Clamp01(sv.impact_lambda01);

    out_view.execution_posture_mode      = sv.execution_posture_mode;
    out_view.execution_posture_mode      = sv.execution_posture_mode;
    out_view.reduced_only                = sv.reduced_only;
    out_view.flow_mode                   = sv.micro_mode;
    out_view.direct_micro_available      = sv.direct_micro_available;
    out_view.proxy_micro_available       = sv.proxy_micro_available;

    out_view.darkpool01                  = Clamp01(sv.darkpool01);
    out_view.liquidity_hunt01            = Clamp01(sv.liquidity_hunt01);
    out_view.toxicity01                  = Clamp01(sv.toxicity01);
    out_view.spread_stress01             = Clamp01(sv.volatility_stress01);

    out_view.inst_ofi01                  = Clamp01(sv.ofi01);
    out_view.inst_obi01                  = Clamp01(sv.obi01);
    out_view.inst_cvd01                  = Clamp01(sv.cvd01);

    out_view.inst_delta_proxy01          = Clamp01(sv.delta_proxy01);
    out_view.inst_footprint01            = Clamp01(sv.footprint01);
    out_view.inst_profile01              = Clamp01(sv.profile01);
    out_view.inst_absorption01           = Clamp01(sv.absorption01);
    out_view.inst_replenishment01        = Clamp01(sv.replenishment01);
    out_view.inst_vwap_location01        = Clamp01(sv.vwap_location01);
    out_view.inst_liquidity_reject01     = Clamp01(sv.liquidity_reject01);

    out_view.confluence_veto_mask        = sv.confluence_veto_mask;
    out_view.route_reason                = sv.source_tag;
    out_view.veto_reason                 = (sv.confluence_veto_mask != 0 ? "state_confluence_veto" : "none");

    ApplyUpstreamGateReasonHints(out_view);

    return true;
  }

  inline bool LoadInstitutionalStateFromConfluence(const string sym,
                                                   const ENUM_TIMEFRAMES tf,
                                                   InstitutionalStatePolicyView &out_view)
  {
    ResetInstitutionalStatePolicyView(out_view);

    #ifdef CFG_HAS_CONFLUENCE
      #ifdef CONFL_HAS_MACHINE_STATE_TRANSPORT
        Confl::InstitutionalStateTransport inst;
        inst.Clear();

        if(!Scan::GetInstitutionalStateTransport(sym, tf, inst))
          return false;

        #ifdef POLICIES_HAS_INST_TRANSPORT_TOXICITY01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_TOXICITY01
            out_view.toxicity01 = Clamp01(inst.toxicity01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_TOXICITY_SCORE01
              out_view.toxicity01 = Clamp01(inst.inst_toxicity_score01);
            #else
              #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MS_TOXICITY
                out_view.toxicity01 = Clamp01(inst.ms_toxicity);
              #endif
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_SPREAD_STRESS01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SPREAD_STRESS01
            out_view.spread_stress01 = Clamp01(inst.spread_stress01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VOLATILITY_STRESS01
              out_view.spread_stress01 = Clamp01(inst.volatility_stress01);
            #else
              #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ICT_SPREAD_STRESS_SCORE01
                out_view.spread_stress01 = Clamp01(inst.ict_spread_stress_score01);
              #endif
            #endif
          #endif
        #endif

        if(!inst.valid)
          return false;

        out_view.valid             = true;
        out_view.trade_gate_pass   = (bool)inst.trade_gate_pass;
        out_view.alpha_score       = Clamp01(inst.alpha_score);
        out_view.execution_score   = Clamp01(inst.execution_score);
        out_view.risk_score        = Clamp01(inst.risk_score);
        out_view.state_quality01   = Clamp01(inst.state_quality01);

        #ifdef POLICIES_HAS_INST_TRANSPORT_VPIN01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VPIN01
            out_view.vpin01 = Clamp01(inst.vpin01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MS_VPIN
              out_view.vpin01 = Clamp01(inst.ms_vpin);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_RESILIENCY01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_RESILIENCY01
            out_view.resiliency01 = Clamp01(inst.resiliency01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MS_RESIL
              out_view.resiliency01 = Clamp01(inst.ms_resil);
            #endif
          #endif
        #endif

        // Optional downstream diagnostics.
        // Policies consumes them only if the canonical transport exposes them.
        // It does NOT derive substitutes locally.
        #ifdef POLICIES_HAS_INST_TRANSPORT_OBSERVABILITY01
          out_view.observability_confidence01 = Clamp01(inst.observability_confidence01);
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_OBSERVABILITY_PENALTY01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OBSERVABILITY_PENALTY01
            out_view.observability_penalty01 = Clamp01(inst.observability_penalty01);
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_TRUTH_TIER01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_TRUTH_TIER01
            out_view.truth_tier01 = Clamp01(inst.truth_tier01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_TRUTH_TIER
              out_view.truth_tier01 = PolicyTruthTierOrdinalTo01((int)inst.truthTier);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_VENUE_COVERAGE01
          out_view.venue_coverage01 = Clamp01(inst.venue_coverage01);
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_XVENUE_DISLOCATION01
          out_view.cross_venue_dislocation01 = Clamp01(inst.cross_venue_dislocation01);
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_IMPACT_BETA01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_IMPACT_BETA01
            out_view.impact_beta01 = Clamp01(inst.impact_beta01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_IMPACT_BETA01
              out_view.impact_beta01 = Clamp01(inst.inst_impact_beta01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_IMPACT_LAMBDA01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_IMPACT_LAMBDA01
            out_view.impact_lambda01 = Clamp01(inst.impact_lambda01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_IMPACT_LAMBDA01
              out_view.impact_lambda01 = Clamp01(inst.inst_impact_lambda01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_EXECUTION_POSTURE_MODE
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_EXECUTION_POSTURE_MODE
            out_view.execution_posture_mode = (int)inst.execution_posture_mode;
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_EXECUTION_POSTURE_MODE
              out_view.execution_posture_mode = (int)inst.inst_execution_posture_mode;
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_REDUCED_ONLY
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_REDUCED_ONLY
            out_view.reduced_only = (bool)inst.reduced_only;
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ICT_EXECUTION_REDUCED_ONLY
              out_view.reduced_only = (bool)inst.ict_execution_reduced_only;
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_FLOW_MODE
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_FLOW_MODE
            out_view.flow_mode = (int)inst.inst_flow_mode;
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_MICRO_MODE
              out_view.flow_mode = (int)inst.micro_mode;
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_DIRECT_MICRO_AVAILABLE
          out_view.direct_micro_available = (bool)inst.direct_micro_available;
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_PROXY_MICRO_AVAILABLE
          out_view.proxy_micro_available = (bool)inst.proxy_micro_available;
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_DARKPOOL01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARKPOOL01
            out_view.darkpool01 = Clamp01(inst.darkpool01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARK_POOL_CONFIDENCE01
              out_view.darkpool01 = Clamp01(inst.dark_pool_confidence01);
            #else
              #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_DARKPOOL01
                out_view.darkpool01 = Clamp01(inst.inst_darkpool01);
              #endif
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_DARKPOOL_CONTRADICTION01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARKPOOL_CONTRADICTION01
            out_view.darkpool_contradiction01 = Clamp01(inst.darkpool_contradiction01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DARK_POOL_CONTRADICTION01
              out_view.darkpool_contradiction01 = Clamp01(inst.dark_pool_contradiction01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_SD_OB_INVALIDATION_PROXIMITY01
          #ifdef CONFL_MS_HAS_SDOB_INV_PROX01
            out_view.sd_ob_invalidation_proximity01 = Clamp01(inst.sd_ob_invalidation_proximity01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SM_INVALIDATION_PROXIMITY01
              out_view.sd_ob_invalidation_proximity01 = Clamp01(inst.sm_invalidation_proximity01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_VACUUM01
          out_view.liquidity_vacuum01 = Clamp01(inst.liquidity_vacuum01);
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_HUNT01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_HUNT01
            out_view.liquidity_hunt01 = Clamp01(inst.liquidity_hunt01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_SWEEP_TRAP01
              out_view.liquidity_hunt01 = Clamp01(inst.liquidity_sweep_trap01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_OFI01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_OFI01
            out_view.inst_ofi01 = Clamp01(inst.inst_ofi01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OFI01
              out_view.inst_ofi01 = Clamp01(inst.ofi01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_OBI01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_OBI01
            out_view.inst_obi01 = Clamp01(inst.inst_obi01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_OBI01
              out_view.inst_obi01 = Clamp01(inst.obi01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_CVD01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_CVD01
            out_view.inst_cvd01 = Clamp01(inst.inst_cvd01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_CVD01
              out_view.inst_cvd01 = Clamp01(inst.cvd01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_DELTA_PROXY01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_DELTA_PROXY01
            out_view.inst_delta_proxy01 = Clamp01(inst.inst_delta_proxy01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_DELTA_PROXY01
              out_view.inst_delta_proxy01 = Clamp01(inst.delta_proxy01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_FOOTPRINT01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_FOOTPRINT01
            out_view.inst_footprint01 = Clamp01(inst.inst_footprint01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_FOOTPRINT01
              out_view.inst_footprint01 = Clamp01(inst.footprint01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_PROFILE01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_PROFILE01
            out_view.inst_profile01 = Clamp01(inst.inst_profile01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_PROFILE01
              out_view.inst_profile01 = Clamp01(inst.profile01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_ABSORPTION01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_ABSORPTION01
            out_view.inst_absorption01 = Clamp01(inst.inst_absorption01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ABSORPTION01
              out_view.inst_absorption01 = Clamp01(inst.absorption01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_REPLENISHMENT01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_REPLENISHMENT01
            out_view.inst_replenishment01 = Clamp01(inst.inst_replenishment01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_REPLENISHMENT01
              out_view.inst_replenishment01 = Clamp01(inst.replenishment01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_VWAP_LOCATION01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_VWAP_LOCATION01
            out_view.inst_vwap_location01 = Clamp01(inst.inst_vwap_location01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VWAP_LOCATION01
              out_view.inst_vwap_location01 = Clamp01(inst.vwap_location01);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_REJECT01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_LIQUIDITY_REJECT01
            out_view.inst_liquidity_reject01 = Clamp01(inst.inst_liquidity_reject01);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_REJECT01
              out_view.inst_liquidity_reject01 = Clamp01(inst.liquidity_reject01);
            #else
              #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_REJECTION01
                out_view.inst_liquidity_reject01 = Clamp01(inst.rejection01);
              #endif
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_CONFLUENCE_VETO_MASK
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_CONFLUENCE_VETO_MASK
            out_view.confluence_veto_mask = (int)inst.confluence_veto_mask;
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_INST_CONFLUENCE_VETO_MASK
              out_view.confluence_veto_mask = (int)inst.inst_confluence_veto_mask;
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_ROUTE_REASON
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_ROUTE_REASON
            out_view.route_reason = inst.route_reason;
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_VETO_REASON
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_VETO_REASON
            out_view.veto_reason = inst.veto_reason;
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_INVALIDATION_EVENT01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SD_OB_INVALIDATION_EVENT01
            out_view.invalidation_event01 = (inst.sd_ob_invalidation_event01 > 0.5);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_SM_INVALIDATION_EVENT01
              out_view.invalidation_event01 = (inst.sm_invalidation_event01 > 0.5);
            #endif
          #endif
        #endif

        #ifdef POLICIES_HAS_INST_TRANSPORT_LIQUIDITY_TRAP_EVENT01
          #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_TRAP_EVENT01
            out_view.liquidity_trap_event01 = (inst.liquidity_trap_event01 > 0.5);
          #else
            #ifdef CONFL_MACHINE_STATE_TRANSPORT_HAS_LIQUIDITY_SWEEP_TRAP_EVENT01
              out_view.liquidity_trap_event01 = (inst.liquidity_sweep_trap01 > 0.5);
            #endif
          #endif
        #endif

        if(out_view.flow_mode != POLICIES_INST_FLOW_MODE_DIRECT &&
           out_view.flow_mode != POLICIES_INST_FLOW_MODE_PROXY &&
           out_view.flow_mode != POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
        {
          out_view.flow_mode = InstitutionalFlowModeFromObservability01(out_view.observability_confidence01);
        }

        if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_DIRECT)
          out_view.direct_micro_available = true;

        if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_PROXY)
          out_view.proxy_micro_available = true;

        if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
          out_view.reduced_only = true;

        if(StringLen(out_view.route_reason) <= 0)
          out_view.route_reason = StringFormat("confluence_fallback:%s",
                                               InstitutionalFlowModeText(out_view.flow_mode));

        if(StringLen(out_view.veto_reason) <= 0)
          out_view.veto_reason = "none";

        ApplyUpstreamGateReasonHints(out_view);

        return true;
      #endif
    #endif

    return false;
  }

  inline void _PolicyMergeInstitutionalView(const Settings &cfg,
                                            const InstitutionalStatePolicyView &v,
                                            PolicyResult &out)
  {
    out.institutional_state_loaded       = v.valid;
    out.institutional_gate_pass          = v.trade_gate_pass;
    out.institutional_delay_recommended  = v.delay_recommended;
    out.institutional_derisk_recommended = v.derisk_recommended;

    out.alpha_score                    = v.alpha_score;
    out.execution_score                = v.execution_score;
    out.risk_score                     = v.risk_score;
    out.state_quality01                = v.state_quality01;

    out.vpin01                         = v.vpin01;
    out.vpin_limit01                   = CfgMicroVPINMax01(cfg);
    out.resiliency01                   = v.resiliency01;
    out.resiliency_min01               = CfgMicroResiliencyMin01(cfg);

    out.toxicity01                     = v.toxicity01;
    out.toxicity_max01                 = CfgMicroToxicityMax01(cfg);
    out.spread_stress01                = v.spread_stress01;
    out.spread_stress_max01            = CfgMicroSpreadStressMax01(cfg);

    out.observability_confidence01     = v.observability_confidence01;
    out.flow_confidence01            = v.flow_confidence01;
    out.observability_min01            = CfgMicroObservabilityMin01(cfg);
    out.venue_coverage01               = v.venue_coverage01;
    out.venue_coverage_min01           = CfgMicroVenueCoverageMin01(cfg);
    out.cross_venue_dislocation01      = v.cross_venue_dislocation01;
    out.cross_venue_dislocation_max01  = CfgMicroXVenueDislocationMax01(cfg);

    out.impact_beta01                  = v.impact_beta01;
    out.impact_beta_max01              = CfgMicroImpactBetaMax01(cfg);
    out.impact_lambda01                = v.impact_lambda01;
    out.impact_lambda_max01            = CfgMicroImpactLambdaMax01(cfg);

    out.truth_tier01                  = v.truth_tier01;
    out.truth_tier_aggressive_min01   = CfgMicroTruthTierAggressiveMin01(cfg);
    out.execution_posture_mode        = v.execution_posture_mode;
    out.reduced_only                  = v.reduced_only;
    out.invalidation_event01          = v.invalidation_event01;
    out.liquidity_trap_event01        = v.liquidity_trap_event01;

    out.darkpool01                     = v.darkpool01;
    out.darkpool_min01                 = CfgMicroDarkPoolMin01(cfg);
    out.darkpool_contradiction01       = v.darkpool_contradiction01;
    out.darkpool_contradiction_max01   = CfgMicroDarkPoolContradictionMax01(cfg);

    out.sd_ob_invalidation_proximity01 = v.sd_ob_invalidation_proximity01;
    out.sd_ob_invalidation_max01       = CfgSmartMoneyInvalidationMax01(cfg);

    out.liquidity_vacuum01             = v.liquidity_vacuum01;
    out.liquidity_vacuum_max01         = CfgLiquidityVacuumMax01(cfg);
    out.liquidity_hunt01               = v.liquidity_hunt01;
    out.liquidity_hunt_max01           = CfgLiquidityHuntMax01(cfg);

    out.observability_penalty01        = v.observability_penalty01;

    out.direct_micro_available         = v.direct_micro_available;
    out.proxy_micro_available          = v.proxy_micro_available;
    out.flow_mode                      = v.flow_mode;

    out.inst_ofi01                     = v.inst_ofi01;
    out.inst_obi01                     = v.inst_obi01;
    out.inst_cvd01                     = v.inst_cvd01;

    out.inst_delta_proxy01             = v.inst_delta_proxy01;
    out.inst_footprint01               = v.inst_footprint01;
    out.inst_profile01                 = v.inst_profile01;
    out.inst_absorption01              = v.inst_absorption01;
    out.inst_replenishment01           = v.inst_replenishment01;
    out.inst_vwap_location01           = v.inst_vwap_location01;
    out.inst_liquidity_reject01        = v.inst_liquidity_reject01;

    out.confluence_veto_mask           = v.confluence_veto_mask;
    out.route_reason                   = v.route_reason;
    out.veto_reason                    = v.veto_reason;
  }

  inline Direction _IntegratedStateDir(const FinalStrategyIntegratedStateVector_t &st)
  {
     if(st.hypothesis.intended_direction == TDIR_SELL)
        return DIR_SELL;
     return DIR_BUY;
  }

  inline void _IntegratedStateToStratScore(const FinalStrategyIntegratedStateVector_t &st,
                                           StratScore &ss)
  {
     ZeroMemory(ss);

     ss.id        = (StrategyID)st.hypothesis.strategy_id;
     ss.score     = Clamp01((st.confidence_score + st.alpha_score + st.execution_score + (1.0 - st.risk_score)) / 4.0);
     ss.risk_mult = Clamp(1.0 - (0.50 * Clamp01(st.risk_score)), 0.25, 1.0);

     ss.hint_sl_price = st.hypothesis.stop_loss;
     ss.hint_tp_price = st.hypothesis.take_profit;
  }

  inline double PolicyISV_RawSlot(const RawSignalBank_t &bank,
                                  const int slot,
                                  const double fallback = 0.0)
  {
     if(slot < 0 || slot >= ISV::ISV_SLOT_COUNT)
        return fallback;
     return bank.raw[slot];
  }

  inline double PolicyISV_ZSlot(const RawSignalBank_t &bank,
                                const int slot,
                                const double fallback = 0.0)
  {
     if(slot < 0 || slot >= ISV::ISV_SLOT_COUNT)
        return fallback;
     return bank.z[slot];
  }

  inline double PolicyISV_Clamp11(const double x)
  {
     if(x > 1.0)  return 1.0;
     if(x < -1.0) return -1.0;
     return x;
  }

  inline double PolicyISV_Toxicity01(const RawSignalBank_t &bank)
  {
     const double vpin01 =
        Clamp01(PolicyISV_RawSlot(bank, ISV::ISV_VPIN, 0.0));

     const double lambda01 =
        Clamp01(MathAbs(PolicyISV_RawSlot(bank, ISV::ISV_LAMBDA_T, 0.0)));

     const double resiliency01 =
        Clamp01(1.0 - Clamp01(MathAbs(PolicyISV_ZSlot(bank, ISV::ISV_DEPTH_FADE, 0.0)) / 3.0));

     return Clamp01(0.45 * vpin01 +
                    0.35 * lambda01 +
                    0.20 * (1.0 - resiliency01));
  }

  inline double PolicyISV_DeltaProxy01(const RawSignalBank_t &bank)
  {
     const double signed_flow =
        PolicyISV_RawSlot(bank, ISV::ISV_SIGNED_FLOW, 0.0);

     return Clamp01(0.50 + 0.50 * PolicyISV_Clamp11(signed_flow));
  }

  inline double PolicyISV_Absorption01(const RawSignalBank_t &bank)
  {
     return Clamp01(
        MathMax(
           MathAbs(PolicyISV_RawSlot(bank, ISV::ISV_ABS_PLUS, 0.0)),
           MathAbs(PolicyISV_RawSlot(bank, ISV::ISV_ABS_MINUS, 0.0))
        )
     );
  }

  inline double PolicyISV_Replenishment01(const RawSignalBank_t &bank)
  {
     return Clamp01(
        MathMax(
           MathAbs(PolicyISV_RawSlot(bank, ISV::ISV_REPL_BID, 0.0)),
           MathAbs(PolicyISV_RawSlot(bank, ISV::ISV_REPL_ASK, 0.0))
        )
     );
  }

  inline double PolicyISV_LiquidityReject01(const RawSignalBank_t &bank)
  {
     return Clamp01(MathAbs(PolicyISV_RawSlot(bank, ISV::ISV_SWEEP_SCORE, 0.0)));
  }

  inline void _PolicyMergeIntegratedState(const Settings &cfg,
                                          const FinalStrategyIntegratedStateVector_t &st,
                                          PolicyResult &out)
  {
     out.institutional_state_loaded       = st.valid;
     out.institutional_gate_pass          = (st.signal_stack_gate_pass &&
                                             st.location_pass &&
                                             st.pre_filter_pass &&
                                             st.execution_pass &&
                                             st.risk_pass);
     out.institutional_delay_recommended  = false;
     out.institutional_derisk_recommended = false;

     out.alpha_score      = Clamp01(st.alpha_score);
     out.execution_score  = Clamp01(st.execution_score);
     out.risk_score       = Clamp01(st.risk_score);
     out.state_quality01  = Clamp01((st.confidence_score + st.alpha_score + st.execution_score + (1.0 - st.risk_score)) / 4.0);

     out.vpin01                        = Clamp01(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_VPIN, 0.0));
     out.vpin_limit01                  = CfgMicroVPINMax01(cfg);
     out.resiliency01                  = Clamp01(1.0 - Clamp01(MathAbs(PolicyISV_ZSlot(st.raw_bank, ISV::ISV_DEPTH_FADE, 0.0)) / 3.0));
     out.resiliency_min01              = CfgMicroResiliencyMin01(cfg);

     out.toxicity01                    = PolicyISV_Toxicity01(st.raw_bank);
     out.toxicity_max01                = CfgMicroToxicityMax01(cfg);
     out.spread_stress01               = Clamp01(MathAbs(PolicyISV_ZSlot(st.raw_bank, ISV::ISV_SPREAD_SHOCK, 0.0)) / 3.0);
     out.spread_stress_max01           = CfgMicroSpreadStressMax01(cfg);

     out.observability_confidence01    = Clamp01(st.raw_bank.degrade.observability01);
     out.flow_confidence01             = Clamp01(1.0 - st.raw_bank.degrade.observability_penalty01);
     out.observability_min01           = CfgMicroObservabilityMin01(cfg);
     out.venue_coverage01              = Clamp01(st.raw_bank.degrade.venue_coverage01);
     out.venue_coverage_min01          = CfgMicroVenueCoverageMin01(cfg);
     out.cross_venue_dislocation01     = 0.0;
     out.cross_venue_dislocation_max01 = CfgMicroXVenueDislocationMax01(cfg);

     out.impact_beta01                 = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_BETA_T, 0.0)));
     out.impact_beta_max01             = CfgMicroImpactBetaMax01(cfg);
     out.impact_lambda01               = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_LAMBDA_T, 0.0)));
     out.impact_lambda_max01           = CfgMicroImpactLambdaMax01(cfg);

     out.truth_tier01                  = Clamp01(1.0 - st.raw_bank.degrade.observability_penalty01);
     out.truth_tier_aggressive_min01   = CfgMicroTruthTierAggressiveMin01(cfg);
     out.execution_posture_mode        = 0;
     out.reduced_only                  = (st.raw_bank.degrade.inst_unavailable == 1 && st.raw_bank.degrade.proxy_inst_available == 0);
     out.invalidation_event01          = false;
     out.liquidity_trap_event01        = false;

     out.darkpool01                    = 1.0;
     out.darkpool_min01                = CfgMicroDarkPoolMin01(cfg);
     out.darkpool_contradiction01      = 0.0;
     out.darkpool_contradiction_max01  = CfgMicroDarkPoolContradictionMax01(cfg);

     out.sd_ob_invalidation_proximity01 = 0.0;
     out.sd_ob_invalidation_max01       = CfgSmartMoneyInvalidationMax01(cfg);

     out.liquidity_vacuum01             = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_LIQUIDITY_STRESS_PROXY, 0.0)));
     out.liquidity_vacuum_max01         = CfgLiquidityVacuumMax01(cfg);
     out.liquidity_hunt01               = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_SWEEP_SCORE, 0.0)));
     out.liquidity_hunt_max01           = CfgLiquidityHuntMax01(cfg);

     out.observability_penalty01        = Clamp01(st.raw_bank.degrade.observability_penalty01);

     out.direct_micro_available         = (st.raw_bank.degrade.inst_available > 0 && st.raw_bank.degrade.inst_unavailable == 0);
     out.proxy_micro_available          = (st.raw_bank.degrade.proxy_inst_available > 0);

     if(out.direct_micro_available)
        out.flow_mode = POLICIES_INST_FLOW_MODE_DIRECT;
     else if(out.proxy_micro_available)
        out.flow_mode = POLICIES_INST_FLOW_MODE_PROXY;
     else
        out.flow_mode = POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY;

     out.inst_ofi01                     = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_OFI, 0.0)));
     out.inst_obi01                     = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_OBI_1, 0.0)));
     out.inst_cvd01                     = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_FLOW_IMB, 0.0)));

     out.inst_delta_proxy01             = PolicyISV_DeltaProxy01(st.raw_bank);
     out.inst_footprint01               = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_FOOTPRINT_DELTA, 0.0)));
     out.inst_profile01                 = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_POC_DIST, 0.0)));
     out.inst_absorption01              = PolicyISV_Absorption01(st.raw_bank);
     out.inst_replenishment01           = PolicyISV_Replenishment01(st.raw_bank);
     out.inst_vwap_location01           = Clamp01(MathAbs(PolicyISV_RawSlot(st.raw_bank, ISV::ISV_MID_MINUS_VWAP, 0.0)));
     out.inst_liquidity_reject01        = PolicyISV_LiquidityReject01(st.raw_bank);

     out.confluence_veto_mask           = 0;
     out.route_reason                   = "integrated_state";
     out.veto_reason                    = (StringLen(st.veto_reason) > 0 ? st.veto_reason : "none");
  }

  inline bool ApplyInstitutionalStatePolicy(const Settings &cfg,
                                            const string sym,
                                            StratScore &ss,
                                            InstitutionalStatePolicyView &out_view)
  {
    ResetInstitutionalStatePolicyView(out_view);

    if(!LoadInstitutionalStateFromSymbolState(cfg, sym, CfgTFEntry(cfg), out_view))
    {
      if(!LoadInstitutionalStateFromConfluence(sym, CfgTFEntry(cfg), out_view))
        return true; // no canonical transport yet => do not invent pseudo-state here
    }

    out_view.gate_reason = GATE_OK;

    // Canonical fused veto from Confluence transport beats any local optimism.
    if(out_view.confluence_veto_mask != 0)
    {
      out_view.delay_recommended = true;
      out_view.gate_reason = GATE_INSTITUTIONAL;

      if(StringLen(out_view.veto_reason) <= 0)
        out_view.veto_reason = "confluence_veto";

      return false;
    }

    // Upstream hard institutional block is terminal here.
    // Policies may consume it, but must not override it.
    if(out_view.upstream_hard_inst_block)
    {
      out_view.delay_recommended = true;
      out_view.gate_reason = GATE_INST_HARD_BLOCK;

      if(StringLen(out_view.veto_reason) <= 0 || out_view.veto_reason == "none")
        out_view.veto_reason = "hard_inst_block";

      return false;
    }

    // Upstream signal-stack / location / prefilter gate failures also win here.
    // Policies must not rebuild or override those decisions.
    if(!out_view.upstream_pre_filter_pass ||
       !out_view.upstream_signal_stack_gate_pass ||
       !out_view.upstream_location_pass ||
       !out_view.upstream_execution_gate_pass ||
       !out_view.upstream_risk_gate_pass)
    {
      out_view.delay_recommended = true;
      out_view.gate_reason = GATE_INSTITUTIONAL;

      if(StringLen(out_view.veto_reason) <= 0 || out_view.veto_reason == "none")
      {
        if(!out_view.upstream_signal_stack_gate_pass)
          out_view.veto_reason = "signal_stack_gate_fail";
        else if(!out_view.upstream_location_pass)
          out_view.veto_reason = "location_pass_fail";
        else if(!out_view.upstream_execution_gate_pass)
          out_view.veto_reason = "execution_gate_fail";
        else if(!out_view.upstream_risk_gate_pass)
          out_view.veto_reason = "risk_gate_fail";
        else
          out_view.veto_reason = "pre_filter_fail";
      }

      return false;
    }

    if(PolicyInstitutionalBypassActive(cfg))
    {
      if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
        out_view.reduced_only = true;

      out_view.gate_reason = GATE_OK;
      out_view.delay_recommended = false;

      if(StringLen(out_view.route_reason) <= 0)
        out_view.route_reason = "tester_bypass";

      if(StringLen(out_view.veto_reason) <= 0 || out_view.veto_reason == "none")
        out_view.veto_reason = "tester_bypass";

      _GateDetail(cfg, GATE_INSTITUTIONAL, sym,
                  StringFormat("tester_bypass=1 flow_mode=%d direct=%d proxy=%d",
                               out_view.flow_mode,
                               (out_view.direct_micro_available ? 1 : 0),
                               (out_view.proxy_micro_available ? 1 : 0)));
      return true;
    }

    // Structure-only is always reduced-only from policy perspective.
    if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
      out_view.reduced_only = true;

    // Generic canonical veto from the fused transport
    if(!out_view.trade_gate_pass)
    {
      out_view.gate_reason = UpstreamInstitutionalGateReasonFromView(out_view);

      if(StringLen(out_view.veto_reason) <= 0 || out_view.veto_reason == "none")
        out_view.veto_reason = "trade_gate_fail";

      return false;
    }

   // State quality gate
   if(out_view.state_quality01 < PolicyStateQualityMin01())
   {
     out_view.delay_recommended = true;
     out_view.gate_reason = GATE_INSTITUTIONAL;
     return false;
   }

    // Observability gate
    {
      const double omin = CfgMicroObservabilityMin01(cfg);
      if(omin > 0.0 && out_view.observability_confidence01 < omin)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_MICRO_OBSERVABILITY;
        return false;
      }
    }

    // Flow confidence gate
    {
      const double fmin = CfgMicroObservabilityMin01(cfg);
      if(fmin > 0.0 &&
         (out_view.direct_micro_available || out_view.proxy_micro_available) &&
         out_view.flow_confidence01 < fmin)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_MICRO_OBSERVABILITY;

        if(StringLen(out_view.veto_reason) <= 0 || out_view.veto_reason == "none")
          out_view.veto_reason = "flow_confidence_low";

        return false;
      }
    }

    // Stronger observability gate for continuation / breakout style posture.
    // Policies does not own archetypes; it uses posture + reduced_only as the hard proxy.
    {
      const double ostrong = CfgMicroContinuationObservabilityMin01(cfg);
      if(ostrong > 0.0 &&
         InstitutionalNeedsStrongObservability(out_view) &&
         out_view.observability_confidence01 < ostrong)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_MICRO_OBSERVABILITY;
        return false;
      }
    }

    if(CfgMicroStructureOnlyAggressiveVetoOn(cfg) &&
       InstitutionalStructureOnlyPostureTooAggressive(out_view))
    {
      out_view.delay_recommended = true;
      out_view.gate_reason = GATE_MICRO_TRUTH;

      if(StringLen(out_view.veto_reason) <= 0)
        out_view.veto_reason = "structure_only_posture";

      return false;
    }

    if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_PROXY &&
       CfgMicroProxyForceReducedOnlyOn(cfg) &&
       !out_view.reduced_only &&
       out_view.observability_confidence01 < CfgMicroContinuationObservabilityMin01(cfg))
    {
      out_view.reduced_only = true;
      out_view.derisk_recommended = true;
    }

    // Venue coverage gate
    {
      const double vmin = CfgMicroVenueCoverageMin01(cfg);
      if(vmin > 0.0 && out_view.venue_coverage01 < vmin)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_MICRO_VENUE;
        return false;
      }
    }

    // Quote instability / cross-venue dislocation veto
    {
      const double xmax = CfgMicroXVenueDislocationMax01(cfg);
      if(xmax < 1.0 && out_view.cross_venue_dislocation01 >= xmax)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_MICRO_QUOTE_INSTABILITY;
        return false;
      }
    }

    #ifdef POLICIES_INST_ENABLE_SPREAD_STRESS_VETO
      if(CfgMicroSpreadStressGateOn(cfg))
      {
        const double smax = CfgMicroSpreadStressMax01(cfg);
        if(smax < 1.0 && out_view.spread_stress01 >= smax)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_SPREAD_STRESS;
          return false;
        }
      }
    #endif

    // Explicit microstructure hard gates
    #ifdef POLICIES_INST_ENABLE_VPIN_VETO
      if(CfgMicroVPINGateOn(cfg))
      {
        const double vmax = CfgMicroVPINMax01(cfg);
        if(vmax < 1.0 && out_view.vpin01 >= vmax)
        {
          out_view.gate_reason = GATE_MICRO_VPIN;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_TOXICITY_VETO
      if(CfgMicroToxicityGateOn(cfg))
      {
        const double tmax = CfgMicroToxicityMax01(cfg);
        if(tmax < 1.0 && out_view.toxicity01 >= tmax)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_TOXICITY;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_RESILIENCY_VETO
      if(CfgMicroResiliencyGateOn(cfg))
      {
        const double rmin = CfgMicroResiliencyMin01(cfg);
        if(rmin > 0.0 && out_view.resiliency01 <= rmin)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_RESILIENCY;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_IMPACT_VETO
      if(CfgMicroImpactGateOn(cfg))
      {
        const double bmax = CfgMicroImpactBetaMax01(cfg);
        const double lmax = CfgMicroImpactLambdaMax01(cfg);

        if((bmax < 1.0 && out_view.impact_beta01 >= bmax) ||
           (lmax < 1.0 && out_view.impact_lambda01 >= lmax))
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_IMPACT;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_TRUTH_POSTURE_VETO
      if(InstitutionalAggressivePosture(out_view))
      {
        const double tmin = CfgMicroTruthTierAggressiveMin01(cfg);
        if(tmin > 0.0 && out_view.truth_tier01 < tmin)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_TRUTH;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_DARKPOOL_VETO
      if(CfgMicroDarkPoolGateOn(cfg))
      {
        const double dmin = CfgMicroDarkPoolMin01(cfg);
        const double cmax = CfgMicroDarkPoolContradictionMax01(cfg);

        if((dmin > 0.0 && out_view.darkpool01 <= dmin) ||
           (cmax < 1.0 && out_view.darkpool_contradiction01 >= cmax))
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_DARKPOOL;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_INVALIDATION_EVENT_VETO
      if(out_view.invalidation_event01)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_SM_INVALIDATION;
        return false;
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_SD_OB_INVALIDATION_VETO
      if(CfgSmartMoneyInvalidationGateOn(cfg))
      {
        const double smax = CfgSmartMoneyInvalidationMax01(cfg);
        if(smax < 1.0 && out_view.sd_ob_invalidation_proximity01 >= smax)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_SM_INVALIDATION;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_LIQUIDITY_TRAP_VETO
      if(CfgLiquidityTrapGateOn(cfg))
      {
        const double vmax = CfgLiquidityVacuumMax01(cfg);
        const double hmax = CfgLiquidityHuntMax01(cfg);

        if(vmax < 1.0 && out_view.liquidity_vacuum01 >= vmax)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_MICRO_THIN_LIQUIDITY;
          return false;
        }

        if(hmax < 1.0 && out_view.liquidity_hunt01 >= hmax)
        {
          out_view.delay_recommended = true;
          out_view.gate_reason = GATE_LIQUIDITY_TRAP;
          return false;
        }
      }
    #endif

    #ifdef POLICIES_INST_ENABLE_LIQUIDITY_TRAP_EVENT_VETO
      if(out_view.liquidity_trap_event01)
      {
        out_view.delay_recommended = true;
        out_view.gate_reason = GATE_LIQUIDITY_TRAP;
        return false;
      }
    #endif

    // Weak execution head => delay / no-trade-now
    if(out_view.execution_score < (double)POLICIES_INST_DELAY_EXECUTION_SCORE01)
    {
      out_view.delay_recommended = true;
      out_view.gate_reason = GATE_INSTITUTIONAL;
      return false;
    }

    // Risk head says "too dangerous" => veto
    if(out_view.risk_score <= (double)POLICIES_INST_VETO_RISK_SCORE01)
    {
      out_view.gate_reason = GATE_INSTITUTIONAL;
      return false;
    }

    // Risk head says "allowed, but smaller" => derisk
    if(out_view.risk_score < (double)POLICIES_INST_DERISK_RISK_SCORE01)
    {
      out_view.derisk_recommended = true;
      ss.risk_mult = Clamp01(ss.risk_mult * Clamp(out_view.risk_score, 0.25, 1.0));
    }

    if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_PROXY)
    {
      ss.risk_mult = Clamp01(ss.risk_mult * CfgMicroProxyDeriskMult01(cfg));
      out_view.derisk_recommended = true;
    }
    else if(out_view.flow_mode == POLICIES_INST_FLOW_MODE_STRUCTURE_ONLY)
    {
      ss.risk_mult = Clamp01(ss.risk_mult * CfgMicroStructureOnlyDeriskMult01(cfg));
      out_view.reduced_only = true;
      out_view.derisk_recommended = true;
    }
    
    return true;
  }

  inline ulong InstitutionalMaskForGateReason(const int gr)
  {
    if(gr == GATE_INST_HARD_BLOCK)        return CA_POLMASK_INSTITUTIONAL;
    if(gr == GATE_MICRO_VPIN)             return CA_POLMASK_MICRO_VPIN;
    if(gr == GATE_MICRO_RESILIENCY)       return CA_POLMASK_MICRO_RESILIENCY;
    if(gr == GATE_MICRO_OBSERVABILITY)    return CA_POLMASK_MICRO_OBSERVABILITY;
    if(gr == GATE_MICRO_VENUE)            return CA_POLMASK_MICRO_VENUE;
    if(gr == GATE_MICRO_IMPACT)           return CA_POLMASK_MICRO_IMPACT;
    if(gr == GATE_MICRO_DARKPOOL)         return CA_POLMASK_MICRO_DARKPOOL;
    if(gr == GATE_SM_INVALIDATION)        return CA_POLMASK_SM_INVALIDATION;
    if(gr == GATE_LIQUIDITY_TRAP)         return CA_POLMASK_LIQUIDITY_TRAP;
    if(gr == GATE_MICRO_QUOTE_INSTABILITY)return CA_POLMASK_MICRO_QUOTE_INSTABILITY;
    if(gr == GATE_MICRO_THIN_LIQUIDITY)   return CA_POLMASK_MICRO_THIN_LIQUIDITY;
    if(gr == GATE_MICRO_TOXICITY)         return CA_POLMASK_MICRO_TOXICITY;
    if(gr == GATE_MICRO_SPREAD_STRESS)    return CA_POLMASK_MICRO_SPREAD_STRESS;
    if(gr == GATE_MICRO_TRUTH)            return CA_POLMASK_MICRO_TRUTH;
    return CA_POLMASK_INSTITUTIONAL;
  }

  inline bool _EvaluateFinalSendGateEx(const Settings &cfg,
                                       const string sym,
                                       StratScore &ss,
                                       PolicyResult &out,
                                       InstitutionalStatePolicyView &inst_view,
                                       const bool audit)
  {
    const bool ok_full = _EvaluateFullEx(cfg, sym, out, audit);
    if(!audit && !ok_full)
      return false;

    ResetInstitutionalStatePolicyView(inst_view);

    if(PolicyDisableMicrostructureGatesActive(cfg))
    {
      ApplyNeutralInstitutionalStatePolicyView(inst_view, "micro_disabled");
      _PolicyMergeInstitutionalView(cfg, inst_view, out);
      out.allowed = true;
      out.primary_reason = GATE_OK;
      out.veto_mask = 0;
      return true;
    }

    if(!ApplyInstitutionalStatePolicy(cfg, sym, ss, inst_view))
    {
      if((PolicyTesterLooseModeActive(cfg) || PolicyMicroRelaxActive(cfg)) &&
         !InstitutionalUpstreamDegradeVeto(inst_view) &&
         inst_view.gate_reason != GATE_INST_HARD_BLOCK)
      {
        ApplyNeutralInstitutionalStatePolicyView(inst_view, "micro_relaxed");
        _PolicyMergeInstitutionalView(cfg, inst_view, out);
        out.allowed = true;
        out.primary_reason = GATE_OK;
        out.veto_mask = 0;
        return true;
      }

      _PolicyMergeInstitutionalView(cfg, inst_view, out);

      int gr = inst_view.gate_reason;
      if(gr <= GATE_OK)
        gr = GATE_INSTITUTIONAL;

      const ulong mask = InstitutionalMaskForGateReason(gr);

      _PolicyVeto(out, gr, mask);
      if(!audit)
        return false;
    }

    if(!inst_view.valid)
      ApplyNeutralInstitutionalStatePolicyView(inst_view, "micro_unavailable");

    _PolicyMergeInstitutionalView(cfg, inst_view, out);
    return out.allowed;
  }

  inline bool EvaluateFinalSendGate(const Settings &cfg,
                                    const string sym,
                                    StratScore &ss,
                                    PolicyResult &out,
                                    InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateFinalSendGateEx(cfg, sym, ss, out, inst_view, false);
  }

  inline bool EvaluateFinalSendGateAudit(const Settings &cfg,
                                         const string sym,
                                         StratScore &ss,
                                         PolicyResult &out,
                                         InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateFinalSendGateEx(cfg, sym, ss, out, inst_view, true);
  }

  inline bool EvaluateFinalSendGate(const Settings &cfg,
                                    StratScore &ss,
                                    PolicyResult &out,
                                    InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateFinalSendGateEx(cfg, _Symbol, ss, out, inst_view, false);
  }

  inline bool EvaluateFinalSendGateAudit(const Settings &cfg,
                                         StratScore &ss,
                                         PolicyResult &out,
                                         InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateFinalSendGateEx(cfg, _Symbol, ss, out, inst_view, true);
  }

  inline bool _EvaluateFinalSendGateFromIntegratedStateEx(const Settings &cfg,
                                                          FinalStrategyIntegratedStateVector_t &io_state,
                                                          PolicyResult &out,
                                                          const bool audit)
  {
     const string sym =
        (StringLen(io_state.symbol) > 0 ? io_state.symbol :
         (StringLen(io_state.raw_bank.symbol) > 0 ? io_state.raw_bank.symbol : _Symbol));

     const bool ok_full = _EvaluateFullEx(cfg, sym, out, audit);
     if(!audit && !ok_full)
     {
        PolicyApplyResultToIntegratedState(out, io_state);
        return false;
     }

     _PolicyMergeIntegratedState(cfg, io_state, out);

     if(!io_state.valid)
     {
        _PolicyVeto(out, GATE_INSTITUTIONAL, CA_POLMASK_INSTITUTIONAL);
        PolicyApplyResultToIntegratedState(out, io_state);
        if(!audit) return false;
     }

     if(!io_state.signal_stack_gate_pass ||
        !io_state.location_pass ||
        !io_state.pre_filter_pass ||
        !io_state.execution_pass ||
        !io_state.risk_pass)
     {
        _PolicyVeto(out, GATE_INSTITUTIONAL, CA_POLMASK_INSTITUTIONAL);

        if(StringLen(out.veto_reason) <= 0 || out.veto_reason == "none")
        {
           if(!io_state.signal_stack_gate_pass) out.veto_reason = "signal_stack_gate_fail";
           else if(!io_state.location_pass)     out.veto_reason = "location_pass_fail";
           else if(!io_state.execution_pass)    out.veto_reason = "execution_gate_fail";
           else if(!io_state.risk_pass)         out.veto_reason = "risk_gate_fail";
           else                                 out.veto_reason = "pre_filter_fail";
        }

        PolicyApplyResultToIntegratedState(out, io_state);
        if(!audit) return false;
     }

     if(io_state.raw_bank.degrade.hard_inst_block == 1)
     {
        _PolicyVeto(out, GATE_INST_HARD_BLOCK, CA_POLMASK_INSTITUTIONAL);
        out.veto_reason = "hard_inst_block";
        PolicyApplyResultToIntegratedState(out, io_state);
        if(!audit) return false;
     }

     if(out.execution_score < (double)POLICIES_INST_DELAY_EXECUTION_SCORE01)
     {
        _PolicyVeto(out, GATE_INSTITUTIONAL, CA_POLMASK_INSTITUTIONAL);
        out.veto_reason = "execution_score_too_low";
        PolicyApplyResultToIntegratedState(out, io_state);
        if(!audit) return false;
     }

     if(out.risk_score <= (double)POLICIES_INST_VETO_RISK_SCORE01)
     {
        _PolicyVeto(out, GATE_INSTITUTIONAL, CA_POLMASK_INSTITUTIONAL);
        out.veto_reason = "risk_score_veto";
        PolicyApplyResultToIntegratedState(out, io_state);
        if(!audit) return false;
     }

     if(out.risk_score < (double)POLICIES_INST_DERISK_RISK_SCORE01)
        out.institutional_derisk_recommended = true;

     out.allowed = true;
     out.primary_reason = GATE_OK;
     out.veto_mask = 0;

     PolicyApplyResultToIntegratedState(out, io_state);
     return true;
  }

  inline bool EvaluateFinalSendGateFromIntegratedState(const Settings &cfg,
                                                       FinalStrategyIntegratedStateVector_t &io_state,
                                                       PolicyResult &out)
  {
     return _EvaluateFinalSendGateFromIntegratedStateEx(cfg, io_state, out, false);
  }

  inline bool EvaluateFinalSendGateFromIntegratedStateAudit(const Settings &cfg,
                                                            FinalStrategyIntegratedStateVector_t &io_state,
                                                            PolicyResult &out)
  {
     return _EvaluateFinalSendGateFromIntegratedStateEx(cfg, io_state, out, true);
  }

  inline bool _EvaluateMicrostructurePolicyEx(const Settings &cfg,
                                              const string sym,
                                              StratScore &ss,
                                              PolicyResult &out,
                                              InstitutionalStatePolicyView &inst_view,
                                              const bool audit)
  {
    s_last_eval_sym = sym;
    _EnsureLoaded(cfg);

    _PolicyReset(out);
    ResetInstitutionalStatePolicyView(inst_view);

    if(PolicyDisableMicrostructureGatesActive(cfg))
    {
      ApplyNeutralInstitutionalStatePolicyView(inst_view, "micro_disabled");
      _PolicyMergeInstitutionalView(cfg, inst_view, out);
      out.allowed = true;
      out.primary_reason = GATE_OK;
      out.veto_mask = 0;
      return true;
    }

    if(!ApplyInstitutionalStatePolicy(cfg, sym, ss, inst_view))
    {
      if((PolicyTesterLooseModeActive(cfg) || PolicyMicroRelaxActive(cfg)) &&
         !InstitutionalUpstreamDegradeVeto(inst_view) &&
         inst_view.gate_reason != GATE_INST_HARD_BLOCK)
      {
        ApplyNeutralInstitutionalStatePolicyView(inst_view, "micro_relaxed");
        _PolicyMergeInstitutionalView(cfg, inst_view, out);
        out.allowed = true;
        out.primary_reason = GATE_OK;
        out.veto_mask = 0;
        return true;
      }

      _PolicyMergeInstitutionalView(cfg, inst_view, out);

      int gr = inst_view.gate_reason;
      if(gr <= GATE_OK)
        gr = GATE_INSTITUTIONAL;

      _PolicyVeto(out, gr, InstitutionalMaskForGateReason(gr));
      if(!audit)
        return false;
    }

    if(!inst_view.valid)
      ApplyNeutralInstitutionalStatePolicyView(inst_view, "micro_unavailable");

    _PolicyMergeInstitutionalView(cfg, inst_view, out);
    return out.allowed;
  }

  inline bool EvaluateMicrostructurePolicy(const Settings &cfg,
                                           const string sym,
                                           StratScore &ss,
                                           PolicyResult &out,
                                           InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateMicrostructurePolicyEx(cfg, sym, ss, out, inst_view, false);
  }

  inline bool EvaluateMicrostructurePolicyAudit(const Settings &cfg,
                                                const string sym,
                                                StratScore &ss,
                                                PolicyResult &out,
                                                InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateMicrostructurePolicyEx(cfg, sym, ss, out, inst_view, true);
  }

  inline bool EvaluateMicrostructurePolicy(const Settings &cfg,
                                           StratScore &ss,
                                           PolicyResult &out,
                                           InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateMicrostructurePolicyEx(cfg, _Symbol, ss, out, inst_view, false);
  }

  inline bool EvaluateMicrostructurePolicyAudit(const Settings &cfg,
                                                StratScore &ss,
                                                PolicyResult &out,
                                                InstitutionalStatePolicyView &inst_view)
  {
    return _EvaluateMicrostructurePolicyEx(cfg, _Symbol, ss, out, inst_view, true);
  }

  // ----------------------------------------------------------------------------
  // Classic gates: Check / CheckFull / AllowedByPolicies
  // Candidate-aware final pre-send gate: EvaluateFinalSendGate(...)
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

      // Router floor (diagnostic only; actual eligibility still lives in Router)
      const double routerMin = CfgRouterMinScore(cfg);
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
    if(CfgNewsPolicyEnabled(cfg))
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
    StratScore SS = in_ss; ConfluenceBreakdown BD = in_bd;
    bool skip=false; ApplyPolicyRiskOverlays(cfg, symbol, SS, BD, skip);
    if(skip){ gate_reason=GATE_NEWS; out_intent.reason=gate_reason; return false; }

    OrderPlan plan; ZeroMemory(plan);
    if(!Risk::ComputeOrderForSymbol(symbol, dir, cfg, SS, plan, BD))
    { gate_reason=GATE_CONFLICT; out_intent.reason=gate_reason; return false; }

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
     else if(r.primary_reason == GATE_MICRO_VPIN)
       aux_out = (int)MathRound(1000.0 * r.vpin01);
     else if(r.primary_reason == GATE_MICRO_RESILIENCY)
       aux_out = (int)MathRound(1000.0 * r.resiliency01);
     else if(r.primary_reason == GATE_MICRO_OBSERVABILITY)
       aux_out = (int)MathRound(1000.0 * r.observability_confidence01);
     else if(r.primary_reason == GATE_MICRO_VENUE)
       aux_out = (int)MathRound(1000.0 * r.venue_coverage01);
     else if(r.primary_reason == GATE_MICRO_QUOTE_INSTABILITY)
       aux_out = (int)MathRound(1000.0 * PolicyQuoteInstability01(r));
     else if(r.primary_reason == GATE_MICRO_IMPACT)
       aux_out = (int)MathRound(1000.0 * MathMax(r.impact_beta01, r.impact_lambda01));
     else if(r.primary_reason == GATE_MICRO_TRUTH)
       aux_out = (int)MathRound(1000.0 * r.truth_tier01);
     else if(r.primary_reason == GATE_MICRO_DARKPOOL)
       aux_out = (int)MathRound(1000.0 * MathMax(1.0 - r.darkpool01, r.darkpool_contradiction01));
     else if(r.primary_reason == GATE_SM_INVALIDATION)
       aux_out = (int)MathRound(1000.0 * r.sd_ob_invalidation_proximity01);
     else if(r.primary_reason == GATE_MICRO_THIN_LIQUIDITY)
       aux_out = (int)MathRound(1000.0 * PolicyThinLiquidity01(r));
     else if(r.primary_reason == GATE_LIQUIDITY_TRAP)
       aux_out = (int)MathRound(1000.0 * r.liquidity_hunt01);

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

    double   day_dd_strict_pct;
    bool     sizing_reset_active;
    int      sizing_reset_sec_left;

    int      risk_reject_code;
    double   risk_money_base;
    double   risk_money_final;
    double   risk_taper;
    double   risk_throttle;
    double   risk_news_mult;
    double   risk_eff_mult;
    double   risk_lots_final;
  };

  inline void _FillRiskTelemetryFromEngine(const string sym, Telemetry &t)
  {
    #ifdef POLICIES_HAS_RISKENGINE_DIAG_BRIDGE
      Risk::RiskDiag rd;
      bool have = false;

      #ifdef POLICIES_HAS_RISKENGINE_DIAG_SYMBOL_BRIDGE
        have = Risk::GetLastDiagForSymbol(sym, rd);
      #else
        Risk::GetLastDiag(rd);
        have = (StringLen(rd.sym) > 0 && StringCompare(rd.sym, sym, false) == 0);
      #endif

      if(!have)
        return;

      t.risk_reject_code = rd.reject_code;
      t.risk_money_base  = rd.risk_money_base;
      t.risk_money_final = rd.risk_money_final;
      t.risk_taper       = rd.taper;
      t.risk_throttle    = rd.throttle;
      t.risk_news_mult   = rd.news_mult;
      t.risk_eff_mult    = rd.eff_mult;
      t.risk_lots_final  = rd.lots_final;
    #endif
  }

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
    t.day_dd_strict_pct   = pr.day_dd_strict_pct;
    t.sizing_reset_active = pr.sizing_reset_active;
    t.sizing_reset_sec_left = pr.sizing_reset_sec_left;

    // day PL & stops
    double pl=0.0; int w=0,l=0;
    if(DailyRealizedPL(cfg, pl, w, l)){ t.day_pl = pl; t.day_wins=w; t.day_losses=l; }

    // attempts + last attempt + last retcode
    t.attempts_today = _GVGetI(_Key("ATTEMPTS_D"), 0);
    t.last_attempt_ts= (datetime)_GVGetD(_Key("LAST_ATTEMPT_TS"), 0.0);
    t.last_retcode   = (uint)_GVGetI(_Key("LAST_EXEC_RC"), 0);
    {
      const string risk_sym = (StringLen(s_last_eval_sym) > 0 ? s_last_eval_sym : _Symbol);
      _FillRiskTelemetryFromEngine(risk_sym, t);
    }
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

    double      alpha_score;
    double      execution_score;
    double      risk_score;
    double      state_quality01;
    double      observability_confidence01;
    double      venue_coverage01;
    double      cross_venue_dislocation01;

    double      vpin01;
    double      vpin_limit01;
    double      resiliency01;
    double      resiliency_min01;

    double      impact_beta01;
    double      impact_beta_max01;
    double      impact_lambda01;
    double      impact_lambda_max01;

    double      darkpool01;
    double      darkpool_min01;
    double      darkpool_contradiction01;
    double      darkpool_contradiction_max01;

    double      sd_ob_invalidation_proximity01;
    double      sd_ob_invalidation_max01;

    double      liquidity_vacuum01;
    double      liquidity_vacuum_max01;
    double      liquidity_hunt01;
    double      liquidity_hunt_max01;

    bool        institutional_gate_pass;
    bool        institutional_delay_recommended;
    bool        institutional_derisk_recommended;

    double      observability_penalty01;

    bool        direct_micro_available;
    bool        proxy_micro_available;
    int         flow_mode;

    int         execution_posture_mode;
    bool        reduced_only;

    double      inst_ofi01;
    double      inst_obi01;
    double      inst_cvd01;

    double      inst_delta_proxy01;
    double      inst_footprint01;
    double      inst_profile01;
    double      inst_absorption01;
    double      inst_replenishment01;
    double      inst_vwap_location01;
    double      inst_liquidity_reject01;

    int         confluence_veto_mask;
    string      route_reason;
    string      veto_reason;

    string      tag;
    StratScore  ss;
    ConfluenceBreakdown bd;
    int         reason;
  };

  inline void ResetIntent(TradeIntent &ti)
  {
    ZeroMemory(ti);
    ti.ok=false; ti.symbol=""; ti.dir=DIR_BUY; ti.score=0.0; ti.risk_mult=1.0;
    ti.entry=0.0; ti.sl=0.0; ti.tp=0.0; ti.lots=0.0;

    ti.alpha_score=0.0; ti.execution_score=0.0; ti.risk_score=0.0; ti.state_quality01=0.0;
    ti.observability_confidence01 = (double)POLICIES_INST_DEFAULT_OBSERVABILITY01;
    ti.venue_coverage01           = (double)POLICIES_INST_DEFAULT_VENUE_COVERAGE01;
    ti.cross_venue_dislocation01  = (double)POLICIES_INST_DEFAULT_XVENUE_DISLOCATION01;

    ti.vpin01        = (double)POLICIES_INST_DEFAULT_VPIN01;
    ti.vpin_limit01  = 1.0;
    ti.resiliency01  = (double)POLICIES_INST_DEFAULT_RESILIENCY01;
    ti.resiliency_min01 = 0.0;

    ti.impact_beta01       = (double)POLICIES_INST_DEFAULT_IMPACT_BETA01;
    ti.impact_beta_max01   = (double)POLICIES_INST_MAX_IMPACT_BETA01;
    ti.impact_lambda01     = (double)POLICIES_INST_DEFAULT_IMPACT_LAMBDA01;
    ti.impact_lambda_max01 = (double)POLICIES_INST_MAX_IMPACT_LAMBDA01;

    ti.darkpool01                   = (double)POLICIES_INST_DEFAULT_DARKPOOL01;
    ti.darkpool_min01               = (double)POLICIES_INST_MIN_DARKPOOL01;
    ti.darkpool_contradiction01     = (double)POLICIES_INST_DEFAULT_DARKPOOL_CONTRADICTION01;
    ti.darkpool_contradiction_max01 = (double)POLICIES_INST_MAX_DARKPOOL_CONTRADICTION01;

    ti.sd_ob_invalidation_proximity01 = (double)POLICIES_INST_DEFAULT_SD_OB_INVALIDATION_PROXIMITY01;
    ti.sd_ob_invalidation_max01       = (double)POLICIES_INST_MAX_SD_OB_INVALIDATION_PROXIMITY01;

    ti.liquidity_vacuum01           = (double)POLICIES_INST_DEFAULT_LIQUIDITY_VACUUM01;
    ti.liquidity_vacuum_max01       = (double)POLICIES_INST_MAX_LIQUIDITY_VACUUM01;
    ti.liquidity_hunt01             = (double)POLICIES_INST_DEFAULT_LIQUIDITY_HUNT01;
    ti.liquidity_hunt_max01         = (double)POLICIES_INST_MAX_LIQUIDITY_HUNT01;

    ti.institutional_gate_pass=true;
    ti.institutional_delay_recommended=false;
    ti.institutional_derisk_recommended=false;

    ti.observability_penalty01 = Clamp01(1.0 - ti.observability_confidence01);

    ti.direct_micro_available = false;
    ti.proxy_micro_available  = false;
    ti.flow_mode              = POLICIES_INST_FLOW_MODE_PROXY;

    ti.execution_posture_mode = 0;
    ti.reduced_only           = false;

    ti.inst_ofi01             = 0.5;
    ti.inst_obi01             = 0.5;
    ti.inst_cvd01             = 0.5;

    ti.inst_delta_proxy01     = 0.5;
    ti.inst_footprint01       = 0.5;
    ti.inst_profile01         = 0.5;
    ti.inst_absorption01      = 0.5;
    ti.inst_replenishment01   = 0.5;
    ti.inst_vwap_location01   = 0.5;
    ti.inst_liquidity_reject01= 0.0;

    ti.confluence_veto_mask   = 0;
    ti.route_reason           = "";
    ti.veto_reason            = "none";

    ti.reason=GATE_OK;
  }

  inline void _FillIntentInstitutionalPolicy(TradeIntent &ti, const PolicyResult &r)
  {
    ti.alpha_score                     = r.alpha_score;
    ti.execution_score                 = r.execution_score;
    ti.risk_score                      = r.risk_score;
    ti.state_quality01                 = r.state_quality01;
    ti.observability_confidence01      = r.observability_confidence01;
    ti.observability_penalty01         = r.observability_penalty01;
    ti.venue_coverage01                = r.venue_coverage01;
    ti.cross_venue_dislocation01       = r.cross_venue_dislocation01;

    ti.vpin01                          = r.vpin01;
    ti.vpin_limit01                    = r.vpin_limit01;
    ti.resiliency01                    = r.resiliency01;
    ti.resiliency_min01                = r.resiliency_min01;

    ti.impact_beta01                   = r.impact_beta01;
    ti.impact_beta_max01               = r.impact_beta_max01;
    ti.impact_lambda01                 = r.impact_lambda01;
    ti.impact_lambda_max01             = r.impact_lambda_max01;

    ti.darkpool01                      = r.darkpool01;
    ti.darkpool_min01                  = r.darkpool_min01;
    ti.darkpool_contradiction01        = r.darkpool_contradiction01;
    ti.darkpool_contradiction_max01    = r.darkpool_contradiction_max01;

    ti.sd_ob_invalidation_proximity01  = r.sd_ob_invalidation_proximity01;
    ti.sd_ob_invalidation_max01        = r.sd_ob_invalidation_max01;

    ti.liquidity_vacuum01              = r.liquidity_vacuum01;
    ti.liquidity_vacuum_max01          = r.liquidity_vacuum_max01;
    ti.liquidity_hunt01                = r.liquidity_hunt01;
    ti.liquidity_hunt_max01            = r.liquidity_hunt_max01;

    ti.institutional_gate_pass         = r.institutional_gate_pass;
    ti.institutional_delay_recommended = r.institutional_delay_recommended;
    ti.institutional_derisk_recommended= r.institutional_derisk_recommended;

    ti.direct_micro_available          = r.direct_micro_available;
    ti.proxy_micro_available           = r.proxy_micro_available;
    ti.flow_mode                       = r.flow_mode;
    ti.execution_posture_mode          = r.execution_posture_mode;
    ti.reduced_only                    = r.reduced_only;

    ti.inst_ofi01                      = r.inst_ofi01;
    ti.inst_obi01                      = r.inst_obi01;
    ti.inst_cvd01                      = r.inst_cvd01;

    ti.inst_delta_proxy01              = r.inst_delta_proxy01;
    ti.inst_footprint01                = r.inst_footprint01;
    ti.inst_profile01                  = r.inst_profile01;
    ti.inst_absorption01               = r.inst_absorption01;
    ti.inst_replenishment01            = r.inst_replenishment01;
    ti.inst_vwap_location01            = r.inst_vwap_location01;
    ti.inst_liquidity_reject01         = r.inst_liquidity_reject01;

    ti.confluence_veto_mask            = r.confluence_veto_mask;
    ti.route_reason                    = r.route_reason;
    ti.veto_reason                     = r.veto_reason;
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

    StratScore SS = in_ss;
    ConfluenceBreakdown BD = in_bd;

    // Keep news / global policy overlays independent and first.
    bool skip=false;
    ApplyPolicyRiskOverlays(cfg, symbol, SS, BD, skip);
    if(skip)
    {
      gate_reason=GATE_NEWS;
      out_intent.reason=gate_reason;
      return false;
    }

    PolicyResult final_gate;
    _PolicyReset(final_gate);

    InstitutionalStatePolicyView inst_view;
    ResetInstitutionalStatePolicyView(inst_view);

    if(!EvaluateFinalSendGate(cfg, symbol, SS, final_gate, inst_view))
    {
//      out_intent.alpha_score                     = final_gate.alpha_score;
//      out_intent.execution_score                 = final_gate.execution_score;
//      out_intent.risk_score                      = final_gate.risk_score;
//      out_intent.state_quality01                 = final_gate.state_quality01;
//      out_intent.observability_confidence01      = final_gate.observability_confidence01;
//      out_intent.venue_coverage01                = final_gate.venue_coverage01;
//      out_intent.cross_venue_dislocation01       = final_gate.cross_venue_dislocation01;
//
//      out_intent.vpin01                          = final_gate.vpin01;
//      out_intent.vpin_limit01                    = final_gate.vpin_limit01;
//      out_intent.resiliency01                    = final_gate.resiliency01;
//      out_intent.resiliency_min01                = final_gate.resiliency_min01;
//
//      out_intent.impact_beta01                   = final_gate.impact_beta01;
//      out_intent.impact_beta_max01               = final_gate.impact_beta_max01;
//      out_intent.impact_lambda01                 = final_gate.impact_lambda01;
//      out_intent.impact_lambda_max01             = final_gate.impact_lambda_max01;
//
//      out_intent.darkpool01                      = final_gate.darkpool01;
//      out_intent.darkpool_min01                  = final_gate.darkpool_min01;
//      out_intent.darkpool_contradiction01        = final_gate.darkpool_contradiction01;
//      out_intent.darkpool_contradiction_max01    = final_gate.darkpool_contradiction_max01;
//
//      out_intent.sd_ob_invalidation_proximity01  = final_gate.sd_ob_invalidation_proximity01;
//      out_intent.sd_ob_invalidation_max01        = final_gate.sd_ob_invalidation_max01;
//
//      out_intent.liquidity_vacuum01              = final_gate.liquidity_vacuum01;
//      out_intent.liquidity_vacuum_max01          = final_gate.liquidity_vacuum_max01;
//      out_intent.liquidity_hunt01                = final_gate.liquidity_hunt01;
//      out_intent.liquidity_hunt_max01            = final_gate.liquidity_hunt_max01;
//
//      out_intent.institutional_gate_pass         = final_gate.institutional_gate_pass;
//      out_intent.institutional_delay_recommended = final_gate.institutional_delay_recommended;
//      out_intent.institutional_derisk_recommended= final_gate.institutional_derisk_recommended;

      _FillIntentInstitutionalPolicy(out_intent, final_gate);

      gate_reason       = final_gate.primary_reason;
      out_intent.reason = gate_reason;
      return false;
    }

    OrderPlan plan; ZeroMemory(plan);
    if(!Risk::ComputeOrderForSymbol(symbol, dir, cfg, SS, plan, BD))
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

    _FillIntentInstitutionalPolicy(out_intent, final_gate);
//    out_intent.alpha_score                     = final_gate.alpha_score;
//    out_intent.execution_score                 = final_gate.execution_score;
//    out_intent.risk_score                      = final_gate.risk_score;
//    out_intent.state_quality01                 = final_gate.state_quality01;
//    out_intent.observability_confidence01      = final_gate.observability_confidence01;
//    out_intent.venue_coverage01                = final_gate.venue_coverage01;
//    out_intent.cross_venue_dislocation01       = final_gate.cross_venue_dislocation01;
//
//    out_intent.vpin01                          = final_gate.vpin01;
//    out_intent.vpin_limit01                    = final_gate.vpin_limit01;
//    out_intent.resiliency01                    = final_gate.resiliency01;
//    out_intent.resiliency_min01                = final_gate.resiliency_min01;
//
//    out_intent.impact_beta01                   = final_gate.impact_beta01;
//    out_intent.impact_beta_max01               = final_gate.impact_beta_max01;
//    out_intent.impact_lambda01                 = final_gate.impact_lambda01;
//    out_intent.impact_lambda_max01             = final_gate.impact_lambda_max01;
//
//    out_intent.darkpool01                      = final_gate.darkpool01;
//    out_intent.darkpool_min01                  = final_gate.darkpool_min01;
//    out_intent.darkpool_contradiction01        = final_gate.darkpool_contradiction01;
//    out_intent.darkpool_contradiction_max01    = final_gate.darkpool_contradiction_max01;
//
//    out_intent.sd_ob_invalidation_proximity01  = final_gate.sd_ob_invalidation_proximity01;
//    out_intent.sd_ob_invalidation_max01        = final_gate.sd_ob_invalidation_max01;
//
//    out_intent.liquidity_vacuum01              = final_gate.liquidity_vacuum01;
//    out_intent.liquidity_vacuum_max01          = final_gate.liquidity_vacuum_max01;
//    out_intent.liquidity_hunt01                = final_gate.liquidity_hunt01;
//    out_intent.liquidity_hunt_max01            = final_gate.liquidity_hunt_max01;
//
//    out_intent.institutional_gate_pass         = final_gate.institutional_gate_pass;
//    out_intent.institutional_delay_recommended = final_gate.institutional_delay_recommended;
//    out_intent.institutional_derisk_recommended= final_gate.institutional_derisk_recommended;

    out_intent.ss        = SS;
    out_intent.bd        = BD;
    out_intent.tag       = MakeTag(symbol, (StringLen(strat_name)>0?strat_name:"strategy"), dir, SS.score);
    out_intent.reason    = GATE_OK;
    return true;
  }

  inline bool BuildTradeIntentFromIntegratedState(const Settings &cfg,
                                                  FinalStrategyIntegratedStateVector_t &io_state,
                                                  TradeIntent &out_intent,
                                                  int &gate_reason)
  {
     _EnsureLoaded(cfg);

     ResetIntent(out_intent);

     const string symbol =
        (StringLen(io_state.symbol) > 0 ? io_state.symbol :
         (StringLen(io_state.raw_bank.symbol) > 0 ? io_state.raw_bank.symbol : _Symbol));

     out_intent.symbol = symbol;

     PolicyResult final_gate;
     _PolicyReset(final_gate);

     if(!EvaluateFinalSendGateFromIntegratedState(cfg, io_state, final_gate))
     {
        _FillIntentInstitutionalPolicy(out_intent, final_gate);
        gate_reason       = final_gate.primary_reason;
        out_intent.reason = gate_reason;
        return false;
     }

     OrderPlan plan;
     ZeroMemory(plan);

     if(!Risk::ComputeFromIntegratedStateForSymbol(symbol, io_state, cfg, plan))
     {
        gate_reason       = GATE_CONFLICT;
        out_intent.reason = gate_reason;
        io_state.risk_pass = false;
        io_state.veto_tag = "risk_engine";
        io_state.veto_reason = Risk::LastRejectReason();
        return false;
     }

     const Direction dir = _IntegratedStateDir(io_state);

     out_intent.ok         = true;
     out_intent.dir        = dir;
     out_intent.strat_id   = (StrategyID)io_state.hypothesis.strategy_id;
     out_intent.strat_name = StringFormat("strategy_%d", io_state.hypothesis.strategy_id);
     out_intent.score      = Clamp01(io_state.route_rank > 0.0 ? io_state.route_rank : io_state.confidence_score);
     out_intent.risk_mult  = Clamp(1.0 - (0.50 * Clamp01(io_state.risk_score)), 0.25, 1.0);

     out_intent.entry      = plan.price;
     out_intent.sl         = plan.sl;
     out_intent.tp         = plan.tp;
     out_intent.lots       = plan.lots;

     _FillIntentInstitutionalPolicy(out_intent, final_gate);

     out_intent.tag        = MakeTag(symbol,
                                     out_intent.strat_name,
                                     dir,
                                     out_intent.score);
     out_intent.reason     = GATE_OK;

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

    // Final machine-readable pre-send gating is owned by BuildTradeIntentFromPick()
    // through EvaluateFinalSendGate(...).

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
