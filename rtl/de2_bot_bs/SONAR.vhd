-- SONAR.VHD (a peripheral module for SCOMP)
-- 2012.06.07
-- This sonar device is based on the summer 2001 project 
-- by Clliff Cross, Matt Pinkston, Phap Dinh, and Vu Phan.
-- Interrupt functionality based on the summer 2014 project
-- by Team Twinkies

LIBRARY IEEE;
LIBRARY LPM;

USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
USE LPM.LPM_COMPONENTS.ALL;


ENTITY SONAR IS
  PORT(CLOCK,    -- 170 kHz
       RESETN,   -- active-low reset
       CS,       -- device select for I/O operations (should be high when I/O address is 0xA0 through 0xA7, and
                 --   also when an IO_CYCLE is ongoing
       IO_WRITE, -- indication of OUT (vs. IN), when I/O operation occurring
       ECHO      : IN    STD_LOGIC;   -- active-high indication of echo (remains high until INIT lowered)
       ADDR      : IN    STD_LOGIC_VECTOR(4 DOWNTO 0);  -- select one of eight internal registers for I/O, assuming
                            -- that device in fact supports usage of multiple registers between 0xA0 and 0xA7
       INIT      : OUT   STD_LOGIC;        -- initiate a ping (hold high until completion of echo/no-echo cycle)
       LISTEN    : OUT   STD_LOGIC;        -- listen (raise after INIT, allowing for blanking interval)
       SONAR_NUM : OUT   STD_LOGIC_VECTOR(2 DOWNTO 0);  -- select a sonar transducer for pinging
       SONAR_INT : OUT   STD_LOGIC;  -- interrupt output
       IO_DATA   : INOUT STD_LOGIC_VECTOR(15 DOWNTO 0)  -- I/O data bus for host operations
       );
END SONAR;


ARCHITECTURE behavior OF SONAR IS
  SIGNAL INIT_INT : STD_LOGIC;  -- Local (to architecture) copy of INIT
  SIGNAL DISABLE_SON : STD_LOGIC;  -- 1: disables all sonar activity 0: enables sonar scanning
  SIGNAL SONAR_EN : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Stores 8 flags to determine whether a sonar is enabled
  SIGNAL INT_EN : STD_LOGIC_VECTOR(7 DOWNTO 0);  -- Stores 8 flags to determine whether interrupts are enabled
  SIGNAL DISTANCE : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- Used to store calculated distance at each iteration
  TYPE SONAR_DATA IS ARRAY (17 DOWNTO 0) OF STD_LOGIC_VECTOR(15 DOWNTO 0);  -- declare an array type
    -- 17 = object_detected, 16 = alarms, 15 DOWNTO 8 = distance, 7 DOWNTO 0 = echo time
  SIGNAL SONAR_RESULT : SONAR_DATA;      -- and use it to store a sonar value (distance) for each sonar transducer
  SIGNAL SELECTED_SONAR : STD_LOGIC_VECTOR(2 DOWNTO 0);    -- At a given time, one sonar is going to be of interest
  SIGNAL ECHO_TIME : STD_LOGIC_VECTOR(15 DOWNTO 0); -- This will be used to time the echo
  SIGNAL PING_TIME : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- This will be used to time the pinger process
  SIGNAL ALARM_DIST : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- Stores maximum distance where alarm is triggered
  -- These three constants assume a 170Khz clock, and would need to be changed if the clock changes
  CONSTANT MIN_TIME : INTEGER := 4325; -- minimum time that sonars must be off between readings.
  CONSTANT MAX_DIST  : STD_LOGIC_VECTOR(15 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(MIN_TIME+6300, 16);  -- ignore echoes after ~5 meters
  CONSTANT OFF_TIME  : STD_LOGIC_VECTOR(15 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(MIN_TIME, 16);  -- creates the minimum cycle
  CONSTANT BLANK_TIME  : STD_LOGIC_VECTOR(15 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(MIN_TIME + 8*17, 16);  -- Ignore early false echoes

  CONSTANT NO_ECHO  : STD_LOGIC_VECTOR(15 DOWNTO 0) := x"7FFF";  -- use 0x7FFF (max positive number) as an indication that no echo was detected
  SIGNAL IO_IN : STD_LOGIC;      -- a derived signal that shows an IN is requested from this device (and it should drive IO data bus)
  SIGNAL LATCH  : STD_LOGIC;      -- a signal that goes high when the host (SCOMP) does an IO_OUT to this device
  SIGNAL PING_STARTED : STD_LOGIC;     -- an indicator that a ping is in progress
  SIGNAL PING_DONE : STD_LOGIC;  -- an indicator that a ping has resulted in an echo, or too much time has passed for an echo
  SIGNAL I : INTEGER;          -- note that we CAN use actual integers.  This will be used as an index below.  Because it does
                               --   not actually need to be implemented as a "real" signal, it can be replaced with a VARIABLE
                               --   declaration within the PROCESS where it is used below.

  BEGIN
    
    -- Use LPM function to create bidirectional I/O data bus
    IO_BUS: lpm_bustri
    GENERIC MAP (
      lpm_width => 16
    )
    PORT MAP (
      data     => SONAR_RESULT( CONV_INTEGER(ADDR)), -- this assumes that during an IN operation, the lowest five address bits 
                                                     --    specify the value of interest.  See definition of SONAR_RESULT above.
                                                     --  The upper address bits are decoded to produce the CS signal used below
      enabledt => IO_IN,  -- based on CS (see below)
      tridata  => IO_DATA
    );

    IO_IN <= (CS AND NOT(IO_WRITE));  -- Drive IO_DATA bus (see above) when this
                                       --   device is selected (CS high), and
                                       --   when it is not an OUT command.
    LATCH <= CS AND IO_WRITE;   -- Similarly, this produces a high (and a rising
                                --   edge suitable for latching), but only when an OUT command occurs       
	
    WITH SELECTED_SONAR SELECT  -- SELECTED_SONAR is the internal signal with a sonar mapping that makes more logical sense.
      SONAR_NUM <= "000" WHEN "001",
                   "001" WHEN "101",
                   "010" WHEN "011",
                   "011" WHEN "111",
                   "100" WHEN "000",
                   "101" WHEN "100",
                   "110" WHEN "010",
                   "111" WHEN "110",
                   "000" WHEN OTHERS;

    INIT <= INIT_INT;
    
    -- distance is the echo time minus a delay constant.
    DISTANCE <= ECHO_TIME-30;
          
    PINGER: PROCESS (CLOCK, RESETN)   -- This process issues a ping after a PING_START signal and times the return

      BEGIN
        IF (RESETN = '0') THEN  -- after reset, do NOT ping, and set all stored echo results to NO_ECHO 
          SONAR_RESULT( 16 ) <= x"0000"; --Least significant 8 bits used for alarm triggers
          SONAR_RESULT( 17 ) <= x"0000"; --Least significant 8 bits used for objects detected
          PING_TIME <= x"0000";
          ECHO_TIME <= x"0000";
          LISTEN <= '0';
          INIT_INT <= '0';                       
          PING_STARTED <= '0';
          PING_DONE <= '0';
          SELECTED_SONAR <= "000";
        -- INITIALIZING SONAR timing values....  
        -- These next few lines of code are something new for this class.  Beware of thinking of
        --   this as equivalent to a series of 8 statements executed SEQUENTIALLY, with an integer "I"
        --   stored somewhere.  A VHDL synthesizer, such as that within Quartus, will create hardware 
        --   that assigns each of the 8 SONAR_RESULT values to NO_ECHO *concurrently* upon reset.  In
        --   other words, the FOR LOOP is a convenient shorthand notation to make 8 parallel assignments.
          FOR I IN 0 to 7 LOOP
            SONAR_RESULT( I ) <= NO_ECHO;   -- "I" was declared as an INTEGER SIGNAL.  Could have been a VARIABLE.
          END LOOP;
        -- However, it is worth noting that if the statement in the loop had been
        --  SONAR_RESULT( I ) <= SONAR_RESULT( (I-1) MOD 8 )
        -- then something else entirely would happen.  First, it would be a circular buffer (like
        -- a series of shift registers with the end wrapped around to the beginning).  Second, it
        -- would not be possible to implement it as a purely combinational logic assignment, since
        -- it would infer some sort of latch (using some "current" values of SONAR_RESULT on
        -- the right-hand side to define "next" values on the right-hand side).          
          
        ELSIF (RISING_EDGE(CLOCK)) THEN
          IF (PING_STARTED /= '1') THEN  -- a new ping should start
            -- increment the sonar selection and check if it's enabled
            SELECTED_SONAR <= SELECTED_SONAR+1;
            IF SONAR_EN(CONV_INTEGER(SELECTED_SONAR)+1) = '1' THEN
              PING_STARTED <= '1';
              PING_DONE <= '0';
              PING_TIME <= x"0000";
              ECHO_TIME <= x"0000";
              LISTEN <= '0';  -- Blank on (turn off after 1.2 ms)
            END IF;
            -- while not otherwise modifying SONAR_RESULT, make sure that
            --  any disabled sonars return 'blank' information
            FOR I IN 0 to 7 LOOP
              IF (( SONAR_EN(I) = '0') AND (CONV_INTEGER(SELECTED_SONAR) /= I) ) THEN
                SONAR_RESULT( 16 )( I ) <= '0';
                SONAR_RESULT( 17 )( I ) <= '0';
                SONAR_RESULT( I ) <= NO_ECHO;
                SONAR_RESULT( I + 8 ) <= NO_ECHO;
              END IF;
            END LOOP;
          ELSE      -- Handle a ping already in progress
            PING_TIME <= PING_TIME + 1;    --   ... increment time counter (ALWAYS)
            IF (PING_TIME >= OFF_TIME) THEN
              ECHO_TIME <= ECHO_TIME + 1;
            END IF;
            IF ( (ECHO = '1') AND (PING_DONE = '0') ) THEN        --   Save the result of a valid echo
              PING_DONE <= '1';
              -- Set alarm flag to 1 if within the programmed ALARM_DIST range.
              IF ( (DISTANCE >= 10#0#) AND (DISTANCE <= CONV_INTEGER(ALARM_DIST)) ) THEN
                SONAR_RESULT( 16 )( CONV_INTEGER('0'&SELECTED_SONAR) ) <= '1';
                IF INT_EN(CONV_INTEGER(SELECTED_SONAR)) = '1' THEN
                  SONAR_INT <= '1';
                END IF;
              ELSE  -- Set alarm flag to 0 otherwise
			    SONAR_RESULT( 16 )( CONV_INTEGER('0'&SELECTED_SONAR) ) <= '0';
              END IF;
              SONAR_RESULT( 17 )( CONV_INTEGER('0'&SELECTED_SONAR) ) <= '1';
              SONAR_RESULT( CONV_INTEGER("00"&SELECTED_SONAR) ) <= ECHO_TIME;   
              SONAR_RESULT( CONV_INTEGER("00"&SELECTED_SONAR) + 8 ) <= DISTANCE;
            END IF;
            IF (PING_TIME = OFF_TIME) THEN  -- Wait for OFF_TIME to pass before starting the ping
              INIT_INT <= '1';  -- Issue a ping.  This must stay high at least until the echo comes back
            ELSIF (PING_TIME = BLANK_TIME) THEN  --   ... turn off blanking at 1.1, going on 1.2 ms
              LISTEN <= '1';
            ELSIF (PING_TIME = MAX_DIST) THEN   -- Stop listening at a specified distance
              INIT_INT <= '0';
              LISTEN <= '0';
              SONAR_INT <= '0';
              IF (PING_DONE = '0' ) THEN     -- And if echo not found earlier, set NO_ECHO indicator
                SONAR_RESULT( 16 )( CONV_INTEGER('0'&SELECTED_SONAR) ) <= '0';
                SONAR_RESULT( 17 )( CONV_INTEGER('0'&SELECTED_SONAR) ) <= '0';
                SONAR_RESULT( CONV_INTEGER("00"&SELECTED_SONAR)) <= NO_ECHO;
                SONAR_RESULT( CONV_INTEGER("00"&SELECTED_SONAR) + 8) <= NO_ECHO;
              END IF;
              PING_STARTED <= '0';
            END IF;
          END IF;
        END IF;
      END PROCESS;

    INPUT_HANDLER: PROCESS (RESETN, LATCH, CLOCK)  -- write to address 0x12 (offset from base of 0xA0) will
                                            --   set the enabled sonars.  Writing to address offset 0x10     
                                            --   will set the alarm distance.              
      BEGIN                  
        IF (RESETN = '0' ) THEN
          SONAR_EN <= x"00";
          ALARM_DIST <= x"0000";
          INT_EN <= x"FF";
        ELSE
          IF (RISING_EDGE(LATCH)) THEN   -- an "OUT" to this device has occurred
            IF (ADDR = "10010") THEN
              SONAR_EN <= IO_DATA(7 DOWNTO 0);
            END IF;
            IF (ADDR = "10000") THEN
              ALARM_DIST <= IO_DATA;
            END IF;
            IF (ADDR = "10001") THEN
              INT_EN <= IO_DATA(7 DOWNTO 0);
            END IF;
          END IF;
          
        END IF;

      END PROCESS;
          
END behavior;
  
 



