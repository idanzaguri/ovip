`ifndef OVIP_APB_AGENT_IF__SV
`define OVIP_APB_AGENT_IF__SV

`include "ovip_apb_defines.sv"

// APB is a point-to-point requester/completer interface: the Requester drives
// the select, address, and write payload; the Completer drives PREADY, the
// read data, and the optional error response. One PSEL per interface (the
// spec's PSELx decoding across multiple completers is interconnect territory,
// not agent territory). Signals are present on the wire at their MAX width;
// the agent's `cfg.addr_width` / `cfg.data_width` select how many bits are
// live, and the monitor/drivers gate optional-signal behavior on `cfg.*_en`.
interface ovip_apb_agent_if(
	input logic pclk,
	input logic presetn
);

	// Requester-driven.
	wire                                psel;
	wire                                penable;
	wire [`OVIP_APB_MAX_ADDR_WIDTH-1:0] paddr;
	wire                                pwrite;
	wire [`OVIP_APB_MAX_DATA_WIDTH-1:0] pwdata;
	wire [`OVIP_APB_MAX_STRB_WIDTH-1:0] pstrb;   // APB4
	wire [2:0]                          pprot;   // APB4

	// Completer-driven.
	wire                                pready;
	wire [`OVIP_APB_MAX_DATA_WIDTH-1:0] prdata;
	wire                                pslverr;

	clocking monitor_cb @(posedge pclk);
		default input #1step output #0;
		input presetn;
		input psel, penable, paddr, pwrite, pwdata, pstrb, pprot;
		input pready, prdata, pslverr;
	endclocking

	// Requester side -- drives everything except PREADY/PRDATA/PSLVERR.
	clocking master_cb @(posedge pclk);
		default input #1step output #0;
		input  presetn;
		input  pready, prdata, pslverr;
		output psel, penable, paddr, pwrite, pwdata, pstrb, pprot;
	endclocking

	// Completer side -- drives only PREADY/PRDATA/PSLVERR.
	clocking slave_cb @(posedge pclk);
		default input #1step output #0;
		input  presetn;
		input  psel, penable, paddr, pwrite, pwdata, pstrb, pprot;
		output pready, prdata, pslverr;
	endclocking

endinterface : ovip_apb_agent_if

`endif
