#ifndef CA_TRADING_SYSTEM_TESTERSETTINGS_MQH
#define CA_TRADING_SYSTEM_TESTERSETTINGS_MQH

#include "Config.mqh"

namespace TesterSettings
{
   // --------------------------------------------------------------------------
   // Preset enum
   // If you later move this enum into Config.mqh, define
   // TESTERSETTINGS_ENUM_DEFINED before including this file.
   // --------------------------------------------------------------------------
   #ifndef TESTERSETTINGS_ENUM_DEFINED
      #define TESTERSETTINGS_ENUM_DEFINED 1
      enum ENUM_TESTER_SETTINGS_PRESET
      {
         TESTER_PRESET_OFF = 0,
         TESTER_PRESET_RELAXED = 1,
         TESTER_PRESET_DEBUG = 2,
         TESTER_PRESET_SMOKE = 3
      };
   #endif

   // --------------------------------------------------------------------------
   // Internal report state
   // --------------------------------------------------------------------------
   struct ApplyReport
   {
      bool   applied;
      bool   score_relaxation;
      bool   news_session_bypass;
      bool   micro_relaxation;
      bool   diagnostics_enabled;
      bool   ergonomics_relaxed;
      bool   validation_ok;

      int    preset;
      string reason;
      string validation_error;
   };

   static ApplyReport g_last_report;
   static bool        g_audit_emitted = false;

   // --------------------------------------------------------------------------
   // Small helpers
   // --------------------------------------------------------------------------
   inline string BoolStr(const bool v)
   {
      return (v ? "true" : "false");
   }

   inline void ResetReport(ApplyReport &r)
   {
      r.applied              = false;
      r.score_relaxation     = false;
      r.news_session_bypass  = false;
      r.micro_relaxation     = false;
      r.diagnostics_enabled  = false;
      r.ergonomics_relaxed   = false;
      r.validation_ok        = true;
      r.preset               = TESTER_PRESET_OFF;
      r.reason               = "";
      r.validation_error     = "";
   }

   inline bool IsTesterContext()
   {
      if(MQLInfoInteger(MQL_TESTER) != 0)       return true;
      if(MQLInfoInteger(MQL_OPTIMIZATION) != 0) return true;
      if(MQLInfoInteger(MQL_VISUAL_MODE) != 0)  return true;
      return false;
   }

   inline bool IsOptimizationContext()
   {
      return (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
   }

   inline bool IsVisualContext()
   {
      return (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
   }

   inline string ActivePresetName(const int preset)
   {
      if(preset == TESTER_PRESET_RELAXED) return "RELAXED";
      if(preset == TESTER_PRESET_DEBUG)   return "DEBUG";
      if(preset == TESTER_PRESET_SMOKE)   return "SMOKE";
      return "OFF";
   }

   inline int ActivePreset(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_PRESET
         return (int)cfg.tester_settings_preset;
      #else
         return TESTER_PRESET_OFF;
      #endif
   }

   inline bool MasterEnabled(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE
         return (cfg.tester_settings_enable ? true : false);
      #else
         return false;
      #endif
   }

   inline bool ApplyOnlyInTester(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_APPLY_ONLY_IN_TESTER
         return (cfg.tester_settings_apply_only_in_tester ? true : false);
      #else
         return true;
      #endif
   }

   inline bool LogAuditEnabled(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_LOG_AUDIT
         return (cfg.tester_settings_log_audit ? true : false);
      #else
         return true;
      #endif
   }

   inline bool EnableVerboseDiagnosticsRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE_VERBOSE_DIAGNOSTICS
         return (cfg.tester_settings_enable_verbose_diagnostics ? true : false);
      #else
         return false;
      #endif
   }

   inline bool ZeroAllMinScoresRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_ZERO_ALL_MIN_SCORES
         return (cfg.tester_settings_zero_all_min_scores ? true : false);
      #else
         return true;
      #endif
   }

   inline bool DisableNewsRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_NEWS
         return (cfg.tester_settings_disable_news ? true : false);
      #else
         return true;
      #endif
   }

   inline bool DisableKillzonesRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_KILLZONES
         return (cfg.tester_settings_disable_killzones ? true : false);
      #else
         return true;
      #endif
   }

   inline bool DisableSessionFilterRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_SESSION_FILTER
         return (cfg.tester_settings_disable_session_filter ? true : false);
      #else
         return true;
      #endif
   }

   inline bool DisableCorrelationRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_CORRELATION
         return (cfg.tester_settings_disable_correlation ? true : false);
      #else
         return true;
      #endif
   }

   inline bool ReduceMicroThresholdsRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_REDUCE_MICRO_THRESHOLDS
         return (cfg.tester_settings_reduce_micro_thresholds ? true : false);
      #else
         return true;
      #endif
   }

   inline bool AllowUnavailableInstitutionalRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_ALLOW_UNAVAILABLE_INSTITUTIONAL
         return (cfg.tester_settings_allow_unavailable_institutional ? true : false);
      #else
         return true;
      #endif
   }

   inline bool EnableDegradedFallbackRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE_DEGRADED_FALLBACK
         return (cfg.tester_settings_enable_degraded_fallback ? true : false);
      #else
         return true;
      #endif
   }

   inline bool BlockIfUnavailableRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_BLOCK_IF_UNAVAILABLE
         return (cfg.tester_settings_block_if_unavailable ? true : false);
      #else
         return false;
      #endif
   }

   inline bool ReduceCooldownsRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_REDUCE_COOLDOWNS
         return (cfg.tester_settings_reduce_cooldowns ? true : false);
      #else
         return false;
      #endif
   }

   inline bool PresetWantsScoreRelaxation(const int preset)
   {
      return (preset == TESTER_PRESET_RELAXED ||
              preset == TESTER_PRESET_DEBUG   ||
              preset == TESTER_PRESET_SMOKE);
   }

   inline bool PresetWantsNewsSessionBypass(const int preset)
   {
      return (preset == TESTER_PRESET_RELAXED ||
              preset == TESTER_PRESET_DEBUG   ||
              preset == TESTER_PRESET_SMOKE);
   }

   inline bool PresetWantsMicroRelaxation(const int preset)
   {
      return (preset == TESTER_PRESET_RELAXED ||
              preset == TESTER_PRESET_DEBUG   ||
              preset == TESTER_PRESET_SMOKE);
   }

   inline bool PresetWantsDiagnostics(const int preset)
   {
      return (preset == TESTER_PRESET_DEBUG ||
              preset == TESTER_PRESET_SMOKE);
   }

   inline bool PresetWantsErgonomics(const int preset)
   {
      return (preset == TESTER_PRESET_SMOKE);
   }

   inline bool ShouldApply(const Settings &cfg)
   {
      if(!MasterEnabled(cfg))
         return false;

      if(ApplyOnlyInTester(cfg) && !IsTesterContext())
         return false;

      if(ActivePreset(cfg) == TESTER_PRESET_OFF)
         return false;

      return true;
   }

   // --------------------------------------------------------------------------
   // Score overrides
   // Zero all effective runtime floors that suppress candidate construction.
   // Add more guarded fields here as your config surface grows.
   // --------------------------------------------------------------------------
   inline void ApplyScoreRelaxation(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);
      if(!PresetWantsScoreRelaxation(preset))
         return;

      if(!ZeroAllMinScoresRequested(cfg))
         return;

      #ifdef CFG_HAS_ROUTER_MIN_SCORE
         cfg.router_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
         cfg.router_fallback_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_ROUTER_FB_MIN
         cfg.router_fb_min = 0.0;
      #endif

      #ifdef CFG_HAS_ROUTER_TESTER_MIN_SCORE_OVERRIDE
         cfg.router_tester_min_score_override = 0.0;
      #endif

      #ifdef CFG_HAS_EXTRA_MIN_SCORE
         cfg.extra_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_EXTRA_MIN_GATE_SCORE
         cfg.extra_min_gate_score = 0.0;
      #endif

      #ifdef CFG_HAS_STRATEGY_MIN_SCORE_DEFAULT
         cfg.strategy_min_score_default = 0.0;
      #endif

      #ifdef CFG_HAS_CHECKLIST_MIN_SCORE
         cfg.checklist_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_DEBUG_CHECKLIST_MIN_SCORE
         cfg.debug_checklist_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_PROFILE_MIN_SCORE
         cfg.profile_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_MAIN_MIN_SCORE
         cfg.main_min_score = 0.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_ALPHA_MIN
         cfg.main_tester_alpha_min = 0.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_EXEC_MIN
         cfg.main_tester_exec_min = 0.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_RISK_MAX
         cfg.main_tester_risk_max = 1.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_LOOSE_GATE
         cfg.main_tester_loose_gate = true;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_SOFTEN_SELECTED_HARD_GATES
         cfg.main_tester_soften_selected_hard_gates = true;
      #endif

      r.score_relaxation = true;
   }

   // --------------------------------------------------------------------------
   // News / session / kill-zone / correlation bypass
   // This must happen on the effective runtime config, not raw inputs.
   // --------------------------------------------------------------------------
   inline void ApplyNewsAndSessionBypass(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);
      if(!PresetWantsNewsSessionBypass(preset))
         return;

      if(DisableNewsRequested(cfg))
      {
         cfg.news_on = false;
         cfg.newsFilterEnabled = false;
         cfg.scan_news_enable = false;

         #ifdef CFG_HAS_EXTRA_NEWS
            cfg.extra_news = false;
         #endif

         #ifdef CFG_HAS_MAIN_NEWS_HARD_VETO
            cfg.main_news_hard_veto = false;
         #endif

         #ifdef CFG_HAS_POLICY_ENABLE_NEWS_BLOCK
            cfg.enable_news_block = false;
         #endif

         #ifdef CFG_HAS_NEWS_BACKEND
            cfg.news_backend_mode = 0;
            cfg.news_mvp_no_block = true;
         #endif

         #ifdef CFG_HAS_W_NEWS
            cfg.w_news = 0.0;
         #endif
      }

      if(DisableKillzonesRequested(cfg))
      {
         #ifdef CFG_HAS_MODE_ENFORCE_KILLZONE
            cfg.mode_enforce_killzone = false;
         #endif

         #ifdef CFG_HAS_TESTER_ENFORCE_KILLZONE
            cfg.tester_enforce_killzone = false;
         #endif

         #ifdef CFG_HAS_KILLZONE_MODE
            cfg.killzone_mode = 0;
         #endif
      }

      if(DisableSessionFilterRequested(cfg))
      {
         #ifdef CFG_HAS_SESSION_FILTER
            cfg.session_filter = false;
         #endif

         #ifdef CFG_HAS_ENABLE_SESSION_FILTER
            cfg.enable_session_filter = false;
         #endif

         #ifdef CFG_HAS_POLICY_ENABLE_REGIME_GATE
            cfg.enable_regime_gate = false;
         #endif

         #ifdef CFG_HAS_POLICY_ENABLE_LIQUIDITY_GATE
            cfg.enable_liquidity_gate = false;
         #endif
      }

      if(DisableCorrelationRequested(cfg))
      {
         cfg.corr_softveto_enable = false;

         #ifdef CFG_HAS_CORR_VETO
            cfg.corr_veto_on = false;
         #endif

         #ifdef CFG_HAS_EXTRA_CORR
            cfg.extra_correlation = false;
         #endif

         #ifdef CFG_HAS_W_CORR
            cfg.w_correlation = 0.0;
         #endif

         #ifdef CFG_HAS_TESTER_DISABLE_NEWS_CORR
            cfg.tester_disable_news_and_correlation = true;
         #endif
      }

      r.news_session_bypass = true;
   }

   // --------------------------------------------------------------------------
   // Microstructure relaxation
   // Keep this threshold-only. No micro logic belongs here.
   // --------------------------------------------------------------------------
   inline void ApplyMicroRelaxation(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);
      if(!PresetWantsMicroRelaxation(preset))
         return;

      if(!ReduceMicroThresholdsRequested(cfg))
         return;

      #ifdef CFG_HAS_MS_OFI_ABS_MIN
         cfg.ms_ofi_abs_min = 0.0;
      #endif

      #ifdef CFG_HAS_MS_OBI_ABS_MIN
         cfg.ms_obi_abs_min = 0.0;
      #endif

      #ifdef CFG_HAS_MS_VPIN_THRESHOLD
         cfg.ms_vpin_threshold = 0.95;
      #endif

      #ifdef CFG_HAS_MS_RESIL_THRESHOLD
         cfg.ms_resil_threshold = 0.0;
      #endif

      #ifdef CFG_HAS_MS_MAX_IMPACT_BETA01
         cfg.ms_max_impact_beta01 = 1.0;
      #endif

      #ifdef CFG_HAS_MS_MAX_IMPACT_LAMBDA01
         cfg.ms_max_impact_lambda01 = 1.0;
      #endif

      #ifdef CFG_HAS_MS_ABSORPTION_MIN01
         cfg.ms_absorption_min01 = 0.0;
      #endif

      #ifdef CFG_HAS_MS_MIN_OBSERVABILITY01
         cfg.ms_min_observability01 = 0.0;
      #endif

      #ifdef CFG_HAS_MS_MIN_DARKPOOL01
         cfg.ms_min_darkpool01 = 0.0;
      #endif

      #ifdef CFG_HAS_MS_MIN_TRUTH_TIER01
         cfg.ms_min_truth_tier01 = 0.0;
      #endif

      #ifdef CFG_HAS_MS_MIN_VENUE_SCOPE01
         cfg.ms_min_venue_scope01 = 0.0;
      #endif

      #ifdef CFG_HAS_MS_MAX_TOXICITY01
         cfg.ms_max_toxicity01 = 0.95;
      #endif

      #ifdef CFG_HAS_MS_MAX_OBSERVABILITY_PENALTY01
         cfg.ms_max_observability_penalty01 = 1.0;
      #endif

      if(AllowUnavailableInstitutionalRequested(cfg))
      {
         #ifdef CFG_HAS_MS_BLOCK_IF_UNAVAILABLE
            cfg.ms_block_if_unavailable = false;
         #endif

         #ifdef CFG_HAS_MS_TESTER_ALLOW_UNAVAILABLE
            cfg.ms_tester_allow_unavailable = true;
         #endif

         #ifdef CFG_HAS_MS_TESTER_LOG_UNAVAILABLE
            cfg.ms_tester_log_unavailable = true;
         #endif

         #ifdef CFG_HAS_TESTER_DISABLE_MICRO_WEIGHTING
            cfg.tester_disable_micro_weighting = false;
         #endif

         #ifdef CFG_HAS_TESTER_MICRO_WEIGHT_SCALE
            cfg.tester_micro_weight_scale = 0.5;
         #endif
      }

      if(EnableDegradedFallbackRequested(cfg))
      {
         #ifdef CFG_HAS_MS_LIVE_ALLOW_DEGRADED_INST_FALLBACK
            cfg.ms_live_allow_degraded_inst_fallback = true;
         #endif

         #ifdef CFG_HAS_MS_TESTER_DEGRADED_SCORE_POLICY_ENABLE
            cfg.ms_tester_degraded_score_policy_enable = true;
         #endif

         #ifdef CFG_HAS_TESTER_DISABLE_MICRO_WEIGHTING
            cfg.tester_disable_micro_weighting = false;
         #endif

         #ifdef CFG_HAS_TESTER_MICRO_WEIGHT_SCALE
            if(cfg.tester_micro_weight_scale <= 0.0)
               cfg.tester_micro_weight_scale = 0.5;
         #endif
      }

      if(BlockIfUnavailableRequested(cfg))
      {
         #ifdef CFG_HAS_MS_BLOCK_IF_UNAVAILABLE
            cfg.ms_block_if_unavailable = true;
         #endif

         #ifdef CFG_HAS_MS_TESTER_ALLOW_UNAVAILABLE
            cfg.ms_tester_allow_unavailable = false;
         #endif
      }

      r.micro_relaxation = true;
   }

   // --------------------------------------------------------------------------
   // Diagnostics
   // --------------------------------------------------------------------------
   inline void ApplyDiagnostics(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);
      if(!PresetWantsDiagnostics(preset) && !EnableVerboseDiagnosticsRequested(cfg))
         return;

      cfg.debug = true;

      #ifdef CFG_HAS_ROUTER_DEBUG
         cfg.router_debug_log = true;
      #endif

      #ifdef CFG_HAS_ICT_SCORE_DEBUG_LOG
         cfg.ict_score_debug_log = true;
      #endif

      #ifdef CFG_HAS_CANDIDATE_TRACE_DEBUG
         cfg.candidate_trace_debug = true;
      #endif

      #ifdef CFG_HAS_LOG_VETO_DETAILS
         cfg.log_veto_details = true;
      #endif

      r.diagnostics_enabled = true;
   }

   // --------------------------------------------------------------------------
   // Optional tester ergonomics for SMOKE mode
   // Keep this strictly to convenience knobs, not safety rail bypass.
   // --------------------------------------------------------------------------
   inline void ApplyErgonomics(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);
      if(!PresetWantsErgonomics(preset))
         return;

      if(!ReduceCooldownsRequested(cfg))
         return;

      #ifdef CFG_HAS_TESTER_THROTTLE_SEC
         cfg.tester_throttle_sec = 60;
      #endif

      #ifdef CFG_HAS_EXEC_COOLDOWN_SEC
         if(cfg.exec_cooldown_sec > 60)
            cfg.exec_cooldown_sec = 60;
      #endif

      #ifdef CFG_HAS_ROUTER_MAX_STRATS
         if(cfg.router_max_strats <= 0 || cfg.router_max_strats > 5)
            cfg.router_max_strats = 5;
      #endif

      r.ergonomics_relaxed = true;
   }

   // --------------------------------------------------------------------------
   // Validation
   // --------------------------------------------------------------------------
   inline bool ValidateAppliedConfig(const Settings &cfg, string &err)
   {
      err = "";

      const int preset = ActivePreset(cfg);
      if(preset == TESTER_PRESET_OFF)
         return true;

      if(PresetWantsScoreRelaxation(preset) && ZeroAllMinScoresRequested(cfg))
      {
         #ifdef CFG_HAS_ROUTER_MIN_SCORE
            if(cfg.router_min_score > 0.0)
               err += "router_min_score still above zero; ";
         #endif

         #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
            if(cfg.router_fallback_min_score > 0.0)
               err += "router_fallback_min_score still above zero; ";
         #endif

         #ifdef CFG_HAS_ROUTER_FB_MIN
            if(cfg.router_fb_min > 0.0)
               err += "router_fb_min still above zero; ";
         #endif
      }

      if(PresetWantsNewsSessionBypass(preset))
      {
         if(DisableNewsRequested(cfg))
         {
            if(cfg.news_on) err += "news_on still true; ";
            if(cfg.newsFilterEnabled) err += "newsFilterEnabled still true; ";
         }

         if(DisableCorrelationRequested(cfg))
         {
            if(cfg.corr_softveto_enable) err += "corr_softveto_enable still true; ";
         }

         #ifdef CFG_HAS_MODE_ENFORCE_KILLZONE
            if(DisableKillzonesRequested(cfg) && cfg.mode_enforce_killzone)
               err += "mode_enforce_killzone still true; ";
         #endif
      }

      if(PresetWantsMicroRelaxation(preset))
      {
         #ifdef CFG_HAS_MS_BLOCK_IF_UNAVAILABLE
            #ifdef CFG_HAS_MS_TESTER_ALLOW_UNAVAILABLE
               if(cfg.ms_block_if_unavailable && cfg.ms_tester_allow_unavailable)
                  err += "ms unavailable policy incoherent; ";
            #endif
         #endif

         #ifdef CFG_HAS_MS_VPIN_THRESHOLD
            if(cfg.ms_vpin_threshold < 0.0 || cfg.ms_vpin_threshold > 1.0)
               err += "ms_vpin_threshold out of range; ";
         #endif

         #ifdef CFG_HAS_MS_RESIL_THRESHOLD
            if(cfg.ms_resil_threshold < 0.0 || cfg.ms_resil_threshold > 1.0)
               err += "ms_resil_threshold out of range; ";
         #endif

         #ifdef CFG_HAS_MS_MAX_IMPACT_BETA01
            if(cfg.ms_max_impact_beta01 < 0.0 || cfg.ms_max_impact_beta01 > 1.0)
               err += "ms_max_impact_beta01 out of range; ";
         #endif

         #ifdef CFG_HAS_MS_MAX_IMPACT_LAMBDA01
            if(cfg.ms_max_impact_lambda01 < 0.0 || cfg.ms_max_impact_lambda01 > 1.0)
               err += "ms_max_impact_lambda01 out of range; ";
         #endif
      }

      return (StringLen(err) == 0);
   }

   // --------------------------------------------------------------------------
   // Audit summary helpers
   // --------------------------------------------------------------------------
   inline string BuildScoreAudit(const Settings &cfg)
   {
      string s = "scores{";

      #ifdef CFG_HAS_ROUTER_MIN_SCORE
         s += StringFormat("router=%.2f", cfg.router_min_score);
      #else
         s += "router=n/a";
      #endif

      #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
         s += StringFormat(" fallback=%.2f", cfg.router_fallback_min_score);
      #endif

      #ifdef CFG_HAS_EXTRA_MIN_SCORE
         s += StringFormat(" extra=%.2f", cfg.extra_min_score);
      #endif

      #ifdef CFG_HAS_EXTRA_MIN_GATE_SCORE
         s += StringFormat(" gate=%.2f", cfg.extra_min_gate_score);
      #endif

      s += "}";
      return s;
   }

   inline string BuildGateAudit(const Settings &cfg)
   {
      string s = "gates{";

      s += StringFormat("news=%s", (cfg.news_on ? "on" : "off"));

      #ifdef CFG_HAS_MODE_ENFORCE_KILLZONE
         s += StringFormat(" killzone=%s", (cfg.mode_enforce_killzone ? "on" : "off"));
      #else
         s += " killzone=n/a";
      #endif

      #ifdef CFG_HAS_SESSION_FILTER
         s += StringFormat(" session=%s", (cfg.session_filter ? "on" : "off"));
      #else
         s += " session=n/a";
      #endif

      s += StringFormat(" corr=%s", (cfg.corr_softveto_enable ? "on" : "off"));
      s += "}";

      return s;
   }

   inline string BuildMicroAudit(const Settings &cfg)
   {
      string s = "micro{";

      #ifdef CFG_HAS_MS_OFI_ABS_MIN
         s += StringFormat("ofi=%.2f ", cfg.ms_ofi_abs_min);
      #endif

      #ifdef CFG_HAS_MS_OBI_ABS_MIN
         s += StringFormat("obi=%.2f ", cfg.ms_obi_abs_min);
      #endif

      #ifdef CFG_HAS_MS_VPIN_THRESHOLD
         s += StringFormat("vpin<=%.2f ", cfg.ms_vpin_threshold);
      #endif

      #ifdef CFG_HAS_MS_RESIL_THRESHOLD
         s += StringFormat("resil>=%.2f ", cfg.ms_resil_threshold);
      #endif

      #ifdef CFG_HAS_MS_BLOCK_IF_UNAVAILABLE
         #ifdef CFG_HAS_MS_TESTER_ALLOW_UNAVAILABLE
            s += StringFormat("unavailable=%s ",
                              (cfg.ms_block_if_unavailable ? "block"
                                                           : (cfg.ms_tester_allow_unavailable ? "allow" : "neutral")));
         #endif
      #endif

      #ifdef CFG_HAS_MS_MAX_IMPACT_BETA01
         s += StringFormat("beta<=%.2f ", cfg.ms_max_impact_beta01);
      #endif

      #ifdef CFG_HAS_MS_MAX_IMPACT_LAMBDA01
         s += StringFormat("lambda<=%.2f ", cfg.ms_max_impact_lambda01);
      #endif

      #ifdef CFG_HAS_MS_ABSORPTION_MIN01
         s += StringFormat("abs>=%.2f ", cfg.ms_absorption_min01);
      #endif

      #ifdef CFG_HAS_MS_MIN_OBSERVABILITY01
         s += StringFormat("obs>=%.2f ", cfg.ms_min_observability01);
      #endif

      s += "}";

      return s;
   }

   inline void EmitAudit(const Settings &cfg)
   {
      if(!LogAuditEnabled(cfg))
         return;

      if(!g_last_report.applied)
         return;

      if(g_audit_emitted)
         return;

      PrintFormat("[TesterSettings] applied preset=%s tester=%s opt=%s visual=%s",
                  ActivePresetName(g_last_report.preset),
                  BoolStr(IsTesterContext()),
                  BoolStr(IsOptimizationContext()),
                  BoolStr(IsVisualContext()));

      Print("[TesterSettings] ",
            BuildScoreAudit(cfg), " ",
            BuildGateAudit(cfg), " ",
            BuildMicroAudit(cfg));

      if(!g_last_report.validation_ok)
      {
         PrintFormat("[TesterSettings][ERR] invalid effective override state: %s",
                     g_last_report.validation_error);
      }

      g_audit_emitted = true;
   }

   inline void EmitSkipAudit(const Settings &cfg, const string reason)
   {
      if(!LogAuditEnabled(cfg))
         return;

      PrintFormat("[TesterSettings] skipped reason=%s", reason);
   }

   // --------------------------------------------------------------------------
   // Public entrypoint
   // Apply AFTER profile/router resolution, BEFORE final runtime boot.
   // Idempotent by assignment.
   // --------------------------------------------------------------------------
   inline bool ApplyToConfig(Settings &cfg)
   {
      ResetReport(g_last_report);
      g_audit_emitted = false;

      g_last_report.preset = ActivePreset(cfg);

      if(!MasterEnabled(cfg))
      {
         g_last_report.reason = "master_disabled";
         EmitSkipAudit(cfg, g_last_report.reason);
         return false;
      }

      if(ApplyOnlyInTester(cfg) && !IsTesterContext())
      {
         g_last_report.reason = "not_tester_context";
         EmitSkipAudit(cfg, g_last_report.reason);
         return false;
      }

      if(g_last_report.preset == TESTER_PRESET_OFF)
      {
         g_last_report.reason = "preset_off";
         EmitSkipAudit(cfg, g_last_report.reason);
         return false;
      }

      ApplyScoreRelaxation(cfg, g_last_report);
      ApplyNewsAndSessionBypass(cfg, g_last_report);
      ApplyMicroRelaxation(cfg, g_last_report);
      ApplyDiagnostics(cfg, g_last_report);
      ApplyErgonomics(cfg, g_last_report);

      g_last_report.applied = true;
      g_last_report.reason  = "applied";

      string err = "";
      g_last_report.validation_ok = ValidateAppliedConfig(cfg, err);
      g_last_report.validation_error = err;

      return true;
   }
}

#endif