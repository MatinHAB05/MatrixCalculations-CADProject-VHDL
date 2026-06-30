LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY IntMatAddCore IS
    PORT (
        Reset, Clock, WriteEnable, BufferSel : IN STD_LOGIC;
        WriteAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        WriteData : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        ReadAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        ReadEnable : IN STD_LOGIC;
        ReadData : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
        DataReady : OUT STD_LOGIC
    );
END IntMatAddCore;

ARCHITECTURE rtl OF IntMatAddCore IS

    COMPONENT dpram1024x16
        PORT (
            clka : IN STD_LOGIC;
            wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
            addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            dina : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            clkb : IN STD_LOGIC;
            enb : IN STD_LOGIC;
            addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            doutb : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    END COMPONENT;

    COMPONENT dpram1024x64
        PORT (
            clka : IN STD_LOGIC;
            wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
            addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            dina : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            clkb : IN STD_LOGIC;
            enb : IN STD_LOGIC;
            addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
        );
    END COMPONENT;

    -- Control FSM States
    TYPE stateType IS (stIdle, stWriteBufferA, stWriteBufferB, stComputeAdd, stWaitLast, stComplete);
    SIGNAL presState : stateType := stIdle;

    -- Core Internal Signals
    SIGNAL iWriteEnableA, iWriteEnableB : STD_LOGIC_VECTOR(0 DOWNTO 0);
    SIGNAL iWriteEnableC : STD_LOGIC_VECTOR(0 DOWNTO 0) := (OTHERS => '0');
    SIGNAL iReadDataA, iReadDataB : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL iWriteDataC_s : signed(63 DOWNTO 0) := (OTHERS => '0');

    -- Addressing & Pipelining Counters
    SIGNAL iCount : unsigned(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL ram_enb_q : STD_LOGIC := '0';
    SIGNAL addr_pipe_r0 : unsigned(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL addr_pipe_r1 : unsigned(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL pipe_valid : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";

BEGIN

    ----------------------------------------------------------------
    -- Input Distribution Routing
    ----------------------------------------------------------------
    iWriteEnableA(0) <= WriteEnable AND BufferSel;
    iWriteEnableB(0) <= WriteEnable AND (NOT BufferSel);

    ram_enb_q <= '1' WHEN (presState = stComputeAdd) ELSE
        '0';

    ----------------------------------------------------------------
    -- RAM Instances
    ----------------------------------------------------------------
    RAM_A : dpram1024x16
    PORT MAP(
        clka => Clock,
        wea => iWriteEnableA,
        addra => WriteAddress,
        dina => WriteData,
        clkb => Clock,
        enb => ram_enb_q,
        addrb => STD_LOGIC_VECTOR(iCount),
        doutb => iReadDataA
    );

    RAM_B : dpram1024x16
    PORT MAP(
        clka => Clock,
        wea => iWriteEnableB,
        addra => WriteAddress,
        dina => WriteData,
        clkb => Clock,
        enb => ram_enb_q,
        addrb => STD_LOGIC_VECTOR(iCount),
        doutb => iReadDataB
    );

    RAM_C : dpram1024x64
    PORT MAP(
        clka => Clock,
        wea => iWriteEnableC,
        addra => STD_LOGIC_VECTOR(addr_pipe_r1),
        dina => STD_LOGIC_VECTOR(iWriteDataC_s),
        clkb => Clock,
        enb => ReadEnable,
        addrb => ReadAddress,
        doutb => ReadData
    );

    ----------------------------------------------------------------
    -- Single-Process Synchronous FSM & Datapath Controller
    ----------------------------------------------------------------
    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF Reset = '1' THEN
                presState <= stIdle;
                iCount <= (OTHERS => '0');
                pipe_valid <= "00";
                iWriteEnableC(0) <= '0';
                iWriteDataC_s <= (OTHERS => '0');
                DataReady <= '0';
            ELSE
                -- Establish solid synthesis defaults to avoid latches
                iWriteEnableC(0) <= '0';
                DataReady <= '0';

                CASE presState IS
                    WHEN stIdle =>
                        iCount <= (OTHERS => '0');
                        pipe_valid <= "00";
                        IF (WriteEnable = '1' AND BufferSel = '1') THEN
                            presState <= stWriteBufferA;
                        END IF;

                    WHEN stWriteBufferA =>
                        IF WriteEnable = '0' THEN
                            presState <= stWriteBufferB;
                        END IF;

                    WHEN stWriteBufferB =>
                        IF WriteEnable = '0' THEN
                            iCount <= (OTHERS => '0');
                            pipe_valid <= "00";
                            presState <= stComputeAdd;
                        END IF;

                    WHEN stComputeAdd =>
                        -- Pipeline Address Progression Tracking
                        addr_pipe_r0 <= iCount;
                        addr_pipe_r1 <= addr_pipe_r0;
                        pipe_valid <= pipe_valid(0) & '1';

                        -- Perform add when BRAM data registers are valid (1-cycle latency)
                        IF pipe_valid(0) = '1' THEN
                            iWriteEnableC(0) <= '1';
                            iWriteDataC_s <= resize(signed(iReadDataA), 64) + resize(signed(iReadDataB), 64);
                        END IF;

                        -- Loop bounds checking
                        IF iCount = 1023 THEN
                            presState <= stWaitLast;
                        ELSE
                            iCount <= iCount + 1;
                        END IF;

                    WHEN stWaitLast =>
                        -- Flush trailing calculation elements through pipeline stages
                        addr_pipe_r1 <= addr_pipe_r0;
                        pipe_valid <= pipe_valid(0) & '0';

                        IF pipe_valid(0) = '1' THEN
                            iWriteEnableC(0) <= '1';
                            iWriteDataC_s <= resize(signed(iReadDataA), 64) + resize(signed(iReadDataB), 64);
                        END IF;
                        presState <= stComplete;

                    WHEN stComplete =>
                        DataReady <= '1'; -- Generates a precise 1-clock pulse for the testbench
                        presState <= stIdle;

                    WHEN OTHERS =>
                        presState <= stIdle;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END rtl;