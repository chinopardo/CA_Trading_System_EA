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

// Do NOT define both.
#ifdef BUILD_PROFILE_TESTER
   #define BUILD_PROFILE_NAME "TESTER"
#else
   #define BUILD_PROFILE_NAME "PRODUCTION"
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

#endif // __BUILD_FLAGS_MQH__
