library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dma_pkg.all;

entity dma_burst_planner is
  generic (MAX_BURST_BEATS : positive := 256);
  port (src, dst, remaining_bytes : in u32_t;
        beats : out natural range 0 to 256);
end;
architecture rtl of dma_burst_planner is
begin
  assert MAX_BURST_BEATS<=256 report "MAX_BURST_BEATS must be 1..256" severity failure;
  process(all)
    variable n, sr, dr : natural;
  begin
    n:=to_integer(shift_right(remaining_bytes,2));
    sr:=(4096-to_integer(src(11 downto 0)))/4;
    dr:=(4096-to_integer(dst(11 downto 0)))/4;
    if n>MAX_BURST_BEATS then n:=MAX_BURST_BEATS; end if;
    if n>sr then n:=sr; end if;
    if n>dr then n:=dr; end if;
    beats<=n;
  end process;
end;
