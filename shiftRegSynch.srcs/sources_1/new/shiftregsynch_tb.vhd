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
        word_out : out std_logic_vector(31 downto 0);
        fifo_rd_en_i: in std_logic
    );   
end shiftregsynch_top;

architecture Behavioral of shiftregsynch_top is
    -- clocking signals
    constant clk_i_period : time := 0.78 ns;  -- 1/127 = 7.8740157
    signal clk_i, rst_i, clk_div: std_logic;
    
    signal rst_clkdiv : std_logic;
    
    signal bit_in_s : std_logic := '0';
    signal shiftreg_s: std_logic_vector(9 downto 0);
    signal locked_sig_o : std_logic_vector(9 downto 0);
    signal synched_s, comma_s    : std_logic;
    
    signal data8b_s     : std_logic_vector(7 downto 0);
    signal disp_s, DataK_out_s, rxCodeErr, rxDispErr  : std_logic;
    
    signal word_pack_s  : std_logic_vector(31 downto 0);
    signal word_output_s : std_logic;
    signal cnt_en_s   : std_logic := '0';
    signal cnt_rst_s  : std_logic;
    signal cnt_o_s   : std_logic_vector(3 downto 0);
    
    -- FIFO signals
    signal fifo_wr_en_s : std_logic;
    signal fifo_full_s, fifo_empty_s, fifo_ol_s, fifo_ul_s, fifo_val_s: std_logic;
    signal rd_en_tst : std_logic:= '0';
    
    -- BEGIN COMPONENT DECLARATIONS --
    component Clock_Divider is
        port (
            clk  : in std_logic;
            reset: in std_logic;
            clock_out: out std_logic);
    end component;
    
    component fifo_statemachine is
        Port (
            clk_i: in std_logic;
            rst_i: in std_logic;
            cnt_o_i: in std_logic_vector(3 downto 0);
            word_valid_i: in std_logic;
            fifo_wr_o: out std_logic
            );
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
            reg_o : out std_logic_vector(9 downto 0);
            aligned_o : out std_logic;
            comma_o : out std_logic
            );
       end component;
       
    component counter is
        Port (
             en_i    : in std_logic;
             rst_i   : in std_logic;
             clk_i   : in std_logic;
               
             cnt_o   : out std_logic_vector(3 downto 0)
            );
    end component;
    
    COMPONENT fifo_32bit
      PORT (
        rst : IN STD_LOGIC;
        clk : IN STD_LOGIC;
        din : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        wr_en : IN STD_LOGIC;
        rd_en : IN STD_LOGIC;
        dout : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        full : OUT STD_LOGIC;
        overflow : OUT STD_LOGIC;
        empty : OUT STD_LOGIC;
        valid : OUT STD_LOGIC;
        underflow : OUT STD_LOGIC
      );
    END COMPONENT;
        
begin
    cnt_rst_s <= '1' when (rst_i = '1' ) else '0'; --or comma_s = '1'
    
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
            reg_o => locked_sig_o,
            aligned_o => synched_s,
            comma_o => comma_s
        );
        
    ---- counter for word packaging ----
    counter_words: counter
        port map(
            en_i => cnt_en_s,
            rst_i => cnt_rst_s,
            clk_i => clk_i,
            cnt_o => cnt_o_s
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
        
        file fp_output : text is in "C:\Users\Cyrill\Documents\S6\BA-GULFstream\Gulf_Eval_Setup\Gulf_Eval_Setup\8chan_output.dat";
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
       -- if rising_edge(clk_i) then 
            if (comma_s = '0') and (synched_s = '1') then
                cnt_en_s <= '1';
                if rising_edge(clk_div) then                    
                    case word_cnt_v is
                        when "00" =>
                            word_pack_s(31 downto 24) <= data8b_s; 
                            word_output_s <= '0';
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
                end if;
            else
                word_pack_s <= (others => '0');
            end if;
            
--        if word_output_s = '1' then 
--            word_out <= word_pack_s;
--        end if;
        
    --    end if;
    end process;
            
    -------- FiFo ---------
    fifo_fsm: fifo_statemachine
        port map(
            clk_i => clk_i,
            rst_i => rst_i,
            cnt_o_i => cnt_o_s,
            word_valid_i => word_output_s,
            fifo_wr_o => fifo_wr_en_s
            );
    
    data_fifo : fifo_32bit
          PORT MAP (
            rst => rst_i,
            clk => clk_i,
            din => word_pack_s,
            wr_en => fifo_wr_en_s,
            rd_en => rd_en_tst,
            dout => word_out,
            full => fifo_full_s,
            overflow => fifo_ol_s,
            empty => fifo_empty_s,
            valid => fifo_val_s,
            underflow => fifo_ul_s
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
