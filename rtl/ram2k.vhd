-- Space Duel 2K Vector RAM.
--
-- Original FPGA implementation by Jeroen Domburg, 2012.
-- Updated for Space Duel by Videodr0me, 2026.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ram2k is
	Port (
		addr     : in  STD_LOGIC_VECTOR(10 downto 0);
		data_in  : in  STD_LOGIC_VECTOR(7 downto 0);
		data_out : out STD_LOGIC_VECTOR(7 downto 0);
		rw_l     : in  STD_LOGIC;
		cs_l     : in  STD_LOGIC;
		ena      : in  STD_LOGIC;
		clk      : in  STD_LOGIC
	);
end ram2k;

architecture Behavioral of ram2k is
	type ram_t is array (0 to 2047) of STD_LOGIC_VECTOR(7 downto 0);
	signal ram : ram_t;
begin
	process (clk)
	begin
		if rising_edge(clk) then
			if ena = '1' then
				if cs_l = '0' and rw_l = '0' then
					ram(conv_integer(addr)) <= data_in;
				end if;
				data_out <= ram(conv_integer(addr));
			end if;
		end if;
	end process;
end Behavioral;
