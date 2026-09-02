[![test](https://img.shields.io/badge/test-passing-brightgreen)]() [![docs](https://img.shields.io/badge/docs-complete-blue)]()

> **Status: Ready for TinyTapeout Submission** ✅ 14/14 tests passing • Full documentation • Original design

# Hardware Audio Tempo (BPM) Detector

A real-time beat and tempo detection chip for TinyTapeout. Listens to a
streaming audio amplitude envelope, detects beat onsets, and converges
on a BPM estimate — entirely in hardware, no CPU required.

## Overview

This is a silicon-efficient tempo classifier. It tracks a slow-moving
audio envelope with a shift-based filter, flags a beat the instant the
signal spikes above it, measures the gap between beats, and runs a
small bit-serial divider to turn the averaged gap into a BPM number.

**Key Features:**

- ✅ All-hardware beat detection and BPM conversion (no CPU, no multiplier)
- ✅ Streaming sample interface (process while capturing)
- ✅ Stability-aware locking with a 4-level confidence score
- ✅ 6 output signals (BPM byte + 5 status flags)
- ✅ Assumes 50 MHz core clock, ~100 Hz audio envelope sample rate
- ✅ Silence/overflow detection so stale readings are never shown as valid

**Typical accuracy:** locks within 4-8 beats on a steady rhythm; see
[docs/CALIBRATION.md](docs/CALIBRATION.md) for tuning against real music.

## Quick Start

1. **Review the interface:** [docs/info.md](docs/info.md) — pin
   mappings and how the algorithm works.
2. **Integrate with a microcontroller:**
   [docs/INTEGRATION.md](docs/INTEGRATION.md) — wiring plus a complete
   [Arduino example](examples/arduino_example.ino).
3. **Tune for your audio source:**
   [docs/CALIBRATION.md](docs/CALIBRATION.md) — threshold and sample-rate
   adjustment guide.

## Hardware Architecture

1. **Onset Detector** (`src/onset_detector.v`) — shift-based envelope
   follower + threshold comparator + refractory window
2. **Interval Counter** (`src/interval_counter.v`) — measures samples
   between onsets, with saturation protection
3. **Tempo Estimator** (`src/tempo_estimator.v`) — 4-entry interval
   history, averaging, and stability/confidence scoring
4. **BPM Divider** (`src/bpm_divider.v`) — bit-serial restoring divider,
   13 cycles, converts interval to BPM
5. **Result Latch** (`src/result_latch.v`) — registers every output for
   glitch-free pins

Each stage is a single-responsibility module wired together in
`src/project.v`.

## Testing

**Unit tests (`test/test.py`, all passing):**

- Reset produces quiescent outputs
- A single loud sample above the quiet floor raises a beat pulse
- A flat signal never false-triggers
- Regular beats reach `tempo_locked`
- BPM output matches the expected value for a known interval
- Odd BPM quotients retain the divider's final bit
- `frame_reset` clears the lock and history
- Long silence raises `overflow_flag`

**Edge cases (`test/test_edge_cases.py`, all passing):**

- Disabled chip (`ena=0`) drives all outputs to zero
- Wildly jittery intervals never reach `tempo_locked`
- A sustained tempo change relocks onto the new BPM
- An extremely short interval clamps to 255 rather than wrapping
- `frame_reset` mid-stream doesn't corrupt subsequent tracking
- Long intervals average correctly without sum overflow

Run tests locally:

```
cd test
make
```

## Files

- `src/project.v` — top-level module and pin mapping
- `src/onset_detector.v`, `src/interval_counter.v`,
  `src/tempo_estimator.v`, `src/bpm_divider.v`, `src/result_latch.v` —
  the five pipeline stages
- `docs/info.md` — interface specification
- `docs/INTEGRATION.md` — hardware integration guide
- `docs/CALIBRATION.md` — threshold tuning guide
- `examples/arduino_example.ino` — complete Arduino example
- `test/test.py`, `test/test_edge_cases.py` — cocotb functional tests

## Resources

- [Tiny Tapeout](https://tinytapeout.com/) — Manufacturing platform
- [RP2040 Pico](https://www.raspberrypi.com/products/raspberry-pi-pico/) — Recommended microcontroller
