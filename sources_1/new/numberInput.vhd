----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/03/2026 10:06:30 PM
-- Design Name: 
-- Module Name: numberInput - Behavioral
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
use IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;
use IEEE.math_real.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity numberInput is
    Port ( SW 			: in  STD_LOGIC_VECTOR (15 downto 0);
           BTN 			: in  STD_LOGIC_VECTOR (4 downto 0);
           CLK 			: in  STD_LOGIC;
           LED 			: out  STD_LOGIC_VECTOR (15 downto 0);
           SSEG_CA 		: out  STD_LOGIC_VECTOR (7 downto 0);
           SSEG_AN 		: out  STD_LOGIC_VECTOR (7 downto 0);
           UART_TXD 	: out  STD_LOGIC);
end numberInput;

architecture Behavioral of numberInput is

component UART_TX_CTRL
Port(
	SEND : in std_logic;
	DATA : in std_logic_vector(7 downto 0);
	CLK : in std_logic;          
	READY : out std_logic;
	UART_TX : out std_logic
	);
end component;

component debouncer
Generic(
        DEBNC_CLOCKS : integer;
        PORT_WIDTH : integer);
Port(
		SIGNAL_I : in std_logic_vector(4 downto 0);
		CLK_I : in std_logic;          
		SIGNAL_O : out std_logic_vector(4 downto 0)
		);
end component;

--The type definition for the UART state machine type. Here is a description of what
--occurs during each state:
-- RST_REG     -- Do Nothing. This state is entered after configuration or a user reset.
--                The state is set to LD_INIT_STR.
-- LD_INIT_STR -- The Welcome String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The welcome string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
-- SEND_CHAR   -- uartSend is set high for a single clock cycle, signaling the character
--                data at sendStr(strIndex) to be registered by the UART_TX_CTRL at the next
--                cycle. Also, strIndex is incremented (behaves as if it were post 
--                incremented after reading the sendStr data). The state is set to RDY_LOW.
-- RDY_LOW     -- Do nothing. Wait for the READY signal from the UART_TX_CTRL to go low, 
--                indicating a send operation has begun. State is set to WAIT_RDY.
-- WAIT_RDY    -- Do nothing. Wait for the READY signal from the UART_TX_CTRL to go high, 
--                indicating a send operation has finished. If READY is high and strEnd = 
--                StrIndex then state is set to WAIT_BTN, else if READY is high and strEnd /=
--                StrIndex then state is set to SEND_CHAR.
-- WAIT_BTN    -- Do nothing. Wait for a button press on BTNU, BTNL, BTND, or BTNR. If a 
--                button press is detected, set the state to LD_BTN_STR.
-- LD_BTN_STR  -- The Button String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The button string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
type UART_STATE_TYPE is (RST_REG, LD_INIT_STR, SEND_CHAR, RDY_LOW, WAIT_RDY, WAIT_BTN, LD_BTN_STR);

--The CHAR_ARRAY type is a variable length array of 8 bit std_logic_vectors. 
--Each std_logic_vector contains an ASCII value and represents a character in
--a string. The character at index 0 is meant to represent the first
--character of the string, the character at index 1 is meant to represent the
--second character of the string, and so on.
type CHAR_ARRAY is array (integer range<>) of std_logic_vector(7 downto 0);

constant RESET_CNTR_MAX : std_logic_vector(17 downto 0) := "110000110101000000";-- 100,000,000 * 0.002 = 200,000 = clk cycles per 2 ms

constant WELCOME_STR_LEN : natural := 29;
constant BTN_STR_LEN : natural := 24;

--Welcome string definition. Note that the values stored at each index
--are the ASCII values of the indicated character.
constant WELCOME_STR : CHAR_ARRAY(0 to 28) := (X"0A",  --\n
															  X"0D",  --\r
															  X"4E",  --N
															  X"45",  --E
															  X"58",  --X
															  X"59",  --Y
															  X"53",  --S
															  X"20",  -- 
															  X"41",  --A
															  X"37",  --7
															  X"20",  -- 
															  X"47",  --G
															  X"50",  --P
															  X"49",  --I
															  X"4F",  --O
															  X"2F",  --/
															  X"55",  --U
															  X"41",  --A
															  X"52",  --R
															  X"54",  --T
															  X"20",  -- 
															  X"44",  --D
															  X"45",  --E
															  X"4D",  --M
															  X"4F",  --O
															  X"21",  --!
															  X"0A",  --\n
															  X"0A",  --\n
															  X"0D"); --\r
															  
--Button press string definition.
constant BTN_STR : CHAR_ARRAY(0 to 23) :=     (X"42",  --B
															  X"75",  --u
															  X"74",  --t
															  X"74",  --t
															  X"6F",  --o
															  X"6E",  --n
															  X"20",  -- 
															  X"70",  --p
															  X"72",  --r
															  X"65",  --e
															  X"73",  --s
															  X"73",  --s
															  X"20",  --
															  X"64",  --d
															  X"65",  --e
															  X"74",  --t
															  X"65",  --e
															  X"63",  --c
															  X"74",  --t
															  X"65",  --e
															  X"64",  --d
															  X"21",  --!
															  X"0A",  --\n
															  X"0D"); --\r

constant TMR_CNTR_MAX : std_logic_vector(9 downto 0) := "1111101000"; --1000 = clk cycles
--This is used to determine when the 7-segment display should be
--incremented
signal tmrCntr : std_logic_vector(9 downto 0) := (others => '0');

constant MAX_STR_LEN : integer := 29;

--Contains the current string being sent over uart.
signal sendStr : CHAR_ARRAY(0 to (MAX_STR_LEN - 1));

--Contains the index of the next character to be sent over uart
--within the sendStr variable.
signal strIndex : natural;

--Contains the length of the current string being sent over uart.
signal strEnd : natural;

type segment_Data_type is array (0 to 7) of std_logic_vector(3 downto 0);
signal segment_Data : segment_Data_type := ("0011", "1000", "0100", "0010", "0001", "1001", "0101", "0101");

--Contains the index of the next character to be sent over uart
--within the sendStr variable.
signal segmentIndex : integer := 0;

constant MAX_SEGMENT_LEN : integer := 7;

--Used to determine when a button press has occured
signal btnReg : std_logic_vector (3 downto 0) := "0000";
signal btnDetect : std_logic;

--UART_TX_CTRL control signals
signal uartRdy : std_logic;
signal uartSend : std_logic := '0';
signal uartData : std_logic_vector (7 downto 0):= "00000000";
signal uartTX : std_logic;

--Current uart state signal
signal uartState : UART_STATE_TYPE := RST_REG;

--Debounced btn signals used to prevent single button presses
--from being interpreted as multiple button presses.
signal btnDeBnc : std_logic_vector(4 downto 0);

signal clk_cntr_reg : std_logic_vector (4 downto 0) := (others=>'0'); 

signal pwm_val_reg : std_logic := '0';

--this counter counts the amount of time paused in the UART reset state
signal reset_cntr : std_logic_vector (17 downto 0) := (others=>'0');


begin

LED <= SW;

--This process controls the counter that triggers the 7-segment
--to be incremented. It counts 100,000,000 and then resets.		  
timer_counter_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if ((tmrCntr = TMR_CNTR_MAX) or (BTN(4) = '1')) then
			tmrCntr <= (others => '0');
		else
			tmrCntr <= tmrCntr + 1;
		end if;
	end if;
end process;


seg_index_counter_process : process (CLK)
begin
	if (rising_edge(CLK)) then
	   if (tmrCntr = TMR_CNTR_MAX) then
            if (segmentIndex = MAX_SEGMENT_LEN) then
                segmentIndex <= 0;
            else
                segmentIndex <= segmentIndex + 1;
            end if;
       end if;
	end if;
end process;

--Selects consecutive LED Segments
seg_led_select_process : process (CLK)
begin
	if (rising_edge(CLK)) then
	    case segmentIndex is
	        when 0 => SSEG_AN <= "11111110";
            when 1 => SSEG_AN <= "11111101";
            when 2 => SSEG_AN <= "11111011";
            when 3 => SSEG_AN <= "11110111";
            when 4 => SSEG_AN <= "11101111";
            when 5 => SSEG_AN <= "11011111";
            when 6 => SSEG_AN <= "10111111";
            when 7 => SSEG_AN <= "01111111";
            when others => SSEG_AN <= "11111111";
        end case;
	end if;
end process;

--Sets consecutive LED Segments
seg_led_set_process : process (CLK)
begin
	if (rising_edge(CLK)) then
	    case segment_Data(segmentIndex) is
	       when "0000" =>
		      SSEG_CA <= "11000000";
		   when "0001" =>
		      SSEG_CA <= "11111001";
		   when "0010" =>
		      SSEG_CA <= "10100100";
		   when "0011" =>
		      SSEG_CA <= "10110000";
		   when "0100" =>
		      SSEG_CA <= "10011001";
		   when "0101" =>
		      SSEG_CA <= "10010010";
		   when "0110" =>
		      SSEG_CA <= "10000010";
		   when "0111" =>
		      SSEG_CA <= "11111000";
		   when "1000" =>
		      SSEG_CA <= "10000000";
		   when "1001" =>
		      SSEG_CA <= "10010000";
		   when others =>
		      SSEG_CA <= "11111111";
        end case;
	end if;
end process;


----------------------------------------------------------
------              Button Control                 -------
----------------------------------------------------------
--Buttons are debounced and their rising edges are detected
--to trigger UART messages


--Debounces btn signals
Inst_btn_debounce: debouncer 
    generic map(
        DEBNC_CLOCKS => (2**16),
        PORT_WIDTH => 5)
    port map(
            SIGNAL_I => BTN,
            CLK_I => CLK,
            SIGNAL_O => btnDeBnc
	);

--Registers the debounced button signals, for edge detection.
btn_reg_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		btnReg <= btnDeBnc(3 downto 0);
	end if;
end process;

--btnDetect goes high for a single clock cycle when a btn press is
--detected. This triggers a UART message to begin being sent.
btnDetect <= '1' when ((btnReg(0)='0' and btnDeBnc(0)='1') or
								(btnReg(1)='0' and btnDeBnc(1)='1') or
								(btnReg(2)='0' and btnDeBnc(2)='1') or
								(btnReg(3)='0' and btnDeBnc(3)='1')  ) else
				  '0';
				  
operations_btn_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (btnReg(2)='0' and btnDeBnc(2)='1') then
			if (SW(0) = '1') then
			     if(segment_Data(0) = 9) then
			         segment_Data(0) <= "0000";
			     else
			         segment_Data(0) <= segment_Data(0) + 1;
			     end if;
			end if;
			if (SW(1) = '1') then
			     if(segment_Data(1) = 9) then
			         segment_Data(1) <= "0000";
			     else
			         segment_Data(1) <= segment_Data(1) + 1;
			     end if;
			end if;
			if (SW(2) = '1') then
			     if(segment_Data(2) = 9) then
			         segment_Data(2) <= "0000";
			     else
			         segment_Data(2) <= segment_Data(2) + 1;
			     end if;
			end if;
			if (SW(3) = '1') then
			     if(segment_Data(3) = 9) then
			         segment_Data(3) <= "0000";
			     else
			         segment_Data(3) <= segment_Data(3) + 1;
			     end if;
			end if;
			if (SW(4) = '1') then
			     if(segment_Data(4) = 9) then
			         segment_Data(4) <= "0000";
			     else
			         segment_Data(4) <= segment_Data(4) + 1;
			     end if;
			end if;
			if (SW(5) = '1') then
			     if(segment_Data(5) = 9) then
			         segment_Data(5) <= "0000";
			     else
			         segment_Data(5) <= segment_Data(5) + 1;
			     end if;
			end if;
			if (SW(6) = '1') then
			     if(segment_Data(6) = 9) then
			         segment_Data(6) <= "0000";
			     else
			         segment_Data(6) <= segment_Data(6) + 1;
			     end if;
			end if;
			if (SW(7) = '1') then
			     if(segment_Data(7) = 9) then
			         segment_Data(7) <= "0000";
			     else
			         segment_Data(7) <= segment_Data(7) + 1;
			     end if;
			end if;
	    end if;
		if (btnReg(3)='0' and btnDeBnc(3)='1') then
			if (SW(0) = '1') then
			     if(segment_Data(0) = 0) then
			         segment_Data(0) <= "1001";
			     else
			         segment_Data(0) <= segment_Data(0) - 1;
			     end if;
			end if;
			if (SW(1) = '1') then
			     if(segment_Data(1) = 0) then
			         segment_Data(1) <= "1001";
			     else
			         segment_Data(1) <= segment_Data(1) - 1;
			     end if;
			end if;
			if (SW(2) = '1') then
			     if(segment_Data(2) = 0) then
			         segment_Data(2) <= "1001";
			     else
			         segment_Data(2) <= segment_Data(2) - 1;
			     end if;
			end if;
			if (SW(3) = '1') then
			     if(segment_Data(3) = 0) then
			         segment_Data(3) <= "1001";
			     else
			         segment_Data(3) <= segment_Data(3) - 1;
			     end if;
			end if;
			if (SW(4) = '1') then
			     if(segment_Data(4) = 0) then
			         segment_Data(4) <= "1001";
			     else
			         segment_Data(4) <= segment_Data(4) - 1;
			     end if;
			end if;
			if (SW(5) = '1') then
			     if(segment_Data(5) = 0) then
			         segment_Data(5) <= "1001";
			     else
			         segment_Data(5) <= segment_Data(5) - 1;
			     end if;
			end if;
			if (SW(6) = '1') then
			     if(segment_Data(6) = 0) then
			         segment_Data(6) <= "1001";
			     else
			         segment_Data(6) <= segment_Data(6) - 1;
			     end if;
			end if;
			if (SW(7) = '1') then
			     if(segment_Data(7) = 0) then
			         segment_Data(7) <= "1001";
			     else
			         segment_Data(7) <= segment_Data(7) - 1;
			     end if;
			end if;
		end if;
	end if;
end process;


----------------------------------------------------------
------              UART Control                   -------
----------------------------------------------------------
--Messages are sent on reset and when a button is pressed.

--This counter holds the UART state machine in reset for ~2 milliseconds. This
--will complete transmission of any byte that may have been initiated during 
--FPGA configuration due to the UART_TX line being pulled low, preventing a 
--frame shift error from occuring during the first message.
process(CLK)
begin
  if (rising_edge(CLK)) then
    if ((reset_cntr = RESET_CNTR_MAX) or (uartState /= RST_REG)) then
      reset_cntr <= (others=>'0');
    else
      reset_cntr <= reset_cntr + 1;
    end if;
  end if;
end process;

--Next Uart state logic (states described above)
next_uartState_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (btnDeBnc(4) = '1') then
			uartState <= RST_REG;
		else	
			case uartState is 
			when RST_REG =>
                if (reset_cntr = RESET_CNTR_MAX) then
                  uartState <= LD_INIT_STR;
                end if;
			when LD_INIT_STR =>
				uartState <= SEND_CHAR;
			when SEND_CHAR =>
				uartState <= RDY_LOW;
			when RDY_LOW =>
				uartState <= WAIT_RDY;
			when WAIT_RDY =>
				if (uartRdy = '1') then
					if (strEnd = strIndex) then
						uartState <= WAIT_BTN;
					else
						uartState <= SEND_CHAR;
					end if;
				end if;
			when WAIT_BTN =>
				if (btnDetect = '1') then
					uartState <= LD_BTN_STR;
				end if;
			when LD_BTN_STR =>
				uartState <= SEND_CHAR;
			when others=> --should never be reached
				uartState <= RST_REG;
			end case;
		end if ;
	end if;
end process;

--Loads the sendStr and strEnd signals when a LD state is
--is reached.
string_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR) then
			sendStr <= WELCOME_STR;
			strEnd <= 8;
		elsif (uartState = LD_BTN_STR) then
			sendStr(0 to 23) <= BTN_STR;
			strEnd <= 8;
		end if;
	end if;
end process;

--Conrols the strIndex signal so that it contains the index
--of the next character that needs to be sent over uart
char_count_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR or uartState = LD_BTN_STR) then
			strIndex <= 0;
		elsif (uartState = SEND_CHAR) then
			strIndex <= strIndex + 1;
		end if;
	end if;
end process;

--Controls the UART_TX_CTRL signals
char_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = SEND_CHAR) then
			uartSend <= '1';
			uartData <= "0011" & segment_Data(7-strIndex);
		else
			uartSend <= '0';
		end if;
	end if;
end process;

--Component used to send a byte of data over a UART line.
Inst_UART_TX_CTRL: UART_TX_CTRL port map(
		SEND => uartSend,
		DATA => uartData,
		CLK => CLK,
		READY => uartRdy,
		UART_TX => uartTX 
	);

UART_TXD <= uartTX;

end Behavioral;
