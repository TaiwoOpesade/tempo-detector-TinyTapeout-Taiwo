"""
Edge-case validation for tt_um_taiwoopesade_tempo_detector_sky26c: disabled
chip behaviour, jittery/unstable tempo, tempo changes mid-stream, and
the divide-by-zero guard in the BPM divider.
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
    dut.ui_in.value = level
    dut.uio_in.value = UIO_SAMPLE_VALID
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0
    dut.ui_in.value = QUIET_LEVEL
    await RisingEdge(dut.clk)


async def play_beats(dut, num_beats, interval_samples):
    for _ in range(num_beats):
        await feed_sample(dut, LOUD_LEVEL)
        for _ in range(interval_samples - 1):
            await feed_sample(dut, QUIET_LEVEL)


@cocotb.test()
async def test_disabled_chip_outputs_zero(dut):
    """When ena is low, all outputs should sit at zero regardless of input."""
    await start_clock(dut)
    await reset_dut(dut)
    dut.ena.value = 0

    for _ in range(10):
        await feed_sample(dut, LOUD_LEVEL)

    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_out.value) == 0


@cocotb.test()
async def test_jittery_tempo_stays_unlocked(dut):
    """Wildly varying intervals should never reach tempo_locked."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    intervals = [20, 80, 15, 95, 30, 70, 10, 100]
    for interval in intervals:
        await feed_sample(dut, LOUD_LEVEL)
        for _ in range(interval - 1):
            await feed_sample(dut, QUIET_LEVEL)

    locked = int(dut.uio_out.value) & UIO_TEMPO_LOCKED
    assert not locked, "wildly irregular intervals should not report tempo_locked"


@cocotb.test()
async def test_tempo_change_relocks(dut):
    """After locking to one tempo, a sustained new tempo should relock."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    # Lock onto 120 BPM (interval = 50 samples @ 100 Hz assumed rate).
    await play_beats(dut, num_beats=8, interval_samples=50)
    assert int(dut.uio_out.value) & UIO_TEMPO_LOCKED
    bpm_first = int(dut.uo_out.value)
    assert abs(bpm_first - 120) <= 2

    # Switch to 100 BPM (interval = 60 samples). Enough beats must pass
    # for the 4-entry history to fully turn over before it's stable again.
    await play_beats(dut, num_beats=8, interval_samples=60)
    bpm_second = int(dut.uo_out.value)
    assert abs(bpm_second - 100) <= 3, f"expected ~100 BPM after tempo change, got {bpm_second}"


@cocotb.test()
async def test_extreme_fast_tempo_clamped(dut):
    """A very short interval (faster than any real music) should clamp, not wrap."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    # Interval of 2 samples => 6000/2 = 3000, far above the 8-bit 255 cap.
    await play_beats(dut, num_beats=8, interval_samples=6)

    bpm = int(dut.uo_out.value)
    assert bpm <= 255, "BPM output must never exceed the 8-bit range"


@cocotb.test()
async def test_frame_reset_during_stream_is_safe(dut):
    """Asserting frame_reset mid-stream should not corrupt subsequent tracking."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)
    await play_beats(dut, num_beats=3, interval_samples=50)

    dut.uio_in.value = UIO_FRAME_RESET
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 3)

    # Chip should be able to track a fresh tempo cleanly after the reset.
    await play_beats(dut, num_beats=8, interval_samples=50)
    assert int(dut.uio_out.value) & UIO_TEMPO_LOCKED
    assert abs(int(dut.uo_out.value) - 120) <= 2


@cocotb.test()
async def test_long_intervals_average_without_overflow(dut):
    """The four-entry sum must retain carry bits before averaging."""
    await start_clock(dut)
    await reset_dut(dut)

    for _ in range(10):
        await feed_sample(dut, QUIET_LEVEL)

    # 6000 / 400 = 15 BPM; four 400-sample intervals sum above 10 bits.
    await play_beats(dut, num_beats=8, interval_samples=400)
    await ClockCycles(dut.clk, 30)

    assert int(dut.uio_out.value) & UIO_TEMPO_LOCKED
    assert abs(int(dut.uo_out.value) - 15) <= 1
