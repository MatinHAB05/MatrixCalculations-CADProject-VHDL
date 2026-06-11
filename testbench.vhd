LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;

ENTITY tb_IntMatMulCore IS
END;

ARCHITECTURE sim OF tb_IntMatMulCore IS

  COMPONENT IntMatMulCore
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

  uut : IntMatMulCore
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
    FILE FIN_A   : text OPEN read_mode IS "A.txt";
    FILE FIN_B   : text OPEN read_mode IS "B.txt";
    FILE FOUT    : text OPEN write_mode IS "AB.txt";
    FILE FIN_EXP : text OPEN read_mode IS "AB_testcase.txt";
    FILE FLOG    : text OPEN write_mode IS "sim_log.txt"; -- New log file

    VARIABLE L     : line;
    VARIABLE L_log : line; -- New separate line buffer for logs
    
    VARIABLE val_exp   : INTEGER;
    VARIABLE val_act   : INTEGER;
    VARIABLE error_cnt : INTEGER := 0;

    VARIABLE addr    : INTEGER;
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

    -- Wait for Hardware Core to Finish Multiplication
    WAIT UNTIL ready = '1';
    WAIT UNTIL rising_edge(clk);

    -- Write Log File Header
    write(L_log, STRING'("=== MATRIX MULTIPLICATION VERIFICATION LOG ==="));
    writeline(FLOG, L_log);

    -- Read Results, Log to File, and Verify
    re <= '1';
    
    -- NOTE: If your "AB_testcase.txt" has all 1024 integers on ONE single line 
    -- instead of 1 integer per line, uncomment the next line:
    -- readline(FIN_EXP, line_exp);

    FOR row IN 0 TO 31 LOOP
      FOR col IN 0 TO 31 LOOP
        addr := row * 32 + col;
        raddr <= STD_LOGIC_VECTOR(to_unsigned(addr, 10));
        
        -- Wait for memory read latency
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        WAIT FOR 1 ns; 
        
        -- 1. Read Expected Value from testcase file
        readline(FIN_EXP, line_exp); 
        read(line_exp, val_exp);
        
        -- 2. Grab Actual Value from design output
        val_act := to_integer(signed(rdata));

        -- 3. Write to the clean AB.txt output matrix file
        write(L, STRING'("C("));
        write(L, row);
        write(L, STRING'(","));
        write(L, col);
        write(L, STRING'(") = "));
        write(L, val_act);
        writeline(FOUT, L);
        
        -- 4. Compare and Write detailed logs to sim_log.txt
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
    
    -- Write Final Summary into the Log File
    write(L_log, STRING'("=============================================="));
    writeline(FLOG, L_log);
    IF error_cnt = 0 THEN
      write(L_log, STRING'("FINAL STATUS: PASSED (All 1024 points match!)"));
      writeline(FLOG, L_log);
      
      -- Keep a single clean assertion in the console just to stop the simulation gracefully
      ASSERT false REPORT "Simulation Finished Successfully: 0 Errors. Check sim_log.txt for full matrix dump." SEVERITY failure;
    ELSE
      write(L_log, STRING'("FINAL STATUS: FAILED with "));
      write(L_log, error_cnt);
      write(L_log, STRING'(" errors."));
      writeline(FLOG, L_log);
      
      ASSERT false REPORT "Simulation Completed with " & INTEGER'image(error_cnt) & " ERRORS. Check sim_log.txt to debug mismatches." SEVERITY failure;
    END IF;

  END PROCESS;

END sim;