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
// 1) Build profile selection (optional)
// -------------------------------------------------------------------
// Default is PRODUCTION unless you explicitly define BUILD_PROFILE_TESTER.
//
// To enable tester profile:
//   Uncomment the next line OR define it in MetaEditor project settings.
//#define BUILD_PROFILE_TESTER
// Optional: strict production institutional bundle.
// Keeps production posture, but hardens ownership boundaries and compile-time discipline.
// Uncomment the next line OR define it in MetaEditor project settings.
//#define BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL

// Do NOT define both.
#ifdef BUILD_PROFILE_TESTER
   #ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
      #error "BUILD_PROFILE_TESTER and BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL must not both be enabled"
   #endif
#endif

#ifdef BUILD_PROFILE_TESTER
   #define BUILD_PROFILE_NAME "TESTER"
#else
   #ifdef BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL
      #define BUILD_PROFILE_NAME "PRODUCTION_STRICT_INSTITUTIONAL"
   #else
      #define BUILD_PROFILE_NAME "PRODUCTION"
   #endif
#endif

// -------------------------------------------------------------------
// 1A) Institutional ownership guards (manual opt-in)
// -------------------------------------------------------------------
// Normally you should prefer the strict production institutional bundle below.
// These individual switches remain available for staged migration or targeted testing.
//
//#define BUILD_STRICT_CANONICAL_OFX_ONLY
//#define BUILD_REQUIRE_SINGLE_SCAN_OWNER
//#define BUILD_DISABLE_LEGACY_OFX_COMPAT
//#define BUILD_REQUIRE_STATE_HEADS
//#define BUILD_REQUIRE_CANONICAL_SESSION_RESETS
//#define ROUTER_SCAN_OWNER_IS_MSH

// -------------------------------------------------------------------
// 1B) Strict production institutional bundle
// -------------------------------------------------------------------
// This is the preferred live-trading ownership profile.
// It centralizes:
//   - canonical OFX-only discipline
//   - a single scan owner
//   - no legacy OFX compatibility path
//   - required state heads
//   - required canonical session resets
//   - explicit scan-owner macro ownership here, not ad hoc elsewhere
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
   //#define STRAT_DIRECT_EXEC_TESTER_ONLY

   // Explicitly allow execution of those helpers (still blocked unless in Tester/Optimization at runtime).
   // Uncomment ONLY when you intentionally want to run strategy direct-exec regression:
   //#define STRAT_DIRECT_EXEC_ALLOW

   // Optional: prints standardized denial reasons
   //#define STRAT_DIRECT_EXEC_VERBOSE

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

   #ifndef ROUTER_SCAN_OWNER_IS_MSH
      #error "Strict production institutional bundle requires ROUTER_SCAN_OWNER_IS_MSH"
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
//   - Define ROUTER_SCAN_OWNER_IS_MSH here only, not ad hoc in downstream files.
//   - Downstream modules should consume BUILD_* ownership flags, not re-declare policy.
//   - BUILD_PROFILE_STRICT_PRODUCTION_INSTITUTIONAL is the preferred live-trading posture
//     when you want compile-time enforcement of canonical ownership boundaries.
#endif // __BUILD_FLAGS_MQH__
