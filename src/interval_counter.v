`default_nettype none
`timescale 1ns / 1ps

// interval_counter
// -----------------------------------------------------------------------
// Counts audio samples (sample_valid pulses) since the last validated
// beat onset. When a new onset arrives, the running count is captured as
// last_interval and the counter restarts. If the counter reaches
// MAX_INTERVAL before the next onset (very slow tempo, or silence) it
// saturates and raises overflow_flag instead of wrapping.
// -----------------------------------------------------------------------
module interval_counter #(
    parameter integer WIDTH        = 10,
    parameter integer MAX_INTERVAL = 1023
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  enable,
    input  wire                  sample_valid,
    input  wire                  onset_pulse,
    output reg  [WIDTH-1:0]      last_interval,
    output reg                   interval_valid,  // pulses when last_interval updates
    output reg                   overflow_flag
);

    reg [WIDTH-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count          <= {WIDTH{1'b0}};
            last_interval  <= {WIDTH{1'b0}};
            interval_valid <= 1'b0;
            overflow_flag  <= 1'b0;
        end else if (!enable) begin
            count          <= {WIDTH{1'b0}};
            interval_valid <= 1'b0;
            overflow_flag  <= 1'b0;
        end else begin
            interval_valid <= 1'b0;

            if (sample_valid) begin
                if (onset_pulse) begin
                    last_interval  <= count;
                    interval_valid <= 1'b1;
                    count          <= {WIDTH{1'b0}};
                    overflow_flag  <= 1'b0;
                end else if (count == MAX_INTERVAL[WIDTH-1:0]) begin
                    overflow_flag <= 1'b1;      // stayed saturated: no beat for a long time
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end

endmodule
