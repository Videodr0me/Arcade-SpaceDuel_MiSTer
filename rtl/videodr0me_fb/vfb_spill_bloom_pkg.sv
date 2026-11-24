// ============================================================================
// Space Duel visible spill and bloom excitation.
// Written 2026 by Videodr0me
// ============================================================================
package vfb_spill_bloom_pkg;

	localparam logic [7:0] SPILL_ANCHOR = 8'd225;

	// F(x) = round(255 * (x/255)^2.5), indexed by an eight-bit native level.
	localparam logic [2047:0] NATIVE_SEEDS      = {
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
		8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd1, 8'd1,
		8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1,
		8'd1, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2,
		8'd2, 8'd3, 8'd3, 8'd3, 8'd3, 8'd3, 8'd4, 8'd4,
		8'd4, 8'd4, 8'd4, 8'd5, 8'd5, 8'd5, 8'd5, 8'd6,
		8'd6, 8'd6, 8'd6, 8'd7, 8'd7, 8'd7, 8'd7, 8'd8,
		8'd8, 8'd8, 8'd9, 8'd9, 8'd9, 8'd10, 8'd10, 8'd10,
		8'd11, 8'd11, 8'd12, 8'd12, 8'd12, 8'd13, 8'd13, 8'd14,
		8'd14, 8'd15, 8'd15, 8'd15, 8'd16, 8'd16, 8'd17, 8'd17,
		8'd18, 8'd18, 8'd19, 8'd19, 8'd20, 8'd20, 8'd21, 8'd22,
		8'd22, 8'd23, 8'd23, 8'd24, 8'd25, 8'd25, 8'd26, 8'd26,
		8'd27, 8'd28, 8'd28, 8'd29, 8'd30, 8'd30, 8'd31, 8'd32,
		8'd33, 8'd33, 8'd34, 8'd35, 8'd36, 8'd36, 8'd37, 8'd38,
		8'd39, 8'd40, 8'd40, 8'd41, 8'd42, 8'd43, 8'd44, 8'd45,
		8'd46, 8'd46, 8'd47, 8'd48, 8'd49, 8'd50, 8'd51, 8'd52,
		8'd53, 8'd54, 8'd55, 8'd56, 8'd57, 8'd58, 8'd59, 8'd60,
		8'd61, 8'd62, 8'd63, 8'd64, 8'd65, 8'd67, 8'd68, 8'd69,
		8'd70, 8'd71, 8'd72, 8'd73, 8'd75, 8'd76, 8'd77, 8'd78,
		8'd80, 8'd81, 8'd82, 8'd83, 8'd85, 8'd86, 8'd87, 8'd89,
		8'd90, 8'd91, 8'd93, 8'd94, 8'd95, 8'd97, 8'd98, 8'd99,
		8'd101, 8'd102, 8'd104, 8'd105, 8'd107, 8'd108, 8'd110, 8'd111,
		8'd113, 8'd114, 8'd116, 8'd117, 8'd119, 8'd121, 8'd122, 8'd124,
		8'd125, 8'd127, 8'd129, 8'd130, 8'd132, 8'd134, 8'd135, 8'd137,
		8'd139, 8'd141, 8'd142, 8'd144, 8'd146, 8'd148, 8'd150, 8'd151,
		8'd153, 8'd155, 8'd157, 8'd159, 8'd161, 8'd163, 8'd165, 8'd166,
		8'd168, 8'd170, 8'd172, 8'd174, 8'd176, 8'd178, 8'd180, 8'd182,
		8'd184, 8'd186, 8'd189, 8'd191, 8'd193, 8'd195, 8'd197, 8'd199,
		8'd201, 8'd204, 8'd206, 8'd208, 8'd210, 8'd212, 8'd215, 8'd217,
		8'd219, 8'd221, 8'd224, 8'd226, 8'd228, 8'd231, 8'd233, 8'd235,
		8'd238, 8'd240, 8'd243, 8'd245, 8'd248, 8'd250, 8'd253, 8'd255
	};
	localparam logic [7:0]    SPILL_NATIVE_SEED = NATIVE_SEEDS[(255-int'(SPILL_ANCHOR))*8 +: 8];
	localparam int            SPILL_GAIN_Q12    = (4096 * int'(SPILL_NATIVE_SEED) +
	                                               int'(SPILL_ANCHOR) / 2) /
	                                              int'(SPILL_ANCHOR);

	// Above 255 the high energy bit contributes 256 to E - reference.
	function automatic [8:0] spill_excess(input logic [7:0] energy_low, input logic full_primary);
		spill_excess = {1'b0, energy_low} + (full_primary ? 9'd1 : (9'd256 - {1'b0, SPILL_ANCHOR}));
	endfunction

	// After decay, bits [8:0] hold either the ordinary eight-bit level, or
	// {1, primary_is_255, seven-bit share per unlit gun}. The codec preserves all nine bits.
	function automatic [15:0] display_pixel(input logic [2:0] mask, input logic [8:0] energy,
	                                         input logic full_primary, input logic [8:0] excess);
		logic [8:0] share;
		begin
			share = (mask == 3'b100 || mask == 3'b010 || mask == 3'b001) ? excess >> 1 : excess;
			if (mask == 3'd0 || energy == 9'd0)
				display_pixel = 16'd0;
			else if (!energy[8])
				display_pixel = {mask, 4'd0, energy};
			else if (mask == 3'b111)
				display_pixel = {mask, 4'd0, 9'd255};
			else
				display_pixel = {mask, 4'd0, 1'b1, full_primary, |share[8:7] ? 7'd127 : share[6:0]};
		end
	endfunction

	function automatic [7:0] visible_primary(input logic [8:0] level);
		visible_primary = !level[8] ? level[7:0] : level[7] ? 8'd255 : SPILL_ANCHOR;
	endfunction

	// ROM initialization. F(255)/255 is exactly one, so full-primary spill
	// uses the visible share directly. Off uses F(225)/225 rounded to Q12.
	function automatic [14:0] spill_seed_value(input logic [8:0] level);
		logic [7:0] primary;
		logic [6:0] share;
		begin
			primary          = visible_primary(level);
			share            = level[8] ? level[6:0] : 7'd0;
			spill_seed_value = {NATIVE_SEEDS[(255-int'(primary))*8 +: 8],
			                    level[7] ? share : 7'((int'(share) * SPILL_GAIN_Q12 + 2048) >> 12)};
		end
	endfunction

	function automatic [23:0] spill_visible_rgb(input logic [15:0] pixel);
		logic [2:0] mask;
		logic [7:0] primary, spill;
		begin
			mask              = pixel[15:13];
			primary           = visible_primary(pixel[8:0]);
			spill             = {1'b0, pixel[8] ? pixel[6:0] : 7'd0};
			spill_visible_rgb = {mask[2] ? primary : spill, mask[1] ? primary : spill,
			                     mask[0] ? primary : spill};
		end
	endfunction
endpackage
