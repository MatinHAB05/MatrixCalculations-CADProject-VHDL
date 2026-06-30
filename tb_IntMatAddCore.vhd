LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;

ENTITY tb_IntMatAddCore IS
END;

ARCHITECTURE sim OF tb_IntMatAddCore IS

    COMPONENT IntMatAddCore
        PORT (
            Reset, Clock, WriteEnable, BufferSel : IN STD_LOGIC;
            WriteAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            WriteData : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            ReadAddress : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
            ReadEnable : IN STD_LOGIC;
            ReadData : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
            DataReady : OUT STD_LOGIC
        );
    END COMPONENT;

    SIGNAL clk, rst : STD_LOGIC := '0';
    SIGNAL we, bufsel : STD_LOGIC := '0';
    SIGNAL waddr : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL wdata : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL re : STD_LOGIC := '0';
    SIGNAL raddr : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');
    SIGNAL rdata : STD_LOGIC_VECTOR(63 DOWNTO 0);
    SIGNAL ready : STD_LOGIC;

    CONSTANT T : TIME := 20 ns;

BEGIN

    uut : IntMatAddCore
    PORT MAP(
        Reset => rst,
        Clock => clk,
        WriteEnable => we,
        BufferSel => bufsel,
        WriteAddress => waddr,
        WriteData => wdata,
        ReadEnable => re,
        ReadAddress => raddr,
        ReadData => rdata,
        DataReady => ready
    );

    clk <= NOT clk AFTER T/2;

    PROCESS
    BEGIN
        rst <= '1';
        WAIT FOR 5 * T;
        rst <= '0';
        WAIT;
    END PROCESS;

    PROCESS
        FILE FIN_A : text OPEN read_mode IS "A.txt";
        FILE FIN_B : text OPEN read_mode IS "B.txt";
        FILE FIN_EXP : text OPEN read_mode IS "AB_add_testcase.txt"; -- Core expected results matrix file
        FILE FOUT : text OPEN write_mode IS "AB_add.txt";
        FILE FLOG : text OPEN write_mode IS "sim_log_add.txt";

        VARIABLE L : line;
        VARIABLE L_log : line;

        VARIABLE val_exp : INTEGER;
        VARIABLE val_act : INTEGER;
        VARIABLE error_cnt : INTEGER := 0;

        VARIABLE addr : INTEGER;
        VARIABLE valA, valB : INTEGER;
        VARIABLE line_in : LINE;
        VARIABLE line_exp : LINE;
    BEGIN
        we <= '0';
        bufsel <= '0';
        waddr <= (OTHERS => '0');
        wdata <= (OTHERS => '0');
        re <= '0';
        raddr <= (OTHERS => '0');

        WAIT UNTIL rst = '0';
        WAIT UNTIL rising_edge(clk);

        -- Load Matrix A
        bufsel <= '1';
        we <= '1';
        FOR addr IN 0 TO 1023 LOOP
            readline(FIN_A, line_in);
            read(line_in, valA);
            waddr <= STD_LOGIC_VECTOR(to_unsigned(addr, 10));
            wdata <= STD_LOGIC_VECTOR(to_signed(valA, 16));
            WAIT UNTIL rising_edge(clk);
        END LOOP;
        we <= '0';
        WAIT UNTIL rising_edge(clk);

        -- Load Matrix B
        bufsel <= '0';
        we <= '1';
        FOR addr IN 0 TO 1023 LOOP
            readline(FIN_B, line_in);
            read(line_in, valB);
            waddr <= STD_LOGIC_VECTOR(to_unsigned(addr, 10));
            wdata <= STD_LOGIC_VECTOR(to_signed(valB, 16));
            WAIT UNTIL rising_edge(clk);
        END LOOP;
        we <= '0';
        WAIT UNTIL rising_edge(clk);

        -- Wait for Pipelined Hardware Core Execution Loop
        WAIT UNTIL ready = '1';
        WAIT UNTIL rising_edge(clk);

        -- Initialize verification headers
        write(L_log, STRING'("=== MATRIX ADD HARDWARE VERIFICATION LOG ==="));
        writeline(FLOG, L_log);

        re <= '1';

        FOR row IN 0 TO 31 LOOP
            FOR col IN 0 TO 31 LOOP
                addr := row * 32 + col;
                raddr <= STD_LOGIC_VECTOR(to_unsigned(addr, 10));

                -- Memory read latency synchronization delays
                WAIT UNTIL rising_edge(clk);
                WAIT UNTIL rising_edge(clk);
                WAIT FOR 1 ns;

                -- 1. Parse Expected Value
                readline(FIN_EXP, line_exp);
                read(line_exp, val_exp);

                -- 2. Capture Core Output Data Stage
                val_act := to_integer(signed(rdata));

                -- 3. Update Clean Add Matrix Output File
                write(L, STRING'("C("));
                write(L, row);
                write(L, STRING'(","));
                write(L, col);
                write(L, STRING'(") = "));
                write(L, val_act);
                writeline(FOUT, L);

                -- 4. Check Boundary Equivalence and Log Diagnostics
                IF val_act = val_exp THEN
                    write(L_log, STRING'("SUCCESS: C( "));
                    write(L_log, row);
                    write(L_log, STRING'(", "));
                    write(L_log, col);
                    write(L_log, STRING'(" ) matches. Value = "));
                    write(L_log, val_act);
                    writeline(FLOG, L_log);
                ELSE
                    write(L_log, STRING'("FAIL: Mismatch at C( "));
                    write(L_log, row);
                    write(L_log, STRING'(", "));
                    write(L_log, col);
                    write(L_log, STRING'(" ) | Expected: "));
                    write(L_log, val_exp);
                    write(L_log, STRING'(" | Got: "));
                    write(L_log, val_act);
                    writeline(FLOG, L_log);
                    error_cnt := error_cnt + 1;
                END IF;

            END LOOP;
        END LOOP;
        re <= '0';

        -- Finalize Evaluation Metrics
        write(L_log, STRING'("=============================================="));
        writeline(FLOG, L_log);
        IF error_cnt = 0 THEN
            write(L_log, STRING'("FINAL STATUS: PASSED (All Add points match!)"));
            writeline(FLOG, L_log);
            ASSERT false REPORT "Matrix Add Finished Successfully: 0 Errors. Check sim_log_add.txt" SEVERITY failure;
        ELSE
            write(L_log, STRING'("FINAL STATUS: FAILED with "));
            write(L_log, error_cnt);
            write(L_log, STRING'(" errors."));
            writeline(FLOG, L_log);
            ASSERT false REPORT "Matrix Add Completed with " & INTEGER'image(error_cnt) & " ERRORS. Check sim_log_add.txt" SEVERITY failure;
        END IF;

    END PROCESS;

END sim;