// ============================================================================
// Vector pixel FIFO and rasterizer.
// Written 2026 by Videodr0me
// Transfers source pixels to the framebuffer clock and applies the selected
// dot scale and diagonal-fill processing.
// ============================================================================

module vfb_rasterizer #(
	parameter TILE_SIZE   =  8,
	parameter FIFO_ADDR_W = 10
) (
	input  logic clk_sys,
	input  logic clk_12,
	input  logic reset,

	// Vector input
	input  logic [10:0] X_VECTOR,
	input  logic [10:0] Y_VECTOR,
	input  logic [8:0]  Z_VECTOR,
	input  logic [2:0]  COLOR,
	input  logic        IS_DOT,
	input  logic        BEAM_ON,
	input  logic        FRAME_DONE,
	input  logic [2:0]  DOT_MODE,
	input  logic [11:0] FB_WIDTH,
	input  logic [11:0] FB_HEIGHT,

	// Tile cache output
	output logic        pixel_valid,
	input  logic        pixel_ready,
	output logic [15:0] pixel_tile_id,
	output logic [5:0]  pixel_offset,
	output logic [15:0] pixel_data,
	input  logic [3:0]  draw_idx,         // Pixel draw-time phase
	input  logic [15:0] frame_tick_clks,  // Source clocks per draw-index phase
	input  logic [3:0]  completed_frame_age,

	output logic        eof_token,
	output logic [3:0]  eof_frame_age,
	output logic        fifo_high_water_led,
	output logic        fifo_empty
);

	initial begin
		if (TILE_SIZE != 8)
			$error("vfb_rasterizer TILE_SIZE must be 8");
	end

	localparam FIFO_DEPTH = 1 << FIFO_ADDR_W;
	localparam FIFO_PTR_W = FIFO_ADDR_W + 1;
	import vfb_control_pkg::*;
	logic [2:0] dot_mode_q = DOT_1X;

	always_ff @(posedge clk_sys)
		dot_mode_q <= DOT_MODE;

	function [FIFO_PTR_W-1:0] b2g(input [FIFO_PTR_W-1:0] b);
		b2g = b ^ (b >> 1);
	endfunction

	function [FIFO_PTR_W-1:0] g2b(input [FIFO_PTR_W-1:0] g);
		logic [FIFO_PTR_W-1:0] b;
		begin
			b[FIFO_PTR_W-1] = g[FIFO_PTR_W-1];
			for (int i=FIFO_PTR_W-2; i>=0; i=i-1)
				b[i] = b[i+1] ^ g[i];
			g2b = b;
		end
	endfunction

	// The FIFO lets vector drawing continue while the framebuffer is busy.
	(* ramstyle = "M10K" *) logic [35:0] fifo_mem [0:FIFO_DEPTH-1];

	logic [FIFO_PTR_W-1:0] wr_ptr   = 0;
	logic [FIFO_PTR_W-1:0] wr_ptr_g = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr   = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr_g = 0;

	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] wr_ptr_g_sync1    = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] wr_ptr_g_sync2    = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] rd_ptr_g_sync1_12 = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [FIFO_PTR_W-1:0] rd_ptr_g_sync2_12 = 0;

	// Retain a one-render-clock reset until the source has cleared its pointer.
	// Complete the request/acknowledge cycle before releasing the reader, then
	// let the writer restart only after that release reaches the source clock.
	logic reset_req    = 1'b1;
	logic fifo_run     = 1'b0;
	logic reset_ack_12 = 1'b0;

	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [1:0] reset_req_sync_12 = 2'b11;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [1:0] fifo_run_sync_12  = 2'b00;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [1:0] reset_ack_sync    = 2'b00;

	always_ff @(posedge clk_sys) begin
		reset_ack_sync <= {reset_ack_sync[0], reset_ack_12};
		if (reset) begin
			reset_req <= 1'b1;
			fifo_run  <= 1'b0;
		end else if (reset_req) begin
			if (reset_ack_sync[1]) reset_req <= 1'b0;
		end else if (!reset_ack_sync[1]) begin
			fifo_run <= 1'b1;
		end
	end

	always_ff @(posedge clk_12) begin
		reset_req_sync_12 <= {reset_req_sync_12[0], reset_req};
		fifo_run_sync_12  <= {fifo_run_sync_12[0], fifo_run};
		reset_ack_12      <= reset_req_sync_12[1];
	end

	wire rst_sys = !fifo_run;
	wire rst_12  = reset_req_sync_12[1] || !fifo_run_sync_12[1];

	// Source-clock side
	logic [10:0] last_x          = 0;
	logic [10:0] last_y          = 0;
	logic        last_beam_on    = 0;
	logic        last_frame_done = 0;

	wire push_eof = (FRAME_DONE && !last_frame_done);
	wire push_pix = (BEAM_ON && (X_VECTOR != last_x || Y_VECTOR != last_y || !last_beam_on));
	wire fifo_we  = push_eof || push_pix;

	wire [35:0] fifo_din = push_eof ? {
		1'b1, 15'd0, completed_frame_age, frame_tick_clks
	} : {
		1'b0,          // 35
		IS_DOT,        // 34
		Z_VECTOR[8],   // 33 = energy headroom
		COLOR,         // 32:30 = RGB
		Y_VECTOR,      // 29:19
		X_VECTOR,      // 18:8
		Z_VECTOR[7:0]  // 7:0
	};

	wire [FIFO_PTR_W-1:0] wr_ptr_next   = wr_ptr + 1'b1;
	wire [FIFO_PTR_W-1:0] wr_ptr_g_next = b2g(wr_ptr_next);
	wire                  fifo_full_12  = (wr_ptr_g_next ==
	                                       {~rd_ptr_g_sync2_12[FIFO_PTR_W-1:FIFO_PTR_W-2],
	                                        rd_ptr_g_sync2_12[FIFO_PTR_W-3:0]});

	// Synchronize the Gray-coded read pointer into clk_12 for full-FIFO detection.
	always_ff @(posedge clk_12) begin
		if (rst_12) begin
			rd_ptr_g_sync1_12 <= 0;
			rd_ptr_g_sync2_12 <= 0;
		end else begin
			rd_ptr_g_sync1_12 <= rd_ptr_g;
			rd_ptr_g_sync2_12 <= rd_ptr_g_sync1_12;
		end
	end

	always_ff @(posedge clk_12) begin
		last_x          <= X_VECTOR;
		last_y          <= Y_VECTOR;
		last_beam_on    <= BEAM_ON;
		last_frame_done <= FRAME_DONE;

		if (rst_12) begin
			wr_ptr   <= 0;
			wr_ptr_g <= 0;
		end else if (fifo_we) begin
			if (!fifo_full_12) begin
				fifo_mem[wr_ptr[FIFO_ADDR_W-1:0]] <= fifo_din;
				wr_ptr                            <= wr_ptr_next;
				wr_ptr_g                          <= wr_ptr_g_next;
			end
		end
	end

	// Framebuffer-clock side
	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			wr_ptr_g_sync1 <= 0;
			wr_ptr_g_sync2 <= 0;
		end else begin
			wr_ptr_g_sync1 <= wr_ptr_g;
			wr_ptr_g_sync2 <= wr_ptr_g_sync1;
		end
	end
	assign fifo_empty = (rd_ptr_g == wr_ptr_g_sync2);

	// FIFO high-water LED, held for about 73 ms at the renderer clock.
	wire  [FIFO_PTR_W-1:0] wr_ptr_bin      = g2b(wr_ptr_g_sync2);
	wire  [FIFO_PTR_W-1:0] fifo_used       = wr_ptr_bin - rd_ptr;
	logic                  fifo_high_water = 1'b0;
	always_ff @(posedge clk_sys)
		fifo_high_water <= (fifo_used > FIFO_PTR_W'(128));

	localparam logic [23:0] LED_HOLD_CYCLES = 24'd9_349_794;
	logic [23:0]            led_timer       =             0;
	always_ff @(posedge clk_sys) begin
		if (fifo_high_water) led_timer <= LED_HOLD_CYCLES;
		else if (led_timer != 0) led_timer <= led_timer - 1'b1;
	end
	assign fifo_high_water_led = (led_timer != 0);

	// Flow: FIFO -> input register -> expansion stage -> tile cache.
	// The input register holds one FIFO entry. The expansion stage emits the
	// source pixel, then any diagonal-fill or dot-scale pixels.
	//   B_IDLE      - accept and emit a source pixel
	//   B_CHECK_SUB - choose and emit a diagonal-fill pixel
	//   B_DOT_SUB   - emit dot-scale pixels

	// Input register
	logic [35:0] a_data;
	logic        a_valid = 0;
	wire         a_ready;

	wire a_fifo_read = !fifo_empty && (!a_valid || a_ready);

	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			a_valid  <= 0;
			rd_ptr   <= 0;
			rd_ptr_g <= 0;
		end else begin
			if (a_ready && a_valid) a_valid <= 0;
			if (a_fifo_read) begin
				a_data   <= fifo_mem[rd_ptr[FIFO_ADDR_W-1:0]];
				rd_ptr   <= rd_ptr + 1'b1;
				rd_ptr_g <= b2g(rd_ptr + 1'b1);
				a_valid  <= 1;
			end
		end
	end

	wire [10:0] a_x      = a_data[18:8];
	wire [10:0] a_y      = a_data[29:19];
	wire [8:0]  a_z      = {a_data[33], a_data[7:0]};
	wire [2:0]  a_c      = a_data[32:30];
	wire        a_is_dot = a_data[34];
	wire        a_eof    = a_data[35];
	wire [2:0]  a_dot    = dot_mode_q;

	// Expansion state
	typedef enum logic [1:0] {
		B_IDLE,
		B_CHECK_SUB,
		B_DOT_SUB
	} b_state_t;

	b_state_t b_state = B_IDLE;

	logic [10:0] s2_out_x;
	logic [10:0] s2_out_y;
	logic [8:0]  s2_out_z;
	logic [2:0]  s2_out_c;
	logic        s2_out_valid           = 0;
	logic [15:0] s2_eof_frame_tick_clks = 0;
	logic [3:0]  s2_eof_frame_age       = 0;

	wire   b_output_free = pixel_ready || !s2_out_valid;
	assign pixel_valid   = s2_out_valid;

	// Two possible pixels for filling a diagonal step.
	logic [10:0] pending_sub_x;
	logic [10:0] pending_sub_y;
	logic [8:0]  pending_sub_z;
	logic [2:0]  pending_sub_c;
	logic [10:0] pending_alt_x;
	logic [10:0] pending_alt_y;
	logic        pending_is_xdom;

	// Keep the previous two source positions.
	logic [10:0] hist_x [2];
	logic [10:0] hist_y [2];
	logic [1:0]  hist_count = 0;

	logic [10:0] read_last_x = 0;
	logic [10:0] read_last_y = 0;

	// Dot-scale state
	logic        [4:0]  dot_idx;
	logic        [4:0]  dot_last_idx;
	logic        [2:0]  dot_mode;
	logic        [8:0]  dot_base_z;
	logic        [2:0]  dot_base_c;
	logic        [10:0] dot_x, dot_y;
	logic signed [2:0]  dot_offset_x;
	logic signed [2:0]  dot_offset_y;

	function automatic logic [5:0] dot_offset_for(
		input logic [2:0] mode,
		input logic [4:0] index
	);
		logic signed [2:0] dx;
		logic signed [2:0] dy;
		begin
			dx = 3'sd0;
			dy = 3'sd0;
			case (mode)
			DOT_15X: dx = 3'sd1;

			DOT_2X: begin
				case (index)
					5'd0:    dx = 3'sd1;
					5'd1:    dy = 3'sd1;
					default: begin dx = 3'sd1; dy = 3'sd1; end
				endcase
			end

			DOT_25X: begin
				case (index)
					5'd0:    dx = 3'sd1;
					5'd1:    dx = 3'sd2;
					5'd2:    dy = 3'sd1;
					5'd3:    begin dx = 3'sd1; dy = 3'sd1; end
					default: begin dx = 3'sd2; dy = 3'sd1; end
				endcase
			end

			DOT_3X: begin
				case (index)
					5'd0:    begin dx = -3'sd1; dy = -3'sd1; end
					5'd1:    dy = -3'sd1;
					5'd2:    begin dx = 3'sd1; dy = -3'sd1; end
					5'd3:    dx = -3'sd1;
					5'd4:    dx = 3'sd1;
					5'd5:    begin dx = -3'sd1; dy = 3'sd1; end
					5'd6:    dy = 3'sd1;
					default: begin dx = 3'sd1; dy = 3'sd1; end
				endcase
			end

			DOT_4X: begin
				case (index)
					5'd0:    begin dx = -3'sd2; dy = -3'sd1; end
					5'd1:    begin dx = -3'sd1; dy = -3'sd1; end
					5'd2:    dy = -3'sd1;
					5'd3:    begin dx = 3'sd1; dy = -3'sd1; end
					5'd4:    dx = -3'sd2;
					5'd5:    dx = -3'sd1;
					5'd6:    dx = 3'sd1;
					5'd7:    begin dx = -3'sd2; dy = 3'sd1; end
					5'd8:    begin dx = -3'sd1; dy = 3'sd1; end
					5'd9:    dy = 3'sd1;
					5'd10:   begin dx = 3'sd1; dy = 3'sd1; end
					5'd11:   begin dx = -3'sd2; dy = 3'sd2; end
					5'd12:   begin dx = -3'sd1; dy = 3'sd2; end
					5'd13:   dy = 3'sd2;
					default: begin dx = 3'sd1; dy = 3'sd2; end
				endcase
			end

			DOT_5X: begin
				case (index)
					5'd0:    begin dx = -3'sd1; dy = -3'sd2; end
					5'd1:    dy = -3'sd2;
					5'd2:    begin dx = 3'sd1; dy = -3'sd2; end
					5'd3:    begin dx = -3'sd2; dy = -3'sd1; end
					5'd4:    begin dx = -3'sd1; dy = -3'sd1; end
					5'd5:    dy = -3'sd1;
					5'd6:    begin dx = 3'sd1; dy = -3'sd1; end
					5'd7:    begin dx = 3'sd2; dy = -3'sd1; end
					5'd8:    dx = -3'sd2;
					5'd9:    dx = -3'sd1;
					5'd10:   dx = 3'sd1;
					5'd11:   dx = 3'sd2;
					5'd12:   begin dx = -3'sd2; dy = 3'sd1; end
					5'd13:   begin dx = -3'sd1; dy = 3'sd1; end
					5'd14:   dy = 3'sd1;
					5'd15:   begin dx = 3'sd1; dy = 3'sd1; end
					5'd16:   begin dx = 3'sd2; dy = 3'sd1; end
					5'd17:   begin dx = -3'sd1; dy = 3'sd2; end
					5'd18:   dy = 3'sd2;
					default: begin dx = 3'sd1; dy = 3'sd2; end
				endcase
			end

			default: begin end
			endcase
			dot_offset_for = {dx, dy};
		end
	endfunction

	wire [5:0]  dot_first_offset    = dot_offset_for(a_dot, 5'd0);
	wire [5:0]  dot_next_offset     = dot_offset_for(dot_mode, dot_idx + 5'd1);
	wire [11:0] dot_candidate_x     = {1'b0, dot_x} + {{9{dot_offset_x[2]}}, dot_offset_x};
	wire [11:0] dot_candidate_y     = {1'b0, dot_y} + {{9{dot_offset_y[2]}}, dot_offset_y};
	wire        dot_candidate_valid = (dot_candidate_x < FB_WIDTH) && (dot_candidate_y < FB_HEIGHT);

	function automatic logic unit_step(input logic [10:0] a, b);
		logic [11:0] difference;
		// Widen before subtracting so zero and 2047 are not adjacent.
		difference = {1'b0, a} - {1'b0, b};
		unit_step  = (difference == 12'h001) || (difference == 12'hfff);
	endfunction

	// Classify the current step without constructing an absolute distance.
	wire step_x_equal   = (a_x == read_last_x);
	wire step_y_equal   = (a_y == read_last_y);
	wire step_x_unit    = unit_step(a_x, read_last_x);
	wire step_y_unit    = unit_step(a_y, read_last_y);
	wire step_is_diag   = (hist_count != 0) && step_x_unit && step_y_unit;
	wire primary_is_dot = a_is_dot && (a_dot != DOT_1X) && (a_dot <= DOT_5X);
	wire is_neighbor    = (step_x_equal || step_x_unit) && (step_y_equal || step_y_unit);

	assign a_ready = a_valid && b_output_free && (b_state == B_IDLE);

	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			s2_out_valid           <=     0;
			eof_token              <=     0;
			s2_eof_frame_tick_clks <= 16'd0;
			s2_eof_frame_age       <=  4'd0;
			b_state                <= B_IDLE;
			hist_count             <= 0;
		end else begin
			if (pixel_ready) begin
				s2_out_valid <= 0;
				eof_token    <= 0;
			end

			case (b_state)
			B_IDLE: begin
				if (a_valid && b_output_free) begin
					if (a_eof) begin
						hist_count             <= 0;
						eof_token              <= 1;
						s2_out_valid           <= 1;
						s2_eof_frame_tick_clks <= a_data[15:0];
						s2_eof_frame_age       <= a_data[19:16];
					end else begin
						s2_out_x     <= a_x;
						s2_out_y     <= a_y;
						s2_out_z     <= a_z;
						s2_out_c     <= a_c;
						s2_out_valid <= 1;

						hist_x[1]  <= hist_x[0];
						hist_y[1]  <= hist_y[0];
						hist_x[0]  <= a_x;
						hist_y[0]  <= a_y;
						hist_count <= is_neighbor ? ((hist_count < 2'd2) ? hist_count + 2'd1 : 2'd2)
						                          : 2'd1;

						if (primary_is_dot) begin
							b_state                      <= B_DOT_SUB;
							dot_mode                     <= a_dot;
							dot_idx                      <= 5'd0;
							{dot_offset_x, dot_offset_y} <= dot_first_offset;
							dot_last_idx                 <= (a_dot == DOT_15X) ? 5'd0 :
							                                (a_dot == DOT_2X) ? 5'd2 :
							                                    (a_dot == DOT_25X) ? 5'd4 :
							                                        (a_dot == DOT_3X) ? 5'd7 :
							                                            (a_dot == DOT_4X) ? 5'd14 :
							                                                5'd19;
							dot_base_z                   <= a_z;
							dot_base_c                   <= a_c;
							dot_x                        <= a_x;
							dot_y                        <= a_y;
						end else if (step_is_diag) begin
							// Keep both fill choices until the next source pixel.
							if (hist_count >= 2'd2 && hist_x[0] == hist_x[1] && hist_y[0] != hist_y[1]) begin
								// After a vertical step, keep the fill on the new x coordinate.
								pending_sub_x   <= a_x;
								pending_sub_y   <= read_last_y;
								pending_alt_x   <= read_last_x;
								pending_alt_y   <= a_y;
								pending_is_xdom <= 1;
							end else begin
								// Otherwise keep the fill on the new y coordinate.
								pending_sub_x   <= read_last_x;
								pending_sub_y   <= a_y;
								pending_alt_x   <= a_x;
								pending_alt_y   <= read_last_y;
								pending_is_xdom <= 0;
							end
							pending_sub_z <= a_z;
							pending_sub_c <= a_c;
							b_state       <= B_CHECK_SUB;
						end

						read_last_x <= a_x;
						read_last_y <= a_y;
					end
				end
			end

			// If the preferred fill meets the next source pixel, use the other corner.
			B_CHECK_SUB: begin
				if (a_valid && b_output_free) begin
					if (!a_eof && (pending_is_xdom ? (a_x == pending_sub_x) : (a_y == pending_sub_y))) begin
						s2_out_x <= pending_alt_x;
						s2_out_y <= pending_alt_y;
					end else begin
						s2_out_x <= pending_sub_x;
						s2_out_y <= pending_sub_y;
					end
					s2_out_z     <= pending_sub_z;
					s2_out_c     <= pending_sub_c;
					s2_out_valid <= 1;
					b_state      <= B_IDLE;
				end
			end

			B_DOT_SUB: begin
				if (b_output_free) begin
					if (dot_candidate_valid) begin
						s2_out_x     <= dot_candidate_x[10:0];
						s2_out_y     <= dot_candidate_y[10:0];
						s2_out_z     <= dot_base_z;
						s2_out_c     <= dot_base_c;
						s2_out_valid <= 1;
					end

					if (dot_idx == dot_last_idx) begin
						b_state <= B_IDLE;
					end else begin
						dot_idx                      <= dot_idx + 5'd1;
						{dot_offset_x, dot_offset_y} <= dot_next_offset;
					end
				end
			end
			endcase
		end
	end

	assign pixel_tile_id = {s2_out_y[10:3], s2_out_x[10:3]};
	assign pixel_offset  = {s2_out_y[2:0],  s2_out_x[2:0]};
	assign pixel_data    = eof_token ? s2_eof_frame_tick_clks : {s2_out_c, draw_idx, s2_out_z};
	assign eof_frame_age = s2_eof_frame_age;

endmodule
