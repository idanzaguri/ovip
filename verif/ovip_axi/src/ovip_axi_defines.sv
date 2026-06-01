`ifndef OVIP_AXI_DEFINES__SV
`define OVIP_AXI_DEFINES__SV

`ifdef OVIP_AXI_INCLUDE_USER_DEFINES
	`include "ovip_axi_user_defines.sv"
`endif

`ifndef OVIP_AXI_MAX_ID_WIDTH
	`define OVIP_AXI_MAX_ID_WIDTH   16
`endif
`ifndef OVIP_AXI_MAX_ADDR_WIDTH
	`define OVIP_AXI_MAX_ADDR_WIDTH 64
`endif
`ifndef OVIP_AXI_MAX_USER_WIDTH
	`define OVIP_AXI_MAX_USER_WIDTH 32
`endif
`ifndef OVIP_AXI_MAX_DATA_WIDTH
	`define OVIP_AXI_MAX_DATA_WIDTH (128*8)
`endif
`ifndef OVIP_AXI_MAX_STRB_WIDTH
	`define OVIP_AXI_MAX_STRB_WIDTH (`OVIP_AXI_MAX_DATA_WIDTH/8)
`endif

// ---------------------------------------------------------------------------
// Soft-default delay limits used by ovip_axi_trans constraints. These set the
// *upper bound* of the default-randomized range for each kind of delay so a
// bare `tr.randomize()` doesn't generate huge timing gaps out of the box.
// Override per call via `with { ... }`, or globally with +define+<name>=<n>.
// ---------------------------------------------------------------------------
`ifndef OVIP_AXI_TRANS_RD_DATA_DELAY_MAX
	`define OVIP_AXI_TRANS_RD_DATA_DELAY_MAX 30  // slave-side per-beat read data delay
`endif
`ifndef OVIP_AXI_TRANS_WR_DATA_DELAY_MAX
	`define OVIP_AXI_TRANS_WR_DATA_DELAY_MAX 30  // master-side per-beat write data delay
`endif
`ifndef OVIP_AXI_TRANS_WR_RESP_DELAY_MAX
	`define OVIP_AXI_TRANS_WR_RESP_DELAY_MAX 30  // slave-side bresp delay
`endif
`ifndef OVIP_AXI_TRANS_ADDR_PHASE_DELAY_MAX
	`define OVIP_AXI_TRANS_ADDR_PHASE_DELAY_MAX 30  // master-side: addr_phase_delay (BEFORE_ADDR data-before-address gap)
`endif
`ifndef OVIP_AXI_TRANS_NEXT_ADDR_DELAY_MAX
	`define OVIP_AXI_TRANS_NEXT_ADDR_DELAY_MAX  30  // master-side: delay_until_next_addr
`endif
`ifndef OVIP_AXI_TRANS_NEXT_DATA_DELAY_MAX
	`define OVIP_AXI_TRANS_NEXT_DATA_DELAY_MAX  30  // master-side: delay_until_next_data
`endif

`endif
