//============================================================================
//  Space Duel vector video presentation
//
//  Written 2026 by Videodr0me
//
//  Maps AVG coordinates into the selected raster mode and connects
//  the vector stream to the sparse framebuffer and CRT effect pipeline.
//============================================================================

module spaceduel_video
#(
	parameter logic [24:0] HEIGHT_STABLE_CYCLES = 25'd25_000_000
)
(
	input  logic        clk_12,
	input  logic        clk_50,
	input  logic        clk_render,
	input  logic        reset,
	input  logic        ddr_reset,
	input  logic        init_reset,

	input  logic        direct_video,
	input  logic        direct_video_31khz,
	input  logic [11:0] hdmi_height,
	input  logic        mode_120hz,
	input  logic        authentic_timing,
	input  logic        crt_15khz_480i,
	input  logic  [1:0] test_video_format,
	input  logic  [2:0] crt_vertical_position,
	input  logic  [2:0] crt_horizontal_position,
	input  logic  [1:0] aspect_ratio,
	input  logic  [1:0] buffer_mode,
	input  logic  [2:0] geometry_orientation,
	input  logic        geometry_zoom_wide,

	input vfb_control_pkg::vfb_profile_settings_t profile_settings,
	input logic                                   effects_bypass,
	input logic [1:0]                             velocity_comp,
	input logic [1:0]                             halo_shape,

	input logic signed [14:0] avg_x,
	input logic signed [14:0] avg_y,
	input logic signed [22:0] avg_step_x,
	input logic signed [22:0] avg_step_y,
	input logic        [7:0]  avg_z,
	input logic        [2:0]  avg_rgb,
	input logic               avg_is_dot,
	input logic               avg_halted,
	input logic               hardware_flip_x,
	input logic               hardware_flip_y,
	input logic               frame_done,

	output logic [12:0] video_arx,
	output logic [12:0] video_ary,
	output logic        ce_pixel,
	output logic        hblank,
	output logic        vblank,
	output logic  [7:0] video_r,
	output logic  [7:0] video_g,
	output logic  [7:0] video_b,
	output logic        hsync,
	output logic        vsync,
	output logic        field,
	output logic        mode_supports_120hz,
	output wire   [1:0] profile_resolution,
	output logic        mode_supports_test_format,
	output logic        mode_is_15khz,
	output logic        fifo_high_water,
	output logic        video_mode_toggle,
	output logic        video_freeze,
	output logic        mode_restart,

	output logic        ddram_clk,
	input  logic        ddram_busy,
	output logic  [7:0] ddram_burst_count,
	output logic [28:0] ddram_address,
	input  logic [63:0] ddram_data_out,
	input  logic        ddram_data_ready,
	output logic        ddram_read,
	output logic [63:0] ddram_data_in,
	output logic  [7:0] ddram_byte_enable,
	output logic        ddram_write,

	input  logic [15:0] sdram_data_in,
	output logic [15:0] sdram_data_out,
	output logic        sdram_data_oe,
	output logic        sdram_cke,
	output logic        sdram_ncs,
	output logic        sdram_nras,
	output logic        sdram_ncas,
	output logic        sdram_nwe,
	output logic  [1:0] sdram_dqm,
	output logic [12:0] sdram_address,
	output logic  [1:0] sdram_bank
);

	// Qualify the source height once. MiSTer Main may later report a PAL/NTSC override;
	// that feedback must not select a different core timing family.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic        direct_video_meta = 1'b0, direct_video_sync = 1'b0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic        direct_31khz_meta = 1'b0, direct_31khz_sync = 1'b0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [11:0] requested_height_meta = 12'd0, requested_height_sync = 12'd0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic        init_reset_50_meta = 1'b1, init_reset_50 = 1'b1;
	logic [11:0] height_candidate = 12'd0, stable_height = 12'd0;
	logic [24:0] height_timer = 25'd0;
	logic        height_direct = 1'b0, height_31khz = 1'b0;

	always_ff @(posedge clk_50) begin
		init_reset_50_meta    <= init_reset;
		init_reset_50         <= init_reset_50_meta;
		direct_video_meta     <= direct_video;
		direct_video_sync     <= direct_video_meta;
		direct_31khz_meta     <= direct_video_31khz;
		direct_31khz_sync     <= direct_31khz_meta;
		requested_height_meta <= direct_video_sync ? (direct_31khz_sync ? 12'd480 : 12'd240)
		                                           : hdmi_height;
		requested_height_sync <= requested_height_meta;
		height_direct         <= direct_video_sync;
		height_31khz          <= direct_31khz_sync;

		if (init_reset_50 || height_direct != direct_video_sync ||
		    (direct_video_sync && height_31khz != direct_31khz_sync)) begin
			height_candidate <= 12'd0;
			stable_height    <= 12'd0;
			height_timer     <= 25'd0;
		end else if (stable_height == 0) begin
			if (requested_height_sync <= 12'd200 || requested_height_sync != height_candidate) begin
				height_candidate <= requested_height_sync;
				height_timer     <= 25'd0;
			end else if (height_timer < HEIGHT_STABLE_CYCLES) begin
				height_timer <= height_timer + 1'd1;
			end else begin
				stable_height <= height_candidate;
				height_timer  <= 25'd0;
			end
		end
	end

	typedef struct packed {
		logic [11:0] height;
		logic        direct_video;
		logic        mode_120hz;
		logic        authentic;
		logic        interlaced;
		logic [1:0]  test_format;
		logic [2:0]  vertical_position;
		logic [2:0]  horizontal_position;
		logic        bypass;
		logic        halo_grid;
	} video_control_t;
	video_control_t control_in;
	assign          control_in = {stable_height, height_direct, mode_120hz,
	                              authentic_timing, crt_15khz_480i, test_video_format,
	                              crt_vertical_position, crt_horizontal_position,
	                              effects_bypass, profile_settings.halo_grid};
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	video_control_t control_meta = '0, control_sync = '0;
	video_control_t control_sync_d = '0, control_stable = '0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic           init_reset_render_meta = 1'b1, init_reset_render = 1'b1;
	always_ff @(posedge clk_render) begin
		init_reset_render_meta <= init_reset;
		init_reset_render      <= init_reset_render_meta;
		control_meta           <= control_in;
		control_sync           <= control_meta;
		control_sync_d         <= control_sync;
		if (control_sync == control_sync_d) control_stable <= control_sync;
	end

	function automatic logic signed [4:0] decode_crt_vertical_position(
		input logic [2:0] selection
	);
		begin
			case (selection)
				3'd1:    decode_crt_vertical_position =  5'sd4;
				3'd2:    decode_crt_vertical_position =  5'sd8;
				3'd3:    decode_crt_vertical_position = 5'sd12;
				3'd4:    decode_crt_vertical_position = -5'sd4;
				3'd5:    decode_crt_vertical_position = -5'sd8;
				3'd6:    decode_crt_vertical_position = -5'sd10;
				default: decode_crt_vertical_position = 5'sd0;
			endcase
		end
	endfunction

	function automatic logic signed [4:0] decode_crt_vertical_position_240p(
		input logic [2:0] selection
	);
		begin
			case (selection)
				3'd1:    decode_crt_vertical_position_240p = 5'sd2;
				3'd2:    decode_crt_vertical_position_240p = 5'sd4;
				3'd3:    decode_crt_vertical_position_240p = 5'sd6;
				3'd4:    decode_crt_vertical_position_240p = -5'sd2;
				3'd5:    decode_crt_vertical_position_240p = -5'sd4;
				3'd6:    decode_crt_vertical_position_240p = -5'sd6;
				default: decode_crt_vertical_position_240p = 5'sd0;
			endcase
		end
	endfunction

	typedef struct packed {
		logic [11:0] fb_width;
		logic [11:0] fb_height;
		logic [11:0] x_center;
		logic [11:0] y_center;
		logic [12:0] optimized_arx;
		logic [12:0] optimized_ary;
		// h_total and v_total are inclusive terminal counts (period - 1);
		// hs_end and vs_end are exclusive upper bounds.
		logic        [11:0] h_total;
		logic        [11:0] v_total;
		logic        [11:0] hs_start;
		logic        [11:0] hs_end;
		logic        [11:0] vs_start;
		logic        [11:0] vs_end;
		logic        [19:0] fractional_numerator;
		logic        [19:0] fractional_denominator;
		logic               is_1080p;
		logic               is_480p;
		logic               is_240p;
		logic               is_120hz;
		logic               is_authentic;
		logic               is_interlaced;
		logic signed [4:0]  crt_vertical_offset;
		logic signed [4:0]  crt_horizontal_offset;
	} video_mode_t;

	function automatic video_mode_t decode_video_mode(
		input logic [11:0] height,
		input logic        mode_120hz,
		input logic        authentic,
		input logic        interlaced,
		input logic  [2:0] crt_position,
		input logic  [2:0] horizontal_position
	);
		video_mode_t        mode;
		logic signed [4:0]  vertical_offset, horizontal_offset;
		logic signed [12:0] shifted_vs_start;
		logic signed [12:0] shifted_vs_end;
		begin
			mode            = '0;
			vertical_offset = (height < 12'd480) ? decode_crt_vertical_position_240p(crt_position)
			                                     : decode_crt_vertical_position(crt_position);
			case (horizontal_position)
				3'd1:    horizontal_offset =  5'sd4;
				3'd2:    horizontal_offset =  5'sd8;
				3'd3:    horizontal_offset = 5'sd12;
				3'd4:    horizontal_offset = -5'sd4;
				3'd5:    horizontal_offset = -5'sd8;
				3'd6:    horizontal_offset = -5'sd12;
				default: horizontal_offset = 5'sd0;
			endcase
			mode.is_authentic = authentic;
			if ((height >= 12'd1080) && (height < 12'd1400)) begin
				mode.fb_width      = 12'd1472;
				mode.fb_height     = 12'd1080;
				mode.x_center      =  12'd736;
				mode.y_center      =  12'd540;
				mode.optimized_arx = 13'h1000 | 13'd1472;
				mode.optimized_ary = 13'h1000 | 13'd1080;
				mode.h_total       = authentic ? 12'd1846 : 12'd1903;
				mode.v_total       = authentic ? 12'd1130 : 12'd1124;
				mode.hs_start      = 12'd1600;
				mode.hs_end        = 12'd1688;
				mode.vs_start      = 12'd1088;
				mode.vs_end        = 12'd1093;
				mode.is_1080p      =     1'b1;
			end else if (height < 12'd480) begin
				mode.fb_width            = 12'd720;
				mode.fb_height           = 12'd240;
				mode.x_center            = 12'd360;
				mode.y_center            = 12'd120;
				mode.optimized_arx       = 13'h1000 | 13'd720;
				mode.optimized_ary       = 13'h1000 | 13'd240;
				mode.h_total             = authentic ? 12'd873 : 12'd883;
				mode.v_total             = authentic ? 12'd259 : 12'd263;
				mode.hs_start            = authentic ? 12'd740 : 12'd755;
				mode.hs_end              = authentic ? 12'd806 : 12'd821;
				shifted_vs_start         = 13'sd246 - vertical_offset;
				shifted_vs_end           = 13'sd249 - vertical_offset;
				mode.vs_start            = shifted_vs_start[11:0];
				mode.vs_end              = shifted_vs_end[11:0];
				mode.is_240p             = 1'b1;
				mode.crt_vertical_offset = vertical_offset;
			end else if (height < 12'd720) begin
				mode.fb_width            = 12'd720;
				mode.fb_height           = 12'd480;
				mode.x_center            = 12'd360;
				mode.y_center            = 12'd240;
				mode.optimized_arx       = 13'h1000 | 13'd720;
				mode.optimized_ary       = 13'h1000 | 13'd480;
				mode.h_total             = authentic ? 12'd873 : 12'd883;
				mode.v_total             = authentic ? (interlaced ? 12'd520 : 12'd519) : 12'd528;
				mode.hs_start            = authentic ? 12'd740 : 12'd755;
				mode.hs_end              = authentic ? 12'd806 : 12'd821;
				shifted_vs_start         = 13'sd493 - vertical_offset;
				shifted_vs_end           = 13'sd499 - vertical_offset;
				mode.vs_start            = shifted_vs_start[11:0];
				mode.vs_end              = shifted_vs_end[11:0];
				mode.is_480p             = 1'b1;
				mode.is_interlaced       = interlaced;
				mode.crt_vertical_offset = vertical_offset;
			end else begin
				mode.fb_width      = 12'd980;
				mode.fb_height     = 12'd720;
				mode.x_center      = 12'd490;
				mode.y_center      = 12'd360;
				mode.optimized_arx = (height >= 12'd1440) ? (13'h1000 | 13'd1960)
				                                          : (13'h1000 | 13'd980);
				mode.optimized_ary = (height >= 12'd1440) ? (13'h1000 | 13'd1440)
				                                          : (13'h1000 | 13'd720);
				mode.h_total       = (mode_120hz || !authentic) ? 12'd1427 : 12'd1359;
				mode.v_total       = (mode_120hz || !authentic) ? 12'd749 : 12'd767;
				mode.hs_start      = 12'd1108;
				mode.hs_end        = 12'd1196;
				mode.vs_start      =  12'd728;
				mode.vs_end        =  12'd733;
				mode.is_120hz      = mode_120hz;
			end
			if (height < 12'd720) begin
				mode.hs_start              = 12'($signed({1'b0, mode.hs_start}) -
				                                 horizontal_offset);
				mode.hs_end                = 12'($signed({1'b0, mode.hs_end}) - horizontal_offset);
				mode.crt_horizontal_offset = horizontal_offset;
			end
			// Commit the pixel-enable ratio with the mode geometry.
			// For 240p, 480p and the 480i source raster, reduce
			// (h_total + 1) * (v_total + 1) / render clocks per source raster.
			// Authentic uses 2088960 clocks per raster and compatible uses 2144140.
			// In authentic 480p, (874 * 520) / 2088960 reduces to 5681 / 26112.
			if (mode.is_480p) begin
				mode.fractional_numerator   = mode.is_authentic ?
				                              (mode.is_interlaced ? 20'd227677 : 20'd5681) :
				                              20'd116909;
				mode.fractional_denominator = mode.is_authentic ?
				                              (mode.is_interlaced ? 20'd1044480 : 20'd26112) :
				                              20'd536035;
			end else begin
				mode.fractional_numerator   = mode.is_authentic ? 20'd5681 : 20'd58344;
				mode.fractional_denominator = mode.is_authentic ? 20'd52224 : 20'd536035;
			end
			decode_video_mode = mode;
		end
	endfunction

	localparam video_mode_t DEFAULT_VIDEO_MODE = decode_video_mode(12'd480, 1'b0, 1'b0,
	                                                               1'b0, 3'd0, 3'd0);

	video_mode_t mode_q = DEFAULT_VIDEO_MODE;

	wire        [11:0] fb_width            = mode_q.fb_width;
	wire        [11:0] fb_height           = mode_q.fb_height;
	wire        [11:0] x_center            = mode_q.x_center;
	wire        [11:0] y_center            = mode_q.y_center;
	wire        [12:0] optimized_arx       = mode_q.optimized_arx;
	wire        [12:0] optimized_ary       = mode_q.optimized_ary;
	wire        [11:0] h_total             = mode_q.h_total;
	wire        [11:0] v_total             = mode_q.v_total;
	wire        [11:0] hs_start            = mode_q.hs_start;
	wire        [11:0] hs_end              = mode_q.hs_end;
	wire        [11:0] vs_start            = mode_q.vs_start;
	wire        [11:0] vs_end              = mode_q.vs_end;
	wire               is_1080p            = mode_q.is_1080p;
	wire               is_480p             = mode_q.is_480p;
	wire               is_240p             = mode_q.is_240p;
	wire               is_120hz            = mode_q.is_120hz;
	wire               is_authentic        = mode_q.is_authentic;
	wire               is_interlaced       = mode_q.is_interlaced;
	wire signed [4:0]  crt_vertical_offset = mode_q.crt_vertical_offset;

	assign profile_resolution = fb_height >= 12'd1000 ? 2'd3 :
	                            fb_height >= 12'd700 ? 2'd2 :
	                                fb_height >= 12'd400 ? 2'd1 : 2'd0;

	video_mode_t requested_mode = DEFAULT_VIDEO_MODE;
	video_mode_t pending_mode_q = DEFAULT_VIDEO_MODE;
	typedef struct packed {
		logic [11:0] height;
		logic        direct_video;
		logic [2:0]  horizontal_position;
		logic [2:0]  crt_position;
		logic        mode_120hz;
		logic        authentic;
		logic        is_15khz;
		logic        interlaced;
		logic        halo_grid;
	} video_key_t;
	logic        request_valid  = 1'b0;
	logic        request_bypass = 1'b1;
	video_key_t  request_key = '0, key_active_q = '0, key_pending_q = '0;

	wire        height_supports_120hz       = !control_stable.direct_video &&
	                                          control_stable.height >= 12'd720 &&
	                                          control_stable.height <= 12'd768;
	wire        request_120hz               = control_stable.mode_120hz && height_supports_120hz;
	wire        request_authentic           = control_stable.authentic && !request_120hz;
	wire        test_format_active          = !control_stable.direct_video &&
	                                          control_stable.height >= 12'd480 &&
	                                          control_stable.height < 12'd720;
	wire        test_format_480i            = test_format_active &&
	                                          control_stable.test_format == 2'd1;
	wire        test_format_240p            = test_format_active &&
	                                          control_stable.test_format == 2'd2;
	wire        request_15khz               = test_format_active ?
	                                          (test_format_480i || test_format_240p) :
	                                          control_stable.height < 12'd480;
	wire        request_480i                = test_format_active ?
	                                          test_format_480i :
	                                          control_stable.interlaced && request_15khz;
	wire [11:0] request_height              = test_format_240p ? 12'd240 :
	                                          request_480i ? 12'd480 : control_stable.height;
	wire [2:0]  request_crt_position        = request_height < 12'd720 ?
	                                          control_stable.vertical_position :
	                                          3'd0;
	wire [2:0]  request_horizontal_position = request_height < 12'd720 ?
	                                          control_stable.horizontal_position :
	                                          3'd0;
	wire        request_inputs_stable       = control_stable.height > 12'd200 &&
	                                          control_stable == control_sync &&
	                                          control_sync == control_sync_d;

	always_ff @(posedge clk_render) begin
		if (init_reset_render) begin
			requested_mode <= DEFAULT_VIDEO_MODE;
			request_valid  <= 1'b0;
			request_bypass <= 1'b1;
			request_key    <=   '0;
		end else begin
			requested_mode                  <= decode_video_mode(request_height, request_120hz,
			                                                     request_authentic, request_480i,
			                                                     request_crt_position,
			                                                     request_horizontal_position);
			request_valid                   <= request_inputs_stable;
			request_bypass                  <= control_stable.bypass;
			request_key.height              <= request_height;
			request_key.direct_video        <= control_stable.direct_video;
			request_key.horizontal_position <= request_horizontal_position;
			request_key.crt_position        <= request_crt_position;
			request_key.mode_120hz          <= request_120hz;
			request_key.authentic           <= request_authentic;
			request_key.is_15khz            <= request_15khz;
			request_key.interlaced          <= request_480i;
			request_key.halo_grid           <= control_stable.halo_grid;
		end
	end

	// Prevent partial frames during video-mode and effects-bypass changes.
	typedef enum logic [2:0] {
		MODE_WAIT_START,
		MODE_START_TIMING,
		MODE_START_HOLD,
		MODE_RUN,
		MODE_WAIT_ACTIVE_VBLANK,
		MODE_WAIT_TIMING_WRAP,
		MODE_WAIT_TARGET_VBLANK,
		MODE_HOLD_TARGET_FRAME
	} mode_state_t;

	mode_state_t mode_state           = MODE_WAIT_START;
	logic        mode_ready           = 1'b0;
	logic        video_mode_toggle_q  = 1'b0;
	logic        video_freeze_q       = 1'b1;
	logic        active_bypass_q      = 1'b1;
	logic        pending_bypass_q     = 1'b1;
	logic        transition_timing_q  = 1'b0;
	logic        transition_restart_q = 1'b0;
	logic        mode_restart_q       = 1'b0;
	logic        raw_path_vblank;
	logic        processed_path_vblank;
	logic        raw_path_vblank_q       = 1'b1;
	logic        processed_path_vblank_q = 1'b1;
	logic        output_vblank_q         = 1'b1;
	logic        output_vblank_entry_q   = 1'b0;
	logic        frame_wrap;
	logic        mode_commit;
	wire         raw_path_vblank_entry           = raw_path_vblank && !raw_path_vblank_q;
	wire         processed_path_vblank_entry     = processed_path_vblank &&
	                                               !processed_path_vblank_q;
	wire         progressive_active_vblank_entry = active_bypass_q ? raw_path_vblank_entry
	                                                               : processed_path_vblank_entry;
	wire         progressive_target_vblank_entry = pending_bypass_q ? raw_path_vblank_entry
	                                                                : processed_path_vblank_entry;
	wire         active_path_vblank_entry        = key_active_q.interlaced ?
	                                               output_vblank_entry_q :
	                                               progressive_active_vblank_entry;
	wire         target_path_vblank_entry        = key_pending_q.interlaced ?
	                                               output_vblank_entry_q :
	                                               progressive_target_vblank_entry;
	wire         request_changed                 = (request_key != key_active_q) ||
	                                               (request_bypass != active_bypass_q);
	wire         profile_path_commit             = (mode_state == MODE_WAIT_TARGET_VBLANK) &&
	                                               !transition_restart_q &&
	                                               target_path_vblank_entry &&
	                                               (pending_bypass_q != active_bypass_q);

	assign video_mode_toggle = video_mode_toggle_q;
	assign video_freeze      = video_freeze_q || control_stable.height <= 12'd200;
	assign mode_restart      = mode_restart_q;

	always_ff @(posedge clk_render) begin
		if (init_reset_render) begin
			raw_path_vblank_q       <= 1'b1;
			processed_path_vblank_q <= 1'b1;
			output_vblank_q         <= 1'b1;
			output_vblank_entry_q   <= 1'b0;
		end else begin
			raw_path_vblank_q       <= raw_path_vblank;
			processed_path_vblank_q <= processed_path_vblank;
			output_vblank_entry_q   <= ce_pixel && vblank && !output_vblank_q;
			if (ce_pixel) output_vblank_q <= vblank;
		end
	end

	always_ff @(posedge clk_render) begin
		if (init_reset_render) begin
			mode_q               <= DEFAULT_VIDEO_MODE;
			pending_mode_q       <= DEFAULT_VIDEO_MODE;
			key_active_q         <=   '0;
			key_pending_q        <=   '0;
			active_bypass_q      <= 1'b1;
			pending_bypass_q     <= 1'b1;
			transition_timing_q  <= 1'b0;
			transition_restart_q <= 1'b0;
			mode_restart_q       <= 1'b0;
			mode_state           <= MODE_WAIT_START;
			mode_ready           <= 1'b0;
			video_freeze_q       <= 1'b1;
		end else begin
			case (mode_state)
				MODE_WAIT_START: begin
					mode_ready     <= 1'b0;
					video_freeze_q <= 1'b1;
					mode_restart_q <= 1'b0;
					if (request_valid) begin
						mode_q           <= requested_mode;
						pending_mode_q   <= requested_mode;
						key_active_q     <= request_key;
						key_pending_q    <= request_key;
						active_bypass_q  <= request_bypass;
						pending_bypass_q <= request_bypass;
						mode_state       <= MODE_START_TIMING;
					end
				end

				MODE_START_TIMING: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b1;
					mode_state     <= MODE_START_HOLD;
				end

				MODE_START_HOLD: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b1;
					if (frame_wrap) begin
						video_freeze_q <= 1'b0;
						mode_state     <= MODE_RUN;
					end
				end

				MODE_RUN: begin
					mode_ready           <= 1'b1;
					video_freeze_q       <= 1'b0;
					mode_restart_q       <= 1'b0;
					transition_restart_q <= 1'b0;
					if (request_valid && request_changed) begin
						pending_mode_q   <= requested_mode;
						key_pending_q    <= request_key;
						pending_bypass_q <= request_bypass;
						mode_state       <= MODE_WAIT_ACTIVE_VBLANK;
					end
				end

				MODE_WAIT_ACTIVE_VBLANK: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b0;
					if (request_valid && !request_changed) begin
						mode_state <= MODE_RUN;
					end else if (request_valid) begin
						pending_mode_q   <= requested_mode;
						key_pending_q    <= request_key;
						pending_bypass_q <= request_bypass;
						if (active_path_vblank_entry) begin
							transition_timing_q  <= (request_key != key_active_q);
							transition_restart_q <= (requested_mode.fb_width != mode_q.fb_width) ||
							                        (requested_mode.fb_height !=
							                         mode_q.fb_height) ||
							                        (requested_mode.is_interlaced !=
							                         mode_q.is_interlaced);
							video_freeze_q       <= 1'b1;
							mode_state           <= (request_key != key_active_q) ?
							                        MODE_WAIT_TIMING_WRAP :
							                        MODE_WAIT_TARGET_VBLANK;
						end
					end
				end

				MODE_WAIT_TIMING_WRAP: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b1;
					if (frame_wrap) begin
						mode_q              <= pending_mode_q;
						key_active_q        <= key_pending_q;
						video_mode_toggle_q <= !video_mode_toggle_q;
						mode_restart_q      <= transition_restart_q;
						mode_state          <= MODE_WAIT_TARGET_VBLANK;
					end
				end

				MODE_WAIT_TARGET_VBLANK: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						mode_restart_q  <= 1'b0;
						key_active_q    <= key_pending_q;
						active_bypass_q <= pending_bypass_q;
						mode_state      <= MODE_HOLD_TARGET_FRAME;
					end else if (!transition_restart_q && target_path_vblank_entry) begin
						key_active_q    <= key_pending_q;
						active_bypass_q <= pending_bypass_q;
						if (!transition_timing_q) video_mode_toggle_q <= !video_mode_toggle_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end
				end

				MODE_HOLD_TARGET_FRAME: begin
					mode_ready     <= 1'b1;
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						transition_restart_q <= 1'b0;
						video_freeze_q       <= 1'b0;
						mode_state           <= MODE_RUN;
					end else if (!transition_restart_q && target_path_vblank_entry) begin
						video_freeze_q <= 1'b0;
						mode_state     <= MODE_RUN;
					end
				end

				default: begin
					mode_state     <= MODE_WAIT_START;
					mode_ready     <= 1'b0;
					video_freeze_q <= 1'b1;
					mode_restart_q <= 1'b0;
				end
			endcase
		end
	end

	always_comb begin
		case (aspect_ratio)
			2'd0:    begin
				video_arx = optimized_arx;
				video_ary = optimized_ary;
			end
			2'd1:    begin
				video_arx = 13'd0;
				video_ary = 13'd0;
			end
			default: begin
				video_arx = 13'h1000 | {1'b0, fb_width};
				video_ary = 13'h1000 | {1'b0, fb_height};
			end
		endcase
	end

	typedef struct packed {
		logic [11:0] fb_width;
		logic [11:0] fb_height;
		logic [11:0] x_center;
		logic [11:0] y_center;
		logic  [2:0] orientation;
		logic        zoom_wide;
		logic        hardware_flip_x;
		logic        hardware_flip_y;
		logic        is_1080p;
		logic        is_480p;
		logic        is_240p;
	} raster_cfg_t;

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	raster_cfg_t        raster_cfg_meta_12 = '0, raster_cfg_12 = '0;
	logic signed [23:0] raster_x;
	logic signed [23:0] raster_y;
	logic               beam_in_bounds;

	always_ff @(posedge clk_12) begin
		if (reset) begin
			raster_cfg_meta_12 <= '0;
			raster_cfg_12      <= '0;
		end else begin
			raster_cfg_meta_12.fb_width        <= fb_width;
			raster_cfg_meta_12.fb_height       <= fb_height;
			raster_cfg_meta_12.x_center        <= x_center;
			raster_cfg_meta_12.y_center        <= y_center;
			raster_cfg_meta_12.orientation     <= geometry_orientation;
			raster_cfg_meta_12.zoom_wide       <= geometry_zoom_wide;
			raster_cfg_meta_12.hardware_flip_x <= hardware_flip_x;
			raster_cfg_meta_12.hardware_flip_y <= hardware_flip_y;
			raster_cfg_meta_12.is_1080p        <= is_1080p;
			raster_cfg_meta_12.is_480p         <= is_480p;
			raster_cfg_meta_12.is_240p         <= is_240p;
			raster_cfg_12                      <= raster_cfg_meta_12;
		end
	end

	spaceduel_geometry geometry (
		.source_x(avg_x),
		.source_y(avg_y),
		.hardware_flip_x(raster_cfg_12.hardware_flip_x),
		.hardware_flip_y(raster_cfg_12.hardware_flip_y),
		.mode_1080p(raster_cfg_12.is_1080p),
		.mode_480p(raster_cfg_12.is_480p),
		.mode_240p(raster_cfg_12.is_240p),
		.center_x(raster_cfg_12.x_center),
		.center_y(raster_cfg_12.y_center),
		.render_width(raster_cfg_12.fb_width),
		.render_height(raster_cfg_12.fb_height),
		.orientation(raster_cfg_12.orientation),
		.zoom_wide(raster_cfg_12.zoom_wide),
		.raster_x(raster_x),
		.raster_y(raster_y),
		.beam_in_bounds(beam_in_bounds)
	);

	logic  raw_beam_on;
	assign raw_beam_on = !avg_halted && (avg_z != 8'd0) && (avg_rgb != 3'b000);

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic mode_ready_12_meta = 1'b0, mode_ready_12 = 1'b0;
	always_ff @(posedge clk_12) begin
		mode_ready_12_meta <= mode_ready;
		mode_ready_12      <= mode_ready_12_meta;
	end

	logic  source_reset;
	assign source_reset = reset || !mode_ready_12;

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [1:0] render_reset_sync = 2'b11;
	logic       render_reset;
	always_ff @(posedge clk_render)
		render_reset_sync <= {render_reset_sync[0], reset || !mode_ready || mode_restart_q};
	assign render_reset = render_reset_sync[1];

	logic [10:0] vector_x_q;
	logic [10:0] vector_y_q;
	logic  [8:0] vector_z_q;
	logic  [2:0] vector_color_q;
	logic        vector_is_dot_q;
	logic        vector_beam_on_q;
	logic        frame_done_q;

	spaceduel_beam_energy beam_energy (
		.clk(clk_12), .reset(source_reset), .mode(velocity_comp),
		.brightness_mode(profile_settings.brightness),
		.step_x(avg_step_x), .step_y(avg_step_y),
		.x_in(raster_x[10:0]), .y_in(raster_y[10:0]), .z_in(avg_z),
		.color_in(avg_rgb), .dot_in(avg_is_dot),
		.beam_in(raw_beam_on && beam_in_bounds), .eof_in(frame_done),
		.x_out(vector_x_q), .y_out(vector_y_q), .energy_out(vector_z_q),
		.color_out(vector_color_q), .dot_out(vector_is_dot_q),
		.beam_out(vector_beam_on_q), .eof_out(frame_done_q)
	);

	logic        half_rate_phase        = 1'b0;
	wire  [19:0] fractional_numerator   = mode_q.fractional_numerator;
	wire  [19:0] fractional_denominator = mode_q.fractional_denominator;
	logic        fractional_ce;
	logic        progressive_ce_pixel =  1'b0;
	logic [10:0] h_counter            = 11'd0;
	logic [10:0] v_counter            = 11'd0;
	logic        timing_reset;
	logic        h_end;
	logic        v_end;
	logic        v_end_q = 1'b0;
	logic        raw_hsync;
	logic        raw_vsync;
	logic        raw_hblank;
	logic        raw_vblank;
	logic [7:0]  progressive_video_r;
	logic [7:0]  progressive_video_g;
	logic [7:0]  progressive_video_b;
	logic        progressive_hsync;
	logic        progressive_vsync;
	logic        progressive_hblank;
	logic        progressive_vblank;

	assign timing_reset = !mode_ready;
	assign h_end        = (h_counter == h_total[10:0]);
	assign v_end        = v_end_q;
	assign frame_wrap   = progressive_ce_pixel && h_end && v_end;
	assign mode_commit  = (mode_state == MODE_WAIT_TIMING_WRAP) && frame_wrap;

	video_fractional_ce #(.WIDTH(20)) pixel_enable_nco (
		.clk(clk_render),
		.reset(timing_reset || mode_commit),
		.advance(is_240p || is_480p),
		.numerator(fractional_numerator),
		.denominator(fractional_denominator),
		.ce(fractional_ce)
	);

	always_ff @(posedge clk_render) begin
		if (timing_reset || mode_commit) begin
			progressive_ce_pixel <= 1'b0;
		end else if (is_1080p || is_120hz) begin
			progressive_ce_pixel <= 1'b1;
		end else if (is_240p || is_480p) begin
			progressive_ce_pixel <= fractional_ce;
		end else begin
			progressive_ce_pixel <= !half_rate_phase;
		end
	end

	always_ff @(posedge clk_render) begin
		if (timing_reset || mode_commit)
			v_end_q <= 1'b0;
		else
			v_end_q <= (v_counter >= v_total[10:0]);
	end

	always_ff @(posedge clk_render) begin
		if (timing_reset) begin
			half_rate_phase <= 1'b0;
			h_counter       <= h_total[10:0];
			v_counter       <= fb_height[10:0] + 11'd2;
		end else if (mode_commit) begin
			half_rate_phase <=  1'b0;
			h_counter       <= 11'd0;
			v_counter       <= 11'd0;
		end else begin
			half_rate_phase <= !half_rate_phase;
			if (progressive_ce_pixel) begin
				if (h_end) begin
					h_counter <= 11'd0;
					v_counter <= v_end ? 11'd0 : v_counter + 1'd1;
				end else begin
					h_counter <= h_counter + 1'd1;
				end
			end
		end
	end

	always_comb begin
		raw_hsync  = !((h_counter >= hs_start[10:0]) && (h_counter < hs_end[10:0]));
		raw_vsync  = !((v_counter >= vs_start[10:0]) && (v_counter < vs_end[10:0]));
		raw_hblank = (h_counter >= fb_width[10:0]);
		raw_vblank = (v_counter >= fb_height[10:0]);
	end

	wire full_spill_primary = profile_settings.brightness != vfb_control_pkg::BRIGHTNESS_OFF;

	vfb_top framebuffer (
		.clk_sys(clk_render),
		.clk_12(clk_12),
		.reset(render_reset),
		.source_reset(source_reset),
		.ddr_reset(ddr_reset),
		.video_timing_reset(timing_reset),

		.X_VECTOR(vector_x_q),
		.Y_VECTOR(vector_y_q),
		.Z_VECTOR(vector_z_q),
		.COLOR(vector_color_q),
		.IS_DOT(vector_is_dot_q),
		.BEAM_ON(vector_beam_on_q),

		.DDRAM_CLK(ddram_clk),
		.DDRAM_BUSY(ddram_busy),
		.DDRAM_BURSTCNT(ddram_burst_count),
		.DDRAM_ADDR(ddram_address),
		.DDRAM_DOUT(ddram_data_out),
		.DDRAM_DOUT_READY(ddram_data_ready),
		.DDRAM_RD(ddram_read),
		.DDRAM_DIN(ddram_data_in),
		.DDRAM_BE(ddram_byte_enable),
		.DDRAM_WE(ddram_write),

		.SDRAM_DQ_IN(sdram_data_in),
		.SDRAM_DQ_OUT(sdram_data_out),
		.SDRAM_DQ_OE(sdram_data_oe),
		.SDRAM_CKE(sdram_cke),
		.SDRAM_nCS(sdram_ncs),
		.SDRAM_nRAS(sdram_nras),
		.SDRAM_nCAS(sdram_ncas),
		.SDRAM_nWE(sdram_nwe),
		.SDRAM_DQM(sdram_dqm),
		.SDRAM_A(sdram_address),
		.SDRAM_BA(sdram_bank),

		.RENDER_WIDTH(fb_width),
		.RENDER_HEIGHT(fb_height),
		.VGA_R(progressive_video_r),
		.VGA_G(progressive_video_g),
		.VGA_B(progressive_video_b),
		.VGA_HS(progressive_hsync),
		.VGA_VS(progressive_vsync),
		.VGA_HBLANK(progressive_hblank),
		.VGA_VBLANK(progressive_vblank),

		.h_cnt(h_counter),
		.v_cnt(v_counter),
		.ce_pix(progressive_ce_pixel),
		.hsync(raw_hsync),
		.vsync(raw_vsync),
		.hblank(raw_hblank),
		.vblank(raw_vblank),

		.FLASH_PARAM(8'd0),
		.OSD_120HZ(is_120hz),
		.FRAME_DONE(frame_done_q),
		.BUFFER_MODE(buffer_mode),
		.DOT_MODE(profile_settings.dot_mode),
		.FIFO_HIGH_WATER_LED(fifo_high_water),
		.osd_full_spill_primary(full_spill_primary),
		.osd_bloom_width(profile_settings.bloom_width),
		.osd_bloom_curve(profile_settings.bloom_curve),
		.osd_halo_filter(profile_settings.halo_filter),
		.osd_halo_curve(profile_settings.halo_curve),
		.osd_phosphor_mode(profile_settings.intra_frame_decay),
		.osd_inter_frame_phosphor_mode(profile_settings.inter_frame_decay),
		.osd_halo_spread(profile_settings.halo_spread),
		.osd_halo_knee(profile_settings.halo_knee),
		.osd_color_space(profile_settings.color_space),
		.osd_presentation_color(profile_settings.presentation_color),
		.osd_slot_mask(profile_settings.slot_mask),
		.osd_slot_mask_rows(vfb_control_pkg::orientation_swaps_axes(geometry_orientation)),
		.full_bypass_active(active_bypass_q),
		.halo_shape(halo_shape),
		.halo_grid_8(key_active_q.halo_grid),
		.raw_path_vblank(raw_path_vblank),
		.processed_path_vblank(processed_path_vblank)
	);

	localparam logic [1:0] INTERLACER_PATH_RESTART_CYCLES = 2'd3;
	logic [1:0]            interlacer_restart_count       = 2'd0;
	logic                  interlacer_mode_commit_q       = 1'b0;
	always_ff @(posedge clk_render) begin
		if (init_reset_render || timing_reset)
			interlacer_mode_commit_q <= 1'b0;
		else
			interlacer_mode_commit_q <= mode_commit;
	end

	always_ff @(posedge clk_render) begin
		if (init_reset_render || timing_reset || !is_interlaced)
			interlacer_restart_count <= 2'd0;
		else if (profile_path_commit)
			interlacer_restart_count <= INTERLACER_PATH_RESTART_CYCLES;
		else if (interlacer_restart_count != 2'd0)
			interlacer_restart_count <= interlacer_restart_count - 1'd1;
	end

	vfb_interlacer interlacer (
		.clk_sys(clk_render),
		.reset(timing_reset || interlacer_mode_commit_q || mode_restart_q ||
		       !is_interlaced ||
		       (interlacer_restart_count != 2'd0)),
		.enable(is_interlaced),
		.authentic_timing(is_authentic),
		.vertical_offset(crt_vertical_offset),
		.horizontal_offset(mode_q.crt_horizontal_offset),
		.ce_pix_in(progressive_ce_pixel),
		.r_in(progressive_video_r),
		.g_in(progressive_video_g),
		.b_in(progressive_video_b),
		.hsync_in(progressive_hsync),
		.vsync_in(progressive_vsync),
		.hblank_in(progressive_hblank),
		.vblank_in(progressive_vblank),
		.ce_pix_out(ce_pixel),
		.r_out(video_r),
		.g_out(video_g),
		.b_out(video_b),
		.hsync_out(hsync),
		.vsync_out(vsync),
		.hblank_out(hblank),
		.vblank_out(vblank),
		.field_out(field)
	);

	always_comb mode_supports_120hz       = mode_ready && height_supports_120hz;
	always_comb mode_supports_test_format = mode_ready && test_format_active;
	always_comb mode_is_15khz             = mode_ready && (is_240p || is_interlaced);

endmodule
