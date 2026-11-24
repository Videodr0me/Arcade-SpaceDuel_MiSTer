-- Space Duel vector ROM.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity vecrom is
	Port (
		addr    : in  STD_LOGIC_VECTOR(13 downto 0);
		data    : out STD_LOGIC_VECTOR(7 downto 0);
		clk     : in  STD_LOGIC;
		dn_addr : in  STD_LOGIC_VECTOR(15 downto 0);
		dn_data : in  STD_LOGIC_VECTOR(7 downto 0);
		dn_wr   : in  STD_LOGIC
	);
end vecrom;

architecture Behavioral of vecrom is
	signal r7_data  : STD_LOGIC_VECTOR(7 downto 0);
	signal np7_data : STD_LOGIC_VECTOR(7 downto 0);
	signal r7_wr    : STD_LOGIC;
	signal np7_wr   : STD_LOGIC;
begin
	-- MRA offsets: R7 at $5000 and NP7 at $6000.
	r7_wr  <= dn_wr when dn_addr(15 downto 11) = "01010" else '0';
	np7_wr <= dn_wr when dn_addr(15 downto 12) = "0110" else '0';

	r7_rom : entity work.dpram generic map (11, 8)
	port map (
		clock_a   => clk,
		wren_a    => r7_wr,
		address_a => dn_addr(10 downto 0),
		data_a    => dn_data,
		clock_b   => clk,
		address_b => addr(10 downto 0),
		q_b       => r7_data
	);

	np7_rom : entity work.dpram generic map (12, 8)
	port map (
		clock_a   => clk,
		wren_a    => np7_wr,
		address_a => dn_addr(11 downto 0),
		data_a    => dn_data,
		clock_b   => clk,
		address_b => addr(11 downto 0),
		q_b       => np7_data
	);

	-- AVG address space: vector RAM $0000-$07ff, then the two ROM banks.
	data <= r7_data  when addr(13 downto 11) = "001" else
	        np7_data when addr(13 downto 12) = "01" else
	        x"00";
end Behavioral;
