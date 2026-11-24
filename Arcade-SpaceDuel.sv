//============================================================================
//  Atari Space Duel for MiSTer
//
//  Written 2026 by Videodr0me
//
//  Original arcade hardware by Atari, 1982.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

	`include "build_id.v"
	import vfb_control_pkg::*;

	logic [127:0] status;
	logic  [31:0] joystick_0;
	logic  [31:0] joystick_1;
	logic  [31:0] joystick;
	logic   [1:0] buttons;
	logic         direct_video;
	wire   [21:0] gamma_bus;

	logic         ioctl_download;
	logic         ioctl_upload;
	logic         ioctl_upload_req;
	logic         ioctl_wr;
	logic         ioctl_rd;
	logic  [26:0] ioctl_addr;
	logic   [7:0] ioctl_dout;
	logic   [7:0] ioctl_din;
	logic  [15:0] ioctl_index;
	wire          rom_download   = ioctl_download && (ioctl_index == 16'd0);
	wire          nvram_file     = ioctl_index == 16'd4;
	wire          nvram_download = nvram_file && ioctl_download;
	wire          nvram_upload   = nvram_file && ioctl_upload;

	logic clk_12;
	logic clk_render;
	logic pll_locked;

	wire [127:0] main_status, stored_status;
	tri [35:0] extension_bus;
	wire                   settings_commit, settings_echo, settings_clear, capture_reply, settings_valid;
	wire                   reply_pending, custom_editable, profile_info_req;
	wire  [7:0]            profile_info;
	wire  [10:0]           ps2_key;
	wire  [15:0]           menu_mask;
	wire  [2:0]            profile;
	wire  [1:0]            profile_resolution;
	vfb_profile_settings_t custom_1_settings, custom_2_settings, resolved_settings;
	logic                  video_supports_120hz, video_supports_test_format;
	logic                  video_is_15khz, video_field;
	logic                  video_mode_restart, video_mode_toggle, video_freeze;
	logic                  rom_loaded = 1'b0;

	always_ff @(posedge clk_12)
		if (rom_download && ioctl_wr) rom_loaded <= 1'b1;

	spaceduel_status_guard status_guard (
		.clk_sys(clk_12), .ext_bus(extension_bus), .incoming(main_status),
		.reply_pending(reply_pending), .reply_zero(status == 128'd0),
		.stored(stored_status), .commit(settings_commit), .echo(settings_echo),
		.clear_settings(settings_clear), .capture(capture_reply), .settings_valid(settings_valid)
	);

	spaceduel_profile_control profile_control (
		.clk_sys(clk_12), .reset(RESET || !pll_locked || rom_download),
		.commit(settings_commit), .echo(settings_echo), .clear_settings(settings_clear),
		.stored(stored_status), .incoming(main_status),
		.settings_ready(settings_valid && rom_loaded && !rom_download),
		.video_resolution(profile_resolution), .video_freeze(video_freeze),
		.video_is_15khz(video_is_15khz), .direct_video(direct_video),
		.video_supports_120hz(video_supports_120hz),
		.video_supports_test_format(video_supports_test_format),
		.osd_open(OSD_STATUS), .ps2_key(ps2_key),
		.custom_1_settings(custom_1_settings), .custom_2_settings(custom_2_settings),
		.resolved_settings(resolved_settings), .profile(profile), .status(status),
		.reply_pending(reply_pending), .custom_editable(custom_editable), .menu_mask(menu_mask),
		.info_req(profile_info_req), .info(profile_info)
	);

	localparam CONF_STR = {
		"Space Duel;;",
		"-;",
		"H7P1,Video Profiles & Effects;",
		"P1O[14:12],Profile,80s Cruise Control,80s Overdrive,Neon Fever,Plasma Storm,Custom 1,Custom 2,A Touch of CRT;",
		"H9HAHBP1-;",
		"H9HAHBP1-,Step away from the modern..;",
		"H9HAHBP1-,Richer halos and blooming;",
		"H9HAHBP1-,bring back the arcade glow.;",
		"H9HAHBP1-,HD presets (720p/1080p) add;",
		"H9HAHBP1-,WG6100 color conversion and;",
		"H9HAHBP1-,a faint vertical slot mask.;",
		"H9HAHBP1-;",
		"H9HAHBP1-,For advanced settings;",
		"H9HAHBP1-,select Custom Profiles 1/2;",
		"h9HAHBP1-;",
		"h9HAHBP1-,The phosphor runs hotter.;",
		"h9HAHBP1-,Even faint sparks stand out.;",
		"h9HAHBP1-,The linked ships leave arcs;",
		"h9HAHBP1-,of light as they swing.;",
		"h9HAHBP1-,HD presets (720p/1080p);",
		"h9HAHBP1-,hold those trails longer.;",
		"h9HAHBP1-;",
		"h9HAHBP1-,For advanced settings;",
		"h9HAHBP1-,select Custom Profiles 1/2;",
		"H9hAHBP1-;",
		"H9hAHBP1-,Midnight arcade. Voltage up.;",
		"H9hAHBP1-,Cubes tumble in gently;",
		"H9hAHBP1-,flickering neon light.;",
		"H9hAHBP1-,Shoot one and the fragments;",
		"H9hAHBP1-,leave trails of color.;",
		"H9hAHBP1-,Bright lights and flashing.;",
		"H9hAHBP1-;",
		"H9hAHBP1-,For advanced settings;",
		"H9hAHBP1-,select Custom Profiles 1/2;",
		"h9hAHBP1-;",
		"h9hAHBP1-,A storm across the phosphor.;",
		"h9hAHBP1-,One ship erupts. Sparks race;",
		"h9hAHBP1-,down the fuse to the other.;",
		"h9hAHBP1-,Both blasts cast broad halos;",
		"h9hAHBP1-,and leave trails of light.;",
		"h9hAHBP1-;",
		"h9hAHBP1-,      Epilepsy warning;",
		"h9hAHBP1-,    excessive flashing;",
		"h9hAHBP1-,       bright lights;",
		"h9hAHBP1-;",
		"h9hAHBP1-,For advanced settings;",
		"h9hAHBP1-,select Custom Profiles 1/2;",
		"H9hAhBP1-;",
		"H9hAhBP1-,Modern clarity with a touch;",
		"H9hAhBP1-,of old. Subtle halo & bloom;",
		"H9hAhBP1-,while vectors stay crisp.;",
		"H9hAhBP1-;",
		"H9hAhBP1-,For advanced settings;",
		"H9hAhBP1-,select Custom Profiles 1/2;",
		"hCH9P1O[26:24],> Dot Scale,1x,1.5x,2x,2.5x,3x,4x,5x;",
		"hCH9P1O[17:16],> Brightness,Off,Linear 1,Linear 2,Bright;",
		"hCH9P1O[33:31],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hCH9H5P1O[36:34],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hCH9P1O[39:37],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hCH9H6P1O[42:40],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hCH9H6P1O[44:43],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
		"hCH9H6P1O[47:45],> Halo Compression,Off,2,4,6,8,16,24,32;",
		"hCH9H6P1O[48],> Halo Grid,16x16,8x8;",
		"hCH9P1O[28:27],> Inter-Frame Decay,Off,Short,Medium,Long;",
		"hCH9P1O[30:29],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"hCH9P1O[21],> Color Space,Original,WG6100->709;",
		"hCH9P1O[20:18],> Color Channels,RGB,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hCH9P1O[23:22],> Slot Mask,Off,Mild,Medium,Max;",
		"hCh9P1O[90:88],> Dot Scale,1x,1.5x,2x,2.5x,3x,4x,5x;",
		"hCh9P1O[81:80],> Brightness,Off,Linear 1,Linear 2,Bright;",
		"hCh9P1O[97:95],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hCh9H5P1O[100:98],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hCh9P1O[103:101],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hCh9H6P1O[106:104],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hCh9H6P1O[108:107],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
		"hCh9H6P1O[111:109],> Halo Compression,Off,2,4,6,8,16,24,32;",
		"hCh9H6P1O[112],> Halo Grid,16x16,8x8;",
		"hCh9P1O[92:91],> Inter-Frame Decay,Off,Short,Medium,Long;",
		"hCh9P1O[94:93],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"hCh9P1O[85],> Color Space,Original,WG6100->709;",
		"hCh9P1O[84:82],> Color Channels,RGB,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hCh9P1O[87:86],> Slot Mask,Off,Mild,Medium,Max;",
		"P2,Video Timing & Geometry;",
		"P2O[77:75],Orientation,Normal,Rotate 90 CW,Rotate 180,Rotate 90 CCW,Mirror Horizontal,Mirror Vertical,Mirror H + 90 CW,Mirror H + 90 CCW;",
		"P2O[64],Zoom,Normal,Wide;",
		"P2-;",
		"d0D1P2O[56],120Hz (720p only),Off,On;",
		"P2O[63],61.52Hz (Authentic),Off,On;",
		"h1P2O[55],Direct Video Scan Rate,15 kHz,31 kHz;",
		"h2P2O[54],15 kHz Format,480i,240p;",
		"h3P2O[59:57],CRT Vertical Position,0,+4,+8,+12,-4,-8,-10;",
		"h4P2O[59:57],CRT Vertical Position,0,+2,+4,+6,-2,-4,-6;",
		"hDP2O[62:60],CRT Horizontal Position,0,+1,+2,+3,-1,-2,-3;",
		"P2-;",
		"P2O[79:78],Aspect Ratio,Optimized,Stretched,Pixel Perfect;",
		"-;",
		"P3,System;",
		"P3O[1],Autosave NVRAM,On,Off;",
		"P3T[4],Save NVRAM;",
		"P3-;",
		"P3O[5],Pause when OSD is open,Off,On;",
		"P3O[6],Dim video after 60s,On,Off;",
		"P3-;",
		"P3O[10],PCB Audio Filter,On,Off;",
		"P3-;",
		"P3-,Diagnostics:;",
		"P3O[11],Effects Bypass,Off,On;",
		"hFP3O[121:120],SD Test Format,480p,480i,240p;",
		"P3O[127:126],Buffer Mode,EOF + VBL,VBL,EOF;",
		"P3O[9:8],Beam Velocity,Off,0.5,0.75,1.0;",
		"P3O[119:118],B-Spline,B=2.00,Normal,B=1.50,B=1.75;",
		"DIP;",
		"-;",
		"P5,Core Info;",
		"P5-,Space Duel (Atari 1982);",
		"P5-,MiSTer Core by Videodr0me;",
		"P5-;",
		"P5-,Original gameplay with;",
		"P5-,high-resolution CRT effects.;",
		"P5-;",
		"P5-,If you enjoy reliving the;",
		"P5-,golden age of arcade games;",
		"P5-,please support my work and;",
		"P5-,future updates:;",
		"P5-;",
		"P5-,buymeacoffee.com/videodr0me;",
		"-;",
		"R7,Reset;",
		"J1,Fire,Shield,Thrust,Start,Select,Coin,Pause,Coin 2;",
		"jn,A,B,X,Start,Select,R,L,Y;",
		"I,Profile: 80s Cruise Control,Profile: 80s Overdrive,Profile: Neon Fever,Profile: Plasma Storm,Profile: Custom 1,Profile: Custom 2,Profile: A Touch of CRT,Copied to Custom 1,Copied to Custom 2;",
		"V,v0.1.", `BUILD_DATE
	};

	hps_io #(.CONF_STR(CONF_STR)) hps_io_inst (
		.clk_sys(clk_12),
		.HPS_BUS(HPS_BUS),
		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.buttons(buttons),
		.forced_scandoubler(),
		.direct_video(direct_video),
		.new_vmode(video_mode_toggle),
		.gamma_bus(gamma_bus),
		.status(main_status), .status_in(status), .status_set(capture_reply),
		.EXT_BUS(extension_bus), .ps2_key(ps2_key),
		.info_req(profile_info_req), .info(profile_info),
		.status_menumask(menu_mask),
		.ioctl_download(ioctl_download),
		.ioctl_upload(ioctl_upload),
		.ioctl_upload_req(ioctl_upload_req),
		.ioctl_upload_index(8'd4),
		.ioctl_wr(ioctl_wr),
		.ioctl_rd(ioctl_rd),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_din(ioctl_din),
		.ioctl_index(ioctl_index),
		.ioctl_wait(1'b0)
	);

	pll pll (
		.refclk(CLK_50M),
		.rst(1'b0),
		.outclk_0(clk_12),
		.outclk_1(),
		.outclk_2(clk_render),
		.locked(pll_locked)
	);

	logic [7:0] dip_switch [0:3];
	initial begin
		dip_switch[0] = 8'hff;
		dip_switch[1] = 8'hff;
		dip_switch[2] = 8'h0f;
		dip_switch[3] = 8'h00;
	end

	always @(posedge clk_12) begin
		if (ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[26:2])
			dip_switch[ioctl_addr[1:0]] <= ioctl_dout;
	end

	assign joystick = joystick_0 | joystick_1;

	logic [23:0] paused_rgb;
	logic [7:0]  raw_video_r;
	logic [7:0]  raw_video_g;
	logic [7:0]  raw_video_b;
	logic        machine_reset;
	logic        machine_reset_base;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [1:0]  video_mode_restart_12 = 2'b00;
	logic        pause_cpu;
	logic [7:0]  nvram_data_out;
	logic        nvram_modified;
	logic        nvram_dirty         = 1'b0;
	logic        retry_short_save    = 1'b0;
	logic        manual_save_pending = 1'b0;
	wire         nvram_save_start    = nvram_upload && ioctl_rd && (ioctl_addr == 27'd0);

	assign machine_reset_base = RESET || status[ST_MAIN_RESET] || status[ST_GAME_RESET] ||
	                            buttons[1] || rom_download || nvram_download || !pll_locked;

	always_ff @(posedge clk_12)
		video_mode_restart_12 <= {video_mode_restart_12[0], video_mode_restart};

	assign machine_reset = machine_reset_base || video_mode_restart_12[1];

	always_ff @(posedge clk_12) begin
		if (nvram_download) nvram_dirty <= 1'b0;
		else if (nvram_modified || (!nvram_upload && retry_short_save)) nvram_dirty <= 1'b1;
		else if (nvram_save_start) nvram_dirty <= 1'b0;

		// hps_io advances the address with each byte read. Address 64 completes the image.
		if (!nvram_upload || (ioctl_rd && ioctl_addr == 27'd64)) retry_short_save <= 1'b0;
		else if (nvram_save_start && nvram_dirty) retry_short_save <= 1'b1;

		if (settings_commit && main_status[ST_SAVE_NVRAM] && !stored_status[ST_SAVE_NVRAM])
			manual_save_pending <= 1'b1;
		else if (!nvram_upload) manual_save_pending <= 1'b0;
	end

	assign ioctl_upload_req = !nvram_upload &&
	                          ((!status[ST_AUTOSAVE_OFF] && nvram_dirty) || manual_save_pending);
	assign ioctl_din        = nvram_file ? nvram_data_out : 8'h00;

	wire        pause_dim;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [1:0] pause_dim_sync = 2'b00;

	always_ff @(posedge clk_render)
		pause_dim_sync <= {pause_dim_sync[0], pause_dim};

	assign paused_rgb = pause_dim_sync[1] ? {raw_video_r >> 1, raw_video_g >> 1, raw_video_b >> 1}
	                                      : {raw_video_r, raw_video_g, raw_video_b};

	pause #(.RW(8), .GW(8), .BW(8), .CLK_HZ(12_096_000)) pause_inst (
		.clk_sys(clk_12),
		.reset(machine_reset),
		.user_button(joystick[10]),
		.pause_request(1'b0),
		.options({~status[ST_DIM], status[ST_OSD_PAUSE]}),
		.OSD_STATUS(OSD_STATUS),
		.r(8'd0),
		.g(8'd0),
		.b(8'd0),
		.pause_cpu(pause_cpu),
		.dim_video(pause_dim),
		.rgb_out()
	);

	logic signed [15:0] machine_audio;
	logic signed [14:0] avg_x;
	logic signed [14:0] avg_y;
	logic signed [22:0] avg_step_x, avg_step_y;
	logic         [7:0] avg_z;
	logic         [2:0] avg_rgb;
	logic               avg_is_dot;
	logic               avg_halted;
	logic               hardware_flip_x;
	logic               hardware_flip_y;

	spaceduel_core machine (
		.clk_12(clk_12),
		.reset(machine_reset),
		.pause(pause_cpu),
		.audio_filter_off(status[ST_AUDIO_FILTER_OFF]),
		.coin_1(joystick[9]),
		.coin_2(joystick[11]),
		.service(dip_switch[3][1]),
		.diagnostic_step(dip_switch[3][2]),
		.cabinet_cocktail(dip_switch[3][0]),
		.cabinet_options(dip_switch[2][2:0]),
		.dsw_d4(dip_switch[0]),
		.dsw_b4(dip_switch[1]),
		.p1_left(joystick_0[1]),
		.p1_right(joystick_0[0]),
		.p1_fire(joystick_0[4]),
		.p1_shield(joystick_0[5]),
		.p1_thrust(joystick_0[6]),
		.p1_start(joystick[7]),
		.p1_select(joystick[8]),
		.p2_left(joystick_1[1]),
		.p2_right(joystick_1[0]),
		.p2_fire(joystick_1[4]),
		.p2_shield(joystick_1[5]),
		.p2_thrust(joystick_1[6]),
		.rom_write(ioctl_wr && rom_download),
		.rom_address(ioctl_addr[15:0]),
		.rom_data(ioctl_dout),
		.nvram_address(ioctl_addr[5:0]),
		.nvram_data_in(ioctl_dout),
		.nvram_write(nvram_download && ioctl_wr),
		.nvram_data_out(nvram_data_out),
		.nvram_modified(nvram_modified),
		.audio(machine_audio),
		.x_out(avg_x),
		.y_out(avg_y),
		.step_x_out(avg_step_x),
		.step_y_out(avg_step_y),
		.intensity_out(avg_z),
		.rgb_out(avg_rgb),
		.is_dot(avg_is_dot),
		.avg_halted(avg_halted),
		.flip_x(hardware_flip_x),
		.flip_y(hardware_flip_y)
	);

	logic        sdram_data_oe;
	logic [15:0] sdram_data_out;
	logic  [1:0] sdram_dqm;
	logic        video_hblank;
	logic        video_vblank;
	logic        fifo_high_water;

	assign SDRAM_CLK  = ~clk_render;
	assign SDRAM_DQ   = sdram_data_oe ? sdram_data_out : 16'hzzzz;
	assign SDRAM_DQML = sdram_dqm[0];
	assign SDRAM_DQMH = sdram_dqm[1];

	spaceduel_video video (
		.clk_12(clk_12),
		.clk_50(CLK_50M),
		.clk_render(clk_render),
		.reset(machine_reset),
		.ddr_reset(machine_reset),
		.init_reset(!pll_locked),
		.direct_video(direct_video),
		.direct_video_31khz(status[ST_DIRECT_31KHZ]),
		.hdmi_height(HDMI_HEIGHT),
		.mode_120hz(status[ST_120HZ]),
		.authentic_timing(status[ST_AUTHENTIC]),
		.crt_15khz_480i(!status[ST_CRT_240P]),
		.test_video_format(direct_video ? 2'd0 : status[TEST_FORMAT_LSB +: 2]),
		.crt_vertical_position(status[CRT_VERTICAL_LSB +: 3]),
		.crt_horizontal_position(status[CRT_HORIZONTAL_LSB +: 3]),
		.aspect_ratio(status[ASPECT_LSB +: 2]),
		.buffer_mode(status[BUFFER_MODE_LSB +: 2]),
		.geometry_orientation(status[ORIENTATION_LSB +: 3]),
		.geometry_zoom_wide(status[ST_ZOOM_WIDE]),
		.profile_settings(resolved_settings),
		.effects_bypass(status[ST_BYPASS]),
		.velocity_comp(status[VELOCITY_LSB +: 2]),
		.halo_shape(status[HALO_SHAPE_LSB +: 2] + 2'd3),
		.avg_x(avg_x),
		.avg_y(avg_y),
		.avg_step_x(avg_step_x),
		.avg_step_y(avg_step_y),
		.avg_z(avg_z),
		.avg_rgb(avg_rgb),
		.avg_is_dot(avg_is_dot),
		.avg_halted(avg_halted),
		.hardware_flip_x(hardware_flip_x),
		.hardware_flip_y(hardware_flip_y),
		.frame_done(avg_halted),
		.video_arx(VIDEO_ARX),
		.video_ary(VIDEO_ARY),
		.ce_pixel(CE_PIXEL),
		.hblank(video_hblank),
		.vblank(video_vblank),
		.video_r(raw_video_r),
		.video_g(raw_video_g),
		.video_b(raw_video_b),
		.hsync(VGA_HS),
		.vsync(VGA_VS),
		.field(video_field),
		.mode_supports_120hz(video_supports_120hz),
		.profile_resolution(profile_resolution),
		.mode_supports_test_format(video_supports_test_format),
		.mode_is_15khz(video_is_15khz),
		.fifo_high_water(fifo_high_water),
		.video_mode_toggle(video_mode_toggle),
		.video_freeze(video_freeze),
		.mode_restart(video_mode_restart),
		.ddram_clk(DDRAM_CLK),
		.ddram_busy(DDRAM_BUSY),
		.ddram_burst_count(DDRAM_BURSTCNT),
		.ddram_address(DDRAM_ADDR),
		.ddram_data_out(DDRAM_DOUT),
		.ddram_data_ready(DDRAM_DOUT_READY),
		.ddram_read(DDRAM_RD),
		.ddram_data_in(DDRAM_DIN),
		.ddram_byte_enable(DDRAM_BE),
		.ddram_write(DDRAM_WE),
		.sdram_data_in(SDRAM_DQ),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(SDRAM_CKE),
		.sdram_ncs(SDRAM_nCS),
		.sdram_nras(SDRAM_nRAS),
		.sdram_ncas(SDRAM_nCAS),
		.sdram_nwe(SDRAM_nWE),
		.sdram_dqm(sdram_dqm),
		.sdram_address(SDRAM_A),
		.sdram_bank(SDRAM_BA)
	);

	assign CLK_VIDEO      = clk_render;
	assign VGA_R          = paused_rgb[23:16];
	assign VGA_G          = paused_rgb[15:8];
	assign VGA_B          = paused_rgb[7:0];
	assign VGA_DE         = !(video_hblank || video_vblank);
	assign VGA_F1         = video_field;
	assign VGA_SL         = 2'b00;
	assign VGA_SCALER     =  1'b0;
	assign VGA_DISABLE    =  1'b0;
	assign HDMI_FREEZE    = video_freeze;
	assign HDMI_BLACKOUT  = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;

	assign AUDIO_L   = machine_audio;
	assign AUDIO_R   = machine_audio;
	assign AUDIO_S   =  1'b1;
	assign AUDIO_MIX = 2'b00;

	assign LED_USER  = fifo_high_water || ioctl_download;
	assign LED_DISK  = 2'b00;
	assign LED_POWER = 2'b00;
	assign BUTTONS   = 2'b00;

	assign ADC_BUS  = 4'bzzzz;
	assign USER_OUT =   7'h7f;
	assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
	assign {SD_SCK, SD_MOSI, SD_CS}       = 3'bzzz;

`ifdef MISTER_FB
	assign FB_EN = 1'b0;
	assign FB_FORMAT = 5'd0;
	assign FB_WIDTH = 12'd0;
	assign FB_HEIGHT = 12'd0;
	assign FB_BASE = 32'd0;
	assign FB_STRIDE = 14'd0;
	assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
	assign FB_PAL_CLK = 1'b0;
	assign FB_PAL_ADDR = 8'd0;
	assign FB_PAL_DOUT = 24'd0;
	assign FB_PAL_WR = 1'b0;
`endif
`endif

`ifdef MISTER_DUAL_SDRAM
	assign SDRAM2_CLK = 1'bz;
	assign SDRAM2_A = 13'hzzz;
	assign SDRAM2_BA = 2'bzz;
	assign SDRAM2_DQ = 16'hzzzz;
	assign {SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 4'hf;
`endif

endmodule
