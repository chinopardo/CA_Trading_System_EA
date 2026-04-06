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
//  - BUILD_ENABLE_PROXY_MICRO_FALLBACK is OPTIONAL.
//  - BUILD_ALLOW_STRUCTURE_ONLY_MODE is OPTIONAL and only valid when
//    BUILD_ENABLE_PROXY_MICRO_FALLBACK is enabled.
//  - These two flags must be enabled here only (manual opt-in) or in
//    MetaEditor project settings, not auto-declared in Router/Risk/strategies.

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
   // If you want proxy-mode fallback, enable BUILD_ENABLE_PROXY_MICRO_FALLBACK
   // manually in section 1A above or in MetaEditor project settings.
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
// 3) Tester-only direct execution scheme (opt-in)
// -------------------------------------------------------------------
// These flags support StrategyDirectExecGuards.mqh.
//
// Meaning:
//  - STRAT_DIRECT_EXEC_TESTER_ONLY : Compiles direct-exec surfaces into strategies
//  - STRAT_DIRECT_EXEC_ALLOW       : Explicitly allows use (still runtime-gated to Tester/Opt)
//  - STRAT_DIRECT_EXEC_VERBOSE     : Prints standardized block reasons when denied
//
// Recommended workflow:
//  - For normal trading (even in tester): leave all OFF.
//  - For regression testing direct exec: turn ON both *_TESTER_ONLY and *_ALLOW.
//  - For noisy diagnostics: also enable *_VERBOSE.

#ifdef BUILD_PROFILE_TESTER

   // Compile the direct-exec code paths (still not usable unless ALLOW is defined).
   // Uncomment to compile direct execution helpers into strategy binaries:
   #define STRAT_DIRECT_EXEC_TESTER_ONLY

   // Explicitly allow execution of those helpers (still blocked unless in Tester/Optimization at runtime).
   // Uncomment ONLY when you intentionally want to run strategy direct-exec regression:
   #define STRAT_DIRECT_EXEC_ALLOW

   // Optional: prints standardized denial reasons
   #define STRAT_DIRECT_EXEC_VERBOSE

#else
   // Production: hard safety. If someone tries to enable these flags, block the build.
   #ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
      #error "STRAT_DIRECT_EXEC_TESTER_ONLY must not be enabled in PRODUCTION builds"
   #endif
   #ifdef STRAT_DIRECT_EXEC_ALLOW
      #error "STRAT_DIRECT_EXEC_ALLOW must not be enabled in PRODUCTION builds"
   #endif
   #ifdef STRAT_DIRECT_EXEC_VERBOSE
      #error "STRAT_DIRECT_EXEC_VERBOSE must not be enabled in PRODUCTION builds"
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

   string de = "OFF";
#ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
   de = "COMPILED";
#endif
#ifdef STRAT_DIRECT_EXEC_ALLOW
   if(de == "COMPILED") de = "COMPILED+ALLOWED";
   else de = "ALLOWED"; // shouldn't happen, but kept explicit
#endif

   Print(BUILD_TAG, " Strategy direct execution: ", de);

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
   Print(BUILD_TAG, " Fallback policy source: BUILD_ENABLE_PROXY_MICRO_FALLBACK / BUILD_ALLOW_STRUCTURE_ONLY_MODE are manual opt-in only");
   
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

// -------------------------------------------------------------------
// 5) Integration notes (for your codebase)
// -------------------------------------------------------------------
// Recommended include order:
//   - In CA_Trading_System_EA.mq5 (very top of includes):
//       #include "include/BuildFlags.mqh"
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
