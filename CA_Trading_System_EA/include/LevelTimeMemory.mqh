#ifndef LEVEL_TIME_MEMORY_MQH
#define LEVEL_TIME_MEMORY_MQH

// Requires Types.mqh (LevelTimeMemoryCtx, LevelTimeMemoryResult)

// ---------------------------------------------------------------------------
// ComputeLevelTimeMemory  (enhanced, multi-TF)
// ---------------------------------------------------------------------------
// Primary: scans the entry TF for bar touches on the zone [level_lo, level_hi].
// Enhanced: adds HTF and mid-TF touch scoring, pivot proximity bonus,
//           trendline proximity bonus, and OB quality bonus from ctx.
//
// composite_score combines all tiers and bonuses for use as a quality multiplier.
//
// Scoring guide (composite_score):
//   >= 0.60  → well-remembered, high-quality level
//   0.35–0.59 → moderately remembered
//   < 0.35   → fresh level (use with caution as primary POI)
// ---------------------------------------------------------------------------
inline bool ComputeLevelTimeMemory(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const double level_lo,
                                   const double level_hi,
                                   const int    lookback,
                                   const double band_pct,
                                   const LevelTimeMemoryCtx &ctx,
                                   LevelTimeMemoryResult &out)
{
   ZeroMemory(out);
   out.data_valid = false;

   if(level_lo <= 0.0 || level_hi <= 0.0 || level_lo > level_hi)
      return false;
   if(lookback < 5)
      return false;

   const double mid    = 0.5 * (level_lo + level_hi);
   const double band   = mid * MathMax(band_pct, 0.0001);
   const double lo_ext = level_lo - band;
   const double hi_ext = level_hi + band;

   // ---- Entry TF scan (base layer) ----
   int touches = 0;
   const int barsAvail  = Bars(sym, tf);
   const int scanLimit  = MathMin(lookback, barsAvail - 1);
   for(int i = 1; i <= scanLimit; i++)
   {
      if(iLow(sym, tf, i) <= hi_ext && iHigh(sym, tf, i) >= lo_ext)
         touches++;
   }
   out.touch_count   = touches;
   out.lookback_used = scanLimit;
   out.touch_density = (scanLimit > 0) ? (double)touches / scanLimit : 0.0;

   const double saturation_cap = 50.0;
   out.entry_score = MathMin(1.0, (double)touches / saturation_cap);
   out.memory_score = out.entry_score;    // base: entry score only

   // ================================================================
   // ENHANCED MULTI-TF PATH
   // ================================================================
   out.htf_score       = 0.0;
   out.mid_score       = 0.0;
   out.pivot_bonus     = 0.0;
   out.trendline_bonus = 0.0;
   out.ob_quality_bonus= 0.0;
   out.composite_score = out.entry_score;

   #ifdef AXIS_TIME_MEMORY_ENHANCED
   if(ctx.data_populated)
   {
      // ----------------------------------------------------------------
      // 1. HTF ZONE SCAN — Higher TF Support & Resistance memory
      //    Uses ctx.htf_lo / htf_hi on ctx.tf_htf timeframe.
      //    A level that has been tested and held on the daily or H4
      //    carries far more institutional memory than an entry TF OB.
      // ----------------------------------------------------------------
      if(ctx.htf_lo > 0.0 && ctx.htf_hi > ctx.htf_lo && ctx.htf_lookback >= 5)
      {
         const double htfBand  = 0.5*(ctx.htf_lo+ctx.htf_hi) * MathMax(band_pct, 0.0001);
         const double htfLoExt = ctx.htf_lo - htfBand;
         const double htfHiExt = ctx.htf_hi + htfBand;
         const int htfAvail    = Bars(sym, ctx.tf_htf);
         const int htfLimit    = MathMin(ctx.htf_lookback, htfAvail - 1);
         int htfTouches = 0;
         for(int i = 1; i <= htfLimit; i++)
            if(iLow(sym, ctx.tf_htf, i) <= htfHiExt &&
               iHigh(sym, ctx.tf_htf, i) >= htfLoExt)
               htfTouches++;
         out.htf_score = MathMin(1.0, (double)htfTouches / 20.0); // saturates at 20 HTF bars
      }

      // ----------------------------------------------------------------
      // 2. MID-TF ZONE SCAN — Supply & Demand memory on mid TF (H1)
      //    Uses ctx.mid_lo / mid_hi on ctx.tf_mid timeframe.
      // ----------------------------------------------------------------
      if(ctx.mid_lo > 0.0 && ctx.mid_hi > ctx.mid_lo && ctx.mid_lookback >= 5)
      {
         const double midBand  = 0.5*(ctx.mid_lo+ctx.mid_hi) * MathMax(band_pct, 0.0001);
         const double midLoExt = ctx.mid_lo - midBand;
         const double midHiExt = ctx.mid_hi + midBand;
         const int midAvail    = Bars(sym, ctx.tf_mid);
         const int midLimit    = MathMin(ctx.mid_lookback, midAvail - 1);
         int midTouches = 0;
         for(int i = 1; i <= midLimit; i++)
            if(iLow(sym, ctx.tf_mid, i) <= midHiExt &&
               iHigh(sym, ctx.tf_mid, i) >= midLoExt)
               midTouches++;
         out.mid_score = MathMin(1.0, (double)midTouches / 30.0); // saturates at 30 mid-TF bars
      }

      // ----------------------------------------------------------------
      // 3. PIVOT PROXIMITY BONUS
      //    Daily/weekly pivot PP/R1/S1 proximity means the level has a
      //    universal market memory — all market participants are watching it.
      //    dist_atr = 0 means price is exactly at the pivot.
      //    dist_atr >= 2.0 means price is 2 ATRs away — no bonus.
      // ----------------------------------------------------------------
      if(ctx.near_pivot && ctx.pivot_dist_atr < 2.0)
      {
         out.pivot_bonus = _NarrClamp01(0.20 * (1.0 - ctx.pivot_dist_atr / 2.0));
      }

      // ----------------------------------------------------------------
      // 4. TRENDLINE PROXIMITY BONUS
      //    An active trendline at or near the current zone means the level
      //    is defined by BOTH horizontal memory AND diagonal market structure.
      //    dist_atr = 0 means touching the trendline.
      // ----------------------------------------------------------------
      if(ctx.near_trendline && ctx.trendline_dist_atr < 1.5)
      {
         out.trendline_bonus = _NarrClamp01(0.15 * (1.0 - ctx.trendline_dist_atr / 1.5));
      }

      // ----------------------------------------------------------------
      // 5. OB ZONE QUALITY BONUS
      //    A high-quality OBZone (strong displacement, unmitigated, fresh)
      //    carries more institutional memory than a generic price level.
      //    We incorporate OBZone metadata from StructureSDOB quality helpers.
      // ----------------------------------------------------------------
      if(ctx.ob_quality01 > 0.0 || ctx.ob_freshness01 > 0.0)
      {
         // Quality × freshness composite: both must be present for full bonus
         const double obComposite = 0.6 * ctx.ob_quality01 + 0.4 * ctx.ob_freshness01;

         // Existing touch count from OBZone metadata supplements the bar-scan result
         if(ctx.ob_touch_count > 0)
         {
            const int cappedOBTouches = MathMin(ctx.ob_touch_count, 10);
            out.touch_count += cappedOBTouches;  // blend into reported count
         }

         // FVG overlap increases the institutional significance of the zone
         const double fvgBonus = ctx.fvg_overlap01 * 0.05;

         out.ob_quality_bonus = _NarrClamp01(obComposite * 0.15 + fvgBonus);
      }

      // ----------------------------------------------------------------
      // 6. COMPOSITE SCORE
      //    Weighted combination of HTF, mid-TF, and entry-TF scores, plus bonuses.
      //    HTF and mid-TF tiers require ctx fields to be populated (non-zero zone).
      //    Entry score always contributes.
      // ----------------------------------------------------------------
      const double htfW   = _NarrClamp01(ctx.htf_lo > 0.0 ? 0.30 : 0.0);
      const double midW   = _NarrClamp01(ctx.mid_lo > 0.0 ? 0.35 : 0.0);
      const double entryW = 1.0 - htfW - midW;   // remainder to entry score

      const double tieredScore = _NarrClamp01(
         htfW * out.htf_score +
         midW * out.mid_score +
         entryW * out.entry_score);

      out.composite_score = _NarrClamp01(
         tieredScore +
         out.pivot_bonus +
         out.trendline_bonus +
         out.ob_quality_bonus);

      // Update the canonical memory_score to be the composite
      out.memory_score = out.composite_score;
   }
   #endif // AXIS_TIME_MEMORY_ENHANCED

   out.data_valid = true;
   return true;
}

// Backward-compatible overload (no ctx parameter — original 6-param signature)
inline bool ComputeLevelTimeMemory(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const double level_lo,
                                   const double level_hi,
                                   const int    lookback,
                                   const double band_pct,
                                   LevelTimeMemoryResult &out)
{
   LevelTimeMemoryCtx ctx;
   ctx.Reset();
   return ComputeLevelTimeMemory(sym, tf, level_lo, level_hi, lookback, band_pct, ctx, out);
}

// QualityMultiplier helper (unchanged from prior plan)
inline double LevelTimeMemory_QualityMultiplier(const double memory_score,
                                                const double min_mult = 0.88,
                                                const double max_mult = 1.12)
{
   return min_mult + (max_mult - min_mult) * MathMin(1.0, MathMax(0.0, memory_score));
}

#ifndef _NARR_CLAMP01
   inline double _NarrClamp01(const double v)
   { if(v < 0.0) return 0.0; if(v > 1.0) return 1.0; return v; }
   #define _NARR_CLAMP01
#endif

#endif // LEVEL_TIME_MEMORY_MQH