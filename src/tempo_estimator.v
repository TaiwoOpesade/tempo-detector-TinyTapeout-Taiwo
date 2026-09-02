`default_nettype none
`timescale 1ns / 1ps

// tempo_estimator
// -----------------------------------------------------------------------
// Keeps a 4-entry shift-register history of the most recent beat-to-beat
// intervals. Every time a new (non-stale) interval arrives, it is
// combined with the previous 3 to form a 4-value candidate window; once
// at least 4 intervals have ever been seen, the average of that window
// (a free shift, since 4 is a power of two) and its spread (max - min)
// are used to classify tempo stability:
//   spread <= avg/16  -> confidence 3 (high), tempo_locked
//   spread <= avg/4   -> confidence 2 (medium), tempo_locked
//   spread <= avg/2   -> confidence 1 (low), not locked
//   otherwise         -> confidence 0 (none), not locked
// An interval that comes back close to MAX_INTERVAL means the source
// went quiet for a while (song paused/changed) - that reading is
// discarded and the history restarts, rather than being averaged in as
// a bogus data point.
// -----------------------------------------------------------------------
module tempo_estimator #(
    parameter integer WIDTH           = 10,
    parameter integer STALE_THRESHOLD = 900
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               frame_reset,
    input  wire               interval_valid,
    input  wire [WIDTH-1:0]   last_interval,

    output reg  [WIDTH-1:0]   avg_interval,
    output reg                avg_valid,      // one-cycle pulse: new average ready
    output reg                tempo_locked,
    output reg  [1:0]         confidence
);

    reg [WIDTH-1:0] hist0, hist1, hist2; // hist0 = most recent
    reg [2:0]       fill_count;

    wire is_stale = (last_interval >= STALE_THRESHOLD[WIDTH-1:0]);

    // Candidate 4-value window if this interval is accepted: the new
    // sample plus the 3 most recent history entries (the oldest entry drops off).
    wire [WIDTH-1:0] c0 = last_interval;
    wire [WIDTH-1:0] c1 = hist0;
    wire [WIDTH-1:0] c2 = hist1;
    wire [WIDTH-1:0] c3 = hist2;

    wire [WIDTH-1:0] max01 = (c0 > c1) ? c0 : c1;
    wire [WIDTH-1:0] max23 = (c2 > c3) ? c2 : c3;
    wire [WIDTH-1:0] cmax  = (max01 > max23) ? max01 : max23;
    wire [WIDTH-1:0] min01 = (c0 < c1) ? c0 : c1;
    wire [WIDTH-1:0] min23 = (c2 < c3) ? c2 : c3;
    wire [WIDTH-1:0] cmin  = (min01 < min23) ? min01 : min23;
    wire [WIDTH-1:0] cspread = cmax - cmin;

    // Four WIDTH-bit values need WIDTH+2 bits before the divide-by-four.
    // Keeping the extra carry bits avoids corrupting averages for slower
    // tempos (for example, four intervals of 400 samples sum to 1600).
    wire [WIDTH+1:0] csum = {2'b00, c0} + {2'b00, c1} +
                             {2'b00, c2} + {2'b00, c3};
    wire [WIDTH-1:0] cavg = csum[WIDTH+1:2];

    wire window_full = (fill_count >= 3'd3); // this interval makes it 4

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hist0        <= {WIDTH{1'b0}};
            hist1        <= {WIDTH{1'b0}};
            hist2        <= {WIDTH{1'b0}};
            fill_count   <= 3'd0;
            avg_interval <= {WIDTH{1'b0}};
            avg_valid    <= 1'b0;
            tempo_locked <= 1'b0;
            confidence   <= 2'b00;
        end else if (!enable || frame_reset) begin
            hist0        <= {WIDTH{1'b0}};
            hist1        <= {WIDTH{1'b0}};
            hist2        <= {WIDTH{1'b0}};
            fill_count   <= 3'd0;
            avg_valid    <= 1'b0;
            tempo_locked <= 1'b0;
            confidence   <= 2'b00;
        end else begin
            avg_valid <= 1'b0;

            if (interval_valid) begin
                if (is_stale) begin
                    hist0        <= {WIDTH{1'b0}};
                    hist1        <= {WIDTH{1'b0}};
                    hist2        <= {WIDTH{1'b0}};
                    fill_count   <= 3'd0;
                    tempo_locked <= 1'b0;
                    confidence   <= 2'b00;
                end else begin
                    hist2 <= hist1;
                    hist1 <= hist0;
                    hist0 <= last_interval;

                    if (fill_count < 3'd4)
                        fill_count <= fill_count + 3'd1;

                    if (window_full) begin
                        avg_valid    <= 1'b1;
                        avg_interval <= cavg;

                        if (cspread <= (cavg >> 4)) begin
                            confidence   <= 2'b11;
                            tempo_locked <= 1'b1;
                        end else if (cspread <= (cavg >> 2)) begin
                            confidence   <= 2'b10;
                            tempo_locked <= 1'b1;
                        end else if (cspread <= (cavg >> 1)) begin
                            confidence   <= 2'b01;
                            tempo_locked <= 1'b0;
                        end else begin
                            confidence   <= 2'b00;
                            tempo_locked <= 1'b0;
                        end
                    end
                end
            end
        end
    end

endmodule
