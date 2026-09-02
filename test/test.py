"""
Functional tests for tt_um_taiwoopesade_tempo_detector_sky26c.

Drives synthetic audio streams (periodic loud pulses on a quiet floor)
into the chip and checks that it reports beat pulses, converges on the
expected BPM, and reaches a stable "locked" state.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


QUIET_LEVEL = 20
LOUD_LEVEL = 200

UIO_SAMPLE_VALID = 0b0000_0001
UIO_FRAME_RESET = 0b0000_0010

UIO_BEAT_PULSE = 0b0000_0100
UIO_TEMPO_LOCKED = 0b0000_1000
UIO_ONSET_ACTIVE = 0b0001_0000
UIO_OVERFLOW = 0b0010_0000


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())


async def reset_dut(dut):
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def feed_sample(dut, level):
    """
    Present one sample with sample_valid pulsed for exactly one clock,
    then wait one further settled clock so registered outputs driven by
    this sample (beat_pulse, etc.) are visible to a read immediately
    after this coroutine returns.
    """
    dut.ui_in.value = level
    dut.uio_in.value = UIO_SAMPLE_VALID
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0
    dut.ui_in.value = QUIET_LEVEL
    await RisingEdge(dut.clk)


async def play_beats(dut, num_beats, interval_samples, idle_cycles_between=3):
    """
    Feed `num_beats` beats, each a single loud sample followed by
    `interval_samples - 1` quiet samples, with a few idle (non-valid)
    clock cycles sprinkled in between samples to mimic a slower external
    sample clock than the chip's core clock.
    """
    beats_seen = 0
    for _ in range(num_beats):
        await feed_sample(dut, LOUD_LEVEL)
        if int(dut.uio_out.value) & UIO_BEAT_PULSE:
            beats_seen += 1
        await ClockCycles(dut.clk, idle_cycles_between)

        for _ in range(interval_samples - 1):
            await feed_sample(dut, QUIET_LEVEL)
            await ClockCycles(dut.clk, idle_cycles_between)

    return beats_seen


@cocotb.test()
async def test_reset_state(dut):
    """After reset, outputs should be quiescent."""
    await start_clock(dut)
    await reset_dut(dut)

    assert int(dut.uo_out.value) == 0, "bpm_estimate should start at 0"
    assert (int(dut.uio_out.value) & UIO_TEMPO_LOCKED) == 0
    assert (int(dut.uio_out.value) & UIO_BEAT_PULSE) == 0


@cocotb.test()
async def test_single_beat_produces_pulse(dut):
    """A single loud sample above the quiet floor should raise a beat pulse."""
    await start_clock(dut)
    await reset_dut(dut)

    # Settle the envelope on the quiet floor first.
    for _ in range(20):
        await feed_sample(dut, QUIET_LEVEL)

    await feed_sample(dut, LOUD_LEVEL)
    pulse = int(dut.uio_out.value) & UIO_BEAT_PULSE
    assert pulse, "expected beat_pulse to assert on a loud sample after quiet"


@cocotb.test()
async def test_no_false_positive_on_steady_signal(dut):
    """A perfectly flat signal (no dynamics) should never trigger a beat."""
    await start_clock(dut)
    await reset_dut(dut)

    beats = 0
    for _ in range(60):
        await feed_sample(dut, QUIET_LEVEL)
        if int(dut.uio_out.value) & UIO_BEAT_PULSE:
            beats += 1

    assert beats == 0, f"expected no beats on a flat signal, saw {beats}"


@cocotb.test()
async def test_regular_beats_lock_tempo(dut):
    """A steady periodic beat pattern should eventually reach tempo_locked."""
    await start_clock(dut)
    await reset_dut(dut)

    # Let the envelope settle on the quiet floor.
    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    interval_samples = 50  # constant spacing between beats
    beats_seen = await play_beats(dut, num_beats=8, interval_samples=interval_samples)

    assert beats_seen >= 6, f"expected most beats to register, saw {beats_seen}/8"

    locked = int(dut.uio_out.value) & UIO_TEMPO_LOCKED
    confidence = (int(dut.uio_out.value) >> 6) & 0b11
    assert locked, "expected tempo_locked after several regular beats"
    assert confidence >= 2, f"expected high/medium confidence, got {confidence}"


@cocotb.test()
async def test_bpm_matches_expected_value(dut):
    """
    With SAMPLE_RATE_HZ = 100 baked into the divider (NUMERATOR = 6000),
    a fixed interval of 50 samples between beats should converge to
    bpm = 6000 / 50 = 120.
    """
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    await play_beats(dut, num_beats=10, interval_samples=50)

    # Give the bit-serial divider (13 cycles) time to finish after the
    # last beat's average was computed.
    await ClockCycles(dut.clk, 30)

    bpm = int(dut.uo_out.value)
    assert abs(bpm - 120) <= 2, f"expected ~120 BPM, got {bpm}"


@cocotb.test()
async def test_bpm_preserves_odd_quotient(dut):
    """The serial divider must retain the low bit for odd BPM results."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    # The test driver contributes one onset sample plus 48 quiet samples,
    # making the measured interval 48: 6000 / 48 = 125.
    await play_beats(dut, num_beats=8, interval_samples=49)
    await ClockCycles(dut.clk, 30)

    assert abs(int(dut.uo_out.value) - 125) <= 1


@cocotb.test()
async def test_frame_reset_clears_lock(dut):
    """Asserting frame_reset should drop tempo_locked and clear history."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)
    await play_beats(dut, num_beats=8, interval_samples=50)

    assert int(dut.uio_out.value) & UIO_TEMPO_LOCKED, "should be locked before reset"

    dut.uio_in.value = UIO_FRAME_RESET
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 3)

    assert (int(dut.uio_out.value) & UIO_TEMPO_LOCKED) == 0, "lock should clear on frame_reset"


@cocotb.test()
async def test_overflow_flag_on_long_silence(dut):
    """A very long gap with no beat should raise overflow_flag."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)
    # Establish one beat, then go quiet for far longer than any
    # realistic interval to force the interval counter to saturate.
    await feed_sample(dut, LOUD_LEVEL)

    for _ in range(1100):
        await feed_sample(dut, QUIET_LEVEL)

    assert int(dut.uio_out.value) & UIO_OVERFLOW, "expected overflow_flag after long silence"
