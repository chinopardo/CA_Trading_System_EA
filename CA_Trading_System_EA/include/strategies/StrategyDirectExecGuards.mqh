//+------------------------------------------------------------------+
//| StrategyDirectExecGuards.mqh                                      |
//| Production-ready standardized guard scheme for "direct execution" |
//|                                                                  |
//| Purpose:                                                         |
//|  - Ensure strategies NEVER place trades directly in live mode.    |
//|  - Allow direct execution ONLY for regression in Tester/Optimize, |
//|    and ONLY when explicitly enabled by build macros.              |
//|  - Enforce veto-tag and alpha/execution/risk head gating before   |
//|    any direct execution surface is allowed to continue.           |
//|                                                                  |
//| Compile-time switches (normally set in BuildFlags.mqh or project  |
//| defines; tester builds may auto-bridge them in this header):      |
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

#ifdef BUILD_PROFILE_TESTER
   #ifndef STRAT_DIRECT_EXEC_TESTER_ONLY
      #define STRAT_DIRECT_EXEC_TESTER_ONLY
   #endif

   #ifndef STRAT_DIRECT_EXEC_ALLOW
      #define STRAT_DIRECT_EXEC_ALLOW
   #endif
#endif

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

   inline double Clamp01x(const double v)
   {
      if(!MathIsValidNumber(v))
         return(0.0);
      if(v < 0.0)
         return(0.0);
      if(v > 1.0)
         return(1.0);
      return(v);
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

   static bool s_tester_bypass = false;

   inline void SetTesterBypass(const bool on)
   {
      s_tester_bypass = on;
   }

   inline bool TesterBypassActive()
   {
      if(!s_tester_bypass)
         return(false);

      return InTesterEnv();
   }

   inline bool ConfigTesterDirectExecActive(const Settings &cfg)
   {
      if(InTesterEnv())
         return(true);

      if(Config::CfgTesterDegradedModeActive(cfg))
         return(true);

      return(false);
   }

   inline void SyncTesterBypassFromConfig(const Settings &cfg)
   {
      SetTesterBypass(ConfigTesterDirectExecActive(cfg));
   }

   inline bool ConfigTesterOverrideActive(const Settings &cfg)
   {
      if(ConfigTesterDirectExecActive(cfg))
         return(true);

      return(false);
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

   inline string Msg_TesterBypass(const string strategy_name)
   {
      return(Prefix(strategy_name) + " direct execution tester bypass active");
   }

   inline string Msg_TesterOverride(const string strategy_name)
   {
      return(Prefix(strategy_name) + " direct execution forced by tester degraded config override");
   }

   inline string Msg_TaggedVeto(const string strategy_name,
                                const string veto_tag,
                                const string veto_detail)
   {
      string msg = Prefix(strategy_name) + " direct execution blocked by veto";
      if(veto_tag != "")
         msg += " [" + veto_tag + "]";
      if(veto_detail != "")
         msg += " " + veto_detail;
      return(msg);
   }

   inline string Msg_HeadFail(const string strategy_name,
                              const string why_in)
   {
      if(why_in == "")
         return(Prefix(strategy_name) + " direct execution blocked by head thresholds");
      return(Prefix(strategy_name) + " direct execution blocked by head thresholds (" + why_in + ")");
   }

   // ----------------------------------------------------------------
   // Core gate: returns true only when direct execution is permitted.
   // Fills why_out with a standardized reason on failure.
   // ----------------------------------------------------------------
   inline bool CanRun(const string strategy_name, string &why_out)
   {
      why_out = "";

      if(TesterBypassActive())
      {
         why_out = Msg_TesterBypass(strategy_name);
         return(true);
      }

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

   inline bool CanRun(const string strategy_name, const Settings &cfg, string &why_out)
   {
      why_out = "";

      SyncTesterBypassFromConfig(cfg);

      if(ConfigTesterOverrideActive(cfg))
      {
         if(Config::CfgTesterDegradedModeActive(cfg))
            why_out = Msg_TesterOverride(strategy_name);
         else
            why_out = Msg_TesterBypass(strategy_name);

         return(true);
      }

      return(CanRun(strategy_name, why_out));
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

   inline bool GuardBool(const string strategy_name, const Settings &cfg, string &why_out)
   {
      const bool ok = CanRun(strategy_name, cfg, why_out);
      if(!ok)
         MaybeLogBlocked(why_out);
      return(ok);
   }

   // ----------------------------------------------------------------
   // Preferred guard: full strategy structs. This is the canonical
   // direct-exec gate after strategy evaluation has already populated
   // score + heads + veto metadata.
   // ----------------------------------------------------------------
   inline bool GuardStratScore(const string strategy_name,
                               const Settings &cfg,
                               StratScore &ss,
                               ConfluenceBreakdown &bd,
                               string &why_out)
   {
      why_out = "";

      if(!CanRun(strategy_name, cfg, why_out))
      {
         if(ss.veto_tag == "")
            ss.veto_tag = "direct_exec_env_block";
         if(ss.veto_detail == "")
            ss.veto_detail = why_out;

         ss.eligible = false;
         ss.reason   = why_out;

         bd.veto = true;
         bd.meta = why_out;
         StratCopyHeadMetaToBreakdown(ss, bd);

         MaybeLogBlocked(why_out);
         return(false);
      }

      string why_gate = "";
      if(!StratEligibilityPass(cfg, ss, why_gate))
      {
         if(ss.veto_tag != "")
            why_out = Msg_TaggedVeto(strategy_name, ss.veto_tag, ss.veto_detail);
         else
            why_out = Msg_HeadFail(strategy_name, why_gate);

         if(ss.veto_tag == "")
            ss.veto_tag = "direct_exec_head_gate";
         if(ss.veto_detail == "")
            ss.veto_detail = why_gate;

         ss.eligible = false;
         ss.reason   = why_out;

         bd.veto = true;
         bd.meta = why_out;
         StratCopyHeadMetaToBreakdown(ss, bd);

         MaybeLogBlocked(why_out);
         return(false);
      }

      bd.veto = false;

      if(why_out == Msg_TesterOverride(strategy_name) || why_out == Msg_TesterBypass(strategy_name))
         bd.meta = why_out;
      else
         bd.meta = "";

      if(ss.reason == "" && why_out != "")
         ss.reason = why_out;

      StratCopyHeadMetaToBreakdown(ss, bd);
      return(true);
   }

   // ----------------------------------------------------------------
   // Generic field-based guard for callers that do not pass a full
   // StratScore struct but still need head-aware blocking.
   // ----------------------------------------------------------------
   inline bool GuardScoreEx(const string strategy_name,
                            const double computed_score,
                            const double computed_alpha_score,
                            const double computed_execution_score,
                            const double computed_risk_score,
                            const string computed_archetype_label,
                            const string current_veto_tag,
                            const string current_veto_detail,
                            const double alpha_min,
                            const double exec_min,
                            const double risk_max,
                            double &out_score,
                            double &out_alpha_score,
                            double &out_execution_score,
                            double &out_risk_score,
                            bool   &out_eligible,
                            string &out_reason,
                            string &out_veto_tag,
                            string &out_veto_detail,
                            string &out_archetype_label)
   {
      const double score01 = Clamp01x(computed_score);
      const double alpha01 = Clamp01x(MathIsValidNumber(computed_alpha_score) ? computed_alpha_score : score01);
      const double exec01  = Clamp01x(MathIsValidNumber(computed_execution_score) ? computed_execution_score : score01);
      const double risk01  = Clamp01x(MathIsValidNumber(computed_risk_score) ? computed_risk_score : (1.0 - score01));

      string why = "";
      if(!CanRun(strategy_name, why))
      {
         out_score           = score01;
         out_alpha_score     = alpha01;
         out_execution_score = exec01;
         out_risk_score      = risk01;
         out_eligible        = false;
         out_reason          = why;
         out_veto_tag        = "direct_exec_env_block";
         out_veto_detail     = why;
         out_archetype_label = computed_archetype_label;

         MaybeLogBlocked(why);
         return(false);
      }

      if(current_veto_tag != "")
      {
         why = Msg_TaggedVeto(strategy_name, current_veto_tag, current_veto_detail);

         out_score           = score01;
         out_alpha_score     = alpha01;
         out_execution_score = exec01;
         out_risk_score      = risk01;
         out_eligible        = false;
         out_reason          = why;
         out_veto_tag        = current_veto_tag;
         out_veto_detail     = (current_veto_detail != "" ? current_veto_detail : why);
         out_archetype_label = computed_archetype_label;

         MaybeLogBlocked(why);
         return(false);
      }

      const double alphaMin = Clamp01x(alpha_min);
      const double execMin  = Clamp01x(exec_min);
      const double riskMax  = Clamp01x(risk_max);

      if(alpha01 < alphaMin || exec01 < execMin || risk01 > riskMax)
      {
         string why_head = "";

         if(alpha01 < alphaMin)
            why_head = StringFormat("alpha %.2f < %.2f", alpha01, alphaMin);
         else if(exec01 < execMin)
            why_head = StringFormat("exec %.2f < %.2f", exec01, execMin);
         else
            why_head = StringFormat("risk %.2f > %.2f", risk01, riskMax);

         why = Msg_HeadFail(strategy_name, why_head);

         out_score           = score01;
         out_alpha_score     = alpha01;
         out_execution_score = exec01;
         out_risk_score      = risk01;
         out_eligible        = false;
         out_reason          = why;
         out_veto_tag        = "direct_exec_head_gate";
         out_veto_detail     = why_head;
         out_archetype_label = computed_archetype_label;

         MaybeLogBlocked(why);
         return(false);
      }

      return(true);
   }

   // ----------------------------------------------------------------
   // Legacy fallback: environment-only guard. Prefer GuardStratScore()
   // or GuardScoreEx() for head-aware direct execution checks.
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
// 0) Optional tester runtime bypass from EA/main file:
//
//    // In the main EA file (not in this header):
//    // input bool InpAllowDirectExec = true;
//
//    // Then during init / setup:
//    // StrategyDirectExec::SetTesterBypass(InpAllowDirectExec);
//
//    // Or, better, when cfg is available:
//    // StrategyDirectExec::SetTesterBypass(CfgTesterDegradedModeActive(cfg));
//
//    // This bypass is tester-only at runtime and does not weaken live mode.
//
// 1) Guard the Execution include in EACH strategy file:
//
//    // Preferred source of truth remains BuildFlags.mqh.
//    // In tester builds, this header also provides a defensive macro bridge.
//
//    #ifdef STRAT_DIRECT_EXEC_TESTER_ONLY
//    #ifdef STRAT_DIRECT_EXEC_ALLOW
//    #include "../Execution.mqh"
//    #endif
//    #endif
//
// 2) Guard direct execution blocks:
//
//
//    // Preferred when you already have full strategy structs:
//    string why = "";
//    if(!StrategyDirectExec::GuardStratScore("StrategyMain", cfg, ss, bd, why))
//       return(false);
//
//    // Or field-based when you want head-aware direct-exec gating
//    // without passing the full structs:
//
//    if(!StrategyDirectExec::GuardScoreEx("ICT_Wyckoff_SpringUTAD",
//                                         ss.score,
//                                         ss.alpha_score,
//                                         ss.execution_score,
//                                         ss.risk_score,
//                                         ss.archetype_label,
//                                         ss.veto_tag,
//                                         ss.veto_detail,
//                                         cfg.main_alpha_min,
//                                         cfg.main_exec_min,
//                                         cfg.main_risk_max,
//                                         ss.score,
//                                         ss.alpha_score,
//                                         ss.execution_score,
//                                         ss.risk_score,
//                                         ss.eligible,
//                                         ss.reason,
//                                         ss.veto_tag,
//                                         ss.veto_detail,
//                                         ss.archetype_label))
//       return(false);
//
//    // Legacy env-only fallback:
//
//    if(!StrategyDirectExec::GuardScore("ICT_Wyckoff_SpringUTAD",
//                                       finalQ,
//                                       ss.score,
//                                       ss.eligible,
//                                       ss.reason))
//       return(false);
// 3) Direct execution should ONLY happen after the guard passes:
//    Exec::RequestEntryBuy(...)
//    Exec::RequestEntrySell(...)
//

#endif // __STRATEGY_DIRECT_EXEC_GUARDS_MQH__
