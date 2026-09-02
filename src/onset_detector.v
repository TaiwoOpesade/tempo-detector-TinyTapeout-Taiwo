`default_nettype none
`timescale 1ns / 1ps

// onset_detector
// -----------------------------------------------------------------------
// Tracks a slow-moving envelope (baseline) of the incoming audio stream
// using a single-pole IIR filter built entirely from shifts and adds
// (no multiplier). A "beat onset" is flagged the first sample where the
// instantaneous sample jumps ONSET_THRESHOLD above the baseline, after
// which a refractory window suppresses re-triggering on the same beat.
// -----------------------------------------------------------------------
module onset_detector #(
    parameter integer DECAY_SHIFT       = 4,   // baseline tracks 1/16th of the gap per sample
    parameter integer ONSET_THRESHOLD   = 20,  // sample must exceed baseline + this to trigger
    parameter integer REFRACTORY_CYCLES = 5    // samples to ignore after a trigger
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire        enable,
    input  wire        sample_valid,
    input  wire [7:0]  sample,
    output wire        onset_pulse,   // one sample_valid-wide pulse per detected beat
    output wire        onset_active   // combinational: sample currently above threshold
);

    // baseline_acc stores the baseline scaled up by 2^DECAY_SHIFT for headroom
    reg signed [15:0] baseline_acc;
    reg [7:0]          refractory_cnt;
    reg                above_prev;

    wire signed [15:0] sample_scaled  = {8'd0, sample} <<< DECAY_SHIFT;
    wire signed [15:0] baseline_gap   = sample_scaled - baseline_acc;
    wire signed [15:0] baseline_step  = baseline_gap >>> DECAY_SHIFT;
    wire signed [15:0] baseline_shift = baseline_acc >>> DECAY_SHIFT;

    // Clamp the recovered baseline back into the 0-255 sample range.
    wire [7:0] baseline_level = (baseline_shift < 16'sd0)   ? 8'd0   :
                                (baseline_shift > 16'sd255) ? 8'd255 :
                                baseline_shift[7:0];

    // Widen to 9 bits so baseline + threshold can't wrap before comparing.
    wire [8:0] onset_reference = {1'b0, baseline_level} + ONSET_THRESHOLD[8:0];
    assign onset_active = ({1'b0, sample} > onset_reference);

    wire refractory_open = (refractory_cnt == 8'd0);
    wire rising_edge_hit = onset_active && !above_prev && refractory_open;

    assign onset_pulse = sample_valid && rising_edge_hit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baseline_acc   <= 16'sd0;
            refractory_cnt <= 8'd0;
            above_prev     <= 1'b0;
        end else if (!enable) begin
            baseline_acc   <= 16'sd0;
            refractory_cnt <= 8'd0;
            above_prev     <= 1'b0;
        end else if (sample_valid) begin
            baseline_acc <= baseline_acc + baseline_step;
            above_prev   <= onset_active;

            if (rising_edge_hit) begin
                refractory_cnt <= REFRACTORY_CYCLES[7:0];
            end else if (refractory_cnt != 8'd0) begin
                refractory_cnt <= refractory_cnt - 8'd1;
            end
        end
    end

endmodule
