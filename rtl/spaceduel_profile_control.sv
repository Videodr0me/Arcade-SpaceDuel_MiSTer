// Space Duel profile shortcuts and persistent custom controls.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later

`default_nettype none

module spaceduel_profile_control (
	input  wire           clk_sys,
	input  wire           reset,
	input  wire           commit, echo, clear_settings,
	input  wire  [127:0]  stored, incoming,
	input  wire           settings_ready,
	input  wire  [1:0]    video_resolution,
	input  wire           video_freeze, video_is_15khz, direct_video,
	input  wire           video_supports_120hz, video_supports_test_format,
	input  wire           osd_open,
	input  wire  [10:0]   ps2_key,

	output vfb_control_pkg::vfb_profile_settings_t custom_1_settings,
	output vfb_control_pkg::vfb_profile_settings_t custom_2_settings,
	output vfb_control_pkg::vfb_profile_settings_t resolved_settings =
	    vfb_control_pkg::fixed_profile(vfb_control_pkg::PROFILE_TYPICAL, 2'd1),

	output wire  [2:0]    profile,
	output logic [127:0]  status,
	output wire           reply_pending, custom_editable,
	output logic [15:0]   menu_mask,
	output logic          info_req = 1'b0,
	output logic [7:0]    info = 8'd0
);
	import vfb_control_pkg::*;

	function automatic vfb_profile_settings_t read_custom(input logic [127:0] cfg, input logic slot);
		read_custom = slot ? cfg[CUSTOM2_LSB +: PROFILE_BITS] : cfg[CUSTOM1_LSB +: PROFILE_BITS];
	endfunction

	function automatic logic [127:0] write_custom(
		input logic [127:0] cfg, input logic slot, input vfb_profile_settings_t value);
		write_custom = cfg;
		if (slot) write_custom[CUSTOM2_LSB +: PROFILE_BITS] = value;
		else      write_custom[CUSTOM1_LSB +: PROFILE_BITS] = value;
	endfunction

	// Accept synchronized video-mode settings after two matching clk_sys samples.
	// Initialize custom slots after video resumes with the matching preset table.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [4:0] mode_meta = {3'b001, 2'd1}, mode_sync = {3'b001, 2'd1};
	logic [4:0] mode_sync_d = {3'b001, 2'd1};
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic       rate_meta = 1'b0, rate_sync = 1'b0;
	always_ff @(posedge clk_sys) begin
		mode_meta   <= {video_supports_test_format, video_is_15khz, video_freeze, video_resolution};
		mode_sync   <= mode_meta;
		mode_sync_d <= mode_sync;
		rate_meta   <= video_supports_120hz;
		rate_sync   <= rate_meta;
	end

	wire       can_reply   = settings_ready &&
	                         !reset &&
	                         !(stored[ST_MAIN_RESET] ||
	                           stored[ST_GAME_RESET] ||
	                           stored[ST_SAVE_NVRAM]);
	wire [1:0] crt_table   = !direct_video && mode_sync[4] ?
	                         (stored[TEST_FORMAT_LSB +: 2] == 2'd2 ? 2'd0 : 2'd1) :
	                         (stored[ST_CRT_240P] &&
	                          !(direct_video && stored[ST_DIRECT_31KHZ]) ? 2'd0 : 2'd1);
	wire       table_ready = !(direct_video || mode_sync[3] || mode_sync[4]) ||
	                         mode_sync[1:0] == crt_table;
	wire       seed_ready  = can_reply && !commit && !mode_sync[2] && mode_sync == mode_sync_d &&
	                         table_ready;

	vfb_profile_settings_t custom1_status, custom2_status, custom1_default, custom2_default;
	vfb_profile_settings_t selected_settings;
	wire   [1:0]           slot_valid;
	wire                   initialized = &slot_valid;
	wire   [2:0]           selected_profile;
	wire                   custom_selected = profile == PROFILE_CUSTOM1 ||
	                                         profile == PROFILE_CUSTOM2;
	wire   [3:0]           pending;
	wire   [1:0]           velocity_setting;
	assign                 profile         = selected_profile == 3'd7 ? PROFILE_TYPICAL
	                                                                  : selected_profile;
	assign                 custom1_default = fixed_profile(PROFILE_TYPICAL, mode_sync[1:0]);
	assign                 custom2_default = fixed_profile(PROFILE_OVERDRIVEN, mode_sync[1:0]);

	always_comb begin
		custom_1_settings = custom1_status;
		custom_2_settings = custom2_status;
		// Use default presets until the custom slots are initialized.
		if (!slot_valid[0]) custom_1_settings = custom1_default;
		if (!slot_valid[1]) custom_2_settings = custom2_default;
		case (profile)
			PROFILE_CUSTOM1: selected_settings = custom_1_settings;
			PROFILE_CUSTOM2: selected_settings = custom_2_settings;
			default:         selected_settings = fixed_profile(profile, mode_sync[1:0]);
		endcase
	end

	// Preset copies retain selected settings while Effects Bypass controls the renderer.
	always_ff @(posedge clk_sys) begin
		if (reset) resolved_settings <= fixed_profile(PROFILE_TYPICAL, 2'd1);
		else if (mode_sync == mode_sync_d) begin
			// Allow halo-grid changes to complete while video is frozen.
			if (stored[ST_BYPASS]) resolved_settings <= bypass_settings();
			else                   resolved_settings <= selected_settings;
		end
	end

	function automatic logic [2:0] cycle_profile(input logic [2:0] current, input logic next);
		if (next) cycle_profile = current == PROFILE_TOUCH ? PROFILE_TYPICAL : current + 3'd1;
		else      cycle_profile = current == PROFILE_TYPICAL ? PROFILE_TOUCH : current - 3'd1;
	endfunction

	logic       key_toggle_q = 1'b0;
	logic [1:0] profile_keys_down = 0, control_keys_down = 0, shift_keys_down = 0;
	logic [3:0] copy_keys_down   = 0;
	wire        key_event        = ps2_key[10] != key_toggle_q;
	wire        profile_prev_key = ps2_key[7:0] == 8'h4e;
	wire        profile_next_key = ps2_key[7:0] == 8'h55;
	wire        key_press        = key_event && ps2_key[9] && !ps2_key[8] && !osd_open && can_reply;
	wire        profile_press    = key_press &&
	                               ((profile_prev_key && !profile_keys_down[0]) ||
	                                (profile_next_key && !profile_keys_down[1]));
	wire        copy_first_key   = ps2_key[7:0] == 8'h16;
	wire        copy_second_key  = ps2_key[7:0] == 8'h1e;
	wire        copy_f6_key      = ps2_key[7:0] == 8'h0b;
	wire        copy_f7_key      = ps2_key[7:0] == 8'h83;
	wire        copy_chord       = (|control_keys_down) && (|shift_keys_down);
	// Require a new copy-key press once the source preset is ready.
	wire       copy_ready = seed_ready || (can_reply && initialized && custom_selected);
	wire [1:0] copy_to    = {2{key_press && copy_ready}} &
	                        ({copy_f7_key && !copy_keys_down[3],
	                          copy_f6_key && !copy_keys_down[2]} |
	                         ({2{copy_chord}} & {copy_second_key && !copy_keys_down[1],
	                           copy_first_key  && !copy_keys_down[0]})) &
	                        {profile != PROFILE_CUSTOM2, profile != PROFILE_CUSTOM1};
	wire       copy_press = |copy_to;

	always_ff @(posedge clk_sys) begin
		key_toggle_q <= ps2_key[10];
		// Prevent stale held-key state after closing the OSD.
		if (osd_open) begin
			profile_keys_down <= 0;
			control_keys_down <= 0;
			shift_keys_down   <= 0;
			copy_keys_down    <= 0;
		end else if (key_event) begin
			if (ps2_key[7:0] == 8'h14) control_keys_down[ps2_key[8]] <= ps2_key[9];
			if (!ps2_key[8]) begin
				if (profile_prev_key)      profile_keys_down[0] <= ps2_key[9];
				if (profile_next_key)      profile_keys_down[1] <= ps2_key[9];
				if (ps2_key[7:0] == 8'h12) shift_keys_down[0]   <= ps2_key[9];
				if (ps2_key[7:0] == 8'h59) shift_keys_down[1]   <= ps2_key[9];
				if (copy_first_key)        copy_keys_down[0]    <= ps2_key[9];
				if (copy_second_key)       copy_keys_down[1]    <= ps2_key[9];
				if (copy_f6_key)           copy_keys_down[2]    <= ps2_key[9];
				if (copy_f7_key)           copy_keys_down[3]    <= ps2_key[9];
			end
		end
	end

	wire seed = seed_ready && !initialized;
	spaceduel_settings_field #(2) velocity_edit (
		.*, .set(seed), .target(VELOCITY_100),
		.old_value(stored[VELOCITY_LSB +: 2]), .new_value(incoming[VELOCITY_LSB +: 2]),
		.value(velocity_setting), .pending(pending[3])
	);
	spaceduel_settings_field #(3) profile_edit (
		.*, .set(profile_press), .target(cycle_profile(profile, profile_next_key)),
		.old_value(stored[PROFILE_LSB +: 3]), .new_value(incoming[PROFILE_LSB +: 3]),
		.value(selected_profile), .pending(pending[0])
	);
	spaceduel_settings_field #(1 + PROFILE_BITS) custom1_edit (
		.*, .set(seed || copy_to[0]),
		.target({1'b1, copy_to[0] ? selected_settings :
		          custom1_default}),
		.old_value({stored[CUSTOM_INIT_BIT], read_custom(stored, 1'b0)}),
		.new_value({incoming[CUSTOM_INIT_BIT], read_custom(incoming, 1'b0)}),
		.value({slot_valid[0], custom1_status}), .pending(pending[1])
	);
	spaceduel_settings_field #(1 + PROFILE_BITS) custom2_edit (
		.*, .set(seed || copy_to[1]),
		.target({1'b1, copy_to[1] ? selected_settings :
		          custom2_default}),
		.old_value({stored[CUSTOM_INIT_BIT], read_custom(stored, 1'b1)}),
		.new_value({incoming[CUSTOM_INIT_BIT], read_custom(incoming, 1'b1)}),
		.value({slot_valid[1], custom2_status}), .pending(pending[2])
	);
	always_comb begin
		status                    = write_custom(write_custom(stored, 1'b0, custom1_status),
		                                         1'b1, custom2_status);
		status[PROFILE_LSB +: 3]  = profile;
		status[CUSTOM_INIT_BIT]   = initialized;
		status[VELOCITY_LSB +: 2] = velocity_setting;
	end
	assign reply_pending   = can_reply && (|pending);
	assign custom_editable = can_reply && stored[CUSTOM_INIT_BIT];
	always_comb begin
		menu_mask       = '0;
		menu_mask[0]    = rate_sync || direct_video;
		menu_mask[1]    = direct_video;
		menu_mask[2]    = mode_sync[3] && !mode_sync[4];
		menu_mask[3]    = mode_sync[1:0] == 2'd1 && !mode_sync[2];
		menu_mask[4]    = mode_sync[3] && mode_sync[1:0] == 2'd0 && !mode_sync[2];
		menu_mask[5]    = custom_selected && selected_settings.bloom_width == BLOOM_OFF;
		menu_mask[6]    = custom_selected && selected_settings.halo_filter == HALO_OFF;
		menu_mask[7]    = stored[ST_BYPASS];
		menu_mask[11:9] = profile;
		menu_mask[12]   = custom_editable && custom_selected;
		menu_mask[13]   = mode_sync[1:0] < 2'd2 && !mode_sync[2];
		menu_mask[15]   = mode_sync[4];
	end

	logic info_pending = 0, info_is_copy = 0, info_copy_target = 0;
	always_ff @(posedge clk_sys) begin
		info_req <= 0;
		if (reset || osd_open || clear_settings) info_pending <= 0;
		else if (copy_press || profile_press) begin
			info_pending     <= 1;
			info_is_copy     <= copy_press;
			info_copy_target <= copy_to[1];
		end else if (info_pending && !(|pending) && !seed) begin
			info_pending <= 0;
			info_req     <= 1;
			info         <= info_is_copy ? (info_copy_target ? 8'd9 : 8'd8)
			                             : 8'd1 + {5'd0, profile};
		end
	end
endmodule

// Keep local edits pending until MiSTer Main acknowledges them
// or sends an independent change to the same settings field.
module spaceduel_settings_field #(parameter WIDTH = 1) (
	input  wire              clk_sys, commit, echo, clear_settings, set,
	input  wire  [WIDTH-1:0] target, old_value, new_value,
	output wire  [WIDTH-1:0] value,
	output logic             pending = 0
);
	logic  [WIDTH-1:0] wanted;
	assign             value = pending ? wanted : old_value;
	always_ff @(posedge clk_sys) begin
		if (clear_settings) pending <= 0;
		else if (set) begin
			wanted  <= target;
			pending <= pending || target != (commit ? new_value : old_value);
		end else if (commit && ((new_value == wanted) || (!echo && new_value != old_value)))
			pending <= 0;
	end
endmodule

`default_nettype wire
