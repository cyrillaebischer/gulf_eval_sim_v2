----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 28.06.2022 14:05:21
-- Design Name: 
-- Module Name: shiftregsynch_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_textio.ALL;
use STD.textio.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity shiftregsynch_top is
    port(
        data_wr_out : out std_logic_vector(31 downto 0);
        addr_wr_out : out std_logic_vector(5 downto 0);
        wr_en_out   : out std_logic
    );   
end shiftregsynch_top;

architecture Behavioral of shiftregsynch_top is

    -- clocking  and TB reset signals
    constant clk_i_period : time := 0.78 ns;  -- 1/127 = 7.8740157
    signal clk_i, rst_i, clk_div: std_logic;
    
    signal rst_clkdiv : std_logic;
    
    -- Deserializer and Locking
    signal bit_in_s : std_logic := '0';
    signal shiftreg_s: std_logic_vector(9 downto 0);
    signal locked_sig_o : std_logic_vector(9 downto 0);
    signal synched_s, comma_s    : std_logic;
    
    -- Decoder
    signal data8b_s     : std_logic_vector(7 downto 0);
    signal disp_s, DataK_out_s, rxCodeErr, rxDispErr  : std_logic;
    
    -- Data Extraction
    signal word_pack_s  : std_logic_vector(31 downto 0);
    signal word_output_s : std_logic;
    
    ---------------------------------------------------------------------------------
    -- BEGIN COMPONENT DECLARATIONS --
    component Clock_Divider is
        port (
            clk  : in std_logic;
            reset: in std_logic;
            clock_out: out std_logic);
    end component;
    
    component sipo is
        port(
            clk_i :in std_logic;
            rst_i :in std_logic;
            data_i :in std_logic;
            data_o :out std_logic_vector(9 downto 0)
            );
        end component;
    
    component sync_statemachine is
        port(
            reg_i : in std_logic_vector(9 downto 0);
            clk_i : in std_logic;
            rst_i : in std_logic;  
            err_i : in std_logic;        
            reg_o : out std_logic_vector(9 downto 0);
            aligned_o : out std_logic;
            comma_o : out std_logic
            );
       end component;
       
    component data_wr_fsm is
           Port (
                rst_i : in std_logic;
                clk_i : in std_logic;
                valid_i : in std_logic;
                wr_data_in : in std_logic_vector(31 downto 0);
                wr_data_out : out std_logic_vector(31 downto 0);
                wr_en_o: out std_logic;
                wr_adr_o : out std_logic_vector(5 downto 0));
       end component;
        
begin
    
    ---- shiftregister ----
    shift_reg: sipo
        port map( 
            clk_i => clk_i,
            rst_i => rst_i,
            data_i => bit_in_s,
            data_o =>shiftreg_s
            ); 
            
            
    ---- comma / locking ----
    commalink: sync_statemachine
        port map(
            reg_i => shiftreg_s,
            clk_i => clk_i,
            rst_i => rst_i,
            err_i => rxCodeErr,
            reg_o => locked_sig_o,
            aligned_o => synched_s,
            comma_o => comma_s
        );

    
    U_Decode8b10b : entity work.Decode8b10b 
          generic map (
             GATE_DELAY_G => 1 ns
          )
          port map (
             clk      => clk_i,
             rst      => rst_i,
             dataIn   => locked_sig_o,
             dispIn   => disp_s,
             dataOut  => data8b_s,
             dataKOut => DataK_out_s,
             dispOut  => disp_s,
             codeErr  => rxCodeErr,
             dispErr  => rxDispErr
          );

    ---- Bit read in process ----
    rd_values: process(clk_i)
        
        file fp_output : text is in "C:\Users\Cyrill\Documents\S6\BA-GULFstream\Gulf_Eval_Setup\Gulf_Eval_Setup\8chan_output_err.dat";
        variable ln_r     : line;
        variable x : std_logic;
        
        variable stop          : boolean := false;
        begin   
            if (rising_Edge(clk_i))then
                if stop = false then
                            readline(fp_output,ln_r);
                            read(ln_r,x);
                            bit_in_s <= x;
                            if endfile(fp_output) = true then
                                stop := true;    
                            end if;
                end if;
            else
                bit_in_s <= bit_in_s;
            end if;
    end process;
    
    ---- word packaging process ----
word_pack: process(clk_i, clk_div)
    variable word_cnt_v : unsigned(1 downto 0) := "00";
    begin
            
                if rising_edge(clk_div) then 
                    if (comma_s = '0') and (synched_s = '1') then                   
                        case word_cnt_v is
                            when "00" =>
                                word_pack_s(31 downto 24) <= data8b_s;
                                word_cnt_v := word_cnt_v +1;
                                
                            when "01" =>
                                word_pack_s(23 downto 16) <= data8b_s; 
                                word_cnt_v := word_cnt_v +1;
                            when "10" =>
                                word_pack_s(15 downto 8) <= data8b_s; 
                                word_cnt_v := word_cnt_v +1;
                            when "11"=>
                                word_pack_s(7 downto 0) <= data8b_s; 
                                word_cnt_v := "00";
                                word_output_s <= '1';
                            when others =>
                                --word_output_s <= '0';
                            
                        end case;
                    else
                        word_output_s <= '0';
                        word_pack_s <= (others => '0');
                    end if;
                end if;
            
    end process;
    
    ---- Write to Memory FSM ----
    adr_fsm: data_wr_fsm
               Port map (
                   rst_i    => rst_i,
                   clk_i    => clk_div,
                   valid_i  => word_output_s,
                   wr_data_in => word_pack_s,
                   wr_data_out => data_wr_out,
                   wr_en_o  => wr_en_out,
                   wr_adr_o => addr_wr_out
                   );                   
        
    rst_clkdiv <= not(synched_s);
    clk_divider: Clock_Divider
        port map(
            clk  => clk_i,
            reset=> rst_clkdiv,
            clock_out => clk_div
            );
            
    ---- clock process ----   
clkX1: process
    begin 
        clk_i <= '0';
        wait for clk_i_period/2;
        clk_i <= '1';
        wait for clk_i_period/2;
    end process;
    
    ---- reset process ----
    reset: process
    begin
        rst_i <= '1';
        wait for 30 ns;
        rst_i <= '0';
       wait;
    end process;


end Behavioral;
