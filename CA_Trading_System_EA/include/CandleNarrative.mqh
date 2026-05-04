#ifndef CANDLE_NARRATIVE_MQH
#define CANDLE_NARRATIVE_MQH

// Requires Types.mqh (CandleNarrativeCtx, CandleNarrativeResult)
// Requires MathUtils.mqh (or uses inline clamp below)

#ifndef _NARR_CLAMP01
   inline double _NarrClamp01(const double v)
   { if(v < 0.0) return 0.0; if(v > 1.0) return 1.0; return v; }
   #define _NARR_CLAMP01
#endif

// ---------------------------------------------------------------------------
// ComputeCandleNarrative  (enhanced)
// ---------------------------------------------------------------------------
// Analyses the last `lookback` CLOSED bars from the COUNTER-TREND perspective
// and returns an exhaustion score enriched by PatternSet, VSA, ATR, AMD, and
// HTF trend when ctx.data_populated = true.
//
// Exhaustion interpretation (out.exhaustion_score):
//   >= 0.65  → strong opposing exhaustion  — high-confidence confirmation
//   0.50–0.64 → moderate exhaustion        — supporting evidence
//   0.35–0.49 → weak / neutral             — inconclusive
//   < 0.35   → opposing side still active  — caution
// ---------------------------------------------------------------------------
inline bool ComputeCandleNarrative(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const int lookback,
                                   const CandleNarrativeCtx &ctx,
                                   CandleNarrativeResult &out)
{
   ZeroMemory(out);
   out.data_valid = false;

   if(lookback < 2 || lookback > 10)
      return false;

   const bool oppIsBull = (dir == DIR_SELL);

   double bodyRatios[];
   double closeQuality[];
   double oppWickRatio[];
   ArrayResize(bodyRatios,   lookback);
   ArrayResize(closeQuality, lookback);
   ArrayResize(oppWickRatio, lookback);

   // ---- ATR normalisation reference ----
   // If ATR is available, compute a per-bar relative spread metric.
   // We normalise candle range by ATR so that wide-range high-volatility bars
   // don't artificially dominate the body ratio.
   const double atr_ref = (ctx.data_populated && ctx.atr_pts > 1e-10)
                           ? ctx.atr_pts : 0.0;

   for(int i = 0; i < lookback; i++)
   {
      const int bar = i + 1;
      const double h = iHigh( sym, tf, bar);
      const double l = iLow(  sym, tf, bar);
      const double o = iOpen( sym, tf, bar);
      const double c = iClose(sym, tf, bar);
      double range = h - l;

      if(range < 1e-10)
      {
         bodyRatios[i] = 0.5; closeQuality[i] = 0.5; oppWickRatio[i] = 0.0;
         continue;
      }

      // ATR-normalise the range: shrink over-extended bars, boost quiet bars,
      // but cap so no single bar dominates.  Range > 2×ATR is a spike — cap at 1.0.
      // Range < 0.5×ATR is a compression bar — keep its metrics as-is.
      double rangeWeight = 1.0;
      if(atr_ref > 1e-10)
      {
         const double rangeRatio = range / atr_ref;
         // Spike bar: body/wick metrics less reliable — reduce weight toward 0.5 neutral
         if(rangeRatio > 2.0)
            rangeWeight = MathMax(0.50, 1.0 - (rangeRatio - 2.0) * 0.15);
      }

      bodyRatios[i] = MathAbs(c - o) / range;

      if(oppIsBull)
      {
         closeQuality[i] = (c - l) / range;
         oppWickRatio[i] = (h - MathMax(o, c)) / range;
      }
      else
      {
         closeQuality[i] = (h - c) / range;
         oppWickRatio[i] = (MathMin(o, c) - l) / range;
      }

      // Apply range-weight: blend toward neutral 0.5 for spike bars
      bodyRatios[i]   = bodyRatios[i]   * rangeWeight + 0.5 * (1.0 - rangeWeight);
      closeQuality[i] = closeQuality[i] * rangeWeight + 0.5 * (1.0 - rangeWeight);
   }

   // ---- Averages ----
   double sumBody = 0.0, sumClose = 0.0, sumWick = 0.0;
   for(int i = 0; i < lookback; i++)
   {
      sumBody  += bodyRatios[i];
      sumClose += closeQuality[i];
      sumWick  += oppWickRatio[i];
   }
   out.body_ratio_avg    = sumBody  / lookback;
   out.close_quality_avg = sumClose / lookback;

   // ---- OLS slopes ----
   double sumX=0.0, sumXY_b=0.0, sumXY_c=0.0, sumXY_w=0.0, sumX2=0.0;
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
      return false;

   out.body_ratio_slope    = (n * sumXY_b - sumX * sumBody)  / denom;
   out.close_quality_slope = (n * sumXY_c - sumX * sumClose) / denom;
   out.wick_trend_slope    = (n * sumXY_w - sumX * sumWick)  / denom;

   // ---- Base exhaustion sub-scores ----
   const double bodyExhaustion  = _NarrClamp01( out.body_ratio_slope    * 4.0 + 0.5);
   const double wickExhaustion  = _NarrClamp01(-out.wick_trend_slope    * 4.0 + 0.5);
   const double closeExhaustion = _NarrClamp01( out.close_quality_slope * 4.0 + 0.5);
   const double levelExhaustion = _NarrClamp01( 1.0 - out.body_ratio_avg * 2.5);

   double baseScore = _NarrClamp01(
      0.35 * bodyExhaustion +
      0.30 * wickExhaustion +
      0.25 * closeExhaustion +
      0.10 * levelExhaustion);

   // ========================================================================
   // ENHANCED ENRICHMENT PATH — active only when ctx.data_populated = true
   // ========================================================================
   out.pattern_boost     = 0.0;
   out.vsa_boost         = 0.0;
   out.amd_context_weight= 1.0;
   out.htf_align_weight  = 1.0;
   out.vol_regime_weight = 1.0;

   #ifdef CANDLE_NARRATIVE_ENHANCED
   if(ctx.data_populated)
   {
      // ----------------------------------------------------------------
      // 1. PATTERN BOOST — PatternSet AMD scores confirm/deny exhaustion
      //    We check whether the SAME-DIRECTION pattern side has a strong AMD
      //    reading.  A strong AMD candlestick pattern in our direction, while
      //    the counter-trend side's body is shrinking, is powerful confluence.
      // ----------------------------------------------------------------
      const bool pattDirBull = (dir == DIR_BUY);

      // Matching side AMD score (our trade direction matches this side)
      const double sameSideAmpdi = pattDirBull ? ctx.patt_cs_ampdi01 : ctx.patt_ch_ampdi01;

      // A high same-side AMD score reinforces exhaustion of the opposing side.
      // Range: +0.00 to +0.12 boost
      if(sameSideAmpdi >= 0.50)
         out.pattern_boost = _NarrClamp01(0.12 * (sameSideAmpdi - 0.50) * 2.0);

      // Confirm directional bias from pattern
      const bool pattBullConfirm = ctx.patt_cs_bull && (sameSideAmpdi >= 0.40);
      const bool pattBearConfirm = !ctx.patt_cs_bull && (sameSideAmpdi >= 0.40);
      const bool dirConfirmed    = pattDirBull ? pattBullConfirm : pattBearConfirm;

      // Volume + momentum from PatternSet: if volume confirms the pattern,
      // it adds to exhaustion confidence.  Range: additional 0..+0.06
      if(dirConfirmed && ctx.patt_cs_vol01 >= 0.55 && ctx.patt_cs_mom01 >= 0.50)
         out.pattern_boost += 0.06;

      // Cap total pattern boost
      out.pattern_boost = _NarrClamp01(out.pattern_boost);

      // ----------------------------------------------------------------
      // 2. VSA BOOST — Climax/Spring/Upthrust confirms reversal narrative
      //    A VSA climax AGAINST our direction (buying climax when we SELL,
      //    selling climax when we BUY) is the strongest single exhaustion
      //    signal in this system.
      // ----------------------------------------------------------------
      if(ctx.vsa_climax_against && ctx.vsa_climax_score01 >= 0.55)
      {
         // Range: +0.05 to +0.15 based on climax intensity
         out.vsa_boost = _NarrClamp01(0.15 * (ctx.vsa_climax_score01 - 0.55) / 0.45);
         out.vsa_boost = MathMax(out.vsa_boost, 0.05);
      }

      // Spring (bullish) or Upthrust (bearish) confirms reversal
      const bool vsaReversal = (dir == DIR_BUY  && ctx.vsa_spring) ||
                               (dir == DIR_SELL && ctx.vsa_upthrust);
      if(vsaReversal)
         out.vsa_boost = MathMax(out.vsa_boost, 0.10);

      out.vsa_boost = _NarrClamp01(out.vsa_boost);

      // ----------------------------------------------------------------
      // 3. AMD PHASE CONTEXT WEIGHT
      //    In Accumulation: buy signals are high-probability → boost BUY exhaustion
      //    In Distribution: sell signals are high-probability → boost SELL exhaustion
      //    In Manipulation: both sides tricky → slight penalty to exhaustion confidence
      // ----------------------------------------------------------------
      if(ctx.amd_accumulation && dir == DIR_BUY)
         out.amd_context_weight = 1.12;
      else if(ctx.amd_distribution && dir == DIR_SELL)
         out.amd_context_weight = 1.12;
      else if(ctx.amd_manipulation)
         out.amd_context_weight = 0.88;    // cautious — manipulation phase traps both sides
      else
         out.amd_context_weight = 1.00;

      // ----------------------------------------------------------------
      // 4. HTF TREND ALIGNMENT WEIGHT
      //    Trading with the HTF trend amplifies exhaustion signal value.
      //    Counter-trend trades reduce confidence (score penalty).
      // ----------------------------------------------------------------
      const double htfW = _NarrClamp01(ctx.htf_trend_strength01);
      const double htfScale = ctx.htf_trend_aligned
         ? (1.0 + htfW * ctx.htf_trend_strength01 * 0.15)  // aligned: +0..+15%
         : (1.0 - htfW * 0.20);                             // counter: -0..-20%
      out.htf_align_weight = _NarrClamp01(htfScale);

      // ----------------------------------------------------------------
      // 5. VOLATILITY REGIME SCALING
      //    Very high volatility: candlestick patterns are less reliable.
      //    Very low volatility: patterns are cleaner and more predictive.
      // ----------------------------------------------------------------
      if(ctx.vol_regime01 > 0.75)
         out.vol_regime_weight = 1.0 - (ctx.vol_regime01 - 0.75) * 0.40;  // mild penalty
      else if(ctx.vol_regime01 < 0.30)
         out.vol_regime_weight = 1.0 + (0.30 - ctx.vol_regime01) * 0.30;  // mild boost
      out.vol_regime_weight = _NarrClamp01(out.vol_regime_weight);
   }
   #endif // CANDLE_NARRATIVE_ENHANCED

   // ---- Final composite exhaustion score ----
   // Base score × AMD weight × HTF weight × vol weight, then add pattern + VSA boosts.
   const double enrichedBase = _NarrClamp01(
      baseScore * out.amd_context_weight * out.htf_align_weight * out.vol_regime_weight);

   out.exhaustion_score = _NarrClamp01(enrichedBase + out.pattern_boost + out.vsa_boost);

   out.data_valid       = true;
   out.opposing_exhausted = (out.exhaustion_score >= 0.55);

   return true;
}

// Backward-compatible overload (no ctx parameter)
inline bool ComputeCandleNarrative(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const Direction dir,
                                   const int lookback,
                                   CandleNarrativeResult &out)
{
   CandleNarrativeCtx ctx;
   ctx.Reset();
   return ComputeCandleNarrative(sym, tf, dir, lookback, ctx, out);
}

#endif // CANDLE_NARRATIVE_MQH