-- Atari Analog Vector Generator (AVG) by Videodr0me 2026
--
-- PROM-driven state machine following Space Duel hardware sequencing.
-- Reference: Atari SP-181, second printing, sheets 6B (vector data),
-- 7A (sequencer) and 7B (flags, scaling and timer).
-- The 256x4 state PROM is loaded via the MRA download interface.
-- PROM actions advance on 1.512 MHz clken ticks. ST2 lets non-fetch strobes
-- continue while vector memory is unavailable; fetches wait for tagged data.
-- Normalization and binary scaling run concurrently at 12.096 MHz.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity avg_prom_core is
	Port (
		avg_data_valid : in  STD_LOGIC;
		vgrst          : in  STD_LOGIC;
		vggo           : in  STD_LOGIC;
		halted         : out STD_LOGIC;
		xout           : out STD_LOGIC_VECTOR(14 downto 0);
		yout           : out STD_LOGIC_VECTOR(14 downto 0);
		zout           : out STD_LOGIC_VECTOR(7 downto 0);
		rgbout         : out STD_LOGIC_VECTOR(2 downto 0);
		is_dot         : out STD_LOGIC;
		step_x_out     : out STD_LOGIC_VECTOR(22 downto 0);
		step_y_out     : out STD_LOGIC_VECTOR(22 downto 0);
		clken          : in  STD_LOGIC;
		clk            : in  STD_LOGIC;

		-- External memory interface for AVG
		avg_addr_out : out STD_LOGIC_VECTOR(15 downto 0);
		avg_data_in  : in  STD_LOGIC_VECTOR(7 downto 0);

		dn_addr : in  std_logic_vector(7 downto 0);
		dn_data : in  std_logic_vector(7 downto 0);
		dn_wr   : in  std_logic
	);
end avg_prom_core;

-- Core-facing instruction encoding. The AVG wrapper swaps A0 on AVG
-- fetches because the CPU-visible vector memory stores words low byte first.
--   First byte read (LATCH 1): contains opcode in bits 7:5
--   Second byte read (LATCH 0): contains low data byte
--
--  Opcode                     Hex      Binary (hi byte, lo byte)
--    VCTR  (draw long)         0x00     000YYYYY YYYYYYYY  IIIXXXXX XXXXXXXX
--    HALT                      0x20     00100000 00000000
--    SVEC  (draw short)        0x40     010YYYYY IIIXXXXX
--    STAT  (color, U=0)        0x60     0110____ ZZZZ0RGB
--    STAT  (scale, U=1)        0x70     0111_SSS LLLLLLLL
--    CENTER                    0x80     10000000 0DDDDDDD  (DVY sets timer via norm)
--    JSRL  (call subroutine)   0xA0     101AAAAA AAAAAAAA
--    RTSL  (return)            0xC0     11000000 00000000
--    JMPL  (jump)              0xE0     111AAAAA AAAAAAAA

architecture Behavioral of avg_prom_core is
	type stackarraytype is array (natural range <>) of std_logic_vector(13 downto 0);

	-- ================================================================
	-- AVG state PROM (256 x 4 bits)
	-- Loaded from ROM set via dn_addr/dn_data/dn_wr during download.
	-- Hardware: 136002-125.n4 bipolar PROM
	--
	-- Address: A7=NORMAL_A7, A6..A4=OP2..OP0, A3..A0=F3..F0.
	-- Data: O4..O1. O4=1 selects a latch/strobe action and O3..O1
	-- select the action number:
	--
	--   $8 = LATCH 0  (load DVY low byte)
	--   $9 = LATCH 1  (load DVY high byte + opcode)
	--   $A = LATCH 2  (load DVX low byte)
	--   $B = LATCH 3  (load DVX high byte + intensity)
	--   $C = STROBE 0 (normalize / push PC)
	--   $D = STROBE 1 (scale / SP adjust)
	--   $E = STROBE 2 (load STAT or PC for JMP/JSR/RTS)
	--   $F = STROBE 3 (GO draw / HALT / CENTER)
	--
	-- O4=0 performs no latch or strobe action.
	-- ================================================================
	type prom_array_t is array (0 to 255) of std_logic_vector(3 downto 0);
	signal avg_prom : prom_array_t;

	signal pc          : STD_LOGIC_VECTOR(13 downto 0);
	signal instruction : STD_LOGIC_VECTOR(15 downto 0);
	signal operand     : STD_LOGIC_VECTOR(15 downto 0);
	-- Three-entry return stack; pushes cycle through slots 0, 1, 2, 0.
	-- Return addresses use byte-PC form with bit 0 = '0'.
	signal stack       : stackarraytype(2 downto 0);
	signal sp          : STD_LOGIC_VECTOR(1 downto 0);
	signal memory_din  : STD_LOGIC_VECTOR(7 downto 0);
	signal memory_addr : STD_LOGIC_VECTOR(13 downto 0);

	signal vec_dx           : STD_LOGIC_VECTOR(12 downto 0);
	signal vec_dy           : STD_LOGIC_VECTOR(12 downto 0);
	signal vec_zero         : STD_LOGIC;
	signal vec_draw         : STD_LOGIC;
	signal vec_done         : STD_LOGIC;
	signal stat_intensity   : STD_LOGIC_VECTOR(3 downto 0);
	signal vector_intensity : STD_LOGIC_VECTOR(3 downto 0);
	signal final_intensity  : STD_LOGIC_VECTOR(3 downto 0);
	signal rgb              : STD_LOGIC_VECTOR(2 downto 0);
	-- Linear scale controls beam velocity through the analog scaling circuit,
	-- independently of the LS161 timer chain that sets draw duration.
	signal linear_scale_reg : STD_LOGIC_VECTOR(7 downto 0);
	-- Binary scale selects 0-7 additional timer shifts.
	-- The scale-form STAT instruction loads it at STROBE 2.
	signal bin_scale : STD_LOGIC_VECTOR(2 downto 0);

	-- PROM state machine signals (256x4 PROM 136002-125.n4)
	signal prom_state : STD_LOGIC_VECTOR(3 downto 0); -- latched feedback F3..F0
	signal prom_addr  : STD_LOGIC_VECTOR(7 downto 0);
	signal next_state : STD_LOGIC_VECTOR(3 downto 0);
	signal op         : STD_LOGIC_VECTOR(2 downto 0); -- current opcode OP2..OP0
	signal halt_flag  : STD_LOGIC;                    -- set by HALT instruction
	-- GO selects the idle PROM page while the drawer runs.
	-- Drawer completion clears GO and resumes instruction processing.
	signal go_flag : STD_LOGIC; -- drawing in progress (VCTR/CNTR set)

	signal norm_active : STD_LOGIC;                    -- normalization in progress
	signal norm_count  : STD_LOGIC_VECTOR(3 downto 0); -- normalization shift count; limit 15
	-- Timer preset for vector_drawer: 15 bits, or the low eight bits for SVEC.
	-- Normalization and binary scaling shift in ones.
	signal hw_timer        : STD_LOGIC_VECTOR(14 downto 0); -- 15-bit hardware timer
	signal is_svec         : STD_LOGIC;                     -- OP1: '1' for SVEC, '0' for VCTR
	signal binscale_active : STD_LOGIC;                     -- bin_scale shifting in progress
	signal binscale_count  : STD_LOGIC_VECTOR(2 downto 0);  -- current shift count

	function shifted_timer (timer : STD_LOGIC_VECTOR(14 downto 0); short_vector : STD_LOGIC)
		return STD_LOGIC_VECTOR is
		variable shifted : STD_LOGIC_VECTOR(14 downto 0);
	begin
		shifted := '1' & timer(14 downto 1);
		if short_vector = '1' then
			shifted(7) := '1';
		end if;
		return shifted;
	end function;

begin
	-- External memory interface
	avg_addr_out <= "00" & memory_addr;
	memory_din   <= avg_data_in;

	-- PROM A7 = NOR(HALT*, GO). ST2 comes from the pending PROM output,
	-- before the feedback latch advances.
	prom_addr  <= (not (halt_flag or go_flag)) & op & prom_state;
	next_state <= avg_prom(conv_integer(prom_addr));

	-- PROM download: write during ROM loading
	process (clk)
	begin
		if clk'event and clk = '1' then
			if dn_wr = '1' then
				avg_prom(conv_integer(dn_addr)) <= dn_data(3 downto 0);
			end if;
		end if;
	end process;

	vectordrawer : entity work.vector_drawer port map (
		clk          => clk,
		hw_timer     => hw_timer,
		is_svec      => is_svec,
		linear_scale => linear_scale_reg,
		rel_x        => vec_dx,
		rel_y        => vec_dy,
		zero         => vec_zero,
		draw         => vec_draw,
		done         => vec_done,
		is_dot       => is_dot,
		step_x_out   => step_x_out,
		step_y_out   => step_y_out,
		xout         => xout,
		yout         => yout
	);

	-- =================================================================
	-- Main PROM-driven sequencer. Actions execute on valid clken ticks.
	-- =================================================================
	process (clk)
	begin
		if clk'event and clk = '1' then
			-- Default single-cycle command strobes.
			vec_zero <= '0';
			vec_draw <= '0';

			if clken = '1' then
				-- /STOP clears GO independently of CPU vector-memory ownership.
				if go_flag = '1' and vec_done = '1' then
					go_flag <= '0';
				end if;

				if vgrst = '1' then
					-- VGRST resets the sequencer and drawer.
					pc               <= "00000000000000";
					instruction      <= x"0000";
					operand          <= x"0000";
					prom_state       <= x"0";
					op               <= "000";
					halt_flag        <= '1';
					go_flag          <= '0';
					norm_active      <= '0';
					norm_count       <= "0000";
					sp               <= "00";
					rgb              <= "000";
					stat_intensity   <= (others => '0');
					vector_intensity <= (others => '0');
					linear_scale_reg <= (others => '0');
					bin_scale        <= "000";
					vec_dx           <= (others => '0');
					vec_dy           <= (others => '0');
					hw_timer         <= (others => '0');
					is_svec          <= '0';
					binscale_active  <= '0';
					binscale_count   <= "000";
					vec_zero         <= '1';
					vec_draw         <= '0';
				elsif halt_flag = '1' then
					-- Halted: wait for VGGO.
					pc       <= (others => '0');
					rgb      <= "000";
					vec_zero <= '1';
					if vggo = '1' then
						halt_flag  <= '0';
						prom_state <= x"0";
						sp         <= "00";
					end if;

				elsif avg_data_valid = '0' and next_state(2) = '0' then
					-- SP-181 sheet 7A: ST2 bypasses the VMEM clock hold for
					-- strobes C..F. Fetches still require their tagged response.
					null;

				else
					-- Execute the pending PROM action.
					if next_state(3) = '1' then
						-- O4=1: O3..O1 select a latch or strobe.
						case next_state(2 downto 0) is

							when "001" =>
								-- LATCH 1: load the opcode and DVY high byte; clear DVY0-7,
								-- DVX0-12 and vector intensity (SP-181 sheet 6B).
								instruction(15 downto 8) <= memory_din;
								op                       <= memory_din(7 downto 5);
								instruction(7 downto 0)  <= (others => '0');
								operand(11 downto 0)     <= (others => '0');
								operand(12)              <= '0';
								vector_intensity         <= "0000";
								pc                       <= pc + "00000000000001";

							when "000" =>
								-- LATCH 0 (action $8): Read lo byte -> DVY low
								instruction(7 downto 0) <= memory_din;
								pc                      <= pc + "00000000000001";

							when "011" =>
								-- LATCH 3 (action $B): Read hi byte -> DVX high + intensity
								operand(15 downto 8) <= memory_din;
								pc                   <= pc + "00000000000001";

							when "010" =>
								-- LATCH 2 (action $A): Read lo byte -> DVX low
								operand(7 downto 0) <= memory_din;
								pc                  <= pc + "00000000000001";

							when "100" =>
								-- STROBE 0 (action $C): Push PC for JSR, or start normalization
								if op = "101" then -- JSRL: push PC
									if (sp = "00") then stack(0) <= pc; end if;
									if (sp = "01") then stack(1) <= pc; end if;
									if (sp = "10") then stack(2) <= pc; end if;
								else
									-- STROBE 0 starts normalization for VCTR, SVEC and CENTER.
									if op = "000" or op = "010" or op = "100" then
										norm_active <= '1';
										norm_count  <= "0000";
										hw_timer    <= (others => '0');
										is_svec     <= op(1);
									end if;
								end if;

							when "101" =>
								-- STROBE 1: adjust SP for JSR/RTS or start binary scaling
								-- for VCTR/SVEC.
								if op = "101" then    -- JSRL: sp++
									if sp = "10" then
										sp <= "00";
									else
										sp <= sp + "01";
									end if;
								elsif op = "110" then -- RTSL: sp--
									-- Pop cycles 0, 2, 1, 0. Underflow reads the retained slot.
									-- Reverse wrap from 0 to 2 on an unmatched RTS is inferred.
									if sp = "00" then
										sp <= "10";
									else
										sp <= sp - "01";
									end if;
								elsif op = "000" or op = "010" then
									-- VCTR/SVEC: start LS191 bin_scale count-down,
									-- gating fill-bit shifts into the LS161 timer chain.
									if bin_scale /= "000" then
										-- Only nonzero SCALE clears the NORM flip-flop.
										norm_active     <= '0';
										binscale_active <= '1';
										binscale_count  <= "000";
									end if;
								end if;

							when "110" =>
								-- STROBE 2 (action $E): Load STAT or update PC
								if op = "011" then
									if instruction(12) = '0' then
										-- STAT encodes Z and color in the low byte:
										-- 0110_xxxx_ZZZZ_0RGB
										stat_intensity <= instruction(7 downto 4);
										rgb            <= instruction(2 downto 0);
									else
										-- Scale (0111_SSS LLLLLLLL)
										linear_scale_reg <= instruction(7 downto 0);
										bin_scale        <= instruction(10 downto 8);
									end if;

								elsif op = "101" or op = "111" then
									-- JSRL or JMPL: PC = instruction(12:0) << 1
									pc(13 downto 1) <= instruction(12 downto 0);
									pc(0)           <= '0';
								elsif op = "110" then
									-- RTSL: pop PC from stack
									-- SP was already decremented by STROBE 1, so read stack[sp] directly
									if (sp = "00") then pc <= stack(0); end if;
									if (sp = "01") then pc <= stack(1); end if;
									if (sp = "10") then pc <= stack(2); end if;
								end if;

							when "111" =>
								-- STROBE 3 (action $F): GO draw / HALT / CENTER
								-- VCTR/SVEC: OP2=0,OP0=0 -> VCTR flag set -> GO=1 -> draw
								-- CENTER:    OP2=1 -> CNTR flag set -> GO=1 -> timer wait
								-- HALT:      OP0=1 -> halt flag set
								if op = "000" or op = "010" then
									-- VCTR asynchronously clears the NORM flip-flop.
									norm_active <= '0';
									-- VCTR/SVEC: pass normalized DVY/DVX to drawer.
									vec_dy           <= instruction(12 downto 0);
									vec_dx           <= operand(12 downto 0);
									vector_intensity <= operand(15 downto 12);
									vec_draw         <= '1';
									go_flag          <= '1';
								elsif op = "001" then
									halt_flag <= '1';
								elsif op = "100" then
									-- CENTER: DVY was loaded by LATCH1+LATCH0 and
									-- normalized at STROBE0 (sets timer duration).
									-- CNTR=1 -> GO=1 -> timer counts -> /STOP.
									-- CNTR asynchronously clears the NORM flip-flop.
									norm_active <= '0';
									-- /CENTER resets integrators to screen center.
									-- Modeled as zero+draw: position resets, timer waits.
									vec_dx           <= (others => '0');
									vec_dy           <= (others => '0');
									vector_intensity <= "0000";
									vec_zero         <= '1';
									vec_draw         <= '1';
									go_flag          <= '1';
								end if;

							when others => null;
						end case;
					end if;
					prom_state <= next_state;

				end if;
			end if;

			-- Normalize DVX/DVY and prepare the timer preset at 12.096 MHz.
			if norm_active = '1' then
				-- Stop on a sign-bit mismatch or the RTL limit of 15 shifts.
				if instruction(12) /= instruction(11) or operand(12) /= operand(11) or
				   norm_count >= "1111" then
					norm_active <= '0';
					if is_svec = '1' then
						hw_timer(14 downto 8) <= (others => '0');
					end if;
				else
					instruction(12 downto 1) <= instruction(11 downto 0);
					instruction(0)           <= '0';
					operand(12 downto 1)     <= operand(11 downto 0);
					operand(0)               <= '0';
					hw_timer                 <= shifted_timer(hw_timer, is_svec);
					norm_count               <= norm_count + "0001";
				end if;
			end if;

			-- Apply bin_scale additional timer shifts at 12.096 MHz.
			-- Retain the low eight timer bits for SVEC when scaling finishes.
			if binscale_active = '1' then
				if binscale_count >= bin_scale then
					binscale_active <= '0';
					if is_svec = '1' then
						hw_timer(14 downto 8) <= (others => '0');
					end if;
				else
					hw_timer       <= shifted_timer(hw_timer, is_svec);
					binscale_count <= binscale_count + "001";
				end if;
			end if;

		end if;
	end process;

	-- Present the current PC as the requested AVG byte address.
	process (clk)
	begin
		if clk'event and clk = '1' then
			memory_addr <= pc;
		end if;
	end process;

	halted <= halt_flag;

	-- Values 2 and 3 select the four-bit STAT intensity. Other vector
	-- intensity codes use their upper three bits and force the LSB low.
	final_intensity <= stat_intensity when vector_intensity(3 downto 1) = "001" else
	                   vector_intensity(3 downto 1) & '0';
	zout            <= final_intensity & final_intensity;

	rgbout <= rgb;
end Behavioral;
