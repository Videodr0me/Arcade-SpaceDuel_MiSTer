// ============================================================================
// Delayed-primary, bloom, and broad-halo video pipeline.
// Written 2026 by Videodr0me
//
// Primary pixels are delayed vertically in external SDRAM and horizontally
// in a short MLAB shift register. The local filter adds bloom while the
// undelayed image generates the broad halo. The two paths are combined at
// the final saturated addition.
// ============================================================================

module vfb_halo_pipeline #(
	parameter integer MAX_WIDTH            = 1472,
	parameter integer SDR_DELAY_LINES      =   87,
	parameter integer SDR_FIFO_DEPTH       =  256,
	parameter integer PRIMARY_H_DELAY      =   42,
	parameter integer PRIMARY_DATA_ADVANCE =    0
) (
	input  logic        clk_sys,
	input  logic        reset,
	input  logic        ce_pix,

	input  logic [2:0]  osd_bloom_width,
	input  logic [9:0]  bloom_curve_gain,
	input  logic [9:0]  halo_curve_gain,
	input  logic [7:0]  halo_filter,
	input  logic [1:0]  halo_spread_mode,
	input  logic [2:0]  halo_knee_mode,
	input  logic [1:0]  halo_shape,
	input  logic        halo_grid_8,
	input  logic [11:0] active_height,
	input  logic        color_space_wg6100_709,
	input  logic [2:0]  presentation_color,
	input  logic [1:0]  slot_mask_mode,
	input  logic        slot_mask_rows,

	input  logic [15:0] CANONICAL_IN,
	input  logic        VGA_HS_IN,
	input  logic        VGA_VS_IN,
	input  logic        VGA_HBLANK_IN,
	input  logic        VGA_VBLANK_IN,

	output logic [7:0]  VGA_R_OUT,
	output logic [7:0]  VGA_G_OUT,
	output logic [7:0]  VGA_B_OUT,
	output logic        VGA_HS_OUT,
	output logic        VGA_VS_OUT,
	output logic        VGA_HBLANK_OUT,
	output logic        VGA_VBLANK_OUT,

	input  logic [15:0] sdram_data_in,
	output logic [15:0] sdram_data_out,
	output logic        sdram_data_oe,
	output logic        sdram_cke,
	output logic        sdram_cs,
	output logic        sdram_ras,
	output logic        sdram_cas,
	output logic        sdram_we,
	output logic [1:0]  sdram_dqm,
	output logic [12:0] sdram_addr,
	output logic [1:0]  sdram_ba,

	output logic        sdram_overflow,
	output logic        sdram_underflow,
	output logic        sdram_init_done
);

	logic [2:0] osd_bloom_width_q        =   3'd0;
	logic [9:0] bloom_curve_gain_q       = 10'd64;
	logic [9:0] halo_curve_gain_q        = 10'd64;
	logic [7:0] halo_filter_q            =   8'd0;
	logic [1:0] halo_spread_mode_q       =   2'd0;
	logic [2:0] halo_knee_mode_q         = vfb_control_pkg::KNEE_16;
	logic [1:0] halo_shape_q             = 2'd3;
	logic       halo_grid_8_q            = 1'b0;
	logic       color_space_wg6100_709_q = 1'b0;
	logic [2:0] presentation_color_q     = 3'd0;
	logic [1:0] slot_mask_mode_q         = 2'd0;
	logic       slot_mask_rows_q         = 1'b0;

	always_ff @(posedge clk_sys) begin
		osd_bloom_width_q        <= osd_bloom_width;
		bloom_curve_gain_q       <= bloom_curve_gain;
		halo_curve_gain_q        <= halo_curve_gain;
		halo_filter_q            <= halo_filter;
		halo_spread_mode_q       <= halo_spread_mode;
		halo_knee_mode_q         <= halo_knee_mode;
		halo_shape_q             <= halo_shape;
		halo_grid_8_q            <= halo_grid_8;
		color_space_wg6100_709_q <= color_space_wg6100_709;
		presentation_color_q     <= presentation_color;
		slot_mask_mode_q         <= slot_mask_mode;
		slot_mask_rows_q         <= slot_mask_rows;
	end

	logic [15:0] delayed_canonical;
	logic        delayed_hs;
	logic        delayed_vs;
	logic        delayed_hblank;
	logic        delayed_vblank;
	wire  [11:0] line_delay = halo_grid_8_q ? vfb_layout_pkg::VFB_HALO_DELAY_8_LINES
	                                        : 12'(SDR_DELAY_LINES);
	// Discard coarse history when its cell dimensions change.
	wire halo_reset = reset || (halo_grid_8_q != halo_grid_8);

	// Give the line-delay logic and SDRAM controller separate reset drivers.
	(* preserve, dont_merge *) logic primary_line_delay_reset_q = 1'b1;
	(* preserve, dont_merge *) logic primary_sdram_reset_q      = 1'b1;
	always_ff @(posedge clk_sys) begin
		primary_line_delay_reset_q <= reset;
		primary_sdram_reset_q      <= reset;
	end

	vfb_sdram_delay #(
		.SDRAM_MHZ(128),
		.FIFO_DEPTH(SDR_FIFO_DEPTH)
	) primary_line_delay (
		.clk_sys(clk_sys),
		.reset(primary_line_delay_reset_q),
		.controller_reset(primary_sdram_reset_q),
		.ce_pix(ce_pix),
		.line_delay(line_delay),
		.CANONICAL_IN(CANONICAL_IN),
		.VGA_HS_IN(VGA_HS_IN),
		.VGA_VS_IN(VGA_VS_IN),
		.VGA_HBLANK_IN(VGA_HBLANK_IN),
		.VGA_VBLANK_IN(VGA_VBLANK_IN),
		.CANONICAL_OUT(delayed_canonical),
		.VGA_HS_OUT(delayed_hs),
		.VGA_VS_OUT(delayed_vs),
		.VGA_HBLANK_OUT(delayed_hblank),
		.VGA_VBLANK_OUT(delayed_vblank),
		.sdram_data_in(sdram_data_in),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(sdram_cke),
		.sdram_cs(sdram_cs),
		.sdram_ras(sdram_ras),
		.sdram_cas(sdram_cas),
		.sdram_we(sdram_we),
		.sdram_dqm(sdram_dqm),
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba),
		.overflow(sdram_overflow),
		.underflow(sdram_underflow),
		.init_done(sdram_init_done)
	);

	// Align primary pixels and video timing with the halo.
	initial begin
		if (PRIMARY_H_DELAY <= 0 || PRIMARY_DATA_ADVANCE < 0 || PRIMARY_DATA_ADVANCE >= PRIMARY_H_DELAY)
			$error("vfb_halo_pipeline invalid primary delay");
	end

	(* ramstyle = "MLAB" *) logic [19:0] horizontal_delay [0:PRIMARY_H_DELAY-1];
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			horizontal_delay[0] <= {delayed_hs, delayed_vs, delayed_hblank,
			                        delayed_vblank, delayed_canonical};
			for (int i = 1; i < PRIMARY_H_DELAY; i = i + 1)
				horizontal_delay[i] <= horizontal_delay[i-1];
		end
	end

	wire [19:0] filter_input = {horizontal_delay[PRIMARY_H_DELAY-1][19:16],
	                            horizontal_delay[PRIMARY_H_DELAY-1-PRIMARY_DATA_ADVANCE][15:0]};

	logic [7:0] composite_r;
	logic [7:0] composite_g;
	logic [7:0] composite_b;
	logic       composite_hs;
	logic       composite_vs;
	logic       composite_hblank;
	logic       composite_vblank;

	vfb_filter bloom_filter (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.reset(reset),
		.osd_bloom_width(osd_bloom_width_q),
		.bloom_curve_gain(bloom_curve_gain_q),
		.CANONICAL_IN(filter_input[15:0]),
		.VGA_HS_IN(filter_input[19]),
		.VGA_VS_IN(filter_input[18]),
		.VGA_HBLANK_IN(filter_input[17]),
		.VGA_VBLANK_IN(filter_input[16]),
		.VGA_R_OUT(composite_r),
		.VGA_G_OUT(composite_g),
		.VGA_B_OUT(composite_b),
		.VGA_HS_OUT(composite_hs),
		.VGA_VS_OUT(composite_vs),
		.VGA_HBLANK_OUT(composite_hblank),
		.VGA_VBLANK_OUT(composite_vblank)
	);

	// Halo applies its square-law excitation to the visible primary colors.
	wire [23:0] halo_source = vfb_spill_bloom_pkg::spill_visible_rgb(CANONICAL_IN);

	logic [7:0] wide_halo_r;
	logic [7:0] wide_halo_g;
	logic [7:0] wide_halo_b;
	logic       wide_halo_valid;

	vfb_halo_wide #(
		.MAX_WIDTH(MAX_WIDTH),
		.RECONSTRUCTION_DELAY_LINES(SDR_DELAY_LINES)
	) wide_halo (
		.clk_sys(clk_sys),
		.reset(halo_reset),
		.ce_pix(ce_pix),
		.halo_curve_gain(halo_curve_gain_q),
		.halo_spread_mode(halo_spread_mode_q),
		.halo_knee_mode(halo_knee_mode_q),
		.halo_grid_8(halo_grid_8_q),
		.halo_shape(halo_shape_q),
		.active_height(active_height),
		.VGA_R_IN(halo_source[23:16]),
		.VGA_G_IN(halo_source[15:8]),
		.VGA_B_IN(halo_source[7:0]),
		.VGA_HBLANK_IN(VGA_HBLANK_IN),
		.VGA_VBLANK_IN(VGA_VBLANK_IN),
		.HALO_R_OUT(wide_halo_r),
		.HALO_G_OUT(wide_halo_g),
		.HALO_B_OUT(wide_halo_b),
		.HALO_VALID_OUT(wide_halo_valid)
	);

	function automatic [7:0] halo_contribution(
		input logic [7:0] channel,
		input logic       valid,
		input logic [7:0] strength
	);
		logic [8:0]  scaled;
		logic [11:0] scaled_11_32;
		logic [10:0] scaled_3_4;
		begin
			if (!valid)
				halo_contribution = 8'd0;
			else begin
				case (strength)
					8'd8:    begin
						// 0.25x
						halo_contribution = {2'b00, channel[7:2]};
					end
					8'd11:   begin
						// 0.33x, represented as 11/32.
						scaled_11_32      = ({4'd0, channel} << 3) +
						                    ({4'd0, channel} << 1) +
						                    {4'd0, channel} + 12'd16;
						halo_contribution = {1'b0, scaled_11_32[11:5]};
					end
					8'd16:   begin
						// 0.5x
						halo_contribution = {1'b0, channel[7:1]};
					end
					8'd24:   begin
						// 0.75x, rounded.
						scaled_3_4        = ({3'd0, channel} << 1) + {3'd0, channel} + 11'd2;
						halo_contribution = scaled_3_4[9:2];
					end
					8'd32:   begin
						// 1.0x
						halo_contribution = channel;
					end
					8'd40:   begin
						// 1.25x, saturating.
						scaled            = {1'b0, channel} + {3'b000, channel[7:2]};
						halo_contribution = scaled[8] ? 8'hff : scaled[7:0];
					end
					8'd48:   begin
						// 1.5x, saturating.
						scaled            = {1'b0, channel} + {2'b00, channel[7:1]};
						halo_contribution = scaled[8] ? 8'hff : scaled[7:0];
					end
					default: begin
						halo_contribution = 8'd0;
					end
				endcase
			end
		end
	endfunction

	logic [7:0] mix_composite_r;
	logic [7:0] mix_composite_g;
	logic [7:0] mix_composite_b;
	logic [7:0] mix_halo_r;
	logic [7:0] mix_halo_g;
	logic [7:0] mix_halo_b;
	logic       mix_hs;
	logic       mix_vs;
	logic       mix_hblank;
	logic       mix_vblank;
	logic [7:0] present_r;
	logic [7:0] present_g;
	logic [7:0] present_b;
	logic       present_hs;
	logic       present_vs;
	logic       present_hblank;
	logic       present_vblank;

	vfb_final_present final_present (
		.clk_sys(clk_sys),
		.reset(reset),
		.ce_pix(ce_pix),
		.color_space_wg6100_709(color_space_wg6100_709_q),
		.presentation_color(presentation_color_q),
		.slot_mask_mode(slot_mask_mode_q),
		.slot_mask_rows(slot_mask_rows_q),
		.VGA_R_IN(present_r),
		.VGA_G_IN(present_g),
		.VGA_B_IN(present_b),
		.VGA_HS_IN(present_hs),
		.VGA_VS_IN(present_vs),
		.VGA_HBLANK_IN(present_hblank),
		.VGA_VBLANK_IN(present_vblank),
		.VGA_R_OUT(VGA_R_OUT),
		.VGA_G_OUT(VGA_G_OUT),
		.VGA_B_OUT(VGA_B_OUT),
		.VGA_HS_OUT(VGA_HS_OUT),
		.VGA_VS_OUT(VGA_VS_OUT),
		.VGA_HBLANK_OUT(VGA_HBLANK_OUT),
		.VGA_VBLANK_OUT(VGA_VBLANK_OUT)
	);

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			mix_composite_r <= 8'd0;
			mix_composite_g <= 8'd0;
			mix_composite_b <= 8'd0;
			mix_halo_r      <= 8'd0;
			mix_halo_g      <= 8'd0;
			mix_halo_b      <= 8'd0;
			mix_hs          <= 1'b1;
			mix_vs          <= 1'b1;
			mix_hblank      <= 1'b1;
			mix_vblank      <= 1'b1;
			present_r       <= 8'd0;
			present_g       <= 8'd0;
			present_b       <= 8'd0;
			present_hs      <= 1'b1;
			present_vs      <= 1'b1;
			present_hblank  <= 1'b1;
			present_vblank  <= 1'b1;
		end else if (ce_pix) begin
			logic [8:0] mixed_r;
			logic [8:0] mixed_g;
			logic [8:0] mixed_b;

			mixed_r = {1'b0, mix_composite_r} + {1'b0, mix_halo_r};
			mixed_g = {1'b0, mix_composite_g} + {1'b0, mix_halo_g};
			mixed_b = {1'b0, mix_composite_b} + {1'b0, mix_halo_b};

			if (mix_hblank || mix_vblank) begin
				present_r <= 8'd0;
				present_g <= 8'd0;
				present_b <= 8'd0;
			end else begin
				present_r <= mixed_r[8] ? 8'hff : mixed_r[7:0];
				present_g <= mixed_g[8] ? 8'hff : mixed_g[7:0];
				present_b <= mixed_b[8] ? 8'hff : mixed_b[7:0];
			end
			present_hs      <= mix_hs;
			present_vs      <= mix_vs;
			present_hblank  <= mix_hblank;
			present_vblank  <= mix_vblank;

			mix_composite_r <= composite_r;
			mix_composite_g <= composite_g;
			mix_composite_b <= composite_b;
			mix_halo_r      <= halo_contribution(wide_halo_r, wide_halo_valid, halo_filter_q);
			mix_halo_g      <= halo_contribution(wide_halo_g, wide_halo_valid, halo_filter_q);
			mix_halo_b      <= halo_contribution(wide_halo_b, wide_halo_valid, halo_filter_q);
			mix_hs          <= composite_hs;
			mix_vs          <= composite_vs;
			mix_hblank      <= composite_hblank;
			mix_vblank      <= composite_vblank;
		end
	end

endmodule
