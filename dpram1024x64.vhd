LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY dpram1024x64 IS
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
END ENTITY;

ARCHITECTURE behavioral OF dpram1024x64 IS
  TYPE ram_type IS ARRAY (0 TO 1023) OF STD_LOGIC_VECTOR(63 DOWNTO 0);
  SIGNAL ram : ram_type := (OTHERS => (OTHERS => '0'));
BEGIN

  -- WRITE PORT
  PROCESS (clka)
  BEGIN
    IF rising_edge(clka) THEN
      IF wea(0) = '1' THEN
        ram(to_integer(unsigned(addra))) <= dina;
      END IF;
    END IF;
  END PROCESS;

  -- READ PORT
  PROCESS (clkb)
  BEGIN
    IF rising_edge(clkb) THEN
      IF enb = '1' THEN
        doutb <= ram(to_integer(unsigned(addrb)));
      END IF;
    END IF;
  END PROCESS;

END ARCHITECTURE;