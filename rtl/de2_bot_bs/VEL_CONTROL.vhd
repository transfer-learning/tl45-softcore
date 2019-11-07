-- VEL_CONTROL.VHD
-- Based on the velocity controller by Team Flying Robots, Spring 2011
-- Subsequent mods by T. Collins and K. Johnson, including addition of closed-loop control

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!

										LIBRARY IEEE;
										LIBRARY LPM;

										USE IEEE.STD_LOGIC_1164.ALL;
										USE IEEE.STD_LOGIC_SIGNED.ALL;
										USE LPM.LPM_COMPONENTS.ALL;
										USE IEEE.NUMERIC_STD.ALL;

										ENTITY VEL_CONTROL IS
										PORT(PWM_CLK,    -- must be a 100 MHz clock signal to get ~25kHz phase frequency
											RESETN,
											CS,       -- chip select, asserted when new speed is input
											IO_WRITE : IN STD_LOGIC;  -- asserted when being written to
											IO_DATA  : IN STD_LOGIC_VECTOR(15 DOWNTO 0);  -- commanded speed from SCOMP (only lower 8 bits used)
											POSITION : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- actual position of motor, for closed loop control
											CTRL_CLK : IN STD_LOGIC;  -- clock that determines control loop sampling rate (64 Hz)
											ENABLE   : IN STD_LOGIC;  -- prevents running control while motors are disabled
											SOFT_HALT : IN STD_LOGIC; -- resets desired velocity to 0
											MOTOR_PHASE : OUT STD_LOGIC; -- polarity of motor output
											MOTOR_EN    : OUT STD_LOGIC;
											I_WARN      : OUT STD_LOGIC; -- integrator warning
											WATCHDOG    : OUT STD_LOGIC;  -- safety feature
											I_VAL       : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)  -- integrator level
										);
										END VEL_CONTROL;

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!

										ARCHITECTURE a OF VEL_CONTROL IS
											SIGNAL COUNT  : STD_LOGIC_VECTOR(11 DOWNTO 0); -- counter output
											SIGNAL IO_DATA_INT : STD_LOGIC_VECTOR(15 DOWNTO 0); -- internal speed value
											SIGNAL POSITION_INT : STD_LOGIC_VECTOR(31 DOWNTO 0); -- internal speed value
											SIGNAL LATCH : STD_LOGIC;
											SIGNAL PWM_CMD : STD_LOGIC_VECTOR(11 DOWNTO 0);
											SIGNAL MOTOR_PHASE_INT : STD_LOGIC;
											SIGNAL FIRST_PASS : STD_LOGIC;
											SIGNAL SH_ACK, SH_REQ : STD_LOGIC;
											SIGNAL I_WARN_INT : STD_LOGIC;
											SIGNAL WATCHDOG_INT : STD_LOGIC_VECTOR(7 DOWNTO 0);

										BEGIN
											-- Use LPM counter megafunction to make a divide-by-4096 counter
											counter: LPM_COUNTER
											GENERIC MAP(
												lpm_width => 12,
												lpm_direction => "UP"
											)
											PORT MAP(
												clock => PWM_CLK,
												q => COUNT
											);

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!

											-- Use LPM compare megafunction to produce desired duty cycle
											compare: LPM_COMPARE
											GENERIC MAP(
												lpm_width => 12,
												lpm_representation => "UNSIGNED"
											)
											PORT MAP(
												dataa => COUNT,
												datab =>  PWM_CMD(11 DOWNTO 0),
												ageb => MOTOR_PHASE_INT
											);

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!

											LATCH <= CS AND IO_WRITE; -- part of IO fix (below) -- TRC
											I_WARN <= I_WARN_INT;   -- output integrator warning
											
											PROCESS (RESETN, LATCH, SOFT_HALT)
												BEGIN
												-- set speed to 0 after a reset
												IF RESETN = '0' THEN
													IO_DATA_INT <= x"0000";
													MOTOR_EN <= '0';
												ELSIF SOFT_HALT = '0' THEN
													IO_DATA_INT <= x"0000";
												-- keep the IO data (velocity command) from SCOMP in an internal register IO_DATA_INT
												ELSIF RISING_EDGE(LATCH) THEN   -- fixed unreliable OUT operation - TRC
												-- make sure data is within correct range
													IF ((IO_DATA(15 DOWNTO 9) = "000000000") 
													  OR ((IO_DATA(15 DOWNTO 9) = "111111111") AND (IO_DATA(8 DOWNTO 0) /= "000000000"))) THEN
														IO_DATA_INT <= IO_DATA(15 DOWNTO 0);
													ELSE 
														IO_DATA_INT <= x"0000";  -- behavior for out of range (treat as zero)
													END IF;
													MOTOR_EN <= '1';
												END IF;
											END PROCESS;

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!

											-- process to help handle software position resets.
											PROCESS (SOFT_HALT, SH_ACK)
											BEGIN
												IF SH_ACK = '1' THEN
													SH_REQ <= '0';
												ELSIF RISING_EDGE(SOFT_HALT) THEN
													SH_REQ <= '1';
												END IF;
											END PROCESS;
											
											PROCESS BEGIN -- sample the position
												WAIT UNTIL FALLING_EDGE(CTRL_CLK);
												POSITION_INT <= POSITION;
											END PROCESS;
												
											-- added closed loop control so that motor will try to achieve exactly the value commanded - TRC
											PROCESS (CTRL_CLK, RESETN, ENABLE)
												VARIABLE IN_VEL, CMD_VEL, VEL_ERR, CUM_VEL_ERR: INTEGER := 0;
												VARIABLE LAST_CMD_VEL, LAST_VEL: INTEGER := 0;
												VARIABLE CURR_VEL, CURR_POS, LAST_POS: INTEGER := 0;
												VARIABLE DERR: INTEGER := 0;
												CONSTANT ELIMIT: INTEGER := 500;       -- prevents excessive control
												CONSTANT ILIMIT: INTEGER := 32767; -- Prevents excessive integral
												CONSTANT LIMIT: INTEGER := 6000000;     -- prevents excessive speed
												CONSTANT DEADZONE: INTEGER := 1600000;
												CONSTANT MAX_ACC: INTEGER := 128;        -- limit overall acceleration to 1024(tick/s)/s
												VARIABLE MOTOR_CMD: INTEGER := 0;
												VARIABLE PROP_CTRL, INT_CTRL, DERIV_CTRL, FF_CTRL: INTEGER := 0;

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!
												CONSTANT KP: INTEGER := 2500;--3000;
												CONSTANT KI: INTEGER := 52;
												CONSTANT KD: INTEGER := 13; 
												CONSTANT KF: INTEGER := 1600;

												BEGIN
												
												I_VAL <= STD_LOGIC_VECTOR(TO_SIGNED((CUM_VEL_ERR), I_VAL'LENGTH));
											
												IF (RESETN = '0') OR (ENABLE = '0') THEN
													MOTOR_CMD := 0; -- at startup, motor should be stopped
													CUM_VEL_ERR := 0;
													LAST_VEL := 0;
													CURR_VEL := 0;
													DERR := 0;
													CURR_POS := 0;
													LAST_POS := 0;
													IN_VEL := 0;
													CMD_VEL := 0;
													I_WARN_INT <= '0';
													FIRST_PASS <= '1';
													SH_ACK <= '0';
													CUM_VEL_ERR := 0;
												ELSIF RISING_EDGE(CTRL_CLK) THEN   -- determine a control signal at each control cycle
													IF (FIRST_PASS = '1') OR (SH_REQ = '1') THEN -- avoid jumps when first enabled
														CURR_POS := TO_INTEGER(SIGNED(POSITION_INT));
														LAST_POS := TO_INTEGER(SIGNED(POSITION_INT));
														FIRST_PASS <= '0';
														SH_ACK <= '1';
													ELSE
													
													SH_ACK <= '0';
													
													-- update the command velocity
													-- user control value units are 128ticks/s; control clock here is 32Hz; so there's a factor of 4
													IN_VEL := TO_INTEGER(SIGNED(IO_DATA_INT(9 DOWNTO 0)&"00")); -- match magnitudes
													-- Control acceleration
													IF WATCHDOG_INT = "00000000" THEN
													-- If soft watchdog times out, decelerate to 0
														IF CMD_VEL > MAX_ACC THEN
															CMD_VEL := CMD_VEL - MAX_ACC;
														ELSIF CMD_VEL < -MAX_ACC THEN
															CMD_VEL := CMD_VEL + MAX_ACC;
														ELSE
															CMD_VEL := 0;
														END IF;
													ELSE -- if watchdog active, accelerate normally
														IF IN_VEL - CMD_VEL > MAX_ACC THEN
															CMD_VEL := CMD_VEL + MAX_ACC;
														ELSIF IN_VEL - CMD_VEL < -MAX_ACC THEN
															CMD_VEL := CMD_VEL - MAX_ACC;
														ELSE
															CMD_VEL := IN_VEL;
														END IF;
													END IF;
													
													-- check current error based on previous interval
													CURR_POS := TO_INTEGER(SIGNED(POSITION_INT));
													LAST_VEL := CURR_VEL;
													CURR_VEL := CURR_POS - LAST_POS;
													LAST_POS := CURR_POS;
													VEL_ERR := CMD_VEL - CURR_VEL;  -- commanded vel should equal measured vel
													
													-- derivative term is calculated as "derivative on measurement" to avoid kick.
													DERR := LAST_VEL - CURR_VEL;
													DERIV_CTRL := DERR * KD;-- The "D" component
													
													PROP_CTRL := VEL_ERR * KP;   -- The "P" component of the PID controller
													
													-- Limit the error going in to the integrator
													IF (VEL_ERR > ELIMIT) THEN
														VEL_ERR := ELIMIT;
													ELSIF (VEL_ERR < -ELIMIT) THEN
														VEL_ERR := -ELIMIT;
													END IF;
													IF (CURR_VEL = 0) AND (CMD_VEL = 0) THEN
														CUM_VEL_ERR := 0; -- when stopped, clear the integrator
													ELSIF (CUM_VEL_ERR + VEL_ERR) > ILIMIT THEN
													-- limit the I term, and set the stall warning if I is too large.
														CUM_VEL_ERR := ILIMIT;  -- limit integrator when motor is stopped or stalled
														I_WARN_INT <= '1';
													ELSIF (CUM_VEL_ERR + VEL_ERR) < -ILIMIT THEN
														CUM_VEL_ERR := -ILIMIT;  -- limit integrator when motor is stopped or stalled			
														I_WARN_INT <= '1';
													ELSE
														CUM_VEL_ERR := CUM_VEL_ERR + VEL_ERR;   -- perform the integration, if not near setpoint
														I_WARN_INT <= '0';
													END IF;
													INT_CTRL  := CUM_VEL_ERR * KI;   -- The "I" component
													IF CMD_VEL > 0 THEN
														FF_CTRL := CMD_VEL * KF + DEADZONE;   -- FeedForward component...
													ELSIF CMD_VEL < 0 THEN
														FF_CTRL := CMD_VEL * KF - DEADZONE;   -- FeedForward component...
													ELSE
														FF_CTRL := 0;
													END IF;
													MOTOR_CMD := (FF_CTRL) + (PROP_CTRL) + (INT_CTRL) + (DERIV_CTRL);
													-- Cap the motor command at its safe limit
													IF (MOTOR_CMD > LIMIT) THEN
														MOTOR_CMD := LIMIT;
													ELSIF (MOTOR_CMD < -LIMIT) THEN
														MOTOR_CMD := -LIMIT;
													END IF;
													END IF;
												END IF;
												
												PWM_CMD <= STD_LOGIC_VECTOR(TO_SIGNED((MOTOR_CMD/8192)+2048, PWM_CMD'LENGTH));

											END PROCESS;

											-- copy internal signal to external
											PROCESS BEGIN
											WAIT UNTIL RISING_EDGE(PWM_CLK);
												MOTOR_PHASE <= MOTOR_PHASE_INT;
											END PROCESS;
											
											-- soft watchdog to control hard watchdog
											PROCESS (RESETN, LATCH, CTRL_CLK)
												BEGIN
												IF (RESETN = '0') THEN
													WATCHDOG_INT <= "00000000";
												ELSIF (LATCH = '1') THEN -- async set when written
													WATCHDOG_INT <= "00010000"; -- half a second timeout
												ELSIF RISING_EDGE(CTRL_CLK) THEN
													IF WATCHDOG_INT /= "00000000" THEN
														WATCHDOG_INT <= WATCHDOG_INT - 1;
													END IF;
												END IF;
											END PROCESS;
											-- toggle the hard watchdog
											WITH WATCHDOG_INT SELECT WATCHDOG <=
												'0' WHEN "00000000",
												CTRL_CLK WHEN OTHERS;
													
													
										END a;

-- DO NOT ALTER ANYTHING IN THIS FILE.
-- IT IS EASY TO CREATE POSITIVE FEEDBACK,
-- INSTABILITY, AND RUNAWAY ROBOTS!!

