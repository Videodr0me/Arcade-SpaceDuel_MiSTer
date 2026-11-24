//============================================================================
//  Atari Space Duel machine
//
//  Written 2026 by Videodr0me
//============================================================================

module spaceduel_core
(
	input  logic        clk_12,
	input  logic        reset,
	input  logic        pause,
	input  logic        audio_filter_off,

	input  logic        coin_1,
	input  logic        coin_2,
	input  logic        service,
	input  logic        diagnostic_step,
	input  logic        cabinet_cocktail,
	input  logic  [2:0] cabinet_options,
	input  logic  [7:0] dsw_d4,
	input  logic  [7:0] dsw_b4,

	input  logic        p1_left,
	input  logic        p1_right,
	input  logic        p1_fire,
	input  logic        p1_shield,
	input  logic        p1_thrust,
	input  logic        p1_start,
	input  logic        p1_select,
	input  logic        p2_left,
	input  logic        p2_right,
	input  logic        p2_fire,
	input  logic        p2_shield,
	input  logic        p2_thrust,

	input  logic        rom_write,
	input  logic [15:0] rom_address,
	input  logic  [7:0] rom_data,

	input  logic  [5:0] nvram_address,
	input  logic  [7:0] nvram_data_in,
	input  logic        nvram_write,
	output logic  [7:0] nvram_data_out,
	output logic        nvram_modified,

	output logic signed [15:0] audio,
	output logic signed [14:0] x_out,
	output logic signed [14:0] y_out,
	output logic signed [22:0] step_x_out,
	output logic signed [22:0] step_y_out,
	output logic        [7:0]  intensity_out,
	output logic        [2:0]  rgb_out,
	output logic               is_dot,
	output logic               avg_halted,
	output logic               flip_x,
	output logic               flip_y
);

	// The five program ROMs occupy $4000-$8fff. The final ROM is mirrored
	// through $ffff and contains the CPU vectors.
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0]
		program_rom [0:20479];
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0]
		work_ram [0:1023];

	logic [14:0] program_index;
	logic  [7:0] program_data_q;
	logic  [7:0] work_ram_data_q;

	logic [23:0] cpu_address;
	logic  [7:0] cpu_data_in;
	logic  [7:0] cpu_data_out;
	logic        cpu_write_n;
	logic        cpu_irq_n;
	logic  [2:0] cpu_div = 3'd0;
	logic        cpu_enable;

	logic  [8:0] clock_3khz       = 9'd0;
	logic  [3:0] irq_div          = 4'd0;
	logic  [7:0] watchdog_counter = 8'd0;
	logic        watchdog_reset   = 1'b0;

	logic  [7:0] avg_cpu_data;
	logic [13:0] avg_cpu_address;
	logic        avg_select_n;
	logic        avg_go;
	logic        avg_reset;
	logic  [7:0] pokey_a_data;
	logic  [7:0] pokey_b_data;
	logic  [7:0] pokey_a_audio;
	logic  [7:0] pokey_b_audio;
	logic        pokey_a_select_n;
	logic        pokey_b_select_n;
	logic  [7:0] earom_data;
	logic  [7:0] input_0;
	logic  [7:0] input_serial;
	logic  [7:0] output_latch = 8'hff;

	wire cpu_write = cpu_enable && !cpu_write_n;
	// SP-181 sheet 4B: K6 selects 256-byte read windows; L4 selects
	// 128-byte write windows. Device address pins select within each window.
	wire ram_select          = (cpu_address[15:10] == 6'b000000);
	wire input_0_select      = (cpu_address[15:8] == 8'h08);
	wire input_serial_select = (cpu_address[15:8] == 8'h09);
	wire earom_read_select   = (cpu_address[15:8] == 8'h0a);
	wire output_write        = cpu_write && (cpu_address[15:7] == 9'h018);
	wire irq_ack             = cpu_write && (cpu_address[15:7] == 9'h01c);
	wire irq_tick            = cpu_enable && (clock_3khz == 9'h0ff);
	wire irq_pending         = irq_div[3] && irq_div[2];
	wire watchdog_clear      = cpu_write && (cpu_address[15:7] == 9'h01a);
	wire watchdog_tick       = cpu_enable && (clock_3khz == 9'h1ff);
	wire machine_reset       = reset || watchdog_reset;
	wire earom_control_write = cpu_write && (cpu_address[15:7] == 9'h01d);
	wire earom_latch_write   = cpu_write && (cpu_address[15:7] == 9'h01e);
	wire program_select      = (cpu_address[15:14] != 2'b00);

	assign cpu_enable       = (cpu_div == 3'd0);
	assign cpu_irq_n        = !irq_pending;
	assign avg_cpu_address  = cpu_address[13:0] - 14'h2000;
	assign avg_select_n     = (cpu_address[15:13] != 3'b001);
	assign avg_go           = cpu_write && (cpu_address[15:7] == 9'h019);
	assign avg_reset        = reset || (cpu_write && (cpu_address[15:7] == 9'h01b));
	assign pokey_a_select_n = (cpu_address[15:10] != 6'b000100);
	assign pokey_b_select_n = (cpu_address[15:10] != 6'b000101);

	T65 cpu
	(
		.Mode(2'b00),
		.BCD_en(1'b1),
		.Res_n(!machine_reset),
		.Enable(cpu_enable),
		.Clk(clk_12),
		.Rdy(!pause),
		.Abort_n(1'b1),
		.IRQ_n(cpu_irq_n),
		.NMI_n(1'b1),
		.SO_n(1'b1),
		.R_W_n(cpu_write_n),
		.Sync(),
		.EF(),
		.MF(),
		.XF(),
		.ML_n(),
		.VP_n(),
		.VDA(),
		.VPA(),
		.A(cpu_address),
		.DI(cpu_write_n ? cpu_data_in : cpu_data_out),
		.DO(cpu_data_out),
		.Regs(),
		.DEBUG(),
		.NMI_ack()
	);

	avg vector_generator
	(
		.cpu_data_in(avg_cpu_data),
		.cpu_data_out(cpu_data_out),
		.cpu_addr(avg_cpu_address),
		.cpu_cs_l(avg_select_n),
		.cpu_rw_l(cpu_write_n),
		.vgrst(avg_reset),
		.vggo(avg_go),
		.halted(avg_halted),
		.xout15(x_out),
		.yout15(y_out),
		.step_x_out(step_x_out),
		.step_y_out(step_y_out),
		.zout(intensity_out),
		.rgbout(rgb_out),
		.is_dot_out(is_dot),
		.dbg(),
		.clken(cpu_enable),
		.clk(clk_12),
		.dn_addr(rom_address),
		.dn_data(rom_data),
		.dn_wr(rom_write)
	);

	pokey pokey_a
	(
		.ADDR(cpu_address[3:0]),
		.DIN(cpu_data_out),
		.DOUT(pokey_a_data),
		.DOUT_OE_L(),
		.RW_L(cpu_write_n),
		.CS(1'b1),
		.CS_L(pokey_a_select_n),
		.AUDIO_OUT(pokey_a_audio),
		.PIN(dsw_d4),
		.ENA(cpu_enable),
		.CLK(clk_12)
	);

	pokey pokey_b
	(
		.ADDR(cpu_address[3:0]),
		.DIN(cpu_data_out),
		.DOUT(pokey_b_data),
		.DOUT_OE_L(),
		.RW_L(cpu_write_n),
		.CS(1'b1),
		.CS_L(pokey_b_select_n),
		.AUDIO_OUT(pokey_b_audio),
		.PIN(dsw_b4),
		.ENA(cpu_enable),
		.CLK(clk_12)
	);

	atari_er2055 earom
	(
		.clk(clk_12),
		.reset(reset),
		.latch_write(earom_latch_write),
		.latch_address(cpu_address[5:0]),
		.latch_data(cpu_data_out),
		.control_write(earom_control_write || watchdog_reset),
		.control_data(watchdog_reset ? 4'd0 : cpu_data_out[3:0]),
		.data_out(earom_data),
		.modified(nvram_modified),
		.nvram_address(nvram_address),
		.nvram_data_in(nvram_data_in),
		.nvram_write(nvram_write),
		.nvram_data_out(nvram_data_out)
	);

	always_comb begin
		program_index = 15'd0;
		if (cpu_address[15:0] >= 16'h8000)
			program_index = 15'h4000 + {3'd0, cpu_address[11:0]};
		else if (cpu_address[15:0] >= 16'h4000)
			program_index = cpu_address[14:0] - 15'h4000;
	end

	always_ff @(posedge clk_12) begin
		program_data_q  <= program_rom[program_index];
		work_ram_data_q <= work_ram[cpu_address[9:0]];

		if (rom_write && (rom_address < 16'h5000)) program_rom[rom_address[14:0]] <= rom_data;

		if (cpu_write && ram_select) work_ram[cpu_address[9:0]] <= cpu_data_out;
	end

	// J4 counts rising 3 kHz edges and holds when QC and QD assert IRQ.
	// INTACK clears J4 without resetting the upstream clock divider.
	always_ff @(posedge clk_12) begin
		if (reset) begin
			// External reset initializes these counters; watchdog reset leaves J4 running.
			cpu_div    <= 3'd0;
			clock_3khz <= 9'd0;
			irq_div    <= 4'd0;
		end else begin
			cpu_div <= cpu_div + 1'd1;
			if (cpu_enable) clock_3khz <= clock_3khz + 1'd1;
			if (irq_ack)
				irq_div <= 4'd0;
			else if (irq_tick && !irq_pending)
				irq_div <= irq_div + 1'd1;
		end
	end

	// H4 counts falling 3 kHz edges; its bit 7 rising edge clocks K3.
	// WDCLR clears H4 without releasing K3. Runtime reset starts after 128
	// ticks and changes again after 256 ticks. Pause holds the watchdog.
	always_ff @(posedge clk_12) begin
		if (reset) begin
			watchdog_counter <= 8'd0;
			watchdog_reset   <= 1'b0;
		end else if (watchdog_clear) begin
			watchdog_counter <= 8'd0;
		end else if (!pause && watchdog_tick) begin
			watchdog_counter <= watchdog_counter + 1'd1;
			if (watchdog_counter == 8'h7f) watchdog_reset <= !watchdog_reset;
		end
	end

	always_ff @(posedge clk_12) begin
		if (reset)
			output_latch <= 8'hff;
		else if (watchdog_reset)
			output_latch <= 8'd0;
		else if (output_write)
			output_latch <= cpu_data_out;
	end

	assign flip_x = !output_latch[6];
	assign flip_y = !output_latch[7];

	always_comb begin
		input_0 = {clock_3khz[8], avg_halted, !diagnostic_step, !service, 2'b11, !coin_1, !coin_2};

		// L9 and N9 drive only DB7:6. Model undriven DB5:0 as high;
		// their electrical value on the board has not been measured.
		input_serial = 8'h3f;
		case (cpu_address[2:0])
			3'd0:    input_serial[7:6] = {p1_shield, p1_fire};
			3'd1:    input_serial[7:6] = {p2_shield, p2_fire};
			3'd2:    input_serial[7:6] = {p1_left, p1_right};
			3'd3:    input_serial[7:6] = {p2_left, p2_right};
			3'd4:    input_serial[7:6] = {p1_thrust, p1_start};
			3'd5:    input_serial[7:6] = {p2_thrust, !cabinet_options[0]};
			3'd6:    input_serial[7:6] = {p1_select, !cabinet_options[1]};
			default: input_serial[7:6] = {cabinet_cocktail, !cabinet_options[2]};
		endcase
	end

	always_comb begin
		cpu_data_in = 8'hff;
		if (ram_select)
			cpu_data_in = work_ram_data_q;
		else if (input_0_select)
			cpu_data_in = input_0;
		else if (input_serial_select)
			cpu_data_in = input_serial;
		else if (earom_read_select)
			cpu_data_in = earom_data;
		else if (!pokey_a_select_n)
			cpu_data_in = pokey_a_data;
		else if (!pokey_b_select_n)
			cpu_data_in = pokey_b_data;
		else if (!avg_select_n)
			cpu_data_in = avg_cpu_data;
		else if (program_select)
			cpu_data_in = program_data_q;
	end

	logic        [8:0]  audio_sum;
	logic signed [15:0] filtered_audio;

	spaceduel_audio_filter audio_filter (
		.clk(clk_12), .reset(reset), .ce(cpu_enable),
		.pokey_a(pokey_a_audio), .pokey_b(pokey_b_audio), .audio(filtered_audio)
	);

	always_comb begin
		audio_sum = {1'b0, pokey_a_audio} + {1'b0, pokey_b_audio};
		// Bypass scales the 9-bit POKEY sum to 15-bit positive PCM.
		audio = pause ? 16'sd0 :
		        audio_filter_off ? $signed({1'b0, audio_sum, 6'd0}) : filtered_audio;
	end

endmodule
