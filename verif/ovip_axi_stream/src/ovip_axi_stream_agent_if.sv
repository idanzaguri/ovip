`ifndef OVIP_AXI_STREAM_AGENT_IF__SV
`define OVIP_AXI_STREAM_AGENT_IF__SV

`include "ovip_axi_stream_defines.sv"

// AXI-Stream is a single point-to-point channel: one Transmitter drives data
// and qualifiers, one Receiver drives tready. All signals except aclk/aresetn/
// tvalid are optional per the spec; absent signals are still present on the
// wire here at their MAX width but the agent's `cfg.*_width` selects how many
// of those bits are actually live, and the monitor/driver gate per-signal
// behavior on `cfg.*_en` / `cfg.protocol_type`.
interface ovip_axi_stream_agent_if(
	input logic aclk,
	input logic aresetn
);

	// Mandatory handshake.
	wire tvalid;
	wire tready;

	// Optional payload + byte qualifiers + packet boundary.
	wire [`OVIP_AXI_STREAM_MAX_DATA_WIDTH-1:0] tdata;
	wire [`OVIP_AXI_STREAM_MAX_STRB_WIDTH-1:0] tstrb;
	wire [`OVIP_AXI_STREAM_MAX_KEEP_WIDTH-1:0] tkeep;
	wire                                       tlast;

	// Optional source / destination / sideband.
	wire [`OVIP_AXI_STREAM_MAX_ID_WIDTH  -1:0] tid;
	wire [`OVIP_AXI_STREAM_MAX_DEST_WIDTH-1:0] tdest;
	wire [`OVIP_AXI_STREAM_MAX_USER_WIDTH-1:0] tuser;

	// AXI5-Stream wake-up signaling (issue B addition).
	wire twakeup;

	clocking monitor_cb @(posedge aclk);
		default input #1step output #0;
		input aresetn;
		input tvalid, tready;
		input tdata, tstrb, tkeep, tlast;
		input tid, tdest, tuser;
		input twakeup;
	endclocking

	// Transmitter side -- drives everything except tready.
	clocking master_cb @(posedge aclk);
		default input #1step output #0;
		input  aresetn;
		input  tready;
		output tvalid;
		output tdata, tstrb, tkeep, tlast;
		output tid, tdest, tuser;
		output twakeup;
	endclocking

	// Receiver side -- drives only tready.
	clocking slave_cb @(posedge aclk);
		default input #1step output #0;
		input  aresetn;
		input  tvalid;
		input  tdata, tstrb, tkeep, tlast;
		input  tid, tdest, tuser;
		input  twakeup;
		output tready;
	endclocking

endinterface : ovip_axi_stream_agent_if

`endif
