//+------------------------------------------------------------------+
//| AutoVolatility.mqh                                               |
//| Cached volatility analytics: ADR, ATR, and D1 return sigma        |
//| Build cadence: 24 = daily aligned to CLOSED D1 stamp              |
//|               else N-hour bucket cadence                          |
//+------------------------------------------------------------------+
#ifndef CA_AUTOVOLATILITY_MQH
#define CA_AUTOVOLATILITY_MQH
// ------------------------------
// Tunables (safe defaults)
// ------------------------------
#define AUTOVOL_MAX_SLOTS                 64
#define AUTOVOL_DEFAULT_CADENCE_HOURS     24
#define AUTOVOL_DEFAULT_ADR_LOOKBACK_DAYS 20
#define AUTOVOL_DEFAULT_RET_LOOKBACK_D1   60
#define AUTOVOL_DEFAULT_ATR_PERIOD        14

#define AUTOVOL_MIN_CADENCE_HOURS         1
#define AUTOVOL_MAX_CADENCE_HOURS         168   // 7 days cap
#define AUTOVOL_MIN_ADR_LOOKBACK_DAYS     5
#define AUTOVOL_MAX_ADR_LOOKBACK_DAYS     200
#define AUTOVOL_MIN_RET_LOOKBACK_D1       20
#define AUTOVOL_MAX_RET_LOOKBACK_D1       400

#define AUTOVOL_BACKOFF_BASE_SEC          60    // 1 min
#define AUTOVOL_BACKOFF_MAX_SEC           3600  // 1 hour

// Annualization constant for daily sigma (trading days)
#define AUTOVOL_TRADING_DAYS_PER_YEAR     252.0

namespace AutoVol
{
// ------------------------------
// Helpers
// ------------------------------
inline int  _AutoVolClampInt(const int v, const int lo, const int hi)
{
  if(v < lo) return lo;
  if(v > hi) return hi;
  return v;
}
inline double _AutoVolClamp01(const double v)
{
  if(v < 0.0) return 0.0;
  if(v > 1.0) return 1.0;
  return v;
}
inline datetime _AutoVolNow(const datetime now)
{
  if(now > 0) return now;
  // Prefer trade server time when available; fall back to TimeCurrent
  datetime ts = TimeTradeServer();
  if(ts > 0) return ts;
  return TimeCurrent();
}
inline int _AutoVolDayKey(const datetime t)
{
  return (int)(t / 86400);
}
inline int _AutoVolHourBucket(const datetime t, const int cadence_hours)
{
  const int ch = (cadence_hours <= 0 ? 1 : cadence_hours);
  return (int)((t / 3600) / ch);
}
inline bool _AutoVolEnsureSymbolSelected(const string sym)
{
  if(sym == "") return false;
  if(SymbolSelect(sym, true)) return true;
  // If SymbolSelect fails, still try to proceed; CopyRates may succeed for known symbols.
  return true;
}
inline double _AutoVolPointSafe(const string sym)
{
  double p = SymbolInfoDouble(sym, SYMBOL_POINT);
  if(p <= 0.0) p = 0.00001; // very defensive fallback
  return p;
}

// ------------------------------
// Flags (for diagnostics)
// ------------------------------
enum ENUM_AUTOVOL_FLAGS
{
  AUTOVOL_F_NONE               = 0,
  AUTOVOL_F_D1_STAMP_OK        = 1 << 0,
  AUTOVOL_F_D1_STAMP_FALLBACK  = 1 << 1,
  AUTOVOL_F_ADR_USED_MEDIAN    = 1 << 2,
  AUTOVOL_F_ADR_USED_AVG       = 1 << 3,
  AUTOVOL_F_SIGMA_INSUFF       = 1 << 4,
  AUTOVOL_F_ATR_D1_OK          = 1 << 5,
  AUTOVOL_F_ATR_H1_OK          = 1 << 6
};

// ------------------------------
// Public stats payload
// ------------------------------
struct AutoVolStats
{
  bool     ok;
  string   symbol;

  datetime built_at;           // when this snapshot was built
  datetime d1_closed_stamp;    // open time of the most recent CLOSED D1 bar (shift=1)

  int      cadence_hours;      // 24 = daily aligned to closed D1; otherwise N-hour bucket
  int      adr_lookback_days;  // ADR range distribution lookback
  int      ret_lookback_d1;    // D1 return sigma lookback
  int      atr_period;         // ATR period used for ATR D1/H1

  // Daily range distribution (points)
  double   d1_range_today_pts; // range of most recent CLOSED D1 bar
  double   d1_range_avg_pts;   // avg range over lookback days
  double   d1_range_med_pts;   // median range over lookback days

  // Derived normalization
  double   adr_pts;            // chosen ADR ref (median preferred; avg fallback)
  double   day_range_used01;   // clamp01(today_range / adr_pts)

  // ATR snapshots (points) from CLOSED bars
  double   atr_d1_pts;         // ATR(period) on D1, shift=1
  double   atr_h1_pts;         // ATR(period) on H1, shift=1

  // D1 log-return sigma (%)
  double   d1_ret_sigma_pct;      // daily sigma in percent
  double   d1_ret_sigma_ann_pct;  // annualized sigma in percent
  double   ret_sigma_ann_pct;     // canonical alias (for consumers)

  // Usage / diagnostics
  int      bars_d1_used;       // how many D1 bars actually used in computations
  int      bars_h1_used;       // how many H1 bars used (typically 1)
  int      flags;              // ENUM_AUTOVOL_FLAGS
  string   err;                // non-empty when ok==false
};

// ------------------------------
// Internal slot
// ------------------------------
struct AutoVolSlot
{
  bool     used;
  string   symbol;

  AutoVolStats st;

  // Due tracking
  int      hour_bucket_last;
  int      day_key_last;

  // Failure throttle
  int      fail_count;
  datetime next_retry;
  datetime last_try;
};

// ------------------------------
// Module state
// ------------------------------
static AutoVolSlot g_av[AUTOVOL_MAX_SLOTS];

static string g_registered_syms[AUTOVOL_MAX_SLOTS];
static int    g_registered_count = 0;

static int    g_default_cadence_hours     = AUTOVOL_DEFAULT_CADENCE_HOURS;
static int    g_default_adr_lookback_days = AUTOVOL_DEFAULT_ADR_LOOKBACK_DAYS;
static int    g_default_ret_lookback_d1   = AUTOVOL_DEFAULT_RET_LOOKBACK_D1;
static int    g_default_atr_period        = AUTOVOL_DEFAULT_ATR_PERIOD;

// ------------------------------
// Slot management
// ------------------------------
inline int _AutoVolFindSlot(const string sym)
{
  for(int i=0; i<AUTOVOL_MAX_SLOTS; i++)
    if(g_av[i].used && g_av[i].symbol == sym)
      return i;
  return -1;
}
inline int _AutoVolAllocSlot(const string sym)
{
  int idx = _AutoVolFindSlot(sym);
  if(idx >= 0) return idx;

  for(int i=0; i<AUTOVOL_MAX_SLOTS; i++)
  {
    if(!g_av[i].used)
    {
      g_av[i].used   = true;
      g_av[i].symbol = sym;

      // Reset slot state
      g_av[i].hour_bucket_last = -1;
      g_av[i].day_key_last     = -1;
      g_av[i].fail_count       = 0;
      g_av[i].next_retry       = 0;
      g_av[i].last_try         = 0;

      // Reset stats
      AutoVolStats s;
      s.ok=false; s.symbol=sym; s.built_at=0; s.d1_closed_stamp=0;
      s.cadence_hours=0; s.adr_lookback_days=0; s.ret_lookback_d1=0; s.atr_period=0;
      s.d1_range_today_pts=0; s.d1_range_avg_pts=0; s.d1_range_med_pts=0;
      s.adr_pts=0; s.day_range_used01=0;
      s.atr_d1_pts=0; s.atr_h1_pts=0;
      s.d1_ret_sigma_pct=0; s.d1_ret_sigma_ann_pct=0; s.ret_sigma_ann_pct=0;
      s.bars_d1_used=0; s.bars_h1_used=0; s.flags=AUTOVOL_F_NONE; s.err="";
      g_av[i].st = s;

      return i;
    }
  }
  return -1;
}

// ------------------------------
// Data acquisition helpers
// ------------------------------
inline bool _AutoVolGetClosedD1Stamp(const string sym, datetime &stamp, int &flags, string &err)
{
  stamp = 0;
  MqlRates r[];
  ArraySetAsSeries(r, true);
  int got = CopyRates(sym, PERIOD_D1, 1, 1, r); // shift=1 => most recent CLOSED D1 bar
  if(got == 1)
  {
    stamp = r[0].time;
    flags |= AUTOVOL_F_D1_STAMP_OK;
    return true;
  }

  // Fallback: no stamp; caller may use day-key gating
  flags |= AUTOVOL_F_D1_STAMP_FALLBACK;
  err = "CopyRates(D1, shift=1) failed for closed stamp. last_error=" + IntegerToString(GetLastError());
  return false;
}

inline bool _AutoVolComputeADRPoints(const string sym,
                                    const int lookback_days,
                                    double &today_pts,
                                    double &avg_pts,
                                    double &med_pts,
                                    int &bars_used,
                                    string &err)
{
  today_pts = 0.0; avg_pts = 0.0; med_pts = 0.0; bars_used = 0;
  err = "";

  const int lb = _AutoVolClampInt(lookback_days, AUTOVOL_MIN_ADR_LOOKBACK_DAYS, AUTOVOL_MAX_ADR_LOOKBACK_DAYS);
  const double pt = _AutoVolPointSafe(sym);

  MqlRates r[];
  ArraySetAsSeries(r, true);
  int got = CopyRates(sym, PERIOD_D1, 1, lb, r); // closed bars only
  if(got < 3)
  {
    err = "ADR: insufficient D1 bars. got=" + IntegerToString(got) + " last_error=" + IntegerToString(GetLastError());
    return false;
  }

  double ranges[];
  ArrayResize(ranges, got);

  double sum = 0.0;
  for(int i=0; i<got; i++)
  {
    double rng = (r[i].high - r[i].low) / pt;
    if(rng < 0.0) rng = 0.0;
    ranges[i] = rng;
    sum += rng;
  }

  today_pts = ranges[0];
  avg_pts   = sum / (double)got;

  double sorted[];
  ArrayResize(sorted, got);
  for(int i=0; i<got; i++) sorted[i] = ranges[i];
  ArraySort(sorted);

  if((got % 2) == 1)
    med_pts = sorted[got/2];
  else
    med_pts = 0.5 * (sorted[(got/2)-1] + sorted[got/2]);

  bars_used = got;
  return true;
}

inline bool _AutoVolComputeATRPoints(const string sym,
                                    const ENUM_TIMEFRAMES tf,
                                    const int period,
                                    double &atr_pts,
                                    int &bars_used,
                                    int &flags,
                                    string &err)
{
  atr_pts = 0.0; bars_used = 0; err = "";

  const int per = _AutoVolClampInt(period, 2, 200);
  const double pt = _AutoVolPointSafe(sym);

  int h = iATR(sym, tf, per);
  if(h == INVALID_HANDLE)
  {
    err = "ATR: iATR handle invalid. tf=" + IntegerToString((int)tf) + " per=" + IntegerToString(per)
          + " last_error=" + IntegerToString(GetLastError());
    return false;
  }

  double buf[];
  ArraySetAsSeries(buf, true);
  int got = CopyBuffer(h, 0, 1, 1, buf); // shift=1 => closed bar ATR
  IndicatorRelease(h);

  if(got != 1)
  {
    err = "ATR: CopyBuffer failed. tf=" + IntegerToString((int)tf) + " got=" + IntegerToString(got)
          + " last_error=" + IntegerToString(GetLastError());
    return false;
  }

  atr_pts = buf[0] / pt;
  bars_used = 1;

  if(tf == PERIOD_D1) flags |= AUTOVOL_F_ATR_D1_OK;
  if(tf == PERIOD_H1) flags |= AUTOVOL_F_ATR_H1_OK;

  return true;
}

inline bool _AutoVolComputeD1RetSigmaPct(const string sym,
                                        const int lookback_d1,
                                        double &sigma_pct,
                                        double &sigma_ann_pct,
                                        int &bars_used,
                                        int &flags,
                                        string &err)
{
  sigma_pct = 0.0; sigma_ann_pct = 0.0; bars_used = 0; err = "";

  const int lb = _AutoVolClampInt(lookback_d1, AUTOVOL_MIN_RET_LOOKBACK_D1, AUTOVOL_MAX_RET_LOOKBACK_D1);

  // Need lb+1 closes to produce lb returns
  MqlRates r[];
  ArraySetAsSeries(r, true);
  int want = lb + 1;
  int got  = CopyRates(sym, PERIOD_D1, 1, want, r); // closed bars only
  if(got < 3)
  {
    flags |= AUTOVOL_F_SIGMA_INSUFF;
    err = "Sigma: insufficient D1 bars. got=" + IntegerToString(got) + " last_error=" + IntegerToString(GetLastError());
    return false;
  }

  int n = got - 1; // number of returns available
  if(n < 2)
  {
    flags |= AUTOVOL_F_SIGMA_INSUFF;
    err = "Sigma: insufficient returns. n=" + IntegerToString(n);
    return false;
  }

  double sum = 0.0;
  double sumsq = 0.0;
  int used = 0;

  for(int i=0; i<n; i++)
  {
    double c0 = r[i].close;
    double c1 = r[i+1].close;
    if(c0 <= 0.0 || c1 <= 0.0) continue;

    double ret = MathLog(c0 / c1);
    sum += ret;
    sumsq += ret * ret;
    used++;
  }

  if(used < 2)
  {
    flags |= AUTOVOL_F_SIGMA_INSUFF;
    err = "Sigma: not enough valid closes for returns. used=" + IntegerToString(used);
    return false;
  }

  double mean = sum / (double)used;
  // sample variance
  double var = 0.0;
  if(used > 1)
  {
    var = (sumsq - (double)used * mean * mean) / (double)(used - 1);
    if(var < 0.0) var = 0.0;
  }

  double sig = MathSqrt(var);
  sigma_pct     = sig * 100.0;
  sigma_ann_pct = sig * MathSqrt(AUTOVOL_TRADING_DAYS_PER_YEAR) * 100.0;

  bars_used = used + 1; // approximate bars used
  return true;
}

// ------------------------------
// Due logic
// ------------------------------
inline bool _AutoVolIsDue(const AutoVolSlot &slot,
                          const datetime now,
                          const int cadence_hours,
                          const int adr_lookback_days,
                          const int ret_lookback_d1,
                          const int atr_period,
                          const datetime closed_d1_stamp,
                          const bool has_d1_stamp,
                          string &reason)
{
  reason = "";

  // Parameter changes force rebuild
  if(slot.st.cadence_hours != cadence_hours ||
     slot.st.adr_lookback_days != adr_lookback_days ||
     slot.st.ret_lookback_d1 != ret_lookback_d1 ||
     slot.st.atr_period != atr_period)
  {
    reason = "params_changed";
    return true;
  }

  // Never built
  if(slot.st.built_at <= 0)
  {
    reason = "never_built";
    return true;
  }

  // Daily aligned to CLOSED D1 stamp (exactly 24)
  if(cadence_hours == 24)
  {
    if(has_d1_stamp)
    {
      if(closed_d1_stamp != slot.st.d1_closed_stamp)
      {
        reason = "d1_stamp_changed";
        return true;
      }
      reason = "daily_ok";
      return false;
    }

    // Fallback: day-key based
    int dk = _AutoVolDayKey(now);
    if(dk != slot.day_key_last)
    {
      reason = "daykey_changed";
      return true;
    }
    reason = "daily_fallback_ok";
    return false;
  }

  // N-hour bucket cadence
  int bucket = _AutoVolHourBucket(now, cadence_hours);
  if(bucket != slot.hour_bucket_last)
  {
    reason = "bucket_changed";
    return true;
  }

  reason = "bucket_ok";
  return false;
}

// ------------------------------
// Build + commit
// ------------------------------
inline int _AutoVolBackoffSec(const int fail_count)
{
  // Exponential-ish backoff capped
  int fc = fail_count;
  if(fc < 1) fc = 1;
  if(fc > 10) fc = 10;

  int sec = AUTOVOL_BACKOFF_BASE_SEC * fc;
  if(sec > AUTOVOL_BACKOFF_MAX_SEC) sec = AUTOVOL_BACKOFF_MAX_SEC;
  return sec;
}

inline bool _AutoVolBuildSlotIfDue(const int idx,
                                  const datetime now_in,
                                  const int cadence_hours_in,
                                  const int adr_lookback_days_in,
                                  const int ret_lookback_d1_in,
                                  const int atr_period_in,
                                  const bool force,
                                  AutoVolStats &out)
{
  out = g_av[idx].st;

  datetime now = _AutoVolNow(now_in);

  int cadence_hours     = _AutoVolClampInt(cadence_hours_in, AUTOVOL_MIN_CADENCE_HOURS, AUTOVOL_MAX_CADENCE_HOURS);
  int adr_lookback_days = _AutoVolClampInt(adr_lookback_days_in, AUTOVOL_MIN_ADR_LOOKBACK_DAYS, AUTOVOL_MAX_ADR_LOOKBACK_DAYS);
  int ret_lookback_d1   = _AutoVolClampInt(ret_lookback_d1_in, AUTOVOL_MIN_RET_LOOKBACK_D1, AUTOVOL_MAX_RET_LOOKBACK_D1);
  int atr_period        = _AutoVolClampInt(atr_period_in, 2, 200);

  // Throttle repeated failures
  if(!force && g_av[idx].next_retry > 0 && now < g_av[idx].next_retry)
  {
    // Return last cached state
    out = g_av[idx].st;
    return out.ok;
  }

  string reason = "";
  datetime d1_stamp = 0;
  bool has_stamp = false;

  int flags = AUTOVOL_F_NONE;
  string stamp_err = "";
  has_stamp = _AutoVolGetClosedD1Stamp(g_av[idx].symbol, d1_stamp, flags, stamp_err);

  if(!force)
  {
    if(!_AutoVolIsDue(g_av[idx], now, cadence_hours, adr_lookback_days, ret_lookback_d1, atr_period, d1_stamp, has_stamp, reason))
    {
      // Not due: return cached
      out = g_av[idx].st;
      return out.ok;
    }
  }

  // Attempt build
  g_av[idx].last_try = now;

  AutoVolStats tmp = g_av[idx].st;
  tmp.ok = false;
  tmp.err = "";
  tmp.flags = flags;

  tmp.symbol = g_av[idx].symbol;
  tmp.built_at = now;
  tmp.cadence_hours = cadence_hours;
  tmp.adr_lookback_days = adr_lookback_days;
  tmp.ret_lookback_d1 = ret_lookback_d1;
  tmp.atr_period = atr_period;

  tmp.d1_closed_stamp = (has_stamp ? d1_stamp : 0);

  int used_d1 = 0;
  int used_h1 = 0;

  // ADR
  double adr_today=0, adr_avg=0, adr_med=0;
  int adr_used=0;
  string adr_err="";
  bool ok_adr = _AutoVolComputeADRPoints(tmp.symbol, adr_lookback_days, adr_today, adr_avg, adr_med, adr_used, adr_err);

  // ATR D1/H1
  double atr_d1=0, atr_h1=0;
  int atr_d1_used=0, atr_h1_used=0;
  string atr_err_d1="", atr_err_h1="";
  bool ok_atr_d1 = _AutoVolComputeATRPoints(tmp.symbol, PERIOD_D1, atr_period, atr_d1, atr_d1_used, tmp.flags, atr_err_d1);
  bool ok_atr_h1 = _AutoVolComputeATRPoints(tmp.symbol, PERIOD_H1, atr_period, atr_h1, atr_h1_used, tmp.flags, atr_err_h1);

  // Sigma
  double sig_pct=0, sig_ann=0;
  int sig_used=0;
  string sig_err="";
  bool ok_sig = _AutoVolComputeD1RetSigmaPct(tmp.symbol, ret_lookback_d1, sig_pct, sig_ann, sig_used, tmp.flags, sig_err);

  // If stamp missing for daily, update fallback day_key tracking to prevent repeated rebuild within same day
  if(cadence_hours == 24 && !has_stamp)
    g_av[idx].day_key_last = _AutoVolDayKey(now);

  // N-hour bucket tracking
  if(cadence_hours != 24)
    g_av[idx].hour_bucket_last = _AutoVolHourBucket(now, cadence_hours);

  // Aggregate stats if core pieces are available
  // Minimum viable: ADR + sigma, with ATR optional (but recommended)
  if(ok_adr && ok_sig)
  {
    tmp.d1_range_today_pts = adr_today;
    tmp.d1_range_avg_pts   = adr_avg;
    tmp.d1_range_med_pts   = adr_med;

    // Derived ADR ref + range used
    tmp.adr_pts = (tmp.d1_range_med_pts > 0.0 ? tmp.d1_range_med_pts : tmp.d1_range_avg_pts);
    if(tmp.d1_range_med_pts > 0.0) tmp.flags |= AUTOVOL_F_ADR_USED_MEDIAN;
    else                           tmp.flags |= AUTOVOL_F_ADR_USED_AVG;

    if(tmp.adr_pts > 0.0)
      tmp.day_range_used01 = _AutoVolClamp01(tmp.d1_range_today_pts / tmp.adr_pts);
    else
      tmp.day_range_used01 = 0.0;

    // ATRs (optional)
    tmp.atr_d1_pts = (ok_atr_d1 ? atr_d1 : 0.0);
    tmp.atr_h1_pts = (ok_atr_h1 ? atr_h1 : 0.0);

    // Sigma
    tmp.d1_ret_sigma_pct     = sig_pct;
    tmp.d1_ret_sigma_ann_pct = sig_ann;
    tmp.ret_sigma_ann_pct    = tmp.d1_ret_sigma_ann_pct; // canonical alias

    // Usage counts
    used_d1 = adr_used;
    if(sig_used > used_d1) used_d1 = sig_used;
    tmp.bars_d1_used = used_d1;

    used_h1 = 0;
    if(ok_atr_h1) used_h1 = atr_h1_used;
    tmp.bars_h1_used = used_h1;

    tmp.ok = true;
  }
  else
  {
    // Build failed: build a helpful error
    string e = "";
    if(!has_stamp && cadence_hours == 24) e += "[stamp]" + stamp_err + " ";
    if(!ok_adr) e += "[adr]" + adr_err + " ";
    if(!ok_sig) e += "[sigma]" + sig_err + " ";
    // ATRs are optional; include diagnostics only
    if(!ok_atr_d1) e += "[atr_d1]" + atr_err_d1 + " ";
    if(!ok_atr_h1) e += "[atr_h1]" + atr_err_h1 + " ";
    tmp.err = e;
    tmp.ok = false;
  }

  if(tmp.ok)
  {
    // Commit success
    g_av[idx].st = tmp;
    g_av[idx].fail_count = 0;
    g_av[idx].next_retry = 0;

    // Keep last due trackers aligned to the build moment
    if(cadence_hours == 24 && has_stamp)
      g_av[idx].day_key_last = _AutoVolDayKey(now);

    out = g_av[idx].st;
    return true;
  }

  // Failure: keep prior good stats, but update throttle
  g_av[idx].fail_count++;
  int backoff = _AutoVolBackoffSec(g_av[idx].fail_count);
  g_av[idx].next_retry = now + backoff;

  out = g_av[idx].st;
  // If we have no valid cached stats yet, return tmp so caller can see error
  if(out.built_at <= 0)
  {
    out = tmp;
  }
  return false;
}

// ------------------------------
// Public API
// ------------------------------
inline void AutoVolResetAll()
{
  for(int i=0; i<AUTOVOL_MAX_SLOTS; i++)
  {
    g_av[i].used = false;
    g_av[i].symbol = "";

    g_av[i].hour_bucket_last = -1;
    g_av[i].day_key_last = -1;
    g_av[i].fail_count = 0;
    g_av[i].next_retry = 0;
    g_av[i].last_try = 0;

    AutoVolStats s;
    s.ok=false; s.symbol=""; s.built_at=0; s.d1_closed_stamp=0;
    s.cadence_hours=0; s.adr_lookback_days=0; s.ret_lookback_d1=0; s.atr_period=0;
    s.d1_range_today_pts=0; s.d1_range_avg_pts=0; s.d1_range_med_pts=0;
    s.adr_pts=0; s.day_range_used01=0;
    s.atr_d1_pts=0; s.atr_h1_pts=0;
    s.d1_ret_sigma_pct=0; s.d1_ret_sigma_ann_pct=0; s.ret_sigma_ann_pct=0;
    s.bars_d1_used=0; s.bars_h1_used=0; s.flags=AUTOVOL_F_NONE; s.err="";
    g_av[i].st = s;
  }

  g_registered_count = 0;
  for(int i=0; i<AUTOVOL_MAX_SLOTS; i++) g_registered_syms[i] = "";
}

inline void AutoVolSetCadenceHours(const int cadence_hours)
{
  g_default_cadence_hours = _AutoVolClampInt(cadence_hours, AUTOVOL_MIN_CADENCE_HOURS, AUTOVOL_MAX_CADENCE_HOURS);
}
inline void AutoVolSetADRLookbackDays(const int days)
{
  g_default_adr_lookback_days = _AutoVolClampInt(days, AUTOVOL_MIN_ADR_LOOKBACK_DAYS, AUTOVOL_MAX_ADR_LOOKBACK_DAYS);
}
inline void AutoVolSetD1ReturnLookback(const int bars)
{
  g_default_ret_lookback_d1 = _AutoVolClampInt(bars, AUTOVOL_MIN_RET_LOOKBACK_D1, AUTOVOL_MAX_RET_LOOKBACK_D1);
}
inline void AutoVolSetATRPeriod(const int period)
{
  g_default_atr_period = _AutoVolClampInt(period, 2, 200);
}

inline bool AutoVolRegisterSymbol(const string sym)
{
  if(sym == "") return false;

  // prevent duplicates
  for(int i=0; i<g_registered_count; i++)
    if(g_registered_syms[i] == sym)
      return true;

  if(g_registered_count >= AUTOVOL_MAX_SLOTS) return false;

  _AutoVolEnsureSymbolSelected(sym);
  if(_AutoVolAllocSlot(sym) < 0) return false;

  g_registered_syms[g_registered_count] = sym;
  g_registered_count++;
  return true;
}

inline int AutoVolRegisteredCount()
{
  return g_registered_count;
}

inline bool AutoVolGet(const string sym,
                       AutoVolStats &out,
                       const int cadence_hours = -1,
                       const bool force = false,
                       const int adr_lookback_days = -1,
                       const int ret_lookback_d1 = -1,
                       const int atr_period = -1,
                       const datetime now = 0)
{
  out.ok = false;
  out.symbol = sym;

  if(sym == "") { out.err = "symbol_empty"; return false; }

  _AutoVolEnsureSymbolSelected(sym);

  int idx = _AutoVolAllocSlot(sym);
  if(idx < 0)
  {
    out.err = "no_free_autovol_slots";
    return false;
  }

  int ch = (cadence_hours < 0 ? g_default_cadence_hours : cadence_hours);
  int ad = (adr_lookback_days < 0 ? g_default_adr_lookback_days : adr_lookback_days);
  int rl = (ret_lookback_d1 < 0 ? g_default_ret_lookback_d1 : ret_lookback_d1);
  int ap = (atr_period < 0 ? g_default_atr_period : atr_period);

  return _AutoVolBuildSlotIfDue(idx, now, ch, ad, rl, ap, force, out);
}

inline void AutoVolBuildAllIfDue(const datetime now = 0)
{
  datetime t = _AutoVolNow(now);
  AutoVolStats tmp;

  // Build only registered symbols (explicit control)
  for(int i=0; i<g_registered_count; i++)
  {
    string sym = g_registered_syms[i];
    if(sym == "") continue;
    AutoVolGet(sym, tmp, g_default_cadence_hours, false, g_default_adr_lookback_days, g_default_ret_lookback_d1, g_default_atr_period, t);
  }
}

// Convenience for EA OnTimer()
inline void AutoVolOnTimer()
{
  AutoVolBuildAllIfDue(_AutoVolNow(0));
}
} // namespace AutoVol
#endif // CA_AUTOVOLATILITY_MQH