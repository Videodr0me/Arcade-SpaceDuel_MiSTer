// ============================================================================
// Final CRT presentation stage.
// Written 2026 by Videodr0me
//
// This stage runs after primary, bloom, halo, and phosphor processing.
// Its settings affect only the final video output.
//
// Pipeline:
//   A1-A3: align native RGB and timing, look up and add WG6100 color offsets
//   C1: blank or select native/WG6100 RGB
//   C2: presentation color transform
//   C3: orientation-aware slot mask with bright-pixel gap closure
//   C4: final output register
//
// RGB, sync, and blanking remain aligned through every stage.
// ============================================================================

module vfb_final_present (
	input  logic        clk_sys,
	input  logic        reset,
	input  logic        ce_pix,

	input  logic        color_space_wg6100_709,
	input  logic [2:0]  presentation_color,
	input  logic [1:0]  slot_mask_mode,
	input  logic        slot_mask_rows,

	input  logic [7:0]  VGA_R_IN,
	input  logic [7:0]  VGA_G_IN,
	input  logic [7:0]  VGA_B_IN,
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
	output logic        VGA_VBLANK_OUT
);
	import vfb_control_pkg::*;

	logic       color_space_wg6100_709_q = 1'b0;
	logic [2:0] presentation_color_q     = CHANNEL_ORIGINAL;
	logic [1:0] slot_mask_mode_q         = SLOT_MASK_OFF;
	logic       slot_mask_rows_q         = 1'b0;
	always_ff @(posedge clk_sys) begin
		color_space_wg6100_709_q <= color_space_wg6100_709;
		presentation_color_q     <= presentation_color;
		slot_mask_mode_q         <= slot_mask_mode;
		slot_mask_rows_q         <= slot_mask_rows;
	end

	typedef struct packed {
		logic [7:0] r, g, b;
		logic       hs, vs, hblank, vblank;
	} pixel_t;

	pixel_t native_a1, native_a2, native_a3;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			native_a1 <= {24'd0, 4'b1111};
			native_a2 <= {24'd0, 4'b1111};
			native_a3 <= {24'd0, 4'b1111};
		end else if (ce_pix) begin
			native_a1 <= {VGA_R_IN, VGA_G_IN, VGA_B_IN, VGA_HS_IN, VGA_VS_IN,
			              VGA_HBLANK_IN, VGA_VBLANK_IN};
			native_a2 <= native_a1;
			native_a3 <= native_a2;
		end
	end

	logic [23:0] wg_offset_a2;
	vfb_wg6100_rom wg6100_rom (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.addr({native_a1.r[7:4], native_a1.g[7:4], native_a1.b[7:4]}),
		.correction(wg_offset_a2)
	);

	function automatic [7:0] scale_half(input logic [7:0] channel);
		logic [8:0] rounded;
		begin
			rounded    = {1'b0, channel} + 9'd1;
			scale_half = rounded[8:1];
		end
	endfunction

	// Each offset keeps every channel in its address cell in the range 0..255.
	function automatic [7:0] apply_wg_offset(
		input logic        [7:0] channel,
		input logic signed [7:0] offset
	);
		logic signed [9:0] sum;
		begin
			sum             = $signed({2'b00, channel}) + 10'(offset);
			apply_wg_offset = sum[7:0];
		end
	endfunction

	// The reset blank travels with native RGB and masks the color result at C1.
	logic [7:0] wg_r_a3, wg_g_a3, wg_b_a3;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			wg_r_a3 <= apply_wg_offset(native_a2.r, wg_offset_a2[23:16]);
			wg_g_a3 <= apply_wg_offset(native_a2.g, wg_offset_a2[15:8]);
			wg_b_a3 <= apply_wg_offset(native_a2.b, wg_offset_a2[7:0]);
		end
	end

	function automatic [7:0] scale_14_16(input logic [7:0] channel);
		logic [10:0] scaled;
		begin
			// Exact round(channel * 14 / 16), reduced to
			// floor((channel * 7 + 4) / 8).
			scaled      = ({3'd0, channel} << 3) - {3'd0, channel} + 11'd4;
			scale_14_16 = scaled[10:3];
		end
	endfunction

	logic [7:0] cs_r;
	logic [7:0] cs_g;
	logic [7:0] cs_b;
	logic       cs_hs;
	logic       cs_vs;
	logic       cs_hblank;
	logic       cs_vblank;

	// Keep color arithmetic separate from the slot-mask predicates.
	(* preserve, dont_retime *) logic [7:0] ch_r;
	(* preserve, dont_retime *) logic [7:0] ch_g;
	(* preserve, dont_retime *) logic [7:0] ch_b;
	logic ch_hs;
	logic ch_vs;
	logic ch_hblank;
	logic ch_vblank;

	// C3: exact round(channel * 0.67), with one synchronous ROM per channel.
	// Unconditional data reads allow block-ROM inference. C4 selects the result
	// using the aligned flag, without adding a presentation stage.
	logic [7:0] medium_rgb [0:2];
	(* preserve, dont_retime *) logic selected_medium;
	genvar c;
	generate for (c = 0; c < 3; c = c + 1) begin : medium_channel
		(* romstyle = "M10K" *) logic [7:0] mask_rom [0:255];
		wire [7:0] channel_in = c == 0 ? ch_r : c == 1 ? ch_g : ch_b;
		initial begin
			for (int i = 0; i < 256; i = i + 1)
				mask_rom[i] = 8'((i * 67 + 50) / 100);
		end
		always_ff @(posedge clk_sys) if (ce_pix) medium_rgb[c] <= mask_rom[channel_in];
	end endgenerate

	logic [7:0] selected_r;
	logic [7:0] selected_g;
	logic [7:0] selected_b;
	logic       selected_hs;
	logic       selected_vs;
	logic       selected_hblank;
	logic       selected_vblank;

	logic slot_column_parity;
	logic slot_row_parity;
	logic slot_line_active;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			cs_r      <= 8'd0;
			cs_g      <= 8'd0;
			cs_b      <= 8'd0;
			cs_hs     <= 1'b1;
			cs_vs     <= 1'b1;
			cs_hblank <= 1'b1;
			cs_vblank <= 1'b1;
		end else if (ce_pix) begin
			cs_hs     <= native_a3.hs;
			cs_vs     <= native_a3.vs;
			cs_hblank <= native_a3.hblank;
			cs_vblank <= native_a3.vblank;
			if (native_a3.hblank || native_a3.vblank) begin
				cs_r <= 8'd0;
				cs_g <= 8'd0;
				cs_b <= 8'd0;
			end else begin
				cs_r <= color_space_wg6100_709_q ? wg_r_a3 : native_a3.r;
				cs_g <= color_space_wg6100_709_q ? wg_g_a3 : native_a3.g;
				cs_b <= color_space_wg6100_709_q ? wg_b_a3 : native_a3.b;
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			ch_r      <= 8'd0;
			ch_g      <= 8'd0;
			ch_b      <= 8'd0;
			ch_hs     <= 1'b1;
			ch_vs     <= 1'b1;
			ch_hblank <= 1'b1;
			ch_vblank <= 1'b1;
		end else if (ce_pix) begin
			logic [9:0] grey_sum;
			logic [7:0] grey;

			ch_hs     <= cs_hs;
			ch_vs     <= cs_vs;
			ch_hblank <= cs_hblank;
			ch_vblank <= cs_vblank;

			grey_sum = {2'd0, cs_r} + {1'd0, cs_g, 1'b0} + {2'd0, cs_b};
			grey     = grey_sum[9:2];

			case (presentation_color_q)
				CHANNEL_ORIGINAL: begin ch_r <= cs_r; ch_g <= cs_g; ch_b <= cs_b; end
				CHANNEL_RBG:      begin ch_r <= cs_r; ch_g <= cs_b; ch_b <= cs_g; end
				CHANNEL_GRB:      begin ch_r <= cs_g; ch_g <= cs_r; ch_b <= cs_b; end
				CHANNEL_GBR:      begin ch_r <= cs_g; ch_g <= cs_b; ch_b <= cs_r; end
				CHANNEL_BRG:      begin ch_r <= cs_b; ch_g <= cs_r; ch_b <= cs_g; end
				CHANNEL_BGR:      begin ch_r <= cs_b; ch_g <= cs_g; ch_b <= cs_r; end
				CHANNEL_BW:       begin ch_r <= grey; ch_g <= grey; ch_b <= grey; end
				CHANNEL_NEGATIVE: begin ch_r <= ~cs_r; ch_g <= ~cs_g; ch_b <= ~cs_b; end
				default:          begin ch_r <= cs_r; ch_g <= cs_g; ch_b <= cs_b; end
			endcase
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			selected_r         <= 8'd0;
			selected_g         <= 8'd0;
			selected_b         <= 8'd0;
			selected_hs        <= 1'b1;
			selected_vs        <= 1'b1;
			selected_hblank    <= 1'b1;
			selected_vblank    <= 1'b1;
			selected_medium    <= 1'b0;
			slot_column_parity <= 1'b0;
			slot_row_parity    <= 1'b0;
			slot_line_active   <= 1'b0;
		end else if (ce_pix) begin
			logic gap_position;
			logic close_gap;

			selected_hs     <= ch_hs;
			selected_vs     <= ch_vs;
			selected_hblank <= ch_hblank;
			selected_vblank <= ch_vblank;

			gap_position = (slot_mask_mode_q != SLOT_MASK_OFF) &&
			               (slot_mask_rows_q ? slot_row_parity : slot_column_parity);
			close_gap    = (slot_mask_mode_q == SLOT_MASK_MILD) &&
			               ((ch_r >= 8'd200) || (ch_g >= 8'd200) || (ch_b >= 8'd200));
			selected_medium <= !ch_hblank && !ch_vblank && gap_position &&
			                   slot_mask_mode_q == SLOT_MASK_MEDIUM;

			if (ch_hblank || ch_vblank) begin
				selected_r         <= 8'd0;
				selected_g         <= 8'd0;
				selected_b         <= 8'd0;
				slot_column_parity <= 1'b0;
				if (ch_vblank) begin
					slot_row_parity  <= 1'b0;
					slot_line_active <= 1'b0;
				end else begin
					if (slot_line_active) slot_row_parity <= ~slot_row_parity;
					slot_line_active <= 1'b0;
				end
			end else begin
				if (gap_position && !close_gap) begin
					case (slot_mask_mode_q)
						SLOT_MASK_MAX: begin
							selected_r <= scale_half(ch_r);
							selected_g <= scale_half(ch_g);
							selected_b <= scale_half(ch_b);
						end
						default:       begin
							selected_r <= scale_14_16(ch_r);
							selected_g <= scale_14_16(ch_g);
							selected_b <= scale_14_16(ch_b);
						end
					endcase
				end else begin
					selected_r <= ch_r;
					selected_g <= ch_g;
					selected_b <= ch_b;
				end
				slot_column_parity <= ~slot_column_parity;
				slot_line_active   <= 1'b1;
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			VGA_R_OUT      <= 8'd0;
			VGA_G_OUT      <= 8'd0;
			VGA_B_OUT      <= 8'd0;
			VGA_HS_OUT     <= 1'b1;
			VGA_VS_OUT     <= 1'b1;
			VGA_HBLANK_OUT <= 1'b1;
			VGA_VBLANK_OUT <= 1'b1;
		end else if (ce_pix) begin
			VGA_R_OUT      <= selected_medium ? medium_rgb[0] : selected_r;
			VGA_G_OUT      <= selected_medium ? medium_rgb[1] : selected_g;
			VGA_B_OUT      <= selected_medium ? medium_rgb[2] : selected_b;
			VGA_HS_OUT     <= selected_hs;
			VGA_VS_OUT     <= selected_vs;
			VGA_HBLANK_OUT <= selected_hblank;
			VGA_VBLANK_OUT <= selected_vblank;
		end
	end

endmodule
