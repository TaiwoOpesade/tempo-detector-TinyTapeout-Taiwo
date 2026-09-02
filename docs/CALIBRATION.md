# Calibration Guide

The chip has no runtime-tunable registers by design (it's a
silicon-efficient, CPU-free classifier). Tuning means changing a
parameter in `src/project.v` and resynthesizing. This is the same
tradeoff the original hardware face-detection chip made with its RGB
thresholds — simpler silicon, calibration happens at compile time.

## Parameters you can tune

All live in the module instantiations inside `src/project.v`.

### `ONSET_THRESHOLD` (onset_detector, default 20)

How far above the tracked envelope a sample must jump to count as a
beat.

- **Missing quiet beats?** Lower it (try 12-15). Watch `onset_active`
  (`uio_out[4]`) on a scope — it should pulse on every beat you can hear.
- **False triggers on background noise/hiss?** Raise it (try 25-35).

### `DECAY_SHIFT` (onset_detector, default 4)

Controls how fast the envelope follows the signal (bigger = slower,
smoother envelope; smaller = faster, twitchier envelope that can start
chasing individual beats instead of the background level).

- **Envelope drifting up during sustained loud passages, missing later
  beats?** Increase to 5 or 6 (slower envelope, less affected by the
  beats themselves).
- **Envelope too sluggish after a volume change?** Decrease to 3.

### `REFRACTORY_CYCLES` (onset_detector, default 5)

Minimum samples between two accepted onsets. At the assumed 100 Hz
sample rate, 5 samples = 50 ms, i.e. caps detection around 1200 BPM —
comfortably above any real tempo, so raising this mainly helps with
double-triggering on percussive beats with a long decay tail.

- **One beat being counted twice?** Increase to 8-10.

### `STALE_THRESHOLD` (tempo_estimator, default 900)

How close an interval can get to `MAX_INTERVAL` (1023) before it's
treated as "the source went quiet" rather than a real slow beat. Lower
it if you want the chip to forget history sooner after a pause.

### `NUMERATOR` (bpm_divider, default 6000)

`NUMERATOR = 60 * assumed_sample_rate_hz`. The whole design assumes a
**100 Hz** envelope sample rate (`ui_in` updates driven by
`sample_valid` roughly every 10 ms). If your front-end decimates to a
different rate, recompute this constant — e.g. for 200 Hz,
`NUMERATOR = 12000`.

## A quick tuning procedure

1. Feed a click track or metronome app at a known BPM into your
   front-end.
2. Watch `confidence` (`uio_out[7:6]`) climb toward `2'b11` within the
   first 4-8 beats. If it never gets there, loosen `ONSET_THRESHOLD`
   first — an unstable confidence score almost always means beats are
   being missed or double-counted, not that the averaging math is wrong.
3. Once locked, compare `bpm_estimate` against the known BPM. A
   consistent offset (not noise) usually means `NUMERATOR` doesn't match
   your actual sample rate — check your front-end's decimation timing.
4. Test with real music, not just a metronome — percussive genres
   (electronic, hip-hop) tend to need a higher `ONSET_THRESHOLD` than
   acoustic ones to avoid triggering on every hi-hat.
