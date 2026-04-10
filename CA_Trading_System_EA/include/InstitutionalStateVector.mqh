
#ifndef CA_INSTITUTIONALSTATEVECTOR_MQH
#define CA_INSTITUTIONALSTATEVECTOR_MQH

#include "Config.mqh"
#include "Types.mqh"

#include "VSA.mqh"
#include "VWAP.mqh"
#include "AutoVolatility.mqh"
#include "VolumeProfile.mqh"
#include "FootprintProxy.mqh"
#include "DeltaProxy.mqh"
#include "FVG.mqh"
#include "LiquidityCues.mqh"
#include "OrderBookImbalance.mqh"
#include "StructureSDOB.mqh"
#include "Indicators.mqh"
#include "PivotsLevels.mqh"
#include "Fibonacci.mqh"
#include "Trendlines.mqh"
#include "Correlation.mqh"
#include "WyckoffCycle.mqh"

namespace ISV
{
enum InstitutionalStateVectorSlot
{
   ISV_BID = 0,
   ISV_ASK = 1,
   ISV_SPREAD = 2,
   ISV_REL_SPREAD = 3,
   ISV_MID = 4,
   ISV_MICRO = 5,
   ISV_DOM_BID_K = 6,
   ISV_DOM_ASK_K = 7,
   ISV_DOM_TOT_K = 8,
   ISV_DOM_SKEW_K = 9,
   ISV_DOM_PRESSURE_K = 10,
   ISV_BUY_FLOW = 11,
   ISV_SELL_FLOW = 12,
   ISV_NET_FLOW = 13,
   ISV_FLOW_IMB = 14,
   ISV_SIGNED_FLOW = 15,
   ISV_CVD = 16,
   ISV_OBI_1 = 17,
   ISV_OBI_K = 18,
   ISV_OFI = 19,
   ISV_BETA_T = 20,
   ISV_LAMBDA_T = 21,
   ISV_VPIN = 22,
   ISV_ABS_PLUS = 23,
   ISV_ABS_MINUS = 24,
   ISV_REPL_BID = 25,
   ISV_REPL_ASK = 26,
   ISV_RESIL_T = 27,
   ISV_IMPACT_Q = 28,
   ISV_MID_MINUS_VWAP = 29,
   ISV_MID_MINUS_TWAP = 30,
   ISV_POV_GAP = 31,
   ISV_RV = 32,
   ISV_BV = 33,
   ISV_JUMP = 34,
   ISV_SIGMA_P = 35,
   ISV_SIGMA_GK = 36,
   ISV_CLV = 37,
   ISV_VOL_Z = 38,
   ISV_ER = 39,
   ISV_FOOTPRINT_DELTA = 40,
   ISV_POC_DIST = 41,
   ISV_VA_STATE = 42,
   ISV_TPO_STATE = 43,
   ISV_SWEEP_SCORE = 44,
   ISV_SPREAD_SHOCK = 45,
   ISV_SLIPPAGE = 46,
   ISV_DEPTH_FADE = 47,
   ISV_DP_SHARE = 48,
   ISV_ATS_SHARE = 49,
   ISV_VENUE_MIX_ENTROPY = 50,
   ISV_INTERNALISATION_PROXY = 51,
   ISV_QUOTE_FADE = 52,
   ISV_SD_SCORE = 53,
   ISV_OB_SCORE = 54,
   ISV_WYCKOFF_SCORE = 55,
   ISV_FVG_SCORE = 56,
   ISV_RSI = 57,
   ISV_MACD = 58,
   ISV_MACD_SIGNAL = 59,
   ISV_MACD_HIST = 60,
   ISV_STOCH_RSI = 61,
   ISV_ROC = 62,
   ISV_ADX = 63,
   ISV_RHO = 64,
   ISV_SR_DIST = 65,
   ISV_PIVOT_DIST = 66,
   ISV_FIB_DIST = 67,
   ISV_TREND_SLOPE = 68,
   ISV_SLOT_COUNT = 69
};

inline double Clamp01(const double v)
{
   if(v < 0.0) return 0.0;
   if(v > 1.0) return 1.0;
   return v;
}

inline double ClampSym(const double v, const double a=1.0)
{
   if(v >  a) return  a;
   if(v < -a) return -a;
   return v;
}

inline double SafeDiv(const double num, const double den, const double fallback=0.0)
{
   if(MathAbs(den) <= 1e-12)
      return fallback;
   return (num / den);
}

inline bool IsFinite(const double v)
{
   return MathIsValidNumber(v);
}

inline double FiniteOrZero(const double v)
{
   if(!IsFinite(v))
      return 0.0;
   return v;
}

inline double Sigmoid(const double x)
{
   if(x >= 40.0) return 1.0;
   if(x <= -40.0) return 0.0;
   return (1.0 / (1.0 + MathExp(-x)));
}

inline double TanhLike(const double x)
{
   if(x >= 20.0) return 1.0;
   if(x <= -20.0) return -1.0;
   const double ex = MathExp(2.0 * x);
   return ((ex - 1.0) / (ex + 1.0));
}

inline double PointValue(const string sym)
{
   double pt = 0.0;
   if(!SymbolInfoDouble(sym, SYMBOL_POINT, pt) || pt <= 0.0)
      pt = 0.00001;
   return pt;
}

inline double TickVolumeAt(const string sym,
                           const ENUM_TIMEFRAMES tf,
                           const int shift)
{
   long v = iVolume(sym, tf, shift);
   if(v < 0) v = 0;
   return (double)v;
}

inline double ATRPrice(const string sym,
                       const ENUM_TIMEFRAMES tf,
                       const int period,
                       const int shift)
{
   const double pt = PointValue(sym);
   const double atr_pts = Indi::ATRPoints(sym, tf, period, shift);
   if(atr_pts <= 0.0 || pt <= 0.0)
      return 0.0;
   return (atr_pts * pt);
}

inline double BinaryEntropy01(const double p_raw)
{
   double p = p_raw;
   if(p < 1e-9) p = 1e-9;
   if(p > 1.0 - 1e-9) p = 1.0 - 1e-9;
   return (-(p * MathLog(p) + (1.0 - p) * MathLog(1.0 - p)) / MathLog(2.0));
}

inline bool SymbolLooksOTCFragmented(const string sym)
{
   string s = sym;
   StringToUpper(s);
   if(StringFind(s, "XAU") >= 0) return true;
   if(StringFind(s, "XAG") >= 0) return true;
   if(StringFind(s, "GOLD") >= 0) return true;
   if(StringFind(s, "SILVER") >= 0) return true;
   if(StringLen(s) == 6) return true;
   return false;
}

inline void FillPseudoDepthFromOBI(const double obi1,
                                   const double obik,
                                   const double local_depth_proxy01,
                                   double &dom_bid_1,
                                   double &dom_ask_1,
                                   double &dom_tot_1,
                                   double &dom_skew_1,
                                   double &dom_pressure_1,
                                   double &dom_bid_k,
                                   double &dom_ask_k,
                                   double &dom_tot_k,
                                   double &dom_skew_k,
                                   double &dom_pressure_k)
{
   const double scale = MathMax(0.05, Clamp01(local_depth_proxy01));
   dom_bid_1 = 0.5 * (1.0 + ClampSym(obi1, 1.0)) * scale;
   dom_ask_1 = 0.5 * (1.0 - ClampSym(obi1, 1.0)) * scale;
   dom_tot_1 = dom_bid_1 + dom_ask_1;
   dom_skew_1 = ClampSym(obi1, 1.0);
   dom_pressure_1 = dom_bid_1 - dom_ask_1;

   dom_bid_k = 0.5 * (1.0 + ClampSym(obik, 1.0)) * scale;
   dom_ask_k = 0.5 * (1.0 - ClampSym(obik, 1.0)) * scale;
   dom_tot_k = dom_bid_k + dom_ask_k;
   dom_skew_k = ClampSym(obik, 1.0);
   dom_pressure_k = dom_bid_k - dom_ask_k;
}

inline double RegressionSlopeRaw(const string sym,
                                 const ENUM_TIMEFRAMES tf,
                                 const int lookback,
                                 const int shift)
{
   int n = lookback;
   if(n < 10) n = 10;
   if(n > 200) n = 200;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int got = CopyRates(sym, tf, shift, n, rates);
   if(got < 5)
      return 0.0;

   double sum_x = 0.0;
   double sum_y = 0.0;
   double sum_xx = 0.0;
   double sum_xy = 0.0;

   for(int i = 0; i < got; i++)
   {
      const double x = (double)i;
      const double y = rates[got - 1 - i].close;
      sum_x += x;
      sum_y += y;
      sum_xx += x * x;
      sum_xy += x * y;
   }

   const double den = ((double)got * sum_xx - sum_x * sum_x);
   if(MathAbs(den) <= 1e-12)
      return 0.0;

   return (((double)got * sum_xy - sum_x * sum_y) / den);
}

struct ZWindow
{
   double values[];
   int    head;
   int    count;
   int    cap;

   void Reset(const int window)
   {
      cap = window;
      if(cap < 5) cap = 5;
      ArrayResize(values, cap);
      ArrayInitialize(values, 0.0);
      head = 0;
      count = 0;
   }

   void Push(const double v)
   {
      if(cap <= 0)
         return;

      values[head] = v;
      head++;
      if(head >= cap)
         head = 0;

      if(count < cap)
         count++;
   }

   double Mean() const
   {
      if(count <= 0)
         return 0.0;

      double s = 0.0;
      for(int i = 0; i < count; i++)
         s += values[i];
      return (s / (double)count);
   }

   double StdDev(const double mean, const double eps) const
   {
      if(count <= 1)
         return eps;

      double v = 0.0;
      for(int i = 0; i < count; i++)
      {
         const double d = values[i] - mean;
         v += d * d;
      }

      v /= (double)(count - 1);
      if(v < eps * eps)
         v = eps * eps;
      return MathSqrt(v);
   }

   double ZScoreSample(const double x,
                       const double eps,
                       const int min_samples,
                       const double clamp_abs) const
   {
      if(count < min_samples)
         return 0.0;

      const double m = Mean();
      const double sd = StdDev(m, eps);
      double z = (x - m) / sd;

      if(clamp_abs > 0.0)
         z = ClampSym(z, clamp_abs);

      return z;
   }
};

struct Runtime
{
   bool initialized;
   datetime last_bar_time;
   double   last_raw[ISV_SLOT_COUNT];
   double   last_z[ISV_SLOT_COUNT];
   ZWindow  slots[ISV_SLOT_COUNT];
   DeltaX::OrderFlowSeriesCacheBridge flow_bridge;

   void Reset(const int z_window)
   {
      initialized = true;
      last_bar_time = 0;

      for(int i = 0; i < ISV_SLOT_COUNT; i++)
      {
         last_raw[i] = 0.0;
         last_z[i] = 0.0;
         slots[i].Reset(z_window);
      }

      flow_bridge.Reset();
   }
};

struct BuildConfig
{
   int    closed_shift;
   int    z_window;
   int    z_min_samples;
   double z_epsilon;
   double z_cap_abs;

   int    flow_lookback;
   int    twap_lookback_bars;
   int    indicator_lookback;
   int    atr_period;
   int    trend_reg_lookback;

   int    corr_len;
   int    profile_lookback_bars;
   int    profile_bin_points;
   double profile_value_area_pct;

   int    dom_band_points;

   double participation_target01;
   double impact_order_qty;
   double size_max;

   double theta_alpha;
   double theta_exec;
   double theta_risk;
   double theta_vpin;
   double theta_resil;
   double min_state_quality01;

   bool   enable_market_profile;

   void SetDefaults()
   {
      closed_shift = 1;
      z_window = 80;
      z_min_samples = 20;
      z_epsilon = 1e-8;
      z_cap_abs = 6.0;

      flow_lookback = 60;
      twap_lookback_bars = 60;
      indicator_lookback = 80;
      atr_period = 14;
      trend_reg_lookback = 40;

      corr_len = 60;
      profile_lookback_bars = 200;
      profile_bin_points = 10;
      profile_value_area_pct = 0.70;

      dom_band_points = 25;

      participation_target01 = 0.10;
      impact_order_qty = 1.0;
      size_max = 1.0;

      theta_alpha = 0.55;
      theta_exec = 0.40;
      theta_risk = 0.60;
      theta_vpin = 0.65;
      theta_resil = 0.15;
      min_state_quality01 = 0.20;

      enable_market_profile = false;
   }
};

inline void LoadBuildConfigFromSettings(const Settings &cfg,
                                        BuildConfig &out)
{
   out.SetDefaults();

   if(cfg.scan_obi_z_window > 0)
      out.z_window = cfg.scan_obi_z_window;

   if(cfg.scan_obi_z_min_samples > 0)
      out.z_min_samples = cfg.scan_obi_z_min_samples;

   if(cfg.scan_obi_depth_points > 0)
      out.dom_band_points = cfg.scan_obi_depth_points;

   if(cfg.scan_obi_of_delta_lookback > 0)
      out.flow_lookback = cfg.scan_obi_of_delta_lookback;

   if(cfg.scan_inst_twap_lookback > 0)
      out.twap_lookback_bars = cfg.scan_inst_twap_lookback;

   if(cfg.atr_period > 1)
      out.atr_period = cfg.atr_period;

   if(cfg.scan_vp_lookback_bars > 0)
      out.profile_lookback_bars = cfg.scan_vp_lookback_bars;

   if(cfg.scan_vp_bin_points > 0)
      out.profile_bin_points = cfg.scan_vp_bin_points;

   if(cfg.scan_vp_value_area_pct > 0.0)
      out.profile_value_area_pct = cfg.scan_vp_value_area_pct;

   if(cfg.scan_inst_pov_target_participation01 > 0.0)
      out.participation_target01 = Clamp01(cfg.scan_inst_pov_target_participation01);

   if(cfg.scan_inst_alpha_threshold > 0.0)
      out.theta_alpha = cfg.scan_inst_alpha_threshold;

   if(cfg.scan_inst_execution_threshold > 0.0)
      out.theta_exec = cfg.scan_inst_execution_threshold;

   if(cfg.scan_inst_risk_threshold > 0.0)
      out.theta_risk = cfg.scan_inst_risk_threshold;

   out.enable_market_profile = cfg.scan_inst_market_profile_enable;
}

inline void LoadOBISettings(const Settings &cfg,
                            OBI::Settings &out)
{
   out = OBI::Settings();

   out.max_levels                     = cfg.scan_obi_max_levels;
   out.min_total_volume               = cfg.scan_obi_min_tot_vol;
   out.zone_pad_points                = cfg.scan_obi_zone_pad_points;
   out.min_edge_distance_points       = cfg.scan_obi_min_edge_distance_points;
   out.cache_ms                       = cfg.scan_obi_cache_ms;
   out.nodata_cache_ms                = cfg.scan_obi_nodata_cache_ms;
   out.retry_cooldown_ms              = cfg.scan_obi_retry_cooldown_ms;

   out.obi_mode                       = cfg.scan_obi_mode;
   out.top_levels_per_side            = cfg.scan_obi_top_levels;
   out.weighted_enable                = cfg.scan_obi_weighted_enable;
   out.weight_half_life_points        = cfg.scan_obi_weight_half_life_points;
   out.weight_ref                     = cfg.scan_obi_weight_ref;

   out.obi_basis_mode                 = cfg.scan_obi_basis_mode;
   out.obi_norm_mode                  = cfg.scan_obi_norm_mode;
   out.obi_z_window                   = cfg.scan_obi_z_window;
   out.obi_z_min_samples              = cfg.scan_obi_z_min_samples;
   out.obi_z_clamp_abs                = cfg.scan_obi_z_clamp_abs;

   out.obi_transform_mode             = cfg.scan_obi_transform_mode;
   out.obi_logistic_k                 = cfg.scan_obi_logistic_k;
   out.obi_power_gamma                = cfg.scan_obi_power_gamma;

   out.obi_spread_min_points          = cfg.scan_obi_spread_min_points;
   out.obi_spread_adjust_cap          = cfg.scan_obi_spread_adjust_cap;

   out.ofi_use_full_depth             = (cfg.scan_obi_ofi_mode != 0);
   out.ofi_levels_n                   = cfg.scan_obi_ofi_levels;
   out.ofi_norm_mode                  = cfg.scan_obi_ofi_norm_mode;

   out.of_delta_source_mode           = cfg.scan_obi_of_delta_source_mode;
   out.of_delta_lookback              = cfg.scan_obi_of_delta_lookback;
   out.of_delta_use_fp_ticks_preferred= cfg.scan_obi_of_delta_use_fp_ticks_preferred;
   out.of_delta_min_total             = cfg.scan_obi_of_delta_min_total;

   out.lpi_enable                     = cfg.scan_obi_lpi_enable;
   out.lpi_alpha                      = cfg.scan_obi_lpi_alpha;
   out.lpi_beta                       = cfg.scan_obi_lpi_beta;

   out.persistence_mode               = cfg.scan_obi_persistence_mode;
   out.persistence_len                = cfg.scan_obi_persistence_len;
   out.persistence_gamma              = cfg.scan_obi_persistence_gamma;
   out.persistence_threshold          = cfg.scan_obi_persistence_threshold;

   out.absorption_enable              = cfg.scan_obi_absorption_enable;
   out.absorption_lookback            = cfg.scan_obi_absorption_lookback;
   out.absorption_price_eps_points    = cfg.scan_obi_absorption_price_eps_points;
   out.absorption_z_clamp_abs         = cfg.scan_obi_absorption_z_clamp_abs;

   out.score_enable                   = cfg.scan_obi_score_enable;
   out.score_w1_zobi                  = cfg.scan_obi_score_w1_zobi;
   out.score_w2_ndelta                = cfg.scan_obi_score_w2_ndelta;
   out.score_w3_zabs                  = cfg.scan_obi_score_w3_zabs;
   out.score_w4_persistence           = cfg.scan_obi_score_w4_persistence;
   out.score_z_window                 = cfg.scan_obi_score_z_window;
   out.score_z_min_samples            = cfg.scan_obi_score_z_min_samples;
   out.score_z_clamp_abs              = cfg.scan_obi_score_z_clamp_abs;

   out.fx_fxlpi_enable                = cfg.scan_obi_fx_fxlpi_enable;
   out.fx_spread_z_window             = cfg.scan_obi_fx_spread_z_window;
   out.fx_spread_z_min_samples        = cfg.scan_obi_fx_spread_z_min_samples;
   out.fx_obi_weight                  = cfg.scan_obi_fx_obi_weight;
   out.fx_spread_weight               = cfg.scan_obi_fx_spread_weight;
   out.signal_metric_mode             = cfg.scan_obi_signal_metric_mode;

   out.microprice_enable              = cfg.scan_obi_microprice_enable;
   out.microprice_min_levels          = cfg.scan_obi_microprice_min_levels;
   out.microprice_smoothing_mode      = cfg.scan_obi_microprice_smoothing_mode;
   out.microprice_smoothing_period    = cfg.scan_obi_microprice_smoothing_period;

   out.queue_imbalance_clamp_abs      = cfg.scan_obi_queue_imbalance_clamp_abs;
   out.queue_norm_mode                = cfg.scan_obi_queue_norm_mode;
   out.queue_z_window                 = cfg.scan_obi_queue_z_window;
   out.queue_z_min_samples            = cfg.scan_obi_queue_z_min_samples;

   out.resiliency_enable              = cfg.scan_obi_resiliency_enable;
   out.resiliency_shock_min_abs       = cfg.scan_obi_resiliency_shock_min_abs;
   out.resiliency_refill_window_sec   = cfg.scan_obi_resiliency_refill_window_sec;
   out.resiliency_half_life_max_sec   = cfg.scan_obi_resiliency_half_life_max_sec;
   out.resiliency_depth_recovery_mode = cfg.scan_obi_resiliency_depth_recovery_mode;
   out.resiliency_spread_recovery_weight = cfg.scan_obi_resiliency_spread_recovery_weight;

   out.impact_beta_enable             = cfg.scan_ofx_impact_enable;
   out.impact_beta_window             = cfg.scan_ofx_impact_window;
   out.impact_beta_ew_alpha           = cfg.scan_ofx_impact_ew_alpha;
   out.impact_beta_min_samples        = cfg.scan_ofx_impact_min_samples;
   out.impact_beta_depth_adjust_enable= cfg.scan_ofx_impact_depth_adjust_enable;
   out.impact_beta_smoothing_period   = cfg.scan_ofx_impact_smoothing_period;
   out.impact_beta_weight_mode        = cfg.scan_ofx_impact_weight_mode;
   out.impact_beta_weight_decay       = cfg.scan_ofx_impact_weight_decay;
   out.impact_beta_concave_enable     = cfg.scan_ofx_impact_concave_enable;
   out.impact_beta_psi                = cfg.scan_ofx_impact_concavity_psi;
}

inline void LoadVWAPConfig(const Settings &cfg,
                           const ENUM_TIMEFRAMES tf,
                           VWAPConfig &out)
{
   VWAP::DefaultConfig(out);
   out.tf = tf;
   out.atrPeriod = MathMax(2, cfg.atr_period);
   out.volEstimatorLB = MathMax(10, cfg.scan_inst_bv_lookback);
   out.vpinBucketLB = MathMax(20, cfg.scan_inst_twap_lookback);
   out.vpinBucketSizeMult = 1.0;
   out.vpinMinFullBuckets = 2;
}

inline void LoadVPParams(const Settings &cfg,
                         VP::Params &out)
{
   out = VP::ParamsDefault();
   out.lookback_bars = MathMax(20, cfg.scan_vp_lookback_bars);
   out.bin_points = MathMax(1, cfg.scan_vp_bin_points);
   out.value_area_pct = cfg.scan_vp_value_area_pct;
   out.profile_type = cfg.scan_vp_profile_mode;
   out.session_mode = cfg.scan_vp_session_mode;
   out.anchor_minute_utc = cfg.scan_vp_anchor_minute_utc;
   out.composite_sessions = cfg.scan_vp_composite_sessions;
   out.range_from = cfg.scan_vp_range_from_ts;
   out.range_to = cfg.scan_vp_range_to_ts;
   out.distribute_by_range = cfg.scan_vp_distribute_range;
   out.value_area_method = cfg.scan_vp_value_area_method;
   out.vwap_source_mode = cfg.scan_vp_vwap_source_mode;
   out.row_height_mode = cfg.scan_vp_row_height_mode;
   out.row_height_atr_period = MathMax(2, cfg.atr_period);
   out.row_height_atr_mult = 0.25;
   out.compute_vwap = true;
   out.compute_tpo = cfg.scan_inst_market_profile_enable;
   out.compute_developing_poc = true;
   out.compute_shape = true;
   out.compute_nodes_full = true;
   out.delta_mode = true;
   out.use_vsa = true;
   out.vol_estimator_lb = MathMax(10, cfg.scan_inst_bv_lookback);
   out.vpin_bucket_lb = MathMax(20, cfg.scan_inst_twap_lookback);
   out.vpin_bucket_size_mult = 1.0;
   out.vpin_min_full_buckets = 2;
   out.allow_tick_footprint = true;
}

inline void LoadVSAParams(VSA::ClassicalParams &out)
{
   out.SetDefaults();
   out.use_true_range = false;
   out.use_percentile_rank = true;
   out.use_session_volume_norm = true;
   out.spread_zscore_enable = true;
   out.absorption_zscore_enable = true;
}

inline void LoadTrendlinesConfig(TrendlinesConfig &out)
{
   Trendlines_DefaultConfig(out);
   out.lookback_bars = 400;
   out.atr_period = 14;
}

inline void LoadSeriesUpdateParams(DeltaX::OrderFlowSeriesUpdateParams &out)
{
   out.Reset();
   out.cvd_ema_len = 20;
   out.delta_ema_len = 20;
   out.exhaust_lb = 8;
   out.update_exhaust_ref = true;
}

inline void LoadToxicityUpdateParams(const Settings &cfg,
                                     DeltaX::OrderFlowToxicityUpdateParams &out)
{
   out.Reset();
   out.bucket_window = MathMax(10, cfg.scan_ofx_toxicity_lookback);
   out.ew_len = MathMax(2, cfg.scan_ofx_toxicity_bucket_size);
   out.persistence_len = MathMax(2, cfg.scan_obi_persistence_len);
   out.mode = cfg.scan_ofx_toxicity_bucket_mode;
   out.min_total_vol = 1.0;
   out.equal_volume_bucket_size = MathMax(10.0, (double)cfg.scan_ofx_toxicity_bucket_size);
   out.allow_true_vpin = true;
}

inline void LoadImpactUpdateParams(const Settings &cfg,
                                   DeltaX::OrderFlowImpactUpdateParams &out)
{
   out.Reset();
   out.window = MathMax(5, cfg.scan_ofx_impact_window);
   out.min_samples = MathMax(2, cfg.scan_ofx_impact_min_samples);
   out.smoothing_len = MathMax(0, cfg.scan_ofx_impact_smoothing_period);
   out.mode = 1;
   out.ew_alpha = cfg.scan_ofx_impact_ew_alpha;
   out.depth_adjust_enable = cfg.scan_ofx_impact_depth_adjust_enable;
   out.depth_ref = 1.0;
   out.weight_mode = cfg.scan_ofx_impact_weight_mode;
   out.weight_decay = cfg.scan_ofx_impact_weight_decay;
   out.concave_enable = cfg.scan_ofx_impact_concave_enable;
   out.concavity_psi = cfg.scan_ofx_impact_concavity_psi;
}

struct Result
{
   bool valid;
   string symbol;
   ENUM_TIMEFRAMES tf;
   datetime bar_time;

   bool dom_proxy_used;
   bool flow_proxy_used;
   bool tick_volume_proxy_used;
   bool footprint_proxy_used;
   bool profile_proxy_used;

   int  direction_dir11;

   double raw[ISV_SLOT_COUNT];
   double z[ISV_SLOT_COUNT];

   double alpha_t;
   double exec_t;
   double risk_t;
   bool   trade_gate;
   double size01;

   double observability01;
   double observability_penalty01;
   double venue_coverage01;

   MicrostructureStats         ms;
   InstitutionalStateSnapshot  snap;
   OrderFlowDisplaySnapshot    ofx;

   void Reset()
   {
      valid = false;
      symbol = "";
      tf = PERIOD_CURRENT;
      bar_time = 0;

      dom_proxy_used = false;
      flow_proxy_used = false;
      tick_volume_proxy_used = false;
      footprint_proxy_used = false;
      profile_proxy_used = false;

      direction_dir11 = 0;

      for(int i = 0; i < ISV_SLOT_COUNT; i++)
      {
         raw[i] = 0.0;
         z[i] = 0.0;
      }

      alpha_t = 0.0;
      exec_t = 0.0;
      risk_t = 1.0;
      trade_gate = false;
      size01 = 0.0;

      observability01 = 0.0;
      observability_penalty01 = 1.0;
      venue_coverage01 = 0.0;

      ms.Reset();
      snap.Reset();
      ofx.Reset();
   }
};

inline void NormalizeRawVector(const BuildConfig &cfg,
                               Runtime &rt,
                               const datetime bar_time,
                               const double &raw[],
                               double &out_z[])
{
   const bool same_bar = (rt.initialized && rt.last_bar_time == bar_time);

   if(same_bar)
   {
      for(int i = 0; i < ISV_SLOT_COUNT; i++)
         out_z[i] = rt.last_z[i];
      return;
   }

   for(int i = 0; i < ISV_SLOT_COUNT; i++)
   {
      double x = raw[i];
      if(!IsFinite(x))
         x = 0.0;

      out_z[i] = rt.slots[i].ZScoreSample(x, cfg.z_epsilon, cfg.z_min_samples, cfg.z_cap_abs);
      rt.slots[i].Push(x);
      rt.last_raw[i] = x;
      rt.last_z[i] = out_z[i];
   }

   rt.last_bar_time = bar_time;
}

inline void BuildHeads(const Settings &cfg,
                       const BuildConfig &bcfg,
                       const double &raw[],
                       const double &z[],
                       Result &out)
{
   const double benchmark_z =
      0.50 * z[ISV_MID_MINUS_VWAP] +
      0.50 * z[ISV_MID_MINUS_TWAP];

   const double profile_z =
      0.60 * z[ISV_VA_STATE] +
      0.40 * z[ISV_TPO_STATE];

   const double structure_z =
      0.30 * z[ISV_SD_SCORE] +
      0.30 * z[ISV_OB_SCORE] +
      0.20 * z[ISV_FVG_SCORE] +
      0.20 * z[ISV_WYCKOFF_SCORE];

   const double momentum_z =
      0.30 * z[ISV_MACD] +
      0.20 * z[ISV_MACD_HIST] +
      0.20 * z[ISV_ROC] +
      0.15 * z[ISV_RSI] +
      0.15 * z[ISV_TREND_SLOPE];

   double alpha_lin = 0.0;
   alpha_lin += cfg.scan_inst_weight_microprice * (0.50 * z[ISV_OBI_K] + 0.50 * z[ISV_DOM_SKEW_K]);
   alpha_lin += cfg.scan_inst_weight_resiliency * z[ISV_RESIL_T];
   alpha_lin += cfg.scan_inst_weight_depth_fade * (-MathAbs(z[ISV_DEPTH_FADE]));
   alpha_lin += cfg.scan_inst_weight_cvd * (0.40 * z[ISV_CVD] + 0.35 * z[ISV_FLOW_IMB] + 0.25 * z[ISV_OFI]);
   alpha_lin += cfg.scan_inst_weight_toxicity * (-MathAbs(z[ISV_VPIN]));
   alpha_lin += cfg.scan_inst_weight_impact * (-MathAbs(z[ISV_IMPACT_Q]));
   alpha_lin += cfg.scan_inst_weight_profile_acceptance * profile_z;
   alpha_lin += cfg.scan_inst_weight_market_profile * z[ISV_POC_DIST];
   alpha_lin += cfg.scan_inst_weight_benchmark * benchmark_z;
   alpha_lin += cfg.scan_inst_weight_jump * (-MathAbs(z[ISV_JUMP]));
   alpha_lin += cfg.scan_inst_weight_sweep * z[ISV_SWEEP_SCORE];
   alpha_lin += 0.10 * structure_z;
   alpha_lin += 0.08 * momentum_z;
   alpha_lin += 0.04 * z[ISV_RHO];

   double exec_lin = 0.0;
   exec_lin += 0.25 * z[ISV_RESIL_T];
   exec_lin += 0.18 * z[ISV_OBI_K];
   exec_lin += 0.14 * z[ISV_OFI];
   exec_lin += 0.10 * z[ISV_FLOW_IMB];
   exec_lin += 0.08 * z[ISV_DOM_SKEW_K];
   exec_lin -= 0.12 * MathAbs(z[ISV_SPREAD_SHOCK]);
   exec_lin -= 0.10 * MathAbs(z[ISV_DEPTH_FADE]);
   exec_lin -= 0.08 * MathAbs(z[ISV_POV_GAP]);
   exec_lin -= 0.08 * MathAbs(z[ISV_IMPACT_Q]);
   exec_lin -= 0.05 * MathAbs(z[ISV_SLIPPAGE]);
   exec_lin += 0.05 * benchmark_z;

   double risk_lin = 0.0;
   risk_lin += 0.16 * MathAbs(z[ISV_VPIN]);
   risk_lin += 0.12 * MathAbs(z[ISV_JUMP]);
   risk_lin += 0.12 * MathAbs(z[ISV_SPREAD_SHOCK]);
   risk_lin += 0.10 * MathAbs(z[ISV_DEPTH_FADE]);
   risk_lin += 0.10 * MathAbs(z[ISV_SLIPPAGE]);
   risk_lin += 0.08 * MathAbs(z[ISV_POV_GAP]);
   risk_lin += 0.08 * MathAbs(z[ISV_IMPACT_Q]);
   risk_lin += 0.08 * MathAbs(z[ISV_REL_SPREAD]);
   risk_lin += 0.06 * MathAbs(z[ISV_QUOTE_FADE]);
   risk_lin += 0.05 * MathAbs(z[ISV_DP_SHARE]);
   risk_lin -= 0.08 * z[ISV_RESIL_T];

   out.alpha_t = cfg.scan_inst_head_weight_alpha * alpha_lin;
   out.exec_t  = Sigmoid(cfg.scan_inst_head_weight_execution * exec_lin);
   out.risk_t  = Sigmoid(cfg.scan_inst_head_weight_risk * risk_lin);

   out.direction_dir11 = (out.alpha_t >= 0.0 ? 1 : -1);

   const double alpha_abs = MathAbs(out.alpha_t);
   const double vpin_raw = Clamp01(raw[ISV_VPIN]);
   const double resil_raw = raw[ISV_RESIL_T];
   const double quality_ok = (out.ms.state_quality01 >= bcfg.min_state_quality01 ? 1.0 : 0.0);

   out.trade_gate =
      (alpha_abs > bcfg.theta_alpha &&
       out.exec_t > bcfg.theta_exec &&
       out.risk_t < bcfg.theta_risk &&
       vpin_raw < bcfg.theta_vpin &&
       resil_raw > bcfg.theta_resil &&
       quality_ok > 0.5);

   out.size01 =
      Clamp01(
         bcfg.size_max *
         Sigmoid(1.25 * alpha_abs) *
         (1.0 - out.risk_t) *
         out.exec_t
      );

   out.ms.alpha_score = out.alpha_t;
   out.ms.execution_score = out.exec_t;
   out.ms.risk_score = out.risk_t;
   out.ms.trade_gate_pass = out.trade_gate;

   out.snap.alpha_score = out.alpha_t;
   out.snap.execution_score = out.exec_t;
   out.snap.risk_score = out.risk_t;
   out.snap.trade_gate_pass = out.trade_gate;
}

inline void FillSnapshotNamedFields(Result &out)
{
   out.snap.flow_pressure_z       = out.z[ISV_FLOW_IMB];
   out.snap.queue_pressure_z      = 0.50 * out.z[ISV_OBI_K] + 0.50 * out.z[ISV_DOM_SKEW_K];
   out.snap.toxicity_z            = out.z[ISV_VPIN];
   out.snap.resiliency_z          = out.z[ISV_RESIL_T];
   out.snap.impact_z              = 0.50 * out.z[ISV_BETA_T] + 0.50 * out.z[ISV_IMPACT_Q];
   out.snap.benchmark_dev_z       = 0.50 * out.z[ISV_MID_MINUS_VWAP] + 0.50 * out.z[ISV_MID_MINUS_TWAP];
   out.snap.volatility_jump_z     = out.z[ISV_JUMP];
   out.snap.profile_acceptance_z  = 0.60 * out.z[ISV_VA_STATE] + 0.40 * out.z[ISV_TPO_STATE];
   out.snap.liquidity_stress_z    = 0.55 * out.z[ISV_SPREAD_SHOCK] + 0.45 * out.z[ISV_DEPTH_FADE];
   out.snap.structure_quality_z   = 0.30 * out.z[ISV_SD_SCORE] + 0.30 * out.z[ISV_OB_SCORE] + 0.20 * out.z[ISV_FVG_SCORE] + 0.20 * out.z[ISV_WYCKOFF_SCORE];
   out.snap.momentum_trend_z      = 0.35 * out.z[ISV_MACD] + 0.25 * out.z[ISV_MACD_HIST] + 0.20 * out.z[ISV_ROC] + 0.20 * out.z[ISV_TREND_SLOPE];
   out.snap.correlation_context_z = out.z[ISV_RHO];
}

inline bool Build(const string sym,
                  const ENUM_TIMEFRAMES tf,
                  const Settings &cfg,
                  Runtime &rt,
                  Result &out,
                  const int closed_shift = 1)
{
   out.Reset();

   BuildConfig bcfg;
   LoadBuildConfigFromSettings(cfg, bcfg);

   if(!rt.initialized)
      rt.Reset(bcfg.z_window);

   int shift = closed_shift;
   if(shift < 1)
      shift = 1;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(sym, tf, shift, 220, rates) < 10)
      return false;

   const datetime bar_time = rates[0].time;
   const double close0 = rates[0].close;
   const double open0  = rates[0].open;
   const double high0  = rates[0].high;
   const double low0   = rates[0].low;
   const double close1 = rates[1].close;

   MqlTick tick;
   SymbolInfoTick(sym, tick);

   double bid = tick.bid;
   double ask = tick.ask;
   if(bid <= 0.0 || ask <= 0.0 || ask < bid)
   {
      bid = close0;
      ask = close0;
   }

   const double spread = MathMax(0.0, ask - bid);
   const double mid = 0.5 * (ask + bid);
   const double rel_spread = SafeDiv(spread, MathMax(mid, 1e-12), 0.0);

   const double atr = ATRPrice(sym, tf, bcfg.atr_period, shift);
   const double total_vol = MathMax(1.0, TickVolumeAt(sym, tf, shift));
   const double price_change = (close0 - close1);
   const bool otc_like = SymbolLooksOTCFragmented(sym);

   out.valid = true;
   out.symbol = sym;
   out.tf = tf;
   out.bar_time = bar_time;
   out.tick_volume_proxy_used = otc_like;

   out.ms.Reset();
   out.ms.valid = true;
   out.ms.backendSignalsOnly = true;
   out.ms.bar_time = bar_time;
   out.ms.tf = tf;
   out.ms.sym = sym;

   out.snap.Reset();
   out.snap.valid = true;
   out.snap.backendSignalsOnly = true;
   out.snap.stateBarTime = bar_time;
   out.snap.tf = tf;
   out.snap.mirrorOnly = false;
   out.snap.snapshotOwner = INST_STATE_SNAPSHOT_OWNER_NONE;

   out.ofx.Reset();

   // -----------------------------------------------------------------------
   // 1) OBI / DOM / OFI (primary), with proxy downgrade allowed by provider.
   // -----------------------------------------------------------------------
   OBI::Settings obi_cfg;
   LoadOBISettings(cfg, obi_cfg);

   double obi_signed = 0.0;
   double obi_raw_metric = 0.0;
   OBI::ScannerSignalPack obi_sig;
   OBI::CanonicalAdvancedExportPayload obi_adv;
   OBI::Snapshot obi_snap;

   bool have_obi =
      OBI_DirectionalSupportExportEx(sym,
                                     1,
                                     mid,
                                     bcfg.dom_band_points,
                                     obi_cfg,
                                     tf,
                                     shift,
                                     obi_signed,
                                     obi_raw_metric,
                                     obi_sig,
                                     obi_adv,
                                     obi_snap);

   double dom_bid_1 = 0.0, dom_ask_1 = 0.0, dom_tot_1 = 0.0, dom_skew_1 = 0.0, dom_pressure_1 = 0.0;
   double dom_bid_k = 0.0, dom_ask_k = 0.0, dom_tot_k = 0.0, dom_skew_k = 0.0, dom_pressure_k = 0.0;
   double obi_1 = 0.0, obi_k = 0.0;
   double event_ofi = 0.0;
   double beta_t = 0.0;
   double lambda_t = 0.0;
   double abs_plus = 0.0, abs_minus = 0.0, repl_bid = 0.0, repl_ask = 0.0, resil_t = 0.0;
   double slippage_proxy = 0.0;
   double spread_shock_raw = 0.0;
   double depth_fade_raw = 0.0;
   double micro = mid;

   if(have_obi)
   {
      OBI_ApplySnapshotToMicrostructureStats(obi_snap, out.ms);

      obi_1 = obi_adv.obi1;
      obi_k = obi_adv.obik;
      event_ofi = obi_adv.event_ofi;

      dom_bid_1 = obi_adv.dom_bid_1;
      dom_ask_1 = obi_adv.dom_ask_1;
      dom_tot_1 = obi_adv.dom_tot_1;
      dom_skew_1 = obi_adv.dom_skew_1;
      dom_pressure_1 = obi_adv.dom_pressure_1;

      dom_bid_k = obi_adv.dom_bid_k;
      dom_ask_k = obi_adv.dom_ask_k;
      dom_tot_k = obi_adv.dom_tot_k;
      dom_skew_k = obi_adv.dom_skew_k;
      dom_pressure_k = obi_adv.dom_pressure_k;

      beta_t = obi_adv.beta_t;
      lambda_t = obi_adv.flow_impact_lambda;
      abs_plus = obi_adv.abs_plus;
      abs_minus = obi_adv.abs_minus;
      repl_bid = obi_adv.repl_bid;
      repl_ask = obi_adv.repl_ask;
      resil_t = obi_adv.resil_t;

      slippage_proxy = obi_adv.slippage_basis_points;
      spread_shock_raw = obi_adv.spread_shock_z;
      depth_fade_raw = (obi_adv.local_depth_proxy01 > 0.0 ? (1.0 - Clamp01(obi_adv.local_depth_proxy01)) : 0.0);

      out.dom_proxy_used = (obi_adv.used_proxy_route || !obi_adv.has_true_dom_depth);
      out.venue_coverage01 = Clamp01((obi_adv.depth_coverage01 > 0.0 ? obi_adv.depth_coverage01 : obi_adv.observability_confidence01));
      out.observability01 = Clamp01(obi_adv.observability_confidence01);

      if(obi_adv.microprice_available)
         micro = mid + obi_adv.microprice_minus_mid;
      else if(dom_tot_1 > 1e-12)
         micro = (ask * dom_bid_1 + bid * dom_ask_1) / MathMax(dom_tot_1, 1e-12);

      if(out.dom_proxy_used || dom_tot_k <= 1e-12)
      {
         FillPseudoDepthFromOBI(obi_1,
                                obi_k,
                                (obi_adv.local_depth_proxy01 > 0.0 ? obi_adv.local_depth_proxy01 : 0.50),
                                dom_bid_1, dom_ask_1, dom_tot_1, dom_skew_1, dom_pressure_1,
                                dom_bid_k, dom_ask_k, dom_tot_k, dom_skew_k, dom_pressure_k);
      }
   }
   else
   {
      out.dom_proxy_used = true;
      FillPseudoDepthFromOBI(0.0, 0.0, 0.25,
                             dom_bid_1, dom_ask_1, dom_tot_1, dom_skew_1, dom_pressure_1,
                             dom_bid_k, dom_ask_k, dom_tot_k, dom_skew_k, dom_pressure_k);
      out.venue_coverage01 = (otc_like ? 0.25 : 0.10);
      out.observability01 = out.venue_coverage01;
   }

   // -----------------------------------------------------------------------
   // 2) Canonical executed-flow / fallback order-flow snapshot (DeltaProxy).
   // -----------------------------------------------------------------------
   DeltaX::DeltaSignalPack delta_sig;
   DeltaX::DeltaSignalPackReset(delta_sig);

   bool have_delta_sig =
      DeltaX::SessionDeltaSignalPackEx(sym,
                                       tf,
                                       MathMax(20, bcfg.flow_lookback),
                                       shift,
                                       true,
                                       100.0,
                                       delta_sig);

   double signed_delta = 0.0;
   if(have_delta_sig)
      signed_delta = delta_sig.raw;
   else
      signed_delta = ((close0 >= open0 ? 1.0 : -1.0) * total_vol);

   DeltaX::OrderFlowSeriesUpdateParams of_params;
   DeltaX::OrderFlowToxicityUpdateParams tox_params;
   DeltaX::OrderFlowImpactUpdateParams impact_params;

   LoadSeriesUpdateParams(of_params);
   LoadToxicityUpdateParams(cfg, tox_params);
   LoadImpactUpdateParams(cfg, impact_params);

   const double depth_scalar = MathMax(0.10, dom_tot_k);

   bool have_ofx =
      DeltaX::UpdateCanonicalSeriesSnapshotForBarAdvancedEx(sym,
                                                            tf,
                                                            shift,
                                                            signed_delta,
                                                            total_vol,
                                                            price_change,
                                                            depth_scalar,
                                                            of_params,
                                                            tox_params,
                                                            impact_params,
                                                            delta_sig,
                                                            rt.flow_bridge,
                                                            out.ofx);

   if(have_ofx)
   {
      out.flow_proxy_used = (out.ofx.usedProxy || !out.ofx.dataReliable);
      out.ms.ofi_norm = out.ofx.ofiNorm;
      out.ms.cvd = out.ofx.cvd;
      out.ms.flow_lambda = out.ofx.flowImpactLambda;
      out.ms.impact_beta = out.ofx.ofiImpactBeta;
      out.ms.vpin = Clamp01((out.ofx.vpinLike > 0.0 ? out.ofx.vpinLike : out.ms.vpin));
      out.ms.absorption = Clamp01((out.ofx.absorptionScore > 0.0 ? out.ofx.absorptionScore : out.ms.absorption));
      out.ms.replenishment = Clamp01((out.ofx.replRate > 0.0 ? out.ofx.replRate : out.ms.replenishment));
      out.ms.resiliency = Clamp01((out.ofx.depthRecoveryPct > 0.0 ? out.ofx.depthRecoveryPct : out.ms.resiliency));

      out.ms.signed_flow = out.ofx.signedDelta;
      out.ms.gross_flow = out.ofx.totalFlowVol;
      out.ms.buy_flow_window = out.ofx.buyFlowWindow;
      out.ms.sell_flow_window = out.ofx.sellFlowWindow;
      out.ms.net_flow_window = out.ofx.netFlowWindow;
      out.ms.flow_imb_window = out.ofx.flowImbWindow;
      out.ms.signed_flow_window = out.ofx.signedFlowWindow;
      out.ms.cvd_t = out.ofx.cvdT;

      out.ms.signed_flow_source_mode = out.ofx.signedFlowSourceMode;
      out.ms.signed_source_confidence01 = out.ofx.signedSourceConfidence01;
      out.ms.signed_source_tier = out.ofx.signedSourceTier;
      out.ms.flow_confidence01 = out.ofx.flowConfidence01;
      out.ms.flow_provenance = out.ofx.flowProvenance;

      out.ms.impact_beta_t = (beta_t != 0.0 ? beta_t : out.ofx.ofiImpactBeta);
      out.ms.impact_lambda_t = (lambda_t != 0.0 ? lambda_t : out.ofx.flowImpactLambda);
      out.ms.abs_plus = abs_plus;
      out.ms.abs_minus = abs_minus;
      out.ms.repl_bid = repl_bid;
      out.ms.repl_ask = repl_ask;
      out.ms.resil_t = resil_t;

      if(out.ofx.spreadShockZ != 0.0)
         spread_shock_raw = out.ofx.spreadShockZ;

      if(out.ofx.depthFade01 > 0.0)
         depth_fade_raw = out.ofx.depthFade01;

      if(out.ofx.venueCoverage01 > 0.0)
         out.venue_coverage01 = MathMax(out.venue_coverage01, Clamp01(out.ofx.venueCoverage01));

#ifdef OFDS_HAS_SCANNER_CONTEXT_FIELDS
      out.observability01 = MathMax(out.observability01, Clamp01(out.ofx.observabilityScore01));
#endif
   }
   else
   {
      out.flow_proxy_used = true;
      out.ofx.Reset();
      out.ofx.valid = true;
      out.ofx.usedProxy = true;
      out.ofx.dataReliable = false;
      out.ofx.flowBarTime = bar_time;
      out.ofx.signedDelta = signed_delta;
      out.ofx.cvd = signed_delta;
      out.ofx.buyFlowWindow = MathMax(0.0, signed_delta);
      out.ofx.sellFlowWindow = MathMax(0.0, -signed_delta);
      out.ofx.netFlowWindow = signed_delta;
      out.ofx.flowImbWindow = SafeDiv(signed_delta, total_vol, 0.0);
      out.ofx.signedFlowWindow = signed_delta;
      out.ofx.cvdT = signed_delta;
      out.ofx.vpinLike = 0.50;
      out.ofx.flowImpactLambda = lambda_t;
      out.ofx.ofiImpactBeta = beta_t;
      out.ofx.venueCoverage01 = out.venue_coverage01;
      out.ofx.ofiNorm = SafeDiv(signed_delta, MathMax(total_vol, 1.0), 0.0);

      out.ms.ofi_norm = out.ofx.ofiNorm;
      out.ms.cvd = out.ofx.cvd;
      out.ms.vpin = 0.50;
      out.ms.flow_lambda = lambda_t;
      out.ms.impact_beta = beta_t;
   }

   // -----------------------------------------------------------------------
   // 3) VWAP / TWAP / execution benchmark layer.
   // -----------------------------------------------------------------------
   VWAPConfig vwap_cfg;
   LoadVWAPConfig(cfg, tf, vwap_cfg);

   VWAPBenchmarkCompact vwb;
   vwb.Reset();

   bool have_vwap =
      VWAP::BuildBenchmarkCompact(sym,
                                  tf,
                                  vwap_cfg,
                                  shift,
                                  bcfg.twap_lookback_bars,
                                  VWAP_TWAP_SESSION_BROKER_DAY,
                                  VWAP_POV_GAP_PARTICIPATION_PROXY,
                                  bcfg.participation_target01,
                                  vwb);
   if(have_vwap)
   {
      VWAP::ApplyBenchmarkCompactToMicrostructureStats(vwb, out.ms);
#ifdef MICROSTRUCTURESTATS_HAS_BENCHMARK_CONFIDENCE01
      out.ms.benchmark_confidence01 = Clamp01(vwb.benchmarkConfidence01);
#endif
   }

   double mid_minus_vwap = 0.0;
   double mid_minus_twap = 0.0;
   double pov_gap_proxy = 0.0;
   if(have_vwap)
   {
      mid_minus_vwap = (mid - vwb.vwap);
      mid_minus_twap = (mid - vwb.twap);
      // Benchmark module already exports a normalized participation-gap proxy.
      // In scanner mode we do not own real CumExec_t, so this remains a benchmark proxy.
      pov_gap_proxy = vwb.pov_gap_z;
   }

   // -----------------------------------------------------------------------
   // 4) AutoVol / realized variance / range estimators.
   // -----------------------------------------------------------------------
   AutoVol::AutoVolVolatilityState vol_state;
   AutoVol::AutoVolStats vol_stats;
   vol_state.Clear();

   bool have_autovol =
      AutoVol::AutoVolGetVolatilityState(sym,
                                         (int)AutoVol::AUTOVOL_EST_RV,
                                         vol_state,
                                         vol_stats);

   if(have_autovol)
   {
      const double vol_base = MathMax(vol_state.parkinson_d1_pct, vol_state.gk_d1_pct);
      out.ms.rv = MathMax(0.0, vol_state.rv_h1_pct);
      out.ms.bv = MathMax(0.0, vol_base);
      out.ms.jump = MathMax(0.0, out.ms.rv - out.ms.bv);
   }

   // -----------------------------------------------------------------------
   // 5) VSA exact/classical metrics.
   // -----------------------------------------------------------------------
   VSA::ClassicalParams vsa_cfg;
   LoadVSAParams(vsa_cfg);

   VSA::ClassicalMetrics vsa_m;
   vsa_m.Clear();
   bool have_vsa = VSA::ComputeClassicalMetrics(sym, tf, vsa_cfg, vsa_m);

   double clv_raw = (have_vsa ? vsa_m.clvSigned : 0.0);
   double volz_raw = (have_vsa ? vsa_m.relVol : 0.0);
   double er_raw = 0.0;
   if(atr > 0.0)
      er_raw = ((close0 - open0) / atr) * volz_raw;

   // -----------------------------------------------------------------------
   // 6) Footprint fallback / additive context.
   // -----------------------------------------------------------------------
   FootprintProxy::FPConfig fp_cfg;
   fp_cfg.SetDefaults();

   FootprintProxy::FPCanonicalDownstreamExportPack fp_pack;
   fp_pack.Reset();

   bool have_fp =
      FootprintProxy::BuildCanonicalStateFeedExportPackEx(sym,
                                                          tf,
                                                          shift,
                                                          fp_cfg,
                                                          FootprintProxy::FP_MODE_AUTO,
                                                          MathMax(20, cfg.scan_obi_proxy_fp_z_lookback),
                                                          (cfg.scan_obi_proxy_fp_z_scale > 0.0 ? cfg.scan_obi_proxy_fp_z_scale : 2.0),
                                                          fp_pack);

   double footprint_delta_raw = 0.0;
   if(have_fp && fp_pack.valid)
   {
      footprint_delta_raw = fp_pack.footprintDelta;
      out.footprint_proxy_used = (fp_pack.proxyReliabilityTier <= FootprintProxy::FP_OBI_PROXY_TIER_FAIR);
      out.ms.footprint_delta = fp_pack.footprintDelta;
#ifdef MICROSTRUCTURESTATS_HAS_FOOTPRINT_CUE01
      out.ms.footprintCue01 = Clamp01(MathMax(fp_pack.stacked_imbalance_score, fp_pack.absorption_event_score));
#endif
      if(out.ofx.cvd == 0.0 && fp_pack.session_cvd_proxy != 0.0)
         out.ofx.cvd = fp_pack.session_cvd_proxy;
   }
   else
   {
      out.footprint_proxy_used = true;
      footprint_delta_raw = (have_ofx ? out.ofx.signedDelta : signed_delta);
      out.ms.footprint_delta = footprint_delta_raw;
   }

   // -----------------------------------------------------------------------
   // 7) Volume profile / market profile / POC / value area.
   // -----------------------------------------------------------------------
   VP::Params vp_params;
   LoadVPParams(cfg, vp_params);

   VP::Profile vp;
   VP::Reset(vp);

   VP::ProfileDisplayLevels vpd;
   vpd.Reset();

   bool have_vp = VP::BuildProfile(sym, tf, vp_params, vp);
   if(have_vp)
   {
      VP::ExtractProfileDisplayLevels(vp, vpd, true);
      VP::ApplyProfileDisplayLevelsToMicrostructureStats(vpd, out.ms);
      out.profile_proxy_used = (vpd.synthetic_model_fallback || vpd.quote_heuristic_build);
   }
   else
   {
      out.profile_proxy_used = true;
   }

   double poc_dist_raw = 0.0;
   double va_state_raw = 0.0;
   double tpo_state_raw = 0.0;
   double sr_dist_raw = 0.0;

   if(have_vp && vpd.valid)
   {
      if(atr > 0.0 && vpd.poc > 0.0)
         poc_dist_raw = (close0 - vpd.poc) / atr;
      else
         poc_dist_raw = vpd.poc_dist_z;

      if(vpd.vah > 0.0 && vpd.val > 0.0)
      {
         if(close0 > vpd.vah) va_state_raw = 1.0;
         else if(close0 < vpd.val) va_state_raw = -1.0;
         else va_state_raw = 0.0;
      }
      else
      {
         va_state_raw = vpd.va_state_z;
      }

#ifdef VP_HAS_TPO_MARKET_PROFILE_EXPORT
      if(vpd.tpo_ok && vpd.tpo_vah > 0.0 && vpd.tpo_val > 0.0)
      {
         if(close0 > vpd.tpo_vah) tpo_state_raw = 1.0;
         else if(close0 < vpd.tpo_val) tpo_state_raw = -1.0;
         else tpo_state_raw = 0.0;
      }
#endif
   }

   // -----------------------------------------------------------------------
   // 8) Liquidity sweeps / spread-shock / depth fade / slippage stress.
   // -----------------------------------------------------------------------
   LiqX::Snapshot liq;
   liq.Clear();
   LiqX::SnapshotAndBlend(sym, tf, MathMax(20, bcfg.profile_lookback_bars), liq);

   double sweep_score_raw = Clamp01((liq.sweepScore01 > 0.0 ? liq.sweepScore01 : liq.sweep_str));

   if(liq.spreadShockZ != 0.0)
      spread_shock_raw = liq.spreadShockZ;

   if(liq.depthFade01 > 0.0)
      depth_fade_raw = liq.depthFade01;

#ifdef LIQUIDITYCUES_HAS_STRONG_EVENT_LABEL_EXPORTS
   if(liq.primary_event_score01 > 0.0)
   {
      out.ms.liquidity_event_score01 = Clamp01(liq.primary_event_score01);
      out.ms.liquidity_event_type = liq.primary_event_label;
      out.ms.liquidity_event_time = liq.sweep_when;
      out.ms.liquidity_event_price = liq.sweep_pool_price;
   }
#endif

   // -----------------------------------------------------------------------
   // 9) Structure / SD / OB.
   // -----------------------------------------------------------------------
   StructOB::SDOBCanonicalZoneTruthPayload sdob_bull;
   StructOB::SDOBCanonicalZoneTruthPayload sdob_bear;
   sdob_bull.Reset();
   sdob_bear.Reset();

   const bool have_sdob_bull = StructureSDOB_BuildCanonicalZoneTruthPayload(cfg, sym, tf, true,  out.ofx, sdob_bull);
   const bool have_sdob_bear = StructureSDOB_BuildCanonicalZoneTruthPayload(cfg, sym, tf, false, out.ofx, sdob_bear);

   double sd_score_raw = 0.0;
   double ob_score_raw = 0.0;

   if(have_sdob_bull || have_sdob_bear)
   {
      const double bull_sd = (have_sdob_bull ? sdob_bull.sdScore01 : 0.0);
      const double bear_sd = (have_sdob_bear ? sdob_bear.sdScore01 : 0.0);
      const double bull_ob = (have_sdob_bull ? sdob_bull.obScore01 : 0.0);
      const double bear_ob = (have_sdob_bear ? sdob_bear.obScore01 : 0.0);

      sd_score_raw = (bull_sd - bear_sd);
      ob_score_raw = (bull_ob - bear_ob);

      out.ms.sd_score = MathMax(out.ms.sd_score, MathMax(bull_sd, bear_sd));
      out.ms.ob_score = MathMax(out.ms.ob_score, MathMax(bull_ob, bear_ob));

#ifdef MICROSTRUCTURESTATS_HAS_POI_SCORE01
      out.ms.poi_score01 = MathMax(out.ms.poi_score01, MathMax(have_sdob_bull ? sdob_bull.scoreFinal01 : 0.0,
                                                               have_sdob_bear ? sdob_bear.scoreFinal01 : 0.0));
#endif
#ifdef MICROSTRUCTURESTATS_HAS_POI_KIND
      if(MathAbs(sd_score_raw) >= MathAbs(ob_score_raw))
         out.ms.poi_kind = (sd_score_raw >= 0.0 ? 1 : -1);
#endif
   }

   // -----------------------------------------------------------------------
   // 10) Wyckoff phase.
   // -----------------------------------------------------------------------
   WyckCycleOutput wy;
   bool have_wy = WyckoffCycle_Evaluate(sym, tf, cfg, out.ofx, wy);

   double wyckoff_score_raw = 0.0;
   if(have_wy)
   {
      double phase01 = 0.0;
      double phase_conf01 = 0.0;
      WyckoffPhase phase = WYCKOFF_UNKNOWN;
      if(WyckoffCycle_ExtractCanonicalPhaseState(wy, phase, phase01, phase01, phase_conf01))
      {
         double sign = 0.0;
         if(phase == WYCKOFF_MARKUP || phase == WYCKOFF_ACCUMULATION)
            sign = 1.0;
         else if(phase == WYCKOFF_MARKDOWN || phase == WYCKOFF_DISTRIBUTION)
            sign = -1.0;
         else
            sign = 0.0;

         wyckoff_score_raw = sign * Clamp01((wy.wyckoff_score01 > 0.0 ? wy.wyckoff_score01 : wy.wyckoffScore01));
      }
      else
      {
         wyckoff_score_raw =
            ClampSym((wy.markupRegime01 + wy.accumulationRegime01) -
                     (wy.markdownRegime01 + wy.distributionRegime01), 1.0);
      }

      out.ms.wyckoff_score = MathMax(out.ms.wyckoff_score, MathAbs(wyckoff_score_raw));
#ifdef MICROSTRUCTURESTATS_HAS_WYCKOFF_CONTEXT01
      out.ms.wyckoff_context01 = MathMax(out.ms.wyckoff_context01,
                                         Clamp01((wy.wyckoff_score01 > 0.0 ? wy.wyckoff_score01 : wy.wyckoffScore01)));
#endif
   }

   // -----------------------------------------------------------------------
   // 11) FVG (bull - bear signed score).
   // -----------------------------------------------------------------------
   FVGScannerCompactExport fvg_bull;
   FVGScannerCompactExport fvg_bear;
   fvg_bull.Reset();
   fvg_bear.Reset();

   bool have_fvg_bull = FVG_BuildDirectionalCompactExport_Cfg(sym, tf, cfg, true, fvg_bull);
   bool have_fvg_bear = FVG_BuildDirectionalCompactExport_Cfg(sym, tf, cfg, false, fvg_bear);

   double fvg_score_raw = 0.0;
   if(have_fvg_bull || have_fvg_bear)
   {
      const double bull_s = (have_fvg_bull ? (fvg_bull.rankedScore01 > 0.0 ? fvg_bull.rankedScore01 : fvg_bull.fvgScore01) : 0.0);
      const double bear_s = (have_fvg_bear ? (fvg_bear.rankedScore01 > 0.0 ? fvg_bear.rankedScore01 : fvg_bear.fvgScore01) : 0.0);

      fvg_score_raw = (bull_s - bear_s);

      if(bull_s >= bear_s && have_fvg_bull)
         ApplyFVGScannerCompactExportToMicrostructureStats(fvg_bull, out.ms);
      else if(have_fvg_bear)
         ApplyFVGScannerCompactExportToMicrostructureStats(fvg_bear, out.ms);
   }

   // -----------------------------------------------------------------------
   // 12) Classical indicators + z-export bridge.
   // -----------------------------------------------------------------------
   Indi::NormalizedIndicatorExport indi_z;
   indi_z.Reset();
   if(Indi::BuildNormalizedIndicatorExport(sym, tf, MathMax(20, bcfg.indicator_lookback), indi_z, shift))
      Indi::ApplyNormalizedIndicatorExportToMicrostructureStats(indi_z, out.ms);

   double rsi_raw = Indi::RSI(sym, tf, 14, shift);
   double macd_raw = 0.0, macd_signal_raw = 0.0, macd_hist_raw = 0.0;
   Indi::MACD(sym, tf, 12, 26, 9, shift, macd_raw, macd_signal_raw, macd_hist_raw);
   double stoch_rsi_raw = Indi::StochRSI_K(sym, tf, 14, 14, 3, 3, shift);
   double roc_raw = 0.0;
   Indi::ROCPercent(sym, tf, 12, shift, roc_raw);
   double adx_raw = Indi::ADX(sym, tf, 14, shift);
   double trend_slope_raw = RegressionSlopeRaw(sym, tf, bcfg.trend_reg_lookback, shift);

   // -----------------------------------------------------------------------
   // 13) Pivots, Fibonacci, trendlines, correlation.
   // -----------------------------------------------------------------------
   PivotsGeometryCompactExport piv_ex;
   piv_ex.Clear();
   bool have_piv = Pivots_BuildGeometryCompactExport(sym, tf, cfg, piv_ex);
   if(have_piv)
      ApplyPivotsGeometryCompactExportToMicrostructureStats(piv_ex, out.ms);

   double pivot_dist_raw = (have_piv ? piv_ex.pivotDistZ : 0.0);
   sr_dist_raw = (have_piv ? piv_ex.srDistZ : 0.0);

   Fib::OTEZone fib_zone;
   Fib::CompactZoneExport fib_ex;
   fib_ex.Clear();

   bool have_fib = Fib::CalcOTEZoneForLastImpulsiveSwing(sym, tf, fib_zone);
   if(have_fib && Fib::BuildCompactZoneExport(fib_zone, fib_ex))
      Fib::ApplyCompactZoneExportToMicrostructureStats(fib_ex, out.ms);

   double fib_dist_raw = (fib_ex.valid ? fib_ex.fibDistZ : 0.0);

   int trend_dir = (out.ofx.flowImbWindow >= 0.0 ? 1 : -1);
   if(trend_dir == 0)
      trend_dir = (close0 >= open0 ? 1 : -1);

   TrendlinesConfig tl_cfg;
   LoadTrendlinesConfig(tl_cfg);
   TrendlinesState tl_state;
   Trendlines_ResetState(tl_state);

   if(Trendlines_Update(sym, tf, tl_cfg, tl_state))
      ApplyTrendlineStateToMicrostructureStats(tl_state, trend_dir, out.ms);

   Corr::CorrelationCompactExport corr_ex;
   corr_ex.Clear();
   bool have_corr =
      Corr::BuildProxyCompactExport(sym,
                                    tf,
                                    MathMax(20, bcfg.corr_len),
                                    PRICE_CLOSE,
                                    Corr::CORR_RETURN_ATR_LOG,
                                    corr_ex,
                                    shift,
                                    MathMax(2, cfg.atr_period),
                                    0.0,
                                    6.0);

   if(have_corr)
      Corr::ApplyCorrelationCompactExportToMicrostructureStats(corr_ex, Corr::CORR_MICRO_SLOT_BASKET, out.ms);

   double rho_raw = (have_corr ? corr_ex.rho_xy_raw : 0.0);

   // -----------------------------------------------------------------------
   // 14) Remaining execution / venue / internalisation proxies.
   // -----------------------------------------------------------------------
   double sigma_p_raw = 0.0;
   double sigma_gk_raw = 0.0;
   double rv_raw = out.ms.rv;
   double bv_raw = out.ms.bv;
   double jump_raw = out.ms.jump;

   if(have_autovol)
   {
      const double vol_base = MathMax(vol_state.parkinson_d1_pct, vol_state.gk_d1_pct);
      rv_raw = MathMax(0.0, vol_state.rv_h1_pct);
      bv_raw = MathMax(0.0, vol_base);
      jump_raw = MathMax(0.0, rv_raw - bv_raw);
      sigma_p_raw = MathMax(0.0, vol_state.parkinson_d1_pct);
      sigma_gk_raw = MathMax(0.0, vol_state.gk_d1_pct);
   }
   else if(have_vsa)
   {
      rv_raw = vsa_m.realizedVariance;
      bv_raw = vsa_m.bipowerVariation;
      jump_raw = vsa_m.jumpVariance;
      sigma_p_raw = vsa_m.parkinsonVariance;
      sigma_gk_raw = vsa_m.garmanKlassVariance;
   }

   const double sigma_D = MathMax(0.0001, (sigma_p_raw > 0.0 ? sigma_p_raw : 0.0001));
   const double part_rate = Clamp01(cfg.scan_inst_exec_is_aggressiveness01);
   const double impact_q_raw = sigma_D * MathSqrt(MathMax(bcfg.impact_order_qty, 0.0001) / MathMax(total_vol, 1.0)) * (0.5 + 0.5 * part_rate);

   const double dp_share_raw = Clamp01(out.ms.darkpool01);
   const double ats_share_raw = Clamp01(MathMax(0.0, out.ms.darkpool01 - 0.5 * out.ms.darkpool_contradiction01));
   const double venue_mix_entropy_raw = BinaryEntropy01(MathMax(0.01, out.venue_coverage01));
   const double internalisation_proxy_raw = Clamp01(MathMax(out.ms.hidden_liquidity_proxy01, out.ms.darkpool01));
   const double quote_fade_raw = Clamp01(MathMax(out.ms.liquidity_vacuum01, 1.0 - out.venue_coverage01));

   if(slippage_proxy == 0.0)
      slippage_proxy = out.ms.expected_slippage_stress01;

   if(depth_fade_raw == 0.0)
      depth_fade_raw = (out.ms.depth_fade_z != 0.0 ? MathAbs(out.ms.depth_fade_z) : 0.0);

   // -----------------------------------------------------------------------
   // 15) Raw vector publish in exact requested order.
   // -----------------------------------------------------------------------
   out.raw[ISV_BID] = bid;
   out.raw[ISV_ASK] = ask;
   out.raw[ISV_SPREAD] = spread;
   out.raw[ISV_REL_SPREAD] = rel_spread;
   out.raw[ISV_MID] = mid;
   out.raw[ISV_MICRO] = micro;
   out.raw[ISV_DOM_BID_K] = dom_bid_k;
   out.raw[ISV_DOM_ASK_K] = dom_ask_k;
   out.raw[ISV_DOM_TOT_K] = dom_tot_k;
   out.raw[ISV_DOM_SKEW_K] = dom_skew_k;
   out.raw[ISV_DOM_PRESSURE_K] = dom_pressure_k;
   out.raw[ISV_BUY_FLOW] = out.ofx.buyFlowWindow;
   out.raw[ISV_SELL_FLOW] = out.ofx.sellFlowWindow;
   out.raw[ISV_NET_FLOW] = out.ofx.netFlowWindow;
   out.raw[ISV_FLOW_IMB] = out.ofx.flowImbWindow;
   out.raw[ISV_SIGNED_FLOW] = out.ofx.signedFlowWindow;
   out.raw[ISV_CVD] = out.ofx.cvdT;
   out.raw[ISV_OBI_1] = obi_1;
   out.raw[ISV_OBI_K] = obi_k;
   out.raw[ISV_OFI] = (event_ofi != 0.0 ? event_ofi : out.ofx.ofiNorm);
   out.raw[ISV_BETA_T] = (beta_t != 0.0 ? beta_t : out.ofx.ofiImpactBeta);
   out.raw[ISV_LAMBDA_T] = (lambda_t != 0.0 ? lambda_t : out.ofx.flowImpactLambda);
   out.raw[ISV_VPIN] = Clamp01((out.ms.vpin > 0.0 ? out.ms.vpin : out.ofx.vpinLike));
   out.raw[ISV_ABS_PLUS] = abs_plus;
   out.raw[ISV_ABS_MINUS] = abs_minus;
   out.raw[ISV_REPL_BID] = repl_bid;
   out.raw[ISV_REPL_ASK] = repl_ask;
   out.raw[ISV_RESIL_T] = (resil_t != 0.0 ? resil_t : out.ms.resiliency);
   out.raw[ISV_IMPACT_Q] = impact_q_raw;
   out.raw[ISV_MID_MINUS_VWAP] = mid_minus_vwap;
   out.raw[ISV_MID_MINUS_TWAP] = mid_minus_twap;
   out.raw[ISV_POV_GAP] = pov_gap_proxy;
   out.raw[ISV_RV] = rv_raw;
   out.raw[ISV_BV] = bv_raw;
   out.raw[ISV_JUMP] = jump_raw;
   out.raw[ISV_SIGMA_P] = sigma_p_raw;
   out.raw[ISV_SIGMA_GK] = sigma_gk_raw;
   out.raw[ISV_CLV] = clv_raw;
   out.raw[ISV_VOL_Z] = volz_raw;
   out.raw[ISV_ER] = er_raw;
   out.raw[ISV_FOOTPRINT_DELTA] = footprint_delta_raw;
   out.raw[ISV_POC_DIST] = poc_dist_raw;
   out.raw[ISV_VA_STATE] = va_state_raw;
   out.raw[ISV_TPO_STATE] = tpo_state_raw;
   out.raw[ISV_SWEEP_SCORE] = sweep_score_raw;
   out.raw[ISV_SPREAD_SHOCK] = spread_shock_raw;
   out.raw[ISV_SLIPPAGE] = slippage_proxy;
   out.raw[ISV_DEPTH_FADE] = depth_fade_raw;
   out.raw[ISV_DP_SHARE] = dp_share_raw;
   out.raw[ISV_ATS_SHARE] = ats_share_raw;
   out.raw[ISV_VENUE_MIX_ENTROPY] = venue_mix_entropy_raw;
   out.raw[ISV_INTERNALISATION_PROXY] = internalisation_proxy_raw;
   out.raw[ISV_QUOTE_FADE] = quote_fade_raw;
   out.raw[ISV_SD_SCORE] = sd_score_raw;
   out.raw[ISV_OB_SCORE] = ob_score_raw;
   out.raw[ISV_WYCKOFF_SCORE] = wyckoff_score_raw;
   out.raw[ISV_FVG_SCORE] = fvg_score_raw;
   out.raw[ISV_RSI] = rsi_raw;
   out.raw[ISV_MACD] = macd_raw;
   out.raw[ISV_MACD_SIGNAL] = macd_signal_raw;
   out.raw[ISV_MACD_HIST] = macd_hist_raw;
   out.raw[ISV_STOCH_RSI] = stoch_rsi_raw;
   out.raw[ISV_ROC] = roc_raw;
   out.raw[ISV_ADX] = adx_raw;
   out.raw[ISV_RHO] = rho_raw;
   out.raw[ISV_SR_DIST] = sr_dist_raw;
   out.raw[ISV_PIVOT_DIST] = pivot_dist_raw;
   out.raw[ISV_FIB_DIST] = fib_dist_raw;
   out.raw[ISV_TREND_SLOPE] = trend_slope_raw;

   // -----------------------------------------------------------------------
   // 16) Single normalization policy z(x) over rolling windows.
   // -----------------------------------------------------------------------
   NormalizeRawVector(bcfg, rt, bar_time, out.raw, out.z);

   // -----------------------------------------------------------------------
   // 17) Snapshot / head publish.
   // -----------------------------------------------------------------------
   out.observability01 = MathMax(out.observability01, Clamp01(0.50 * out.venue_coverage01 + 0.50 * out.ms.state_quality01));
   out.observability_penalty01 = Clamp01(1.0 - out.observability01);

   out.ms.state_quality01 =
      Clamp01(
         0.45 * out.ms.state_quality01 +
         0.25 * out.observability01 +
         0.15 * Clamp01(out.ms.flow_confidence01) +
         0.15 * Clamp01(out.ms.benchmark_confidence01)
      );

   out.snap.valid = true;
   out.snap.backendSignalsOnly = true;
   out.snap.stateBarTime = bar_time;
   out.snap.tf = tf;
   out.snap.assetClass = out.ofx.assetClass;
   out.snap.truthTier = out.ofx.truthTier;
   out.snap.venueScope = out.ofx.venueScope;
   out.snap.snapshotOwner = INST_STATE_SNAPSHOT_OWNER_NONE;
   out.snap.mirrorOnly = false;
   out.snap.state_quality01 = out.ms.state_quality01;

   BindCanonicalHeadsToInstitutionalStateSnapshot(out.snap,
                                                  out.ofx.ofiNorm,
                                                  out.z[ISV_OFI],
                                                  out.z[ISV_CVD],
                                                  Clamp01(MathMax(out.raw[ISV_ABS_PLUS], out.raw[ISV_ABS_MINUS])),
                                                  Clamp01(out.raw[ISV_VPIN]),
                                                  Clamp01(out.raw[ISV_RESIL_T]),
                                                  Clamp01(MathAbs(out.raw[ISV_BETA_T])),
                                                  Clamp01(MathAbs(out.raw[ISV_LAMBDA_T])),
                                                  out.venue_coverage01,
                                                  out.observability01,
                                                  Clamp01(1.0 - ats_share_raw),
                                                  venue_mix_entropy_raw,
                                                  internalisation_proxy_raw,
                                                  quote_fade_raw,
                                                  dp_share_raw,
                                                  Clamp01(MathAbs(out.raw[ISV_IMPACT_Q])),
                                                  Clamp01(bcfg.participation_target01),
                                                  Clamp01(out.ms.participationRate01),
                                                  cfg.scan_inst_exec_schedule_mode);

   BindCanonicalDepthFlowHeadsToInstitutionalStateSnapshot(out.snap,
                                                           dom_bid_1,
                                                           dom_ask_1,
                                                           dom_tot_1,
                                                           dom_skew_1,
                                                           dom_pressure_1,
                                                           dom_bid_k,
                                                           dom_ask_k,
                                                           dom_tot_k,
                                                           dom_skew_k,
                                                           dom_pressure_k,
                                                           obi_1,
                                                           obi_k,
                                                           out.raw[ISV_OFI],
                                                           (have_obi ? obi_adv.event_ofi_best : 0.0),
                                                           (have_obi ? obi_adv.event_ofi_full : 0.0));

   BindExtendedContextToInstitutionalStateSnapshot(out.snap,
                                                   out.ofx.executionPostureMode,
#ifdef OFDS_HAS_SCANNER_CONTEXT_FIELDS
                                                   out.ofx.observabilityTier,
#else
                                                   OBS_TIER_UNKNOWN,
#endif
                                                   out.observability_penalty01,
                                                   Clamp01(1.0 - out.venue_coverage01),
                                                   Clamp01(MathAbs(out.raw[ISV_SLIPPAGE])),
                                                   Clamp01(MathAbs(out.raw[ISV_DEPTH_FADE])),
                                                   Clamp01(MathAbs(out.raw[ISV_JUMP])),
                                                   Clamp01(MathAbs(out.raw[ISV_VA_STATE])),
                                                   Clamp01(MathAbs(out.raw[ISV_POC_DIST])),
                                                   Clamp01(out.ms.profile_value_area_accept01),
                                                   Clamp01(out.ms.poi_score01),
                                                   Clamp01(out.ms.poi_distance_atr01),
                                                   out.ms.poi_kind,
                                                   Clamp01(out.ms.liquidity_event_score01),
                                                   out.ms.liquidity_event_type,
                                                   out.ms.liquidity_event_time,
                                                   out.ms.liquidity_event_price,
                                                   TimeCurrent(),
                                                   bar_time);

   BindScannerContextToInstitutionalStateSnapshot(out.snap,
#ifdef OFDS_HAS_SCANNER_CONTEXT_FIELDS
                                                  out.ofx.snapshotFreshnessCode,
                                                  out.ofx.signalFreshnessCode,
#else
                                                  SCAN_FRESH_UNKNOWN,
                                                  SCAN_FRESH_UNKNOWN,
#endif
                                                  VETO_NONE,
#ifdef OFDS_HAS_SCANNER_CONTEXT_FIELDS
                                                  out.ofx.poiFlags,
                                                  out.ofx.liquidityEventFlags
#else
                                                  INST_POIFLAG_NONE,
                                                  INST_LIQFLAG_NONE
#endif
                                                  );

   FillSnapshotNamedFields(out);
   BuildHeads(cfg, bcfg, out.raw, out.z, out);

   out.snap.alpha_score = out.alpha_t;
   out.snap.execution_score = out.exec_t;
   out.snap.risk_score = out.risk_t;
   out.snap.trade_gate_pass = out.trade_gate;
   out.snap.state_quality01 = out.ms.state_quality01;

   return true;
}

} // namespace ISV

#endif // CA_INSTITUTIONALSTATEVECTOR_MQH
