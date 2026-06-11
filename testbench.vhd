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
    VARIABLE L : line;
    FILE FIN_A : text OPEN read_mode IS "A.txt";
    FILE FIN_B : text OPEN read_mode IS "B.txt";
    FILE FOUT : text OPEN write_mode IS "AB.txt";
    VARIABLE addr : INTEGER;
    VARIABLE valA, valB : INTEGER;
    VARIABLE line_in : LINE;
  BEGIN
    we <= '0';
    bufsel <= '0';
    waddr <= (OTHERS => '0');
    wdata <= (OTHERS => '0');
    re <= '0';
    raddr <= (OTHERS => '0');

    WAIT UNTIL rst = '0';
    WAIT UNTIL rising_edge(clk);

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

    WAIT UNTIL ready = '1';
    WAIT UNTIL rising_edge(clk);

    re <= '1';
    FOR row IN 0 TO 31 LOOP
      FOR col IN 0 TO 31 LOOP
        addr := row * 32 + col;
        raddr <= STD_LOGIC_VECTOR(to_unsigned(addr, 10));
        WAIT UNTIL rising_edge(clk);
        WAIT UNTIL rising_edge(clk);
        WAIT FOR 1 ns;
        write(L, STRING'("C("));
        write(L, row);
        write(L, STRING'(","));
        write(L, col);
        write(L, STRING'(") = "));
        write(L, to_integer(signed(rdata)));
        writeline(FOUT, L);
      END LOOP;
    END LOOP;

    re <= '0';
    ASSERT false REPORT "Simulation Finished Successfully" SEVERITY failure;
  END PROCESS;

END sim;