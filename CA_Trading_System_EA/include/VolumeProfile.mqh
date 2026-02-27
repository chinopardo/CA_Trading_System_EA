#property strict
#include "FootprintProxy.mqh"   // Spec Method C (tick-level / proxy via BuildRange)
/*
  VolumeProfile.mqh (Production-ready, VSA-weighted Volume Profile)
  -----------------------------------------------------------------
  Purpose:
    Build a rolling/session-like Volume Profile (volume-by-price histogram)
    using a VSA-weighted proxy instead of raw volume.

  Key outputs:
    - POC (Point of Control)
    - VAH/VAL (Value Area High/Low)
    - HVN/LVN (High/Low Volume Node representative levels)
    - Histogram bins (total + optional up/down)

  Notes:
    - Designed for scanners (OnTimer / new-bar rebuild). No per-tick rebuilding.
    - Uses CopyRates once per build.
    - VSA weighting follows the same concept as the PineScript example:
        volMA = SMA(volume, len)
        thresholds: high=volMA*highMult, ultra=volMA*ultraMult, low=volMA*lowMult
      Then weight is boosted/penalized accordingly and also adjusted by bar spread.

  Integration:
    - Call VP::BuildProfile(...) to compute levels and histogram.
    - Call VP::EvalSignals(...) to evaluate touch/breakout bands (optional).
*/

namespace VP
{
  // ---------------------------
  // Parameters / Outputs
  // ---------------------------
  enum VSAWeightMode
  {
    VP_VSA_WEIGHT_LEGACY      = 0,
    VP_VSA_WEIGHT_EXACTSPEC   = 1
  };

  // Profile construction mode:
  // Backward-compatible:
  //   VP_PROFILE_ROLLING_BARS (legacy current behavior)
  //   VP_PROFILE_TIME_RANGE   (legacy explicit range)
  // Extended:
  //   FIXED_RANGE / SESSION / VISIBLE_RANGE / COMPOSITE / ANCHORED / ROLLING_WINDOW
  enum ProfileType
  {
    VP_PROFILE_ROLLING_BARS   = 0, // legacy alias
    VP_PROFILE_TIME_RANGE     = 1, // legacy alias

    VP_PROFILE_FIXED_RANGE    = 2,
    VP_PROFILE_SESSION        = 3,
    VP_PROFILE_VISIBLE_RANGE  = 4, // caller must supply range_from/range_to
    VP_PROFILE_COMPOSITE      = 5,
    VP_PROFILE_ANCHORED       = 6,
    VP_PROFILE_ROLLING_WINDOW = 7  // explicit alias of rolling bars
  };

  // Explicit allocation mode (spec + backward compatibility)
  enum AllocationMode
  {
    VP_ALLOC_AUTO               = 0, // map from legacy bool distribute_by_range
    VP_ALLOC_CLOSE              = 1, // Spec Method A (strict close-bin)
    VP_ALLOC_TYPICAL            = 2, // Legacy compatibility path
    VP_ALLOC_RANGE_PROPORTIONAL = 3, // Spec Method B
    VP_ALLOC_TICK_FOOTPRINT     = 4  // Spec Method C via FootprintProxy::BuildRange
  };

  // Bin/grid sizing mode
  enum BinMode
  {
    VP_BIN_BY_POINTS = 0, // legacy/current behavior
    VP_BIN_BY_COUNT  = 1  // spec-friendly N bins
  };

  // Volume output mode (primary/raw volume interpretation)
  enum VolumeMode
  {
    VP_VOL_TOTAL = 0,
    VP_VOL_BUY   = 1,
    VP_VOL_SELL  = 2,
    VP_VOL_DELTA = 3
  };

  // VWAP source mode for OHLC-based builds
  enum VwapSourceMode
  {
    VP_VWAP_HLC3    = 0, // default
    VP_VWAP_CLOSE   = 1,
    VP_VWAP_TYPICAL = 2  // (H+L+C)/3 same as HLC3 here; kept explicit for readability
  };

  // Lightweight backend shape classification
  enum ProfileShapeCode
  {
    VP_SHAPE_UNKNOWN             = 0,
    VP_SHAPE_D_BALANCED          = 1,
    VP_SHAPE_P_SHORT_COVERING    = 2,
    VP_SHAPE_B_LONG_LIQUIDATION  = 3,
    VP_SHAPE_DOUBLE_DISTRIBUTION = 4
  };

  // Session / anchor helpers (backend-only; caller/config can map semantics later)
  enum SessionMode
  {
    VP_SESSION_BROKER_DAY = 0, // server-day reset (simple default)
    VP_SESSION_ANCHORED   = 1  // uses anchor_minute_utc (interpreted as minute-of-day)
  };

  // Value Area method:
  // 0 = POC-outward contiguous expansion (current/professional default)
  // 1 = ranked-desc accumulation (AOFIDS literal-style "sort by volume and accumulate")
  //
  // NOTE:
  // - Ranked mode still returns VAH/VAL as a bounding envelope [min_selected_bin .. max_selected_bin]
  //   because this module exposes VA as contiguous levels (VAL/VAH), not a sparse bin mask.
  enum ValueAreaMethod
  {
    VP_VA_POC_OUTWARD = 0,
    VP_VA_RANKED_DESC = 1
  };
  
  struct Params
  {
    // ---------------- Build mode / window ----------------
    int      profile_type;      // ProfileType
    datetime range_from;        // used by TIME/FIXED/VISIBLE; optional in others
    datetime range_to;          // used by TIME/FIXED/VISIBLE; optional in others
    int      max_range_bars;    // safety cap for TIME/FIXED/VISIBLE/SESSION/COMPOSITE

    int      session_mode;      // SessionMode (backend helper)
    int      anchor_minute_utc; // 0..1439 (used when profile_type/session_mode require anchor)
    int      composite_sessions;// >=1, for COMPOSITE (day/session units, backend default = day)
    
    int    lookback_bars;       // closed bars to profile (legacy/current)
    int    bin_points;          // legacy grid size in points
    int    bin_mode;            // BinMode
    int    bin_count;           // used when bin_mode == VP_BIN_BY_COUNT (spec N bins)
    double value_area_pct;      // 0.0..1.0 (0.70 typical)
    int    value_area_method;   // ValueAreaMethod (default = VP_VA_POC_OUTWARD)
    int    max_bins;            // safety cap (e.g., 400)

    // Allocation / volume semantics
    int    alloc_mode;          // AllocationMode (AUTO preserves legacy behavior)
    bool   distribute_by_range; // legacy compatibility switch (mapped when alloc_mode=AUTO)
    bool   split_up_down;       // weighted histogram up/down split (legacy optional)
    int    volume_mode;         // VolumeMode (primary consumer intent)
    bool   delta_mode;          // compute/store delta bins if possible

    // Tick-level path (Spec Method C via FootprintProxy)
    bool   allow_tick_footprint;      // permit Method C path when alloc_mode requests it
    int    footprint_build_mode;      // FootprintProxy::FPBuildMode numeric passthrough (0=auto,1=ticks,2=model)
    int    footprint_min_bars;        // minimum bars before trying BuildRange

    // VSA weighting
    bool   use_vsa;
    int    vsa_ma_len;          // SMA length for volume/spread baselines
    double high_mult;
    double ultra_mult;
    double low_mult;
    double high_boost;
    double ultra_boost;
    double low_boost;
    double spread_floor;
    double spread_cap;
    int    vsa_weight_mode;     // VSAWeightMode

    // VWAP output
    bool   compute_vwap;
    int    vwap_source_mode;    // VwapSourceMode (OHLC paths only; footprint path uses bin-centers)

    // Developing POC series
    bool   compute_developing_poc;
    int    dev_poc_max_points;  // cap memory

    // Smoothing / node detection
    bool   smoothing_enable;
    double smoothing_sigma_bins;
    int    smoothing_radius;
    bool   node_detect_on_smoothed;

    // Shape classification
    bool   compute_shape;
  };

  struct Profile
  {
    bool     ok;
    datetime built_ts;
    datetime range_from;
    datetime range_to;

    double price_min;
    double price_max;
    double bin_size;
    int    bins;

    // Weighted histogram summaries (legacy scanner-compatible)
    double total_w;
    double max_w;

    // Key levels (legacy-compatible outputs kept)
    double poc;
    double vah;
    double val;

    // Representative nodes (single levels kept for backward compatibility)
    double hvn;
    double lvn;

    // Weighted histogram (legacy existing arrays)
    double w_total[];
    double w_up[];
    double w_dn[];

    // ---------------- NEW: raw volume-by-price outputs ----------------
    double v_total[];   // raw total volume per bin (spec-primary output)
    double v_buy[];     // buy-side volume per bin (exact in footprint mode; heuristic in OHLC mode)
    double v_sell[];    // sell-side volume per bin
    double v_delta[];   // v_buy - v_sell per bin

    double total_volume_raw;
    double total_volume_weighted; // alias/duplicate of total_w for explicitness
    double delta_total;           // sum(v_delta)

    int    volume_mode_used;      // VolumeMode actually used for node scans / interpretation
    int    allocation_mode_used;  // AllocationMode resolved from Params
    bool   built_from_ticks;      // true if Method C / FootprintProxy path succeeded

    // ---------------- NEW: VWAP ----------------
    double vwap;
    bool   vwap_ok;

    // ---------------- NEW: developing POC ----------------
    double   dev_poc[];
    datetime dev_poc_times[];
    int      dev_poc_count;

    // ---------------- NEW: smoothing output ----------------
    double smoothed_total[];

    // ---------------- NEW: full node lists ----------------
    double hvn_prices[];
    double hvn_weights[];
    int    hvn_count;

    double lvn_prices[];
    double lvn_weights[];
    int    lvn_count;

    // ---------------- NEW: shape classification ----------------
    int    shape_code;   // ProfileShapeCode
    double shape_score;  // 0..1 confidence-like metric
  };

  struct Signals
  {
    bool touch_poc;
    bool touch_vah;
    bool touch_val;
    bool touch_hvn;
    bool touch_lvn;

    bool breakout_up;
    bool breakout_dn;

    double dist_poc_pts;
    double dist_vah_pts;
    double dist_val_pts;
    double dist_hvn_pts;
    double dist_lvn_pts;
  };

  // ---------------------------
  // Helpers
  // ---------------------------
  inline double _PointOf(const string sym)
  {
    double pt = 0.0;
    if(!SymbolInfoDouble(sym, SYMBOL_POINT, pt))
      pt = _Point;
    if(pt <= 0.0)
      pt = _Point;
    return pt;
  }

  // Volume source policy aligned with VSA.mqh:
  // prefer real volume when available, else fallback to tick volume.
  inline double _BarVolumeLikeVSA(const MqlRates &b)
  {
    if(b.real_volume > 0)
      return (double)b.real_volume;
    return (double)b.tick_volume;
  }
  
  inline double _Clamp(const double v, const double lo, const double hi)
  {
    if(v < lo) return lo;
    if(v > hi) return hi;
    return v;
  }

  inline int _ClampInt(const int v, const int lo, const int hi)
  {
    if(v < lo) return lo;
    if(v > hi) return hi;
    return v;
  }

  inline double _BinCenter(const double pmin, const double bin_size, const int idx)
  {
    return (pmin + ( (double)idx + 0.5 ) * bin_size);
  }

  inline int _PriceToBin(const double p, const double pmin, const double bin_size, const int bins)
  {
    if(bin_size <= 0.0) return 0;
    int idx = (int)MathFloor((p - pmin) / bin_size);
    if(idx < 0) idx = 0;
    if(idx >= bins) idx = bins - 1;
    return idx;
  }

  inline void _EnsureArrays(Profile &out, const int bins, const bool split_up_down)
  {
    ArrayResize(out.w_total, bins);
    ArrayInitialize(out.w_total, 0.0);

    if(split_up_down)
    {
      ArrayResize(out.w_up, bins);
      ArrayResize(out.w_dn, bins);
      ArrayInitialize(out.w_up, 0.0);
      ArrayInitialize(out.w_dn, 0.0);
    }
    else
    {
      ArrayResize(out.w_up, 0);
      ArrayResize(out.w_dn, 0);
    }

    // Optional/new arrays are managed by dedicated helpers
    _EnsureOptionalArrays(out);
  }

  // SMA over series-array ranges: i..i+len-1 (rates[0] is newest closed bar in our build)
  inline double _SMA(const double &arr[], const int i, const int len)
  {
    if(len <= 1) return arr[i];
    double s = 0.0;
    for(int k=0; k<len; k++)
      s += arr[i + k];
    return s / (double)len;
  }

  // Standard deviation over a window arr[i..i+len-1] (population stdev)
  inline double _StdWin(const double &arr[], const int i, const int len, const double mean)
  {
    if(len <= 1) return 0.0;

    double v = 0.0;
    for(int k=0; k<len; k++)
    {
      const double d = arr[i + k] - mean;
      v += d * d;
    }

    v /= (double)len;
    return (v > 0.0 ? MathSqrt(v) : 0.0);
  }
  
  inline double _VSAWeight(const double vol,
                           const double vol_ma,
                           const double spread_pts,
                           const double spread_ma_pts,
                           const Params &p)
  {
    if(!p.use_vsa) return vol;

    double m = 1.0;
    const double ultra_thr = vol_ma * p.ultra_mult;
    const double high_thr  = vol_ma * p.high_mult;
    const double low_thr   = vol_ma * p.low_mult;

    if(vol > ultra_thr)      m = p.ultra_boost;
    else if(vol > high_thr)  m = p.high_boost;
    else if(vol < low_thr)   m = p.low_boost;

    double s_ma = spread_ma_pts;
    if(s_ma <= 0.0) s_ma = 1.0;

    double spread_mult = spread_pts / s_ma;
    spread_mult = _Clamp(spread_mult, p.spread_floor, p.spread_cap);

    return (vol * m * spread_mult);
  }

  // Exact-spec-aligned VP weighting (optional mode):
  // Uses RelVol (z-score of volume) and SpreadRatio, but remains conservative by
  // reusing existing boost bounds and spread clamps from Params.
  inline double _VSAWeight_ExactSpecAligned(const double vol,
                                            const double vol_ma,
                                            const double vol_std,
                                            const double spread_pts,
                                            const double spread_ma_pts,
                                            const Params &p)
  {
    if(!p.use_vsa) return vol;

    double relVol = 0.0;
    if(vol_std > 0.0)
      relVol = (vol - vol_ma) / vol_std;

    double spreadRatio = 0.0;
    if(spread_ma_pts > 0.0)
      spreadRatio = spread_pts / spread_ma_pts;

    // SpreadRatio is an exact-spec component; keep your existing VP safety clamps
    double spread_mult = _Clamp(spreadRatio, p.spread_floor, p.spread_cap);

    // Conservative RelVol -> multiplier map (bounded by existing VP boost knobs)
    double rel_mult = 1.0 + 0.20 * relVol;
    rel_mult = _Clamp(rel_mult, p.low_boost, p.ultra_boost);

    return (vol * rel_mult * spread_mult);
  }

  // Backward-compatible dispatcher:
  // mode 0 = existing legacy heuristic
  // mode 1 = exact-spec-aligned (RelVol + SpreadRatio)
  inline double _VSAWeightEx(const double vol,
                             const double vol_ma,
                             const double vol_std,
                             const double spread_pts,
                             const double spread_ma_pts,
                             const Params &p)
  {
    if(p.vsa_weight_mode == VP_VSA_WEIGHT_EXACTSPEC)
      return _VSAWeight_ExactSpecAligned(vol, vol_ma, vol_std, spread_pts, spread_ma_pts, p);

    return _VSAWeight(vol, vol_ma, spread_pts, spread_ma_pts, p);
  }

  // Legacy weighted-only accumulator kept for compatibility/reference.
  inline void _AccumulateBin(Profile &out, const int idx, const double w, const bool is_up, const bool split_up_down)
  {
    out.w_total[idx] += w;
    if(split_up_down)
    {
      if(is_up) out.w_up[idx] += w;
      else      out.w_dn[idx] += w;
    }
  }

  // Spec Method A: strict close-price allocation (full volume to close bin)
  inline void _AccumulateByClose(Profile &out,
                                 const double pmin,
                                 const double bin_size,
                                 const int bins,
                                 const double o,
                                 const double h,
                                 const double l,
                                 const double c,
                                 const double raw_v,
                                 const double weighted_w,
                                 const bool split_up_down)
  {
    const int idx = _PriceToBin(c, pmin, bin_size, bins);
    const bool is_up = (c >= o);
    _AccumulateBinDual(out, idx, raw_v, weighted_w, is_up, split_up_down);
  }
  
  // Legacy compatibility path: typical-price allocation (NOT spec Method A)
  inline void _AccumulateByTypical(Profile &out,
                                   const double pmin,
                                   const double bin_size,
                                   const int bins,
                                   const double o,
                                   const double h,
                                   const double l,
                                   const double c,
                                   const double raw_v,
                                   const double weighted_w,
                                   const bool split_up_down)
  {
    const double tp = (h + l + c) / 3.0;
    const int idx = _PriceToBin(tp, pmin, bin_size, bins);
    const bool is_up = (c >= o);
    _AccumulateBinDual(out, idx, raw_v, weighted_w, is_up, split_up_down);
  }

  inline void _AccumulateByRange(Profile &out,
                                 const double pmin,
                                 const double bin_size,
                                 const int bins,
                                 const double o,
                                 const double h,
                                 const double l,
                                 const double c,
                                 const double raw_v,
                                 const double weighted_w,
                                 const bool split_up_down)
  {
    const bool is_up = (c >= o);

    const double lo = MathMin(l, h);
    const double hi = MathMax(l, h);
    const double rng = hi - lo;

    // Zero-range candle edge case -> assign full to close bin (spec-safe)
    if(rng <= 0.0)
    {
      _AccumulateByClose(out, pmin, bin_size, bins, o, h, l, c, raw_v, weighted_w, split_up_down);
      return;
    }

    int idx_lo = _PriceToBin(lo, pmin, bin_size, bins);
    int idx_hi = _PriceToBin(hi, pmin, bin_size, bins);
    if(idx_hi < idx_lo)
    {
      int t = idx_hi;
      idx_hi = idx_lo;
      idx_lo = t;
    }

    for(int idx = idx_lo; idx <= idx_hi; idx++)
    {
      const double bin_lo = pmin + (double)idx * bin_size;
      const double bin_hi = bin_lo + bin_size;

      const double ov_lo = MathMax(bin_lo, lo);
      const double ov_hi = MathMin(bin_hi, hi);
      const double ov = ov_hi - ov_lo;

      if(ov > 0.0)
      {
        const double frac = ov / rng;
        _AccumulateBinDual(out, idx, raw_v * frac, weighted_w * frac, is_up, split_up_down);
      }
    }
  }

  inline void _EnsureRawArrays(Profile &out, const int bins)
  {
    ArrayResize(out.v_total, bins);
    ArrayResize(out.v_buy,   bins);
    ArrayResize(out.v_sell,  bins);
    ArrayResize(out.v_delta, bins);

    ArrayInitialize(out.v_total, 0.0);
    ArrayInitialize(out.v_buy,   0.0);
    ArrayInitialize(out.v_sell,  0.0);
    ArrayInitialize(out.v_delta, 0.0);
  }

  inline void _EnsureOptionalArrays(Profile &out)
  {
    ArrayResize(out.smoothed_total, 0);

    ArrayResize(out.hvn_prices, 0);
    ArrayResize(out.hvn_weights, 0);
    out.hvn_count = 0;

    ArrayResize(out.lvn_prices, 0);
    ArrayResize(out.lvn_weights, 0);
    out.lvn_count = 0;

    ArrayResize(out.dev_poc, 0);
    ArrayResize(out.dev_poc_times, 0);
    out.dev_poc_count = 0;
  }

  // Accumulate both raw volume and weighted histogram
  // OHLC mode buy/sell split is heuristic by candle direction (exact split is only available in footprint path)
  inline void _AccumulateBinDual(Profile &out,
                                 const int idx,
                                 const double raw_v,
                                 const double weighted_w,
                                 const bool is_up,
                                 const bool split_up_down)
  {
    if(idx < 0 || idx >= out.bins) return;
    if(raw_v <= 0.0 && weighted_w <= 0.0) return;

    out.w_total[idx] += weighted_w;
    out.v_total[idx] += raw_v;

    if(split_up_down)
    {
      if(is_up) out.w_up[idx] += weighted_w;
      else      out.w_dn[idx] += weighted_w;
    }

    // Heuristic raw buy/sell split (bar-direction allocation) for OHLC methods
    if(is_up)
    {
      out.v_buy[idx]   += raw_v;
      out.v_delta[idx] += raw_v;
    }
    else
    {
      out.v_sell[idx]  += raw_v;
      out.v_delta[idx] -= raw_v;
    }
  }
  
  inline int _FindPOCIndex(const Profile &out)
  {
    int best = 0;
    double best_w = -1.0;
    const int n = out.bins;
    for(int i=0; i<n; i++)
    {
      const double w = out.w_total[i];
      if(w > best_w)
      {
        best_w = w;
        best = i;
      }
    }
    return best;
  }

  inline void _ComputeValueArea(const Profile &out,
                                const int poc_idx,
                                const double va_pct,
                                int &out_left,
                                int &out_right)
  {
    const int n = out.bins;
    out_left = poc_idx;
    out_right = poc_idx;

    if(n <= 1) return;

    double total = 0.0;
    for(int i=0; i<n; i++) total += out.w_total[i];

    const double target = total * _Clamp(va_pct, 0.01, 0.99);
    double acc = out.w_total[poc_idx];

    int L = poc_idx - 1;
    int R = poc_idx + 1;

    while(acc < target && (L >= 0 || R < n))
    {
      const double wL = (L >= 0 ? out.w_total[L] : -1.0);
      const double wR = (R < n ? out.w_total[R] : -1.0);

      if(wR > wL)
      {
        if(R < n) { acc += wR; out_right = R; R++; }
        else if(L >= 0) { acc += wL; out_left = L; L--; }
      }
      else
      {
        if(L >= 0) { acc += wL; out_left = L; L--; }
        else if(R < n) { acc += wR; out_right = R; R++; }
      }
    }
  }

  // Ranked-desc Value Area (AOFIDS literal-style):
  // - Seed with POC bin
  // - Add next highest-volume bins (by weighted histogram basis) until target coverage is reached
  // - Return VAH/VAL as a contiguous envelope spanning selected bins
  //
  // This preserves the module's existing VAH/VAL output model while allowing a non-contiguous
  // selection policy internally.
  inline void _ComputeValueAreaRanked(const Profile &out,
                                      const int poc_idx,
                                      const double va_pct,
                                      int &out_left,
                                      int &out_right)
  {
    const int n = out.bins;
    out_left = poc_idx;
    out_right = poc_idx;

    if(n <= 1) return;
    if(poc_idx < 0 || poc_idx >= n) return;

    double total = 0.0;
    for(int i=0; i<n; i++)
      total += out.w_total[i];

    const double target = total * _Clamp(va_pct, 0.01, 0.99);
    if(target <= 0.0) return;

    bool picked[];
    ArrayResize(picked, n);
    for(int i=0; i<n; i++) picked[i] = false;

    double acc = 0.0;
    int picked_count = 0;

    // Always seed with POC to preserve expected VP semantics
    picked[poc_idx] = true;
    picked_count = 1;
    acc = out.w_total[poc_idx];

    while(acc < target && picked_count < n)
    {
      int best_i = -1;
      double best_w = -1.0;

      for(int i=0; i<n; i++)
      {
        if(picked[i]) continue;

        const double w = out.w_total[i];
        if(w > best_w)
        {
          best_w = w;
          best_i = i;
        }
      }

      if(best_i < 0)
        break;

      picked[best_i] = true;
      picked_count++;

      if(best_w > 0.0)
        acc += best_w;

      if(best_i < out_left)  out_left = best_i;
      if(best_i > out_right) out_right = best_i;
    }
  }
  
  inline void _GaussianSmooth1D(const double &src[],
                                const int n,
                                const int radius,
                                const double sigma,
                                double &dst[])
  {
    ArrayResize(dst, 0);
    if(n <= 0) return;

    ArrayResize(dst, n);
    if(radius <= 0 || sigma <= 0.0)
    {
      for(int i=0; i<n; i++) dst[i] = src[i];
      return;
    }

    const int r = radius;
    double kernel[];
    ArrayResize(kernel, 2*r + 1);

    double sum_k = 0.0;
    for(int j=-r; j<=r; j++)
    {
      const double x = (double)j;
      const double w = MathExp(-(x*x) / (2.0 * sigma * sigma));
      kernel[j + r] = w;
      sum_k += w;
    }
    if(sum_k <= 0.0) sum_k = 1.0;

    for(int i=0; i<n; i++)
    {
      double acc = 0.0;
      double acc_w = 0.0;

      for(int j=-r; j<=r; j++)
      {
        int k = i + j;
        if(k < 0) k = 0;
        if(k >= n) k = n - 1;

        const double kw = kernel[j + r] / sum_k;
        acc += src[k] * kw;
        acc_w += kw;
      }

      dst[i] = (acc_w > 0.0 ? acc / acc_w : src[i]);
    }
  }

  inline void _CollectLocalNodes(const Profile &out,
                                 const double &arr[],
                                 double &hvn_prices[],
                                 double &hvn_weights[],
                                 int &hvn_count,
                                 double &lvn_prices[],
                                 double &lvn_weights[],
                                 int &lvn_count)
  {
    hvn_count = 0;
    lvn_count = 0;
    ArrayResize(hvn_prices, 0);
    ArrayResize(hvn_weights, 0);
    ArrayResize(lvn_prices, 0);
    ArrayResize(lvn_weights, 0);

    const int n = out.bins;
    if(n < 3) return;

    for(int i=1; i<n-1; i++)
    {
      const double a = arr[i-1];
      const double b = arr[i];
      const double c = arr[i+1];

      if(b > a && b > c) // HVN local max
      {
        const int k = hvn_count;
        ArrayResize(hvn_prices,  k + 1);
        ArrayResize(hvn_weights, k + 1);
        hvn_prices[k]  = _BinCenter(out.price_min, out.bin_size, i);
        hvn_weights[k] = b;
        hvn_count++;
      }
      else if(b < a && b < c) // LVN local min
      {
        const int k2 = lvn_count;
        ArrayResize(lvn_prices,  k2 + 1);
        ArrayResize(lvn_weights, k2 + 1);
        lvn_prices[k2]  = _BinCenter(out.price_min, out.bin_size, i);
        lvn_weights[k2] = b;
        lvn_count++;
      }
    }
  }
  
  inline void _DevPOCAppend(Profile &out,
                            const Params &p,
                            const datetime t_bar,
                            const int poc_idx)
  {
    if(!p.compute_developing_poc) return;
    if(p.dev_poc_max_points <= 0) return;
    if(poc_idx < 0 || poc_idx >= out.bins) return;

    if(out.dev_poc_count >= p.dev_poc_max_points)
      return;

    const int k = out.dev_poc_count;
    ArrayResize(out.dev_poc, k + 1);
    ArrayResize(out.dev_poc_times, k + 1);

    out.dev_poc[k] = _BinCenter(out.price_min, out.bin_size, poc_idx);
    out.dev_poc_times[k] = t_bar;
    out.dev_poc_count++;
  }

  inline void _ClassifyShape(Profile &out, const double &arr[])
  {
    out.shape_code = VP_SHAPE_UNKNOWN;
    out.shape_score = 0.0;

    if(out.bins < 5 || out.max_w <= 0.0) return;

    const int poc_idx = _PriceToBin(out.poc, out.price_min, out.bin_size, out.bins);
    const double poc_pos = (out.bins > 1 ? (double)poc_idx / (double)(out.bins - 1) : 0.5);

    // Secondary peak and valley depth heuristic
    int peak1 = _FindPOCIndex(out);
    int peak2 = _FindSecondMaxIndex(out, peak1);

    double peak2w = (peak2 >= 0 && peak2 < out.bins ? arr[peak2] : 0.0);
    double valley_min = out.max_w;

    if(peak2 >= 0)
    {
      int lo = MathMin(peak1, peak2);
      int hi = MathMax(peak1, peak2);
      for(int i=lo; i<=hi; i++)
        if(arr[i] < valley_min) valley_min = arr[i];
    }

    const double sec_peak_frac = (out.max_w > 0.0 ? peak2w / out.max_w : 0.0);
    const double valley_frac   = (out.max_w > 0.0 ? valley_min / out.max_w : 1.0);

    // Double distribution (two meaningful peaks with valley between)
    if(sec_peak_frac >= 0.60 && valley_frac <= 0.45)
    {
      out.shape_code  = VP_SHAPE_DOUBLE_DISTRIBUTION;
      out.shape_score = _Clamp(0.5 * sec_peak_frac + 0.5 * (1.0 - valley_frac), 0.0, 1.0);
      return;
    }

    // P/b/D heuristic by POC location
    if(poc_pos >= 0.62)
    {
      out.shape_code  = VP_SHAPE_P_SHORT_COVERING;
      out.shape_score = _Clamp((poc_pos - 0.62) / 0.38, 0.0, 1.0);
    }
    else if(poc_pos <= 0.38)
    {
      out.shape_code  = VP_SHAPE_B_LONG_LIQUIDATION;
      out.shape_score = _Clamp((0.38 - poc_pos) / 0.38, 0.0, 1.0);
    }
    else
    {
      out.shape_code  = VP_SHAPE_D_BALANCED;
      out.shape_score = _Clamp(1.0 - MathAbs(poc_pos - 0.5) * 4.0, 0.0, 1.0);
    }
  }
  
  // Resolves profile window semantics into either:
  //  - rolling bar mode (use_bars_mode = true), or
  //  - explicit time range (use_bars_mode = false, out_from/out_to filled)
  //
  // NOTE:
  // This backend resolver is intentionally self-contained (no TimeUtils dependency yet).
  // Session/composite/anchored are resolved using server-time day windows.
  inline bool _ResolveProfileWindow(const Params &p_in,
                                    const ENUM_TIMEFRAMES tf,
                                    bool &use_bars_mode,
                                    int &out_profile_bars,
                                    datetime &out_from,
                                    datetime &out_to)
  {
    Params p = p_in;
    use_bars_mode = true;
    out_profile_bars = p.lookback_bars;
    out_from = 0;
    out_to = 0;

    const int prof_type = _ClampInt(p.profile_type, VP_PROFILE_ROLLING_BARS, VP_PROFILE_ROLLING_WINDOW);

    if(prof_type == VP_PROFILE_ROLLING_BARS || prof_type == VP_PROFILE_ROLLING_WINDOW)
    {
      use_bars_mode = true;
      out_profile_bars = (p.lookback_bars > 0 ? p.lookback_bars : 200);
      return true;
    }

    // Explicit range-like modes
    if((prof_type == VP_PROFILE_TIME_RANGE ||
        prof_type == VP_PROFILE_FIXED_RANGE ||
        prof_type == VP_PROFILE_VISIBLE_RANGE) &&
       p.range_from > 0 && p.range_to > 0 && p.range_to > p.range_from)
    {
      use_bars_mode = false;
      out_from = p.range_from;
      out_to   = p.range_to;
      return true;
    }

    // SESSION / ANCHORED / COMPOSITE fallback windowing (server-time day-based backend helper)
    const datetime now_ts = TimeCurrent();
    if(now_ts <= 0) return false;

    const int anchor_min = _ClampInt(p.anchor_minute_utc, 0, 1439);

    MqlDateTime dt;
    TimeToStruct(now_ts, dt);

    // Server-day midnight
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime day0 = StructToTime(dt);

    datetime anchor_ts = day0 + anchor_min * 60;
    if(anchor_ts > now_ts)
      anchor_ts -= 86400;

    if(prof_type == VP_PROFILE_SESSION)
    {
      use_bars_mode = false;
      out_from = (p.session_mode == VP_SESSION_ANCHORED ? anchor_ts : day0);
      out_to   = now_ts;
      return (out_to > out_from);
    }

    if(prof_type == VP_PROFILE_ANCHORED)
    {
      use_bars_mode = false;
      // Caller may supply explicit anchor in range_from; if not, use resolved anchor_ts
      out_from = (p.range_from > 0 ? p.range_from : anchor_ts);
      out_to   = (p.range_to   > 0 ? p.range_to   : now_ts);
      return (out_to > out_from);
    }

    if(prof_type == VP_PROFILE_COMPOSITE)
    {
      const int sessions = (p.composite_sessions > 0 ? p.composite_sessions : 3);
      use_bars_mode = false;
      out_to = now_ts;
      // Day-based composite fallback (backend-safe; later can be upgraded to TimeUtils session windows)
      out_from = anchor_ts - (datetime)((sessions - 1) * 86400);
      return (out_to > out_from);
    }

    // Fallback to rolling bars if mode unsupported or caller did not provide a valid range
    use_bars_mode = true;
    out_profile_bars = (p.lookback_bars > 0 ? p.lookback_bars : 200);
    return true;
  }
  
  // Spec Method C (tick-level / proxy) path via FootprintProxy::BuildRange
  // Returns false if the footprint range build is unavailable/fails; caller should fallback.
  inline bool _BuildProfileFromFootprintRange(const string sym,
                                              const ENUM_TIMEFRAMES tf,
                                              const Params &p,
                                              const int from_shift,
                                              const int bars_count,
                                              Profile &out)
  {
    if(!p.allow_tick_footprint) return false;
    if(bars_count <= 0) return false;
    if(from_shift < 0) return false;
    if(bars_count < MathMax(1, p.footprint_min_bars)) return false;

    FootprintProxy::FPConfig fpc;
    fpc.SetDefaults();

    // Grid setup (best-effort coherence with VP params)
    if(p.bin_points > 0) fpc.bin_points = p.bin_points;
    if(p.max_bins > 0)   fpc.max_levels = p.max_bins;
    fpc.value_area_pct = p.value_area_pct;

    FootprintProxy::FPBar fp;
    const int fp_mode_i = _ClampInt(p.footprint_build_mode, 0, 2);
    const FootprintProxy::FPBuildMode mode = (FootprintProxy::FPBuildMode)fp_mode_i;

    if(!FootprintProxy::BuildRange(sym, tf, from_shift, bars_count, fpc, fp, mode))
      return false;

    if(fp.levels <= 0 || fp.step <= 0.0)
      return false;

    // Build VP grid directly from footprint range grid (no remapping / no double binning)
    out.price_min = fp.price_min;
    out.price_max = fp.price_max;
    out.bin_size  = fp.step;
    out.bins      = fp.levels;
    out.built_from_ticks = fp.built_from_ticks;
    out.allocation_mode_used = VP_ALLOC_TICK_FOOTPRINT;

    _EnsureArrays(out, out.bins, p.split_up_down);
    _EnsureRawArrays(out, out.bins);

    for(int i=0; i<out.bins; i++)
    {
      const double vb = (i < ArraySize(fp.buy)   ? fp.buy[i]   : 0.0);
      const double vs = (i < ArraySize(fp.sell)  ? fp.sell[i]  : 0.0);
      const double vt = (i < ArraySize(fp.total) ? fp.total[i] : (vb + vs));
      const double vd = (i < ArraySize(fp.delta) ? fp.delta[i] : (vb - vs));

      out.v_buy[i]   = vb;
      out.v_sell[i]  = vs;
      out.v_total[i] = vt;
      out.v_delta[i] = vd;

      // Weighted path = raw path in tick/footprint mode (conservative default)
      out.w_total[i] = vt;
      if(p.split_up_down)
      {
        out.w_up[i] = vb;
        out.w_dn[i] = vs;
      }
    }

    // Raw/weighted summaries
    out.total_volume_raw      = fp.total_vol;
    out.total_w               = fp.total_vol;
    out.total_volume_weighted = out.total_w;
    out.delta_total           = fp.delta_total;
    out.max_w                 = fp.poc_vol;

    // Direct level reuse from FootprintProxy (kept but finalized again for consistency later)
    out.poc = fp.poc_price;
    out.vah = fp.vah;
    out.val = fp.val;

    // Exact bin-centered VWAP from footprint totals
    double sum_px_vol = 0.0;
    double sum_vol = 0.0;
    for(int i2=0; i2<out.bins; i2++)
    {
      const double v = out.v_total[i2];
      if(v <= 0.0) continue;
      const double px = _BinCenter(out.price_min, out.bin_size, i2);
      sum_px_vol += px * v;
      sum_vol    += v;
    }
    out.vwap = (sum_vol > 0.0 ? (sum_px_vol / sum_vol) : 0.0);
    out.vwap_ok = (sum_vol > 0.0);

    return (out.total_w > 0.0);
  }
  
  // Legacy representative-node helpers kept for backward compatibility.
  // Full node lists are populated separately via _CollectLocalNodes(...).
  inline int _FindSecondMaxIndex(const Profile &out, const int exclude_idx)
  {
    int best = -1;
    double best_w = -1.0;
    for(int i=0; i<out.bins; i++)
    {
      if(i == exclude_idx) continue;
      const double w = out.w_total[i];
      if(w > best_w)
      {
        best_w = w;
        best = i;
      }
    }
    return best;
  }

  inline int _FindLVNIndexNearPOC(const Profile &out, const int poc_idx, const double lvn_frac)
  {
    const double thr = out.max_w * _Clamp(lvn_frac, 0.01, 0.80);
    const int n = out.bins;

    int best = -1;
    double best_w = 1e100;

    // Search outward from POC for the first meaningful low-volume pocket
    for(int r=1; r<n; r++)
    {
      const int i1 = poc_idx - r;
      const int i2 = poc_idx + r;

      if(i1 >= 0)
      {
        const double w = out.w_total[i1];
        if(w > 0.0 && w <= thr && w < best_w) { best_w = w; best = i1; }
      }
      if(i2 < n)
      {
        const double w = out.w_total[i2];
        if(w > 0.0 && w <= thr && w < best_w) { best_w = w; best = i2; }
      }

      // If we found a decent candidate close to POC, stop early
      if(best != -1 && r >= 5) break;
    }

    // Fallback: global minimum non-zero
    if(best == -1)
    {
      for(int i=0; i<n; i++)
      {
        const double w = out.w_total[i];
        if(w > 0.0 && w < best_w) { best_w = w; best = i; }
      }
    }
    return best;
  }

  // ---------------------------
  // Public API
  // ---------------------------
  Params ParamsDefault()
  {
    Params p;
    p.profile_type   = VP_PROFILE_ROLLING_BARS;
    p.range_from     = 0;
    p.range_to       = 0;
    p.max_range_bars = 5000;

    p.session_mode        = VP_SESSION_BROKER_DAY;
    p.anchor_minute_utc   = 0;
    p.composite_sessions  = 3;
    
    p.lookback_bars       = 200;
    p.bin_points          = 10;
    p.bin_mode            = VP_BIN_BY_POINTS;
    p.bin_count           = 64;     // spec-friendly default when using BIN_BY_COUNT
    p.value_area_pct      = 0.70;
    p.value_area_method   = VP_VA_POC_OUTWARD; // preserve current behavior
    p.max_bins            = 400;

    // Backward-compatible default:
    // AUTO + distribute_by_range=false => legacy typical allocation
    p.alloc_mode          = VP_ALLOC_AUTO;
    p.distribute_by_range = false;
    p.split_up_down       = false;

    p.volume_mode         = VP_VOL_TOTAL;
    p.delta_mode          = false;

    p.allow_tick_footprint = false; // preserve legacy lightweight behavior
    p.footprint_build_mode = 0;     // AUTO
    p.footprint_min_bars   = 20;

    p.use_vsa      = true;
    p.vsa_ma_len   = 30;
    p.high_mult    = 1.5;
    p.ultra_mult   = 3.0;
    p.low_mult     = 0.5;

    // Conservative VSA boosts
    p.high_boost   = 1.25;
    p.ultra_boost  = 1.60;
    p.low_boost    = 0.70;

    p.spread_floor = 0.50;
    p.spread_cap   = 2.00;
    p.vsa_weight_mode = VP_VSA_WEIGHT_LEGACY;

    p.compute_vwap     = true;
    p.vwap_source_mode = VP_VWAP_HLC3;

    p.compute_developing_poc = false;
    p.dev_poc_max_points     = 512;

    p.smoothing_enable       = false;
    p.smoothing_sigma_bins   = 1.25;
    p.smoothing_radius       = 2;
    p.node_detect_on_smoothed= false;

    p.compute_shape = false;

    return p;
  }

  void Reset(Profile &out)
  {
    out.ok = false;
    out.built_ts = 0;
    out.range_from = 0;
    out.range_to = 0;

    out.price_min = 0.0;
    out.price_max = 0.0;
    out.bin_size  = 0.0;
    out.bins      = 0;

    out.total_w = 0.0;
    out.max_w   = 0.0;

    out.poc = 0.0;
    out.vah = 0.0;
    out.val = 0.0;

    out.hvn = 0.0;
    out.lvn = 0.0;

    ArrayResize(out.w_total, 0);
    ArrayResize(out.w_up, 0);
    ArrayResize(out.w_dn, 0);

    ArrayResize(out.v_total, 0);
    ArrayResize(out.v_buy, 0);
    ArrayResize(out.v_sell, 0);
    ArrayResize(out.v_delta, 0);

    out.total_volume_raw = 0.0;
    out.total_volume_weighted = 0.0;
    out.delta_total = 0.0;

    out.volume_mode_used = VP_VOL_TOTAL;
    out.allocation_mode_used = VP_ALLOC_AUTO;
    out.built_from_ticks = false;

    out.vwap = 0.0;
    out.vwap_ok = false;

    ArrayResize(out.dev_poc, 0);
    ArrayResize(out.dev_poc_times, 0);
    out.dev_poc_count = 0;

    ArrayResize(out.smoothed_total, 0);

    ArrayResize(out.hvn_prices, 0);
    ArrayResize(out.hvn_weights, 0);
    out.hvn_count = 0;

    ArrayResize(out.lvn_prices, 0);
    ArrayResize(out.lvn_weights, 0);
    out.lvn_count = 0;

    out.shape_code = VP_SHAPE_UNKNOWN;
    out.shape_score = 0.0;
  }

  // Build a profile either from:
  // - closed bars (ROLLING_BARS): shift=1..lookback_bars (default)
  // - time range (TIME_RANGE): [range_from..range_to] (caller provides times)
  inline bool BuildProfile(const string sym,
                           const ENUM_TIMEFRAMES tf,
                           const Params &p_in,
                           Profile &out)
  {
    Reset(out);
    Params p = p_in;

    // ---------------- Core / legacy sanitizers (restore backward stability) ----------------
    if(p.lookback_bars < 20) p.lookback_bars = 20;
    if(p.bin_points < 1)     p.bin_points = 1;
    p.value_area_pct = _Clamp(p.value_area_pct, 0.05, 0.95);
    p.value_area_method = _ClampInt(p.value_area_method, VP_VA_POC_OUTWARD, VP_VA_RANKED_DESC);
    p.max_bins = _ClampInt(p.max_bins, 50, 2000);
    p.vsa_ma_len = _ClampInt(p.vsa_ma_len, 3, 200);
    p.vsa_weight_mode = _ClampInt(p.vsa_weight_mode, VP_VSA_WEIGHT_LEGACY, VP_VSA_WEIGHT_EXACTSPEC);

    p.profile_type   = _ClampInt(p.profile_type, VP_PROFILE_ROLLING_BARS, VP_PROFILE_ROLLING_WINDOW);
    p.max_range_bars = _ClampInt(p.max_range_bars, 50, 200000);

    // ---------------- Extended sanitizers ----------------
    p.bin_mode = _ClampInt(p.bin_mode, VP_BIN_BY_POINTS, VP_BIN_BY_COUNT);
    p.bin_count = _ClampInt(p.bin_count, 5, 2000);

    p.alloc_mode = _ClampInt(p.alloc_mode, VP_ALLOC_AUTO, VP_ALLOC_TICK_FOOTPRINT);
    p.volume_mode = _ClampInt(p.volume_mode, VP_VOL_TOTAL, VP_VOL_DELTA);

    p.session_mode = _ClampInt(p.session_mode, VP_SESSION_BROKER_DAY, VP_SESSION_ANCHORED);
    p.anchor_minute_utc = _ClampInt(p.anchor_minute_utc, 0, 1439);
    p.composite_sessions = _ClampInt(p.composite_sessions, 1, 100);

    p.footprint_build_mode = _ClampInt(p.footprint_build_mode, 0, 2);
    p.footprint_min_bars   = _ClampInt(p.footprint_min_bars, 1, 50000);

    p.vwap_source_mode = _ClampInt(p.vwap_source_mode, VP_VWAP_HLC3, VP_VWAP_TYPICAL);

    p.dev_poc_max_points = _ClampInt(p.dev_poc_max_points, 0, 100000);

    p.smoothing_sigma_bins = _Clamp(p.smoothing_sigma_bins, 0.05, 20.0);
    p.smoothing_radius     = _ClampInt(p.smoothing_radius, 0, 100);

    p.compute_shape = (p.compute_shape ? true : false);

    // Basic range sanity (used only in TIME_RANGE mode)
    if(p.range_from < 0) p.range_from = 0;
    if(p.range_to   < 0) p.range_to   = 0;
    
    const double pt = _PointOf(sym);
    if(pt <= 0.0) return false;

    int profile_bars = p.lookback_bars;

    // Need extra bars for VSA baselines in rolling mode only
    int need = p.lookback_bars + p.vsa_ma_len + 5;

    bool use_bars_mode = true;
    datetime win_from = 0;
    datetime win_to   = 0;
    if(!_ResolveProfileWindow(p, tf, use_bars_mode, profile_bars, win_from, win_to))
      return false;

    // Backward compatibility mapping:
    // AUTO preserves historical behavior:
    //   distribute_by_range=true  -> proportional (spec Method B)
    //   distribute_by_range=false -> typical (legacy path)
    int alloc_mode_eff = p.alloc_mode;
    if(alloc_mode_eff == VP_ALLOC_AUTO)
      alloc_mode_eff = (p.distribute_by_range ? VP_ALLOC_RANGE_PROPORTIONAL : VP_ALLOC_TYPICAL);
      
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    int got = 0;

    if(use_bars_mode)
    {
      // Rolling modes: use closed bars, with extra preload for VSA baselines
      got = CopyRates(sym, tf, 1, need, rates);
      profile_bars = (profile_bars > 0 ? profile_bars : p.lookback_bars);
    }
    else
    {
      // Time/range/session/composite/anchored/visible: explicit window
      got = CopyRates(sym, tf, win_from, win_to, rates);
      profile_bars = got;
      if(profile_bars > p.max_range_bars) profile_bars = p.max_range_bars;
    }

    if(got < 25) return false;
    if(profile_bars < 20) return false;

    // Rolling modes need preload bars for VSA baseline windows.
    // Explicit time/range modes do NOT require got >= profile_bars+5.
    if(use_bars_mode)
    {
      if(got < profile_bars + 5) return false;
    }
    else
    {
      if(got < profile_bars) return false;
    }

    // Spec Method C (tick-level / proxy via FootprintProxy::BuildRange)
    // Try only when requested; fallback to OHLC path if it fails.
    if(alloc_mode_eff == VP_ALLOC_TICK_FOOTPRINT)
    {
      // BuildRange expects oldest shift + count.
      // rates[0] = newest in window, rates[profile_bars-1] = oldest in profiled slice
      const datetime t_oldest = rates[profile_bars - 1].time;
      int from_shift = iBarShift(sym, tf, t_oldest, false);

      if(from_shift >= 0)
      {
        if(_BuildProfileFromFootprintRange(sym, tf, p, from_shift, profile_bars, out))
        {
          out.range_to   = rates[0].time;
          out.range_from = rates[profile_bars - 1].time;
          out.volume_mode_used = p.volume_mode;

          // Optional smoothing for node detection/output
          if(p.smoothing_enable)
            _GaussianSmooth1D(out.v_total, out.bins, p.smoothing_radius, p.smoothing_sigma_bins, out.smoothed_total);

          // Summaries derived from chosen node basis (raw or smoothed)
          if(p.node_detect_on_smoothed && ArraySize(out.smoothed_total) == out.bins)
          {
            _CollectLocalNodes(out, out.smoothed_total,
                               out.hvn_prices, out.hvn_weights, out.hvn_count,
                               out.lvn_prices, out.lvn_weights, out.lvn_count);
          }
          else
          {
            _CollectLocalNodes(out, out.v_total,
                               out.hvn_prices, out.hvn_weights, out.hvn_count,
                               out.lvn_prices, out.lvn_weights, out.lvn_count);
          }

          // Backward-compatible representative HVN/LVN (use existing legacy helpers as fallback)
          const int hvn_idx2 = _FindSecondMaxIndex(out, _FindPOCIndex(out));
          if(hvn_idx2 >= 0) out.hvn = _BinCenter(out.price_min, out.bin_size, hvn_idx2);

          const int lvn_idx2 = _FindLVNIndexNearPOC(out, _FindPOCIndex(out), 0.15);
          if(lvn_idx2 >= 0) out.lvn = _BinCenter(out.price_min, out.bin_size, lvn_idx2);

          if(p.compute_shape)
          {
            if(p.node_detect_on_smoothed && ArraySize(out.smoothed_total) == out.bins)
              _ClassifyShape(out, out.smoothed_total);
            else
              _ClassifyShape(out, out.v_total);
          }

          out.ok = true;
          out.built_ts = TimeCurrent();
          return true;
        }
      }

      // If Method C requested but unavailable, continue with OHLC fallback (graceful degradation)
      alloc_mode_eff = (p.distribute_by_range ? VP_ALLOC_RANGE_PROPORTIONAL : VP_ALLOC_TYPICAL);
    }
    
    // Range min/max across the profiled window (closed bars only)
    double pmin = rates[0].low;
    double pmax = rates[0].high;

    for(int i=0; i<profile_bars; i++)
    {
      if(rates[i].low  < pmin) pmin = rates[i].low;
      if(rates[i].high > pmax) pmax = rates[i].high;
    }

    if(pmax <= pmin)
      return false;

    double bin_size = (double)p.bin_points * pt;
    if(bin_size <= 0.0) bin_size = pt;

    int bins = 0;

    // Grid mode: by count (spec) or by points (legacy)
    if(p.bin_mode == VP_BIN_BY_COUNT && p.bin_count >= 5)
    {
      bins = _ClampInt(p.bin_count, 5, p.max_bins);
      bin_size = (pmax - pmin) / (double)bins;
      if(bin_size <= 0.0) return false;

      // Snap bin size to point multiple, then recompute actual bins
      bin_size = MathMax(pt, MathCeil(bin_size / pt) * pt);
      bins = (int)MathFloor((pmax - pmin) / bin_size) + 1;
      bins = _ClampInt(bins, 5, p.max_bins);
    }
    else
    {
      bins = (int)MathFloor((pmax - pmin) / bin_size) + 1;
      if(bins < 5) bins = 5;

      if(bins > p.max_bins)
      {
        bin_size = (pmax - pmin) / (double)p.max_bins;
        bin_size = MathMax(pt, MathCeil(bin_size / pt) * pt);
        bins = (int)MathFloor((pmax - pmin) / bin_size) + 1;
        bins = _ClampInt(bins, 5, p.max_bins);
      }
    }

    out.price_min = pmin;
    out.price_max = pmax;
    out.bin_size  = bin_size;
    out.bins      = bins;
    out.allocation_mode_used = alloc_mode_eff;
    out.volume_mode_used = p.volume_mode;
    out.built_from_ticks = false;

    _EnsureArrays(out, bins, p.split_up_down);
    _EnsureRawArrays(out, bins);

    // Precompute vol & spread arrays for SMA baselines
    const int n = got;
    double v_arr[];
    double s_arr[];
    ArrayResize(v_arr, n);
    ArrayResize(s_arr, n);

    for(int i=0; i<n; i++)
    {
      v_arr[i] = _BarVolumeLikeVSA(rates[i]);
      const double spr = (rates[i].high - rates[i].low) / pt;
      s_arr[i] = MathMax(0.0, spr);
    }

    // Accumulate histogram (raw volume + weighted volume)
    double sum_vwap_px_vol = 0.0;
    double sum_vwap_vol    = 0.0;

    for(int i=0; i<profile_bars; i++)
    {
      const double o = rates[i].open;
      const double h = rates[i].high;
      const double l = rates[i].low;
      const double c = rates[i].close;

      const double raw_vol = v_arr[i];

      double vma = raw_vol;
      double sma_spr = s_arr[i];

      if(i + p.vsa_ma_len < n)
      {
        vma     = _SMA(v_arr, i, p.vsa_ma_len);
        sma_spr = _SMA(s_arr, i, p.vsa_ma_len);
      }

      double vstd = 0.0;
      if(i + p.vsa_ma_len < n)
        vstd = _StdWin(v_arr, i, p.vsa_ma_len, vma);

      const double spr_pts = s_arr[i];
      const double weighted_w = _VSAWeightEx(raw_vol, vma, vstd, spr_pts, sma_spr, p);

      if(raw_vol <= 0.0 && weighted_w <= 0.0)
        continue;

      // Explicit allocation mode (AUTO already resolved into alloc_mode_eff)
      if(alloc_mode_eff == VP_ALLOC_RANGE_PROPORTIONAL)
      {
        _AccumulateByRange(out, pmin, bin_size, bins, o, h, l, c, raw_vol, weighted_w, p.split_up_down);
      }
      else if(alloc_mode_eff == VP_ALLOC_CLOSE)
      {
        _AccumulateByClose(out, pmin, bin_size, bins, o, h, l, c, raw_vol, weighted_w, p.split_up_down);
      }
      else // VP_ALLOC_TYPICAL fallback (legacy)
      {
        _AccumulateByTypical(out, pmin, bin_size, bins, o, h, l, c, raw_vol, weighted_w, p.split_up_down);
      }

      // OHLC-based VWAP accumulation (spec 4.1)
      if(p.compute_vwap && raw_vol > 0.0)
      {
        double px_vwap = 0.0;
        if(p.vwap_source_mode == VP_VWAP_CLOSE)      px_vwap = c;
        else if(p.vwap_source_mode == VP_VWAP_TYPICAL) px_vwap = (h + l + c) / 3.0;
        else                                         px_vwap = (h + l + c) / 3.0; // HLC3 default

        sum_vwap_px_vol += px_vwap * raw_vol;
        sum_vwap_vol    += raw_vol;
      }

      // Developing POC (rolling POC_t)
      if(p.compute_developing_poc)
      {
        const int poc_idx_now = _FindPOCIndex(out);
        _DevPOCAppend(out, p, rates[i].time, poc_idx_now);
      }
    }

    out.vwap    = (p.compute_vwap && sum_vwap_vol > 0.0 ? (sum_vwap_px_vol / sum_vwap_vol) : 0.0);
    out.vwap_ok = (p.compute_vwap && sum_vwap_vol > 0.0);

    // ---------------- Finalize: summaries + levels + optional derived outputs ----------------
    double total_w = 0.0;
    double mx_w = 0.0;

    double total_v = 0.0;
    double total_delta = 0.0;

    for(int i=0; i<bins; i++)
    {
      total_w += out.w_total[i];
      if(out.w_total[i] > mx_w) mx_w = out.w_total[i];

      total_v += out.v_total[i];
      total_delta += out.v_delta[i];
    }

    out.total_w = total_w;
    out.max_w   = mx_w;

    out.total_volume_raw      = total_v;
    out.total_volume_weighted = total_w;
    out.delta_total           = total_delta;

    if(total_w <= 0.0 || mx_w <= 0.0)
      return false;

    // POC (weighted basis preserved for backward compatibility)
    const int poc_idx = _FindPOCIndex(out);
    out.poc = _BinCenter(pmin, bin_size, poc_idx);

    // Value Area (weighted basis preserved)
    int left = poc_idx;
    int right = poc_idx;

    if(p.value_area_method == VP_VA_RANKED_DESC)
      _ComputeValueAreaRanked(out, poc_idx, p.value_area_pct, left, right);
    else
      _ComputeValueArea(out, poc_idx, p.value_area_pct, left, right);

    out.val = pmin + (double)left * bin_size;
    out.vah = pmin + ((double)right + 1.0) * bin_size;

    // Optional smoothing output (raw total basis)
    if(p.smoothing_enable)
      _GaussianSmooth1D(out.v_total, out.bins, p.smoothing_radius, p.smoothing_sigma_bins, out.smoothed_total);

    // Full HVN/LVN node lists (raw or smoothed basis depending on params)
    if(p.node_detect_on_smoothed && ArraySize(out.smoothed_total) == out.bins)
    {
      _CollectLocalNodes(out, out.smoothed_total,
                         out.hvn_prices, out.hvn_weights, out.hvn_count,
                         out.lvn_prices, out.lvn_weights, out.lvn_count);
    }
    else
    {
      _CollectLocalNodes(out, out.v_total,
                         out.hvn_prices, out.hvn_weights, out.hvn_count,
                         out.lvn_prices, out.lvn_weights, out.lvn_count);
    }

    // Representative HVN/LVN (backward-compatible single levels)
    const int hvn_idx = _FindSecondMaxIndex(out, poc_idx);
    if(hvn_idx >= 0) out.hvn = _BinCenter(pmin, bin_size, hvn_idx);

    const int lvn_idx = _FindLVNIndexNearPOC(out, poc_idx, 0.15);
    if(lvn_idx >= 0) out.lvn = _BinCenter(pmin, bin_size, lvn_idx);

    // Shape classification (optional)
    if(p.compute_shape)
    {
      if(p.node_detect_on_smoothed && ArraySize(out.smoothed_total) == out.bins)
        _ClassifyShape(out, out.smoothed_total);
      else
        _ClassifyShape(out, out.v_total);
    }

    // Timestamps
    out.built_ts   = TimeCurrent();
    out.range_to   = rates[0].time;
    out.range_from = rates[profile_bars-1].time;

    out.ok = true;
    return true;
  }

  // Evaluate touch/breakout signals against an existing profile.
  // Distances returned in points (>=0). Use ATR-based bands in the caller.
  inline void EvalSignals(const string sym,
                          const Profile &vp,
                          const double price_mid,
                          const double price_close,
                          const double touch_band_pts,
                          const double break_margin_pts,
                          const double node_band_pts,
                          Signals &out)
  {
    out.touch_poc = false;
    out.touch_vah = false;
    out.touch_val = false;
    out.touch_hvn = false;
    out.touch_lvn = false;
    out.breakout_up = false;
    out.breakout_dn = false;

    out.dist_poc_pts = 1e100;
    out.dist_vah_pts = 1e100;
    out.dist_val_pts = 1e100;
    out.dist_hvn_pts = 1e100;
    out.dist_lvn_pts = 1e100;

    if(!vp.ok) return;

    double pt = 0.0;
    if(!SymbolInfoDouble(sym, SYMBOL_POINT, pt)) pt = _Point;
    if(pt <= 0.0) pt = _Point;
    if(pt <= 0.0) return;

    // Distances in points
    if(vp.poc > 0.0) out.dist_poc_pts = MathAbs(price_mid - vp.poc) / pt;
    if(vp.vah > 0.0) out.dist_vah_pts = MathAbs(price_mid - vp.vah) / pt;
    if(vp.val > 0.0) out.dist_val_pts = MathAbs(price_mid - vp.val) / pt;
    if(vp.hvn > 0.0) out.dist_hvn_pts = MathAbs(price_mid - vp.hvn) / pt;
    if(vp.lvn > 0.0) out.dist_lvn_pts = MathAbs(price_mid - vp.lvn) / pt;

    const double tb = MathMax(0.0, touch_band_pts);
    const double nb = MathMax(0.0, node_band_pts);
    const double bm = MathMax(0.0, break_margin_pts);

    out.touch_poc = (out.dist_poc_pts <= tb);
    out.touch_vah = (out.dist_vah_pts <= tb);
    out.touch_val = (out.dist_val_pts <= tb);

    out.touch_hvn = (out.dist_hvn_pts <= nb);
    out.touch_lvn = (out.dist_lvn_pts <= nb);

    // Breakouts use close beyond VA edges (+/- margin)
    out.breakout_up = (price_close > (vp.vah + bm * pt));
    out.breakout_dn = (price_close < (vp.val - bm * pt));
  }
} // namespace VP
