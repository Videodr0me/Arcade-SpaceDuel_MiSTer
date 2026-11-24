// ============================================================================
// Phosphor timing.
// Written 2026 by Videodr0me
// Builds decay-age maps from measured frame durations.
// ============================================================================

module vfb_phosphor_timing #(
	parameter [15:0]  AGE_QUANTUM_CLKS     =  16'd18519,
	parameter [17:0]  SYS_AGE_QUANTUM_CLKS = 18'd196764,
	parameter integer BUFFER_COUNT         =          5,
	parameter integer BUF_IDX_W            =          3
) (
	input  logic clk_source,
	input  logic clk_sys,
	input  logic reset_source,
	input  logic reset_sys,
	input  logic frame_done,

	input logic                 eof_token_popped,
	input logic [15:0]          eof_frame_tick_clks_popped,
	input logic [3:0]           eof_frame_age_popped,
	input logic [BUF_IDX_W-1:0] buf_draw,
	input logic [BUF_IDX_W-1:0] buf_display,
	input logic                 vbl_swap_req,
	input logic                 presentation_120hz,
	input logic [1:0]           BUFFER_MODE,

	input  logic                 compose_req,
	input  logic [BUF_IDX_W-1:0] compose_buf,
	input  logic                 raw_frame_dropped,
	input  logic [BUF_IDX_W-1:0] raw_frame_dropped_buf,
	output logic [3:0]           compose_draw_idx,
	output logic [63:0]          compose_age_map,
	output logic [3:0]           compose_frame_age,

	output logic [3:0]  draw_idx,
	output logic [15:0] active_frame_tick_clks,
	output logic [3:0]  completed_frame_age,
	output logic [3:0]  readout_draw_idx,
	output logic [63:0] readout_age_map
);

	localparam [15:0] DEFAULT_TICK_CLKS     = (AGE_QUANTUM_CLKS == 16'd0) ? 16'd1 : AGE_QUANTUM_CLKS;
	localparam [16:0] AGE_QUANTUM_EXT       = {1'b0, DEFAULT_TICK_CLKS};
	localparam [16:0] AGE_HALF_QUANTUM      = {1'b0, (DEFAULT_TICK_CLKS >> 1)};
	localparam [17:0] SYS_DEFAULT_TICK_CLKS = (SYS_AGE_QUANTUM_CLKS == 18'd0) ?
	                                          18'd1 :
	                                          SYS_AGE_QUANTUM_CLKS;
	localparam [17:0] SYS_HALF_QUANTUM      = SYS_DEFAULT_TICK_CLKS >> 1;
	localparam [63:0] IDENTITY_AGE_MAP      = 64'hFEDCBA9876543210;

	// Convert frame duration to rounded decay-age units, capped at 15.
	// Calculate this metadata in clk_source before writing the EOF token.
	function automatic [3:0] elapsed_age_from_tick(input logic [15:0] tick_clks);
		begin
			elapsed_age_from_tick = 4'd0;
			for (int age = 1; age <= 15; age++) begin
				if (tick_clks >= 16'((age * DEFAULT_TICK_CLKS - AGE_HALF_QUANTUM + 15) / 16))
					elapsed_age_from_tick = 4'(age);
			end
		end
	endfunction

	function automatic [15:0] frame_tick_from_period(input logic [19:0] period);
		logic [16:0] rounded_tick;
		begin
			if (period[19:4] == 16'hffff) begin
				frame_tick_from_period = 16'hffff;
			end else begin
				rounded_tick           = {1'b0, period[19:4]} + {16'd0, period[3]};
				frame_tick_from_period = (rounded_tick == 17'd0) ? 16'd1 : rounded_tick[15:0];
			end
		end
	endfunction

	logic        frame_done_q;
	logic        have_eof_reference;
	logic [19:0] eof_period_count;
	logic [15:0] draw_tick_count;
	logic [3:0]  draw_idx_source;
	logic [3:0]  draw_gray_source;
	wire  [3:0]  draw_idx_next = draw_idx_source + 4'd1;

	wire          frame_done_rise           = frame_done && !frame_done_q;
	wire   [15:0] measured_frame_tick_clks  = frame_tick_from_period(eof_period_count);
	wire   [15:0] completed_frame_tick_clks = have_eof_reference ? measured_frame_tick_clks
	                                                             : active_frame_tick_clks;
	assign        completed_frame_age       = elapsed_age_from_tick(completed_frame_tick_clks);

	always_ff @(posedge clk_source) begin
		if (reset_source) begin
			frame_done_q           <=  1'b0;
			have_eof_reference     <=  1'b0;
			eof_period_count       <= 20'd0;
			draw_tick_count        <= 16'd0;
			draw_idx_source        <=  4'd0;
			draw_gray_source       <=  4'd0;
			active_frame_tick_clks <= DEFAULT_TICK_CLKS;
		end else begin
			frame_done_q <= frame_done;

			if (draw_tick_count >= active_frame_tick_clks - 16'd1) begin
				draw_tick_count  <= 16'd0;
				draw_idx_source  <= draw_idx_next;
				draw_gray_source <= draw_idx_next ^ (draw_idx_next >> 1);
			end else begin
				draw_tick_count <= draw_tick_count + 16'd1;
			end

			if (frame_done_rise) begin
				eof_period_count <= 20'd1;
				if (have_eof_reference)
					active_frame_tick_clks <= measured_frame_tick_clks;
				else
					have_eof_reference <= 1'b1;
			end else if (eof_period_count != 20'hfffff) begin
				eof_period_count <= eof_period_count + 20'd1;
			end
		end
	end

	// A source reset can change several Gray bits at once. Mask the receiver
	// immediately and release only after both data synchronizer stages settle.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [2:0] draw_reset_sync = 3'b111;
	always_ff @(posedge clk_sys or posedge reset_source) begin
		if (reset_source) draw_reset_sync <= 3'b111;
		else              draw_reset_sync <= {draw_reset_sync[1:0], 1'b0};
	end

	logic       draw_reset_sys_q;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [3:0] draw_gray_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	logic [3:0] draw_gray_sync;
	always_ff @(posedge clk_sys) begin
		draw_gray_meta   <= draw_gray_source;
		draw_reset_sys_q <= reset_sys;
		// Preserve the zero sample on the first clock after receiver reset.
		if (reset_sys || draw_reset_sys_q) begin
			draw_gray_sync <= 4'd0;
		end else begin
			draw_gray_sync <= draw_gray_meta;
		end
	end
	assign draw_idx = draw_reset_sync[2] ?
	                  4'd0 :
	                  {draw_gray_sync[3], ^draw_gray_sync[3:2],
	                   ^draw_gray_sync[3:1], ^draw_gray_sync};

	logic [63:0] buf_age_map [0:BUFFER_COUNT-1];
	logic [3:0]  buf_frame_age [0:BUFFER_COUNT-1];
	// Carry dropped-frame age into the next composition, saturating at 15.
	logic                 compose_req_q;
	logic [3:0]           skipped_frame_age;
	logic [3:0]           compose_age_carry;
	logic                 map_busy;
	logic                 map_build_store_buffer;
	logic [BUF_IDX_W-1:0] map_build_buf;
	logic [3:0]           map_build_index;
	logic [3:0]           map_build_age;
	logic [15:0]          map_build_tick;
	logic [20:0]          map_build_remainder;
	logic [63:0]          map_build_data;
	logic                 map_commit_pending;
	logic [63:0]          latest_age_map;
	logic [BUF_IDX_W-1:0] prev_buf_display;
	logic                 have_vbl_reference;
	logic [17:0]          vbl_age_tick_count;
	logic [3:0]           vbl_elapsed_age;
	logic                 presentation_120hz_control_q = 1'b0;
	logic [1:0]           buffer_mode_q                = 2'd0;
	logic                 presentation_120hz_q;
	logic                 presentation_vbl_half;

	always_ff @(posedge clk_sys) begin
		presentation_120hz_control_q <= presentation_120hz;
		buffer_mode_q                <= BUFFER_MODE;
	end

	wire [15:0] popped_frame_tick_clks = (eof_frame_tick_clks_popped == 16'd0) ?
	                                     DEFAULT_TICK_CLKS :
	                                     eof_frame_tick_clks_popped;

	function automatic [3:0] saturating_age_sum(
		input logic [3:0] lhs,
		input logic [3:0] rhs
	);
		logic [4:0] sum;
		begin
			sum                = {1'b0, lhs} + {1'b0, rhs};
			saturating_age_sum = (sum > 5'd15) ? 4'd15 : sum[3:0];
		end
	endfunction

	// Pseudo-random reference phases for readout and composition.
	function automatic [15:0] phase_prng_next(input logic [15:0] state);
		begin
			phase_prng_next = {state[14:0], state[15] ^ state[13] ^ state[12] ^ state[10]};
		end
	endfunction

	logic [15:0] readout_phase_prng;
	logic [15:0] compose_phase_prng;
	wire  [15:0] readout_phase_prng_next = phase_prng_next(readout_phase_prng);
	wire  [15:0] compose_phase_prng_next = phase_prng_next(compose_phase_prng);

	wire [3:0] dropped_frame_age = buf_frame_age[raw_frame_dropped_buf];

	always_comb begin
		compose_age_map   = buf_age_map[compose_buf];
		compose_frame_age = saturating_age_sum(buf_frame_age[compose_buf], compose_age_carry);
	end

	always_ff @(posedge clk_sys) begin
		if (reset_sys) begin
			compose_req_q          <= 1'b0;
			skipped_frame_age      <= 4'd0;
			compose_age_carry      <= 4'd0;
			map_busy               <= 1'b0;
			map_build_store_buffer <= 1'b0;
			map_build_buf          <=   '0;
			map_build_index        <= 4'd0;
			map_build_age          <= 4'd0;
			map_build_tick         <= DEFAULT_TICK_CLKS;
			map_build_remainder    <= 21'd0;
			map_build_data         <= 64'd0;
			map_commit_pending     <=  1'b0;
			latest_age_map         <= IDENTITY_AGE_MAP;
			prev_buf_display       <=   '0;
			have_vbl_reference     <= 1'b0;
			vbl_age_tick_count     <= SYS_HALF_QUANTUM;
			vbl_elapsed_age        <=     4'd0;
			presentation_120hz_q   <=     1'b0;
			presentation_vbl_half  <=     1'b0;
			readout_draw_idx       <=     4'd0;
			compose_draw_idx       <=     4'd0;
			readout_phase_prng     <= 16'h1ace;
			compose_phase_prng     <= 16'hbeef;
			readout_age_map        <= IDENTITY_AGE_MAP;
			for (int i = 0; i < BUFFER_COUNT; i++) begin
				buf_age_map[i]   <= IDENTITY_AGE_MAP;
				buf_frame_age[i] <= 4'd0;
			end
		end else begin
			compose_req_q        <= compose_req;
			presentation_120hz_q <= presentation_120hz_control_q;

			// VBL-only mode measures elapsed age between display-swap requests.
			if (buffer_mode_q != 2'd1) begin
				have_vbl_reference <= 1'b0;
				vbl_age_tick_count <= SYS_HALF_QUANTUM;
				vbl_elapsed_age    <= 4'd0;
			end else if (vbl_swap_req) begin
				have_vbl_reference <= 1'b1;
				vbl_age_tick_count <= SYS_HALF_QUANTUM;
				vbl_elapsed_age    <= 4'd0;
			end else if (have_vbl_reference && (vbl_age_tick_count >= SYS_DEFAULT_TICK_CLKS - 18'd1)) begin
				vbl_age_tick_count <= 18'd0;
				if (vbl_elapsed_age != 4'd15) vbl_elapsed_age <= vbl_elapsed_age + 4'd1;
			end else if (have_vbl_reference) begin
				vbl_age_tick_count <= vbl_age_tick_count + 18'd1;
			end

			if (compose_req && !compose_req_q) begin
				compose_phase_prng <= compose_phase_prng_next;
				compose_draw_idx   <= compose_phase_prng_next[3:0];
				compose_age_carry  <= skipped_frame_age;
				skipped_frame_age  <= raw_frame_dropped ? dropped_frame_age : 4'd0;
			end else if (raw_frame_dropped) begin
				skipped_frame_age <= saturating_age_sum(skipped_frame_age, dropped_frame_age);
			end

			if (presentation_120hz_control_q != presentation_120hz_q) begin
				presentation_vbl_half <= 1'b0;
			end else if (vbl_swap_req) begin
				if (presentation_120hz_control_q) begin
					presentation_vbl_half <= ~presentation_vbl_half;
					if (!presentation_vbl_half) begin
						readout_phase_prng <= readout_phase_prng_next;
						readout_draw_idx   <= readout_phase_prng_next[3:0];
					end
				end else begin
					presentation_vbl_half <= 1'b0;
					readout_phase_prng    <= readout_phase_prng_next;
					readout_draw_idx      <= readout_phase_prng_next[3:0];
				end
			end

			prev_buf_display <= buf_display;
			if (vbl_swap_req || (buf_display != prev_buf_display)) begin
				readout_age_map <= buf_age_map[buf_display];
			end

			if (map_commit_pending) begin
				latest_age_map <= map_build_data;
				if (map_build_store_buffer) buf_age_map[map_build_buf] <= map_build_data;
				map_commit_pending <= 1'b0;
				map_busy           <= 1'b0;
			end else if (map_busy) begin
				if ((map_build_age == 4'd15) || (map_build_remainder < AGE_QUANTUM_EXT)) begin
					map_build_data[{map_build_index, 2'b00} +: 4] <= map_build_age;
					if (map_build_index == 4'd15) begin
						map_commit_pending <= 1'b1;
					end else begin
						map_build_index <= map_build_index + 4'd1;
						if (map_build_age != 4'd15)
							map_build_remainder <= map_build_remainder + {5'd0, map_build_tick};
					end
				end else begin
					map_build_remainder <= map_build_remainder - AGE_QUANTUM_EXT;
					map_build_age       <= map_build_age + 4'd1;
				end
			end else if (eof_token_popped) begin
				// Start an age-map rebuild when idle; retain the previous map until completion.
				map_busy               <= 1'b1;
				map_build_store_buffer <= (buffer_mode_q != 2'd1);
				map_build_buf          <= buf_draw;
				map_build_index        <= 4'd1;
				map_build_age          <= 4'd0;
				map_build_tick         <= popped_frame_tick_clks;
				map_build_remainder    <= AGE_HALF_QUANTUM + {5'd0, popped_frame_tick_clks};
				map_build_data         <= 64'd0;
			end

			// Record EOF frame age even while the age-map builder is busy.
			if (eof_token_popped && (buffer_mode_q != 2'd1))
				buf_frame_age[buf_draw] <= eof_frame_age_popped;

			if ((buffer_mode_q == 2'd1) && vbl_swap_req) begin
				buf_age_map[buf_draw]   <= latest_age_map;
				buf_frame_age[buf_draw] <= have_vbl_reference ? vbl_elapsed_age : 4'd0;
			end
		end
	end

endmodule
