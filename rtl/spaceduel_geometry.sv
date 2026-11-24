//============================================================================
//  Space Duel vector geometry
//
//  Written 2026 by Videodr0me
//
//  Maps the signed AVG coordinate field into the selected raster mode.
//============================================================================

module spaceduel_geometry
(
	input  logic signed [14:0] source_x,
	input  logic signed [14:0] source_y,
	input  logic               hardware_flip_x,
	input  logic               hardware_flip_y,
	input  logic               mode_1080p,
	input  logic               mode_480p,
	input  logic               mode_240p,
	input  logic        [11:0] center_x,
	input  logic        [11:0] center_y,
	input  logic        [11:0] render_width,
	input  logic        [11:0] render_height,
	input  logic         [2:0] orientation,
	input  logic               zoom_wide,
	output logic signed [23:0] raster_x,
	output logic signed [23:0] raster_y,
	output logic               beam_in_bounds
);

	// Scale numerator over 4096. The 720-wide modes apply another 9/8
	// horizontally so their physical framing matches the square-pixel modes.
	localparam logic [8:0] SCALE_1080              = 9'd344;
	localparam logic [8:0] SCALE_1080_WIDE         = 9'd301;
	localparam logic [8:0] SCALE_720               = 9'd228;
	localparam logic [8:0] SCALE_720_WIDE          = 9'd200;
	localparam logic [8:0] SCALE_LOW               = 9'd152;
	localparam logic [8:0] SCALE_LOW_WIDE          = 9'd133;
	localparam logic [8:0] SCALE_1080_QUARTER      = 9'd269;
	localparam logic [8:0] SCALE_1080_QUARTER_WIDE = 9'd220;
	localparam logic [8:0] SCALE_720_QUARTER       = 9'd179;
	localparam logic [8:0] SCALE_720_QUARTER_WIDE  = 9'd146;
	localparam logic [8:0] SCALE_480_QUARTER       = 9'd106;
	localparam logic [8:0] SCALE_480_QUARTER_WIDE  =  9'd88;
	localparam logic [8:0] SCALE_240_QUARTER       = 9'd105;
	localparam logic [8:0] SCALE_240_QUARTER_WIDE  =  9'd87;

	logic         [8:0] scale_num;
	logic               quarter_turn;
	logic signed [15:0] flipped_x;
	logic signed [15:0] flipped_y;
	logic signed [25:0] product_x;
	logic signed [25:0] product_y;
	logic signed [28:0] product_x_9;
	logic signed [23:0] scaled_x;
	logic signed [23:0] scaled_y;
	logic signed [23:0] selected_x;
	logic signed [23:0] selected_y;
	logic signed [23:0] oriented_x;
	logic signed [23:0] oriented_y;
	logic signed [23:0] presented_y;
	logic               negate_x;
	logic               negate_y;

	always_comb begin
		quarter_turn = vfb_control_pkg::orientation_swaps_axes(orientation);

		if (mode_1080p)
			scale_num = quarter_turn ? (zoom_wide ? SCALE_1080_QUARTER_WIDE : SCALE_1080_QUARTER)
			                         : (zoom_wide ? SCALE_1080_WIDE : SCALE_1080);
		else if (mode_480p)
			scale_num = quarter_turn ? (zoom_wide ? SCALE_480_QUARTER_WIDE : SCALE_480_QUARTER)
			                         : (zoom_wide ? SCALE_LOW_WIDE : SCALE_LOW);
		else if (mode_240p)
			scale_num = quarter_turn ? (zoom_wide ? SCALE_240_QUARTER_WIDE : SCALE_240_QUARTER)
			                         : (zoom_wide ? SCALE_LOW_WIDE : SCALE_LOW);
		else
			scale_num = quarter_turn ? (zoom_wide ? SCALE_720_QUARTER_WIDE : SCALE_720_QUARTER)
			                         : (zoom_wide ? SCALE_720_WIDE : SCALE_720);

		flipped_x   = hardware_flip_x ? -$signed({source_x[14], source_x})
		                              : $signed({source_x[14], source_x});
		flipped_y   = hardware_flip_y ? -$signed({source_y[14], source_y})
		                              : $signed({source_y[14], source_y});

		product_x   = flipped_x * $signed({1'b0, scale_num});
		product_y   = flipped_y * $signed({1'b0, scale_num});
		product_x_9 = $signed({{3{product_x[25]}}, product_x}) +
		              ($signed({{3{product_x[25]}}, product_x}) <<< 3);

		if (mode_480p || mode_240p)
			scaled_x = $signed(product_x_9[28:15]);
		else
			scaled_x = $signed(product_x[25:12]);
		scaled_y = $signed(product_y[25:12]);

		case (orientation)
			3'd0:    begin selected_x = scaled_x; negate_x = 1'b0;
			             selected_y = scaled_y; negate_y = 1'b1; end
			3'd1:    begin selected_x = scaled_y; negate_x = 1'b0;
			             selected_y = scaled_x; negate_y = 1'b0; end
			3'd2:    begin selected_x = scaled_x; negate_x = 1'b1;
			             selected_y = scaled_y; negate_y = 1'b0; end
			3'd3:    begin selected_x = scaled_y; negate_x = 1'b1;
			             selected_y = scaled_x; negate_y = 1'b1; end
			3'd4:    begin selected_x = scaled_x; negate_x = 1'b1;
			             selected_y = scaled_y; negate_y = 1'b1; end
			3'd5:    begin selected_x = scaled_x; negate_x = 1'b0;
			             selected_y = scaled_y; negate_y = 1'b0; end
			3'd6:    begin selected_x = scaled_y; negate_x = 1'b0;
			             selected_y = scaled_x; negate_y = 1'b1; end
			default: begin selected_x = scaled_y; negate_x = 1'b1;
			               selected_y = scaled_x; negate_y = 1'b0; end
		endcase

		oriented_x  = negate_x ? -selected_x : selected_x;
		presented_y = mode_240p ? (selected_y >>> 1) : selected_y;
		oriented_y  = negate_y ? -presented_y : presented_y;

		// Even raster dimensions are centered between the two middle pixels.
		// Apply the one-pixel correction only to a reflected axis.
		raster_x = $signed({12'd0, center_x}) - (negate_x ? 24'sd1 : 24'sd0) + oriented_x;
		raster_y = $signed({12'd0, center_y}) - (negate_y ? 24'sd1 : 24'sd0) + oriented_y;

		beam_in_bounds = (raster_x >= 24'sd0) && (raster_x < $signed({12'd0, render_width})) &&
		                 (raster_y >= 24'sd0) && (raster_y < $signed({12'd0, render_height}));
	end

endmodule
