// Source brightness and drawing-speed compensation before raster deduplication.
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

module spaceduel_beam_energy (
	input  wire                clk, reset,
	input  wire          [1:0] mode, brightness_mode,
	input  wire signed  [22:0] step_x, step_y,
	input  wire         [10:0] x_in, y_in,
	input  wire          [7:0] z_in,
	input  wire          [2:0] color_in,
	input  wire                dot_in, beam_in, eof_in,
	output wire         [10:0] x_out, y_out,
	output logic         [8:0] energy_out,
	output wire          [2:0] color_out,
	output wire                dot_out, beam_out, eof_out
);
	import vfb_control_pkg::*;

	typedef struct packed {
		logic [10:0] x, y;
		logic  [7:0] z;
		logic  [2:0] color;
		logic        dot, beam, eof;
	} sample_t;
	sample_t    sample_q [0:4];
	logic [1:0] mode_q       = VELOCITY_100;
	logic [1:0] brightness_q = BRIGHTNESS_OFF;
	always_ff @(posedge clk) begin
		mode_q       <= mode;
		brightness_q <= brightness_mode;
	end

	// Source curve for the Bright setting, applied before velocity compensation.
	// The packed constant is used only while constructing the synchronous ROM.
	localparam logic [2047:0] BRIGHT_SOURCE = {
		8'd0, 8'd2, 8'd3, 8'd5, 8'd7, 8'd9, 8'd10, 8'd12,
		8'd14, 8'd15, 8'd17, 8'd19, 8'd21, 8'd22, 8'd24, 8'd26,
		8'd27, 8'd29, 8'd31, 8'd33, 8'd34, 8'd36, 8'd38, 8'd39,
		8'd41, 8'd43, 8'd45, 8'd46, 8'd48, 8'd50, 8'd52, 8'd54,
		8'd56, 8'd58, 8'd60, 8'd62, 8'd64, 8'd66, 8'd68, 8'd70,
		8'd72, 8'd74, 8'd76, 8'd78, 8'd80, 8'd82, 8'd84, 8'd86,
		8'd88, 8'd90, 8'd92, 8'd94, 8'd96, 8'd98, 8'd100, 8'd102,
		8'd104, 8'd106, 8'd108, 8'd110, 8'd112, 8'd114, 8'd116, 8'd118,
		8'd120, 8'd122, 8'd124, 8'd126, 8'd128, 8'd130, 8'd132, 8'd134,
		8'd136, 8'd138, 8'd140, 8'd142, 8'd144, 8'd146, 8'd148, 8'd150,
		8'd152, 8'd154, 8'd156, 8'd158, 8'd160, 8'd162, 8'd164, 8'd166,
		8'd168, 8'd170, 8'd172, 8'd174, 8'd176, 8'd178, 8'd180, 8'd182,
		8'd184, 8'd186, 8'd188, 8'd190, 8'd192, 8'd194, 8'd196, 8'd198,
		8'd200, 8'd202, 8'd204, 8'd206, 8'd208, 8'd210, 8'd212, 8'd214,
		8'd216, 8'd216, 8'd217, 8'd217, 8'd217, 8'd217, 8'd218, 8'd218,
		8'd218, 8'd219, 8'd219, 8'd219, 8'd219, 8'd220, 8'd220, 8'd220,
		8'd221, 8'd221, 8'd221, 8'd221, 8'd222, 8'd222, 8'd222, 8'd223,
		8'd223, 8'd223, 8'd223, 8'd224, 8'd224, 8'd224, 8'd225, 8'd225,
		8'd225, 8'd225, 8'd226, 8'd226, 8'd226, 8'd227, 8'd227, 8'd227,
		8'd227, 8'd228, 8'd228, 8'd228, 8'd229, 8'd229, 8'd229, 8'd229,
		8'd230, 8'd230, 8'd230, 8'd231, 8'd231, 8'd231, 8'd231, 8'd232,
		8'd232, 8'd233, 8'd233, 8'd234, 8'd234, 8'd235, 8'd235, 8'd236,
		8'd236, 8'd237, 8'd237, 8'd238, 8'd239, 8'd239, 8'd240, 8'd240,
		8'd241, 8'd241, 8'd242, 8'd242, 8'd243, 8'd244, 8'd244, 8'd245,
		8'd245, 8'd246, 8'd246, 8'd247, 8'd247, 8'd248, 8'd248, 8'd249,
		8'd250, 8'd250, 8'd251, 8'd251, 8'd252, 8'd252, 8'd253, 8'd253,
		8'd254, 8'd254, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255,
		8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255,
		8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255,
		8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255,
		8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255,
		8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255, 8'd255
	};

	function automatic logic [7:0] source_value(input integer native_z, input logic [1:0] tone);
		integer scaled;
		begin
			scaled = (native_z * 225 + 127) / 255;
			case (tone)
				BRIGHTNESS_LINEAR2: source_value = 8'(native_z);
				BRIGHTNESS_BRIGHT:  source_value = BRIGHT_SOURCE[(255 - scaled) * 8 +: 8];
				default:            source_value = 8'(scaled); // Off and Linear 1
			endcase
		end
	endfunction

	(* romstyle = "M10K" *) logic [7:0] source_rom [0:1023];
	initial begin
		for (int i = 0; i < 1024; i = i + 1)
			source_rom[i] = source_value(i & 255, 2'(i >> 8));
	end
	logic [7:0] source_lut, source_level_q;
	always_ff @(posedge clk) source_lut <= source_rom[{brightness_q, sample_q[0].z}];

	// The drawer latches its command one clock after AVG intensity changes.
	// Stage 0 retains that first sample until its actual increments are available.
	// Keep the commanded slope during endpoint holds; do not add dwell energy.
	logic [22:0] abs_x, abs_y, rounded_x, rounded_y;
	logic [14:0] major_step, minor_step;
	logic [21:0] axis_norm, diagonal_norm, speed_q16, rounded_speed;
	logic        stationary_q;
	always_comb begin
		abs_x         = step_x[22] ? -$unsigned(step_x) : $unsigned(step_x);
		abs_y         = step_y[22] ? -$unsigned(step_y) : $unsigned(step_y);
		rounded_x     = abs_x + 23'd128;
		rounded_y     = abs_y + 23'd128;
		major_step    = rounded_x[22:8] > rounded_y[22:8] ? rounded_x[22:8] : rounded_y[22:8];
		minor_step    = rounded_x[22:8] > rounded_y[22:8] ? rounded_y[22:8] : rounded_x[22:8];
		axis_norm     = ({7'd0, major_step} << 6) + ({7'd0, minor_step} << 3);
		diagonal_norm = ({7'd0, major_step} << 6) - ({7'd0, major_step} << 3) +
		                ({7'd0, minor_step} << 5) + {7'd0, minor_step};
		rounded_speed = speed_q16 + 22'd128;
	end

	// Q8 speed index k represents k/256 native coordinate units per clock.
	// Full gain is clamp(2/speed, 1, 4), rounded to Q8. Division is constant
	// ROM initialization only. Stationary commands and speeds >= 2 use unity.
	(* romstyle = "M10K" *) logic [10:0] gain_rom [0:511];
	initial begin
		for (int k = 0; k < 512; k = k + 1)
			if (k <= 128) gain_rom[k] = 11'd1024;
			else          gain_rom[k] = 11'((131072 + k / 2) / k);
	end
	logic [10:0] gain_lut_q8;
	logic        gain_unity_q;
	wire  [10:0] gain_q8 = gain_unity_q ? 11'd256 : gain_lut_q8;
	// Keep the registered ROM read free of reset and data selection so Quartus
	// can use a block ROM. The unity flag follows the same lookup stage.
	always_ff @(posedge clk) gain_lut_q8 <= gain_rom[rounded_speed[16:8]];

	// Q10 represents all four strengths exactly, including a full 4x gain.
	logic [12:0] gain_extra, applied_gain_q10;
	logic [19:0] energy_product;
	always_comb begin
		gain_extra = {2'd0, gain_q8} - 13'd256;
		case (mode_q)
			VELOCITY_050: applied_gain_q10 = 13'd1024 + (gain_extra << 1);
			VELOCITY_075: applied_gain_q10 = 13'd1024 + (gain_extra << 1) + gain_extra;
			VELOCITY_100: applied_gain_q10 = {gain_q8, 2'b00};
			default:      applied_gain_q10 = 13'd1024;
		endcase
	end

	// Five sample registers align coordinates, color, flags and EOF with energy.
	// The latency is fixed in every mode, including Off.
	always_ff @(posedge clk) begin
		if (reset) begin
			for (int i = 0; i < 5; i = i + 1) sample_q[i] <= '0;
			speed_q16      <= 22'd0;
			stationary_q   <=  1'b1;
			gain_unity_q   <=  1'b1;
			source_level_q <=  8'd0;
			energy_product <= 20'd0;
			energy_out     <=  9'd0;
		end else begin
			sample_q[0] <= {x_in, y_in, z_in, color_in, dot_in, beam_in, eof_in};
			for (int i = 1; i < 5; i = i + 1) sample_q[i] <= sample_q[i-1];
			speed_q16    <= axis_norm > diagonal_norm ? axis_norm : diagonal_norm;
			stationary_q <= step_x == 23'sd0 && step_y == 23'sd0;
			gain_unity_q <= stationary_q || rounded_speed >= 22'd131072;
			// Reset clears the sample tags; do not reuse an earlier ROM response.
			source_level_q <= sample_q[1].z == 8'd0 ? 8'd0 : source_lut;
			energy_product <= source_level_q * applied_gain_q10 + 20'd512;
			energy_out     <= energy_product[19] ? 9'd511 : energy_product[18:10];
		end
	end

	assign x_out     = sample_q[4].x;
	assign y_out     = sample_q[4].y;
	assign color_out = sample_q[4].color;
	assign dot_out   = sample_q[4].dot;
	assign beam_out  = sample_q[4].beam;
	assign eof_out   = sample_q[4].eof;
endmodule

`default_nettype wire
