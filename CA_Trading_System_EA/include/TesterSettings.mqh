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
         TESTER_PRESET_OFF     = 0,
         TESTER_PRESET_RELAXED = 1,
         TESTER_PRESET_DEBUG   = 2,
         TESTER_PRESET_SMOKE   = 3,
         TESTER_PRESET_PARITY  = 4
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
      bool   loose_tester;
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
      r.loose_tester         = false;
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
      if(preset == TESTER_PRESET_PARITY)  return "PARITY";
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

   inline bool PresetIsParity(const int preset)
   {
      return (preset == TESTER_PRESET_PARITY);
   }

   inline void AppendAuditToken(string &csv, const string token)
   {
      if(StringLen(token) <= 0)
         return;

      if(StringLen(csv) > 0)
         csv += ",";

      csv += token;
   }

   inline bool IsParityPresetName(const string preset_name)
   {
      if(preset_name == "PARITY") return true;
      if(preset_name == "parity") return true;
      if(preset_name == "MAIN_ONLY_PARITY") return true;
      if(preset_name == "main_only_parity") return true;
      if(preset_name == "CONSISTENCY_PARITY") return true;
      if(preset_name == "consistency_parity") return true;
      return false;
   }

   inline void PrimeParityPresetInputs(Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE
         cfg.tester_settings_enable = true;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_APPLY_ONLY_IN_TESTER
         cfg.tester_settings_apply_only_in_tester = true;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_PRESET
         cfg.tester_settings_preset = TESTER_PRESET_PARITY;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_LOG_AUDIT
         cfg.tester_settings_log_audit = true;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE_VERBOSE_DIAGNOSTICS
         cfg.tester_settings_enable_verbose_diagnostics = true;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_ZERO_ALL_MIN_SCORES
         cfg.tester_settings_zero_all_min_scores = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_NEWS
         cfg.tester_settings_disable_news = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_KILLZONES
         cfg.tester_settings_disable_killzones = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_SESSION_FILTER
         cfg.tester_settings_disable_session_filter = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_DISABLE_CORRELATION
         cfg.tester_settings_disable_correlation = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_REDUCE_MICRO_THRESHOLDS
         cfg.tester_settings_reduce_micro_thresholds = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_ALLOW_UNAVAILABLE_INSTITUTIONAL
         cfg.tester_settings_allow_unavailable_institutional = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE_DEGRADED_FALLBACK
         cfg.tester_settings_enable_degraded_fallback = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_BLOCK_IF_UNAVAILABLE
         cfg.tester_settings_block_if_unavailable = true;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_REDUCE_COOLDOWNS
         cfg.tester_settings_reduce_cooldowns = false;
      #endif

      #ifdef CFG_HAS_TESTERSETTINGS_LOOSE_TESTER
         cfg.tester_settings_loose_tester = false;
      #endif
   }

   inline bool ApplyPresetNameAlias(Settings &cfg, const string preset_name)
   {
      if(!IsParityPresetName(preset_name))
         return false;

      PrimeParityPresetInputs(cfg);
      return true;
   }

   inline bool AnyNewsSessionBypassRequested(const Settings &cfg)
   {
      return (DisableNewsRequested(cfg) ||
              DisableKillzonesRequested(cfg) ||
              DisableSessionFilterRequested(cfg) ||
              DisableCorrelationRequested(cfg));
   }

   inline bool AnyMicroRelaxationRequested(const Settings &cfg)
   {
      return (ReduceMicroThresholdsRequested(cfg) ||
              AllowUnavailableInstitutionalRequested(cfg) ||
              EnableDegradedFallbackRequested(cfg) ||
              BlockIfUnavailableRequested(cfg));
   }

   inline string BuildParitySafeKnobs(const Settings &cfg)
   {
      string s = "";

      AppendAuditToken(s, "canonical_route_unchanged");
      AppendAuditToken(s, "strat_mode_unchanged");

      if(cfg.debug)
         AppendAuditToken(s, "debug");

      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE_VERBOSE_DIAGNOSTICS
         if(cfg.tester_settings_enable_verbose_diagnostics)
            AppendAuditToken(s, "verbose_diagnostics");
      #endif

      #ifdef CFG_HAS_ROUTER_DEBUG
         if(cfg.router_debug_log)
            AppendAuditToken(s, "router_debug");
      #endif

      #ifdef CFG_HAS_ICT_SCORE_DEBUG_LOG
         if(cfg.ict_score_debug_log)
            AppendAuditToken(s, "ict_score_debug");
      #endif

      #ifdef CFG_HAS_CANDIDATE_TRACE_DEBUG
         if(cfg.candidate_trace_debug)
            AppendAuditToken(s, "candidate_trace");
      #endif

      #ifdef CFG_HAS_LOG_VETO_DETAILS
         if(cfg.log_veto_details)
            AppendAuditToken(s, "veto_detail_logging");
      #endif

      if(cfg.debug)
         AppendAuditToken(s, "hypothesis_reject_logging_via_debug");

      if(StringLen(s) <= 0)
         s = "none";

      return s;
   }

   inline string BuildParityBreakingKnobs(const Settings &cfg)
   {
      string s = "";

      if(g_last_report.score_relaxation)
         AppendAuditToken(s, "score_relaxation");

      if(g_last_report.news_session_bypass)
         AppendAuditToken(s, "news_session_bypass");

      if(g_last_report.micro_relaxation)
         AppendAuditToken(s, "micro_relaxation");

      if(g_last_report.loose_tester)
         AppendAuditToken(s, "loose_tester");

      if(g_last_report.ergonomics_relaxed)
         AppendAuditToken(s, "ergonomics_relaxation");

      if(Config::CfgStrategyMode(cfg) != STRAT_MAIN_ONLY)
         AppendAuditToken(s, "mode_not_main_only");

      #ifdef CFG_HAS_ALLOW_TESTER_DEGRADED_INST_FALLBACK
         if(cfg.allow_tester_degraded_inst_fallback)
            AppendAuditToken(s, "tester_degraded_fallback");
      #endif

      #ifdef CFG_HAS_ROUTER_TESTER_MIN_SCORE_OVERRIDE
         if(cfg.router_tester_min_score_override > 0.0)
            AppendAuditToken(s, "router_tester_min_override");
      #endif

      #ifdef CFG_HAS_TESTER_DISABLE_NEWS_CORR
         if(cfg.tester_disable_news_and_correlation)
            AppendAuditToken(s, "tester_disable_news_correlation");
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_LOOSE_GATE
         if(cfg.main_tester_loose_gate)
            AppendAuditToken(s, "main_tester_loose_gate");
      #endif

      if(StringLen(s) <= 0)
         s = "none";

      return s;
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

   inline bool LooseTesterRequested(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTERSETTINGS_LOOSE_TESTER
         return (cfg.tester_settings_loose_tester ? true : false);
      #else
         return true;
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
      return (preset == TESTER_PRESET_DEBUG  ||
              preset == TESTER_PRESET_SMOKE  ||
              preset == TESTER_PRESET_PARITY);
   }

   inline bool PresetWantsErgonomics(const int preset)
   {
      return (preset == TESTER_PRESET_SMOKE);
   }

   inline int ResolveTesterMaxStrats(const Settings &cfg)
   {
      #ifdef CFG_HAS_TESTER_REGISTERED_STRATEGY_COUNT
         if(cfg.tester_registered_strategy_count > 0)
            return cfg.tester_registered_strategy_count;
      #endif

      #ifdef CFG_HAS_REGISTERED_STRATEGY_COUNT
         if(cfg.registered_strategy_count > 0)
            return cfg.registered_strategy_count;
      #endif

      #ifdef CFG_HAS_ROUTER_MAX_STRATS
         if(cfg.router_max_strats > 0)
            return cfg.router_max_strats;
      #endif

      return 10;
   }

   inline void DisableKillzone(Settings &cfg, ApplyReport &r)
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

      r.news_session_bypass = true;
   }

   inline void DisableMicrostructureGates(Settings &cfg, ApplyReport &r)
   {
      ApplyMicroRelaxation(cfg, r);

      #ifdef CFG_HAS_MS_BLOCK_IF_UNAVAILABLE
         cfg.ms_block_if_unavailable = false;
      #endif

      #ifdef CFG_HAS_MS_TESTER_ALLOW_UNAVAILABLE
         cfg.ms_tester_allow_unavailable = true;
      #endif

      #ifdef CFG_HAS_MS_TESTER_LOG_UNAVAILABLE
         cfg.ms_tester_log_unavailable = true;
      #endif

      #ifdef CFG_HAS_MS_TESTER_DEGRADED_SCORE_POLICY_ENABLE
         cfg.ms_tester_degraded_score_policy_enable = true;
      #endif
   }

   inline void ApplyLooseTesterBypass(Settings &cfg, ApplyReport &r)
   {
      if(!IsTesterContext())
         return;

      const int preset = ActivePreset(cfg);

      if(PresetIsParity(preset))
         return;

      if(!LooseTesterRequested(cfg))
         return;

      #ifdef CFG_HAS_POLICY_ENABLE_REGIME_GATE
         cfg.enable_regime_gate = false;
      #endif

      #ifdef CFG_HAS_REGIME_GATE_ON
         cfg.regime_gate_on = false;
      #endif

      #ifdef CFG_HAS_POLICY_ENABLE_LIQUIDITY_GATE
         cfg.enable_liquidity_gate = false;
      #endif

      #ifdef CFG_HAS_LIQ_INVALID_HARDFAIL
         cfg.liq_hard_fail_on_invalid_metrics = false;
      #endif

      #ifdef CFG_HAS_ADR_CAP_MULT
         cfg.adr_cap_mult = 0.0;
      #endif

      #ifdef CFG_HAS_ADR_MIN_PIPS
         cfg.adr_min_pips = 0.0;
      #endif

      #ifdef CFG_HAS_ADR_MAX_PIPS
         cfg.adr_max_pips = 0.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_LOOSE_GATE
         cfg.main_tester_loose_gate = true;
      #endif

      r.loose_tester = true;
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

      if(PresetIsParity(preset))
         return;

      if(!PresetWantsScoreRelaxation(preset) && !ZeroAllMinScoresRequested(cfg))
         return;

      #ifdef CFG_HAS_ROUTER_MIN_SCORE
         cfg.router_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_ROUTER_FALLBACK_MIN
         cfg.router_fallback_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_ROUTER_FB_MIN
         cfg.router_fb_min = -1.0;
      #endif

      #ifdef CFG_HAS_ROUTER_TESTER_MIN_SCORE_OVERRIDE
         cfg.router_tester_min_score_override = -1.0;
      #endif

      #ifdef CFG_HAS_ROUTER_MAX_STRATS
         const int tester_max_strats = ResolveTesterMaxStrats(cfg);
         if(tester_max_strats > 0)
            cfg.router_max_strats = tester_max_strats;
      #endif

      #ifdef CFG_HAS_EXTRA_MIN_SCORE
         cfg.extra_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_EXTRA_MIN_GATE_SCORE
         cfg.extra_min_gate_score = -1.0;
      #endif

      #ifdef CFG_HAS_STRATEGY_MIN_SCORE_DEFAULT
         cfg.strategy_min_score_default = -1.0;
      #endif

      #ifdef CFG_HAS_CHECKLIST_MIN_SCORE
         cfg.checklist_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_DEBUG_CHECKLIST_MIN_SCORE
         cfg.debug_checklist_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_PROFILE_MIN_SCORE
         cfg.profile_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_MAIN_MIN_SCORE
         cfg.main_min_score = -1.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_ALPHA_MIN
         cfg.main_tester_alpha_min = -1.0;
      #endif

      #ifdef CFG_HAS_MAIN_TESTER_EXEC_MIN
         cfg.main_tester_exec_min = -1.0;
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

      if(cfg.qualityThresholdHigh > 0.0)
         cfg.qualityThresholdHigh = 0.0;

      if(cfg.qualityThresholdContinuation > 0.0)
         cfg.qualityThresholdContinuation = 0.0;

      if(cfg.qualityThresholdReversal > 0.0)
         cfg.qualityThresholdReversal = 0.0;

      r.score_relaxation = true;
   }

   // --------------------------------------------------------------------------
   // News / session / kill-zone / correlation bypass
   // This must happen on the effective runtime config, not raw inputs.
   // --------------------------------------------------------------------------
   inline void ApplyNewsAndSessionBypass(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);

      if(PresetIsParity(preset))
         return;

      if(!PresetWantsNewsSessionBypass(preset) && !AnyNewsSessionBypassRequested(cfg))
         return;

      cfg.news_on = false;
      cfg.newsFilterEnabled = false;
      cfg.scan_news_enable = false;
      cfg.cf_news_ok = false;
      cfg.cf_correlation = false;
      cfg.corr_softveto_enable = false;

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

      if(DisableKillzonesRequested(cfg))
         DisableKillzone(cfg, r);

      #ifdef CFG_HAS_SESSION_FILTER
         cfg.session_filter = false;
      #endif

      #ifdef CFG_HAS_ENABLE_SESSION_FILTER
         cfg.enable_session_filter = false;
      #endif

      #ifdef CFG_HAS_POLICY_ENABLE_REGIME_GATE
         cfg.enable_regime_gate = false;
      #endif

      #ifdef CFG_HAS_REGIME_GATE_ON
         cfg.regime_gate_on = false;
      #endif

      #ifdef CFG_HAS_POLICY_ENABLE_LIQUIDITY_GATE
         cfg.enable_liquidity_gate = false;
      #endif

      #ifdef CFG_HAS_LIQ_INVALID_HARDFAIL
         cfg.liq_hard_fail_on_invalid_metrics = false;
      #endif

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

      r.news_session_bypass = true;
   }

   // --------------------------------------------------------------------------
   // Microstructure relaxation
   // Keep this threshold-only. No micro logic belongs here.
   // --------------------------------------------------------------------------
   inline void ApplyMicroRelaxation(Settings &cfg, ApplyReport &r)
   {
      const int preset = ActivePreset(cfg);

      if(PresetIsParity(preset))
         return;

      if(!PresetWantsMicroRelaxation(preset) && !AnyMicroRelaxationRequested(cfg))
         return;

      #ifdef CFG_HAS_MS_OFI_ABS_MIN
         cfg.ms_ofi_abs_min = 0.0;
      #endif

      #ifdef CFG_HAS_MS_OBI_ABS_MIN
         cfg.ms_obi_abs_min = 0.0;
      #endif

      #ifdef CFG_HAS_MS_VPIN_THRESHOLD
         cfg.ms_vpin_threshold = 1.0;
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
         cfg.ms_max_toxicity01 = 1.0;
      #endif

      #ifdef CFG_HAS_MS_MAX_OBSERVABILITY_PENALTY01
         cfg.ms_max_observability_penalty01 = 1.0;
      #endif

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
         if(cfg.tester_micro_weight_scale <= 0.0 || cfg.tester_micro_weight_scale > 1.0)
            cfg.tester_micro_weight_scale = 0.5;
      #endif

      #ifdef CFG_HAS_MS_LIVE_ALLOW_DEGRADED_INST_FALLBACK
         cfg.ms_live_allow_degraded_inst_fallback = true;
      #endif

      #ifdef CFG_HAS_MS_TESTER_DEGRADED_SCORE_POLICY_ENABLE
         cfg.ms_tester_degraded_score_policy_enable = true;
      #endif

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

      #ifdef CFG_HAS_TESTERSETTINGS_ENABLE_VERBOSE_DIAGNOSTICS
         cfg.tester_settings_enable_verbose_diagnostics = true;
      #endif

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

      if(PresetIsParity(preset))
         return;

      if(!PresetWantsErgonomics(preset) && !ReduceCooldownsRequested(cfg))
         return;

      #ifdef CFG_HAS_TESTER_THROTTLE_SEC
         cfg.tester_throttle_sec = 60;
      #endif

      #ifdef CFG_HAS_EXEC_COOLDOWN_SEC
         if(cfg.exec_cooldown_sec > 60)
            cfg.exec_cooldown_sec = 60;
      #endif

      #ifdef CFG_HAS_ROUTER_MAX_STRATS
         const int tester_max_strats = ResolveTesterMaxStrats(cfg);
         if(tester_max_strats > 0)
            cfg.router_max_strats = tester_max_strats;
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
            if(cfg.cf_news_ok) err += "cf_news_ok still true; ";
         }

         if(DisableCorrelationRequested(cfg))
         {
            if(cfg.corr_softveto_enable) err += "corr_softveto_enable still true; ";
            if(cfg.cf_correlation) err += "cf_correlation still true; ";
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

      if(IsTesterContext() && LooseTesterRequested(cfg))
      {
         #ifdef CFG_HAS_POLICY_ENABLE_REGIME_GATE
            if(cfg.enable_regime_gate)
               err += "enable_regime_gate still true; ";
         #endif

         #ifdef CFG_HAS_REGIME_GATE_ON
            if(cfg.regime_gate_on)
               err += "regime_gate_on still true; ";
         #endif

         #ifdef CFG_HAS_POLICY_ENABLE_LIQUIDITY_GATE
            if(cfg.enable_liquidity_gate)
               err += "enable_liquidity_gate still true; ";
         #endif

         #ifdef CFG_HAS_ADR_CAP_MULT
            if(cfg.adr_cap_mult > 0.0)
               err += "adr_cap_mult still above zero; ";
         #endif

         #ifdef CFG_HAS_ADR_MIN_PIPS
            if(cfg.adr_min_pips > 0.0)
               err += "adr_min_pips still above zero; ";
         #endif

         #ifdef CFG_HAS_ADR_MAX_PIPS
            if(cfg.adr_max_pips > 0.0)
               err += "adr_max_pips still above zero; ";
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
      s += StringFormat(" loose=%s", (g_last_report.loose_tester ? "on" : "off"));
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

   inline void EmitParityAudit(const Settings &cfg)
   {
      if(g_last_report.preset != TESTER_PRESET_PARITY)
         return;

      const bool main_only = (Config::CfgStrategyMode(cfg) == STRAT_MAIN_ONLY);
      const string safe_knobs = BuildParitySafeKnobs(cfg);
      const string breaking_knobs = BuildParityBreakingKnobs(cfg);

      PrintFormat("[TesterSettings][PARITY] preset=%s tester=%s main_only=%s route_path=canonical_run_cached_router_pass parity_safe=%s parity_breaking=%s validation_ok=%s",
                  ActivePresetName(g_last_report.preset),
                  BoolStr(IsTesterContext()),
                  BoolStr(main_only),
                  safe_knobs,
                  breaking_knobs,
                  BoolStr(g_last_report.validation_ok));
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

      EmitParityAudit(cfg);
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

      if(ApplyOnlyInTester(cfg) && !IsTesterContext())
      {
         g_last_report.reason = "not_tester_context";
         EmitSkipAudit(cfg, g_last_report.reason);
         return false;
      }

      if(!IsTesterContext())
      {
         if(!MasterEnabled(cfg))
         {
            g_last_report.reason = "master_disabled";
            EmitSkipAudit(cfg, g_last_report.reason);
            return false;
         }

         if(g_last_report.preset == TESTER_PRESET_OFF)
         {
            g_last_report.reason = "preset_off";
            EmitSkipAudit(cfg, g_last_report.reason);
            return false;
         }
      }

      const int preset = ActivePreset(cfg);

      ApplyScoreRelaxation(cfg, g_last_report);

      if(IsTesterContext() && !PresetIsParity(preset))
      {
         if(PresetWantsMicroRelaxation(preset) || AnyMicroRelaxationRequested(cfg))
            DisableMicrostructureGates(cfg, g_last_report);

         if(PresetWantsNewsSessionBypass(preset) || DisableKillzonesRequested(cfg))
            DisableKillzone(cfg, g_last_report);
      }

      ApplyNewsAndSessionBypass(cfg, g_last_report);
      ApplyLooseTesterBypass(cfg, g_last_report);
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