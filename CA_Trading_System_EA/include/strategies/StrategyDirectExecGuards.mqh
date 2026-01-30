//+------------------------------------------------------------------+
//| StrategyDirectExecGuards.mqh                                      |
//| Production-ready standardized guard scheme for "direct execution" |
//|                                                                  |
//| Purpose:                                                         |
//|  - Ensure strategies NEVER place trades directly in live mode.    |
//|  - Allow direct execution ONLY for regression in Tester/Optimize, |
//|    and ONLY when explicitly enabled by build macros.              |
//|                                                                  |
//| Compile-time switches (set in BuildFlags.mqh or project defines): |
//|  - STRAT_DIRECT_EXEC_TESTER_ONLY  : compile direct-exec surfaces  |
//|  - STRAT_DIRECT_EXEC_ALLOW        : explicit opt-in to USE them   |
//|  - STRAT_DIRECT_EXEC_VERBOSE      : optional logging on blocks    |
//|                                                                  |
//| Notes:                                                           |
//|  - No #if used (MQL5-safe).                                       |
//|  - This header does not auto-include Execution.mqh. Each strategy |
//|    must still guard its own `#include "../Execution.mqh"` using   |
//|    the same macros (see usage below).                             |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_DIRECT_EXEC_GUARDS_MQH__
#define __STRATEGY_DIRECT_EXEC_GUARDS_MQH__

namespace StrategyDirectExec
{
   // ----------------------------------------------------------------
   // Compile-time feature flags (resolved via #ifdef; no #if used).
   // ----------------------------------------------------------------
   inline bool Compiled()
   {
   #ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
      return(true);
   #else
      return(false);
   #endif
   }

   inline bool Allowed()
   {
   #ifdef STRAT_DIRECT_EXEC_ALLOW
      return(true);
   #else
      return(false);
   #endif
   }

   // ----------------------------------------------------------------
   // Runtime environment gate (MQL5-native).
   // ----------------------------------------------------------------
   inline bool InTesterEnv()
   {
      const long is_tester = MQLInfoInteger(MQL_TESTER);
      const long is_opt    = MQLInfoInteger(MQL_OPTIMIZATION);
      return (is_tester != 0 || is_opt != 0);
   }

   // ----------------------------------------------------------------
   // Message helpers (standard phrasing across all strategies).
   // ----------------------------------------------------------------
   inline string Prefix(const string strategy_name)
   {
      if(strategy_name == "")
         return("DirectExec");
      return(strategy_name);
   }

   inline string Msg_NotCompiled(const string strategy_name)
   {
      return(Prefix(strategy_name) + " direct execution not compiled (define STRAT_DIRECT_EXEC_TESTER_ONLY)");
   }

   inline string Msg_NotAllowed(const string strategy_name)
   {
      return(Prefix(strategy_name) + " direct execution disabled (define STRAT_DIRECT_EXEC_ALLOW)");
   }

   inline string Msg_NotTester(const string strategy_name)
   {
      return(Prefix(strategy_name) + " direct execution blocked outside Strategy Tester/Optimization (Router owns live trading)");
   }

   // ----------------------------------------------------------------
   // Core gate: returns true only when direct execution is permitted.
   // Fills why_out with a standardized reason on failure.
   // ----------------------------------------------------------------
   inline bool CanRun(const string strategy_name, string &why_out)
   {
      why_out = "";

      if(!Compiled())
      {
         why_out = Msg_NotCompiled(strategy_name);
         return(false);
      }

      if(!Allowed())
      {
         why_out = Msg_NotAllowed(strategy_name);
         return(false);
      }

      if(!InTesterEnv())
      {
         why_out = Msg_NotTester(strategy_name);
         return(false);
      }

      return(true);
   }

   // ----------------------------------------------------------------
   // Optional logging hook (standardized).
   // ----------------------------------------------------------------
   inline void MaybeLogBlocked(const string &why)
   {
   #ifdef STRAT_DIRECT_EXEC_VERBOSE
      if(why != "")
         Print(why);
   #endif
   }

   // ----------------------------------------------------------------
   // Convenience: guard for functions that return bool and have whyOut.
   // Pattern:
   //    string why="";
   //    if(!StrategyDirectExec::GuardBool("ICT_PO3", why)) return(false);
   // ----------------------------------------------------------------
   inline bool GuardBool(const string strategy_name, string &why_out)
   {
      const bool ok = CanRun(strategy_name, why_out);
      if(!ok) MaybeLogBlocked(why_out);
      return(ok);
   }

   // ----------------------------------------------------------------
   // Convenience: guard for score structs without assuming struct type.
   // You pass references to the fields you want filled.
   //
   // Pattern (before any Exec::RequestEntry* call):
   //    if(!StrategyDirectExec::GuardScore("ICT_SilverBullet", finalQ,
   //                                      ss.score, ss.eligible, ss.reason))
   //       return(false);
   // ----------------------------------------------------------------
   inline bool GuardScore(const string strategy_name,
                          const double computed_score,
                          double &out_score,
                          bool   &out_eligible,
                          string &out_reason)
   {
      string why = "";
      if(CanRun(strategy_name, why))
         return(true);

      out_score    = computed_score;
      out_eligible = false;
      out_reason   = why;

      MaybeLogBlocked(why);
      return(false);
   }
} // namespace StrategyDirectExec

//+------------------------------------------------------------------+
//| Usage reference (copy/paste into each of the 5 strategy files)    |
//+------------------------------------------------------------------+
//
// 1) Guard the Execution include in EACH strategy file:
//
//    #ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
//    #ifdef STRAT_DIRECT_EXEC_ALLOW
//    #include "../Execution.mqh"
//    #endif
//    #endif
//
// 2) Guard direct execution blocks:
//
//    string why="";
//    if(!StrategyDirectExec::GuardBool("ICT_OBFVG_OTE", why))
//       return(false);
//
//    // OR when you have ss.score / ss.eligible / ss.reason + computed_score:
//
//    if(!StrategyDirectExec::GuardScore("ICT_Wyckoff_SpringUTAD", finalQ,
//                                       ss.score, ss.eligible, ss.reason))
//       return(false);
//
// 3) Direct execution should ONLY happen after the guard passes:
//    Exec::RequestEntryBuy(...)
//    Exec::RequestEntrySell(...)
//

#endif // __STRATEGY_DIRECT_EXEC_GUARDS_MQH__
