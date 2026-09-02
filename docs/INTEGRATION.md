# Integration Guide

## Example setup: electret microphone + RP2040 Pico

```
┌──────────────┐
│  Electret Mic│ analog audio
│  + preamp    ├──────────────────────┐
└──────────────┘                      │
                                       ▼
┌──────────────────────┐          ┌──────────────────────┐
│  RP2040 Pico         │          │  TinyTapeout Board   │
│  Microcontroller     │◄────────►│  Tempo Detector Chip │
│  - ADC samples mic   │          │  - Detects onsets    │
│  - Rectify + decimate│          │  - Estimates BPM     │
│  - Drives ui_in/uio_in         │  - Outputs bpm_estimate │
└──────────────────────┘          └──────────────────────┘
        ▲
        │ USB/Serial
        ▼
   PC or Phone
   (Display BPM)
```

## Step 1: Get audio down to an amplitude envelope

The chip does not do FFTs or filtering — it expects an amplitude
envelope, not raw audio. On the microcontroller:

1. Sample the microphone's analog output with the ADC at a few kHz.
2. Rectify (take the absolute value around the ADC's mid-point) and
   apply a simple moving-average or peak-hold over a short window.
3. Decimate down to **~100 Hz** — one 8-bit envelope value every 10 ms.
   This must match the `NUMERATOR` baked into the chip's divider (see
   [CALIBRATION.md](CALIBRATION.md) if you need a different rate).
4. Scale the result to fit 0-255 and drive it onto `ui_in`.

## Step 2: Drive the strobe

Each time a new envelope value is ready:

```cpp
digitalWrite(PIN_AUDIO_SAMPLE_0, (envelope >> 0) & 1);
// ... set all 8 audio_sample pins ...
digitalWrite(PIN_SAMPLE_VALID, HIGH);
delayMicroseconds(1);           // hold for at least one chip clock
digitalWrite(PIN_SAMPLE_VALID, LOW);
```

See [`examples/arduino_example.ino`](../examples/arduino_example.ino) for
a complete, runnable version of this loop, including reading back
`bpm_estimate` and `tempo_locked`.

## Step 3: Read the results

- Poll `uio_out[3]` (`tempo_locked`) before trusting `uo_out`
  (`bpm_estimate`) — the estimate is only meaningful once locked.
- Watch `uio_out[7:6]` (`confidence`) if you want a softer readout (e.g.
  show a "locking..." animation at confidence 1-2, a solid BPM number at
  confidence 3).
- `uio_out[5]` (`overflow_flag`) tells you the source has gone quiet —
  good for triggering a "no beat detected" UI state instead of showing a
  stale number.

## Step 4: Starting a new track

Pulse `uio_in[1]` (`frame_reset`) high for at least one chip clock cycle
whenever you know the source has changed (a new song started, or you've
switched inputs) so the old tempo history doesn't bleed into the new
track's average.
