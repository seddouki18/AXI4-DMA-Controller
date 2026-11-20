-- AXI4 DMA controller, V1. Supported subset and restrictions: see README.md.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package dma_pkg is
  subtype word_t is std_logic_vector(31 downto 0);
  subtype u32_t is unsigned(31 downto 0);
  type axi_req_t is record
    araddr, awaddr : word_t;
    arlen, awlen : std_logic_vector(7 downto 0);
    arsize, awsize : std_logic_vector(2 downto 0);
    arburst, awburst : std_logic_vector(1 downto 0);
    arid, awid : std_logic_vector(0 downto 0);
    arlock, awlock : std_logic;
    arcache, awcache : std_logic_vector(3 downto 0);
    arprot, awprot : std_logic_vector(2 downto 0);
    arqos, awqos : std_logic_vector(3 downto 0);
    arvalid, awvalid : std_logic;
    rready, bready : std_logic;
    wdata : word_t;
    wstrb : std_logic_vector(3 downto 0);
    wlast, wvalid : std_logic;
  end record;
  type axi_rsp_t is record
    arready, awready, wready : std_logic;
    rdata : word_t;
    rresp, bresp : std_logic_vector(1 downto 0);
    rid, bid : std_logic_vector(0 downto 0);
    rlast, rvalid, bvalid : std_logic;
  end record;
  type axil_req_t is record
    awaddr, araddr : std_logic_vector(5 downto 0);
    awprot, arprot : std_logic_vector(2 downto 0);
    awvalid, wvalid, bready, arvalid, rready : std_logic;
    wdata : word_t;
    wstrb : std_logic_vector(3 downto 0);
  end record;
  type axil_rsp_t is record
    awready, wready, bvalid, arready, rvalid : std_logic;
    bresp, rresp : std_logic_vector(1 downto 0);
    rdata : word_t;
  end record;
  constant AXI_REQ_ZERO : axi_req_t := (
    araddr=>(others=>'0'), awaddr=>(others=>'0'),
    arlen=>(others=>'0'), awlen=>(others=>'0'),
    arsize=>"010", awsize=>"010", arburst=>"01", awburst=>"01",
    arid=>"0", awid=>"0", arlock=>'0', awlock=>'0',
    arcache=>"0000", awcache=>"0000", arprot=>"000", awprot=>"000",
    arqos=>"0000", awqos=>"0000", arvalid=>'0', awvalid=>'0',
    rready=>'0', bready=>'0', wdata=>(others=>'0'), wstrb=>"1111",
    wlast=>'0', wvalid=>'0');
  constant AXI_RSP_ZERO : axi_rsp_t := (
    arready=>'0', awready=>'0', wready=>'0', rdata=>(others=>'0'),
    rresp=>"00", bresp=>"00", rid=>"0", bid=>"0",
    rlast=>'0', rvalid=>'0', bvalid=>'0');
  constant AXIL_REQ_ZERO : axil_req_t := (
    awaddr=>(others=>'0'), araddr=>(others=>'0'), awprot=>"000", arprot=>"000",
    awvalid=>'0', wvalid=>'0', bready=>'0', arvalid=>'0', rready=>'0',
    wdata=>(others=>'0'), wstrb=>"0000");
  constant AXIL_RSP_ZERO : axil_rsp_t := (
    awready=>'0', wready=>'0', bvalid=>'0', arready=>'0', rvalid=>'0',
    bresp=>"00", rresp=>"00", rdata=>(others=>'0'));
  function merge_bytes(old_value, new_value : word_t;
                       strb : std_logic_vector(3 downto 0)) return word_t;
  function command_valid(src, dst, len : word_t) return boolean;
end package;

package body dma_pkg is
  function merge_bytes(old_value, new_value : word_t;
                       strb : std_logic_vector(3 downto 0)) return word_t is
    variable v : word_t := old_value;
  begin
    for b in 0 to 3 loop
      if strb(b)='1' then v(8*b+7 downto 8*b):=new_value(8*b+7 downto 8*b); end if;
    end loop;
    return v;
  end;
  function command_valid(src, dst, len : word_t) return boolean is
    variable se, de, lim : unsigned(32 downto 0);
  begin
    if unsigned(len)=0 or src(1 downto 0)/="00" or
       dst(1 downto 0)/="00" or len(1 downto 0)/="00" then return false; end if;
    se:=resize(unsigned(src),33)+resize(unsigned(len),33);
    de:=resize(unsigned(dst),33)+resize(unsigned(len),33);
    lim:=(others=>'0'); lim(32):='1';
    return se<=lim and de<=lim and
      (se<=resize(unsigned(dst),33) or de<=resize(unsigned(src),33));
  end;
end package body;
