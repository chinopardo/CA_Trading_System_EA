#ifndef CA_CATEGORY_SELECTOR_MQH
#define CA_CATEGORY_SELECTOR_MQH

#include "Config.mqh"
#include "Types.mqh"

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

   int count = ArraySize(candidate_list);
   if(count <= 0)
      return;

   for(int i = 0; i < count; i++)
   {
      const int raw_index = candidate_list[i];
      if(!IsCandidateValid(raw_index, raw, z, valid_mask))
         continue;

      double weight = GetCategoryCandidateWeightByPosition(cfg, category, i);
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

inline void SelectFixedCategorySignal(const Settings &cfg,
                                      const int category,
                                      const double &raw[],
                                      const double &z[],
                                      const bool &valid_mask[],
                                      CategorySelectedVector &out_sel)
{
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
   if(cfg.sigsel_inst_selection_mode == Config::INST_SELECTION_DIRECT_FULL)
   {
      int inst_candidates[];
      SigSel_GetInstitutionalCandidates(inst_candidates);

      int best_idx = -1;
      double best_raw = 0.0;
      double best_z = 0.0;
      double best_score = -1.0;

      SelectBestCandidateFromList(cfg,
                                  CAT_INSTITUTIONAL,
                                  raw,
                                  z,
                                  valid_mask,
                                  inst_candidates,
                                  best_idx,
                                  best_raw,
                                  best_z,
                                  best_score);

      if(best_idx >= 0)
         SetCategorySelection(out_sel, CAT_INSTITUTIONAL, best_idx, best_raw, best_z, 1);

      return;
   }

   int orderbook_candidates[];
   int tradeflow_candidates[];
   int impact_candidates[];
   int execquality_candidates[];

   SigSel_GetInstitutionalOrderBookCandidates(orderbook_candidates);
   SigSel_GetInstitutionalTradeFlowCandidates(tradeflow_candidates);
   SigSel_GetInstitutionalImpactCandidates(impact_candidates);
   SigSel_GetInstitutionalExecQualityCandidates(execquality_candidates);

   int sf_best_idx[INST_SUBFAMILY_COUNT];
   double sf_best_raw[INST_SUBFAMILY_COUNT];
   double sf_best_z[INST_SUBFAMILY_COUNT];
   double sf_best_score[INST_SUBFAMILY_COUNT];

   for(int i = 0; i < INST_SUBFAMILY_COUNT; i++)
   {
      sf_best_idx[i]   = -1;
      sf_best_raw[i]   = 0.0;
      sf_best_z[i]     = 0.0;
      sf_best_score[i] = -1.0;
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

   int final_best_idx = -1;
   double final_best_raw = 0.0;
   double final_best_z = 0.0;
   double final_best_score = -1.0;

   for(int sf = 0; sf < INST_SUBFAMILY_COUNT; sf++)
   {
      if(sf_best_idx[sf] < 0)
         continue;

      double sf_weight = GetInstitutionalSubfamilyWeight(cfg, sf);
      if(sf_weight < 0.0)
         sf_weight = 0.0;

      const double score = MathAbs(sf_best_z[sf]) * sf_weight;
      if(score > final_best_score)
      {
         final_best_score = score;
         final_best_idx   = sf_best_idx[sf];
         final_best_raw   = sf_best_raw[sf];
         final_best_z     = sf_best_z[sf];
      }
   }

   if(final_best_idx >= 0)
      SetCategorySelection(out_sel, CAT_INSTITUTIONAL, final_best_idx, final_best_raw, final_best_z, 1);
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
   // full vector = Base + Selected + Pass + Structure + Aux
   //
   // If you later add cfg.sigsel_compact_mode in Config.mqh,
   // wire it here and nowhere else.
   return false;
}

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
   // Current selection logic is magnitude-based per the spec.
   int _dir_unused = dir_t;
   _dir_unused = _dir_unused;

   if(cfg.sigsel_selection_mode == Config::SELECTION_FIXED)
   {
      for(int c = 0; c < CAT_COUNT; c++)
         SelectFixedCategorySignal(cfg, c, raw, z, valid_mask, out_sel);

      return out_sel;
   }

   for(int c = 0; c < CAT_COUNT; c++)
      SelectDynamicCategorySignal(cfg, c, raw, z, valid_mask, out_sel);

   return out_sel;
}

inline CategoryPassVector ComputeCategoryPasses(const CategorySelectedVector &sel,
                                                const double &z[],
                                                const Settings &cfg,
                                                const int dir_t,
                                                const double &raw[],
                                                const double plus_di = 0.0,
                                                const double minus_di = 0.0)
{
   CategoryPassVector out_pass;
   out_pass.Reset();

   if(ArraySize(raw) < RAW_COUNT || ArraySize(z) < RAW_COUNT)
      return out_pass;

   SignalSelectionThresholdView thv;
   LoadThresholdViewFromSettings(cfg, thv);

   for(int c = 0; c < CAT_COUNT; c++)
   {
      const int active_flag = CategorySelectedActiveFlag(sel, c);
      if(active_flag <= 0)
         continue;

      const int raw_index = CategorySelectedRawIndex(sel, c);
      const double raw_value = CategorySelectedRawValue(sel, c);
      const double z_value = CategorySelectedZValue(sel, c);

      if(!IsValidRawIndex(raw_index))
         continue;

      if(CategoryUsesDirectionalPass(c))
      {
         const int mapped_dir =
            DirMapSelectedSignal(raw_value, raw_index, plus_di, minus_di, thv);

         const double th = GetCategoryThreshold(cfg, c);
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

   out_pass.signal_stack_score =
      out_pass.inst_pass +
      out_pass.trend_pass +
      out_pass.mom_pass +
      out_pass.vol_pass +
      out_pass.vola_pass;

   if(cfg.sigsel_enable)
      out_pass.signal_stack_gate =
         (out_pass.signal_stack_score >= cfg.sigsel_min_category_votes ? 1 : 0);
   else
      out_pass.signal_stack_gate = 1;

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
                                  AuxContextVector &aux_ctx,
                                  const double &z[],
                                  const double &raw[])
{
   base_ctx.Reset();
   struct_ctx.Reset();
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
                              aux_ctx,
                              compact_mode);

   return out_vec;
}

} // namespace CategorySelector

#endif