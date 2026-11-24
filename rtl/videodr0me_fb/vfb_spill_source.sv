// ============================================================================
// Local bloom excitation from the post-decay display pixel.
// Written 2026 by Videodr0me
//
// Bloom excitation is ready after three pixel enables.
// ============================================================================
module vfb_spill_source (
	input  logic        clk_sys,
	input  logic        ce_pix,
	input  logic [15:0] canonical_in,
	input  logic [9:0]  bloom_curve_gain,
	output logic [23:0] bloom_rgb
);
	import vfb_spill_bloom_pkg::*;
	import vfb_layout_pkg::*;

	(* romstyle = "M10K" *) logic [14:0] seeds [0:511];
	initial begin
		for (int i = 0; i < 512; i = i + 1)
			seeds[i] = spill_seed_value(9'(i));
	end

	logic [14:0] seed_rom_q;
	logic [2:0]  mask_rom_q;
	// Separate the block-ROM output from the gain and color-selection arithmetic.
	(* preserve, dont_retime *) logic [14:0] seed_q;
	logic [2:0] mask_q;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			seed_rom_q <= seeds[canonical_in[8:0]];
			mask_rom_q <= canonical_in[15:13];
			seed_q     <= seed_rom_q;
			mask_q     <= mask_rom_q;
		end
	end

	wire [7:0] native_drive = vfb_apply_curve_gain(seed_q[14:7], bloom_curve_gain);
	wire [7:0] spill_drive  = vfb_apply_curve_gain({1'b0, seed_q[6:0]}, bloom_curve_gain);

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			bloom_rgb <= {mask_q[2] ? native_drive : spill_drive,
			              mask_q[1] ? native_drive : spill_drive,
			              mask_q[0] ? native_drive : spill_drive};
		end
	end
endmodule
