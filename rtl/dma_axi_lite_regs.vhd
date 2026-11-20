library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dma_pkg.all;

entity dma_axi_lite_regs is
  port (aclk, aresetn : in std_logic;
        req : in axil_req_t; rsp : out axil_rsp_t;
        start, soft_reset : out std_logic;
        cmd_src, cmd_dst, cmd_len : out word_t;
        busy, done_event, error_event : in std_logic;
        engine_error, bytes_committed, cycle_count : in word_t;
        irq : out std_logic);
end;
architecture rtl of dma_axi_lite_regs is
  signal src, dst, len, last_error : word_t := (others=>'0');
  signal done_sticky, err_sticky, irq_en : std_logic := '0';
  signal aw_pending, w_pending : std_logic := '0';
  signal aw_q : std_logic_vector(5 downto 0) := (others=>'0');
  signal wd_q : word_t := (others=>'0');
  signal ws_q : std_logic_vector(3 downto 0) := (others=>'0');
  signal b_v, r_v : std_logic := '0';
  signal b_resp, r_resp : std_logic_vector(1 downto 0) := "00";
  signal r_data : word_t := (others=>'0');
begin
  cmd_src<=src;cmd_dst<=dst;cmd_len<=len;
  irq<=irq_en and (done_sticky or err_sticky);
  rsp.awready<=not (aw_pending or b_v) and aresetn;
  rsp.wready<=not (w_pending or b_v) and aresetn;
  rsp.arready<=not r_v and aresetn;
  rsp.bvalid<=b_v and aresetn;rsp.bresp<=b_resp;
  rsp.rvalid<=r_v and aresetn;rsp.rresp<=r_resp;rsp.rdata<=r_data;
  process(aclk)
    variable v, masked : word_t;
    variable resp_v : std_logic_vector(1 downto 0);
    variable a : natural;
  begin
    if rising_edge(aclk) then
      start<='0';soft_reset<='0';
      if aresetn='0' then
        src<=(others=>'0');dst<=(others=>'0');len<=(others=>'0');
        last_error<=(others=>'0');done_sticky<='0';err_sticky<='0';irq_en<='0';
        aw_pending<='0';w_pending<='0';b_v<='0';r_v<='0';
        b_resp<="00";r_resp<="00";r_data<=(others=>'0');
      else
        if done_event='1' then done_sticky<='1';end if;
        if error_event='1' then err_sticky<='1';done_sticky<='0';last_error<=engine_error;end if;
        if b_v='1' and req.bready='1' then b_v<='0';end if;
        if r_v='1' and req.rready='1' then r_v<='0';end if;
        if req.awvalid='1' and aw_pending='0' and b_v='0' then
          aw_pending<='1';aw_q<=req.awaddr;
        end if;
        if req.wvalid='1' and w_pending='0' and b_v='0' then
          w_pending<='1';wd_q<=req.wdata;ws_q<=req.wstrb;
        end if;
        if aw_pending='1' and w_pending='1' and b_v='0' then
          aw_pending<='0';w_pending<='0';b_v<='1';resp_v:="00";
          a:=to_integer(unsigned(aw_q));masked:=merge_bytes(x"00000000",wd_q,ws_q);
          if aw_q(1 downto 0)/="00" then resp_v:="11";
          else
            case a is
              when 0 =>
                if busy='1' or (masked(0)='1' and masked(1)='1') then resp_v:="10";
                elsif masked(1)='1' then
                  soft_reset<='1';src<=(others=>'0');dst<=(others=>'0');len<=(others=>'0');
                  done_sticky<='0';err_sticky<='0';irq_en<='0';last_error<=(others=>'0');
                elsif masked(0)='1' and not command_valid(src,dst,len) then
                  resp_v:="10";err_sticky<='1';done_sticky<='0';last_error<=x"00000001";
                else
                  if ws_q(0)='1' then irq_en<=wd_q(2);end if;
                  if masked(0)='1' then
                    start<='1';done_sticky<='0';err_sticky<='0';last_error<=(others=>'0');
                  end if;
                end if;
              when 4 =>
                if busy='1' then resp_v:="10";
                else
                  if masked(1)='1' then done_sticky<='0';end if;
                  if masked(2)='1' then err_sticky<='0';last_error<=(others=>'0');end if;
                end if;
              when 8 | 12 | 16 =>
                if busy='1' then resp_v:="10";
                elsif a=8 then src<=merge_bytes(src,wd_q,ws_q);
                elsif a=12 then dst<=merge_bytes(dst,wd_q,ws_q);
                else len<=merge_bytes(len,wd_q,ws_q);end if;
              when 20 | 24 | 28 | 32 => resp_v:="10";
              when others => resp_v:="11";
            end case;
          end if;
          b_resp<=resp_v;
        end if;
        if req.arvalid='1' and r_v='0' then
          v:=(others=>'0');resp_v:="00";a:=to_integer(unsigned(req.araddr));
          if req.araddr(1 downto 0)/="00" then resp_v:="11";
          else
            case a is
              when 0 => v(2):=irq_en;
              when 4 => v(0):=busy;v(1):=done_sticky;v(2):=err_sticky;
              when 8 => v:=src;
              when 12 => v:=dst;
              when 16 => v:=len;
              when 20 => v:=last_error;
              when 24 => v:=bytes_committed;
              when 28 => v:=cycle_count;
              when 32 => v:=x"00010000";
              when others => resp_v:="11";
            end case;
          end if;
          r_data<=v;r_resp<=resp_v;r_v<='1';
        end if;
      end if;
    end if;
  end process;
end;
