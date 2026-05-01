#ifndef CANDLE_NARRATIVE_MQH
#define CANDLE_NARRATIVE_MQH

// Types.mqh must be included before this file to provide CandleNarrativeResult.
// MathUtils.mqh provides _MainClamp01 (or redefine inline below if not available).

#ifndef _NARR_CLAMP01
   inline double _NarrClamp01(const double v)
   {
      if(v < 0.0) return 0.0;
      if(v > 1.0) return 1.0;
      return v;
   }
   #define _NARR_CLAMP01
#endif

// ---------------------------------------------------------------------------
// ComputeCandleNarrative
// ---------------------------------------------------------------------------
// Analyses the last `lookback` CLOSED bars from the COUNTER-TREND perspective
// and returns an exhaustion score for the opposing side.
//
// Parameters:
//   sym      — symbol
//   tf       — timeframe (entry TF, not HTF)
//   dir      — TRADE direction (DIR_BUY or DIR_SELL)
//   lookback — number of closed bars to assess (recommend 3–5)
//   out      — result struct (must be zeroed by caller before this call)
//
// Returns true if data was valid and out is populated.
//
// Interpretation of out.exhaustion_score:
//   >= 0.60  → strong opposing exhaustion — high-confidence confirmation
//   0.45–0.59 → moderate exhaustion — treat as supporting evidence only
//   < 0.45   → opposing side still active — trade against momentum, exercise caution
// ---------------------------------------------------------------------------
inline bool ComputeCandleNarrative(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const int lookback,
                                   CandleNarrativeResult &out)
{
   ZeroMemory(out);
   out.data_valid = false;

   if(lookback < 2 || lookback > 10)
      return false;

   // We measure the OPPOSING side, so invert direction for wick/close analysis.
   // oppIsBull = true  → we measure bearish candle quality (for a BUY entry)
   // oppIsBull = false → we measure bullish candle quality (for a SELL entry)
   const bool oppIsBull = (dir == DIR_SELL); // if we want to BUY, opposing = bearish

   // Dynamically sized arrays for per-bar metrics
   double bodyRatios[];    // |close-open| / (high-low)
   double closeQuality[];  // close position from opposing perspective (0=bad,1=good)
   double oppWickRatio[];  // opposing-direction wick as fraction of range
   ArrayResize(bodyRatios,   lookback);
   ArrayResize(closeQuality, lookback);
   ArrayResize(oppWickRatio, lookback);

   for(int i = 0; i < lookback; i++)
   {
      // i=0 → most recent closed bar; i=lookback-1 → oldest bar in cluster
      const int bar = i + 1; // shift 1 = last closed bar
      const double h = iHigh( sym, tf, bar);
      const double l = iLow(  sym, tf, bar);
      const double o = iOpen( sym, tf, bar);
      const double c = iClose(sym, tf, bar);

      const double range = h - l;
      if(range < 1e-10)
      {
         // Zero-range bar (gap open) — use neutral values and continue
         bodyRatios[i]   = 0.5;
         closeQuality[i] = 0.5;
         oppWickRatio[i] = 0.0;
         continue;
      }

      // Body ratio: how decisive was this candle (0=doji, 1=full marubozu)
      bodyRatios[i] = MathAbs(c - o) / range;

      // Opposing close quality and wick:
      //   oppIsBull (opposing side = bulls, we are SELLING): measure bullish close quality
      //     closeQuality = (close - low) / range   → 1.0 means close at the high (bullish power)
      //     oppWick = (high - max(open,close)) / range  → upper wick (bull rejection)
      //   !oppIsBull (opposing side = bears, we are BUYING): measure bearish close quality
      //     closeQuality = (high - close) / range  → 1.0 means close at the low (bearish power)
      //     oppWick = (min(open,close) - low) / range   → lower wick (bear rejection)
      if(oppIsBull)
      {
         closeQuality[i] = (c - l)              / range;  // bullish close quality
         oppWickRatio[i] = (h - MathMax(o, c))  / range;  // upper wick (bull rejection from high)
      }
      else
      {
         closeQuality[i] = (h - c)              / range;  // bearish close quality
         oppWickRatio[i] = (MathMin(o, c) - l)  / range;  // lower wick (bear rejection from low)
      }
   }

   // --- Compute averages ---
   double sumBody = 0.0, sumClose = 0.0, sumWick = 0.0;
   for(int i = 0; i < lookback; i++)
   {
      sumBody  += bodyRatios[i];
      sumClose += closeQuality[i];
      sumWick  += oppWickRatio[i];
   }
   out.body_ratio_avg    = sumBody  / lookback;
   out.close_quality_avg = sumClose / lookback;

   // --- Compute linear regression slopes (OLS, 1-pass) ---
   // Index convention: i=0 is the MOST RECENT bar.
   // A POSITIVE slope on bodyRatios means older bars (higher i) had larger bodies,
   // so recent bars have SMALLER bodies — opposing momentum is FADING. ← exhaustion signal
   // A NEGATIVE slope on oppWickRatio means recent bars have LARGER wicks than older bars
   // — the opposing side is failing at extremes more frequently. ← exhaustion signal
   // A POSITIVE slope on closeQuality means older bars had stronger closes,
   // recent bars are closing more weakly. ← exhaustion signal

   double sumX=0.0, sumXY_b=0.0, sumXY_c=0.0, sumXY_w=0.0;
   double sumX2=0.0;
   const double n = (double)lookback;

   for(int i = 0; i < lookback; i++)
   {
      sumX    += i;
      sumX2   += (double)i * i;
      sumXY_b += (double)i * bodyRatios[i];
      sumXY_c += (double)i * closeQuality[i];
      sumXY_w += (double)i * oppWickRatio[i];
   }

   const double denom = n * sumX2 - sumX * sumX;
   if(MathAbs(denom) < 1e-10)
      return false; // degenerate (single bar or all same index)

   out.body_ratio_slope    = (n * sumXY_b - sumX * sumBody)  / denom;
   out.close_quality_slope = (n * sumXY_c - sumX * sumClose) / denom;
   out.wick_trend_slope    = (n * sumXY_w - sumX * sumWick)  / denom;

   // --- Normalise slope signals to [0,1] exhaustion sub-scores ---
   // Each slope is scaled and shifted so that:
   //   sub-score = 1.0 means strong exhaustion signal
   //   sub-score = 0.5 means flat / neutral
   //   sub-score = 0.0 means opposing side is getting STRONGER (bad for our trade)

   // Body exhaustion: positive slope means shrinking recent bodies → exhaustion
   const double bodyExhaustion  = _NarrClamp01( out.body_ratio_slope    * 4.0 + 0.5);

   // Wick exhaustion: negative slope means growing recent wicks → exhaustion
   const double wickExhaustion  = _NarrClamp01(-out.wick_trend_slope    * 4.0 + 0.5);

   // Close quality exhaustion: positive slope means deteriorating recent closes → exhaustion
   const double closeExhaustion = _NarrClamp01( out.close_quality_slope * 4.0 + 0.5);

   // Level exhaustion: low average body ratio (choppy, indecisive) → exhaustion
   // A body_ratio_avg < 0.35 means most candles are doji/spinning tops → no conviction
   const double levelExhaustion = _NarrClamp01(1.0 - out.body_ratio_avg * 2.5);

   // Composite weighted exhaustion score
   out.exhaustion_score = _NarrClamp01(
      0.35 * bodyExhaustion  +  // body shrinkage is the primary signal
      0.30 * wickExhaustion  +  // wick growth is the secondary signal
      0.25 * closeExhaustion +  // close deterioration reinforces
      0.10 * levelExhaustion    // absolute low body-ratio is a bonus signal
   );

   out.data_valid          = true;
   out.opposing_exhausted  = (out.exhaustion_score >= 0.55); // default threshold; overridden by cfg

   return true;
}

#endif // CANDLE_NARRATIVE_MQH