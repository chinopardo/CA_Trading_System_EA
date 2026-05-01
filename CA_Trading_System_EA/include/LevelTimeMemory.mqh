#ifndef LEVEL_TIME_MEMORY_MQH
#define LEVEL_TIME_MEMORY_MQH

// ---------------------------------------------------------------------------
// ComputeLevelTimeMemory
// ---------------------------------------------------------------------------
// Scans the last `lookback` CLOSED bars and counts how many had their
// high-low range overlapping the zone [level_lo - band, level_hi + band].
//
// Parameters:
//   sym        — symbol
//   tf         — timeframe (should match the OB/FVG source timeframe)
//   level_lo   — lower edge of the zone (e.g. OB low or FVG low)
//   level_hi   — upper edge of the zone (e.g. OB high or FVG high)
//   lookback   — bars to scan (100 on M15, 100–200 on H1, 50–100 on H4)
//   band_pct   — fractional price band added around zone edges.
//                0.0015 = 0.15%, enough to capture wick touches without noise.
//   out        — result struct (caller must zero it before this call)
//
// Returns true if data was valid.
//
// Scoring guide:
//   memory_score >= 0.50  → well-remembered level (25+ touches in 50 bars)
//   memory_score  0.25–0.49 → moderately remembered (tested but not saturated)
//   memory_score  < 0.25   → fresh level (first or second test)
// ---------------------------------------------------------------------------
inline bool ComputeLevelTimeMemory(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const double level_lo,
                                   const double level_hi,
                                   const int    lookback,
                                   const double band_pct,
                                   LevelTimeMemoryResult &out)
{
   ZeroMemory(out);
   out.data_valid = false;

   if(level_lo <= 0.0 || level_hi <= 0.0 || level_lo > level_hi)
      return false;
   if(lookback < 5)
      return false;

   const double mid     = 0.5 * (level_lo + level_hi);
   const double band    = mid * MathMax(band_pct, 0.0001); // floor at 0.01%
   const double lo_ext  = level_lo - band;
   const double hi_ext  = level_hi + band;

   int touches = 0;
   const int barsAvail = Bars(sym, tf);
   const int scanLimit = MathMin(lookback, barsAvail - 1);

   for(int i = 1; i <= scanLimit; i++) // i=1 → last closed bar; never i=0 (live bar)
   {
      const double barH = iHigh(sym, tf, i);
      const double barL = iLow( sym, tf, i);

      // A bar "touches" the zone when its range intersects the extended band.
      // Condition: bar low <= zone high AND bar high >= zone low
      if(barL <= hi_ext && barH >= lo_ext)
         touches++;
   }

   out.touch_count    = touches;
   out.lookback_used  = scanLimit;
   out.touch_density  = (scanLimit > 0) ? (double)touches / scanLimit : 0.0;

   // Normalise to 0..1.
   // Cap at a "saturation" count — once 50+ bars have touched the level we consider
   // it fully saturated.  Adjust saturation_cap for your typical bar count per session.
   const double saturation_cap = 50.0;
   out.memory_score = MathMin(1.0, (double)touches / saturation_cap);

   out.data_valid = true;
   return true;
}

// ---------------------------------------------------------------------------
// LevelTimeMemory_QualityMultiplier
// ---------------------------------------------------------------------------
// Convenience wrapper: converts a memory_score to a quality multiplier in the
// range [min_mult .. max_mult] centred at 1.0.
//
//   memory_score = 0.0 → multiplier = min_mult (penalise fresh/untested level)
//   memory_score = 0.5 → multiplier ≈ 1.0      (neutral — average level)
//   memory_score = 1.0 → multiplier = max_mult  (boost well-remembered level)
//
// Recommended: min_mult=0.88, max_mult=1.12 for a ±12% quality nudge.
// ---------------------------------------------------------------------------
inline double LevelTimeMemory_QualityMultiplier(const double memory_score,
                                                const double min_mult = 0.88,
                                                const double max_mult = 1.12)
{
   // Linear interpolation between min and max over [0,1]
   return min_mult + (max_mult - min_mult) * MathMin(1.0, MathMax(0.0, memory_score));
}

#endif // LEVEL_TIME_MEMORY_MQH