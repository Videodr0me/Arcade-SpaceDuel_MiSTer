package vfb_layout_pkg;

	// DDRAM addresses count 64-bit words; each 8x8 tile occupies sixteen words.
	// Tile IDs pack {tile_y, tile_x}; tilemaps use a 192-entry row stride.

	localparam integer      VFB_BUFFER_COUNT        =         5;
	localparam integer      VFB_TILE_SIZE           =         8;
	localparam logic [15:0] VFB_TILEMAP_ENTRIES_480 = 16'd11520;

	localparam logic [28:0] VFB_FRAMEBUFFER_BASE = 29'h06000000;
	localparam logic [28:0] VFB_FRAMEBUFFER_LAST = 29'h0654ffff;

	localparam logic [11:0] VFB_HALO_DELAY_8_LINES = 12'd39;

	function automatic logic [28:0] vfb_buffer_base(
		input logic [2:0] index
	);
		begin
			case (index)
				3'd0:    vfb_buffer_base = 29'h06000000;
				3'd1:    vfb_buffer_base = 29'h06110000;
				3'd2:    vfb_buffer_base = 29'h06220000;
				3'd3:    vfb_buffer_base = 29'h06330000;
				3'd4:    vfb_buffer_base = 29'h06440000;
				default: vfb_buffer_base = VFB_FRAMEBUFFER_BASE;
			endcase
		end
	endfunction

	function automatic logic [8:0] vfb_tile_columns(
		input logic [11:0] width
	);
		vfb_tile_columns = 9'((width + 12'd7) >> 3);
	endfunction

	function automatic logic [8:0] vfb_tile_rows(
		input logic [11:0] height
	);
		vfb_tile_rows = 9'((height + 12'd7) >> 3);
	endfunction

	function automatic logic [14:0] vfb_tile_row_addr(
		input logic [7:0] tile_y
	);
		logic [15:0] row_base;
		begin
			row_base          = ({8'd0, tile_y} << 7) + ({8'd0, tile_y} << 6);
			vfb_tile_row_addr = row_base[14:0];
		end
	endfunction

	function automatic logic [14:0] vfb_linear_tile_addr(
		input logic [15:0] tile_id
	);
		vfb_linear_tile_addr = vfb_tile_row_addr(tile_id[15:8]) + {7'd0, tile_id[7:0]};
	endfunction

	function automatic logic [15:0] vfb_tilemap_entries(
		input logic [8:0] rows
	);
		vfb_tilemap_entries = ({7'd0, rows} << 7) + ({7'd0, rows} << 6);
	endfunction

	// Intra-frame decay factors for the stored pixel's physical age.
	function automatic [7:0] vfb_decay_factor(
		input logic [1:0] mode,
		input logic [3:0] age
	);
		begin
			case ({mode, age})
				{2'd1, 4'd0}:  vfb_decay_factor = 8'd255;
				{2'd1, 4'd1}:  vfb_decay_factor = 8'd240;
				{2'd1, 4'd2}:  vfb_decay_factor = 8'd225;
				{2'd1, 4'd3}:  vfb_decay_factor = 8'd212;
				{2'd1, 4'd4}:  vfb_decay_factor = 8'd199;
				{2'd1, 4'd5}:  vfb_decay_factor = 8'd187;
				{2'd1, 4'd6}:  vfb_decay_factor = 8'd176;
				{2'd1, 4'd7}:  vfb_decay_factor = 8'd165;
				{2'd1, 4'd8}:  vfb_decay_factor = 8'd155;
				{2'd1, 4'd9}:  vfb_decay_factor = 8'd146;
				{2'd1, 4'd10}: vfb_decay_factor = 8'd137;
				{2'd1, 4'd11}: vfb_decay_factor = 8'd129;
				{2'd1, 4'd12}: vfb_decay_factor = 8'd121;
				{2'd1, 4'd13}: vfb_decay_factor = 8'd114;
				{2'd1, 4'd14}: vfb_decay_factor = 8'd107;
				{2'd1, 4'd15}: vfb_decay_factor = 8'd101;
				{2'd2, 4'd0}:  vfb_decay_factor = 8'd255;
				{2'd2, 4'd1}:  vfb_decay_factor = 8'd245;
				{2'd2, 4'd2}:  vfb_decay_factor = 8'd235;
				{2'd2, 4'd3}:  vfb_decay_factor = 8'd226;
				{2'd2, 4'd4}:  vfb_decay_factor = 8'd217;
				{2'd2, 4'd5}:  vfb_decay_factor = 8'd208;
				{2'd2, 4'd6}:  vfb_decay_factor = 8'd200;
				{2'd2, 4'd7}:  vfb_decay_factor = 8'd192;
				{2'd2, 4'd8}:  vfb_decay_factor = 8'd184;
				{2'd2, 4'd9}:  vfb_decay_factor = 8'd177;
				{2'd2, 4'd10}: vfb_decay_factor = 8'd170;
				{2'd2, 4'd11}: vfb_decay_factor = 8'd163;
				{2'd2, 4'd12}: vfb_decay_factor = 8'd156;
				{2'd2, 4'd13}: vfb_decay_factor = 8'd150;
				{2'd2, 4'd14}: vfb_decay_factor = 8'd144;
				{2'd2, 4'd15}: vfb_decay_factor = 8'd138;
				{2'd3, 4'd0}:  vfb_decay_factor = 8'd255;
				{2'd3, 4'd1}:  vfb_decay_factor = 8'd250;
				{2'd3, 4'd2}:  vfb_decay_factor = 8'd245;
				{2'd3, 4'd3}:  vfb_decay_factor = 8'd240;
				{2'd3, 4'd4}:  vfb_decay_factor = 8'd235;
				{2'd3, 4'd5}:  vfb_decay_factor = 8'd230;
				{2'd3, 4'd6}:  vfb_decay_factor = 8'd225;
				{2'd3, 4'd7}:  vfb_decay_factor = 8'd221;
				{2'd3, 4'd8}:  vfb_decay_factor = 8'd216;
				{2'd3, 4'd9}:  vfb_decay_factor = 8'd212;
				{2'd3, 4'd10}: vfb_decay_factor = 8'd208;
				{2'd3, 4'd11}: vfb_decay_factor = 8'd204;
				{2'd3, 4'd12}: vfb_decay_factor = 8'd200;
				{2'd3, 4'd13}: vfb_decay_factor = 8'd196;
				{2'd3, 4'd14}: vfb_decay_factor = 8'd192;
				{2'd3, 4'd15}: vfb_decay_factor = 8'd188;
				default:       vfb_decay_factor = 8'd255;
			endcase
		end
	endfunction

	function automatic [7:0] vfb_apply_curve_gain(
		input logic [7:0] curved,
		input logic [9:0] gain
	);
		logic [11:0] scaled;
		logic [8:0]  scaled9;
		begin
			scaled  = 12'd0;
			scaled9 =  9'd0;
			case (gain)
				10'd64:  begin
					vfb_apply_curve_gain = {2'b00, curved[7:2]};
				end
				10'd96:  begin
					scaled               = ({4'd0, curved} << 1) + {4'd0, curved} + 12'd4;
					vfb_apply_curve_gain = {1'b0, scaled[9:3]};
				end
				10'd128: begin
					vfb_apply_curve_gain = {1'b0, curved[7:1]};
				end
				10'd192: begin
					scaled               = ({4'd0, curved} << 1) + {4'd0, curved} + 12'd2;
					vfb_apply_curve_gain = scaled[9:2];
				end
				10'd256: begin
					vfb_apply_curve_gain = curved;
				end
				10'd320: begin
					scaled               = ({4'd0, curved} << 2) + {4'd0, curved} + 12'd2;
					scaled9              = scaled[10:2];
					vfb_apply_curve_gain = scaled9[8] ? 8'hff : scaled9[7:0];
				end
				10'd384: begin
					scaled               = ({4'd0, curved} << 1) + {4'd0, curved} + 12'd1;
					scaled9              = scaled[9:1];
					vfb_apply_curve_gain = scaled9[8] ? 8'hff : scaled9[7:0];
				end
				default: begin
					vfb_apply_curve_gain = curved[7] ? 8'hff : {curved[6:0], 1'b0};
				end
			endcase
		end
	endfunction

	function automatic [2:0] vfb_halo_row_bank(input logic [7:0] y);
		logic [4:0] folded;
		begin
			// 16 is congruent to 1 modulo five; the nibble sum is at most 30.
			folded = {1'b0, y[7:4]} + {1'b0, y[3:0]};
			case (folded)
				5'd0, 5'd5, 5'd10, 5'd15, 5'd20, 5'd25, 5'd30: vfb_halo_row_bank = 3'd0;
				5'd1, 5'd6, 5'd11, 5'd16, 5'd21, 5'd26:        vfb_halo_row_bank = 3'd1;
				5'd2, 5'd7, 5'd12, 5'd17, 5'd22, 5'd27:        vfb_halo_row_bank = 3'd2;
				5'd3, 5'd8, 5'd13, 5'd18, 5'd23, 5'd28:        vfb_halo_row_bank = 3'd3;
				default:                                       vfb_halo_row_bank = 3'd4;
			endcase
		end
	endfunction

endpackage
