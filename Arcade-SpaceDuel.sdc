derive_pll_clocks
derive_clock_uncertainty

# Treat the control, machine, and renderer domains as asynchronous at their
# boundaries; explicit synchronizers and asynchronous FIFOs implement the CDC.
set emu_clk_50  [get_clocks {FPGA_CLK2_50}]
set emu_clk_12  [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_render [get_clocks {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}]

set_clock_groups -asynchronous \
	-group $emu_clk_50 \
	-group $emu_clk_12 \
	-group $emu_clk_render

# Bound Gray routes below 80% of their source periods: 12.096 MHz for write
# and phase, 128.520 MHz for read. set_net_delay remains effective across
# asynchronous clock groups in Quartus 17.
set_net_delay -max 66.100 \
	-from [get_registers {*|rasterizer_inst|wr_ptr_g[*]}] \
	-to   [get_registers {*|rasterizer_inst|wr_ptr_g_sync1[*]}]
set_net_delay -max 6.220 \
	-from [get_registers {*|rasterizer_inst|rd_ptr_g[*]}] \
	-to   [get_registers {*|rasterizer_inst|rd_ptr_g_sync1_12[*]}]
set_net_delay -max 66.100 \
	-from [get_registers {*|phosphor_timing_inst|draw_gray_source[*]}] \
	-to   [get_registers {*|phosphor_timing_inst|draw_gray_meta[*]}]
