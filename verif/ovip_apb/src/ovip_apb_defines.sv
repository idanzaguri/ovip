`ifndef OVIP_APB_DEFINES__SV
`define OVIP_APB_DEFINES__SV

`ifdef OVIP_APB_INCLUDE_USER_DEFINES
	`include "ovip_apb_user_defines.sv"
`endif

// Wire-level maxima for the APB signals. Each value sets the *physical wire
// width* in the interface; the agent's runtime `cfg.*_width` fields select how
// many of those bits are actually active per agent (values above the cap are
// rejected by check_config). The spec caps PADDR at 32 bits and PWDATA/PRDATA
// at 32 bits (8, 16, or 32), so the defaults are already the spec maxima.
`ifndef OVIP_APB_MAX_ADDR_WIDTH
	`define OVIP_APB_MAX_ADDR_WIDTH 32
`endif
`ifndef OVIP_APB_MAX_DATA_WIDTH
	`define OVIP_APB_MAX_DATA_WIDTH 32
`endif
`ifndef OVIP_APB_MAX_STRB_WIDTH
	`define OVIP_APB_MAX_STRB_WIDTH (`OVIP_APB_MAX_DATA_WIDTH/8)
`endif

// Soft-default caps used by ovip_apb_trans constraints. These bound the
// default-randomized range of each timing knob so a bare `tr.randomize()`
// doesn't generate huge gaps out of the box. Override per call via
// `with { ... }`, or globally with +define+<name>=<n>.
`ifndef OVIP_APB_WAIT_STATES_MAX
	`define OVIP_APB_WAIT_STATES_MAX 15
`endif
`ifndef OVIP_APB_DELAY_UNTIL_NEXT_TRANS_MAX
	`define OVIP_APB_DELAY_UNTIL_NEXT_TRANS_MAX 30
`endif

`endif
