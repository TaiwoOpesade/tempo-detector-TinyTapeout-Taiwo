`default_nettype none
`timescale 1ns / 1ps

// bpm_divider
// -----------------------------------------------------------------------
// Converts an averaged inter-onset interval (measured in audio samples)
// into a BPM value using bpm = (60 * SAMPLE_RATE_HZ) / interval_samples.
// NUMERATOR is that constant, precomputed at synthesis time so the chip
// never needs a multiplier. The division itself is a classic bit-serial
// restoring divider: one dividend bit consumed per clock, NUM_WIDTH
// cycles total. No lookup tables, no combinational divider - just a
// small shift/compare/subtract loop, matching the "no complex state
// machines, just registers and comparators" spirit of the rest of the
// design.
// -----------------------------------------------------------------------
module bpm_divider #(
    parameter integer NUM_WIDTH  = 13,
    parameter integer DEN_WIDTH  = 10,
    parameter integer NUMERATOR  = 6000   // 60 * SAMPLE_RATE_HZ(=100)
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   enable,
    input  wire                   start,
    input  wire [DEN_WIDTH-1:0]   denominator,
    output reg  [7:0]             quotient,
    output reg                    done,
    output wire                   busy
);

    localparam [NUM_WIDTH-1:0] NUM_CONST = NUMERATOR[NUM_WIDTH-1:0];
    localparam integer REM_WIDTH = DEN_WIDTH + 1;
    localparam integer BIT_INDEX_WIDTH = $clog2(NUM_WIDTH);

    reg [BIT_INDEX_WIDTH-1:0] bit_idx;
    reg [REM_WIDTH-1:0]       rem;
    reg [NUM_WIDTH-1:0]       quo;
    reg [DEN_WIDTH-1:0]       denom_reg;
    reg                       running;

    assign busy = running;

    wire [REM_WIDTH-1:0] shifted_rem = {rem[REM_WIDTH-2:0], NUM_CONST[bit_idx]};
    wire [REM_WIDTH-1:0] denom_ext   = {1'b0, denom_reg};
    wire                 can_subtract = shifted_rem >= denom_ext;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running   <= 1'b0;
            done      <= 1'b0;
            quotient  <= 8'd0;
            bit_idx   <= {BIT_INDEX_WIDTH{1'b0}};
            rem       <= {REM_WIDTH{1'b0}};
            quo       <= {NUM_WIDTH{1'b0}};
            denom_reg <= {DEN_WIDTH{1'b0}};
        end else if (!enable) begin
            running <= 1'b0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!running) begin
                if (start) begin
                    if (denominator == {DEN_WIDTH{1'b0}}) begin
                        // Divide-by-zero guard: no interval measured yet.
                        quotient <= 8'd255;
                        done     <= 1'b1;
                        running  <= 1'b0;
                    end else begin
                        rem       <= {REM_WIDTH{1'b0}};
                        quo       <= {NUM_WIDTH{1'b0}};
                        denom_reg <= denominator;
                        bit_idx   <= NUM_WIDTH - 1;
                        running   <= 1'b1;
                    end
                end
            end else begin
                if (can_subtract) begin
                    rem            <= shifted_rem - denom_ext;
                    quo[bit_idx]   <= 1'b1;
                end else begin
                    rem            <= shifted_rem;
                    quo[bit_idx]   <= 1'b0;
                end

                if (bit_idx == 0) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                    // Clamp: BPM output is only 8 bits wide (0-255), which
                    // comfortably covers the entire musical tempo range.
                    // quo[0] is being assigned above in this same clock
                    // edge, so include the current compare explicitly.
                    // Otherwise every odd quotient would be rounded down.
                    if (|quo[NUM_WIDTH-1:8]) begin
                        quotient <= 8'd255;
                    end else if (can_subtract) begin
                        quotient <= {quo[7:1], 1'b1};
                    end else begin
                        quotient <= {quo[7:1], 1'b0};
                    end
                end else begin
                    bit_idx <= bit_idx - 1'b1;
                end
            end
        end
    end

endmodule
