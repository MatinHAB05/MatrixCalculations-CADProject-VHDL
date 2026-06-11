LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY IntMatMulCore_Parallel IS
    PORT (
        Reset, Clock, WriteEnable, BufferSel : IN STD_LOGIC;
        WriteAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        WriteData : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        ReadAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        ReadEnable : IN STD_LOGIC;
        ReadData : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
        DataReady : OUT STD_LOGIC
    );
END IntMatMulCore_Parallel;

ARCHITECTURE rtl OF IntMatMulCore_Parallel IS

    -- We retain the 64-bit Dual-Port RAM for output compatibility
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

    -- State Machine States
    TYPE stateType IS (stIdle, stWriteBufferA, stWriteBufferB, stCompute, stComplete);
    SIGNAL presState, nextState : stateType := stIdle;

    -- Internal Register Arrays for fully parallel matrix access
    TYPE matrix_32x32 IS ARRAY (0 TO 31, 0 TO 31) OF signed(15 DOWNTO 0);
    SIGNAL mat_A : matrix_32x32 := (OTHERS => (OTHERS => (OTHERS => '0')));
    SIGNAL mat_B : matrix_32x32 := (OTHERS => (OTHERS => (OTHERS => '0')));

    -- Control and Address Signals
    SIGNAL iCountEnable : STD_LOGIC := '0';
    SIGNAL iCountReset : STD_LOGIC := '0';
    SIGNAL iCount : unsigned(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL iWriteEnableC : STD_LOGIC_VECTOR(0 DOWNTO 0) := (OTHERS => '0');
    SIGNAL iWriteDataC_s : signed(63 DOWNTO 0) := (OTHERS => '0');

    -- Write address decoding signals
    SIGNAL w_row : INTEGER RANGE 0 TO 31;
    SIGNAL w_col : INTEGER RANGE 0 TO 31;

BEGIN

    ----------------------------------------------------------------
    -- Sequential Data Loading into Register Arrays
    ----------------------------------------------------------------
    w_row <= to_integer(unsigned(WriteAddress(9 DOWNTO 5)));
    w_col <= to_integer(unsigned(WriteAddress(4 DOWNTO 0)));

    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF WriteEnable = '1' THEN
                IF BufferSel = '1' THEN
                    mat_A(w_row, w_col) <= signed(WriteData);
                ELSE
                    mat_B(w_row, w_col) <= signed(WriteData);
                END IF;
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- Fully Parallel Combinational Dot-Product Engine
    ----------------------------------------------------------------
    PROCESS (iCount, mat_A, mat_B)
        VARIABLE sum : signed(63 DOWNTO 0);
        VARIABLE r : INTEGER RANGE 0 TO 31;
        VARIABLE c : INTEGER RANGE 0 TO 31;
    BEGIN
        -- Decode current target coordinates from the linear 10-bit address counter
        r := to_integer(iCount(9 DOWNTO 5));
        c := to_integer(iCount(4 DOWNTO 0));

        -- Fully unrolled parallel multiplication and additions
        sum := (OTHERS => '0');
        FOR k IN 0 TO 31 LOOP
            sum := sum + (resize(mat_A(r, k), 32) * resize(mat_B(k, c), 32));
        END LOOP;

        iWriteDataC_s <= sum;
    END PROCESS;

    ----------------------------------------------------------------
    -- RAM_C: Output Storage
    ----------------------------------------------------------------
    RAM_C : dpram1024x64
    PORT MAP(
        clka => Clock,
        wea => iWriteEnableC,
        addra => STD_LOGIC_VECTOR(iCount),
        dina => STD_LOGIC_VECTOR(iWriteDataC_s),

        clkb => Clock,
        enb => ReadEnable,
        addrb => ReadAddress,
        doutb => ReadData
    );

    ----------------------------------------------------------------
    -- FSM Clocked Counter and State Registers
    ----------------------------------------------------------------
    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF Reset = '1' THEN
                presState <= stIdle;
                iCount <= (OTHERS => '0');
            ELSE
                presState <= nextState;
                IF iCountReset = '1' THEN
                    iCount <= (OTHERS => '0');
                ELSIF iCountEnable = '1' THEN
                    iCount <= iCount + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- Finite State Machine Logic
    ----------------------------------------------------------------
    PROCESS (presState, WriteEnable, BufferSel, iCount)
    BEGIN
        iCountEnable <= '0';
        iCountReset <= '0';
        iWriteEnableC(0) <= '0';
        DataReady <= '0';
        nextState <= presState;

        CASE presState IS
            WHEN stIdle =>
                iCountReset <= '1';
                IF (WriteEnable = '1' AND BufferSel = '1') THEN
                    nextState <= stWriteBufferA;
                END IF;

            WHEN stWriteBufferA =>
                IF (WriteEnable = '0') THEN
                    nextState <= stWriteBufferB;
                END IF;

            WHEN stWriteBufferB =>
                IF (WriteEnable = '0') THEN
                    iCountReset <= '1';
                    nextState <= stCompute; -- Move directly to the parallel computation state
                END IF;

            WHEN stCompute =>
                iWriteEnableC(0) <= '1'; -- Streams data straight to RAM_C
                iCountEnable <= '1';
                IF iCount = 1023 THEN
                    nextState <= stComplete;
                END IF;

            WHEN stComplete =>
                DataReady <= '1';
                nextState <= stIdle;

            WHEN OTHERS =>
                nextState <= stIdle;
        END CASE;
    END PROCESS;

END rtl;