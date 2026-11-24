// ============================================================================
// Framebuffer readout and phosphor-decay stage.
// Written 2026 by Videodr0me
// Reads tile rows from DDRAM, converts them back to pixels, and applies
// phosphor decay. Color decoding belongs to the downstream consumers.
// ============================================================================

module vfb_readout #(
	parameter TILE_SIZE       =  8,
	parameter MAX_BURST_TILES = 15
) (
	input  logic clk_sys,
	input  logic reset,

	// DDRAM read interface
	output logic        readout_ready,
	input  logic        readout_grant,
	output logic [15:0] readout_tile_id,
	output logic [8:0]  readout_burstcnt,
	input  logic [63:0] readout_data,
	input  logic        readout_data_valid,

	output logic        vbl_swap_req,
	input  logic        frame_start_req,

	// Video output
	// RGB[15:13], zero[12:9], display value[8:0].
	// Value[8]=0: 8-bit level; value[8]=1: {1, primary_is_255, 7-bit share}.
	output logic [15:0] CANONICAL_PIXEL,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  logic [10:0] h_cnt,
	input  logic [10:0] v_cnt,
	input  logic        ce_pix,
	input  logic        hsync,
	input  logic        vsync,
	input  logic        hblank,
	input  logic        vblank,

	input  logic [11:0] RENDER_WIDTH,
	input  logic [11:0] RENDER_HEIGHT,

	input  logic [3:0]  draw_idx,           // Phosphor persistence draw index
	input  logic [63:0] phosphor_age_map,   // 16 packed physical-age entries
	input  logic [1:0]  osd_phosphor_mode,  // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  logic        full_spill_primary,
	input  logic        display_is_composed,

	output logic [14:0] display_tile_addr,
	input  logic        display_tile_dirty
);
	import vfb_layout_pkg::*;

	initial begin
		if (TILE_SIZE != 8)
			$error("vfb_readout TILE_SIZE must be 8");
		if (MAX_BURST_TILES < 1 || MAX_BURST_TILES > 15)
			$error("vfb_readout MAX_BURST_TILES must be between 1 and 15");
	end

	// Two alternating row buffers hold 184 active tiles and one blanking guard
	// tile. Each row is split between 2K and 1K banks.
	localparam ROW_TILES      =  185;
	localparam ROW_LOW_WORDS  = 2048;
	localparam ROW_HIGH_WORDS = 1024;
	logic [1:0]  phosphor_mode_control_q =    2'd0;
	logic [11:0] render_width_q          = 12'd720;
	logic [11:0] render_height_q         = 12'd480;

	always_ff @(posedge clk_sys) begin
		phosphor_mode_control_q <= osd_phosphor_mode;
		render_width_q          <= RENDER_WIDTH;
		render_height_q         <= RENDER_HEIGHT;
	end

	(* ramstyle = "M10K" *) logic [63:0] buffer_0_low [0:ROW_LOW_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_0_high [0:ROW_HIGH_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_1_low [0:ROW_LOW_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_1_high [0:ROW_HIGH_WORDS-1];

	logic buf_state;

	// Register timing before tile addressing and edge detection.
	logic [10:0] h_cnt_r, v_cnt_r;
	logic        hsync_r, vsync_r, hblank_r, vblank_r;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			// Reset registered timing state so the line-edge detector restarts
			// from a known blank state.
			h_cnt_r  <= 0;
			v_cnt_r  <= 0;
			hsync_r  <= 0;
			vsync_r  <= 0;
			hblank_r <= 1;
			vblank_r <= 1;
		end else begin
			h_cnt_r  <= h_cnt;
			v_cnt_r  <= v_cnt;
			hsync_r  <= hsync;
			vsync_r  <= vsync;
			hblank_r <= hblank;
			vblank_r <= vblank;
		end
	end

	// Detect line and VBLANK edges.
	logic [10:0] prev_h_cnt;
	logic        prev_hblank_r;
	logic        advance_row;
	logic [7:0]  advance_fetch_y;

	typedef enum logic [2:0] {
		IDLE,
		SCAN_WAIT,
		SCAN_DECIDE,
		ZERO_DATA,
		BURST_REQ,
		BURST_WAIT,
		BURST_DATA
	} fetch_state_t;
	fetch_state_t fetch_state = IDLE;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			prev_h_cnt      <= 0;
			prev_hblank_r   <= 1;
			advance_row     <= 0;
			advance_fetch_y <= 0;
			vbl_swap_req    <= 0;
		end else begin
			prev_h_cnt    <= h_cnt_r;
			prev_hblank_r <= hblank_r;

			advance_row   <= 0;
			vbl_swap_req  <= 0;

			// Start a new output line.
			if (h_cnt_r == 0 && prev_h_cnt != 0) begin
				if (v_cnt_r == render_height_q) begin
					// VBLANK starts: request a display-buffer handoff.
					vbl_swap_req <= 1;
				end
			end

			// Switch to the next prepared tile row during the blanking part of
			// local line 7.
			if (!prev_hblank_r && hblank_r) begin
				if ((v_cnt_r + 11'd1) < render_height_q && v_cnt_r[2:0] == 3'd7) begin
					if (fetch_state == IDLE) begin
						advance_row     <= 1;
						advance_fetch_y <= v_cnt_r[10:3] + 8'd2;
					end
				end
			end
		end
	end

	// Tile-grid dimensions change only with the video mode.
	logic [8:0] render_tile_cols;  // ceil(RENDER_WIDTH / 8)
	logic [8:0] render_tile_rows;  // ceil(RENDER_HEIGHT / 8)
	logic [8:0] render_last_tile_col;
	wire  [8:0] tile_cols_next = vfb_tile_columns(render_width_q);
	always_ff @(posedge clk_sys) begin
		render_tile_cols <= tile_cols_next;
		render_tile_rows <= vfb_tile_rows(render_height_q);
		// Keep the row-end threshold aligned with the same width sample.
		render_last_tile_col <= (tile_cols_next == 0) ? 9'd0 : tile_cols_next - 9'd1;
	end

	logic [7:0] fetch_tile_x;
	logic [7:0] target_fetch_y;
	(* preserve, dont_merge *) logic [14:0] fetch_tile_addr;
	logic row0_prefetch_active;

	logic [7:0] run_start_x;
	logic [4:0] run_length;      // Tile count, up to MAX_BURST_TILES.
	logic [4:0] zero_word_cnt;   // 0 to 15 for inline zeroing
	logic [8:0] burst_beat_cnt;  // Zero-based beat index within the burst.

	assign display_tile_addr = fetch_tile_addr;

	wire row_end  = ({1'b0, fetch_tile_x} >= render_last_tile_col);
	wire row_done = ({4'd0, fetch_tile_x} >= {3'd0, render_tile_cols});

	// Row-buffer write pipeline.
	logic        bram_we_r;
	logic        bram_buf_r;
	logic [11:0] bram_addr_r;
	logic [63:0] bram_data_r;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			fetch_state          <= IDLE;
			readout_ready        <= 0;
			buf_state            <= 0;
			bram_we_r            <= 0;
			fetch_tile_addr      <= 0;
			row0_prefetch_active <= 0;
		end else begin
			// At each display handoff, abandon an incomplete fetch and restart at row 0.
			if (frame_start_req) begin
				buf_state            <= 0;
				target_fetch_y       <= 0;
				fetch_tile_x         <= 0;
				fetch_tile_addr      <= 0;
				run_length           <= 0;
				fetch_state          <= SCAN_WAIT;
				readout_ready        <= 0;
				row0_prefetch_active <= 1;
			end else begin
				case (fetch_state)
					IDLE: begin
						if (advance_row) begin
							buf_state      <= ~buf_state;
							target_fetch_y <= advance_fetch_y;
							// Fetch only if the following row is visible.
							if ({1'b0, advance_fetch_y} < render_tile_rows) begin
								fetch_tile_x    <= 0;
								fetch_tile_addr <= vfb_tile_row_addr(advance_fetch_y);
								run_length      <= 0;
								fetch_state     <= SCAN_WAIT;
							end
						end
					end

				SCAN_WAIT: begin
					// Wait one cycle for the synchronous tilemap query.
					fetch_state <= SCAN_DECIDE;
				end

				SCAN_DECIDE: begin
					if (display_tile_dirty) begin
						if (run_length == 0) run_start_x <= fetch_tile_x;
						run_length      <= run_length + 5'd1;
						fetch_tile_x    <= fetch_tile_x + 8'd1;
						fetch_tile_addr <= fetch_tile_addr + 15'd1;
						if (row_end || run_length + 5'd1 == MAX_BURST_TILES[4:0])
							fetch_state <= BURST_REQ;
						else
							fetch_state <= SCAN_WAIT;
					end else if (run_length > 0) begin
						// Request the pending dirty run before checking this clean tile again.
						fetch_state <= BURST_REQ;
					end else begin
						// No dirty run is pending; clear the clean tile locally.
						zero_word_cnt <= 0;
						fetch_state   <= ZERO_DATA;
					end
				end

				ZERO_DATA: begin
					if (zero_word_cnt == 5'd15) begin
						if (row_end) begin
							if (row0_prefetch_active) begin
								row0_prefetch_active <= 0;
								buf_state            <= ~buf_state;
								target_fetch_y       <= 8'd1;
								if (render_tile_rows > 9'd1) begin
									fetch_tile_x    <= 0;
									fetch_tile_addr <= vfb_tile_row_addr(8'd1);
									run_length      <= 0;
									fetch_state     <= SCAN_WAIT;
								end else begin
									fetch_state <= IDLE;
								end
							end else begin
								fetch_state <= IDLE;
							end
						end else begin
							fetch_tile_x    <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state     <= SCAN_WAIT;
						end
					end else begin
						zero_word_cnt <= zero_word_cnt + 5'd1;
					end
				end

				BURST_REQ: begin
					readout_ready    <= 1;
					readout_tile_id  <= {target_fetch_y, run_start_x};
					readout_burstcnt <= {4'd0, run_length} << 4; // run_length * 16
					burst_beat_cnt   <= 0;
					fetch_state      <= BURST_WAIT;
				end

				BURST_WAIT: begin
					if (readout_grant) begin
						readout_ready <= 0;
						fetch_state   <= BURST_DATA;
					end
				end

				BURST_DATA: begin
					if (readout_data_valid) begin
						if (burst_beat_cnt + 9'd1 == readout_burstcnt) begin
							run_length <= 0;
							if (row_done) begin
								if (row0_prefetch_active) begin
									row0_prefetch_active <= 0;
									buf_state            <= ~buf_state;
									target_fetch_y       <= 8'd1;
									if (render_tile_rows > 9'd1) begin
										fetch_tile_x    <= 0;
										fetch_tile_addr <= vfb_tile_row_addr(8'd1);
										run_length      <= 0;
										fetch_state     <= SCAN_WAIT;
									end else begin
										fetch_state <= IDLE;
									end
								end else begin
									fetch_state <= IDLE;
								end
							end else begin
								fetch_state <= SCAN_WAIT;
							end
						end else begin
							burst_beat_cnt <= burst_beat_cnt + 9'd1;
						end
					end
				end
				endcase
			end

			// Write the prepared row-buffer word.
			bram_we_r <= 0;
			if (fetch_state == BURST_DATA && readout_data_valid) begin
				bram_we_r   <= 1;
				bram_buf_r  <= ~buf_state;
				bram_addr_r <= {run_start_x + burst_beat_cnt[8:4], burst_beat_cnt[3:0]};
				bram_data_r <= readout_data;
			end else if (fetch_state == ZERO_DATA) begin
				bram_we_r   <= 1;
				bram_buf_r  <= ~buf_state;
				bram_addr_r <= {fetch_tile_x, zero_word_cnt[3:0]};
				bram_data_r <= 64'd0;
			end

			if (bram_we_r) begin
				if (bram_buf_r == 0) begin
					if (!bram_addr_r[11])
						buffer_0_low[bram_addr_r[10:0]] <= bram_data_r;
					else
						buffer_0_high[bram_addr_r[9:0]] <= bram_data_r;
				end else begin
					if (!bram_addr_r[11])
						buffer_1_low[bram_addr_r[10:0]] <= bram_data_r;
					else
						buffer_1_high[bram_addr_r[9:0]] <= bram_data_r;
				end
			end
		end
	end

	// Convert tile words back to pixels. Canonical data, sync, and blanking
	// follow the row-read, decay, and five-CE alignment path.
	localparam READ_ADVANCE = 11;

	logic [READ_ADVANCE-1:0] hs_pipe, vs_pipe, hb_pipe, vb_pipe;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			hs_pipe <= {READ_ADVANCE{1'b1}};
			vs_pipe <= {READ_ADVANCE{1'b1}};
			hb_pipe <= {READ_ADVANCE{1'b1}};
			vb_pipe <= {READ_ADVANCE{1'b1}};
		end else if (ce_pix) begin
			hs_pipe <= {hs_pipe[READ_ADVANCE-2:0], hsync_r};
			vs_pipe <= {vs_pipe[READ_ADVANCE-2:0], vsync_r};
			hb_pipe <= {hb_pipe[READ_ADVANCE-2:0], hblank_r};
			vb_pipe <= {vb_pipe[READ_ADVANCE-2:0], vblank_r};
		end
	end

	wire vga_hs_pre     = hs_pipe[READ_ADVANCE-2];
	wire vga_vs_pre     = vs_pipe[READ_ADVANCE-2];
	wire vga_hblank_pre = hb_pipe[READ_ADVANCE-2];
	wire vga_vblank_pre = vb_pipe[READ_ADVANCE-2];

	// Pixel read addresses.
	wire  [7:0]  cur_tile_x     = h_cnt_r[10:3];
	wire  [5:0]  cur_offset     = {v_cnt_r[2:0], h_cnt_r[2:0]};
	wire  [7:0]  safe_tile_x    = (hblank_r || cur_tile_x >= ROW_TILES) ? 8'(ROW_TILES-1)
	                                                                    : cur_tile_x;
	wire  [13:0] read_addr      = {safe_tile_x, cur_offset}; // [13:2] = word addr, [1:0] = pixel sel
	wire  [11:0] read_word_addr = read_addr[13:2];
	logic [1:0]  pixel_sel_d1;
	logic [1:0]  pixel_sel_d2;
	logic        buf_state_d1;
	logic        word_bank_d1;
	logic [63:0] raw_word_0_low, raw_word_0_high;
	logic [63:0] raw_word_1_low, raw_word_1_high;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			pixel_sel_d1    <= read_addr[1:0];
			buf_state_d1    <= buf_state;
			word_bank_d1    <= read_word_addr[11];
			raw_word_0_low  <= buffer_0_low[read_word_addr[10:0]];
			raw_word_0_high <= buffer_0_high[read_word_addr[9:0]];
			raw_word_1_low  <= buffer_1_low[read_word_addr[10:0]];
			raw_word_1_high <= buffer_1_high[read_word_addr[9:0]];
		end
	end

	logic [63:0] raw_word;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			pixel_sel_d2 <= pixel_sel_d1;
			case ({buf_state_d1, word_bank_d1})
				2'b00: raw_word <= raw_word_0_low;
				2'b01: raw_word <= raw_word_0_high;
				2'b10: raw_word <= raw_word_1_low;
				2'b11: raw_word <= raw_word_1_high;
			endcase
		end
	end

	logic [15:0] raw_pixel;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			case (pixel_sel_d2)
				2'b00: raw_pixel <= raw_word[15:0];
				2'b01: raw_pixel <= raw_word[31:16];
				2'b10: raw_pixel <= raw_word[47:32];
				2'b11: raw_pixel <= raw_word[63:48];
			endcase
		end
	end

	// Decode the pixel and select its decay factor.
	wire [2:0] pixel_rgb_comb = raw_pixel[15:13];
	wire [8:0] pixel_int_comb = raw_pixel[8:0];

	// Map the stored draw-time phase to physical age.
	wire [3:0] pixel_draw_idx       = raw_pixel[12:9];
	wire [3:0] pixel_age_raw        = draw_idx - pixel_draw_idx;
	wire [5:0] pixel_age_map_offset = {pixel_age_raw, 2'b00};
	wire [3:0] pixel_age            = phosphor_age_map[pixel_age_map_offset +: 4];

	logic [7:0] decay_factor_comb;
	always_comb decay_factor_comb = vfb_decay_factor(phosphor_mode_control_q, pixel_age);

	// Register the decay factor with the decoded pixel.
	logic [7:0] decay_factor_r;
	logic [8:0] pixel_int_r;
	logic [2:0] pixel_rgb_r;
	logic [1:0] phosphor_mode_r;
	logic       display_composed_r;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			decay_factor_r     <= decay_factor_comb;
			pixel_int_r        <= pixel_int_comb;
			pixel_rgb_r        <= pixel_rgb_comb;
			phosphor_mode_r    <= phosphor_mode_control_q;
			display_composed_r <= display_is_composed;
		end
	end

	// Apply decay or keep the original intensity.
	wire [16:0] decayed_full = pixel_int_r * decay_factor_r;  // 9x8 = 17 bits
	wire [8:0]  decayed_int  = decayed_full[16:8];            // >>8

	wire [8:0] final_int_comb = (display_composed_r || (phosphor_mode_r == 2'd0)) ? pixel_int_r
	                                                                              : decayed_int;

	// Register post-decay energy before encoding the display word.
	logic [8:0] final_int;
	logic [2:0] pixel_rgb;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			final_int <= final_int_comb;
			pixel_rgb <= pixel_rgb_r;
		end
	end

	// Subtract the spill reference and divide its excess on successive pixel
	// enables. The resulting display word follows the same five alignment stages.
	logic [2:0]  spill_mask_q;
	logic [8:0]  spill_energy_q, spill_excess_q;
	logic        full_primary_q;
	logic [15:0] canonical_pipe [1:4];
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			spill_mask_q      <= pixel_rgb;
			spill_energy_q    <= final_int;
			full_primary_q    <= full_spill_primary;
			spill_excess_q    <= vfb_spill_bloom_pkg::spill_excess(final_int[7:0],
			                                                       full_spill_primary);
			canonical_pipe[1] <= vfb_spill_bloom_pkg::display_pixel(spill_mask_q, spill_energy_q,
			                                                        full_primary_q, spill_excess_q);
			for (int i = 2; i < 5; i = i + 1)
				canonical_pipe[i] <= canonical_pipe[i-1];
		end
	end

	// Registered output stage.
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			CANONICAL_PIXEL <= 16'd0;
			VGA_HS          <=  1'b1;
			VGA_VS          <=  1'b1;
			VGA_HBLANK      <=  1'b1;
			VGA_VBLANK      <=  1'b1;
		end else if (ce_pix) begin
			VGA_HS     <= vga_hs_pre;
			VGA_VS     <= vga_vs_pre;
			VGA_HBLANK <= vga_hblank_pre;
			VGA_VBLANK <= vga_vblank_pre;

			CANONICAL_PIXEL <= (vga_hblank_pre || vga_vblank_pre) ? 16'd0 : canonical_pipe[4];
		end
	end

endmodule
