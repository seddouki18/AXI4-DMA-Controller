-- Store-and-forward burst buffer. Not a generic streaming FIFO.
-- Synchronous read; output holds when rd_en=0. No RAM-array reset.
library ieee;
use ieee.std_logic_1164.all;
use work.dma_pkg.all;
entity dma_burst_buffer is
  generic (DEPTH : positive := 256);
  port (aclk : in std_logic;
        wr_en, rd_en : in std_logic;
        wr_addr, rd_addr : in natural range 0 to DEPTH-1;
        wr_data : in word_t;
        rd_data : out word_t);
end;
architecture rtl of dma_burst_buffer is
  type ram_t is array(0 to DEPTH-1) of word_t;
  signal ram : ram_t;
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
begin
  process(aclk)
  begin
    if rising_edge(aclk) then
      if wr_en='1' then ram(wr_addr)<=wr_data; end if;
      if rd_en='1' then rd_data<=ram(rd_addr); end if;
    end if;
  end process;
end;
