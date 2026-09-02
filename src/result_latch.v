`default_nettype none
`timescale 1ns / 1ps

// result_latch
// -----------------------------------------------------------------------
// Final output stage: registers every chip output on the clock so pin
// values are always glitch-free, regardless of the combinational paths
// feeding them. bpm_estimate only updates when the divider reports done;
// everything else tracks its upstream source every cycle.
// -----------------------------------------------------------------------
module result_latch (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,

    input  wire [7:0] bpm_in,
    input  wire        bpm_done,
    input  wire        onset_pulse_in,
    input  wire        onset_active_in,
    input  wire        overflow_in,
    input  wire        tempo_locked_in,
    input  wire [1:0]  confidence_in,

    output reg  [7:0]  bpm_estimate,
    output reg         beat_pulse,
    output reg         onset_active,
    output reg         overflow_flag,
    output reg         tempo_locked,
    output reg  [1:0]  confidence
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bpm_estimate  <= 8'd0;
            beat_pulse    <= 1'b0;
            onset_active  <= 1'b0;
            overflow_flag <= 1'b0;
            tempo_locked  <= 1'b0;
            confidence    <= 2'b00;
        end else if (!enable) begin
            beat_pulse    <= 1'b0;
            onset_active  <= 1'b0;
            overflow_flag <= 1'b0;
            tempo_locked  <= 1'b0;
            confidence    <= 2'b00;
        end else begin
            beat_pulse    <= onset_pulse_in;
            onset_active  <= onset_active_in;
            overflow_flag <= overflow_in;
            tempo_locked  <= tempo_locked_in;
            confidence    <= confidence_in;

            if (bpm_done)
                bpm_estimate <= bpm_in;
        end
    end

endmodule
