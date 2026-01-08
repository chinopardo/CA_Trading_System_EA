/*
 * SanityChecks.mqh
 *
 * This header defines a set of helper functions that implement per‑strategy
 * data availability checks for the CA Trading System expert advisor.  Each
 * strategy can invoke the appropriate function at the beginning of its
 * evaluation routine to ensure that all of the data it depends on is
 * available before performing any indicator calculations or trade logic.
 *
 * The functions rely on the built‑in iTime() and Bars() functions to verify
 * that a given timeframe contains at least one bar (and optionally a
 * specified number of bars).  Strategies that utilise Volume‑Weighted
 * Average Price (VWAP) or that need high time frame (HTF) context can
 * supply additional parameters to tailor the check to their needs.  If any
 * required timeframe is missing or lacks sufficient history the sanity
 * function will return false, signalling that the strategy should abstain
 * from further processing on the current tick.
 *
 * Example usage in a strategy evaluation function:
 *   #include "SanityChecks.mqh"
 *   bool Evaluate(const SymbolConfig &cfg)
 *   {
 *     // For a VWAP‑based trend strategy using HTF confirmation
 *     if(!CheckSanityForVWAPStrategy(_Symbol,
 *                                    cfg.entryTF,
 *                                    cfg.htfH1,
 *                                    cfg.htfH4,
 *                                    cfg.htfD1,
 *                                    cfg.vwapLookback))
 *       return false;
 *     // ... remainder of strategy logic ...
 *   }
 *
 * Note: Use Period_CURRENT (0) or a negative value for any HTF parameter
 *       that is unused in a particular strategy to skip the corresponding
 *       availability check.
 */

#ifndef SANITY_CHECKS_MQH
#define SANITY_CHECKS_MQH

// Helper to check that a timeframe has been loaded and contains at least
// `requiredBars` bars.  If `tf` is less than or equal to 0 the check is
// skipped to allow optional HTF parameters.
bool CheckTimeframeAvailability(const string symbol,
                                       const ENUM_TIMEFRAMES tf,
                                       const int requiredBars=1)
  {
    // Skip the check for unused timeframes
    if(tf <= PERIOD_CURRENT)
       return true;
    // Ensure the first bar time is valid
    datetime firstBarTime = iTime(symbol, tf, 0);
    if(firstBarTime <= 0)
      return false;
    // Ensure there are enough bars loaded for the given timeframe
    const int barsTotal = Bars(symbol, tf);
    if(barsTotal < requiredBars)
      return false;
    return true;
  }

// Sanity check for strategies that rely on VWAP and potentially on high
// timeframes for trend confirmation.  The strategy must provide the
// entry timeframe, optional high timeframe inputs, and the VWAP lookback
// period used by the indicator.  A return value of false indicates that
// one or more timeframes are not ready for use.
bool CheckSanityForVWAPStrategy(const string symbol,
                                       const ENUM_TIMEFRAMES entryTF,
                                       const ENUM_TIMEFRAMES htfH1,
                                       const ENUM_TIMEFRAMES htfH4,
                                       const ENUM_TIMEFRAMES htfD1,
                                       const int vwapLookback)
  {
    // Check the entry timeframe has at least vwapLookback bars available
    if(!CheckTimeframeAvailability(symbol, entryTF, vwapLookback))
      return false;
    // Check each specified high timeframe has at least one bar
    if(!CheckTimeframeAvailability(symbol, htfH1))
      return false;
    if(!CheckTimeframeAvailability(symbol, htfH4))
      return false;
    if(!CheckTimeframeAvailability(symbol, htfD1))
      return false;
    return true;
  }

// Sanity check for strategies that do not rely on VWAP but may still use
// high timeframes for confirmation or pattern measurements.  The entry
// timeframe must provide at least `patternLookback` bars if a pattern
// indicator (such as NR7/IB or squeeze) is used.  The optional high
// timeframe parameters behave the same as in the VWAP sanity check and
// should be set to PERIOD_CURRENT (0) when unused.
bool CheckSanityForNonVWAPStrategy(const string symbol,
                                          const ENUM_TIMEFRAMES entryTF,
                                          const ENUM_TIMEFRAMES htfH1,
                                          const ENUM_TIMEFRAMES htfH4,
                                          const ENUM_TIMEFRAMES htfD1,
                                          const int patternLookback)
  {
    // Check the entry timeframe (patternLookback can be 1 if no pattern)
    if(!CheckTimeframeAvailability(symbol, entryTF, patternLookback))
      return false;
    // Check optional high timeframes for at least one bar
    if(!CheckTimeframeAvailability(symbol, htfH1))
      return false;
    if(!CheckTimeframeAvailability(symbol, htfH4))
      return false;
    if(!CheckTimeframeAvailability(symbol, htfD1))
      return false;
    return true;
  }

// Small helpers to make logs readable without extra deps
string _TfToStr(ENUM_TIMEFRAMES tf)
{
   // EnumToString(tf) exists in MQL5 but returns PERIOD_H1 etc.
   // This helper prints the human period too.
   int secs = PeriodSeconds(tf);
   if(secs <= 0) return EnumToString(tf);
   int m = secs/60;
   if(m < 60) return StringFormat("%dM", m);
   int h = m/60;
   if(h < 24) return StringFormat("%dH", h);
   int d = h/24;
   return StringFormat("%dD", d);
}

//-----------------------------
// Configurable debug switch
//-----------------------------
namespace Sanity
{
   static bool s_debug = false;

   void SetDebug(const bool on) { s_debug = on; }

   // Core: "Do we have at least <need> bars on <tf> for <symbol> ?"
   // Uses the iTime(...) approach: the bar at shift (need-1) must exist.
   bool HasBars(const string symbol,
                const ENUM_TIMEFRAMES tf,
                int need,
                const string label = "")
   {
      if(need < 1) need = 1;
      // PERIOD_CURRENT means "not used" in our context => always OK
      if(tf == PERIOD_CURRENT) return true;

      // Try to ensure series is synchronized; iTime will implicitly load
      datetime t = iTime(symbol, tf, need - 1);
      bool ok = (t != 0);

      if(s_debug)
         PrintFormat("[Sanity] %s %s tf=%s need=%d => %s (shift=%d, iTime=%I64d)",
                     (label == "" ? "HasBars" : label),
                     symbol,
                     _TfToStr(tf),
                     need,
                     (ok ? "OK" : "FAIL"),
                     need - 1,
                     (long)t);

      return ok;
   }

   // Check an array of HTFs, each requiring at least <need> bars.
   bool CheckHTFs(const string symbol,
                  const ENUM_TIMEFRAMES &htfs[], // pass only HTFs you truly use
                  const int count,
                  const int need,
                  const string label = "HTF")
   {
      for(int i=0; i<count; ++i)
      {
         const ENUM_TIMEFRAMES tf = htfs[i];
         if(tf == PERIOD_CURRENT) continue; // treat as "not used"
         if(!HasBars(symbol, tf, need, label))
            return false;
      }
      return true;
   }

   // VWAP-based strategies typically need a longer lookback on the ENTRY TF
   // (for VWAP bands / Z-score) and possibly a few HTFs for trend context.
   bool CheckSanityForVWAPStrategy(const string symbol,
                                   const ENUM_TIMEFRAMES entry_tf,
                                   const int vwap_lookback,      // e.g., InpVWAP_Lookback
                                   const ENUM_TIMEFRAMES &htfs[],// ONLY the HTFs this strat uses
                                   const int htf_count,
                                   const int htf_min_bars = 50)  // usually modest
   {
      // 1) Entry TF must have enough bars for VWAP calc
      if(!HasBars(symbol, entry_tf, vwap_lookback, "VWAP/EntryTF"))
         return false;

      // 2) Optional HTFs (only those passed in)
      if(htf_count > 0 && !CheckHTFs(symbol, htfs, htf_count, htf_min_bars, "VWAP/HTF"))
         return false;

      return true;
   }

   // Non-VWAP strategies often need a different lookback (e.g., pattern windows)
   // and MAY use zero HTFs. Pass what you actually use.
   bool CheckSanityForNonVWAPStrategy(const string symbol,
                                      const ENUM_TIMEFRAMES entry_tf,
                                      const int pattern_lookback,   // e.g., InpPattern_Lookback
                                      const ENUM_TIMEFRAMES &htfs[],// ONLY the HTFs this strat uses
                                      const int htf_count,
                                      const int htf_min_bars = 50)
   {
      if(!HasBars(symbol, entry_tf, pattern_lookback, "NonVWAP/EntryTF"))
         return false;

      if(htf_count > 0 && !CheckHTFs(symbol, htfs, htf_count, htf_min_bars, "NonVWAP/HTF"))
         return false;

      return true;
   }
}
#ifndef CA_HAVE_CLASS_SanityChecks
#define CA_HAVE_CLASS_SanityChecks
#include "StrategyBase.mqh"

// Conservative "no-trade" checker strategy for legacy wiring.
class SanityChecks : public StrategyBase
{
protected:
   virtual bool ComputeDirectional(const Direction /*dir*/,
                                   const Settings  &/*cfg*/,
                                   StratScore      &ss,
                                   ConfluenceBreakdown &bd) override
   {
      // Abstain cleanly; telemetry-friendly.
      StratFinalize(false, 0.0, false, ss, bd);
      return false;
   }

   virtual string Name() const { return "SanityChecks"; }
};
#endif // CA_HAVE_CLASS_SanityChecks

#endif // SANITY_CHECKS_MQH
