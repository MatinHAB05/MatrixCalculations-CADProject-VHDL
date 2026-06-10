LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY IntMatMulCore IS
    PORT (
        Reset, Clock, WriteEnable, BufferSel : IN STD_LOGIC;
        WriteAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        WriteData : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        ReadAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        ReadEnable : IN STD_LOGIC;
        ReadData : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
        DataReady : OUT STD_LOGIC
    );
END IntMatMulCore;

ARCHITECTURE rtl OF IntMatMulCore IS

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

    TYPE stateType IS (
        stIdle, stWriteBufferA, stWriteBufferB,
        stReadBufferAB, stWaitAcc, stWriteBufferC, stComplete
    );
    SIGNAL presState, nextState : stateType := stIdle;

    SIGNAL iReadEnableAB : STD_LOGIC := '0';
    SIGNAL iCountEnable : STD_LOGIC := '0';
    SIGNAL iCountEnableAB : STD_LOGIC := '0';
    SIGNAL iCountReset : STD_LOGIC := '0';
    SIGNAL iCountResetAB : STD_LOGIC := '0';

    SIGNAL iWriteEnableA, iWriteEnableB, iWriteEnableC :
    STD_LOGIC_VECTOR(0 DOWNTO 0);

    SIGNAL iReadDataA, iReadDataB : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL iWriteDataC_s : signed(63 DOWNTO 0) := (OTHERS => '0');

    SIGNAL iCount : unsigned(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL iCountA : unsigned(4 DOWNTO 0) := (OTHERS => '0');

    SIGNAL iRowA : unsigned(9 DOWNTO 0);
    SIGNAL iColB : unsigned(19 DOWNTO 0);
    SIGNAL iReadAddrA : unsigned(9 DOWNTO 0);
    SIGNAL iReadAddrB : unsigned(9 DOWNTO 0);

    SIGNAL ram_enb_q, ram_enb_d1 : STD_LOGIC := '0';
    SIGNAL ram_addrA_q, ram_addrB_q : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');

    SIGNAL rd_valid_q : STD_LOGIC := '0';
    SIGNAL rdA_q, rdB_q : signed(15 DOWNTO 0) := (OTHERS => '0');

    SIGNAL acc_cnt : unsigned(5 DOWNTO 0) := (OTHERS => '0'); -- count up to 32

BEGIN

    ----------------------------------------------------------------
    -- Write enables for A and B RAMs
    ----------------------------------------------------------------
    iWriteEnableA(0) <= WriteEnable AND BufferSel;
    iWriteEnableB(0) <= WriteEnable AND (NOT BufferSel);

    ----------------------------------------------------------------
    -- Read address regs
    ----------------------------------------------------------------
    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF (Reset = '1') OR (iCountResetAB = '1') THEN
                ram_enb_q <= '0';
                ram_addrA_q <= (OTHERS => '0');
                ram_addrB_q <= (OTHERS => '0');
            ELSE
                ram_enb_q <= iReadEnableAB;
                ram_addrA_q <= STD_LOGIC_VECTOR(iReadAddrA);
                ram_addrB_q <= STD_LOGIC_VECTOR(iReadAddrB);
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- RAM instances
    ----------------------------------------------------------------
    RAM_A : dpram1024x16
    PORT MAP(
        clka => Clock,
        wea => iWriteEnableA,
        addra => WriteAddress,
        dina => WriteData,

        clkb => Clock,
        enb => ram_enb_q,
        addrb => ram_addrA_q,
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
        addrb => ram_addrB_q,
        doutb => iReadDataB
    );

    ----------------------------------------------------------------
    -- Registered outputs (with extra delay stage)
    ----------------------------------------------------------------
    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF (Reset = '1') OR (iCountResetAB = '1') THEN
                ram_enb_d1 <= '0';
                rd_valid_q <= '0';
                rdA_q <= (OTHERS => '0');
                rdB_q <= (OTHERS => '0');
            ELSE
                ram_enb_d1 <= ram_enb_q;
                rd_valid_q <= ram_enb_d1;
                IF ram_enb_d1 = '1' THEN
                    rdA_q <= signed(iReadDataA);
                    rdB_q <= signed(iReadDataB);
                END IF;
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- RAM_C: result memory
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
    -- Accumulator
    ----------------------------------------------------------------
    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF (Reset = '1') OR (iCountResetAB = '1') THEN
                iWriteDataC_s <= (OTHERS => '0');
                acc_cnt <= (OTHERS => '0');
            ELSIF (iWriteEnableC(0) = '1') THEN
                iWriteDataC_s <= (OTHERS => '0');
                acc_cnt <= (OTHERS => '0');
            ELSIF (rd_valid_q = '1') THEN
                iWriteDataC_s <= iWriteDataC_s +
                    (resize(rdA_q, 32) * resize(rdB_q, 32));
                acc_cnt <= acc_cnt + 1;
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- Counters and state reg
    ----------------------------------------------------------------
    PROCESS (Clock)
    BEGIN
        IF rising_edge(Clock) THEN
            IF Reset = '1' THEN
                presState <= stIdle;
                iCount <= (OTHERS => '0');
                iCountA <= (OTHERS => '0');
            ELSE
                presState <= nextState;
                IF iCountReset = '1' THEN
                    iCount <= (OTHERS => '0');
                ELSIF iCountEnable = '1' THEN
                    iCount <= iCount + 1;
                END IF;
                IF iCountResetAB = '1' THEN
                    iCountA <= (OTHERS => '0');
                ELSIF iCountEnableAB = '1' THEN
                    iCountA <= iCountA + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- Address calculation
    ----------------------------------------------------------------
    iRowA <= iCount SRL 5;
    iColB <= ("0000000000" & iCount) - (iRowA * 32);
    iReadAddrA <= (iRowA SLL 5) + ("00000" & iCountA);
    iReadAddrB <= (("00000" & iCountA) SLL 5) + iColB(9 DOWNTO 0);

    ----------------------------------------------------------------
    -- FSM
    ----------------------------------------------------------------
    PROCESS (presState, WriteEnable, BufferSel, iCount, iCountA, acc_cnt)
    BEGIN
        iReadEnableAB <= '0';
        iCountEnable <= '0';
        iCountEnableAB <= '0';
        iCountReset <= '0';
        iCountResetAB <= '0';
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
                    iCountResetAB <= '1';
                    nextState <= stReadBufferAB;
                END IF;

            WHEN stReadBufferAB =>
                iReadEnableAB <= '1';
                IF iCountA = "11111" THEN
                    nextState <= stWaitAcc; -- wait for pipeline to finish
                ELSE
                    iCountEnableAB <= '1';
                END IF;

            WHEN stWaitAcc =>
                iReadEnableAB <= '0';
                IF acc_cnt = 32 THEN
                    nextState <= stWriteBufferC;
                ELSE
                    nextState <= stWaitAcc;
                END IF;

            WHEN stWriteBufferC =>
                iWriteEnableC(0) <= '1';
                iCountResetAB <= '1';
                iCountEnable <= '1';
                IF iCount = x"3FF" THEN
                    nextState <= stComplete;
                ELSE
                    nextState <= stReadBufferAB;
                END IF;

            WHEN stComplete =>
                DataReady <= '1';
                nextState <= stIdle;

            WHEN OTHERS =>
                nextState <= stIdle;
        END CASE;
    END PROCESS;

END rtl;