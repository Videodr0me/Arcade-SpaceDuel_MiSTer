// Space Duel status layout and resolution-specific CRT profiles.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

package vfb_control_pkg;
	// Each Custom slot occupies 33 contiguous bits; Custom 2 is 64 bits above Custom 1.
	typedef struct packed {
		logic       halo_grid;
		logic [2:0] halo_knee;
		logic [1:0] halo_spread;
		logic [2:0] halo_curve;
		logic [2:0] halo_filter;
		logic [2:0] bloom_curve;
		logic [2:0] bloom_width;
		logic [1:0] intra_frame_decay;
		logic [1:0] inter_frame_decay;
		logic [2:0] dot_mode;
		logic [1:0] slot_mask;
		logic       color_space;
		logic [2:0] presentation_color;
		logic [1:0] brightness;
	} vfb_profile_settings_t;

	localparam int ST_MAIN_RESET = 0, ST_AUTOSAVE_OFF = 1, ST_SAVE_NVRAM = 4;
	localparam int ST_OSD_PAUSE = 5, ST_DIM = 6, ST_GAME_RESET = 7;
	localparam int VELOCITY_LSB = 8, ST_AUDIO_FILTER_OFF = 10;
	localparam int ST_BYPASS = 11, PROFILE_LSB = 12, CUSTOM_INIT_BIT = 15;
	localparam int CUSTOM1_LSB = 16, CUSTOM2_LSB = 80;
	localparam int PROFILE_BITS = $bits(vfb_profile_settings_t);
	localparam int ST_CRT_240P = 54, ST_DIRECT_31KHZ = 55, ST_120HZ = 56;
	localparam int CRT_VERTICAL_LSB = 57, CRT_HORIZONTAL_LSB = 60;
	localparam int ST_AUTHENTIC = 63, ST_ZOOM_WIDE = 64;
	localparam int ORIENTATION_LSB = 75, ASPECT_LSB = 78;
	localparam int HALO_SHAPE_LSB = 118, TEST_FORMAT_LSB = 120, BUFFER_MODE_LSB = 126;

	localparam logic [2:0] PROFILE_TOUCH        = 3'd6;
	localparam logic [2:0] PROFILE_TYPICAL      = 3'd0;
	localparam logic [2:0] PROFILE_OVERDRIVEN   = 3'd1;
	localparam logic [2:0] PROFILE_NEON         = 3'd2;
	localparam logic [2:0] PROFILE_PLASMA_STORM = 3'd3;
	localparam logic [2:0] PROFILE_CUSTOM1      = 3'd4;
	localparam logic [2:0] PROFILE_CUSTOM2      = 3'd5;

	localparam logic [2:0] DOT_1X = 3'd0, DOT_15X = 3'd1, DOT_2X = 3'd2;
	localparam logic [2:0] DOT_25X = 3'd3, DOT_3X = 3'd4, DOT_4X = 3'd5, DOT_5X = 3'd6;

	localparam logic [1:0] BRIGHTNESS_LINEAR1 = 2'd1;
	localparam logic [1:0] BRIGHTNESS_LINEAR2 = 2'd2;
	localparam logic [1:0] BRIGHTNESS_BRIGHT  = 2'd3;
	localparam logic [1:0] BRIGHTNESS_OFF     = 2'd0;

	localparam logic [2:0] BLOOM_OFF    = 3'd0;
	localparam logic [2:0] BLOOM_THIN   = 3'd1;
	localparam logic [2:0] BLOOM_TIGHT  = 3'd2;
	localparam logic [2:0] BLOOM_SOFT   = 3'd3;
	localparam logic [2:0] BLOOM_NORMAL = 3'd4;
	localparam logic [2:0] BLOOM_BROAD  = 3'd5;
	localparam logic [2:0] BLOOM_WIDE_M = 3'd6;
	localparam logic [2:0] BLOOM_WIDE   = 3'd7;

	localparam logic [2:0] CURVE_MINIMAL  = 3'd0;
	localparam logic [2:0] CURVE_MIN_PLUS = 3'd1;
	localparam logic [2:0] CURVE_MILD     = 3'd2;
	localparam logic [2:0] CURVE_MILD_P   = 3'd3;
	localparam logic [2:0] CURVE_MODERATE = 3'd4;
	localparam logic [2:0] CURVE_MOD_PLUS = 3'd5;
	localparam logic [2:0] CURVE_STRONG_M = 3'd6;
	localparam logic [2:0] CURVE_STRONG   = 3'd7;

	localparam logic [2:0] HALO_OFF  = 3'd0;
	localparam logic [2:0] HALO_025X = 3'd1;
	localparam logic [2:0] HALO_033X = 3'd2;
	localparam logic [2:0] HALO_050X = 3'd3;
	localparam logic [2:0] HALO_075X = 3'd4;
	localparam logic [2:0] HALO_100X = 3'd5;
	localparam logic [2:0] HALO_125X = 3'd6;
	localparam logic [2:0] HALO_150X = 3'd7;

	localparam logic [1:0] SPREAD_ORIGINAL = 2'd0;
	localparam logic [1:0] SPREAD_WIDE1    = 2'd1;
	localparam logic [1:0] SPREAD_WIDE2    = 2'd2;
	localparam logic [1:0] SPREAD_FOCUS    = 2'd3;

	localparam logic [2:0] KNEE_OFF = 3'd0, KNEE_2 = 3'd1, KNEE_4 = 3'd2, KNEE_6 = 3'd3;
	localparam logic [2:0] KNEE_8 = 3'd4, KNEE_16 = 3'd5, KNEE_24 = 3'd6, KNEE_32 = 3'd7;
	localparam logic HALO_GRID_16 = 1'b0, HALO_GRID_8 = 1'b1;

	localparam logic [1:0] INTER_OFF    = 2'd0;
	localparam logic [1:0] INTER_SHORT  = 2'd1;
	localparam logic [1:0] INTER_MEDIUM = 2'd2;
	localparam logic [1:0] INTER_LONG   = 2'd3;

	localparam logic [1:0] INTRA_OFF   = 2'd0;
	localparam logic [1:0] INTRA_LUT_A = 2'd1;
	localparam logic [1:0] INTRA_LUT_B = 2'd2;
	localparam logic [1:0] INTRA_LUT_C = 2'd3;

	localparam logic COLORSPACE_OFF        = 1'b0;
	localparam logic COLORSPACE_WG6100_709 = 1'b1;

	localparam logic [2:0] CHANNEL_ORIGINAL = 3'd0;
	localparam logic [2:0] CHANNEL_RBG      = 3'd1;
	localparam logic [2:0] CHANNEL_GRB      = 3'd2;
	localparam logic [2:0] CHANNEL_GBR      = 3'd3;
	localparam logic [2:0] CHANNEL_BRG      = 3'd4;
	localparam logic [2:0] CHANNEL_BGR      = 3'd5;
	localparam logic [2:0] CHANNEL_BW       = 3'd6;
	localparam logic [2:0] CHANNEL_NEGATIVE = 3'd7;

	localparam logic [1:0] SLOT_MASK_OFF = 2'd0, SLOT_MASK_MILD = 2'd1;
	localparam logic [1:0] SLOT_MASK_MEDIUM = 2'd2, SLOT_MASK_MAX = 2'd3;
	localparam logic [1:0] VELOCITY_OFF = 2'd0, VELOCITY_050 = 2'd1;
	localparam logic [1:0] VELOCITY_075 = 2'd2, VELOCITY_100 = 2'd3;

	function automatic logic orientation_swaps_axes(input logic [2:0] orientation);
		return (orientation == 3'd1) || (orientation == 3'd3) ||
		       (orientation == 3'd6) || (orientation == 3'd7);
	endfunction

	function automatic vfb_profile_settings_t pack_settings;
		input logic [2:0] dot_i;
		input logic [1:0] tone_i;
		input logic [2:0] bloom_width_i;
		input logic [2:0] bloom_curve_i;
		input logic [2:0] halo_i;
		input logic [2:0] halo_curve_i;
		input logic [1:0] halo_spread_i;
		input logic [2:0] halo_knee_i;
		input logic [1:0] inter_decay_i;
		input logic [1:0] intra_decay_i;
		input logic       color_space_i;
		input logic [2:0] color_i;
		input logic [1:0] slot_mask_i;
		input logic       halo_grid_i;
		begin
			pack_settings = {halo_grid_i, halo_knee_i, halo_spread_i, halo_curve_i, halo_i,
			                 bloom_curve_i, bloom_width_i, intra_decay_i, inter_decay_i,
			                 dot_i, slot_mask_i, color_space_i, color_i, tone_i};
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_240p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:        fixed_240p = pack_settings(
					DOT_15X, BRIGHTNESS_OFF, BLOOM_THIN, CURVE_MILD_P,
					HALO_OFF, CURVE_MILD_P, SPREAD_FOCUS, KNEE_16,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_8);
				PROFILE_TYPICAL:      fixed_240p = pack_settings(
					DOT_15X, BRIGHTNESS_LINEAR2, BLOOM_TIGHT, CURVE_MIN_PLUS,
					HALO_025X, CURVE_MILD_P, SPREAD_FOCUS, KNEE_16,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_8);
				PROFILE_OVERDRIVEN:   fixed_240p = pack_settings(
					DOT_25X, BRIGHTNESS_BRIGHT, BLOOM_TIGHT, CURVE_MIN_PLUS,
					HALO_025X, CURVE_MILD_P, SPREAD_FOCUS, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_8);
				PROFILE_NEON:         fixed_240p = pack_settings(
					DOT_25X, BRIGHTNESS_BRIGHT, BLOOM_THIN, CURVE_MODERATE,
					HALO_075X, CURVE_MILD, SPREAD_FOCUS, KNEE_4,
					INTER_MEDIUM, INTRA_LUT_C,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				PROFILE_PLASMA_STORM: fixed_240p = pack_settings(
					DOT_3X, BRIGHTNESS_LINEAR2, BLOOM_SOFT, CURVE_MILD_P,
					HALO_150X, CURVE_MODERATE, SPREAD_WIDE2, KNEE_2,
					INTER_MEDIUM, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				default:              fixed_240p = pack_settings(
					DOT_1X, BRIGHTNESS_LINEAR1, BLOOM_OFF, CURVE_MINIMAL,
					HALO_OFF, CURVE_MINIMAL, SPREAD_ORIGINAL, KNEE_16,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_480p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:        fixed_480p = pack_settings(
					DOT_2X, BRIGHTNESS_OFF, BLOOM_TIGHT, CURVE_MILD,
					HALO_033X, CURVE_MILD, SPREAD_WIDE1, KNEE_16,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_8);
				PROFILE_TYPICAL:      fixed_480p = pack_settings(
					DOT_2X, BRIGHTNESS_LINEAR2, BLOOM_TIGHT, CURVE_MILD,
					HALO_050X, CURVE_MILD, SPREAD_WIDE1, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_8);
				PROFILE_OVERDRIVEN:   fixed_480p = pack_settings(
					DOT_3X, BRIGHTNESS_BRIGHT, BLOOM_TIGHT, CURVE_MILD,
					HALO_050X, CURVE_MILD, SPREAD_WIDE1, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_8);
				PROFILE_NEON:         fixed_480p = pack_settings(
					DOT_3X, BRIGHTNESS_BRIGHT, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_050X, CURVE_MILD_P, SPREAD_ORIGINAL, KNEE_24,
					INTER_MEDIUM, INTRA_LUT_C,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				PROFILE_PLASMA_STORM: fixed_480p = pack_settings(
					DOT_4X, BRIGHTNESS_LINEAR2, BLOOM_NORMAL, CURVE_MILD,
					HALO_150X, CURVE_MODERATE, SPREAD_WIDE1, KNEE_2,
					INTER_MEDIUM, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				default:              fixed_480p = pack_settings(
					DOT_1X, BRIGHTNESS_LINEAR1, BLOOM_OFF, CURVE_MINIMAL,
					HALO_OFF, CURVE_MINIMAL, SPREAD_ORIGINAL, KNEE_16,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_720p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:        fixed_720p = pack_settings(
					DOT_3X, BRIGHTNESS_OFF, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_025X, CURVE_MOD_PLUS, SPREAD_FOCUS, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				PROFILE_TYPICAL:      fixed_720p = pack_settings(
					DOT_3X, BRIGHTNESS_LINEAR2, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_025X, CURVE_MOD_PLUS, SPREAD_FOCUS, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_WG6100_709, CHANNEL_ORIGINAL, SLOT_MASK_MILD, HALO_GRID_16);
				PROFILE_OVERDRIVEN:   fixed_720p = pack_settings(
					DOT_3X, BRIGHTNESS_BRIGHT, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_025X, CURVE_MOD_PLUS, SPREAD_FOCUS, KNEE_24,
					INTER_MEDIUM, INTRA_OFF,
					COLORSPACE_WG6100_709, CHANNEL_ORIGINAL, SLOT_MASK_MILD, HALO_GRID_16);
				PROFILE_NEON:         fixed_720p = pack_settings(
					DOT_4X, BRIGHTNESS_BRIGHT, BLOOM_NORMAL, CURVE_MIN_PLUS,
					HALO_050X, CURVE_MOD_PLUS, SPREAD_ORIGINAL, KNEE_16,
					INTER_MEDIUM, INTRA_LUT_C,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				PROFILE_PLASMA_STORM: fixed_720p = pack_settings(
					DOT_4X, BRIGHTNESS_LINEAR2, BLOOM_NORMAL, CURVE_MILD_P,
					HALO_150X, CURVE_MOD_PLUS, SPREAD_WIDE1, KNEE_2,
					INTER_LONG, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				default:              fixed_720p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_1080p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH:        fixed_1080p = pack_settings(
					DOT_4X, BRIGHTNESS_OFF, BLOOM_TIGHT, CURVE_MOD_PLUS,
					HALO_050X, CURVE_MILD_P, SPREAD_WIDE2, KNEE_24,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				PROFILE_TYPICAL:      fixed_1080p = pack_settings(
					DOT_4X, BRIGHTNESS_LINEAR2, BLOOM_NORMAL, CURVE_MIN_PLUS,
					HALO_050X, CURVE_MILD_P, SPREAD_WIDE2, KNEE_24,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_WG6100_709, CHANNEL_ORIGINAL, SLOT_MASK_MILD, HALO_GRID_16);
				PROFILE_OVERDRIVEN:   fixed_1080p = pack_settings(
					DOT_5X, BRIGHTNESS_BRIGHT, BLOOM_NORMAL, CURVE_MIN_PLUS,
					HALO_050X, CURVE_MILD_P, SPREAD_WIDE1, KNEE_24,
					INTER_MEDIUM, INTRA_OFF,
					COLORSPACE_WG6100_709, CHANNEL_ORIGINAL, SLOT_MASK_MILD, HALO_GRID_16);
				PROFILE_NEON:         fixed_1080p = pack_settings(
					DOT_5X, BRIGHTNESS_BRIGHT, BLOOM_WIDE_M, CURVE_MINIMAL,
					HALO_100X, CURVE_MOD_PLUS, SPREAD_WIDE2, KNEE_2,
					INTER_MEDIUM, INTRA_LUT_C,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				PROFILE_PLASMA_STORM: fixed_1080p = pack_settings(
					DOT_5X, BRIGHTNESS_OFF, BLOOM_NORMAL, CURVE_MODERATE,
					HALO_150X, CURVE_STRONG, SPREAD_WIDE2, KNEE_2,
					INTER_LONG, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
				default:              fixed_1080p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	function automatic vfb_profile_settings_t fixed_profile(
		input logic [2:0] profile, input logic [1:0] resolution);
		case (resolution)
			2'd0:    fixed_profile = fixed_240p(profile);
			2'd1:    fixed_profile = fixed_480p(profile);
			2'd2:    fixed_profile = fixed_720p(profile);
			default: fixed_profile = fixed_1080p(profile);
		endcase
	endfunction

	function automatic vfb_profile_settings_t bypass_settings();
		bypass_settings = pack_settings(DOT_1X, BRIGHTNESS_OFF, BLOOM_OFF, CURVE_MINIMAL,
		                                HALO_OFF, CURVE_MINIMAL, SPREAD_ORIGINAL, KNEE_16,
		                                INTER_OFF, INTRA_OFF, COLORSPACE_OFF,
		                                CHANNEL_ORIGINAL, SLOT_MASK_OFF, HALO_GRID_16);
	endfunction
endpackage

`default_nettype wire
