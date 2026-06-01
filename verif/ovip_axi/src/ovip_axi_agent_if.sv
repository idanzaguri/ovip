`ifndef OVIP_AXI_AGENT_IF__SV
`define OVIP_AXI_AGENT_IF__SV

interface ovip_axi_agent_if(
	input logic aclk,
	input logic aresetn
);
	localparam INPUT_SKEW  = 0;
	localparam OUTPUT_SKEW = 0;

	bit is_master;
	bit is_active;

	// write address channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0] awid;
	wire [`OVIP_AXI_MAX_ADDR_WIDTH-1:0] awaddr;
	wire [7:0] awlen;
	wire [3:0] awsize;
	wire [1:0] awburst;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] awuser;
	wire awvalid;
	wire awready;
	wire awlock;
	wire [3:0] awcache;
	wire [2:0] awprot;
	wire [3:0] awqos;
	wire [3:0] awregion;

	// write data channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0] wid; // only in AXI3
	wire [`OVIP_AXI_MAX_DATA_WIDTH-1:0] wdata;
	wire [`OVIP_AXI_MAX_STRB_WIDTH-1:0] wstrb;
	wire wlast;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] wuser;
	wire wvalid;
	wire wready;

	//write response channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0] bid;
	wire [1:0] bresp;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] buser;
	wire bvalid;
	wire bready;

	// read address channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0] arid;
	wire [`OVIP_AXI_MAX_ADDR_WIDTH-1:0] araddr;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] aruser;
	wire [7:0] arlen;
	wire [3:0] arsize;
	wire [1:0] arburst;
	wire arvalid;
	wire arready;
	wire arlock;
	wire [3:0] arcache;
	wire [2:0] arprot;
	wire [3:0] arqos;
	wire [3:0] arregion;

	//read data channel
	wire [`OVIP_AXI_MAX_ID_WIDTH-1:0] rid;
	wire [`OVIP_AXI_MAX_DATA_WIDTH-1:0] rdata;
	wire [1:0] rresp;
	wire rlast;
	wire [`OVIP_AXI_MAX_USER_WIDTH-1:0] ruser;
	wire rvalid;
	wire rready;

	/*
	assign arvalid = (is_master & is_active & ~aresetn)? 1'b0 : 1'bz;
	assign awvalid = (is_master & is_active & ~aresetn)? 1'b0 : 1'bz;
	assign wvalid  = (is_master & is_active & ~aresetn)? 1'b0 : 1'bz;
	assign rvalid  = (~is_master & is_active & ~aresetn)? 1'b0 : 1'bz;
	assign bvalid  = (~is_master & is_active & ~aresetn)? 1'b0 : 1'bz;
	*/

	clocking monitor_cb @(posedge aclk);
		default input #INPUT_SKEW output #OUTPUT_SKEW;
		input aresetn;

		// address write channel
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

		// write channel
		input wid;
		input wdata;
		input wstrb;
		input wlast;
		input wuser;
		input wvalid;
		input wready;

		// write response channel
		input bid;
		input bresp;
		input buser;
		input bvalid;
		input bready;

		// address read channel
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

		// read data channel
		input rid;
		input rdata;
		input rresp;
		input rlast;
		input ruser;
		input rvalid;
		input rready;
	endclocking

	clocking master_cb @(posedge aclk);
		default input #INPUT_SKEW output #OUTPUT_SKEW;
		input aresetn;

		// address write channel
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
		input awready;

		// write channel
		output wid;
		output wdata;
		output wstrb;
		output wlast;
		output wuser;
		output wvalid;
		input wready;

		//write response channel
		input bid;
		input bresp;
		input buser;
		input bvalid;
		output bready;

		// read address channel
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
		input arready;

		//read data channel
		input rid;
		input rdata;
		input rresp;
		input rlast;
		input ruser;
		input rvalid;
		output rready;
	endclocking

	clocking slave_cb @(posedge aclk);
		default input #INPUT_SKEW output #OUTPUT_SKEW;
		input aresetn;

		// address write channel
		input awid;
		input awaddr;
		input awlen;
		input awsize;
		input awburst;
		input awlock;
		input awcache;
		input awprot;
		input awqos;
		input awregion;
		input awuser;
		input awvalid;
		output awready;

		// write channel
		input wid;
		input wdata;
		input wstrb;
		input wlast;
		input wuser;
		input wvalid;
		output wready;

		//write response channel
		output bid;
		output bresp;
		output buser;
		output bvalid;
		input bready;

		// read address channel
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
		output arready;

		//read data channel
		output rid;
		output rdata;
		output rresp;
		output rlast;
		output ruser;
		output rvalid;
		input rready;
	endclocking

endinterface : ovip_axi_agent_if

`endif
