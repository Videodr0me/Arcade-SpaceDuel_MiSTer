// Space Duel PCB analog audio filter and mixer (Atari SP-181, second printing, sheet 5B).
// Copyright (C) 2026 Videodr0me
// SPDX-License-Identifier: GPL-3.0-or-later

module spaceduel_audio_filter (
	input  logic               clk,
	input  logic               reset,
	input  logic               ce,
	input  logic         [7:0] pokey_a,
	input  logic         [7:0] pokey_b,
	output logic signed [15:0] audio = 16'sd0
);
	// One update per 1.512 MHz POKEY clock. States are DAC units with 22
	// fractional bits. Coefficients are round((1-exp(-1/(fs*R*C)))*2^28).
	localparam logic signed [28:0] A_LOW_COEFF       = 29'sd805773;  // 1k, 0.22 uF
	localparam logic signed [28:0] A_DC_COEFF        = 29'sd206839;  // 3.9k, 0.22 uF
	localparam logic signed [28:0] B_DC_COEFF        =   29'sd8070;  // 100k, 0.22 uF
	localparam logic signed [28:0] B_LOW_COEFF       = 29'sd177478;  // 1M, 1 nF
	localparam logic signed [28:0] B_POST_CLIP_COEFF = 29'sd177478;  // 1M, C28 = 1 nF
	localparam logic signed [18:0] B_GAIN            = 19'sd255590;  // 3.9 in Q16

	// Op-amp -15/+13.5 V clipping rails referred to the input of the 10x
	// inverting stage; max single-channel volume (60 DAC units) equals 2.33344 V.
	localparam logic signed [33:0] RAIL_13V5 = 34'sd145595546;
	localparam logic signed [33:0] RAIL_15V0 = 34'sd161772829;

	function automatic logic signed [33:0] lowpass_next(
		input logic signed [33:0] value, previous,
		input logic signed [28:0] coefficient);
		logic signed [34:0] difference, next_value;
		logic signed [63:0] product, increment;
		begin
			difference   = {value[33], value} - {previous[33], previous};
			product      = difference * coefficient;
			increment    = (product + 64'sd134217728) >>> 28;
			next_value   = {previous[33], previous} + increment[34:0];
			lowpass_next = next_value[33:0];
		end
	endfunction

	logic signed [33:0] a_low = 34'sd0, a_dc = 34'sd0, a_ac = 34'sd0;
	logic signed [33:0] a_delay_1 = 34'sd0, a_delay_2 = 34'sd0, a_delay_3 = 34'sd0;
	logic signed [33:0] b_dc = 34'sd0, b_ac = 34'sd0, b_low = 34'sd0;
	logic signed [33:0] b_clipped = 34'sd0, b_post_clip = 34'sd0;
	logic signed [52:0] b_product = 53'sd0;
	wire  signed [33:0] a_input   = {4'd0, pokey_a, 22'd0};
	wire  signed [33:0] b_input   = {4'd0, pokey_b, 22'd0};
	wire  signed [33:0] a_dc_next = lowpass_next(a_low, a_dc, A_DC_COEFF);
	wire  signed [33:0] b_output  = b_post_clip > RAIL_13V5 ? RAIL_13V5 :
	                                b_post_clip < -RAIL_15V0 ? -RAIL_15V0 : b_post_clip;
	wire  signed [52:0] b_scaled  = (b_product + 53'sd32768) >>> 16;
	wire  signed [34:0] mixed     = {a_delay_3[33], a_delay_3} + b_scaled[34:0];
	wire  signed [34:0] pcm       = (mixed + 35'sd32768) >>> 16;

	// Registered stages keep each feedback path to one constant multiply and
	// add in clk_12. Both branches have the same six-sample transport delay.
	// Run continuously, including bypass and pause, so the filter stays settled.
	always_ff @(posedge clk) begin
		if (reset) begin
			a_low       <= 34'sd0;
			a_dc        <= 34'sd0;
			a_ac        <= 34'sd0;
			a_delay_1   <= 34'sd0;
			a_delay_2   <= 34'sd0;
			a_delay_3   <= 34'sd0;
			b_dc        <= 34'sd0;
			b_ac        <= 34'sd0;
			b_low       <= 34'sd0;
			b_clipped   <= 34'sd0;
			b_post_clip <= 34'sd0;
			b_product   <= 53'sd0;
			audio       <= 16'sd0;
		end else if (ce) begin
			// Branch A: low-pass, then AC coupling using the updated DC estimate.
			a_low     <= lowpass_next(a_input, a_low, A_LOW_COEFF);
			a_dc      <= a_dc_next;
			a_ac      <= a_low - a_dc_next;
			a_delay_1 <= a_ac;
			a_delay_2 <= a_delay_1;
			a_delay_3 <= a_delay_2;

			// Branch B subtracts the previous DC estimate before low-pass filtering.
			b_dc        <= lowpass_next(b_input, b_dc, B_DC_COEFF);
			b_ac        <= b_input - b_dc;
			b_low       <= lowpass_next(b_ac, b_low, B_LOW_COEFF);
			b_clipped   <= b_low > RAIL_15V0 ? RAIL_15V0 : b_low < -RAIL_13V5 ? -RAIL_13V5 : b_low;
			b_post_clip <= lowpass_next(b_clipped, b_post_clip, B_POST_CLIP_COEFF);
			b_product   <= b_output * B_GAIN;

			if (pcm > 35'sd32767)       audio <= 16'sh7fff;
			else if (pcm < -35'sd32768) audio <= 16'sh8000;
			else                       audio <= pcm[15:0];
		end
	end
endmodule
