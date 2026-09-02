`default_nettype none
`timescale 1ns / 1ps

// tt_um_taiwoopesade_tempo_detector_sky26c
// =========================================================================
// Hardware Audio Tempo (BPM) Detector — TinyTapeout submission
//
// Streams 8-bit audio amplitude samples in, tracks their envelope with a
// shift-based single-pole filter, flags a "beat onset" whenever a sample
// spikes above that envelope, measures the time between onsets, and
// converts the averaged interval into an estimated BPM entirely in
// hardware (no CPU, no multiplier - just registers, comparators, adders
// and a small bit-serial divider).
//
// Pin map
// -------
// ui_in[7:0]   audio_sample   - streaming unsigned 8-bit amplitude sample
// uio_in[0]    sample_valid   - strobe: a new sample is present this cycle
// uio_in[1]    frame_reset    - restart tempo tracking (new track/song)
// uio_in[7:2]  (unused, tri-stated as inputs)
// uo_out[7:0]  bpm_estimate   - latched BPM estimate (0-255, clamped)
// uio_out[2]   beat_pulse     - one-cycle pulse each detected beat
// uio_out[3]   tempo_locked   - high once recent intervals are stable
// uio_out[4]   onset_active   - raw (pre-refractory) onset flag, for debug
// uio_out[5]   overflow_flag  - no beat seen for a long time (silence)
// uio_out[7:6] confidence     - 2-bit stability score, 3 = tightest lock
// =========================================================================
module tt_um_taiwoopesade_tempo_detector_sky26c (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire        ena,
    input  wire        clk,
    input  wire        rst_n
);

    localparam integer INTERVAL_WIDTH = 10;
    localparam integer MAX_INTERVAL   = 1023;

    wire audio_sample_valid = uio_in[0];
    wire frame_reset        = uio_in[1];
    wire [7:0] audio_sample = ui_in;

    // --- Stage 1: onset detection -----------------------------------
    wire onset_pulse;
    wire onset_active;

    onset_detector #(
        .DECAY_SHIFT      (4),
        .ONSET_THRESHOLD  (20),
        .REFRACTORY_CYCLES(5)
    ) u_onset (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (ena),
        .sample_valid(audio_sample_valid),
        .sample      (audio_sample),
        .onset_pulse (onset_pulse),
        .onset_active(onset_active)
    );

    // --- Stage 2: interval measurement ------------------------------
    wire [INTERVAL_WIDTH-1:0] last_interval;
    wire                      interval_valid;
    wire                      interval_overflow;

    interval_counter #(
        .WIDTH       (INTERVAL_WIDTH),
        .MAX_INTERVAL(MAX_INTERVAL)
    ) u_interval (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (ena),
        .sample_valid  (audio_sample_valid),
        .onset_pulse   (onset_pulse),
        .last_interval (last_interval),
        .interval_valid(interval_valid),
        .overflow_flag (interval_overflow)
    );

    // --- Stage 3: tempo stability estimation ------------------------
    wire [INTERVAL_WIDTH-1:0] avg_interval;
    wire                      avg_valid;
    wire                      tempo_locked;
    wire [1:0]                confidence;

    tempo_estimator #(
        .WIDTH          (INTERVAL_WIDTH),
        .STALE_THRESHOLD(900)
    ) u_estimator (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (ena),
        .frame_reset    (frame_reset),
        .interval_valid (interval_valid),
        .last_interval  (last_interval),
        .avg_interval   (avg_interval),
        .avg_valid      (avg_valid),
        .tempo_locked   (tempo_locked),
        .confidence     (confidence)
    );

    // --- Stage 4: interval -> BPM conversion ------------------------
    wire [7:0] bpm_result;
    wire       bpm_done;
    wire       bpm_busy;

    bpm_divider #(
        .NUM_WIDTH(13),
        .DEN_WIDTH(INTERVAL_WIDTH),
        .NUMERATOR(6000)   // 60 * assumed 100 Hz envelope sample rate
    ) u_divider (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (ena),
        .start      (avg_valid),
        .denominator(avg_interval),
        .quotient   (bpm_result),
        .done       (bpm_done),
        .busy       (bpm_busy)
    );

    // --- Stage 5: registered output bank -----------------------------
    result_latch u_result (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (ena),
        .bpm_in         (bpm_result),
        .bpm_done       (bpm_done),
        .onset_pulse_in (onset_pulse),
        .onset_active_in(onset_active),
        .overflow_in    (interval_overflow),
        .tempo_locked_in(tempo_locked),
        .confidence_in  (confidence),
        .bpm_estimate   (uo_out),
        .beat_pulse     (uio_out[2]),
        .onset_active   (uio_out[4]),
        .overflow_flag  (uio_out[5]),
        .tempo_locked   (uio_out[3]),
        .confidence     (uio_out[7:6])
    );

    assign uio_out[1:0] = 2'b00;
    assign uio_oe       = 8'b1111_1100;

    // Silence unused-signal lint warnings without affecting behaviour.
    wire _unused = &{1'b0, ui_in[7:0], uio_in[7:2], bpm_busy, 1'b0};

endmodule
