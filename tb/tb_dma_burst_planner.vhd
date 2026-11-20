library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.dma_pkg.all;
entity tb_dma_burst_planner is end;
architecture sim of tb_dma_burst_planner is
  signal src, dst, rem_bytes : u32_t := (others=>'0');
  signal beats : natural range 0 to 256;
begin
  dut: entity work.dma_burst_planner port map(src,dst,rem_bytes,beats);
  process
    variable n, want, count : natural := 0;
  begin
    assert command_valid(x"FFFFFFFC",x"00001000",x"00000004") severity failure;
    assert not command_valid(x"FFFFFFFC",x"00001000",x"00000008") severity failure;
    assert not command_valid(x"00001000",x"00001004",x"00000010") severity failure;
    assert command_valid(x"00001000",x"00001010",x"00000010") severity failure;
    -- Sweep every aligned source offset, independently varying destination.
    for so in 0 to 1023 loop
      for k in 0 to 7 loop
        src<=to_unsigned(16#1000#+so*4,32);
        dst<=to_unsigned(16#8000#+((so*17+k*131) mod 1024)*4,32);
        n:=1+((so*7+k*97) mod 600);rem_bytes<=to_unsigned(n*4,32);
        wait for 1 ns;
        want:=n;if want>256 then want:=256;end if;
        if want>1024-so then want:=1024-so;end if;
        if want>1024-((so*17+k*131) mod 1024) then
          want:=1024-((so*17+k*131) mod 1024);end if;
        assert beats=want report "Planner sweep mismatch" severity failure;
        assert beats>=1 and beats<=256 severity failure;count:=count+1;
      end loop;
    end loop;
    report "PLANNER TESTS PASSED cases="&integer'image(count)&" plus command validation" severity note;
    finish;
  end process;
end;
