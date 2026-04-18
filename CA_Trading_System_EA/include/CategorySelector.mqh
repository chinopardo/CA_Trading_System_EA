#ifndef CA_CATEGORY_SELECTOR_MQH
#define CA_CATEGORY_SELECTOR_MQH

#include "Config.mqh"
#include "Types.mqh"
#include "InstitutionalStateVector.mqh"

namespace CategorySelector
{

// ============================================================================
// Internal helpers
// ============================================================================

inline bool IsValidRawIndex(const int raw_index)
{
   return (raw_index >= 0 && raw_index < RAW_COUNT);
}

inline bool IsValidInputArraySizes(const double &raw[],
                                   const double &z[],
                                   const bool &valid_mask[])
{
   if(ArraySize(raw) < RAW_COUNT)
      return false;
   if(ArraySize(z) < RAW_COUNT)
      return false;
   if(ArraySize(valid_mask) < RAW_COUNT)
      return false;
   return true;
}

inline bool IsCategoryEnabledByConfig(const Settings &cfg,
                                     const int category)
{
   if(!cfg.sigsel_enable)
      return true;

   if(category == CAT_INSTITUTIONAL) return cfg.sigsel_enable_inst;
   if(category == CAT_TREND)         return cfg.sigsel_enable_trend;
   if(category == CAT_MOMENTUM)      return cfg.sigsel_enable_mom;
   if(category == CAT_VOLUME)        return cfg.sigsel_enable_vol;
   if(category == CAT_VOLATILITY)    return cfg.sigsel_enable_vola;

   return true;
}

inline int CountEnabledStackCategories(const Settings &cfg)
{
   int enabled_count = 0;

   if(IsCategoryEnabledByConfig(cfg, CAT_INSTITUTIONAL)) enabled_count++;
   if(IsCategoryEnabledByConfig(cfg, CAT_TREND))         enabled_count++;
   if(IsCategoryEnabledByConfig(cfg, CAT_MOMENTUM))      enabled_count++;
   if(IsCategoryEnabledByConfig(cfg, CAT_VOLUME))        enabled_count++;
   if(IsCategoryEnabledByConfig(cfg, CAT_VOLATILITY))    enabled_count++;

   return enabled_count;
}

inline int CapEffectiveMinCategoryVotesToEnabledCategories(const Settings &cfg,
                                                           const int requested_votes)
{
   int enabled_count = CountEnabledStackCategories(cfg);
   if(enabled_count < 1)
      enabled_count = 1;

   int out_votes = requested_votes;
   if(out_votes < 1)
      out_votes = 1;
   if(out_votes > enabled_count)
      out_votes = enabled_count;

   return out_votes;
}

inline void BuildBankSelectionViews(const RawSignalBank_t &bank,
                                    double &raw[],
                                    double &z[],
                                    bool &valid_mask[])
{
   ArrayResize(raw, RAW_COUNT);
   ArrayResize(z, RAW_COUNT);
   ArrayResize(valid_mask, RAW_COUNT);

   for(int i = 0; i < RAW_COUNT; i++)
   {
      raw[i] = bank.raw[i];
      z[i]   = bank.z[i];

      valid_mask[i] =
         (bank.valid &&
          MathIsValidNumber(bank.raw[i]) &&
          MathIsValidNumber(bank.z[i]));
   }
}

inline bool IsInstitutionalProxyRawIndex(const int raw_index)
{
   int proxy_candidates[];
   SigSel_GetInstitutionalProxyCandidates(proxy_candidates);
   return (FindRawIndexPositionInList(proxy_candidates, raw_index) >= 0);
}

inline int ResolveInstitutionalSelectionSourceFromBank(const RawSignalBank_t &bank,
                                                       const CategorySelectedVector &sel)
{
   if(bank.degrade.inst_sel_source == INST_SIGNAL_SOURCE_DIRECT ||
      bank.degrade.inst_sel_source == INST_SIGNAL_SOURCE_PROXY)
      return bank.degrade.inst_sel_source;

   if(sel.inst_active <= 0 || sel.inst_index < 0)
      return INST_SIGNAL_SOURCE_NONE;

   if(IsInstitutionalProxyRawIndex(sel.inst_index))
      return INST_SIGNAL_SOURCE_PROXY;

   return INST_SIGNAL_SOURCE_DIRECT;
}

inline int ResolveEffectiveMinCategoryVotesFromBank(const Settings &cfg,
                                                    const RawSignalBank_t &bank)
{
   const int base_votes  = GetEffectiveMinCategoryVotesBase(cfg);
   const int floor_votes = GetEffectiveMinCategoryVotesFloor(cfg, base_votes);

   int effective_votes = base_votes;

   if(bank.degrade.inst_unavailable == 1 &&
      bank.degrade.proxy_inst_available == 1 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX)
   {
      effective_votes = RelaxMinCategoryVotesByOne(base_votes, floor_votes);
   }
   else
   if(bank.degrade.inst_unavailable == 1 &&
      bank.degrade.proxy_inst_available == 0 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_SOFT_NEUTRAL_THEN_STACK_RELAX)
   {
      effective_votes = RelaxMinCategoryVotesByOne(base_votes, floor_votes);
   }
   else
   if(bank.degrade.inst_unavailable == 1 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX)
   {
      effective_votes = RelaxMinCategoryVotesByOne(base_votes, floor_votes);
   }

   effective_votes =
      CapEffectiveMinCategoryVotesToEnabledCategories(cfg, effective_votes);

   return effective_votes;
}

inline void ClearInstitutionalSelection(CategorySelectedVector &sel)
{
   sel.inst_index  = -1;
   sel.inst_value  = 0.0;
   sel.inst_z      = 0.0;
   sel.inst_active = 0;
}

inline void ApplyInstitutionalAntiEchoFromBank(const Settings &cfg,
                                               const RawSignalBank_t &bank,
                                               CategorySelectedVector &sel)
{
   if(bank.degrade.hard_inst_block == 1)
   {
      ClearInstitutionalSelection(sel);
      return;
   }

   if(sel.inst_active <= 0)
      return;

   const int resolved_source = ResolveInstitutionalSelectionSourceFromBank(bank, sel);

   if(bank.degrade.inst_unavailable == 1 &&
      bank.degrade.proxy_inst_available == 0 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_HARD_BLOCK)
   {
      ClearInstitutionalSelection(sel);
      return;
   }

   if(bank.degrade.inst_unavailable == 1 &&
      resolved_source == INST_SIGNAL_SOURCE_DIRECT &&
      (cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE ||
       cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX ||
       cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_SOFT_NEUTRAL_THEN_STACK_RELAX))
   {
      ClearInstitutionalSelection(sel);
   }
}

inline void OverlayInstitutionalPassMetaFromBank(const Settings &cfg,
                                                 const RawSignalBank_t &bank,
                                                 const CategorySelectedVector &sel,
                                                 CategoryPassVector &passv)
{
   passv.inst_coverage        = bank.degrade.inst_coverage;
   passv.inst_available       = bank.degrade.inst_available;
   passv.inst_partial         = bank.degrade.inst_partial;
   passv.inst_unavailable     = bank.degrade.inst_unavailable;
   passv.proxy_inst_available = bank.degrade.proxy_inst_available;
   passv.inst_sel_source      = ResolveInstitutionalSelectionSourceFromBank(bank, sel);
   passv.hard_inst_block      = bank.degrade.hard_inst_block;

   passv.effective_min_category_votes =
      ResolveEffectiveMinCategoryVotesFromBank(cfg, bank);

   ApplyCategoryEnableMaskToPassMeta(cfg, passv);
}

inline void ApplyCategoryEnableMaskToPassMeta(const Settings &cfg,
                                              CategoryPassVector &passv)
{
   if(!IsCategoryEnabledByConfig(cfg, CAT_INSTITUTIONAL))
   {
      passv.inst_pass = 0;
      passv.inst_sel_source = INST_SIGNAL_SOURCE_NONE;
      passv.hard_inst_block = 0;
   }

   if(!IsCategoryEnabledByConfig(cfg, CAT_TREND))
      passv.trend_pass = 0;

   if(!IsCategoryEnabledByConfig(cfg, CAT_MOMENTUM))
      passv.mom_pass = 0;

   if(!IsCategoryEnabledByConfig(cfg, CAT_VOLUME))
      passv.vol_pass = 0;

   if(!IsCategoryEnabledByConfig(cfg, CAT_VOLATILITY))
      passv.vola_pass = 0;

   passv.effective_min_category_votes =
      CapEffectiveMinCategoryVotesToEnabledCategories(cfg,
                                                      passv.effective_min_category_votes);
}

inline void RefreshStackAndLocationGates(const Settings &cfg,
                                         CategoryPassVector &passv)
{
   passv.effective_min_category_votes =
      CapEffectiveMinCategoryVotesToEnabledCategories(cfg,
                                                      passv.effective_min_category_votes);

   passv.signal_stack_score =
      passv.inst_pass +
      passv.trend_pass +
      passv.mom_pass +
      passv.vol_pass +
      passv.vola_pass;

   if(cfg.sigsel_enable)
   {
      if(passv.hard_inst_block == 1)
         passv.signal_stack_gate = 0;
      else
         passv.signal_stack_gate =
            (passv.signal_stack_score >= passv.effective_min_category_votes ? 1 : 0);
   }
   else
   {
      passv.signal_stack_gate = 1;
   }

   if(cfg.sigsel_enable)
      passv.location_pass = (passv.location_score >= cfg.sigsel_min_location_votes ? 1 : 0);
   else
      passv.location_pass = 1;
}

inline void FillSignalStackGateFromPass(const CategoryPassVector &passv,
                                        SignalStackGate_t &out_gate)
{
   out_gate.Reset();
   out_gate.pass = passv.signal_stack_gate;
   out_gate.hard_inst_block = passv.hard_inst_block;
   out_gate.inst_coverage = passv.inst_coverage;
   out_gate.inst_available = passv.inst_available;
   out_gate.inst_partial = passv.inst_partial;
   out_gate.inst_unavailable = passv.inst_unavailable;
   out_gate.proxy_inst_available = passv.proxy_inst_available;
   out_gate.inst_sel_source = passv.inst_sel_source;
}

inline void FillLocationPassFromBank(const CategoryPassVector &passv,
                                     const RawSignalBank_t &bank,
                                     LocationPass_t &out_loc)
{
   out_loc.Reset();
   out_loc.pass = passv.location_pass;
   out_loc.sweep_score = bank.raw[RAW_SWEEP_SCORE];
   out_loc.liquidity_gap = MathAbs(bank.raw[RAW_LIQUIDITY_STRESS_PROXY]);
   out_loc.spread_shock_z = bank.z[RAW_SPREAD_SHOCK];
   out_loc.slippage_z = bank.z[RAW_SLIPPAGE];
   out_loc.depth_fade_z = bank.z[RAW_DEPTH_FADE];
   out_loc.poc_dist_z = bank.z[RAW_POC_DIST];
   out_loc.va_state_z = bank.z[RAW_VA_STATE];
   out_loc.poi_score01 = bank.ms.poi_score01;
   out_loc.poi_distance_atr01 = bank.ms.poi_distance_atr01;
   out_loc.poi_kind = bank.ms.poi_kind;
   out_loc.liquidity_event_time = bank.ms.liquidity_event_time;
   out_loc.liquidity_event_price = bank.ms.liquidity_event_price;
}

inline string BuildSelectionDiagnosticSummary(const CategorySelectedVector &sel,
                                              const CategoryPassVector &passv,
                                              const RawSignalBank_t &bank)
{
   return StringFormat(
      "sym=%s tf=%d inst[idx=%d z=%.4f src=%d cov=%.3f hard=%d] "
      "trend[idx=%d z=%.4f] mom[idx=%d z=%.4f] vol[idx=%d z=%.4f] vola[idx=%d z=%.4f] "
      "passes[i=%d t=%d m=%d v=%d va=%d] stack=%d req=%d gate=%d loc=%d pass=%d",
      bank.symbol,
      (int)bank.tf,
      sel.inst_index, sel.inst_z, passv.inst_sel_source, passv.inst_coverage, passv.hard_inst_block,
      sel.trend_index, sel.trend_z,
      sel.mom_index, sel.mom_z,
      sel.vol_index, sel.vol_z,
      sel.vola_index, sel.vola_z,
      passv.inst_pass,
      passv.trend_pass,
      passv.mom_pass,
      passv.vol_pass,
      passv.vola_pass,
      passv.signal_stack_score,
      passv.effective_min_category_votes,
      passv.signal_stack_gate,
      passv.location_score,
      passv.location_pass
   );
}

inline void EmitSelectionDiagnosticLog(const CategorySelectedVector &sel,
                                       const CategoryPassVector &passv,
                                       const RawSignalBank_t &bank,
                                       const string log_tag)
{
   PrintFormat("[%s] %s",
               log_tag,
               BuildSelectionDiagnosticSummary(sel, passv, bank));
}

inline void LoadThresholdViewFromSettings(const Settings &cfg,
                                          SignalSelectionThresholdView &out_view)
{
   out_view.Reset();

   out_view.band_rsi       = cfg.sigsel_band_rsi;
   out_view.band_stoch     = cfg.sigsel_band_stoch;
   out_view.th_adx         = cfg.sigsel_th_adx;

   out_view.th_atr_min     = cfg.sigsel_th_atr_min;
   out_view.th_atr_max     = cfg.sigsel_th_atr_max;
   out_view.th_bbwidth_min = cfg.sigsel_th_bbwidth_min;
   out_view.th_bbwidth_max = cfg.sigsel_th_bbwidth_max;
   out_view.th_rv_min      = cfg.sigsel_th_rv_min;
   out_view.th_rv_max      = cfg.sigsel_th_rv_max;
   out_view.th_bv_min      = cfg.sigsel_th_bv_min;
   out_view.th_bv_max      = cfg.sigsel_th_bv_max;
   out_view.th_jump_max    = cfg.sigsel_th_jump_max;
   out_view.th_sigmap_min  = cfg.sigsel_th_sigmap_min;
   out_view.th_sigmap_max  = cfg.sigsel_th_sigmap_max;
   out_view.th_sigmagk_min = cfg.sigsel_th_sigmagk_min;
   out_view.th_sigmagk_max = cfg.sigsel_th_sigmagk_max;
}

inline double GetCategoryThreshold(const Settings &cfg, const int category)
{
   if(category == CAT_INSTITUTIONAL) return cfg.sigsel_th_inst;
   if(category == CAT_TREND)         return cfg.sigsel_th_trend;
   if(category == CAT_MOMENTUM)      return cfg.sigsel_th_mom;
   if(category == CAT_VOLUME)        return cfg.sigsel_th_vol;
   if(category == CAT_VOLATILITY)    return cfg.sigsel_th_vola;
   return 1.0;
}

inline int GetFixedCandidatePosition(const Settings &cfg, const int category)
{
   if(category == CAT_INSTITUTIONAL) return cfg.sigsel_fixed_inst_index;
   if(category == CAT_TREND)         return cfg.sigsel_fixed_trend_index;
   if(category == CAT_MOMENTUM)      return cfg.sigsel_fixed_mom_index;
   if(category == CAT_VOLUME)        return cfg.sigsel_fixed_vol_index;
   if(category == CAT_VOLATILITY)    return cfg.sigsel_fixed_vola_index;
   return 0;
}

inline double GetInstitutionalSubfamilyWeight(const Settings &cfg, const int subfamily)
{
   if(subfamily == INST_SUBFAMILY_ORDERBOOK)   return cfg.sigsel_w_orderbook;
   if(subfamily == INST_SUBFAMILY_TRADEFLOW)   return cfg.sigsel_w_tradeflow;
   if(subfamily == INST_SUBFAMILY_IMPACT)      return cfg.sigsel_w_impact;
   if(subfamily == INST_SUBFAMILY_EXECQUALITY) return cfg.sigsel_w_execquality;
   return 1.0;
}

inline double GetCategoryCandidateWeightByPosition(const Settings &cfg,
                                                   const int category,
                                                   const int position)
{
   if(position < 0)
      return 1.0;

   if(category == CAT_INSTITUTIONAL)
   {
      if(position < ArraySize(cfg.sigsel_inst_weights))
         return cfg.sigsel_inst_weights[position];
      return 1.0;
   }

   if(category == CAT_TREND)
   {
      if(position < ArraySize(cfg.sigsel_trend_weights))
         return cfg.sigsel_trend_weights[position];
      return 1.0;
   }

   if(category == CAT_MOMENTUM)
   {
      if(position < ArraySize(cfg.sigsel_mom_weights))
         return cfg.sigsel_mom_weights[position];
      return 1.0;
   }

   if(category == CAT_VOLUME)
   {
      if(position < ArraySize(cfg.sigsel_vol_weights))
         return cfg.sigsel_vol_weights[position];
      return 1.0;
   }

   if(category == CAT_VOLATILITY)
   {
      if(position < ArraySize(cfg.sigsel_vola_weights))
         return cfg.sigsel_vola_weights[position];
      return 1.0;
   }

   return 1.0;
}

inline int FindRawIndexPositionInList(const int &candidate_list[],
                                      const int raw_index)
{
   const int count = ArraySize(candidate_list);
   for(int i = 0; i < count; i++)
   {
      if(candidate_list[i] == raw_index)
         return i;
   }
   return -1;
}

inline double GetCategoryCandidateWeightByRawIndex(const Settings &cfg,
                                                   const int category,
                                                   const int raw_index,
                                                   const int fallback_position)
{
   int position = fallback_position;

   if(category == CAT_INSTITUTIONAL)
   {
      int all_inst_candidates[];
      SigSel_GetInstitutionalCandidates(all_inst_candidates);

      const int full_pos = FindRawIndexPositionInList(all_inst_candidates, raw_index);
      if(full_pos >= 0)
         position = full_pos;
   }

   return GetCategoryCandidateWeightByPosition(cfg, category, position);
}

inline double GetProxyCandidateWeightByPosition(const Settings &cfg,
                                                const int position)
{
   if(position == 0) return cfg.sigsel_w_proxy_microprice_bias;
   if(position == 1) return cfg.sigsel_w_proxy_auction_bias;
   if(position == 2) return cfg.sigsel_w_proxy_composite;
   return 1.0;
}

inline bool IsCandidateValid(const int raw_index,
                             const double &raw[],
                             const double &z[],
                             const bool &valid_mask[])
{
   if(!IsValidRawIndex(raw_index))
      return false;

   if(!valid_mask[raw_index])
      return false;

   if(!MathIsValidNumber(raw[raw_index]))
      return false;

   if(!MathIsValidNumber(z[raw_index]))
      return false;

   return true;
}

inline void SelectBestCandidateFromList(const Settings &cfg,
                                        const int category,
                                        const double &raw[],
                                        const double &z[],
                                        const bool &valid_mask[],
                                        const int &candidate_list[],
                                        int &best_raw_index,
                                        double &best_raw_value,
                                        double &best_z_value,
                                        double &best_score)
{
   best_raw_index = -1;
   best_raw_value = 0.0;
   best_z_value   = 0.0;
   best_score     = -1.0;

   const int count = ArraySize(candidate_list);
   if(count <= 0)
      return;

   for(int i = 0; i < count; i++)
   {
      const int raw_index = candidate_list[i];
      if(!IsCandidateValid(raw_index, raw, z, valid_mask))
         continue;

      double weight = GetCategoryCandidateWeightByRawIndex(cfg, category, raw_index, i);
      if(weight < 0.0)
         weight = 0.0;

      const double score = MathAbs(z[raw_index]) * weight;
      if(score > best_score)
      {
         best_score     = score;
         best_raw_index = raw_index;
         best_raw_value = raw[raw_index];
         best_z_value   = z[raw_index];
      }
   }
}

inline void SetCategorySelection(CategorySelectedVector &sel,
                                 const int category,
                                 const int raw_index,
                                 const double raw_value,
                                 const double z_value,
                                 const int active_flag)
{
   sel.SetCategory(category, raw_index, raw_value, z_value, active_flag);
}

struct InstitutionalSelectionDiagnostics
{
   int    subavail_ob;
   int    subavail_tf;
   int    subavail_imp;
   int    subavail_eq;

   double inst_coverage;
   int    inst_available;
   int    inst_partial;
   int    inst_unavailable;

   int    proxy_inst_available;
   int    inst_sel_source;
   int    hard_inst_block;
   int    effective_min_category_votes;

   int    selected_raw_index;
   double selected_raw_value;
   double selected_z_value;
   int    selected_active;

   void Reset()
   {
      subavail_ob                  = 0;
      subavail_tf                  = 0;
      subavail_imp                 = 0;
      subavail_eq                  = 0;

      inst_coverage                = 0.0;
      inst_available               = 0;
      inst_partial                 = 0;
      inst_unavailable             = 0;

      proxy_inst_available         = 0;
      inst_sel_source              = INST_SIGNAL_SOURCE_NONE;
      hard_inst_block              = 0;
      effective_min_category_votes = 0;

      selected_raw_index           = -1;
      selected_raw_value           = 0.0;
      selected_z_value             = 0.0;
      selected_active              = 0;
   }
};

inline void FillInstitutionalSubfamilyCandidates(const int subfamily,
                                                 int &dst[])
{
   ArrayResize(dst, 0);

   if(subfamily == INST_SUBFAMILY_ORDERBOOK)
   {
      SigSel_GetInstitutionalOrderBookCandidates(dst);
      return;
   }

   if(subfamily == INST_SUBFAMILY_TRADEFLOW)
   {
      SigSel_GetInstitutionalTradeFlowCandidates(dst);
      return;
   }

   if(subfamily == INST_SUBFAMILY_IMPACT)
   {
      SigSel_GetInstitutionalImpactCandidates(dst);
      return;
   }

   if(subfamily == INST_SUBFAMILY_EXECQUALITY)
   {
      SigSel_GetInstitutionalExecQualityCandidates(dst);
      return;
   }
}

inline int GetInstitutionalSubfamilyForRawIndex(const int raw_index)
{
   int candidates[];

   SigSel_GetInstitutionalOrderBookCandidates(candidates);
   if(FindRawIndexPositionInList(candidates, raw_index) >= 0)
      return INST_SUBFAMILY_ORDERBOOK;

   SigSel_GetInstitutionalTradeFlowCandidates(candidates);
   if(FindRawIndexPositionInList(candidates, raw_index) >= 0)
      return INST_SUBFAMILY_TRADEFLOW;

   SigSel_GetInstitutionalImpactCandidates(candidates);
   if(FindRawIndexPositionInList(candidates, raw_index) >= 0)
      return INST_SUBFAMILY_IMPACT;

   SigSel_GetInstitutionalExecQualityCandidates(candidates);
   if(FindRawIndexPositionInList(candidates, raw_index) >= 0)
      return INST_SUBFAMILY_EXECQUALITY;

   return -1;
}

inline int HasAnyValidCandidateFromList(const double &raw[],
                                        const double &z[],
                                        const bool &valid_mask[],
                                        const int &candidate_list[])
{
   const int count = ArraySize(candidate_list);
   for(int i = 0; i < count; i++)
   {
      if(IsCandidateValid(candidate_list[i], raw, z, valid_mask))
         return 1;
   }
   return 0;
}

inline void SelectBestProxyCandidateFromList(const Settings &cfg,
                                             const double &raw[],
                                             const double &z[],
                                             const bool &valid_mask[],
                                             const int &candidate_list[],
                                             int &best_raw_index,
                                             double &best_raw_value,
                                             double &best_z_value,
                                             double &best_score)
{
   best_raw_index = -1;
   best_raw_value = 0.0;
   best_z_value   = 0.0;
   best_score     = -1.0;

   const int count = ArraySize(candidate_list);
   if(count <= 0)
      return;

   for(int i = 0; i < count; i++)
   {
      const int raw_index = candidate_list[i];
      if(!IsCandidateValid(raw_index, raw, z, valid_mask))
         continue;

      double weight = GetProxyCandidateWeightByPosition(cfg, i);
      if(weight < 0.0)
         weight = 0.0;

      const double score = MathAbs(z[raw_index]) * weight;
      if(score > best_score)
      {
         best_score     = score;
         best_raw_index = raw_index;
         best_raw_value = raw[raw_index];
         best_z_value   = z[raw_index];
      }
   }
}

inline int GetEffectiveMinCategoryVotesBase(const Settings &cfg)
{
   int votes = cfg.sigsel_min_category_votes_default;
   if(votes <= 0)
      votes = cfg.sigsel_min_category_votes;

   if(votes < 1)
      votes = 1;
   if(votes > 5)
      votes = 5;

   return votes;
}

inline int GetEffectiveMinCategoryVotesFloor(const Settings &cfg,
                                             const int base_votes)
{
   int floor_votes = cfg.sigsel_min_category_votes_floor;
   if(floor_votes < 1)
      floor_votes = 1;
   if(floor_votes > base_votes)
      floor_votes = base_votes;

   return floor_votes;
}

inline int RelaxMinCategoryVotesByOne(const int base_votes,
                                      const int floor_votes)
{
   int relaxed_votes = base_votes - 1;
   if(relaxed_votes < floor_votes)
      relaxed_votes = floor_votes;
   return relaxed_votes;
}

inline void BuildInstitutionalSelectionDiagnostics(const Settings &cfg,
                                                   const double &raw[],
                                                   const double &z[],
                                                   const bool &valid_mask[],
                                                   const bool use_fixed_mode,
                                                   InstitutionalSelectionDiagnostics &diag)
{
   diag.Reset();

   int inst_candidates[];
   int orderbook_candidates[];
   int tradeflow_candidates[];
   int impact_candidates[];
   int execquality_candidates[];
   int proxy_candidates[];

   SigSel_GetInstitutionalCandidates(inst_candidates);
   SigSel_GetInstitutionalOrderBookCandidates(orderbook_candidates);
   SigSel_GetInstitutionalTradeFlowCandidates(tradeflow_candidates);
   SigSel_GetInstitutionalImpactCandidates(impact_candidates);
   SigSel_GetInstitutionalExecQualityCandidates(execquality_candidates);
   SigSel_GetInstitutionalProxyCandidates(proxy_candidates);

   diag.subavail_ob = HasAnyValidCandidateFromList(raw, z, valid_mask, orderbook_candidates);
   diag.subavail_tf = HasAnyValidCandidateFromList(raw, z, valid_mask, tradeflow_candidates);
   diag.subavail_imp = HasAnyValidCandidateFromList(raw, z, valid_mask, impact_candidates);
   diag.subavail_eq = HasAnyValidCandidateFromList(raw, z, valid_mask, execquality_candidates);

   double w_ob = cfg.sigsel_w_orderbook;
   double w_tf = cfg.sigsel_w_tradeflow;
   double w_imp = cfg.sigsel_w_impact;
   double w_eq = cfg.sigsel_w_execquality;

   if(w_ob < 0.0)  w_ob = 0.0;
   if(w_tf < 0.0)  w_tf = 0.0;
   if(w_imp < 0.0) w_imp = 0.0;
   if(w_eq < 0.0)  w_eq = 0.0;

   double coverage_den = w_ob + w_tf + w_imp + w_eq;
   if(coverage_den <= 0.0)
   {
      w_ob = 1.0;
      w_tf = 1.0;
      w_imp = 1.0;
      w_eq = 1.0;
      coverage_den = 4.0;
   }

   diag.inst_coverage =
      (w_ob * (double)diag.subavail_ob +
       w_tf * (double)diag.subavail_tf +
       w_imp * (double)diag.subavail_imp +
       w_eq * (double)diag.subavail_eq) / coverage_den;

   diag.inst_available =
      ((diag.subavail_ob == 1) ||
       (diag.subavail_tf == 1) ||
       (diag.subavail_imp == 1) ||
       (diag.subavail_eq == 1) ? 1 : 0);

   diag.inst_unavailable = (diag.inst_available == 1 ? 0 : 1);
   diag.inst_partial =
      ((diag.inst_available == 1) &&
       (diag.inst_coverage < cfg.sigsel_inst_coverage_threshold) ? 1 : 0);

   int direct_idx = -1;
   double direct_raw = 0.0;
   double direct_z = 0.0;
   double direct_score = -1.0;

   if(use_fixed_mode)
   {
      const int inst_count = ArraySize(inst_candidates);
      if(inst_count > 0)
      {
         int fixed_pos = GetFixedCandidatePosition(cfg, CAT_INSTITUTIONAL);
         if(fixed_pos < 0)
            fixed_pos = 0;
         if(fixed_pos >= inst_count)
            fixed_pos = inst_count - 1;

         const int fixed_raw_index = inst_candidates[fixed_pos];

         if(IsCandidateValid(fixed_raw_index, raw, z, valid_mask))
         {
            direct_idx = fixed_raw_index;
            direct_raw = raw[fixed_raw_index];
            direct_z   = z[fixed_raw_index];
            direct_score = MathAbs(direct_z);
         }
         else
         {
            const int fixed_subfamily = GetInstitutionalSubfamilyForRawIndex(fixed_raw_index);

            if(fixed_subfamily >= 0)
            {
               int same_subfamily_candidates[];
               FillInstitutionalSubfamilyCandidates(fixed_subfamily, same_subfamily_candidates);

               SelectBestCandidateFromList(cfg,
                                           CAT_INSTITUTIONAL,
                                           raw,
                                           z,
                                           valid_mask,
                                           same_subfamily_candidates,
                                           direct_idx,
                                           direct_raw,
                                           direct_z,
                                           direct_score);
            }

            if(direct_idx < 0)
            {
               SelectBestCandidateFromList(cfg,
                                           CAT_INSTITUTIONAL,
                                           raw,
                                           z,
                                           valid_mask,
                                           inst_candidates,
                                           direct_idx,
                                           direct_raw,
                                           direct_z,
                                           direct_score);
            }
         }
      }
   }
   else
   {
      if(cfg.sigsel_inst_selection_mode == Config::INST_SELECTION_DIRECT_FULL)
      {
         SelectBestCandidateFromList(cfg,
                                     CAT_INSTITUTIONAL,
                                     raw,
                                     z,
                                     valid_mask,
                                     inst_candidates,
                                     direct_idx,
                                     direct_raw,
                                     direct_z,
                                     direct_score);
      }
      else
      {
         int sf_best_idx[INST_SUBFAMILY_COUNT];
         double sf_best_raw[INST_SUBFAMILY_COUNT];
         double sf_best_z[INST_SUBFAMILY_COUNT];
         double sf_best_score[INST_SUBFAMILY_COUNT];

         for(int sf = 0; sf < INST_SUBFAMILY_COUNT; sf++)
         {
            sf_best_idx[sf]   = -1;
            sf_best_raw[sf]   = 0.0;
            sf_best_z[sf]     = 0.0;
            sf_best_score[sf] = -1.0;
         }

         SelectBestCandidateFromList(cfg,
                                     CAT_INSTITUTIONAL,
                                     raw,
                                     z,
                                     valid_mask,
                                     orderbook_candidates,
                                     sf_best_idx[INST_SUBFAMILY_ORDERBOOK],
                                     sf_best_raw[INST_SUBFAMILY_ORDERBOOK],
                                     sf_best_z[INST_SUBFAMILY_ORDERBOOK],
                                     sf_best_score[INST_SUBFAMILY_ORDERBOOK]);

         SelectBestCandidateFromList(cfg,
                                     CAT_INSTITUTIONAL,
                                     raw,
                                     z,
                                     valid_mask,
                                     tradeflow_candidates,
                                     sf_best_idx[INST_SUBFAMILY_TRADEFLOW],
                                     sf_best_raw[INST_SUBFAMILY_TRADEFLOW],
                                     sf_best_z[INST_SUBFAMILY_TRADEFLOW],
                                     sf_best_score[INST_SUBFAMILY_TRADEFLOW]);

         SelectBestCandidateFromList(cfg,
                                     CAT_INSTITUTIONAL,
                                     raw,
                                     z,
                                     valid_mask,
                                     impact_candidates,
                                     sf_best_idx[INST_SUBFAMILY_IMPACT],
                                     sf_best_raw[INST_SUBFAMILY_IMPACT],
                                     sf_best_z[INST_SUBFAMILY_IMPACT],
                                     sf_best_score[INST_SUBFAMILY_IMPACT]);

         SelectBestCandidateFromList(cfg,
                                     CAT_INSTITUTIONAL,
                                     raw,
                                     z,
                                     valid_mask,
                                     execquality_candidates,
                                     sf_best_idx[INST_SUBFAMILY_EXECQUALITY],
                                     sf_best_raw[INST_SUBFAMILY_EXECQUALITY],
                                     sf_best_z[INST_SUBFAMILY_EXECQUALITY],
                                     sf_best_score[INST_SUBFAMILY_EXECQUALITY]);

         for(int sf = 0; sf < INST_SUBFAMILY_COUNT; sf++)
         {
            if(sf_best_idx[sf] < 0)
               continue;

            double sf_weight = GetInstitutionalSubfamilyWeight(cfg, sf);
            if(sf_weight < 0.0)
               sf_weight = 0.0;

            const double sf_score = MathAbs(sf_best_z[sf]) * sf_weight;
            if(sf_score > direct_score)
            {
               direct_score = sf_score;
               direct_idx   = sf_best_idx[sf];
               direct_raw   = sf_best_raw[sf];
               direct_z     = sf_best_z[sf];
            }
         }
      }
   }

   int proxy_idx = -1;
   double proxy_raw = 0.0;
   double proxy_z = 0.0;
   double proxy_score = -1.0;

   diag.proxy_inst_available =
      HasAnyValidCandidateFromList(raw, z, valid_mask, proxy_candidates);

   SelectBestProxyCandidateFromList(cfg,
                                    raw,
                                    z,
                                    valid_mask,
                                    proxy_candidates,
                                    proxy_idx,
                                    proxy_raw,
                                    proxy_z,
                                    proxy_score);

   const int base_votes  = GetEffectiveMinCategoryVotesBase(cfg);
   const int floor_votes = GetEffectiveMinCategoryVotesFloor(cfg, base_votes);

   diag.effective_min_category_votes = base_votes;
   diag.hard_inst_block = 0;
   diag.inst_sel_source = INST_SIGNAL_SOURCE_NONE;

   if(direct_idx >= 0)
   {
      diag.inst_sel_source    = INST_SIGNAL_SOURCE_DIRECT;
      diag.selected_raw_index = direct_idx;
      diag.selected_raw_value = direct_raw;
      diag.selected_z_value   = direct_z;
      diag.selected_active    = 1;
      return;
   }

   if(diag.inst_unavailable == 1 &&
      diag.proxy_inst_available == 1 &&
      (cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE ||
       cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX))
   {
      if(proxy_idx >= 0)
      {
         diag.inst_sel_source    = INST_SIGNAL_SOURCE_PROXY;
         diag.selected_raw_index = proxy_idx;
         diag.selected_raw_value = proxy_raw;
         diag.selected_z_value   = proxy_z;
         diag.selected_active    = 1;
      }

      if(cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX)
         diag.effective_min_category_votes = RelaxMinCategoryVotesByOne(base_votes, floor_votes);

      return;
   }

   if(diag.inst_unavailable == 1 &&
      diag.proxy_inst_available == 0 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_SOFT_NEUTRAL_THEN_STACK_RELAX)
   {
      diag.inst_sel_source = INST_SIGNAL_SOURCE_NONE;
      diag.selected_raw_index = -1;
      diag.selected_raw_value = 0.0;
      diag.selected_z_value = 0.0;
      diag.selected_active = 0;
      diag.effective_min_category_votes = RelaxMinCategoryVotesByOne(base_votes, floor_votes);
      return;
   }

   if(diag.inst_unavailable == 1 &&
      diag.proxy_inst_available == 0 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_HARD_BLOCK)
   {
      diag.inst_sel_source = INST_SIGNAL_SOURCE_NONE;
      diag.selected_raw_index = -1;
      diag.selected_raw_value = 0.0;
      diag.selected_z_value = 0.0;
      diag.selected_active = 0;
      diag.hard_inst_block = 1;
      return;
   }

   if(diag.inst_unavailable == 1 &&
      diag.proxy_inst_available == 0 &&
      cfg.sigsel_institutional_degrade_mode == INST_DEGRADE_PROXY_SUBSTITUTE_THEN_STACK_RELAX)
   {
      diag.effective_min_category_votes = RelaxMinCategoryVotesByOne(base_votes, floor_votes);
   }
}

inline void ApplyInstitutionalSelectionToVector(const InstitutionalSelectionDiagnostics &diag,
                                                CategorySelectedVector &out_sel)
{
   if(diag.selected_raw_index < 0 || diag.selected_active <= 0)
      return;

   SetCategorySelection(out_sel,
                        CAT_INSTITUTIONAL,
                        diag.selected_raw_index,
                        diag.selected_raw_value,
                        diag.selected_z_value,
                        diag.selected_active);
}

inline void SelectFixedCategorySignal(const Settings &cfg,
                                      const int category,
                                      const double &raw[],
                                      const double &z[],
                                      const bool &valid_mask[],
                                      CategorySelectedVector &out_sel)
{
   if(category == CAT_INSTITUTIONAL)
   {
      InstitutionalSelectionDiagnostics inst_diag;
      BuildInstitutionalSelectionDiagnostics(cfg, raw, z, valid_mask, true, inst_diag);
      ApplyInstitutionalSelectionToVector(inst_diag, out_sel);
      return;
   }

   int candidates[];
   SigSel_GetCategoryCandidates(category, candidates);

   const int count = ArraySize(candidates);
   if(count <= 0)
      return;

   int pos = GetFixedCandidatePosition(cfg, category);
   if(pos < 0)
      pos = 0;
   if(pos >= count)
      pos = count - 1;

   const int raw_index = candidates[pos];
   if(!IsCandidateValid(raw_index, raw, z, valid_mask))
      return;

   SetCategorySelection(out_sel, category, raw_index, raw[raw_index], z[raw_index], 1);
}

inline void SelectDynamicInstitutionalSignal(const Settings &cfg,
                                             const double &raw[],
                                             const double &z[],
                                             const bool &valid_mask[],
                                             CategorySelectedVector &out_sel)
{
   InstitutionalSelectionDiagnostics inst_diag;
   BuildInstitutionalSelectionDiagnostics(cfg, raw, z, valid_mask, false, inst_diag);
   ApplyInstitutionalSelectionToVector(inst_diag, out_sel);
}

inline void SelectDynamicCategorySignal(const Settings &cfg,
                                        const int category,
                                        const double &raw[],
                                        const double &z[],
                                        const bool &valid_mask[],
                                        CategorySelectedVector &out_sel)
{
   if(category == CAT_INSTITUTIONAL)
   {
      SelectDynamicInstitutionalSignal(cfg, raw, z, valid_mask, out_sel);
      return;
   }

   int candidates[];
   SigSel_GetCategoryCandidates(category, candidates);

   int best_idx = -1;
   double best_raw = 0.0;
   double best_z = 0.0;
   double best_score = -1.0;

   SelectBestCandidateFromList(cfg,
                               category,
                               raw,
                               z,
                               valid_mask,
                               candidates,
                               best_idx,
                               best_raw,
                               best_z,
                               best_score);

   if(best_idx >= 0)
      SetCategorySelection(out_sel, category, best_idx, best_raw, best_z, 1);
}

inline bool CategoryUsesDirectionalPass(const int category)
{
   return (category != CAT_VOLATILITY);
}

inline int CategorySelectedRawIndex(const CategorySelectedVector &sel, const int category)
{
   if(category == CAT_INSTITUTIONAL) return sel.inst_index;
   if(category == CAT_TREND)         return sel.trend_index;
   if(category == CAT_MOMENTUM)      return sel.mom_index;
   if(category == CAT_VOLUME)        return sel.vol_index;
   if(category == CAT_VOLATILITY)    return sel.vola_index;
   return -1;
}

inline double CategorySelectedRawValue(const CategorySelectedVector &sel, const int category)
{
   if(category == CAT_INSTITUTIONAL) return sel.inst_value;
   if(category == CAT_TREND)         return sel.trend_value;
   if(category == CAT_MOMENTUM)      return sel.mom_value;
   if(category == CAT_VOLUME)        return sel.vol_value;
   if(category == CAT_VOLATILITY)    return sel.vola_value;
   return 0.0;
}

inline double CategorySelectedZValue(const CategorySelectedVector &sel, const int category)
{
   if(category == CAT_INSTITUTIONAL) return sel.inst_z;
   if(category == CAT_TREND)         return sel.trend_z;
   if(category == CAT_MOMENTUM)      return sel.mom_z;
   if(category == CAT_VOLUME)        return sel.vol_z;
   if(category == CAT_VOLATILITY)    return sel.vola_z;
   return 0.0;
}

inline int CategorySelectedActiveFlag(const CategorySelectedVector &sel, const int category)
{
   if(category == CAT_INSTITUTIONAL) return sel.inst_active;
   if(category == CAT_TREND)         return sel.trend_active;
   if(category == CAT_MOMENTUM)      return sel.mom_active;
   if(category == CAT_VOLUME)        return sel.vol_active;
   if(category == CAT_VOLATILITY)    return sel.vola_active;
   return 0;
}

inline void SetCategoryPassFlag(CategoryPassVector &passv, const int category, const int flag_value)
{
   if(category == CAT_INSTITUTIONAL) passv.inst_pass = flag_value;
   if(category == CAT_TREND)         passv.trend_pass = flag_value;
   if(category == CAT_MOMENTUM)      passv.mom_pass = flag_value;
   if(category == CAT_VOLUME)        passv.vol_pass = flag_value;
   if(category == CAT_VOLATILITY)    passv.vola_pass = flag_value;
}

inline bool UseCompactFinalVectorMode(const Settings &cfg)
{
   // Production default:
   // full vector = Base + Selected + Pass + Structure + Coverage + Aux
   //
   // Compact mode = Base + Selected + Pass + Structure + Coverage
   //
   // If you later add cfg.sigsel_compact_mode in Config.mqh,
   // wire it here and nowhere else.
   return false;
}

// ----------------------------------------------------------------------------
// Legacy compatibility API
// ----------------------------------------------------------------------------
// The array-based API remains in place for backward compatibility.
// New orchestration should prefer the raw-bank consumer API added below.
//
// This file is the only owner of:
// - one-per-category selected signal choice
// - institutional direct/proxy/none selection
// - degrade-aware vote relaxation
// - SignalStackGate_t / LocationPass_t build
//
// Strategies must not re-pick categories, re-run anti-echo, or invent local
// substitute vote rules.
// ----------------------------------------------------------------------------

// ============================================================================
// Public API
// ============================================================================

inline CategorySelectedVector ComputeCategorySelection(const double &raw[],
                                                      const double &z[],
                                                      const bool &valid_mask[],
                                                      const Settings &cfg,
                                                      const int dir_t)
{
   CategorySelectedVector out_sel;
   out_sel.Reset();

   if(!IsValidInputArraySizes(raw, z, valid_mask))
      return out_sel;

   // dir_t is included for future direction-aware selection tie-breaks.
   // Current selection logic remains magnitude-based per the spec.
   int dir_unused = dir_t;
   dir_unused = dir_unused;

   if(cfg.sigsel_selection_mode == Config::SELECTION_FIXED)
   {
      for(int c = 0; c < CAT_COUNT; c++)
      {
         if(!IsCategoryEnabledByConfig(cfg, c))
            continue;

         SelectFixedCategorySignal(cfg, c, raw, z, valid_mask, out_sel);
      }

      return out_sel;
   }

   for(int c = 0; c < CAT_COUNT; c++)
   {
      if(!IsCategoryEnabledByConfig(cfg, c))
         continue;

      SelectDynamicCategorySignal(cfg, c, raw, z, valid_mask, out_sel);
   }

   return out_sel;
}

inline CategoryPassVector ComputeCategoryPasses(const CategorySelectedVector &sel,
                                                const double &z[],
                                                const bool &valid_mask[],
                                                const Settings &cfg,
                                                const int dir_t,
                                                const double &raw[],
                                                const double plus_di = 0.0,
                                                const double minus_di = 0.0)
{
   CategoryPassVector out_pass;
   out_pass.Reset();

   if(ArraySize(raw) < RAW_COUNT || ArraySize(z) < RAW_COUNT || ArraySize(valid_mask) < RAW_COUNT)
      return out_pass;

   SignalSelectionThresholdView thv;
   LoadThresholdViewFromSettings(cfg, thv);

   InstitutionalSelectionDiagnostics inst_diag;
   BuildInstitutionalSelectionDiagnostics(cfg,
                                          raw,
                                          z,
                                          valid_mask,
                                          (cfg.sigsel_selection_mode == Config::SELECTION_FIXED),
                                          inst_diag);

   out_pass.inst_coverage                = inst_diag.inst_coverage;
   out_pass.inst_available               = inst_diag.inst_available;
   out_pass.inst_partial                 = inst_diag.inst_partial;
   out_pass.inst_unavailable             = inst_diag.inst_unavailable;
   out_pass.proxy_inst_available         = inst_diag.proxy_inst_available;
   out_pass.inst_sel_source              = inst_diag.inst_sel_source;
   out_pass.hard_inst_block              = inst_diag.hard_inst_block;
   out_pass.effective_min_category_votes = inst_diag.effective_min_category_votes;

   // Legacy array-path note:
   // these institutional coverage/degrade fields are later overridden by the
   // raw-bank consumer API so that canonical availability/degrade ownership
   // stays with RawSignalBank_t.

   for(int c = 0; c < CAT_COUNT; c++)
   {
      if(!IsCategoryEnabledByConfig(cfg, c))
      {
         SetCategoryPassFlag(out_pass, c, 0);
         continue;
      }

      int active_flag = CategorySelectedActiveFlag(sel, c);
      int raw_index   = CategorySelectedRawIndex(sel, c);
      double raw_value = CategorySelectedRawValue(sel, c);
      double z_value   = CategorySelectedZValue(sel, c);

      if(c == CAT_INSTITUTIONAL)
      {
         active_flag = inst_diag.selected_active;
         raw_index   = inst_diag.selected_raw_index;
         raw_value   = inst_diag.selected_raw_value;
         z_value     = inst_diag.selected_z_value;
      }

      if(active_flag <= 0)
         continue;

      if(!IsValidRawIndex(raw_index))
         continue;

      if(CategoryUsesDirectionalPass(c))
      {
         const int mapped_dir =
            DirMapSelectedSignal(raw_value, raw_index, plus_di, minus_di, thv);

         double th = GetCategoryThreshold(cfg, c);

         if(c == CAT_INSTITUTIONAL)
         {
            if(out_pass.inst_sel_source == INST_SIGNAL_SOURCE_PROXY)
               th = cfg.sigsel_th_inst_proxy;
            else
               th = cfg.sigsel_th_inst;
         }

         const int pass_flag =
            ((mapped_dir == dir_t) && (MathAbs(z_value) >= th) ? 1 : 0);

         SetCategoryPassFlag(out_pass, c, pass_flag);
      }
      else
      {
         const int regime =
            RegimeMapVol(raw_value, raw_index, raw[RAW_BB_WIDTH], thv);

         SetCategoryPassFlag(out_pass, c, (regime == 1 ? 1 : 0));
      }
   }

   ApplyCategoryEnableMaskToPassMeta(cfg, out_pass);

   if(!IsCategoryEnabledByConfig(cfg, CAT_INSTITUTIONAL))
   {
      out_pass.inst_sel_source = INST_SIGNAL_SOURCE_NONE;
      out_pass.inst_pass = 0;
   }
   else if(out_pass.inst_sel_source == INST_SIGNAL_SOURCE_NONE)
   {
      out_pass.inst_pass = 0;
   }

   out_pass.signal_stack_score =
      out_pass.inst_pass +
      out_pass.trend_pass +
      out_pass.mom_pass +
      out_pass.vol_pass +
      out_pass.vola_pass;

   if(cfg.sigsel_enable)
   {
      if(out_pass.hard_inst_block == 1)
      {
         out_pass.signal_stack_gate = 0;
      }
      else
      {
         out_pass.signal_stack_gate =
            (out_pass.signal_stack_score >= out_pass.effective_min_category_votes ? 1 : 0);
      }
   }
   else
   {
      out_pass.signal_stack_gate = 1;
   }

   out_pass.location_score = 0;

   if(raw[RAW_PIVOT_DIST] <= cfg.sigsel_loc_th_pivot)
      out_pass.location_score++;

   if(raw[RAW_SR_DIST] <= cfg.sigsel_loc_th_sr)
      out_pass.location_score++;

   if(raw[RAW_FIB_DIST] <= cfg.sigsel_loc_th_fib)
      out_pass.location_score++;

   if(raw[RAW_SD_SCORE] >= cfg.sigsel_loc_th_sd)
      out_pass.location_score++;

   if(raw[RAW_OB_SCORE] >= cfg.sigsel_loc_th_ob)
      out_pass.location_score++;

   if(raw[RAW_FVG_SCORE] >= cfg.sigsel_loc_th_fvg)
      out_pass.location_score++;

   if(raw[RAW_SWEEP_SCORE] >= cfg.sigsel_loc_th_sweep)
      out_pass.location_score++;

   if(((double)dir_t * raw[RAW_WYCKOFF_SCORE]) >= cfg.sigsel_loc_th_wyckoff)
      out_pass.location_score++;

   if(cfg.sigsel_enable)
      out_pass.location_pass =
         (out_pass.location_score >= cfg.sigsel_min_location_votes ? 1 : 0);
   else
      out_pass.location_pass = 1;

   return out_pass;
}

inline void ComputeContextVectors(BaseContextVector &base_ctx,
                                  StructureVector &struct_ctx,
                                  CoverageContextVector &coverage_ctx,
                                  AuxContextVector &aux_ctx,
                                  const CategoryPassVector &passv,
                                  const double &z[],
                                  const double &raw[])
{
   base_ctx.Reset();
   struct_ctx.Reset();
   coverage_ctx.Reset();
   aux_ctx.Reset();

   if(ArraySize(z) < RAW_COUNT || ArraySize(raw) < RAW_COUNT)
      return;

   // Base context vector: always on
   base_ctx.v[0] = z[RAW_BID];
   base_ctx.v[1] = z[RAW_ASK];
   base_ctx.v[2] = z[RAW_SPREAD];
   base_ctx.v[3] = z[RAW_REL_SPREAD];
   base_ctx.v[4] = z[RAW_MID];
   base_ctx.v[5] = z[RAW_MICRO];

   // Structure vector: always on
   struct_ctx.v[0]  = z[RAW_SWEEP_SCORE];
   struct_ctx.v[1]  = z[RAW_SPREAD_SHOCK];
   struct_ctx.v[2]  = z[RAW_SLIPPAGE];
   struct_ctx.v[3]  = z[RAW_DEPTH_FADE];
   struct_ctx.v[4]  = z[RAW_SD_SCORE];
   struct_ctx.v[5]  = z[RAW_OB_SCORE];
   struct_ctx.v[6]  = z[RAW_WYCKOFF_SCORE];
   struct_ctx.v[7]  = z[RAW_FVG_SCORE];
   struct_ctx.v[8]  = z[RAW_PIVOT_DIST];
   struct_ctx.v[9]  = z[RAW_SR_DIST];
   struct_ctx.v[10] = z[RAW_FIB_DIST];
   struct_ctx.v[11] = z[RAW_TREND_SLOPE];

   // Coverage / degrade context vector: always on
   coverage_ctx.v[0] = z[RAW_INST_COVERAGE];
   coverage_ctx.v[1] = (double)passv.inst_available;
   coverage_ctx.v[2] = (double)passv.inst_partial;
   coverage_ctx.v[3] = (double)passv.inst_unavailable;
   coverage_ctx.v[4] = (double)passv.proxy_inst_available;
   coverage_ctx.v[5] = (double)passv.inst_sel_source;
   coverage_ctx.v[6] = (double)passv.hard_inst_block;
   coverage_ctx.v[7] = (double)passv.effective_min_category_votes;

   // Auxiliary context vector: computed unconditionally, append by mode
   aux_ctx.v[0] = z[RAW_POV_GAP];
   aux_ctx.v[1] = z[RAW_DP_SHARE];
   aux_ctx.v[2] = z[RAW_ATS_SHARE];
   aux_ctx.v[3] = z[RAW_VENUE_MIX_ENTROPY];
   aux_ctx.v[4] = z[RAW_INTERNALISATION_PROXY];
   aux_ctx.v[5] = z[RAW_QUOTE_FADE];
   aux_ctx.v[6] = z[RAW_CORRELATION];
}

inline FinalIntegratedStateVector AssembleFinalVector(const CategorySelectedVector &sel,
                                                      const CategoryPassVector &passv,
                                                      const BaseContextVector &base_ctx,
                                                      const StructureVector &struct_ctx,
                                                      const CoverageContextVector &coverage_ctx,
                                                      const AuxContextVector &aux_ctx,
                                                      const Settings &cfg)
{
   FinalIntegratedStateVector out_vec;
   out_vec.Reset();

   const bool compact_mode = UseCompactFinalVectorMode(cfg);

   out_vec.FillFromComponents(base_ctx,
                              sel,
                              passv,
                              struct_ctx,
                              coverage_ctx,
                              aux_ctx,
                              compact_mode);

   return out_vec;
}

// ============================================================================
// Raw-bank consumer API
// ============================================================================

inline bool BuildSelectedState(const Settings &cfg,
                               const RawSignalBank_t &bank,
                               const int dir_t,
                               CategorySelectedVector &out_sel,
                               CategoryPassVector &out_pass,
                               SignalStackGate_t &out_stack_gate,
                               LocationPass_t &out_location_pass,
                               BaseContextVector &base_ctx,
                               StructureVector &struct_ctx,
                               CoverageContextVector &coverage_ctx,
                               AuxContextVector &aux_ctx,
                               const bool emit_logs = false,
                               const string log_tag = "CategorySelector")
{
   out_sel.Reset();
   out_pass.Reset();
   out_stack_gate.Reset();
   out_location_pass.Reset();
   base_ctx.Reset();
   struct_ctx.Reset();
   coverage_ctx.Reset();
   aux_ctx.Reset();

   if(!bank.valid)
      return false;

   double raw[];
   double z[];
   bool valid_mask[];

   BuildBankSelectionViews(bank, raw, z, valid_mask);

   out_sel = ComputeCategorySelection(raw, z, valid_mask, cfg, dir_t);

   ApplyInstitutionalAntiEchoFromBank(cfg, bank, out_sel);

   out_pass = ComputeCategoryPasses(out_sel,
                                    z,
                                    valid_mask,
                                    cfg,
                                    dir_t,
                                    raw,
                                    bank.plus_di,
                                    bank.minus_di);

   OverlayInstitutionalPassMetaFromBank(cfg, bank, out_sel, out_pass);
   RefreshStackAndLocationGates(cfg, out_pass);

   ComputeContextVectors(base_ctx,
                         struct_ctx,
                         coverage_ctx,
                         aux_ctx,
                         out_pass,
                         z,
                         raw);

   FillSignalStackGateFromPass(out_pass, out_stack_gate);
   FillLocationPassFromBank(out_pass, bank, out_location_pass);

   if(emit_logs)
      EmitSelectionDiagnosticLog(out_sel, out_pass, bank, log_tag);

   return true;
}

inline bool BuildSelectedState(const Settings &cfg,
                               const RawSignalBank_t &bank,
                               const int dir_t,
                               CategorySelectedVector &out_sel,
                               CategoryPassVector &out_pass,
                               SignalStackGate_t &out_stack_gate,
                               LocationPass_t &out_location_pass,
                               BaseContextVector &base_ctx,
                               StructureVector &struct_ctx,
                               CoverageContextVector &coverage_ctx,
                               AuxContextVector &aux_ctx,
                               FinalIntegratedStateVector &out_final,
                               const bool emit_logs = false,
                               const string log_tag = "CategorySelector")
{
   out_final.Reset();

   if(!BuildSelectedState(cfg,
                          bank,
                          dir_t,
                          out_sel,
                          out_pass,
                          out_stack_gate,
                          out_location_pass,
                          base_ctx,
                          struct_ctx,
                          coverage_ctx,
                          aux_ctx,
                          emit_logs,
                          log_tag))
   {
      return false;
   }

   out_final = AssembleFinalVector(out_sel,
                                   out_pass,
                                   base_ctx,
                                   struct_ctx,
                                   coverage_ctx,
                                   aux_ctx,
                                   cfg);

   return true;
}

} // namespace CategorySelector

#endif