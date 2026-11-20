library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.dma_pkg.all;

entity tb_dma_top is
  generic (G_MAX_BEATS : positive := 256; G_SEED : positive := 1);
end;
architecture sim of tb_dma_top is
  constant MEM_WORDS : positive := 32768;
  signal aclk : std_logic := '0';
  signal aresetn : std_logic := '0';
  signal irq : std_logic;
  signal m : axi_req_t;
  signal s : axi_rsp_t := AXI_RSP_ZERO;
  signal lreq : axil_req_t := AXIL_REQ_ZERO;
  signal lrsp : axil_rsp_t;
  signal init_req, check_req : std_logic := '0';
  signal check_src, check_dst, check_len : natural := 0;
  signal stall_mode : natural range 0 to 1 := 0;
  signal inject_r_index : integer := -1;
  signal inject_r_resp, inject_b_resp : std_logic_vector(1 downto 0) := "00";
  signal malformed_last : std_logic := '0';
  signal hold_b, hold_ar : std_logic := '0';
  signal ar_count, aw_count, r_count, w_count, b_count : natural := 0;
  signal model_idle : std_logic := '1';
  -- Added for guide tests T10 and E05.
  signal stall_w_index : integer := -1;
  signal stall_w_cycles : natural := 0;
  signal forced_w_stalls : natural := 0;
  signal drop_last, inject_rid, inject_bid : std_logic := '0';
  -- Added for guide test E07 (slave stops responding).
  constant HANG_CYCLES : positive := 1000;
  signal hold_w, hang_expected, hang_flag : std_logic := '0';
  function pattern(i : natural) return word_t is
  begin return std_logic_vector(to_unsigned(i*13+7,32));end;
  -- Expected number of bursts for a command (guide chapter 8 formula).
  function plan_count(src, dst, len, maxb : natural) return natural is
    variable sa, da, r, n, c : natural;
  begin
    sa:=src;da:=dst;r:=len/4;c:=0;
    while r>0 loop
      n:=r;
      if n>maxb then n:=maxb;end if;
      if n>(4096-(sa mod 4096))/4 then n:=(4096-(sa mod 4096))/4;end if;
      if n>(4096-(da mod 4096))/4 then n:=(4096-(da mod 4096))/4;end if;
      sa:=sa+4*n;da:=da+4*n;r:=r-n;c:=c+1;
    end loop;
    return c;
  end;
  function next_random(x : unsigned(31 downto 0)) return unsigned is
    variable v : unsigned(31 downto 0) := x;
  begin
    v:=v xor shift_left(v,13);v:=v xor shift_right(v,17);
    v:=v xor shift_left(v,5);return v;
  end;
begin
  aclk<=not aclk after 5 ns;
  dut: entity work.dma_top generic map(MAX_BURST_BEATS=>G_MAX_BEATS)
    port map (
      aclk=>aclk,
      aresetn=>aresetn,
      irq=>irq,
      m_axi_araddr=>m.araddr,
      m_axi_awaddr=>m.awaddr,
      m_axi_arlen=>m.arlen,
      m_axi_awlen=>m.awlen,
      m_axi_arsize=>m.arsize,
      m_axi_awsize=>m.awsize,
      m_axi_arburst=>m.arburst,
      m_axi_awburst=>m.awburst,
      m_axi_arid=>m.arid,
      m_axi_awid=>m.awid,
      m_axi_arlock=>m.arlock,
      m_axi_awlock=>m.awlock,
      m_axi_arcache=>m.arcache,
      m_axi_awcache=>m.awcache,
      m_axi_arprot=>m.arprot,
      m_axi_awprot=>m.awprot,
      m_axi_arqos=>m.arqos,
      m_axi_awqos=>m.awqos,
      m_axi_arvalid=>m.arvalid,
      m_axi_awvalid=>m.awvalid,
      m_axi_rready=>m.rready,
      m_axi_bready=>m.bready,
      m_axi_wdata=>m.wdata,
      m_axi_wstrb=>m.wstrb,
      m_axi_wlast=>m.wlast,
      m_axi_wvalid=>m.wvalid,
      m_axi_arready=>s.arready,
      m_axi_awready=>s.awready,
      m_axi_wready=>s.wready,
      m_axi_rdata=>s.rdata,
      m_axi_rresp=>s.rresp,
      m_axi_bresp=>s.bresp,
      m_axi_rid=>s.rid,
      m_axi_bid=>s.bid,
      m_axi_rlast=>s.rlast,
      m_axi_rvalid=>s.rvalid,
      m_axi_bvalid=>s.bvalid,
      s_axi_awaddr=>lreq.awaddr,
      s_axi_araddr=>lreq.araddr,
      s_axi_awprot=>lreq.awprot,
      s_axi_arprot=>lreq.arprot,
      s_axi_awvalid=>lreq.awvalid,
      s_axi_wvalid=>lreq.wvalid,
      s_axi_bready=>lreq.bready,
      s_axi_arvalid=>lreq.arvalid,
      s_axi_rready=>lreq.rready,
      s_axi_wdata=>lreq.wdata,
      s_axi_wstrb=>lreq.wstrb,
      s_axi_awready=>lrsp.awready,
      s_axi_wready=>lrsp.wready,
      s_axi_bvalid=>lrsp.bvalid,
      s_axi_arready=>lrsp.arready,
      s_axi_rvalid=>lrsp.rvalid,
      s_axi_bresp=>lrsp.bresp,
      s_axi_rresp=>lrsp.rresp,
      s_axi_rdata=>lrsp.rdata
    );

  -- A single process owns the memory. All accesses are observed at handshakes.
  memory_model: process(aclk)
    type memory_t is array(0 to MEM_WORDS-1) of word_t;
    variable mem : memory_t;
    variable rd_active, wr_active, pending_b : boolean := false;
    variable rd_base, wr_base, rd_n, wr_n, rd_i, wr_i : natural := 0;
    variable delay_b : natural := 0;
    variable rng : unsigned(31 downto 0) := to_unsigned(G_SEED,32);
    variable v : axi_rsp_t;
    variable expected : word_t;
    variable idx : natural;
    variable w_hold : natural := 0;
    variable w_stall_done : boolean := false;
  begin
    if rising_edge(aclk) then
      if aresetn='0' or init_req='1' then
        for i in mem'range loop mem(i):=pattern(i);end loop;
        s<=AXI_RSP_ZERO;rd_active:=false;wr_active:=false;pending_b:=false;
        rd_i:=0;wr_i:=0;delay_b:=0;
        ar_count<=0;aw_count<=0;r_count<=0;w_count<=0;b_count<=0;model_idle<='1';
        forced_w_stalls<=0;w_hold:=0;w_stall_done:=false;
      else
        v:=s;rng:=next_random(rng);
        if s.rvalid='1' and m.rready='1' then
          r_count<=r_count+1;v.rvalid:='0';
          if rd_i=rd_n-1 then rd_active:=false;else rd_i:=rd_i+1;end if;
        end if;
        if s.bvalid='1' and m.bready='1' then
          b_count<=b_count+1;v.bvalid:='0';
        end if;
        if m.arvalid='1' and s.arready='1' then
          assert not rd_active and v.rvalid='0' report "Two reads outstanding" severity failure;
          assert m.arid="0" and m.arsize="010" and m.arburst="01"
            report "Bad AR attributes" severity failure;
          rd_base:=to_integer(unsigned(m.araddr));rd_n:=to_integer(unsigned(m.arlen))+1;rd_i:=0;
          assert rd_base mod 4=0 and (rd_base mod 4096)+4*rd_n<=4096
            report "AR alignment / 4 KB boundary" severity failure;
          assert rd_n<=G_MAX_BEATS and rd_base/4+rd_n<=MEM_WORDS severity failure;
          rd_active:=true;ar_count<=ar_count+1;
        end if;
        if m.awvalid='1' and s.awready='1' then
          assert not wr_active and not pending_b and v.bvalid='0'
            report "Two writes outstanding" severity failure;
          assert m.awid="0" and m.awsize="010" and m.awburst="01"
            report "Bad AW attributes" severity failure;
          wr_base:=to_integer(unsigned(m.awaddr));wr_n:=to_integer(unsigned(m.awlen))+1;wr_i:=0;
          assert wr_base mod 4=0 and (wr_base mod 4096)+4*wr_n<=4096
            report "AW alignment / 4 KB boundary" severity failure;
          assert wr_n<=G_MAX_BEATS and wr_base/4+wr_n<=MEM_WORDS severity failure;
          wr_active:=true;aw_count<=aw_count+1;w_hold:=0;w_stall_done:=false;
        end if;
        if m.wvalid='1' and s.wready='1' then
          assert wr_active report "W without AW" severity failure;
          assert m.wstrb="1111" report "Unexpected master WSTRB" severity failure;
          if wr_i=wr_n-1 then
            assert m.wlast='1' report "Missing WLAST" severity failure;
          else assert m.wlast='0' report "Early WLAST" severity failure;end if;
          mem(wr_base/4+wr_i):=m.wdata;w_count<=w_count+1;
          if wr_i=wr_n-1 then
            wr_active:=false;pending_b:=true;delay_b:=7;
          else wr_i:=wr_i+1;end if;
        end if;
        -- Registered, independently delayed memory responses.
        if rd_active and v.rvalid='0' and (stall_mode=0 or rng(2 downto 1)/="00") then
          v.rvalid:='1';v.rdata:=mem(rd_base/4+rd_i);v.rresp:="00";v.rid:="0";
          v.rlast:='0';if rd_i=rd_n-1 then v.rlast:='1';end if;
          if rd_i=inject_r_index then v.rresp:=inject_r_resp;end if;
          if malformed_last='1' and rd_i=0 then v.rlast:=not v.rlast;end if;
          if drop_last='1' and rd_i=rd_n-1 then v.rlast:='0';end if;
          if inject_rid='1' and rd_i=0 then v.rid:="1";end if;
        end if;
        if pending_b and v.bvalid='0' and hold_b='0' then
          if delay_b>0 then delay_b:=delay_b-1;
          elsif stall_mode=0 or rng(4 downto 3)/="00" then
            v.bvalid:='1';v.bresp:=inject_b_resp;v.bid:="0";pending_b:=false;
            if inject_bid='1' then v.bid:="1";end if;
          end if;
        end if;
        v.arready:='0';v.awready:='0';v.wready:='0';
        if not rd_active and v.rvalid='0' and hold_ar='0' and
           (stall_mode=0 or rng(6 downto 5)/="00") then v.arready:='1';end if;
        if not wr_active and not pending_b and v.bvalid='0' and
           (stall_mode=0 or rng(8 downto 7)/="00") then v.awready:='1';end if;
        if wr_active and (stall_mode=0 or rng(10 downto 9)/="00") then v.wready:='1';end if;
        if hold_w='1' then v.wready:='0';end if;
        -- Deterministic WREADY pause on one beat index of every burst (T10).
        if wr_active and stall_w_index>=0 and wr_i=stall_w_index and not w_stall_done then
          if w_hold<stall_w_cycles then
            v.wready:='0';w_hold:=w_hold+1;forced_w_stalls<=forced_w_stalls+1;
          else w_stall_done:=true;end if;
        end if;
        if rd_active or wr_active or pending_b or v.rvalid='1' or v.bvalid='1' then
          model_idle<='0';else model_idle<='1';end if;
        s<=v;
        -- Compare the entire memory, including all locations outside destination.
        if check_req='1' then
          for i in mem'range loop
            expected:=pattern(i);
            if i>=check_dst/4 and i<(check_dst+check_len)/4 then
              idx:=check_src/4+i-check_dst/4;expected:=pattern(idx);
            end if;
            assert mem(i)=expected report "Memory mismatch at word "&integer'image(i) severity failure;
          end loop;
        end if;
      end if;
    end if;
  end process;

  stability_monitor: process(aclk)
    variable prev : axi_req_t := AXI_REQ_ZERO;
    variable pl : axil_rsp_t := AXIL_RSP_ZERO;
    variable ps : axi_rsp_t := AXI_RSP_ZERO;
    variable ar_stall, aw_stall, w_stall, lb_stall, lr_stall, r_stall, b_stall : boolean := false;
  begin
    if rising_edge(aclk) then
      if aresetn='0' then
        ar_stall:=false;aw_stall:=false;w_stall:=false;lb_stall:=false;
        lr_stall:=false;r_stall:=false;b_stall:=false;
      else
        if ar_stall then
          assert m.arvalid='1' and m.araddr=prev.araddr and m.arlen=prev.arlen
            and m.arsize=prev.arsize and m.arburst=prev.arburst
            report "AR changed while stalled" severity failure;
        end if;
        if aw_stall then
          assert m.awvalid='1' and m.awaddr=prev.awaddr and m.awlen=prev.awlen
            and m.awsize=prev.awsize and m.awburst=prev.awburst
            report "AW changed while stalled" severity failure;
        end if;
        if w_stall then
          assert m.wvalid='1' and m.wdata=prev.wdata and m.wstrb=prev.wstrb and m.wlast=prev.wlast
            report "W changed while stalled" severity failure;
        end if;
        if lb_stall then assert lrsp.bvalid='1' and lrsp.bresp=pl.bresp severity failure;end if;
        if lr_stall then assert lrsp.rvalid='1' and lrsp.rdata=pl.rdata and lrsp.rresp=pl.rresp severity failure;end if;
        if r_stall then
          assert s.rvalid='1' and s.rdata=ps.rdata and s.rresp=ps.rresp and s.rlast=ps.rlast severity failure;
        end if;
        if b_stall then assert s.bvalid='1' and s.bresp=ps.bresp severity failure;end if;
        ar_stall:=m.arvalid='1' and s.arready='0';
        aw_stall:=m.awvalid='1' and s.awready='0';
        w_stall:=m.wvalid='1' and s.wready='0';
        lb_stall:=lrsp.bvalid='1' and lreq.bready='0';
        lr_stall:=lrsp.rvalid='1' and lreq.rready='0';
        r_stall:=s.rvalid='1' and m.rready='0';b_stall:=s.bvalid='1' and m.bready='0';
        prev:=m;pl:=lrsp;ps:=s;
      end if;
    end if;
  end process;

  -- E07: progress watchdog. It counts the cycles where the DMA offers or waits
  -- (ARVALID, AWVALID, WVALID, RREADY or BREADY high) without any handshake.
  -- An unexpected hang stops the run with a diagnostic naming the channel.
  -- During the E07 tests the hang is expected and only raises hang_flag.
  progress_watchdog: process(aclk)
    variable idle : natural := 0;
    function b(x : std_logic) return string is
    begin if x='1' then return "1";else return "0";end if;end;
    impure function diag return string is
    begin
      return "no AXI handshake for "&integer'image(HANG_CYCLES)&" cycles; ARVALID="&b(m.arvalid)&
        " AWVALID="&b(m.awvalid)&" WVALID="&b(m.wvalid)&" RREADY="&b(m.rready)&
        " BREADY="&b(m.bready)&" R/W/B beats="&integer'image(r_count)&"/"&
        integer'image(w_count)&"/"&integer'image(b_count);
    end;
  begin
    if rising_edge(aclk) then
      if aresetn='0' then idle:=0;hang_flag<='0';
      elsif (m.arvalid='1' and s.arready='1') or (s.rvalid='1' and m.rready='1') or
            (m.awvalid='1' and s.awready='1') or (m.wvalid='1' and s.wready='1') or
            (s.bvalid='1' and m.bready='1') then idle:=0;
      elsif m.arvalid='1' or m.awvalid='1' or m.wvalid='1' or m.rready='1' or m.bready='1' then
        idle:=idle+1;
        if idle=HANG_CYCLES then
          if hang_expected='1' then
            hang_flag<='1';report "E07 watchdog (expected): "&diag severity note;
          else report "E07 watchdog: "&diag severity failure;end if;
        end if;
      else idle:=0;
      end if;
    end if;
  end process;

  stimulus: process
    variable value, status : word_t;
    variable tests : natural := 0;
    variable rand : unsigned(31 downto 0) := to_unsigned(G_SEED,32);
    variable size_bytes, sa, da : natural;
    procedure tick(n : positive := 1) is
    begin for i in 1 to n loop wait until rising_edge(aclk);end loop;end;
    procedure wr(a : natural; d : word_t; st : std_logic_vector(3 downto 0) := "1111";
                 skew : integer := 0; response : std_logic_vector(1 downto 0) := "00") is
      variable adone, wdone : boolean;
      variable held : std_logic_vector(1 downto 0);
    begin
      lreq.awaddr<=std_logic_vector(to_unsigned(a,6));lreq.wdata<=d;lreq.wstrb<=st;
      lreq.bready<='0';
      if skew=0 then
        lreq.awvalid<='1';lreq.wvalid<='1';adone:=false;wdone:=false;
        while not(adone and wdone) loop
          tick;
          if not adone and lrsp.awready='1' then adone:=true;lreq.awvalid<='0';end if;
          if not wdone and lrsp.wready='1' then wdone:=true;lreq.wvalid<='0';end if;
        end loop;
      elsif skew>0 then
        lreq.awvalid<='1';loop tick;exit when lrsp.awready='1';end loop;lreq.awvalid<='0';
        tick(skew);lreq.wvalid<='1';loop tick;exit when lrsp.wready='1';end loop;lreq.wvalid<='0';
      else
        lreq.wvalid<='1';loop tick;exit when lrsp.wready='1';end loop;lreq.wvalid<='0';
        tick(-skew);lreq.awvalid<='1';loop tick;exit when lrsp.awready='1';end loop;lreq.awvalid<='0';
      end if;
      loop tick;exit when lrsp.bvalid='1';end loop;
      held:=lrsp.bresp;
      tick(3);assert lrsp.bvalid='1' and lrsp.bresp=held report "Lite B not held" severity failure;
      assert held=response report "Wrong AXI-Lite BRESP, offset "&integer'image(a) severity failure;
      lreq.bready<='1';tick;lreq.bready<='0';
    end;
    procedure rd(a : natural; variable d : out word_t;
                 response : std_logic_vector(1 downto 0) := "00") is
      variable held : word_t;
    begin
      lreq.araddr<=std_logic_vector(to_unsigned(a,6));lreq.arvalid<='1';lreq.rready<='0';
      loop tick;exit when lrsp.arready='1';end loop;lreq.arvalid<='0';
      loop tick;exit when lrsp.rvalid='1';end loop;held:=lrsp.rdata;
      assert lrsp.rresp=response report "Wrong AXI-Lite RRESP" severity failure;
      tick(2);assert lrsp.rvalid='1' and lrsp.rdata=held severity failure;
      d:=held;lreq.rready<='1';tick;lreq.rready<='0';
    end;
    procedure reset_all is
    begin
      aresetn<='0';lreq<=AXIL_REQ_ZERO;init_req<='0';check_req<='0';
      inject_r_index<=-1;inject_r_resp<="00";inject_b_resp<="00";malformed_last<='0';
      hold_b<='0';hold_ar<='0';stall_w_index<=-1;stall_w_cycles<=0;
      drop_last<='0';inject_rid<='0';inject_bid<='0';hold_w<='0';hang_expected<='0';
      tick(4);aresetn<='1';tick(3);
    end;
    procedure fresh_memory is
    begin init_req<='1';tick(2);init_req<='0';tick(2);end;
    procedure configure(src, dst, len : natural) is
    begin
      wr(8,std_logic_vector(to_unsigned(src,32)),skew=>2);
      wr(12,std_logic_vector(to_unsigned(dst,32)),skew=>-2);
      wr(16,std_logic_vector(to_unsigned(len,32)));
    end;
    procedure terminal(expect_error : boolean := false; expected_code : natural := 0;
                       fault : boolean := false) is
      variable st, ec : word_t;
    begin
      for j in 0 to 50000 loop
        rd(4,st);
        if st(1)='1' or st(2)='1' then
          if expect_error then
            assert st(2)='1' and st(1)='0' report "Expected ERROR only" severity failure;
            rd(20,ec);assert unsigned(ec)=expected_code report "Bad error code" severity failure;
          else assert st(1)='1' and st(2)='0' report "Copy failed" severity failure;end if;
          if fault then assert st(0)='1' severity failure;
          else
            assert st(0)='0' and model_idle='1' report "Terminal before AXI completion" severity failure;
          end if;
          return;
        end if;
      end loop;
      assert false report "Terminal poll timed out" severity failure;
    end;
    procedure memory_check(src, dst, len : natural) is
    begin
      check_src<=src;check_dst<=dst;check_len<=len;check_req<='1';tick(2);check_req<='0';tick;
    end;
    procedure passed(label_s : string) is
    begin tests:=tests+1;report "PASS "&integer'image(tests)&" "&label_s severity note;end;
    procedure copy_case(src, dst, len : natural; label_s : string) is
    begin
      fresh_memory;configure(src,dst,len);wr(0,x"00000001");terminal;
      memory_check(src,dst,len);rd(24,value);
      assert unsigned(value)=len report "Committed byte count" severity failure;
      assert r_count=len/4 and w_count=len/4 and ar_count=aw_count and b_count=aw_count severity failure;
      assert ar_count=plan_count(src,dst,len,G_MAX_BEATS)
        report "Unexpected number of bursts" severity failure;
      rd(28,value);report "METRIC bytes="&integer'image(len)&" cycles="&integer'image(to_integer(unsigned(value))) severity note;
      passed(label_s);
    end;
    procedure w_pause_case(index : natural; label_s : string) is
    begin
      stall_w_index<=index;stall_w_cycles<=5;
      copy_case(16#1000#,16#8000#,1024,label_s);
      assert forced_w_stalls>=5 report "Forced WREADY pause not applied" severity failure;
      stall_w_index<=-1;stall_w_cycles<=0;
    end;
    procedure bad_case(src, dst, len : word_t; label_s : string) is
    begin
      fresh_memory;wr(8,src);wr(12,dst);wr(16,len);
      wr(0,x"00000001",response=>"10");terminal(true,1);
      assert ar_count=0 and aw_count=0 severity failure;memory_check(0,0,0);passed(label_s);
    end;
  begin
    reset_all;rd(4,value);assert value=x"00000000" severity failure;
    rd(32,value);assert value=x"00010000" severity failure;passed("reset and version");
    wr(8,x"11223344");wr(8,x"AABBCCDD","0101",3);rd(8,value);
    assert value=x"11BB33DD" severity failure;
    wr(8,x"00000000","0000",-3);rd(8,value);assert value=x"11BB33DD" severity failure;
    wr(0,x"00000001","0000");rd(4,value);assert value=x"00000000" severity failure;
    passed("Lite skew, strobes, zero strobes, response backpressure");
    rd(36,value,"11");rd(9,value,"11");wr(36,x"00000000",response=>"11");
    wr(32,x"00000000",response=>"10");wr(9,x"00000000",response=>"11");
    wr(0,x"00000003",response=>"10");passed("invalid register and conflicting commands");
    wr(0,x"00000002");rd(8,value);assert value=x"00000000" severity failure;
    passed("idle soft reset");
    copy_case(16#1000#,16#8000#,4,"one word");
    copy_case(16#1000#,16#8000#,16,"four words");
    copy_case(16#1000#,16#8000#,1020,"255 words");
    copy_case(16#1000#,16#8000#,1024,"256 words");
    copy_case(16#1000#,16#8000#,1028,"257 words");
    copy_case(16#1FF0#,16#8000#,128,"source boundary");
    copy_case(16#1000#,16#8FF8#,64,"destination boundary");
    copy_case(16#1FF0#,16#8FF8#,128,"different boundaries");
    copy_case(16#1000#,16#9000#,32768,"32 KiB block");
    stall_mode<=1;
    copy_case(16#1000#,16#8000#,8192,"random independent stalls");
    for k in 1 to 40 loop
      rand:=next_random(rand);size_bytes:=4*(1+to_integer(rand(10 downto 0)));
      sa:=16#1000#+4*to_integer(rand(6 downto 0));
      rand:=next_random(rand);da:=16#9000#+4*to_integer(rand(7 downto 0));
      copy_case(sa,da,size_bytes,"random command "&integer'image(k));
    end loop;
    bad_case(x"00001000",x"00008000",x"00000000","zero length");
    bad_case(x"00001000",x"00008000",x"00000006","non-word length");
    bad_case(x"00001001",x"00008000",x"00000010","unaligned source");
    bad_case(x"00001000",x"00008002",x"00000010","unaligned destination");
    bad_case(x"FFFFFFFC",x"00008000",x"00000008","source overflow");
    bad_case(x"00001000",x"FFFFFFFC",x"00000008","destination overflow");
    bad_case(x"00001000",x"00001004",x"00000010","overlap");
    -- No DONE before the last B response; writes while BUSY are rejected.
    fresh_memory;hold_b<='1';configure(16#1000#,16#8000#,1024);wr(0,x"00000005");
    while w_count<G_MAX_BEATS loop tick;end loop;
    rd(4,value);assert value(0)='1' and value(2 downto 1)="00" severity failure;
    wr(0,x"00000001",response=>"10");wr(8,x"00003000",response=>"10");
    wr(0,x"00000002",response=>"10");wr(4,x"00000006",response=>"10");
    rd(8,value);assert value=x"00001000" severity failure;
    hold_b<='0';terminal;assert irq='1' severity failure;
    memory_check(16#1000#,16#8000#,1024);wr(4,x"00000006");tick;
    assert irq='0' severity failure;passed("busy protection, delayed B, IRQ, W1C");
    -- Read errors must drain the entire accepted burst and not issue AW.
    for code_r in 2 to 3 loop
      for pos in 0 to 2 loop
        fresh_memory;
        if pos=0 then inject_r_index<=0;
        elsif pos=1 then inject_r_index<=G_MAX_BEATS/2;
        else inject_r_index<=G_MAX_BEATS-1;end if;
        if code_r=2 then inject_r_resp<="10";else inject_r_resp<="11";end if;
        configure(16#1000#,16#8000#,1024);wr(0,x"00000001");terminal(true,code_r);
        assert aw_count=0 and ar_count=1 and r_count=G_MAX_BEATS severity failure;
        memory_check(0,0,0);passed("R error draining "&integer'image(code_r));
      end loop;
    end loop;
    inject_r_index<=-1;inject_r_resp<="00";
    for code_b in 4 to 5 loop
      fresh_memory;
      if code_b=4 then inject_b_resp<="10";else inject_b_resp<="11";end if;
      configure(16#1000#,16#8000#,2048);wr(0,x"00000001");terminal(true,code_b);
      rd(24,value);assert value=x"00000000" and aw_count=1 and b_count=1 severity failure;
      passed("B error stops next burst "&integer'image(code_b));
    end loop;
    inject_b_resp<="00";fresh_memory;inject_r_index<=0;inject_r_resp<="01";
    configure(16#1000#,16#8000#,16);wr(0,x"00000001");terminal(true,7);
    passed("unexpected EXOKAY");inject_r_index<=-1;inject_r_resp<="00";
    fresh_memory;malformed_last<='1';configure(16#1000#,16#8000#,16);
    wr(0,x"00000001");terminal(true,6,true);passed("malformed RLAST fault");
    reset_all;fresh_memory;hold_ar<='1';tick(2);
    configure(16#1000#,16#8000#,1024);wr(0,x"00000001");tick(10);
    assert m.arvalid='1' and s.arready='0' severity failure;
    reset_all;rd(4,value);assert value=x"00000000" severity failure;
    passed("coordinated external reset with active AR offer");
    copy_case(16#1000#,16#8000#,64,"restart after reset");
    -- ===== Added tests (guide T01, T05, T10, E05) =====
    -- T01: full register map after reset, no master activity.
    reset_all;
    assert m.arvalid='0' and m.awvalid='0' and m.wvalid='0' and m.rready='0'
      and m.bready='0' and irq='0' report "Master activity after reset" severity failure;
    for a in 0 to 7 loop
      rd(4*a,value);
      assert value=x"00000000" report "Register not reset, offset "&integer'image(4*a) severity failure;
    end loop;
    rd(32,value);assert value=x"00010000" severity failure;
    assert ar_count=0 and aw_count=0 report "Parasitic master transaction" severity failure;
    passed("register map after reset");
    -- T05: remaining nominal lengths.
    copy_case(16#1000#,16#8000#,2048,"2048 bytes");
    copy_case(16#1000#,16#8000#,4096,"4096 bytes, full 4 KiB page");
    -- T10: WREADY held low on the first, middle and last beat of every burst.
    stall_mode<=0;
    w_pause_case(0,"WREADY pause on first beat");
    w_pause_case(G_MAX_BEATS/2,"WREADY pause on middle beat");
    w_pause_case(G_MAX_BEATS-1,"WREADY pause on last beat");
    -- E05: missing RLAST, unexpected RID and BID are protocol faults (code 6).
    reset_all;fresh_memory;drop_last<='1';configure(16#1000#,16#8000#,16);
    wr(0,x"00000001");terminal(true,6,true);passed("missing RLAST fault");
    reset_all;fresh_memory;inject_rid<='1';configure(16#1000#,16#8000#,16);
    wr(0,x"00000001");terminal(true,6,true);
    assert aw_count=0 report "Write after RID fault" severity failure;
    passed("unexpected RID fault");
    reset_all;fresh_memory;inject_bid<='1';configure(16#1000#,16#8000#,2048);
    wr(0,x"00000001");terminal(true,6,true);
    assert aw_count=1 and b_count=1 report "Burst issued after BID fault" severity failure;
    passed("unexpected BID fault");
    reset_all;copy_case(16#1000#,16#8000#,64,"restart after protocol faults");
    -- E07: the slave stops responding on AR, on W in the middle of a burst,
    -- then on B. The progress watchdog must flag the hang. The DMA must stay
    -- BUSY with its offer still present (no false DONE/ERROR, no cancellation),
    -- then finish the copy correctly once the slave responds again.
    for ch in 0 to 2 loop
      reset_all;fresh_memory;hang_expected<='1';
      if ch=0 then hold_ar<='1';elsif ch=2 then hold_b<='1';end if;
      configure(16#1000#,16#8000#,1024);wr(0,x"00000001");
      if ch=1 then
        while w_count<G_MAX_BEATS/2 loop tick;end loop;
        hold_w<='1';
      end if;
      while hang_flag='0' loop tick;end loop;
      rd(4,value);
      assert value(2 downto 0)="001" report "False DONE/ERROR during slave hang" severity failure;
      if ch=0 then assert m.arvalid='1' report "AR offer withdrawn" severity failure;
      elsif ch=1 then assert m.wvalid='1' report "W offer withdrawn" severity failure;
      else assert m.bready='1' report "BREADY dropped" severity failure;end if;
      hold_ar<='0';hold_w<='0';hold_b<='0';
      terminal;memory_check(16#1000#,16#8000#,1024);hang_expected<='0';
      if ch=0 then passed("slave hang on AR detected, no false cancel, resumed");
      elsif ch=1 then passed("slave hang on W mid-burst detected, no false cancel, resumed");
      else passed("slave hang on B detected, no false cancel, resumed");end if;
    end loop;
    report "ALL TESTS PASSED count="&integer'image(tests)&
      " max_beats="&integer'image(G_MAX_BEATS)&" seed="&integer'image(G_SEED) severity note;
    finish;
  end process;
  watchdog: process
  begin wait for 50 ms;assert false report "Global simulation watchdog" severity failure;end process;
end;
