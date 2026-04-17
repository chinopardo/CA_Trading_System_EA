//+------------------------------------------------------------------+
//| BuildFlags.mqh                                                   |
//| Production-ready centralized build-time switches for the EA       |
//|                                                                  |
//| Goal: one place to control compile-time behavior safely.          |
//|                                                                  |
//| Key principles:                                                   |
//|  - Production defaults are SAFE (no direct execution in strategies)|
//|  - Tester-only features require explicit opt-in                   |
//|  - Uses #ifdef / #define / #error only (NO #if)                   |
//+------------------------------------------------------------------+
#ifndef __BUILD_FLAGS_MQH__
#define __BUILD_FLAGS_MQH__

// -------------------------------------------------------------------
// 1) Build profile selection
// -------------------------------------------------------------------
// Default live build is STRICT institutional unless you explicitly opt into
// TESTER or explicitly force classic production for staged migration.
//
// To enable tester profile:
//   Uncomment the next line OR define it in MetaEditor project settings.
   #define BUILD_PROFILE_TESTER
//
// Optional: force classic non-strict production during staged migration.
//   Uncomment the next line OR define it in MetaEditor project settings.
//#define BUILD_PROFILE_PRODUCTION_CLASSIC

// Do NOT define conflicting profiles.
#ifdef BUILD_PROFILE_TESTER
   #ifdef BUILD_PROFILE_PRODUCTION_CLASSIC
      #error "BUILD_PROFILE_TESTER and BUILD_PROFILE_PRODUCTION_CLASSIC must not both be enabled"
   #endif
#endif

#ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
   #ifdef BUILD_PROFILE_PRODUCTION_CLASSIC
      #error "BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL and BUILD_PROFILE_PRODUCTION_CLASSIC must not both be enabled"
   #endif
#endif

// Default non-tester live build = strict institutional.
#ifndef BUILD_PROFILE_TESTER
   #ifndef BUILD_PROFILE_PRODUCTION_CLASSIC
      #ifndef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
         #define BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
      #endif
   #endif
#endif

#ifdef BUILD_PROFILE_TESTER
   #define BUILD_PROFILE_NAME "TESTER"
#else
   #ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
      #define BUILD_PROFILE_NAME "PRODUCTION_STRICT_INSTITUTIONAL"
   #else
      #define BUILD_PROFILE_NAME "PRODUCTION_CLASSIC"
   #endif
#endif

#ifdef BUILD_PROFILE_TESTER
   #ifndef TESTER_BUILD
      #define TESTER_BUILD
   #endif
   #ifndef CONFLUENCE_TRANSPORT_IS_PRESENT
      #define CONFLUENCE_TRANSPORT_IS_PRESENT
   #endif

   #ifndef BUILD_REQUIRE_STATE_HEADS
      #define BUILD_REQUIRE_STATE_HEADS
   #endif

   #ifndef BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
      #define BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
   #endif

   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #define INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
   #endif

   #ifndef BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
      #define BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
   #endif

   #ifndef BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
      #define BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
   #endif

   #ifndef BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
      #define BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
   #endif

   #ifndef BUILD_ENABLE_PROXY_MICRO_FALLBACK
      #define BUILD_ENABLE_PROXY_MICRO_FALLBACK
   #endif
   #ifndef BUILD_ALLOW_STRUCTURE_ONLY_MODE
      #define BUILD_ALLOW_STRUCTURE_ONLY_MODE
   #endif
#endif

// -------------------------------------------------------------------
// 1A) Institutional ownership guards (manual opt-in / manual override)
// -------------------------------------------------------------------
// Normally you should prefer the strict production institutional bundle below.
// These individual switches remain available for staged migration or targeted testing.
//
//// Core ownership / state discipline
//#define BUILD_STRICT_CANONICAL_OFX_ONLY
//#define BUILD_REQUIRE_SINGLE_SCAN_OWNER
//#define BUILD_DISABLE_LEGACY_OFX_COMPAT
//#define BUILD_REQUIRE_STATE_HEADS
//#define BUILD_REQUIRE_CANONICAL_SESSION_RESETS
//#define ROUTER_SCAN_OWNER_IS_MSH
//
//// Confluence / Types ownership contract
//#define CONFLUENCE_TRANSPORT_IS_PRESENT
//#define BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER
//#define CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
//#define BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY
//#define TYPES_SNAPSHOT_IS_MIRROR_ONLY
//
// Institutional transport / fallback discipline
//#define BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
//#define INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
//#define BUILD_ENABLE_PROXY_MICRO_FALLBACK
//#define BUILD_ALLOW_STRUCTURE_ONLY_MODE
//#define BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
//#define BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
//#define BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
// Optional fallback policy note:
//  - In TESTER builds, BUILD_ENABLE_PROXY_MICRO_FALLBACK and
//    BUILD_ALLOW_STRUCTURE_ONLY_MODE are auto-enabled by section 1.
//  - In non-tester builds, both remain optional manual opt-ins.
//  - BUILD_ALLOW_STRUCTURE_ONLY_MODE is only valid when
//    BUILD_ENABLE_PROXY_MICRO_FALLBACK is enabled.
//  - These flags must still be declared here only, not ad hoc in
//    Router/Risk/strategies.

// -------------------------------------------------------------------
// 1A.1) Canonical strategy-pipeline migration flags
// -------------------------------------------------------------------
// Manual overrides for staged migration.
//
// Uncomment only when you intentionally want to force one route.
//
//#define BUILD_FORCE_LEGACY_CANDIDATE_PIPELINE
//#define BUILD_DISABLE_CANONICAL_HYPOTHESIS_PIPELINE
//
// Canonical pipeline feature flags are normally auto-derived from the
// selected build profile in section 1C below.

// -------------------------------------------------------------------
// 1B) Strict production institutional bundle
// -------------------------------------------------------------------
// This is the default live-trading ownership profile unless TESTER or
// explicit classic production is selected.
// It centralizes:
//   - canonical OFX-only discipline
//   - a single scan owner
//   - no legacy OFX compatibility path
//   - required state heads
//   - required canonical session resets
//   - Confluence transport as the canonical fusion path
//   - Confluence as the sole fusion owner
//   - Types snapshot as mirror/export-only when Confluence transport exists
//   - explicit owner macros declared here, not ad hoc elsewhere
#ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
   #ifndef BUILD_STRICT_CANONICAL_OFX_ONLY
      #define BUILD_STRICT_CANONICAL_OFX_ONLY
   #endif

   #ifndef BUILD_REQUIRE_SINGLE_SCAN_OWNER
      #define BUILD_REQUIRE_SINGLE_SCAN_OWNER
   #endif

   #ifndef BUILD_DISABLE_LEGACY_OFX_COMPAT
      #define BUILD_DISABLE_LEGACY_OFX_COMPAT
   #endif

   #ifndef BUILD_REQUIRE_STATE_HEADS
      #define BUILD_REQUIRE_STATE_HEADS
   #endif

   #ifndef BUILD_REQUIRE_CANONICAL_SESSION_RESETS
      #define BUILD_REQUIRE_CANONICAL_SESSION_RESETS
   #endif

   #ifndef CONFLUENCE_TRANSPORT_IS_PRESENT
      #define CONFLUENCE_TRANSPORT_IS_PRESENT
   #endif

   #ifndef BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER
      #define BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER
   #endif

   #ifndef CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
      #define CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
   #endif

   #ifndef BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY
      #define BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY
   #endif

   #ifndef TYPES_SNAPSHOT_IS_MIRROR_ONLY
      #define TYPES_SNAPSHOT_IS_MIRROR_ONLY
   #endif

   #ifndef BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
      #define BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
   #endif

   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #define INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
   #endif

   // Optional fallback policy is NOT auto-enabled by the strict institutional bundle.
   // TESTER builds may auto-enable fallback policy in section 1.
   // For strict production builds, if you want proxy-mode fallback, enable
   // BUILD_ENABLE_PROXY_MICRO_FALLBACK manually in section 1A above or in
   // MetaEditor project settings.
   // If you also want structure-only mode, enable BUILD_ALLOW_STRUCTURE_ONLY_MODE
   // explicitly as a second opt-in.

   #ifndef BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
      #define BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
   #endif

   #ifndef BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
      #define BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
   #endif

   #ifndef BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
      #define BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
   #endif

   #ifndef ROUTER_SCAN_OWNER_IS_MSH
      #define ROUTER_SCAN_OWNER_IS_MSH
   #endif
#endif

 // -------------------------------------------------------------------
 // 1C) Canonical strategy pipeline defaults
 // -------------------------------------------------------------------
 // Canonical new pipeline:
 //   raw bank
 //   -> category selection
 //   -> hypothesis bank
 //   -> final integrated state
 //   -> router / policies / risk / execution
 //
 // Legacy candidate router may remain compiled for migration / tester parity.

#ifndef BUILD_FORCE_LEGACY_CANDIDATE_PIPELINE
 #ifndef BUILD_DISABLE_CANONICAL_HYPOTHESIS_PIPELINE
    #ifdef BUILD_PROFILE_TESTER
       #ifndef BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE
          #define BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE
       #endif
       #ifndef BUILD_ENABLE_HYPOTHESIS_ROUTER
          #define BUILD_ENABLE_HYPOTHESIS_ROUTER
       #endif
       #ifndef BUILD_ENABLE_FINAL_INTEGRATED_STATE
          #define BUILD_ENABLE_FINAL_INTEGRATED_STATE
       #endif
       #ifndef BUILD_ENABLE_POSITIONMGMT_FROM_FINAL_STATE
          #define BUILD_ENABLE_POSITIONMGMT_FROM_FINAL_STATE
       #endif
       #ifndef BUILD_KEEP_LEGACY_CANDIDATE_ROUTER
          #define BUILD_KEEP_LEGACY_CANDIDATE_ROUTER
       #endif
    #else
       #ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
          #ifndef BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE
             #define BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE
          #endif
          #ifndef BUILD_ENABLE_HYPOTHESIS_ROUTER
             #define BUILD_ENABLE_HYPOTHESIS_ROUTER
          #endif
          #ifndef BUILD_ENABLE_FINAL_INTEGRATED_STATE
             #define BUILD_ENABLE_FINAL_INTEGRATED_STATE
          #endif
          #ifndef BUILD_ENABLE_POSITIONMGMT_FROM_FINAL_STATE
             #define BUILD_ENABLE_POSITIONMGMT_FROM_FINAL_STATE
          #endif
          #ifndef BUILD_KEEP_LEGACY_CANDIDATE_ROUTER
             #define BUILD_KEEP_LEGACY_CANDIDATE_ROUTER
          #endif
       #endif

       #ifdef BUILD_PROFILE_PRODUCTION_CLASSIC
          #ifndef BUILD_KEEP_LEGACY_CANDIDATE_ROUTER
             #define BUILD_KEEP_LEGACY_CANDIDATE_ROUTER
          #endif
       #endif
    #endif
 #endif
#endif

// -------------------------------------------------------------------
// 2) Safety-first defaults (Production posture)
// -------------------------------------------------------------------
// IMPORTANT:
// - In PRODUCTION, strategies must never call Exec::RequestEntry* directly.
// - Router must remain the single live execution owner.
//
// Therefore, by default we DO NOT define:
//   STRAT_DIRECT_EXEC_TESTER_ONLY
//   STRAT_DIRECT_EXEC_ALLOW
//   STRAT_DIRECT_EXEC_VERBOSE
//
// These are opt-in only (see section 3).

// Optional: keep log noise down by default.
#define BUILD_LOG_LEVEL_INFO     1
#define BUILD_LOG_LEVEL_DEBUG    0

// Optional: a single tag you can prepend in Print() to identify build.
#define BUILD_TAG "[CA_TS]"

// -------------------------------------------------------------------
// 3) Tester direct execution profile
// -------------------------------------------------------------------
// Runtime/config guards are the authority for whether direct execution may run.
// In tester builds we always expose the runtime-gated surface.
//
// IMPORTANT:
// - STRAT_DIRECT_EXEC_ALLOW is the profile-level "enabled for tester build" macro.
// - STRAT_DIRECT_EXEC_TESTER_ONLY is retained only as a legacy compatibility alias
//   for strategy files that still compile-gate direct-exec helper surfaces on it.
// - Actual use must still be blocked/allowed by runtime tester checks and config.
#ifdef BUILD_PROFILE_TESTER
   #ifndef STRATREG_HAS_BUILD_CANDIDATES
      #define STRATREG_HAS_BUILD_CANDIDATES
   #endif
   #ifndef BUILD_DIRECT_EXEC_RUNTIME_GATED
      #define BUILD_DIRECT_EXEC_RUNTIME_GATED
   #endif

   // Tester profile: always compile with direct-exec runtime permission available.
   #ifndef STRAT_DIRECT_EXEC_ALLOW
      #define STRAT_DIRECT_EXEC_ALLOW
   #endif

   // Legacy compatibility alias:
   // Keep this until all strategy files stop using STRAT_DIRECT_EXEC_TESTER_ONLY
   // as a compile-time include gate.
   #ifndef STRAT_DIRECT_EXEC_TESTER_ONLY
      #define STRAT_DIRECT_EXEC_TESTER_ONLY
   #endif

   // Optional diagnostics remain enabled in tester profile.
   #ifndef STRAT_DIRECT_EXEC_VERBOSE
      #define STRAT_DIRECT_EXEC_VERBOSE
   #endif
#else
   // Production: hard safety. If someone tries to enable these flags, block the build.
   #ifdef BUILD_DIRECT_EXEC_RUNTIME_GATED
      #error "BUILD_DIRECT_EXEC_RUNTIME_GATED must not be enabled in PRODUCTION builds"
   #endif
   #ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
      #error "STRAT_DIRECT_EXEC_TESTER_ONLY must not be enabled in PRODUCTION builds"
   #endif
   #ifdef STRAT_DIRECT_EXEC_ALLOW
      #error "STRAT_DIRECT_EXEC_ALLOW must not be enabled in PRODUCTION builds"
   #endif
   #ifdef STRAT_DIRECT_EXEC_VERBOSE
      #error "STRAT_DIRECT_EXEC_VERBOSE must not be enabled in PRODUCTION builds"
   #endif
   #ifdef TESTER_BUILD
      #error "TESTER_BUILD must not be enabled in PRODUCTION builds"
   #endif
   #ifdef STRATREG_HAS_BUILD_CANDIDATES
      #error "STRATREG_HAS_BUILD_CANDIDATES must not be enabled in PRODUCTION builds"
   #endif
#endif

#ifdef BUILD_FORCE_LEGACY_CANDIDATE_PIPELINE
 #ifdef BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE
    #error "BUILD_FORCE_LEGACY_CANDIDATE_PIPELINE conflicts with BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE"
 #endif
 #ifdef BUILD_ENABLE_HYPOTHESIS_ROUTER
    #error "BUILD_FORCE_LEGACY_CANDIDATE_PIPELINE conflicts with BUILD_ENABLE_HYPOTHESIS_ROUTER"
 #endif
 #ifdef BUILD_ENABLE_FINAL_INTEGRATED_STATE
    #error "BUILD_FORCE_LEGACY_CANDIDATE_PIPELINE conflicts with BUILD_ENABLE_FINAL_INTEGRATED_STATE"
 #endif
#endif

#ifdef BUILD_ENABLE_HYPOTHESIS_ROUTER
 #ifndef BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE
    #error "BUILD_ENABLE_HYPOTHESIS_ROUTER requires BUILD_ENABLE_CANONICAL_STRATEGY_PIPELINE"
 #endif
 #ifndef BUILD_ENABLE_FINAL_INTEGRATED_STATE
    #error "BUILD_ENABLE_HYPOTHESIS_ROUTER requires BUILD_ENABLE_FINAL_INTEGRATED_STATE"
 #endif
#endif

#ifdef BUILD_ENABLE_POSITIONMGMT_FROM_FINAL_STATE
 #ifndef BUILD_ENABLE_FINAL_INTEGRATED_STATE
    #error "BUILD_ENABLE_POSITIONMGMT_FROM_FINAL_STATE requires BUILD_ENABLE_FINAL_INTEGRATED_STATE"
 #endif
#endif

// -------------------------------------------------------------------
// 3A) Compile-time ownership invariants
// -------------------------------------------------------------------
#ifdef BUILD_REQUIRE_SINGLE_SCAN_OWNER
   #ifndef ROUTER_SCAN_OWNER_IS_MSH
      #error "BUILD_REQUIRE_SINGLE_SCAN_OWNER requires ROUTER_SCAN_OWNER_IS_MSH"
   #endif
#endif

#ifdef CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
   #ifndef CONFLUENCE_TRANSPORT_IS_PRESENT
      #error "CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE requires CONFLUENCE_TRANSPORT_IS_PRESENT"
   #endif
#endif

#ifdef BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER
   #ifndef CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
      #error "BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER requires CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE"
   #endif
#endif

#ifdef BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY
   #ifdef CONFLUENCE_TRANSPORT_IS_PRESENT
      #ifndef TYPES_SNAPSHOT_IS_MIRROR_ONLY
         #error "BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY requires TYPES_SNAPSHOT_IS_MIRROR_ONLY when CONFLUENCE_TRANSPORT_IS_PRESENT is enabled"
      #endif
   #endif
#endif

#ifdef BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #error "BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT requires INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT"
   #endif
#endif

#ifdef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
   #ifndef CONFLUENCE_TRANSPORT_IS_PRESENT
      #error "INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT requires CONFLUENCE_TRANSPORT_IS_PRESENT"
   #endif
#endif

#ifdef BUILD_ENABLE_PROXY_MICRO_FALLBACK
   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #error "BUILD_ENABLE_PROXY_MICRO_FALLBACK requires INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT"
   #endif
   #ifndef BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
      #error "BUILD_ENABLE_PROXY_MICRO_FALLBACK requires BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE"
   #endif
   #ifndef BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
      #error "BUILD_ENABLE_PROXY_MICRO_FALLBACK requires BUILD_ENABLE_RISK_OBSERVABILITY_SIZING"
   #endif
   #ifndef BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
      #error "BUILD_ENABLE_PROXY_MICRO_FALLBACK requires BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS"
   #endif
#endif

#ifdef BUILD_ALLOW_STRUCTURE_ONLY_MODE
   #ifndef BUILD_ENABLE_PROXY_MICRO_FALLBACK
      #error "BUILD_ALLOW_STRUCTURE_ONLY_MODE requires BUILD_ENABLE_PROXY_MICRO_FALLBACK"
   #endif
#endif

#ifdef BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #error "BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE requires INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT"
   #endif
#endif

#ifdef BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #error "BUILD_ENABLE_RISK_OBSERVABILITY_SIZING requires INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT"
   #endif
#endif

#ifdef BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
   #ifndef BUILD_REQUIRE_STATE_HEADS
      #error "BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS requires BUILD_REQUIRE_STATE_HEADS"
   #endif
   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #error "BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS requires INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT"
   #endif
#endif

#ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
   #ifndef BUILD_STRICT_CANONICAL_OFX_ONLY
      #error "Strict production institutional bundle requires BUILD_STRICT_CANONICAL_OFX_ONLY"
   #endif

   #ifndef BUILD_REQUIRE_SINGLE_SCAN_OWNER
      #error "Strict production institutional bundle requires BUILD_REQUIRE_SINGLE_SCAN_OWNER"
   #endif

   #ifndef BUILD_DISABLE_LEGACY_OFX_COMPAT
      #error "Strict production institutional bundle requires BUILD_DISABLE_LEGACY_OFX_COMPAT"
   #endif

   #ifndef BUILD_REQUIRE_STATE_HEADS
      #error "Strict production institutional bundle requires BUILD_REQUIRE_STATE_HEADS"
   #endif

   #ifndef BUILD_REQUIRE_CANONICAL_SESSION_RESETS
      #error "Strict production institutional bundle requires BUILD_REQUIRE_CANONICAL_SESSION_RESETS"
   #endif

   #ifndef CONFLUENCE_TRANSPORT_IS_PRESENT
      #error "Strict production institutional bundle requires CONFLUENCE_TRANSPORT_IS_PRESENT"
   #endif

   #ifndef BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER
      #error "Strict production institutional bundle requires BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER"
   #endif

   #ifndef CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
      #error "Strict production institutional bundle requires CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE"
   #endif

   #ifndef BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY
      #error "Strict production institutional bundle requires BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY"
   #endif

   #ifndef TYPES_SNAPSHOT_IS_MIRROR_ONLY
      #error "Strict production institutional bundle requires TYPES_SNAPSHOT_IS_MIRROR_ONLY"
   #endif

   #ifndef ROUTER_SCAN_OWNER_IS_MSH
      #error "Strict production institutional bundle requires ROUTER_SCAN_OWNER_IS_MSH"
   #endif
   
   #ifndef BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
      #error "Strict production institutional bundle requires BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT"
   #endif

   #ifndef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
      #error "Strict production institutional bundle requires INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT"
   #endif

   // Optional fallback policy is not part of the mandatory strict institutional core.
   // If desired, enable BUILD_ENABLE_PROXY_MICRO_FALLBACK and optionally
   // BUILD_ALLOW_STRUCTURE_ONLY_MODE manually in section 1A or project settings.

   #ifndef BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
      #error "Strict production institutional bundle requires BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE"
   #endif

   #ifndef BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
      #error "Strict production institutional bundle requires BUILD_ENABLE_RISK_OBSERVABILITY_SIZING"
   #endif

   #ifndef BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
      #error "Strict production institutional bundle requires BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS"
   #endif
#endif

// -------------------------------------------------------------------
// 4) Optional helper: runtime print of build switches
// -------------------------------------------------------------------
// Safe to call from OnInit() if you want a quick sanity check.
inline void BuildFlags_PrintSummary()
{
   Print(BUILD_TAG, " Build profile: ", BUILD_PROFILE_NAME);

   string de_allow = "OFF";
#ifdef STRAT_DIRECT_EXEC_ALLOW
   de_allow = "ON";
#endif
   Print(BUILD_TAG, " Strategy direct execution allow macro: ", de_allow);

   string de_runtime = "STANDARD";
#ifdef BUILD_DIRECT_EXEC_RUNTIME_GATED
   de_runtime = "CONFIG+TESTER_RUNTIME";
#endif
   Print(BUILD_TAG, " Strategy direct execution authority: ", de_runtime);

#ifdef TESTER_BUILD
   Print(BUILD_TAG, " TESTER_BUILD=ON");
#else
   Print(BUILD_TAG, " TESTER_BUILD=OFF");
#endif

#ifdef STRATREG_HAS_BUILD_CANDIDATES
   Print(BUILD_TAG, " STRATREG_HAS_BUILD_CANDIDATES=ON");
#else
   Print(BUILD_TAG, " STRATREG_HAS_BUILD_CANDIDATES=OFF");
#endif

   string de_compat = "OFF";
#ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
   de_compat = "LEGACY_COMPAT_ON";
#endif
   Print(BUILD_TAG, " Strategy direct execution legacy compile alias: ", de_compat);

#ifdef STRAT_DIRECT_EXEC_VERBOSE
   Print(BUILD_TAG, " Direct exec verbose: ON");
#else
   Print(BUILD_TAG, " Direct exec verbose: OFF");
#endif

   string strict_inst = "OFF";
#ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
   strict_inst = "ON";
#endif
   Print(BUILD_TAG, " Strict institutional bundle: ", strict_inst);

   string canonical_ofx = "OFF";
#ifdef BUILD_STRICT_CANONICAL_OFX_ONLY
   canonical_ofx = "ON";
#endif
   Print(BUILD_TAG, " Canonical OFX only: ", canonical_ofx);

   string scan_owner = "FLEXIBLE";
#ifdef ROUTER_SCAN_OWNER_IS_MSH
   scan_owner = "MSH";
#endif
#ifdef BUILD_REQUIRE_SINGLE_SCAN_OWNER
   if(scan_owner == "MSH")
      scan_owner = "SINGLE=MSH";
   else
      scan_owner = "SINGLE_REQUIRED";
#endif
   Print(BUILD_TAG, " Scan owner discipline: ", scan_owner);

   string legacy_ofx = "ENABLED";
#ifdef BUILD_DISABLE_LEGACY_OFX_COMPAT
   legacy_ofx = "DISABLED";
#endif
   Print(BUILD_TAG, " Legacy OFX compat: ", legacy_ofx);

   string state_heads = "OPTIONAL";
#ifdef BUILD_REQUIRE_STATE_HEADS
   state_heads = "REQUIRED";
#endif
   Print(BUILD_TAG, " State heads: ", state_heads);

   string session_resets = "OPTIONAL";
#ifdef BUILD_REQUIRE_CANONICAL_SESSION_RESETS
   session_resets = "REQUIRED";
#endif
   Print(BUILD_TAG, " Canonical session resets: ", session_resets);

   string confluence_transport = "OFF";
#ifdef CONFLUENCE_TRANSPORT_IS_PRESENT
   confluence_transport = "ON";
#endif
   Print(BUILD_TAG, " Confluence transport present: ", confluence_transport);

   string fusion_owner = "FLEXIBLE";
#ifdef CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE
   fusion_owner = "CONFLUENCE";
#endif
#ifdef BUILD_REQUIRE_CONFLUENCE_SOLE_FUSION_OWNER
   if(fusion_owner == "CONFLUENCE")
      fusion_owner = "SOLE=CONFLUENCE";
   else
      fusion_owner = "SOLE_REQUIRED";
#endif
   Print(BUILD_TAG, " Fusion owner discipline: ", fusion_owner);

   string snapshot_policy = "FLEXIBLE";
#ifdef TYPES_SNAPSHOT_IS_MIRROR_ONLY
   snapshot_policy = "MIRROR_ONLY";
#endif
#ifdef BUILD_REQUIRE_TYPES_SNAPSHOT_MIRROR_ONLY
   if(snapshot_policy == "MIRROR_ONLY")
      snapshot_policy = "MIRROR_ONLY_REQUIRED";
   else
      snapshot_policy = "MIRROR_ONLY_REQUIRED_IF_TRANSPORT";
#endif
   Print(BUILD_TAG, " Types snapshot policy: ", snapshot_policy);

   string inst_bundle_transport = "OFF";
#ifdef INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
   inst_bundle_transport = "ON";
#endif
#ifdef BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
   if(inst_bundle_transport == "ON")
      inst_bundle_transport = "ON_REQUIRED";
   else
      inst_bundle_transport = "REQUIRED";
#endif
   Print(BUILD_TAG, " Institutional bundle transport: ", inst_bundle_transport);

   string proxy_fallback = "OFF";
#ifdef BUILD_ENABLE_PROXY_MICRO_FALLBACK
   proxy_fallback = "ON";
#endif
   Print(BUILD_TAG, " Proxy micro fallback: ", proxy_fallback);

   string structure_only = "OFF";
#ifdef BUILD_ALLOW_STRUCTURE_ONLY_MODE
   structure_only = "ON";
#endif

   Print(BUILD_TAG, " Structure-only mode: ", structure_only);
#ifdef BUILD_PROFILE_TESTER
   Print(BUILD_TAG, " Tester fallback posture: proxy micro fallback + structure-only mode auto-enabled");
#else
   Print(BUILD_TAG, " Tester fallback posture: n/a");
#endif
   Print(BUILD_TAG, " Fallback policy source: TESTER=auto-enable, non-tester=manual opt-in");
   
   string router_observability = "OFF";
#ifdef BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
   router_observability = "ON";
#endif
   Print(BUILD_TAG, " Router observability compare: ", router_observability);

   string risk_observability = "OFF";
#ifdef BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
   risk_observability = "ON";
#endif
   Print(BUILD_TAG, " Risk observability sizing: ", risk_observability);

   string exec_from_heads = "OFF";
#ifdef BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
   exec_from_heads = "ON";
#endif
   Print(BUILD_TAG, " Execution posture from heads: ", exec_from_heads);

   Print(BUILD_TAG, " Log level INFO=", (string)BUILD_LOG_LEVEL_INFO,
                 " DEBUG=", (string)BUILD_LOG_LEVEL_DEBUG);
}

inline void BuildFlags_PrintRuntimeOverrides(const double router_min_score,
                                             const bool tester_degraded_active,
                                             const bool news_gate_enabled,
                                             const bool regime_gate_enabled,
                                             const bool liquidity_gate_enabled,
                                             const bool tester_policy_bypass_active)
{
   Print(BUILD_TAG, " Runtime router min score: ", DoubleToString(router_min_score, 3));
   Print(BUILD_TAG, " Runtime tester degraded active: ", (tester_degraded_active ? "ON" : "OFF"));
   Print(BUILD_TAG, " Runtime tester policy bypass: ", (tester_policy_bypass_active ? "ON" : "OFF"));
   Print(BUILD_TAG, " Runtime policy gates: news=", (news_gate_enabled ? "ON" : "OFF"),
                 " regime=", (regime_gate_enabled ? "ON" : "OFF"),
                 " liquidity=", (liquidity_gate_enabled ? "ON" : "OFF"));
}

// -------------------------------------------------------------------
// 5) Integration notes (for your codebase)
// -------------------------------------------------------------------
// Recommended include order / usage:
//
//   - In CA_Trading_System_EA.mq5 (very top of includes):
//       #include "include/BuildFlags.mqh"
//
//   - In OnInit(), after Settings S is finalized:
//       BuildFlags_PrintSummary();
//       BuildFlags_PrintRuntimeOverrides(Config::CfgRouterMinScore(S),
//                                        Config::CfgTesterDegradedModeActive(S),
//                                        Config::CfgNewsBlockEnabled(S),
//                                        Config::CfgRegimeGateEnabled(S),
//                                        Config::CfgLiquidityGateEnabled(S),
//                                        (IsTesterRuntime() && InpTester_BypassPolicyGates));
//
//   - In each of the 5 strategy files (near the top, before StrategyDirectExecGuards):
//       #include "../BuildFlags.mqh"   // adjust relative path to match your folder structure
//       #include "StrategyDirectExecGuards.mqh"
//
// This ensures all macros are consistent across compilation units.

// Institutional ownership note:
//   - Define ROUTER_SCAN_OWNER_IS_MSH, CONFLUENCE_TRANSPORT_IS_PRESENT,
//     CONFLUENCE_FUSION_OWNER_IS_CONFLUENCE, and TYPES_SNAPSHOT_IS_MIRROR_ONLY
//     here only, not ad hoc in downstream files.
//   - Downstream modules should consume BUILD_* and *_IS_* ownership flags,
//     not re-declare policy locally.
//   - Institutional transport / fallback policy must be declared here only:
//       BUILD_REQUIRE_INSTITUTIONAL_BUNDLE_TRANSPORT
//       INSTITUTIONAL_BUNDLE_TRANSPORT_IS_PRESENT
//       BUILD_ENABLE_ROUTER_OBSERVABILITY_COMPARE
//       BUILD_ENABLE_RISK_OBSERVABILITY_SIZING
//       BUILD_REQUIRE_EXECUTION_POSTURE_FROM_HEADS
//   - Optional fallback flags are manual opt-in here only:
//       BUILD_ENABLE_PROXY_MICRO_FALLBACK
//       BUILD_ALLOW_STRUCTURE_ONLY_MODE
//   - Do not auto-enable fallback policy in Router.mqh, RiskEngine.mqh,
//     strategies, or EA orchestration code.
//   - BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL is now the default
//     live-trading posture unless BUILD_PROFILE_TESTER or
//     BUILD_PROFILE_PRODUCTION_CLASSIC is explicitly selected.
#endif // __BUILD_FLAGS_MQH__
