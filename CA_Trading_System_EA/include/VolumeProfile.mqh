#property strict

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
  struct Params
  {
    int    lookback_bars;       // closed bars to profile (e.g., 200)
    int    bin_points;          // bin size in points (e.g., 10 => 10*_Point)
    double value_area_pct;      // 0.0..1.0 (0.70 typical)
    int    max_bins;            // safety cap (e.g., 400)
    bool   distribute_by_range; // true=distribute weight across candle range; false=typical price
    bool   split_up_down;       // keep up/down histogram (optional)

    // VSA weighting
    bool   use_vsa;
    int    vsa_ma_len;          // SMA length for volume/spread baselines (e.g., 30)
    double high_mult;           // 1.5 (Pine example)
    double ultra_mult;          // 3.0 (Pine example)
    double low_mult;            // 0.5 (Pine example)
    double high_boost;          // multiplier when volume > high_mult*MA
    double ultra_boost;         // multiplier when volume > ultra_mult*MA
    double low_boost;           // multiplier when volume < low_mult*MA
    double spread_floor;        // clamp spread factor lower bound (e.g., 0.50)
    double spread_cap;          // clamp spread factor upper bound (e.g., 2.00)
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

    double total_w;
    double max_w;

    // Key levels
    double poc;
    double vah;
    double val;

    // Representative nodes (single levels)
    double hvn;
    double lvn;

    // Histogram
    double w_total[];
    double w_up[];
    double w_dn[];
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

  inline void _AccumulateBin(Profile &out, const int idx, const double w, const bool is_up, const bool split_up_down)
  {
    out.w_total[idx] += w;
    if(split_up_down)
    {
      if(is_up) out.w_up[idx] += w;
      else      out.w_dn[idx] += w;
    }
  }

  inline void _AccumulateByTypical(Profile &out,
                                   const double pmin,
                                   const double bin_size,
                                   const int bins,
                                   const double o,
                                   const double h,
                                   const double l,
                                   const double c,
                                   const double w,
                                   const bool split_up_down)
  {
    const double tp = (h + l + c) / 3.0;
    const int idx = _PriceToBin(tp, pmin, bin_size, bins);
    const bool is_up = (c >= o);
    _AccumulateBin(out, idx, w, is_up, split_up_down);
  }

  inline void _AccumulateByRange(Profile &out,
                                 const double pmin,
                                 const double bin_size,
                                 const int bins,
                                 const double o,
                                 const double h,
                                 const double l,
                                 const double c,
                                 const double w,
                                 const bool split_up_down)
  {
    const bool is_up = (c >= o);

    const double lo = MathMin(l, h);
    const double hi = MathMax(l, h);
    const double rng = hi - lo;

    if(rng <= 0.0)
    {
      _AccumulateByTypical(out, pmin, bin_size, bins, o, h, l, c, w, split_up_down);
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

    // Distribute by overlap proportion with each bin (fast & stable)
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
        _AccumulateBin(out, idx, w * frac, is_up, split_up_down);
      }
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
    p.lookback_bars       = 200;
    p.bin_points          = 10;
    p.value_area_pct      = 0.70;
    p.max_bins            = 400;
    p.distribute_by_range = false;
    p.split_up_down       = false;

    p.use_vsa      = true;
    p.vsa_ma_len   = 30;
    p.high_mult    = 1.5;
    p.ultra_mult   = 3.0;
    p.low_mult     = 0.5;

    // Sensible boosts: keep conservative so profile doesn't become spiky
    p.high_boost   = 1.25;
    p.ultra_boost  = 1.60;
    p.low_boost    = 0.70;

    p.spread_floor = 0.50;
    p.spread_cap   = 2.00;
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
  }

  // Build a profile from closed bars: shift=1..lookback
  inline bool BuildProfile(const string sym,
                           const ENUM_TIMEFRAMES tf,
                           const Params &p_in,
                           Profile &out)
  {
    Reset(out);
    Params p = p_in;

    if(p.lookback_bars < 20) p.lookback_bars = 20;
    if(p.bin_points < 1)     p.bin_points = 1;
    p.value_area_pct = _Clamp(p.value_area_pct, 0.05, 0.95);
    p.max_bins = _ClampInt(p.max_bins, 50, 2000);
    p.vsa_ma_len = _ClampInt(p.vsa_ma_len, 3, 200);

    const double pt = _PointOf(sym);
    if(pt <= 0.0) return false;

    // Need extra bars for SMA baselines
    const int need = p.lookback_bars + p.vsa_ma_len + 5;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    const int got = CopyRates(sym, tf, 1, need, rates);
    if(got < p.lookback_bars + 5)
      return false;

    // Range min/max across the profiled window (closed bars only)
    double pmin = rates[0].low;
    double pmax = rates[0].high;

    for(int i=0; i<p.lookback_bars; i++)
    {
      if(rates[i].low  < pmin) pmin = rates[i].low;
      if(rates[i].high > pmax) pmax = rates[i].high;
    }

    if(pmax <= pmin)
      return false;

    double bin_size = (double)p.bin_points * pt;
    if(bin_size <= 0.0) bin_size = pt;

    int bins = (int)MathFloor((pmax - pmin) / bin_size) + 1;
    if(bins < 5) bins = 5;

    // Cap bins by increasing bin_size (keeps stability)
    if(bins > p.max_bins)
    {
      bin_size = (pmax - pmin) / (double)p.max_bins;
      // round up to a point multiple
      bin_size = MathMax(pt, MathCeil(bin_size / pt) * pt);
      bins = (int)MathFloor((pmax - pmin) / bin_size) + 1;
      bins = _ClampInt(bins, 5, p.max_bins);
    }

    out.price_min = pmin;
    out.price_max = pmax;
    out.bin_size  = bin_size;
    out.bins      = bins;

    _EnsureArrays(out, bins, p.split_up_down);

    // Precompute vol & spread arrays for SMA baselines
    const int n = got;
    double v_arr[];
    double s_arr[];
    ArrayResize(v_arr, n);
    ArrayResize(s_arr, n);

    for(int i=0; i<n; i++)
    {
      v_arr[i] = (double)rates[i].tick_volume;
      const double spr = (rates[i].high - rates[i].low) / pt;
      s_arr[i] = MathMax(0.0, spr);
    }

    // Accumulate histogram
    for(int i=0; i<p.lookback_bars; i++)
    {
      const double o = rates[i].open;
      const double h = rates[i].high;
      const double l = rates[i].low;
      const double c = rates[i].close;

      const double vol = v_arr[i];

      double vma = vol;
      double sma_spr = s_arr[i];

      if(i + p.vsa_ma_len < n)
      {
        vma     = _SMA(v_arr, i, p.vsa_ma_len);
        sma_spr = _SMA(s_arr, i, p.vsa_ma_len);
      }

      const double spr_pts = s_arr[i];
      const double w = _VSAWeight(vol, vma, spr_pts, sma_spr, p);

      if(w <= 0.0) continue;

      if(p.distribute_by_range)
        _AccumulateByRange(out, pmin, bin_size, bins, o, h, l, c, w, p.split_up_down);
      else
        _AccumulateByTypical(out, pmin, bin_size, bins, o, h, l, c, w, p.split_up_down);
    }

    // Summaries
    double total = 0.0;
    double mx = 0.0;
    for(int i=0; i<bins; i++)
    {
      total += out.w_total[i];
      if(out.w_total[i] > mx) mx = out.w_total[i];
    }

    out.total_w = total;
    out.max_w   = mx;

    if(total <= 0.0 || mx <= 0.0)
      return false;

    // POC
    const int poc_idx = _FindPOCIndex(out);
    out.poc = _BinCenter(pmin, bin_size, poc_idx);

    // Value Area
    int left = poc_idx;
    int right = poc_idx;
    _ComputeValueArea(out, poc_idx, p.value_area_pct, left, right);

    out.val = pmin + (double)left * bin_size;
    out.vah = pmin + ((double)right + 1.0) * bin_size;

    // Representative HVN/LVN
    const int hvn_idx = _FindSecondMaxIndex(out, poc_idx);
    if(hvn_idx >= 0) out.hvn = _BinCenter(pmin, bin_size, hvn_idx);

    const int lvn_idx = _FindLVNIndexNearPOC(out, poc_idx, 0.15);
    if(lvn_idx >= 0) out.lvn = _BinCenter(pmin, bin_size, lvn_idx);

    // Timestamps
    out.built_ts  = TimeCurrent();
    out.range_to  = rates[0].time;
    out.range_from = rates[p.lookback_bars-1].time;

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
