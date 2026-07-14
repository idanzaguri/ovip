`ifndef OVIP_ACE_AGENT_IF__SV
`define OVIP_ACE_AGENT_IF__SV

// ovip_ace_agent_if -- AXI signals with identical names to ovip_axi_agent_if
// (so the inherited ovip_axi_*_driver / ovip_axi_monitor code resolves when
// the IF_T parameter binds to this interface) plus the ACE additions:
//
//   - AR/AW: ARDOMAIN, ARSNOOP, ARBAR, AWDOMAIN, AWSNOOP, AWBAR, AWUNIQUE
//   - R    : RRESP widened from 2 bits to 4 bits (RRESP[3]=IsShared,
//            RRESP[2]=PassDirty; lower two bits keep the AXI semantics)
//   - AC   : snoop address channel  (ACVALID/READY/ADDR/SNOOP/PROT)
//   - CR   : snoop response channel (CRVALID/READY/RESP)
//   - CD   : snoop data channel     (CDVALID/READY/DATA/LAST)
//   - RACK / WACK acknowledge pulses
//   - BROADCAST* interface-control tie-offs (D12, optional)
//
// Clocking-block names (monitor_cb / master_cb / slave_cb) match the AXI
// interface so the parent driver's `vif.master_cb.awvalid <= 1` resolves
// against the same name in the ACE interface.

interface ovip_ace_agent_if(
	input logic aclk,
	input logic aresetn
);
	localparam INPUT_SKEW  = 0;
	localparam OUTPUT_SKEW = 0;

	bit is_master;
	bit is_active;

	// -----------------------------------------------------------------
	// AXI signals -- replicated from ovip_axi_agent_if with the same names.
	// -----------------------------------------------------------------

	// write address channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0]   awid;
	wire [`OVIP_AXI_MAX_ADDR_WIDTH-1:0] awaddr;
	wire [7:0]                          awlen;
	wire [3:0]                          awsize;
	wire [1:0]                          awburst;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] awuser;
	wire                                awvalid;
	wire                                awready;
	wire                                awlock;
	wire [3:0]                          awcache;
	wire [2:0]                          awprot;
	wire [3:0]                          awqos;
	wire [3:0]                          awregion;

	// AW ACE additions
	wire [1:0]                          awdomain;
	wire [2:0]                          awsnoop;
	wire [1:0]                          awbar;
	wire                                awunique;

	// write data channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0]   wid; // only in AXI3
	wire [`OVIP_AXI_MAX_DATA_WIDTH-1:0] wdata;
	wire [`OVIP_AXI_MAX_STRB_WIDTH-1:0] wstrb;
	wire                                wlast;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] wuser;
	wire                                wvalid;
	wire                                wready;

	// write response channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0]   bid;
	wire [1:0]                          bresp;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] buser;
	wire                                bvalid;
	wire                                bready;

	// read address channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0]   arid;
	wire [`OVIP_AXI_MAX_ADDR_WIDTH-1:0] araddr;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] aruser;
	wire [7:0]                          arlen;
	wire [3:0]                          arsize;
	wire [1:0]                          arburst;
	wire                                arvalid;
	wire                                arready;
	wire                                arlock;
	wire [3:0]                          arcache;
	wire [2:0]                          arprot;
	wire [3:0]                          arqos;
	wire [3:0]                          arregion;

	// AR ACE additions
	wire [1:0]                          ardomain;
	wire [3:0]                          arsnoop;
	wire [1:0]                          arbar;

	// read data channel -- RRESP widened from 2 to 4 bits in ACE
	// ([3]=IsShared, [2]=PassDirty). AXI users access only [1:0]
	// via casts to ovip_axi_resp_t; ACE-Lite tie-offs hold [3:2] to 0.
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0]   rid;
	wire [`OVIP_AXI_MAX_DATA_WIDTH-1:0] rdata;
	wire [3:0]                          rresp;
	wire                                rlast;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] ruser;
	wire                                rvalid;
	wire                                rready;

	// -----------------------------------------------------------------
	// ACE-specific channels
	// -----------------------------------------------------------------

	// Snoop address channel (interconnect -> master)
	wire                                  acvalid;
	wire                                  acready;
	wire [`OVIP_ACE_MAX_ACADDR_WIDTH-1:0] acaddr;
	wire [3:0]                            acsnoop;
	wire [2:0]                            acprot;

	// Snoop response channel (master -> interconnect)
	wire                                  crvalid;
	wire                                  crready;
	wire [4:0]                            crresp;

	// Snoop data channel (master -> interconnect)
	wire                                  cdvalid;
	wire                                  cdready;
	wire [`OVIP_ACE_MAX_CDDATA_WIDTH-1:0] cddata;
	wire                                  cdlast;

	// Acknowledge signals (master -> interconnect, single-cycle pulse)
	wire rack;
	wire wack;

	// -----------------------------------------------------------------
	// D12 Interface-control tie-offs. Static; not in any clocking block.
	// Defaults to all-1 so non-D12-aware testbenches see no behavior change.
	// -----------------------------------------------------------------
	bit broadcastinner       = 1'b1;
	bit broadcastouter       = 1'b1;
	bit broadcastcachemaint  = 1'b1;

	// -----------------------------------------------------------------
	// Clocking blocks -- identical names to ovip_axi_agent_if so the
	// inherited drive/sample code resolves under the IF_T parameter.
	// -----------------------------------------------------------------

	clocking monitor_cb @(posedge aclk);
		default input #INPUT_SKEW output #OUTPUT_SKEW;
		input aresetn;

		// AXI: address write channel
		input awid;
		input awaddr;
		input awlen;
		input awsize;
		input awburst;
		input awuser;
		input awlock;
		input awcache;
		input awprot;
		input awqos;
		input awregion;
		input awvalid;
		input awready;

		// AW ACE additions
		input awdomain;
		input awsnoop;
		input awbar;
		input awunique;

		// AXI: write channel
		input wid;
		input wdata;
		input wstrb;
		input wlast;
		input wuser;
		input wvalid;
		input wready;

		// AXI: write response channel
		input bid;
		input bresp;
		input buser;
		input bvalid;
		input bready;

		// AXI: address read channel
		input arid;
		input araddr;
		input aruser;
		input arlen;
		input arsize;
		input arburst;
		input arlock;
		input arcache;
		input arprot;
		input arqos;
		input arregion;
		input arvalid;
		input arready;

		// AR ACE additions
		input ardomain;
		input arsnoop;
		input arbar;

		// AXI: read data channel (rresp is 4-bit in ACE)
		input rid;
		input rdata;
		input rresp;
		input rlast;
		input ruser;
		input rvalid;
		input rready;

		// ACE snoop channels
		input acvalid;
		input acready;
		input acaddr;
		input acsnoop;
		input acprot;

		input crvalid;
		input crready;
		input crresp;

		input cdvalid;
		input cdready;
		input cddata;
		input cdlast;

		input rack;
		input wack;
	endclocking

	clocking master_cb @(posedge aclk);
		default input #INPUT_SKEW output #OUTPUT_SKEW;
		input aresetn;

		// AXI: address write channel
		output awid;
		output awaddr;
		output awlen;
		output awsize;
		output awburst;
		output awlock;
		output awcache;
		output awprot;
		output awqos;
		output awregion;
		output awuser;
		output awvalid;
		input  awready;

		// AW ACE additions (driven by master)
		output awdomain;
		output awsnoop;
		output awbar;
		output awunique;

		// AXI: write channel
		output wid;
		output wdata;
		output wstrb;
		output wlast;
		output wuser;
		output wvalid;
		input  wready;

		// AXI: write response channel
		input  bid;
		input  bresp;
		input  buser;
		input  bvalid;
		output bready;

		// AXI: read address channel
		output arid;
		output araddr;
		output aruser;
		output arlen;
		output arsize;
		output arburst;
		output arlock;
		output arcache;
		output arprot;
		output arqos;
		output arregion;
		output arvalid;
		input  arready;

		// AR ACE additions (driven by master)
		output ardomain;
		output arsnoop;
		output arbar;

		// AXI: read data channel
		input  rid;
		input  rdata;
		input  rresp;
		input  rlast;
		input  ruser;
		input  rvalid;
		output rready;

		// ACE snoop address (interconnect drives, master accepts)
		input  acvalid;
		output acready;
		input  acaddr;
		input  acsnoop;
		input  acprot;

		// ACE snoop response (master drives)
		output crvalid;
		input  crready;
		output crresp;

		// ACE snoop data (master drives)
		output cdvalid;
		input  cdready;
		output cddata;
		output cdlast;

		// ACE acknowledge (master drives)
		output rack;
		output wack;
	endclocking

	clocking slave_cb @(posedge aclk);
		default input #INPUT_SKEW output #OUTPUT_SKEW;
		input aresetn;

		// AXI: address write channel (master drives)
		input  awid;
		input  awaddr;
		input  awlen;
		input  awsize;
		input  awburst;
		input  awlock;
		input  awcache;
		input  awprot;
		input  awqos;
		input  awregion;
		input  awuser;
		input  awvalid;
		output awready;

		// AW ACE additions (master drives, slave samples)
		input  awdomain;
		input  awsnoop;
		input  awbar;
		input  awunique;

		// AXI: write channel
		input  wid;
		input  wdata;
		input  wstrb;
		input  wlast;
		input  wuser;
		input  wvalid;
		output wready;

		// AXI: write response channel (slave drives)
		output bid;
		output bresp;
		output buser;
		output bvalid;
		input  bready;

		// AXI: read address channel (master drives)
		input  arid;
		input  araddr;
		input  aruser;
		input  arlen;
		input  arsize;
		input  arburst;
		input  arlock;
		input  arcache;
		input  arprot;
		input  arqos;
		input  arregion;
		input  arvalid;
		output arready;

		// AR ACE additions (master drives, slave samples)
		input  ardomain;
		input  arsnoop;
		input  arbar;

		// AXI: read data channel (slave drives)
		output rid;
		output rdata;
		output rresp;
		output rlast;
		output ruser;
		output rvalid;
		input  rready;

		// ACE snoop address (slave/interconnect drives)
		output acvalid;
		input  acready;
		output acaddr;
		output acsnoop;
		output acprot;

		// ACE snoop response (master drives, slave samples)
		input  crvalid;
		output crready;
		input  crresp;

		// ACE snoop data (master drives, slave samples)
		input  cdvalid;
		output cdready;
		input  cddata;
		input  cdlast;

		// ACE acknowledge (master drives, slave samples)
		input  rack;
		input  wack;
	endclocking

endinterface : ovip_ace_agent_if

`endif
