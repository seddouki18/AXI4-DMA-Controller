-- DMA engine, V1: store-and-forward, one burst in flight at a time.
-- FSM: IDLE -> PLAN -> AR_REQ -> R_DATA -> AW_REQ -> PREFETCH -> W_DATA
--      -> B_RESP -> PLAN (next burst) or IDLE (done / response error).
-- A protocol violation (RLAST, RID, BID) goes to FAULT; only a
-- coordinated external reset can recover.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dma_pkg.all;

entity dma_engine is
  generic (MAX_BURST_BEATS : positive := 256);
  port (aclk, aresetn : in std_logic;
        start, soft_reset : in std_logic;
        cmd_src, cmd_dst, cmd_len : in word_t;
        busy, done_event, error_event : out std_logic;
        error_code, bytes_committed, cycle_count : out word_t;
        m : out axi_req_t; s : in axi_rsp_t);
end;

architecture rtl of dma_engine is
  type state_t is (IDLE, PLAN, AR_REQ, R_DATA, AW_REQ, PREFETCH, W_DATA, B_RESP, FAULT);
  signal state : state_t := IDLE;
  signal src_cur, dst_cur, remaining : u32_t := (others=>'0');
  signal planned : natural range 0 to 256;
  signal nbeats : natural range 1 to MAX_BURST_BEATS := 1;
  signal ri, wi : natural range 0 to MAX_BURST_BEATS-1 := 0;
  signal ec, committed, cycles : u32_t := (others=>'0');
  signal ram_we, ram_re : std_logic;
  signal ram_ra : natural range 0 to MAX_BURST_BEATS-1 := 0;
  signal ram_q : word_t;
begin
  planner: entity work.dma_burst_planner generic map(MAX_BURST_BEATS)
    port map(src_cur,dst_cur,remaining,planned);

  buffer_i: entity work.dma_burst_buffer generic map(MAX_BURST_BEATS)
    port map(aclk,ram_we,ram_re,ri,ram_ra,s.rdata,ram_q);

  busy<='0' when state=IDLE else '1';
  error_code<=std_logic_vector(ec);
  bytes_committed<=std_logic_vector(committed);
  cycle_count<=std_logic_vector(cycles);
  ram_we<='1' when state=R_DATA and s.rvalid='1' and aresetn='1' else '0';

  -- Read output is the AXI W holding register. Its clock enable is stopped
  -- during W backpressure, so no pending RAM response can overwrite it.
  process(all)
    variable v : axi_req_t;
  begin
    v:=AXI_REQ_ZERO;
    v.araddr:=std_logic_vector(src_cur); v.awaddr:=std_logic_vector(dst_cur);
    v.arlen:=std_logic_vector(to_unsigned(nbeats-1,8)); v.awlen:=v.arlen;
    v.wdata:=ram_q;
    -- Fixed attributes (AxSIZE=010 for 4-byte beats, AxBURST=01 INCR,
    -- WSTRB=1111, IDs=0) come from AXI_REQ_ZERO in dma_pkg.
    ram_re<='0'; ram_ra<=0;
    case state is
      when AR_REQ => v.arvalid:='1';
      when R_DATA => v.rready:='1';
      when AW_REQ => v.awvalid:='1';
      when PREFETCH => ram_re<='1'; ram_ra<=0;
      when W_DATA =>
        v.wvalid:='1';
        if wi=nbeats-1 then v.wlast:='1'; end if;
        if s.wready='1' and wi<nbeats-1 then ram_re<='1'; ram_ra<=wi+1; end if;
      when B_RESP => v.bready:='1';
      when others => null;
    end case;

    -- Reset suppression uses only aresetn, not READY inputs.
    if aresetn='0' then
      v.arvalid:='0';v.awvalid:='0';v.wvalid:='0';v.rready:='0';v.bready:='0';
      ram_re<='0';
    end if;
    m<=v;
  end process;

  process(aclk)
    variable e : u32_t;
    variable expect_last : std_logic;
  begin
    if rising_edge(aclk) then
      done_event<='0'; error_event<='0';
      if aresetn='0' then
        state<=IDLE;src_cur<=(others=>'0');dst_cur<=(others=>'0');
        remaining<=(others=>'0');ec<=(others=>'0');committed<=(others=>'0');
        cycles<=(others=>'0');ri<=0;wi<=0;nbeats<=1;
      else
        if state/=IDLE and cycles/=x"FFFFFFFF" then cycles<=cycles+1; end if;
        case state is
          when IDLE =>
            if soft_reset='1' then
              ec<=(others=>'0');committed<=(others=>'0');cycles<=(others=>'0');
            elsif start='1' then
              src_cur<=unsigned(cmd_src); dst_cur<=unsigned(cmd_dst);
              remaining<=unsigned(cmd_len);ec<=(others=>'0');committed<=(others=>'0');
              cycles<=(others=>'0');state<=PLAN;
            end if;
          when PLAN =>
            assert planned>0 report "Internal zero-length burst" severity failure;
            nbeats<=planned;ri<=0;wi<=0;state<=AR_REQ;
          when AR_REQ => if s.arready='1' then state<=R_DATA; end if;
          when R_DATA =>
            if s.rvalid='1' then
              e:=ec;
              if s.rresp/="00" and e=0 then
                if s.rresp="10" then e:=to_unsigned(2,32);
                elsif s.rresp="11" then e:=to_unsigned(3,32);
                else e:=to_unsigned(7,32); end if;
              end if;
              expect_last:='0';if ri=nbeats-1 then expect_last:='1'; end if;
              if s.rlast/=expect_last or s.rid/="0" then
                -- Malformed peer: no local recovery is claimed.
                if e=0 then e:=to_unsigned(6,32); end if;
                error_event<='1';state<=FAULT;
              elsif ri=nbeats-1 then
                if e/=0 then error_event<='1';state<=IDLE;
                else state<=AW_REQ; end if;
              else ri<=ri+1; end if;
              ec<=e;
            end if;
          when AW_REQ => if s.awready='1' then state<=PREFETCH; end if;
          when PREFETCH => wi<=0;state<=W_DATA;
          when W_DATA =>
            if s.wready='1' then
              if wi=nbeats-1 then state<=B_RESP;else wi<=wi+1;end if;
            end if;
          when B_RESP =>
            if s.bvalid='1' then
              if s.bid/="0" then ec<=to_unsigned(6,32);error_event<='1';state<=FAULT;
              elsif s.bresp/="00" then
                if s.bresp="10" then ec<=to_unsigned(4,32);
                elsif s.bresp="11" then ec<=to_unsigned(5,32);
                else ec<=to_unsigned(7,32);end if;
                error_event<='1';state<=IDLE;
              else
                committed<=committed+to_unsigned(4*nbeats,32);
                if remaining=to_unsigned(4*nbeats,32) then
                  done_event<='1';state<=IDLE;
                else
                  src_cur<=src_cur+to_unsigned(4*nbeats,32);
                  dst_cur<=dst_cur+to_unsigned(4*nbeats,32);
                  remaining<=remaining-to_unsigned(4*nbeats,32);state<=PLAN;
                end if;
              end if;
            end if;
          when FAULT => null; -- Only coordinated external reset can recover.
        end case;
      end if;
    end if;
  end process;
end;