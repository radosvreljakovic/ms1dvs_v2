library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

library lpm;
use lpm.lpm_components.all;

entity fir_filter_2D_process is
	generic (
		PIXEL_WIDTH : integer := 8;
		COEFF_WIDTH : integer := 16;
		PRODUCT_WIDTH : integer := 25; --PIXEL_WIDTH + 1 + COEFF_WIDTH
		KERNEL_SIZE : integer := 7;
		
		MAX_IMAGE_WIDTH : integer := 1656
	);
	port (
		clk : in std_logic := '0';
		reset : in std_logic := '0';
		en : in std_logic := '0';
		shift_input : in std_logic_vector(PIXEL_WIDTH - 1 downto 0) := (others => '0');
		coeffs : in std_logic_vector(COEFF_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0');
		
		--**********************
		result : out std_logic_vector(PRODUCT_WIDTH - 1 downto 0) := (others => '0')
		--**********************
	);
end entity fir_filter_2D_process;

architecture behav of fir_filter_2D_process is

	signal register_bank_input : std_logic_vector(PIXEL_WIDTH*KERNEL_SIZE - 1 downto 0) := (others => '0');
	signal register_bank_output: std_logic_vector(PIXEL_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0');
	
	component altshift_taps
	generic (
		intended_device_family	:	string := "unused";
		number_of_taps	:	natural;
		power_up_state	:	string := "CLEARED";
		tap_distance	:	natural;
		width	:	natural;
		lpm_hint	:	string := "UNUSED";
		lpm_type	:	string := "altshift_taps"
	);
	port(
		aclr	:	in std_logic := '0';
		clken	:	in std_logic := '1';
		clock	:	in std_logic;
		shiftin	:	in std_logic_vector(width - 1 downto 0);
		shiftout	:	out std_logic_vector(width - 1 downto 0);
		taps	:	out std_logic_vector(width*number_of_taps - 1 downto 0)
	);
	end component;
	
	component register_bank_custom is
	generic (
		REG_WIDTH : integer := 8;
		KERNEL_SIZE : integer := 3
	);
	port (
		clk : in std_logic := '0';
		reset : in std_logic := '0';
		load_and_shift : in std_logic := '0';
		input : in std_logic_vector(REG_WIDTH*KERNEL_SIZE - 1 downto 0) := (others => '0');
		output: out std_logic_vector(REG_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0')
	);
	end component;
	
	component convolution is
	generic (
		PIXEL_WIDTH : integer := 8;
		COEFF_WIDTH : integer := 16;
		PRODUCT_WIDTH : integer := 25; --PIXEL_WIDTH + 1 + COEFF_WIDTH
		KERNEL_SIZE : integer := 7
	);
	port (
		--clk : in std_logic := '0';
		reset : in std_logic := '0';
		--en : in std_logic := '0';
		pixels : in std_logic_vector(PIXEL_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0');
		coeffs : in std_logic_vector(COEFF_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0');
		
		result : out std_logic_vector(PRODUCT_WIDTH - 1 downto 0) := (others => '0')
	);
	end component;

begin

	i1: altshift_taps
	generic map (
	number_of_taps => KERNEL_SIZE,
	tap_distance => MAX_IMAGE_WIDTH,
	width => PIXEL_WIDTH
	)
	port map (
	aclr => reset,
	clken => en,
	clock => clk,
	shiftin => shift_input,
	shiftout => open,
	taps => register_bank_input
	);
	
	i2: register_bank_custom
	generic map (
	REG_WIDTH => PIXEL_WIDTH,
	KERNEL_SIZE => KERNEL_SIZE
	)
	port map (
	clk => clk,
	reset => reset,
	load_and_shift => en,
	input => register_bank_input,
	output => register_bank_output
	);
	
	i3: convolution
	generic map (
	PIXEL_WIDTH => PIXEL_WIDTH,
	COEFF_WIDTH => COEFF_WIDTH,
	PRODUCT_WIDTH => PRODUCT_WIDTH,
	KERNEL_SIZE => KERNEL_SIZE
	)
	port map (
	--clk => clk,
	reset => reset,
	--en => en,
	pixels => register_bank_output,
	coeffs => coeffs,
	result => result
	);
	
end architecture behav;
