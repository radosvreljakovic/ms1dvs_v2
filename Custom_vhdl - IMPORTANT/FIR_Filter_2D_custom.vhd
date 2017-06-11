-- FIR_Filter_2D_custom.vhd

-- This file was auto-generated as a prototype implementation of a module
-- created in component editor.  It ties off all outputs to ground and
-- ignores all inputs.  It needs to be edited to make it do something
-- useful.
-- 
-- This file will not be automatically regenerated.  You should check it in
-- to your version control system if you want to keep it.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

--library lpm;
--use lpm.lpm_components.all;

entity FIR_Filter_2D_custom is
	generic (
		DATA_BUS_WIDTH : integer := 32; --16;
		ADDRESS_BUS_WIDTH : integer := 6;
		
		IN_DATA_WIDTH : integer := 8;
		OUT_DATA_WIDTH : integer := 16;
	
		PIXEL_WIDTH : integer := 8;
		COEFF_WIDTH : integer := 16;
		PRODUCT_WIDTH : integer := 25; --PIXEL_WIDTH + 1 + COEFF_WIDTH
		KERNEL_SIZE : integer := 7;
		
		MAX_IMAGE_WIDTH : integer := 1656;
		-- 83 + 6 = 89 za panorama001
		-- 825 + 6 = 831 za panorama01
		-- 1238 + 6 = 1244 za panorama015
		-- 1650 + 6 = 1656 za panorama02
		
		MAX_IMAGE_HEIGHT : integer := 200 -- ovo cisto zbog opsega brojaca... nije bitno za procesiranje
	);
	port (
		clk                    : in  std_logic                     := '0';             --  clock.clk
		reset                  : in  std_logic                     := '0';             --  reset.reset
		avs_params_address     : in  std_logic_vector(ADDRESS_BUS_WIDTH - 1 downto 0)  := (others => '0'); -- params.address
		avs_params_read        : in  std_logic                     := '0';             --       .read
		avs_params_readdata    : out std_logic_vector(DATA_BUS_WIDTH - 1 downto 0);                    --       .readdata
		avs_params_write       : in  std_logic                     := '0';             --       .write
		avs_params_writedata   : in  std_logic_vector(DATA_BUS_WIDTH - 1 downto 0) := (others => '0'); --       .writedata
		avs_params_waitrequest : out std_logic;                                        --       .waitrequest
		asi_in_data            : in  std_logic_vector(IN_DATA_WIDTH - 1 downto 0)  := (others => '0'); --     in.data
		asi_in_ready           : out std_logic;                                        --       .ready
		asi_in_valid           : in  std_logic                     := '0';             --       .valid
		asi_in_sop             : in  std_logic                     := '0';             --       .startofpacket
		asi_in_eop             : in  std_logic                     := '0';             --       .endofpacket
		aso_out_data           : out std_logic_vector(OUT_DATA_WIDTH - 1 downto 0);                    --    out.data
		aso_out_ready          : in  std_logic                     := '0';             --       .ready
		aso_out_valid          : out std_logic;                                        --       .valid
		aso_out_sop            : out std_logic;                                        --       .startofpacket
		aso_out_eop            : out std_logic;                                        --       .endofpacket
		aso_out_empty          : out std_logic                                         --       .empty
	);
end entity FIR_Filter_2D_custom;

architecture behav of FIR_Filter_2D_custom is

	-- kontrolni i statusni registar	
	signal control_reg : std_logic_vector(DATA_BUS_WIDTH - 1 downto 0);
	signal status_reg : std_logic_vector(DATA_BUS_WIDTH - 1 downto 0);
	
	-- registri za sirinu/visinu slike	
	signal image_width_reg : std_logic_vector(DATA_BUS_WIDTH - 1 downto 0);
	signal image_height_reg : std_logic_vector(DATA_BUS_WIDTH - 1 downto 0);
	
	-- registri prebaceni u integer
	signal image_width : integer range MAX_IMAGE_WIDTH downto 0 := 0;
	signal image_height : integer range MAX_IMAGE_HEIGHT downto 0 := 0;
	
	-- registri za cuvanje koeficijenata filtra
	signal coeffs_reg : std_logic_vector(DATA_BUS_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0);
	
	-- koeficijenti filtra duzine 16 bita... za razliku od registara koji su svi po 32 bita
	signal coeffs_shrink : std_logic_vector(COEFF_WIDTH*KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0');
	
	-- adrese registara, relativno u odnosu na baznu adresu komponente
	constant CONTROL_ADDR : std_logic_vector(ADDRESS_BUS_WIDTH - 1 downto 0) := "000000";
	constant STATUS_ADDR : std_logic_vector(ADDRESS_BUS_WIDTH - 1 downto 0) := "000001";
	constant IMAGE_WIDTH_ADDR : std_logic_vector(ADDRESS_BUS_WIDTH - 1 downto 0) := "000010";
	constant IMAGE_HEIGHT_ADDR : std_logic_vector(ADDRESS_BUS_WIDTH - 1 downto 0) := "000011";
	
	-- trenutno selektovana adresa pretvorena u integer (2^6 = 64)
	signal address_index : integer range 63 downto 0 := 0;
	
	-- adrese pojedinacnih koeficijenata
	type coeffs_addr_type is array(KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) of std_logic_vector(ADDRESS_BUS_WIDTH - 1 downto 0);
	signal COEFFS_ADDR : coeffs_addr_type;
	
	-- redni broj selektovanog registra koeficijenta
	signal coeffs_index : integer range KERNEL_SIZE*KERNEL_SIZE - 1 downto 0 := 0;
	
	-- aktiviraju se pri pokusaju upisa u odgovarajuci registar
	signal control_strobe : std_logic := '0';
	--signal status_strobe : std_logic := '0';
	signal image_width_strobe : std_logic := '0';
	signal image_height_strobe : std_logic := '0';
	signal coeffs_strobe : std_logic_vector(KERNEL_SIZE*KERNEL_SIZE - 1 downto 0) := (others => '0');
	
	-- vodimo direktno na read_data signal
	signal read_out_mux : std_logic_vector(DATA_BUS_WIDTH - 1 downto 0);
	
	-- jer hocemo da ga ocitavamo interno
	-- inace, ovo se samo prosledjuje na izlaz
	signal int_asi_in_ready : std_logic := '0';
	
	--*****************************************************
	-- S0: pocetno stanje, ceka se na startovanje preko kontrolnog registra
	-- S1: stanje popunjavanja siftera
	-- S2: generisemo nevalidan izlaz zbog prelaska u novi red
	-- S3/S4: procesiranje trenutnog reda, ali sa razlicitim kontrolnim signalima na ulazu i izlazu
	-- S5: odbacivanje rezultata zbog prelaska u novi red, analogno sa S2
	-- S6/S7: procesiranje poslednjeg reda (sa razlicitim kontrolnim signalima na izlazu), analogno sa S3/S4
	-- S8: kao i S7, samo sto se ne vrsi siftovanje
	type state is (S0, S1, S2, S3, S4, S5, S6, S7, S8);
	signal current_state, next_state : state;
	
	-- brojac usiftovanih piksela dok smo u stanju S1
	signal cnt1 : integer range MAX_IMAGE_WIDTH*KERNEL_SIZE - 1 downto 0 := 0;
	-- brojac rezultata za odbacivanje dok smo u stanju S2
	signal cnt2 : integer range KERNEL_SIZE - 1 downto 0 := 0;
	-- brojac poslatih validnih rezultata izlaznom DMA dok smo u stanju S3
	signal cnt3 : integer range MAX_IMAGE_WIDTH - 1 downto 0 := 0;
	-- brojanje kompletno isprocesiranih redova
	signal cnt4 : integer range MAX_IMAGE_HEIGHT - 2 downto 0 := 0;
	-- brojac rezultata za odbacivanje dok smo u stanju S5
	signal cnt5 : integer range KERNEL_SIZE - 1 downto 0 := 0;
	-- brojac poslatih validnih rezultata izlaznom DMA dok smo u stanju S6
	signal cnt6 : integer range MAX_IMAGE_WIDTH - 1 downto 0 := 0;
	-- brojac trajanja stanja S8 (vestacki ubaceno stanje zbog prilagodjavanja izlaznom DMA)
	signal cnt7 : integer range 9 downto 0 := 0;
	
	-- dozvola siftovanja za sifter... vrednost je 1 kada moze da se siftuje na sledeci clk
	signal shift_enable : std_logic := '0';
	
	-- signal koji se prosledjuje sifteru... moze biti input sa DMA ili 0 ("dummy")
	signal shift_input_mux : std_logic_vector(IN_DATA_WIDTH - 1 downto 0) := (others => '0');
	
	-- signal rezultata konvolucije... treba prebaciti ovo u Q11.5 format i proslediti izlaznom DMA
	signal raw_result : std_logic_vector(PRODUCT_WIDTH - 1 downto 0) := (others => '0');
	
	component fir_filter_2D_process is
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
	end component;
	
begin
	
	-- generisanje adresa pojedinacnih koeficijenata (adrese krecu od 4)
	GEN_COEFFS_ADDR : for i in KERNEL_SIZE*KERNEL_SIZE - 1 downto 0 generate
	begin
		COEFFS_ADDR(i) <= std_logic_vector(to_unsigned(4 + i, ADDRESS_BUS_WIDTH));
	end generate GEN_COEFFS_ADDR;
	
	-- generisanje signala za upis u razlicite registre
	control_strobe <= '1' when (avs_params_write = '1') and (avs_params_address = CONTROL_ADDR) else '0';
	--status_strobe <= '1' when (avs_params_write = '1') and (avs_params_address = STATUS_ADDR) else '0';
	image_width_strobe <= '1' when (avs_params_write = '1') and (avs_params_address = IMAGE_WIDTH_ADDR) else '0';
	image_height_strobe <= '1' when (avs_params_write = '1') and (avs_params_address = IMAGE_HEIGHT_ADDR) else '0';
	
	-- generisanje signala za upis u registre koeficijenata
	GEN_COEFFS_STROBE : for i in KERNEL_SIZE*KERNEL_SIZE - 1 downto 0 generate
	begin
		coeffs_strobe(i) <= '1' when (avs_params_write = '1') and (avs_params_address = COEFFS_ADDR(i)) else '0';
	end generate GEN_COEFFS_STROBE;
	
	--redni broj trenutne adrese
	address_index <= to_integer(unsigned(avs_params_address));
	
	-- redni broj trenutno selektovanog koeficijenata
	coeffs_index <= address_index - 4 when address_index >= 4 and address_index < 4 + KERNEL_SIZE*KERNEL_SIZE
						 else 0;
	
	-- ono sto se ocitava
	read_out_mux <= control_reg when (avs_params_address = CONTROL_ADDR) else
						 status_reg when (avs_params_address = STATUS_ADDR) else
						 image_width_reg when (avs_params_address = IMAGE_WIDTH_ADDR) else
						 image_height_reg when (avs_params_address = IMAGE_HEIGHT_ADDR) else
						 coeffs_reg(DATA_BUS_WIDTH*(coeffs_index + 1) - 1 downto coeffs_index*DATA_BUS_WIDTH) when (avs_params_address = COEFFS_ADDR(coeffs_index))
						 else (others => '0');
						 
	-- upis u kontrolni registar
	write_control_reg: process(clk, reset)
	begin
		if (reset = '1') then
			control_reg <= (others => '0');
		elsif (rising_edge(clk)) then
			if (control_strobe = '1') then
				control_reg <= avs_params_writedata;
			end if;
		end if;
	end process;
	
	-- nije dozvoljen upis u statusni registar, vec samo citanje
	-- statusni registar zavisi samo od trenutnog stanja (ako 2D FIR radi, status je 11...1, inace je status 0)
	status_reg <= (others => '0') when (current_state = S0) else (others => '1');
	
	-- upis u registar sirine slike
	write_image_width_reg: process(clk, reset)
	begin
		if (reset = '1') then
			image_width_reg <= (others => '0');
		elsif (rising_edge(clk)) then
			if (image_width_strobe = '1') then
				image_width_reg <= avs_params_writedata;
			end if;
		end if;
	end process;
	
	-- upis u registar visine slike
	write_image_height_reg: process(clk, reset)
	begin
		if (reset = '1') then
			image_height_reg <= (others => '0');
		elsif (rising_edge(clk)) then
			if (image_height_strobe = '1') then
				image_height_reg <= avs_params_writedata;
			end if;
		end if;
	end process;
	
	-- upis u registre koeficijenata
	write_coeffs_reg: process(clk, reset)
	begin
		if (reset = '1') then
			coeffs_reg <= (others => '0');
		elsif (rising_edge(clk)) then
			if (coeffs_strobe(coeffs_index) = '1') then
				coeffs_reg(DATA_BUS_WIDTH*(coeffs_index + 1) - 1 downto coeffs_index*DATA_BUS_WIDTH) <= avs_params_writedata;
			end if;
		end if;
	end process;

	-- citanje registara
	read_regs: process(clk, reset)
	begin
		if (reset = '1') then
			avs_params_readdata <= (others => '0');
		elsif (rising_edge(clk)) then
			avs_params_readdata <= read_out_mux;
		end if;
	end process;
	
	-- generisanje koeficijenata manje odgovarajuce sirine
	GEN_COEFFS_SHRNIK : for i in KERNEL_SIZE*KERNEL_SIZE - 1 downto 0 generate
	begin
		coeffs_shrink(COEFF_WIDTH*(i + 1) - 1 downto COEFF_WIDTH*i)
		<= coeffs_reg(DATA_BUS_WIDTH*i + COEFF_WIDTH - 1 downto DATA_BUS_WIDTH*i);
	end generate GEN_COEFFS_SHRNIK;
	
	-- ulaz siftera...
	-- treba da selektuje podatak ili 0 (ako se radi "dummy" popunjavanje)... posle
	shift_input_mux <= asi_in_data;
	--shift_input_mux <= (others => '0'); -- proba (sve crno)
	
	-- kada znamo da nam na sledecu uzlaznu ivicu clk stize validan podatak, tada treba i da ga usiftujemo
	-- izuzeci su stanja S5, S6, S7 i S8 kada nema vise validnih podataka na ulazu
	shift_enable <= '1' when ((current_state = S5) or (current_state = S7))	else
						 '0' when ((current_state = S6) or (current_state = S8)) else
						 (asi_in_valid and int_asi_in_ready);
	
	-- instanca komponente koja radi 2D FIR procesiranje
	i1: fir_filter_2D_process
	generic map (
	PIXEL_WIDTH => PIXEL_WIDTH,
	COEFF_WIDTH => COEFF_WIDTH,
	PRODUCT_WIDTH => PRODUCT_WIDTH,
	KERNEL_SIZE => KERNEL_SIZE,
	MAX_IMAGE_WIDTH => MAX_IMAGE_WIDTH
	)
	port map (
	clk => clk,
	reset => reset,
	en => shift_enable, -- ovo je kljucni signal... kada treba da se siftuje?
	shift_input => shift_input_mux, -- ovo je validni ulazni odbirak ili 0 (ako se radi "dummy" prosirivanje)
	coeffs => coeffs_shrink,
	result => raw_result
	);
	
	-- 25b Q14.11 -> 16b Q11.5
	aso_out_data <= raw_result(21 downto 6);
	--aso_out_data <= std_logic_vector(to_unsigned(cnt3, 11)) & "00000";
	--aso_out_data <= std_logic_vector(to_unsigned(cnt4, 11)) & "00000";
	
	-- sirina/visina slike kao integer
	image_width <= to_integer(unsigned(image_width_reg));
	image_height <= to_integer(unsigned(image_height_reg));
	
	-- next_state -> current_state
	control_fsm: process(clk, reset)
	begin
		if (reset = '1') then
			current_state <= S0;
		elsif (rising_edge(clk)) then
			current_state <= next_state;
		end if;
	end process;
	
	-- logika za prelaz u sledece stanje (i generisanje kontrolnog singala aso_out_valid)
	state_machine: process(current_state, cnt1, cnt2, cnt3, cnt4, cnt5, cnt6, cnt7, control_reg, image_width, image_height, aso_out_ready, asi_in_valid)
	begin
		case current_state is
		
			when S0 =>
				-- nismo spremni da primimo podatak, na izlazu ne dajemo nista validno
				int_asi_in_ready <= '0';
				aso_out_valid <= '0';
				-- izlazi se iz pocetnog stanja kad neko setuje kontrolni registar
				-- asi_in_valid = '1' dodato da ne bi na kraju procesiranja masina stanja otisla u S1, vec ostala u S0
				if ((control_reg(0) = '1') and (asi_in_valid = '1')) then
					next_state <= S1;
				-- inace, ostajemo u pocetnom stanju
				else
					next_state <= S0;
				end if;
				
			when S1 =>
				-- spremni smo da primimo podatak, na izlazu ne dajemo nista validno
				int_asi_in_ready <= '1';
				aso_out_valid <= '0';
				-- izlazimo iz ovog stanja kad napunimo sifter do kraja (brojac cnt1 odbrojao koliko treba)
				if ((cnt1 = MAX_IMAGE_WIDTH*KERNEL_SIZE - 1) and (asi_in_valid = '1')) then
					next_state <= S2;
				-- inace, ostajemo u trenutnom stanju
				else
					next_state <= S1;
				end if;
			
			when S2 =>
				-- spremni smo da primimo podatak, na izlazu ne dajemo nista validno
				int_asi_in_ready <= '1';
				aso_out_valid <= '0';
				-- izlazimo iz ovog stanja kad odbacimo sve nevalidne rezultate na kraju trenutnog reda
				if ((cnt2 = KERNEL_SIZE - 1) and (asi_in_valid = '1')) then
					next_state <= S3;
				-- inace, ostajemo u trenutnom stanju
				else
					next_state <= S2;
				end if;
			
			when S3 =>
				-- cekamo da izlazni DMA procita validan podatak i ne smemo da ucitamo novi odbirak na ulazu
				int_asi_in_ready <= '0';
				aso_out_valid <= '1';
				
				-- iz S3 se moze "skociti" nazad u S2 ako smo dosli do kraja reda
				-- moze se otici u S5 ako smo pokupili sve validne podatke na ulazu
				if ((cnt3 = image_width - 1) and (aso_out_ready = '1')) then
					if (cnt4 = image_height - 2) then
						next_state <= S5;
					else					
						next_state <= S2;
					end if;
				-- ako ne, idemo u stanje S4 ili ostajemo u S3
				else
					if (aso_out_ready = '1') then
						next_state <= S4;
					else
						next_state <= S3;
					end if;
				end if;
				
			when S4 =>
				-- cekamo da dodje podatak na ulaz, a na izlazu nije validan podatak
				int_asi_in_ready <= '1';
				aso_out_valid <= '0';
				
				-- vracamo se u stanje S3 ili ostajemo u S4
				if (asi_in_valid = '1') then
					next_state <= S3;
				else
					next_state <= S4;
				end if;
				
			when S5 =>
				-- vise nam ne trebaju podaci sa ulaznog DMA (i nema ih vise), na izlazu ne dajemo nista validno
				int_asi_in_ready <= '0';
				aso_out_valid <= '0';
				
				-- izlazimo iz ovog stanja kad odbacimo sve nevalidne rezultate na kraju ovog (poslednjeg) reda
				if (cnt5 = KERNEL_SIZE - 1) then
					next_state <= S6;
				-- inace, ostajemo u trenutnom stanju
				else
					next_state <= S5;
				end if;
				
			when S6 =>
				-- cekamo da izlazni DMA procita validan podatak i nemamo podataka sa ulaznog DMA
				int_asi_in_ready <= '0';
				aso_out_valid <= '1';
				
				-- iz S6 se moze "skociti" nazad u S0 (zavrsiti obrada) ako smo dosli do kraja ovog (poslednjeg) reda
				if ((cnt6 = image_width - 1) and (aso_out_ready = '1')) then
					next_state <= S0;
				-- ako ne, idemo u stanje S7 ili ostajemo u S6
				else
					if (aso_out_ready = '1') then
						next_state <= S7;
					else
						next_state <= S6;
					end if;
				end if;
				
			when S7 =>
				-- vise nam ne trebaju podaci sa ulaznog DMA (i nema ih vise), na izlazu ne dajemo nista validno
				int_asi_in_ready <= '0';
				aso_out_valid <= '0';
				
				next_state <= S8;
				
			when S8 =>
				-- vise nam ne trebaju podaci sa ulaznog DMA (i nema ih vise), na izlazu ne dajemo nista validno
				int_asi_in_ready <= '0';
				aso_out_valid <= '0';
				
				-- vracamo se u S6 posle 10 taktova
				if (cnt7 = 9) then
					next_state <= S6;
				else
					next_state <= S8;
				end if;

		end case;
	end process;
	
	-- brojanje usiftovanih piksela u stanju S1 (cnt1)
	shifted_pixels_counting: process(clk, reset)
	begin
		if (reset = '1') then
			cnt1 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S1 i samo onda kad ce se usiftovati piksel (shift_enable na '1')
			if ((current_state = S1) and (shift_enable = '1')) then
				-- "prevrtanje" brojaca
				if (cnt1 = MAX_IMAGE_WIDTH*KERNEL_SIZE - 1) then
					cnt1 <= 0;
				else
					cnt1 <= cnt1 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- brojanje rezultata za odbacivanje u stanju S2 (cnt2)
	invalid_results_counting_S2: process(clk, reset)
	begin
		if (reset = '1') then
			cnt2 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S2 i samo onda kad ce se usiftovati piksel (shift_enable na '1')
			if ((current_state = S2) and (shift_enable = '1')) then
				-- "prevrtanje" brojaca
				if (cnt2 = KERNEL_SIZE - 1) then
					cnt2 <= 0;
				else
					cnt2 <= cnt2 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- brojanje korektno poslatih rezultata u stanju S3 (cnt3)
	valid_results_counting_S3: process(clk, reset)
	begin
		if (reset = '1') then
			cnt3 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S3 i samo onda kad ce se poslati validan rezultat (aso_out_ready na '1')
			if ((current_state = S3) and (aso_out_ready = '1')) then
				-- "prevrtanje" brojaca
				if (cnt3 = image_width - 1) then
					cnt3 <= 0;
				else
					cnt3 <= cnt3 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- brojanje isprocesiranih redova (cnt4)
	processed_rows_counting: process(clk, reset)
	begin
		if (reset = '1') then
			cnt4 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S3 na kraju trenutnog reda i samo onda kad ce se poslati validan rezultat (aso_out_ready na '1')
			if ((current_state = S3) and (aso_out_ready = '1') and (cnt3 = image_width - 1)) then
				-- "prevrtanje" brojaca
				if (cnt4 = image_height - 2) then
					cnt4 <= 0;
				else
					cnt4 <= cnt4 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- brojanje rezultata za odbacivanje u stanju S5 (cnt5)
	invalid_results_counting_S5: process(clk, reset)
	begin
		if (reset = '1') then
			cnt5 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S5 i samo onda kad ce se usiftovati piksel (shift_enable na '1')
			-- posto nema ulaza sa DMA, siftovace se na svaki clk, ali ostavimo ovako...
			if ((current_state = S5) and (shift_enable = '1')) then
				-- "prevrtanje" brojaca
				if (cnt5 = KERNEL_SIZE - 1) then
					cnt5 <= 0;
				else
					cnt5 <= cnt5 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- brojanje korektno poslatih rezultata u stanju S6 (cnt 6)
	valid_results_counting_S6: process(clk, reset)
	begin
		if (reset = '1') then
			cnt6 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S6 i samo onda kad ce se poslati validan rezultat (aso_out_ready na '1')
			if ((current_state = S6) and (aso_out_ready = '1')) then
				-- "prevrtanje" brojaca
				if (cnt6 = image_width - 1) then
					cnt6 <= 0;
				else
					cnt6 <= cnt6 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- brojanje vremena dok smo u S8 (cnt7)
	state_duration_S8: process(clk, reset)
	begin
		if (reset = '1') then
			cnt7 <= 0;
		elsif (rising_edge(clk)) then
			-- inkrementiramo dok smo u stanju S8
			if (current_state = S8) then
				-- "prevrtanje" brojaca
				if (cnt7 = 9) then
					cnt7 <= 0;
				else
					cnt7 <= cnt7 + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- interni ready se baca kao output
	asi_in_ready <= int_asi_in_ready;
	
	-- ne koriste se
	aso_out_eop <= '0';
	aso_out_sop <= '0';
	aso_out_empty <= '0';
	avs_params_waitrequest <= '0';

end architecture behav; -- of FIR_Filter_2D_custom
