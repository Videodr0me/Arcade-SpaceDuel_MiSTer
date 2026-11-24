// ============================================================================
// Local bloom stage for the delayed primary stream.
// Written 2026 by Videodr0me
//
// Applies the bloom source curve, runs the local blur passes, and combines
// the result with the primary image.
// ============================================================================

module vfb_filter (
	input  logic        clk_sys,
	input  logic        ce_pix,
	input  logic        reset,

	// Bloom controls
	input  logic [2:0]  osd_bloom_width,
	input  logic [9:0]  bloom_curve_gain,

	// Delayed primary image
	input  logic [15:0] CANONICAL_IN,
	input  logic        VGA_HS_IN,
	input  logic        VGA_VS_IN,
	input  logic        VGA_HBLANK_IN,
	input  logic        VGA_VBLANK_IN,

	// Filtered output
	output logic [7:0]  VGA_R_OUT,
	output logic [7:0]  VGA_G_OUT,
	output logic [7:0]  VGA_B_OUT,
	output logic        VGA_HS_OUT,
	output logic        VGA_VS_OUT,
	output logic        VGA_HBLANK_OUT,
	output logic        VGA_VBLANK_OUT
);
	import vfb_layout_pkg::*;

	logic [2:0] osd_bloom_width_q  =   3'd0;
	logic [9:0] bloom_curve_gain_q = 10'd64;
	always_ff @(posedge clk_sys) begin
		osd_bloom_width_q  <= osd_bloom_width;
		bloom_curve_gain_q <= bloom_curve_gain;
	end

	logic [15:0] canonical_in_r;
	logic        vga_hs_in_r;
	logic        vga_vs_in_r;
	logic        vga_hblank_in_r;
	logic        vga_vblank_in_r;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			canonical_in_r  <= 16'd0;
			vga_hs_in_r     <=  1'b1;
			vga_vs_in_r     <=  1'b1;
			vga_hblank_in_r <=  1'b1;
			vga_vblank_in_r <=  1'b1;
		end else if (ce_pix) begin
			canonical_in_r  <= CANONICAL_IN;
			vga_hs_in_r     <= VGA_HS_IN;
			vga_vs_in_r     <= VGA_VS_IN;
			vga_hblank_in_r <= VGA_HBLANK_IN;
			vga_vblank_in_r <= VGA_VBLANK_IN;
		end
	end

	logic [8:0] bloom_comp_scale;
	always_comb begin
		case (osd_bloom_width_q)
			3'd0:    bloom_comp_scale =   9'd0;  // Off
			3'd1:    bloom_comp_scale =  9'd24;  // Thin
			3'd2:    bloom_comp_scale =  9'd43;  // Tight
			3'd3:    bloom_comp_scale =  9'd80;  // Soft
			3'd4:    bloom_comp_scale = 9'd114;  // Normal
			3'd5:    bloom_comp_scale = 9'd180;  // Broad
			3'd6:    bloom_comp_scale = 9'd240;  // Wide-
			default: bloom_comp_scale = 9'd320;  // Wide
		endcase
	end

	logic en_p1, en_p2, en_p3;
	always_comb begin
		en_p1 = (osd_bloom_width_q >= 3'd1);
		en_p2 = (osd_bloom_width_q >= 3'd3);
		en_p3 = (osd_bloom_width_q >= 3'd5);
	end

	// Delay sync and blanking to match RGB.
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_0 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_1 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_2 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_3 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_4 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_5 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_6 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_7 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_8 [0:2047];

	logic [3:0] s_lb_out [0:8];

	logic [10:0] h_count;
	logic [10:0] h_count_d1;
	logic        hs_d;

	logic [33:0] hs_pipe, vs_pipe, hb_pipe, vb_pipe;
	logic [3:0]  sync_in_d1;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			hs_pipe    <=      '0;
			vs_pipe    <=      '0;
			hb_pipe    <=      '1;
			vb_pipe    <=      '1;
			h_count    <=      '0;
			hs_d       <=      '0;
			sync_in_d1 <= 4'b0011;
		end else if (ce_pix) begin
			hs_d       <= vga_hs_in_r;
			sync_in_d1 <= {vga_hs_in_r, vga_vs_in_r, vga_hblank_in_r, vga_vblank_in_r};

			if (vga_hs_in_r && !hs_d) h_count <= 0;
			else if (h_count < 11'd2047) h_count <= h_count + 11'd1;

			h_count_d1  <= h_count;

			s_lb_out[0] <= sync_lb_0[h_count];
			s_lb_out[1] <= sync_lb_1[h_count];
			s_lb_out[2] <= sync_lb_2[h_count];
			s_lb_out[3] <= sync_lb_3[h_count];
			s_lb_out[4] <= sync_lb_4[h_count];
			s_lb_out[5] <= sync_lb_5[h_count];
			s_lb_out[6] <= sync_lb_6[h_count];
			s_lb_out[7] <= sync_lb_7[h_count];
			s_lb_out[8] <= sync_lb_8[h_count];

			sync_lb_0[h_count_d1] <= sync_in_d1;
			sync_lb_1[h_count_d1] <= s_lb_out[0];
			sync_lb_2[h_count_d1] <= s_lb_out[1];
			sync_lb_3[h_count_d1] <= s_lb_out[2];
			sync_lb_4[h_count_d1] <= s_lb_out[3];
			sync_lb_5[h_count_d1] <= s_lb_out[4];
			sync_lb_6[h_count_d1] <= s_lb_out[5];
			sync_lb_7[h_count_d1] <= s_lb_out[6];
			sync_lb_8[h_count_d1] <= s_lb_out[7];

			hs_pipe <= {hs_pipe[32:0], s_lb_out[8][3]};
			vs_pipe <= {vs_pipe[32:0], s_lb_out[8][2]};
			hb_pipe <= {hb_pipe[32:0], s_lb_out[8][1]};
			vb_pipe <= {vb_pipe[32:0], s_lb_out[8][0]};
		end
	end

	// Track horizontal position through the filter.
	localparam integer COMP_SERVICE_STAGE      = 30;
	localparam integer COMP_WRITE_STAGE        = 31;
	localparam integer COMP_PRESENT_READ_STAGE = 32;
	localparam integer COMP_OUTPUT_SYNC_STAGE  = 30;
	logic [10:0]       active_x;
	logic [10:0]       ax_pipe [1:COMP_PRESENT_READ_STAGE];
	logic              ax_valid_pipe [1:COMP_WRITE_STAGE];

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			active_x <= 11'd0;
			for (int i=1; i<=COMP_PRESENT_READ_STAGE; i++) ax_pipe[i] <= 11'd0;
			for (int i=1; i<=COMP_WRITE_STAGE; i++) ax_valid_pipe[i] <= 1'b0;
		end else if (ce_pix) begin
			if (vga_hblank_in_r) begin
				active_x <= 11'd0;
			end else begin
				if (active_x < 11'd1471) active_x <= active_x + 11'd1;
			end

			ax_pipe[1] <= vga_hblank_in_r ? 11'd0 : active_x;
			for (int i=2; i<=COMP_PRESENT_READ_STAGE; i++) ax_pipe[i] <= ax_pipe[i-1];

			ax_valid_pipe[1] <= !vga_hblank_in_r;
			for (int i=2; i<=COMP_WRITE_STAGE; i++)
				ax_valid_pipe[i] <= ax_valid_pipe[i-1];
		end
	end

	logic [15:0] source_pixel;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) source_pixel <= canonical_in_r;
	end

	// Launch bloom decode early enough to align with the delayed primary.
	logic [15:0] base_pixel;
	always_ff @(posedge clk_sys) if (ce_pix) base_pixel <= source_pixel;
	logic [23:0] bloom_src;
	vfb_spill_source source_decode (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.canonical_in(canonical_in_r),
		.bloom_curve_gain(bloom_curve_gain_q),
		.bloom_rgb(bloom_src)
	);

	// Delay packed 16-bit primary pixels by six lines to align with bloom.
	// Decode RGB after the final alignment stage.
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] base_lb_0 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] base_lb_1 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] base_lb_2 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] base_lb_3 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] base_lb_4 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] base_lb_5 [0:1471];

	logic [15:0] base_lb_0_ram, base_lb_1_ram, base_lb_2_ram, base_lb_3_ram, base_lb_4_ram, base_lb_5_ram;
	logic [10:0] base_cascade_addr;
	logic        base_cascade_valid;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			base_cascade_addr  <= 11'd0;
			base_cascade_valid <=  1'b0;
		end else if (ce_pix) begin
			base_cascade_addr  <= ax_pipe[1];
			base_cascade_valid <= ax_valid_pipe[1];

			base_lb_0_ram <= base_lb_0[ax_pipe[1]];
			base_lb_1_ram <= base_lb_1[ax_pipe[1]];
			base_lb_2_ram <= base_lb_2[ax_pipe[1]];
			base_lb_3_ram <= base_lb_3[ax_pipe[1]];
			base_lb_4_ram <= base_lb_4[ax_pipe[1]];
			base_lb_5_ram <= base_lb_5[ax_pipe[1]];

			if (ax_valid_pipe[2]) base_lb_0[ax_pipe[2]] <= base_pixel;

			if (base_cascade_valid) begin
				base_lb_1[base_cascade_addr] <= base_lb_0_ram;
				base_lb_2[base_cascade_addr] <= base_lb_1_ram;
				base_lb_3[base_cascade_addr] <= base_lb_2_ram;
				base_lb_4[base_cascade_addr] <= base_lb_3_ram;
				base_lb_5[base_cascade_addr] <= base_lb_4_ram;
			end
		end
	end

	logic [15:0] base_align_pipe [1:27];
	logic [23:0] base_primary_rgb;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			base_align_pipe[1] <= base_lb_5_ram;
			for (int i = 2; i <= 27; i++) base_align_pipe[i] <= base_align_pipe[i-1];
			base_primary_rgb <= vfb_spill_bloom_pkg::spill_visible_rgb(base_align_pipe[27]);
		end
	end

	// Three bloom passes.
	logic [10:0] hc_p1, hc_p2;
	logic        hb_p1, hb_p2;
	logic [23:0] b_p1, b_p2, b_p3;

	vfb_blur bloom_pass1 (
		.clk_sys     (clk_sys),
		.ce_pix      (ce_pix),
		.reset       (reset),
		.active_x_in (ax_pipe[3]),
		.hblank_in   (!ax_valid_pipe[3]),
		.enable      (en_p1),
		.rgb_in      (bloom_src),
		.active_x_out(hc_p1),
		.hblank_out  (hb_p1),
		.rgb_out     (b_p1)
	);
	vfb_blur bloom_pass2 (
		.clk_sys     (clk_sys),
		.ce_pix      (ce_pix),
		.reset       (reset),
		.active_x_in (hc_p1),
		.hblank_in   (hb_p1),
		.enable      (en_p2),
		.rgb_in      (b_p1),
		.active_x_out(hc_p2),
		.hblank_out  (hb_p2),
		.rgb_out     (b_p2)
	);
	vfb_blur bloom_pass3 (
		.clk_sys     (clk_sys),
		.ce_pix      (ce_pix),
		.reset       (reset),
		.active_x_in (hc_p2),
		.hblank_in   (hb_p2),
		.enable      (en_p3),
		.rgb_in      (b_p2),
		.active_x_out(),
		.hblank_out  (),
		.rgb_out     (b_p3)
	);

	// Scale the bloom result.
	logic [7:0] bloom_comp_r, bloom_comp_g, bloom_comp_b;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			logic [16:0] cr, cg, cb;
			cr = b_p3[23:16] * bloom_comp_scale;
			cg = b_p3[15:8] * bloom_comp_scale;
			cb = b_p3[7:0] * bloom_comp_scale;

			bloom_comp_r <= |cr[16:12] ? 8'd255 : cr[11:4];
			bloom_comp_g <= |cg[16:12] ? 8'd255 : cg[11:4];
			bloom_comp_b <= |cb[16:12] ? 8'd255 : cb[11:4];
		end
	end

	logic [7:0] bcomp_r_d1, bcomp_g_d1, bcomp_b_d1;
	logic [7:0] bcomp_r_d2, bcomp_g_d2, bcomp_b_d2;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			bcomp_r_d1 <= bloom_comp_r;
			bcomp_g_d1 <= bloom_comp_g;
			bcomp_b_d1 <= bloom_comp_b;
			bcomp_r_d2 <= bcomp_r_d1;
			bcomp_g_d2 <= bcomp_g_d1;
			bcomp_b_d2 <= bcomp_b_d1;
		end
	end

	// Combine primary and bloom by channel maximum.
	logic [7:0] comp_r, comp_g, comp_b;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			comp_r <= (bcomp_r_d2 > base_primary_rgb[23:16]) ? bcomp_r_d2 : base_primary_rgb[23:16];
			comp_g <= (bcomp_g_d2 > base_primary_rgb[15:8]) ? bcomp_g_d2 : base_primary_rgb[15:8];
			comp_b <= (bcomp_b_d2 > base_primary_rgb[7:0]) ? bcomp_b_d2 : base_primary_rgb[7:0];
		end
	end

	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_0 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_1 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_2 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_3 [0:1471];

	logic [23:0] clb_0, clb_1, clb_2, clb_3;
	logic [10:0] comp_cascade_addr;
	logic        comp_cascade_valid;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			comp_cascade_addr  <= 11'd0;
			comp_cascade_valid <=  1'b0;
		end else if (ce_pix) begin
			comp_cascade_addr  <= ax_pipe[COMP_SERVICE_STAGE];
			comp_cascade_valid <= ax_valid_pipe[COMP_SERVICE_STAGE];

			clb_0 <= comp_lb_0[ax_pipe[COMP_SERVICE_STAGE]];
			clb_1 <= comp_lb_1[ax_pipe[COMP_SERVICE_STAGE]];
			clb_2 <= comp_lb_2[ax_pipe[COMP_SERVICE_STAGE]];
			// Read the final delayed row at the output position. Advance the
			// line buffers only for active pixels.
			clb_3 <= comp_lb_3[ax_pipe[COMP_PRESENT_READ_STAGE]];

			if (ax_valid_pipe[COMP_WRITE_STAGE])
				comp_lb_0[ax_pipe[COMP_WRITE_STAGE]] <= {comp_r, comp_g, comp_b};

			if (comp_cascade_valid) begin
				comp_lb_1[comp_cascade_addr] <= clb_0;
				comp_lb_2[comp_cascade_addr] <= clb_1;
				comp_lb_3[comp_cascade_addr] <= clb_2;
			end
		end
	end

	logic  [7:0] comp_r_d1, comp_g_d1, comp_b_d1;
	assign       comp_r_d1 = clb_3[23:16];
	assign       comp_g_d1 = clb_3[15:8];
	assign       comp_b_d1 = clb_3[7:0];

	// Register RGB and timing outputs.
	logic [7:0] mix_r, mix_g, mix_b;
	logic       mix_hs, mix_vs, mix_hblank, mix_vblank;
	logic       out_hs, out_vs, out_hblank, out_vblank;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			mix_r          <= 8'd0;
			mix_g          <= 8'd0;
			mix_b          <= 8'd0;
			mix_hs         <= 1'b1;
			mix_vs         <= 1'b1;
			mix_hblank     <= 1'b1;
			mix_vblank     <= 1'b1;
			out_hs         <= 1'b1;
			out_vs         <= 1'b1;
			out_hblank     <= 1'b1;
			out_vblank     <= 1'b1;
			VGA_R_OUT      <= 8'd0;
			VGA_G_OUT      <= 8'd0;
			VGA_B_OUT      <= 8'd0;
			VGA_HS_OUT     <= 1'b1;
			VGA_VS_OUT     <= 1'b1;
			VGA_HBLANK_OUT <= 1'b1;
			VGA_VBLANK_OUT <= 1'b1;
		end else if (ce_pix) begin
			mix_r      <= comp_r_d1;
			mix_g      <= comp_g_d1;
			mix_b      <= comp_b_d1;
			mix_hs     <= hs_pipe[COMP_OUTPUT_SYNC_STAGE];
			mix_vs     <= vs_pipe[COMP_OUTPUT_SYNC_STAGE];
			mix_hblank <= hb_pipe[COMP_OUTPUT_SYNC_STAGE];
			mix_vblank <= vb_pipe[COMP_OUTPUT_SYNC_STAGE];

			out_hs     <= mix_hs;
			out_vs     <= mix_vs;
			out_hblank <= mix_hblank;
			out_vblank <= mix_vblank;

			VGA_R_OUT      <= mix_r;
			VGA_G_OUT      <= mix_g;
			VGA_B_OUT      <= mix_b;
			VGA_HS_OUT     <= out_hs;
			VGA_VS_OUT     <= out_vs;
			VGA_HBLANK_OUT <= out_hblank;
			VGA_VBLANK_OUT <= out_vblank;
		end
	end

endmodule
