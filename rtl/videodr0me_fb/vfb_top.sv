// ============================================================================
// Tile-based sparse vector framebuffer and CRT effect pipeline.
// Written 2026 by Videodr0me
// ============================================================================

module vfb_top (
	input         clk_sys,
	input         clk_12,
	input         reset,
	input         source_reset,
	input         ddr_reset,
	input         video_timing_reset, // Resyncs presentation without clearing framebuffer state.

	// Vector input
	input  [10:0] X_VECTOR,
	input  [10:0] Y_VECTOR,
	input  [8:0]  Z_VECTOR,
	input  [2:0]  COLOR,
	input         IS_DOT,
	input         BEAM_ON,

	// Framebuffer DDRAM
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	// Compressed primary delay
	input  [15:0] SDRAM_DQ_IN,
	output [15:0] SDRAM_DQ_OUT,
	output        SDRAM_DQ_OE,
	output        SDRAM_CKE,
	output        SDRAM_nCS,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_nWE,
	output  [1:0] SDRAM_DQM,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,

	// Raster dimensions
	input [11:0]  RENDER_WIDTH,
	input [11:0]  RENDER_HEIGHT,

	// Video output
	output logic [7:0]  VGA_R,
	output logic [7:0]  VGA_G,
	output logic [7:0]  VGA_B,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  [10:0] h_cnt,
	input  [10:0] v_cnt,
	input         ce_pix,
	input         hsync,
	input         vsync,
	input         hblank,
	input         vblank,

	// Frame, buffer, and CRT controls
	input  [7:0]  FLASH_PARAM,
	input         OSD_120HZ,
	input         FRAME_DONE,
	input   [1:0] BUFFER_MODE,
	input   [2:0] DOT_MODE,
	output        FIFO_HIGH_WATER_LED,

	input         osd_full_spill_primary,
	input  [2:0]  osd_bloom_width,
	input  [2:0]  osd_bloom_curve,
	input  [2:0]  osd_halo_filter,
	input  [2:0]  osd_halo_curve,
	input  [2:0]  osd_halo_knee,
	input  [1:0]  osd_phosphor_mode,    // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  [1:0]  osd_inter_frame_phosphor_mode,
	input  [1:0]  osd_halo_spread,
	input         osd_color_space,
	input  [2:0]  osd_presentation_color,
	input  [1:0]  osd_slot_mask,
	input         osd_slot_mask_rows,
	input  [1:0]  halo_shape,
	input         halo_grid_8,
	input         full_bypass_active,
	output wire   raw_path_vblank,
	output wire   processed_path_vblank
);
	import vfb_layout_pkg::*;

	localparam TILE_SIZE      = VFB_TILE_SIZE;
	localparam CACHE_COUNT    = 4; // Four cache slots in this integration.
	localparam BUFFER_COUNT   = VFB_BUFFER_COUNT;
	localparam BUF_IDX_W      =  3;
	localparam TILEMAP_ADDR_W = 15;

	// Rasterizer and tile cache
	logic        pixel_valid;
	logic        pixel_ready;
	logic [15:0] pixel_tile_id;
	logic [5:0]  pixel_offset;
	logic [15:0] pixel_data;
	wire         rasterizer_fifo_high_water_led;


	// Readout and DDRAM arbiter
	wire        readout_ready;
	wire        readout_grant;
	wire [15:0] readout_tile_id;
	wire [63:0] readout_data;
	wire        readout_data_valid;
	wire        flush_done_arbiter;

	// End-of-frame timing
	wire        eof_token;
	wire        eof_token_popped;
	wire [15:0] eof_frame_tick_clks_popped;
	wire [3:0]  eof_frame_age_popped;
	wire [3:0]  eof_frame_age;

	// VBLANK display request
	wire        vbl_swap_req;
	wire        readout_frame_start;

	wire [BUF_IDX_W-1:0] buf_display;
	wire [BUF_IDX_W-1:0] buf_draw;
	wire                 arbiter_reset_busy;
	wire                 arbiter_idle;
	wire                 cache_reset_active;

	assign DDRAM_CLK = clk_sys;

	logic [2:0] osd_bloom_width_vid        = 3'd0;
	logic [1:0] osd_halo_spread_vid        = 2'd0;
	logic [2:0] osd_halo_knee_vid          = vfb_control_pkg::KNEE_16;
	logic       osd_color_space_vid        =   1'b0;
	logic [2:0] osd_presentation_color_vid =   3'd0;
	logic [1:0] osd_slot_mask_vid          =   2'd0;
	logic       osd_slot_mask_rows_vid     =   1'b0;
	logic       full_bypass_active_q       =   1'b1;
	logic [1:0] halo_shape_q               =   2'd3;
	logic       halo_grid_8_q              =   1'b0;
	logic [9:0] bloom_curve_gain           = 10'd64;
	logic [9:0] halo_curve_gain            = 10'd64;
	logic [7:0] halo_filter                =   8'd0;
	logic [1:0] osd_phosphor_mode_vid      =   2'd0;
	logic [1:0] inter_frame_mode_vid       =   2'd0;
	logic [2:0] dot_mode_vid               =   3'd0;
	logic [1:0] buffer_mode_vid            =   2'd0;
	logic       osd_120hz_vid              =   1'b0;

	always_ff @(posedge clk_sys) begin
		full_bypass_active_q <= full_bypass_active;
		halo_grid_8_q        <= halo_grid_8;
	end

	wire fb_reset_request = reset;
	// Preserve client payloads until the active DDR transaction has drained.
	// Keep the combinational boundary for scoped fanout duplication in the QSF.
	(* keep *) wire fb_client_reset = arbiter_reset_busy && arbiter_idle;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [1:0] ddr_reset_sync = 2'b11;
	always_ff @(posedge clk_sys) ddr_reset_sync <= {ddr_reset_sync[0], ddr_reset};

	logic filter_reset_q  = 1'b1;
	logic readout_reset_q = 1'b1;
	always_ff @(posedge clk_sys) begin
		filter_reset_q  <= fb_reset_request | video_timing_reset;
		readout_reset_q <= fb_client_reset | video_timing_reset;
	end

	// Measure frame timing in source clocks and store each frame's draw duration.
	wire [3:0]           draw_idx;
	wire [15:0]          active_frame_tick_clks;
	wire [3:0]           completed_frame_age;
	wire [3:0]           readout_draw_idx;
	wire [63:0]          readout_age_map;
	wire                 compose_req;
	wire                 compose_done;
	wire [BUF_IDX_W-1:0] compose_source_buf;
	wire [BUF_IDX_W-1:0] compose_target_buf;
	wire                 compose_has_source;
	wire                 compose_source_is_composed;
	wire                 raw_frame_dropped;
	wire [BUF_IDX_W-1:0] raw_frame_dropped_buf;
	wire [3:0]           compose_draw_idx;
	wire [63:0]          compose_age_map;
	wire [3:0]           compose_frame_age;

	vfb_phosphor_timing #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) phosphor_timing_inst (
		.clk_source(clk_12),
		.clk_sys(clk_sys),
		.reset_source(source_reset),
		.reset_sys(fb_client_reset),
		.frame_done(FRAME_DONE),

		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.eof_frame_age_popped(eof_frame_age_popped),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.vbl_swap_req(vbl_swap_req),
		.presentation_120hz(osd_120hz_vid),
		.BUFFER_MODE(buffer_mode_vid),
		.compose_req(compose_req),
		.compose_buf(compose_target_buf),
		.raw_frame_dropped(raw_frame_dropped),
		.raw_frame_dropped_buf(raw_frame_dropped_buf),
		.compose_draw_idx(compose_draw_idx),
		.compose_age_map(compose_age_map),
		.compose_frame_age(compose_frame_age),

		.draw_idx(draw_idx),
		.active_frame_tick_clks(active_frame_tick_clks),
		.completed_frame_age(completed_frame_age),
		.readout_draw_idx(readout_draw_idx),
		.readout_age_map(readout_age_map)
	);

	vfb_rasterizer #(
		.TILE_SIZE(TILE_SIZE)
	) rasterizer_inst (
		.clk_sys(clk_sys),
		.clk_12(clk_12),
		.reset(fb_client_reset),

		// Vector input
		.X_VECTOR(X_VECTOR),
		.Y_VECTOR(Y_VECTOR),
		.Z_VECTOR(Z_VECTOR),
		.COLOR(COLOR),
		.IS_DOT(IS_DOT),
		.BEAM_ON(BEAM_ON),
		.FRAME_DONE(FRAME_DONE),
		.DOT_MODE(dot_mode_vid),
		.FB_WIDTH(RENDER_WIDTH),
		.FB_HEIGHT(RENDER_HEIGHT),

		// Tile cache output
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),
		.draw_idx(draw_idx),
		.frame_tick_clks(active_frame_tick_clks),
		.completed_frame_age(completed_frame_age),


		.eof_token(eof_token),
		.eof_frame_age(eof_frame_age),
		.fifo_high_water_led(rasterizer_fifo_high_water_led),
		.fifo_empty()
	);

	// Internal connections
	wire        fill_ready, fill_grant;
	wire [28:0] fill_addr;
	wire [7:0]  fill_burstcnt;
	wire [63:0] fill_data;
	wire        fill_data_valid;

	wire        flush_ready, flush_grant, flush_done, flush_advance;
	wire [28:0] flush_addr;
	wire [7:0]  flush_burstcnt;
	wire [63:0] flush_din;
	wire [7:0]  flush_be;

	wire [14:0] display_tile_addr;
	wire        display_tile_dirty;

	wire                      flush_req;
	wire                      clear_req;
	wire [BUF_IDX_W-1:0]      clear_buf_idx;
	wire                      clear_done;
	wire                      draw_ready;
	wire [BUFFER_COUNT-1:0]   buf_draw_hot;
	wire                      display_valid;
	wire                      display_is_composed;
	wire [TILEMAP_ADDR_W-1:0] compose_tilemap_addr;
	wire [BUFFER_COUNT-1:0]   compose_tilemap_write_hot;
	wire                      compose_tilemap_write_din;
	wire [BUFFER_COUNT-1:0]   compose_tilemap_dout;

	wire [28:0] display_buf_base = vfb_buffer_base(buf_display);

	vfb_buffer_controller #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) buffer_controller_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.BUFFER_MODE(buffer_mode_vid),
		.inter_frame_mode(inter_frame_mode_vid),

		.eof_token_popped(eof_token_popped),
		.vbl_swap_req(vbl_swap_req),

		.flush_req(flush_req),
		.flush_done(flush_done),

		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.compose_req(compose_req),
		.compose_source_buf(compose_source_buf),
		.compose_target_buf(compose_target_buf),
		.compose_has_source(compose_has_source),
		.compose_source_is_composed(compose_source_is_composed),
		.compose_done(compose_done),

		.buf_draw(buf_draw),
		.buf_display_out(buf_display),
		.display_valid(display_valid),
		.display_is_composed(display_is_composed),

		.has_draw_buf(),
		.draw_ready(draw_ready),
		.buf_draw_hot(buf_draw_hot),
		.raw_frame_dropped(raw_frame_dropped),
		.raw_frame_dropped_buf(raw_frame_dropped_buf),
		.readout_frame_start(readout_frame_start)
	);

	assign FIFO_HIGH_WATER_LED = rasterizer_fifo_high_water_led;

	vfb_tile_cache_manager #(
		.TILE_SIZE(TILE_SIZE),
		.CACHE_COUNT(CACHE_COUNT),
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) cache_manager_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),
		.reset_active(cache_reset_active),

		.FB_HEIGHT(RENDER_HEIGHT),

		// Rasterizer
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),

		.eof_token(eof_token),
		.eof_frame_age(eof_frame_age),

		// Buffer controller
		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.eof_frame_age_popped(eof_frame_age_popped),
		.flush_req(flush_req),
		.flush_done(flush_done),
		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.display_valid(display_valid),
		.draw_ready(draw_ready),
		.buf_draw_hot(buf_draw_hot),

		// DDRAM arbiter
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done_in(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),

		.display_tile_addr(display_tile_addr),
		.display_tile_dirty(display_tile_dirty),
		.compose_tilemap_addr(compose_tilemap_addr),
		.compose_tilemap_write_hot(compose_tilemap_write_hot),
		.compose_tilemap_write_din(compose_tilemap_write_din),
		.compose_tilemap_dout(compose_tilemap_dout)
	);

	wire [28:0] readout_addr = display_buf_base + ({13'd0, readout_tile_id} << 4);
	wire [8:0]  readout_burstcnt;

	wire        compose_read_ready;
	wire        compose_read_grant;
	wire [28:0] compose_read_addr;
	wire [7:0]  compose_read_burstcnt;
	wire [63:0] compose_read_data;
	wire        compose_read_data_valid;
	wire        compose_write_ready;
	wire        compose_write_grant;
	wire        compose_write_done;
	wire [28:0] compose_write_addr;
	wire [7:0]  compose_write_burstcnt;
	wire [63:0] compose_write_data;
	wire [7:0]  compose_write_be;
	wire        compose_write_advance;

	vfb_phosphor_compositor #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W),
		.TILEMAP_ADDR_W(TILEMAP_ADDR_W)
	) phosphor_compositor_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),
		.render_width(RENDER_WIDTH),
		.render_height(RENDER_HEIGHT),
		.intra_frame_mode(osd_phosphor_mode_vid),
		.inter_frame_mode(inter_frame_mode_vid),
		.compose_req(compose_req),
		.compose_source_buf(compose_source_buf),
		.compose_target_buf(compose_target_buf),
		.compose_has_source(compose_has_source),
		.compose_source_is_composed(compose_source_is_composed),
		.compose_done(compose_done),
		.raw_reference_draw_idx(compose_draw_idx),
		.raw_age_map(compose_age_map),
		.raw_frame_age(compose_frame_age),
		.tilemap_addr(compose_tilemap_addr),
		.tilemap_write_hot(compose_tilemap_write_hot),
		.tilemap_write_din(compose_tilemap_write_din),
		.tilemap_dout(compose_tilemap_dout),
		.read_ready(compose_read_ready),
		.read_grant(compose_read_grant),
		.read_addr(compose_read_addr),
		.read_burstcnt(compose_read_burstcnt),
		.read_data(compose_read_data),
		.read_data_valid(compose_read_data_valid),
		.write_ready(compose_write_ready),
		.write_grant(compose_write_grant),
		.write_done(compose_write_done),
		.write_addr(compose_write_addr),
		.write_burstcnt(compose_write_burstcnt),
		.write_data(compose_write_data),
		.write_be(compose_write_be),
		.write_advance(compose_write_advance)
	);

	vfb_ddr_arbiter ddr_arbiter_inst (
		.clk_sys(clk_sys),
		.rst_sys(fb_reset_request || ddr_reset_sync[1]),
		.cache_reset_active(cache_reset_active),

		// DDRAM Avalon-MM
		.DDRAM_BUSY(DDRAM_BUSY),
		.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
		.DDRAM_ADDR(DDRAM_ADDR),
		.DDRAM_RD(DDRAM_RD),
		.DDRAM_WE(DDRAM_WE),
		.DDRAM_DIN(DDRAM_DIN),
		.DDRAM_BE(DDRAM_BE),
		.DDRAM_DOUT(DDRAM_DOUT),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY),

		// Readout
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_addr(readout_addr),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		// Fill
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		// Flush
		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),
		.compose_read_ready(compose_read_ready),
		.compose_read_grant(compose_read_grant),
		.compose_read_addr(compose_read_addr),
		.compose_read_burstcnt(compose_read_burstcnt),
		.compose_read_data(compose_read_data),
		.compose_read_data_valid(compose_read_data_valid),
		.compose_write_ready(compose_write_ready),
		.compose_write_grant(compose_write_grant),
		.compose_write_done(compose_write_done),
		.compose_write_addr(compose_write_addr),
		.compose_write_burstcnt(compose_write_burstcnt),
		.compose_write_data(compose_write_data),
		.compose_write_be(compose_write_be),
		.compose_write_advance(compose_write_advance),
		.arbiter_idle(arbiter_idle),
		.reset_busy(arbiter_reset_busy)
	);

	wire [7:0]  raw_vga_r;
	wire [7:0]  raw_vga_g;
	wire [7:0]  raw_vga_b;
	wire        raw_vga_hs;
	wire        raw_vga_vs;
	wire        raw_vga_hblank;
	wire        raw_vga_vblank;
	wire [15:0] raw_canonical_pixel;
	wire [23:0] raw_visible = vfb_spill_bloom_pkg::spill_visible_rgb(raw_canonical_pixel);
	wire        raw_blank   = raw_vga_hblank || raw_vga_vblank;
	wire [23:0] raw_rgb     = raw_blank ? 24'd0 :
	                          raw_canonical_pixel == 16'd0 ?
	                              {FLASH_PARAM, FLASH_PARAM, FLASH_PARAM} :
	                              raw_visible;
	assign {raw_vga_r, raw_vga_g, raw_vga_b} = raw_rgb;

	// Synchronize menu options.
	typedef struct packed {
		logic [1:0] halo_shape;
		logic [2:0] halo_knee;
		logic [2:0] halo_curve;
		logic       mode_120hz;
		logic [1:0] buffer_mode;
		logic [2:0] dot_mode;
		logic [1:0] inter_frame_decay;
		logic       slot_mask_rows;
		logic [1:0] slot_mask;
		logic [2:0] presentation_color;
		logic       color_space;
		logic [1:0] halo_spread;
		logic [1:0] intra_frame_decay;
		logic [2:0] halo_filter;
		logic [2:0] bloom_curve;
		logic [2:0] bloom_width;
		logic       reserved;
		logic       full_spill_primary;
	} osd_control_t;

	osd_control_t osd_control_in;
	always_comb begin
		osd_control_in.halo_shape         = halo_shape;
		osd_control_in.halo_knee          = osd_halo_knee;
		osd_control_in.halo_curve         = osd_halo_curve;
		osd_control_in.mode_120hz         = OSD_120HZ;
		osd_control_in.buffer_mode        = BUFFER_MODE;
		osd_control_in.dot_mode           = DOT_MODE;
		osd_control_in.inter_frame_decay  = osd_inter_frame_phosphor_mode;
		osd_control_in.slot_mask_rows     = osd_slot_mask_rows;
		osd_control_in.slot_mask          = osd_slot_mask;
		osd_control_in.presentation_color = osd_presentation_color;
		osd_control_in.color_space        = osd_color_space;
		osd_control_in.halo_spread        = osd_halo_spread;
		osd_control_in.intra_frame_decay  = osd_phosphor_mode;
		osd_control_in.halo_filter        = osd_halo_filter;
		osd_control_in.bloom_curve        = osd_bloom_curve;
		osd_control_in.bloom_width        = osd_bloom_width;
		osd_control_in.reserved           = 1'b0;
		osd_control_in.full_spill_primary = osd_full_spill_primary;
	end

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	osd_control_t osd_control_meta   = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	osd_control_t osd_control_sync   = '0;
	osd_control_t osd_control_sync_d = '0;
	osd_control_t osd_control_stable = '0;

	function automatic [9:0] decode_curve_gain(
		input logic [2:0] sel
	);
		begin
			decode_curve_gain =
				(sel == 3'd0) ? 10'd64  :  // Minimal
				(sel == 3'd1) ? 10'd96  :  // Min+
				(sel == 3'd2) ? 10'd128 :  // Mild
				(sel == 3'd3) ? 10'd192 :  // Mild+
				(sel == 3'd4) ? 10'd256 :  // Moderate
				(sel == 3'd5) ? 10'd320 :  // Mod+
				(sel == 3'd6) ? 10'd384 :  // Strong-
				                  10'd512 ; // Strong
		end
	endfunction

	function automatic [7:0] decode_halo_filter(
		input logic [2:0] sel
	);
		begin
			decode_halo_filter =
				(sel == 3'd0) ? 8'd0  :  // Off
				(sel == 3'd1) ? 8'd8  :  // 0.25x
				(sel == 3'd2) ? 8'd11 :  // 0.33x
				(sel == 3'd3) ? 8'd16 :  // 0.5x
				(sel == 3'd4) ? 8'd24 :  // 0.75x
				(sel == 3'd5) ? 8'd32 :  // 1.0x
				(sel == 3'd6) ? 8'd40 :  // 1.25x
				                  8'd48 ; // 1.5x
		end
	endfunction

	always_ff @(posedge clk_sys) begin
		osd_control_meta   <= osd_control_in;
		osd_control_sync   <= osd_control_meta;
		osd_control_sync_d <= osd_control_sync;
		if (osd_control_sync == osd_control_sync_d) osd_control_stable <= osd_control_sync;

		osd_bloom_width_vid        <= osd_control_stable.bloom_width;
		bloom_curve_gain           <= decode_curve_gain(osd_control_stable.bloom_curve);
		halo_filter                <= decode_halo_filter(osd_control_stable.halo_filter);
		osd_phosphor_mode_vid      <= osd_control_stable.intra_frame_decay;
		osd_halo_spread_vid        <= osd_control_stable.halo_spread;
		osd_color_space_vid        <= osd_control_stable.color_space;
		osd_presentation_color_vid <= osd_control_stable.presentation_color;
		osd_slot_mask_vid          <= osd_control_stable.slot_mask;
		osd_slot_mask_rows_vid     <= osd_control_stable.slot_mask_rows;
		inter_frame_mode_vid       <= osd_control_stable.inter_frame_decay;
		dot_mode_vid               <= osd_control_stable.dot_mode;
		buffer_mode_vid            <= osd_control_stable.buffer_mode;
		osd_120hz_vid              <= osd_control_stable.mode_120hz;
		halo_curve_gain            <= decode_curve_gain(osd_control_stable.halo_curve);
		osd_halo_knee_vid          <= osd_control_stable.halo_knee;
		halo_shape_q               <= osd_control_stable.halo_shape;
	end

	vfb_readout #(
		.TILE_SIZE(TILE_SIZE)
	) readout_inst (
		.clk_sys(clk_sys),
		.reset(readout_reset_q),

		// DDRAM arbiter interface
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_tile_id(readout_tile_id),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		.vbl_swap_req(vbl_swap_req),
		.frame_start_req(readout_frame_start),

		// Readout output
		.CANONICAL_PIXEL(raw_canonical_pixel),
		.VGA_HS(raw_vga_hs),
		.VGA_VS(raw_vga_vs),
		.VGA_HBLANK(raw_vga_hblank),
		.VGA_VBLANK(raw_vga_vblank),

		.display_tile_addr(display_tile_addr),
		.display_tile_dirty(display_tile_dirty),

		.h_cnt(h_cnt),
		.v_cnt(v_cnt),
		.ce_pix(ce_pix),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),

		.RENDER_WIDTH(RENDER_WIDTH),
		.RENDER_HEIGHT(RENDER_HEIGHT),
		.draw_idx(readout_draw_idx),
		.phosphor_age_map(readout_age_map),
		.osd_phosphor_mode(osd_phosphor_mode_vid),
		.full_spill_primary(osd_control_stable.full_spill_primary),
		.display_is_composed(display_is_composed)
	);

	wire   [7:0] filtered_vga_r;
	wire   [7:0] filtered_vga_g;
	wire   [7:0] filtered_vga_b;
	wire         filtered_vga_hs;
	wire         filtered_vga_vs;
	wire         filtered_vga_hblank;
	wire         filtered_vga_vblank;
	assign       raw_path_vblank       = raw_vga_vblank;
	assign       processed_path_vblank = filtered_vga_vblank;

	vfb_halo_pipeline filter_inst (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.reset(filter_reset_q),

		.osd_bloom_width(osd_bloom_width_vid),
		.bloom_curve_gain(bloom_curve_gain),
		.halo_curve_gain(halo_curve_gain),
		.halo_filter(halo_filter),
		.halo_spread_mode(osd_halo_spread_vid),
		.halo_knee_mode(osd_halo_knee_vid),
		.halo_shape(halo_shape_q),
		.halo_grid_8(halo_grid_8_q),
		.active_height(RENDER_HEIGHT),
		.color_space_wg6100_709(osd_color_space_vid),
		.presentation_color(osd_presentation_color_vid),
		.slot_mask_mode(osd_slot_mask_vid),
		.slot_mask_rows(osd_slot_mask_rows_vid),

		.CANONICAL_IN(raw_canonical_pixel),
		.VGA_HS_IN(raw_vga_hs),
		.VGA_VS_IN(raw_vga_vs),
		.VGA_HBLANK_IN(raw_vga_hblank),
		.VGA_VBLANK_IN(raw_vga_vblank),

		.VGA_R_OUT(filtered_vga_r),
		.VGA_G_OUT(filtered_vga_g),
		.VGA_B_OUT(filtered_vga_b),
		.VGA_HS_OUT(filtered_vga_hs),
		.VGA_VS_OUT(filtered_vga_vs),
		.VGA_HBLANK_OUT(filtered_vga_hblank),
		.VGA_VBLANK_OUT(filtered_vga_vblank),

		.sdram_data_in(SDRAM_DQ_IN),
		.sdram_data_out(SDRAM_DQ_OUT),
		.sdram_data_oe(SDRAM_DQ_OE),
		.sdram_cke(SDRAM_CKE),
		.sdram_cs(SDRAM_nCS),
		.sdram_ras(SDRAM_nRAS),
		.sdram_cas(SDRAM_nCAS),
		.sdram_we(SDRAM_nWE),
		.sdram_dqm(SDRAM_DQM),
		.sdram_addr(SDRAM_A),
		.sdram_ba(SDRAM_BA),
		.sdram_overflow(),
		.sdram_underflow(),
		.sdram_init_done()
	);

	// Full bypass selects the unfiltered readout.
	always_ff @(posedge clk_sys) begin
		if (fb_client_reset | video_timing_reset) begin
			VGA_R      <= 8'd0;
			VGA_G      <= 8'd0;
			VGA_B      <= 8'd0;
			VGA_HS     <= 1'b1;
			VGA_VS     <= 1'b1;
			VGA_HBLANK <= 1'b1;
			VGA_VBLANK <= 1'b1;
		end else if (ce_pix) begin
			if (full_bypass_active_q) begin
				VGA_R      <= raw_vga_r;
				VGA_G      <= raw_vga_g;
				VGA_B      <= raw_vga_b;
				VGA_HS     <= raw_vga_hs;
				VGA_VS     <= raw_vga_vs;
				VGA_HBLANK <= raw_vga_hblank;
				VGA_VBLANK <= raw_vga_vblank;
			end else begin
				VGA_R      <= filtered_vga_r;
				VGA_G      <= filtered_vga_g;
				VGA_B      <= filtered_vga_b;
				VGA_HS     <= filtered_vga_hs;
				VGA_VS     <= filtered_vga_vs;
				VGA_HBLANK <= filtered_vga_hblank;
				VGA_VBLANK <= filtered_vga_vblank;
			end
		end
	end

endmodule
