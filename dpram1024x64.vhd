library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram1024x64 is
  port (
    clka  : in  std_logic;
    wea   : in  std_logic_vector(0 downto 0);
    addra : in  std_logic_vector(9 downto 0);
    dina  : in  std_logic_vector(63 downto 0);

    clkb  : in  std_logic;
    enb   : in  std_logic;
    addrb : in  std_logic_vector(9 downto 0);
    doutb : out std_logic_vector(63 downto 0)
  );
end entity;

architecture behavioral of dpram1024x64 is
  type ram_type is array (0 to 1023) of std_logic_vector(63 downto 0);
  signal ram : ram_type := (others => (others => '0'));
begin

  -- WRITE PORT
  process (clka)
  begin
    if rising_edge(clka) then
      if wea(0) = '1' then
        ram(to_integer(unsigned(addra))) <= dina;
      end if;
    end if;
  end process;

  -- READ PORT
  process (clkb)
  begin
    if rising_edge(clkb) then
      if enb = '1' then
        doutb <= ram(to_integer(unsigned(addrb)));
      end if;
    end if;
  end process;

end architecture;
