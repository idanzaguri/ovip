`ifndef OVIP_AXI_STREAM_DEFINES__SV
`define OVIP_AXI_STREAM_DEFINES__SV

// The compile-time defines of ovip_axi_stream: the wire widths of the
// optional signals and the caps of the randomized delays. Each one can be
// set with +define+<name>=<value>, or in ovip_axi_stream_user_defines.sv when
// OVIP_AXI_STREAM_INCLUDE_USER_DEFINES is defined. The file also includes
// ovip_common_defines.sv, which sets the skews of the clocking blocks. The
// README, "Compile-Time Defines", lists them all.

`ifdef OVIP_AXI_STREAM_INCLUDE_USER_DEFINES
	`include "ovip_axi_stream_user_defines.sv"
`endif

// Wire-level maxima for the optional signals on the AXI-Stream channel. Each
// value sets the *physical wire width* in the interface; the agent's runtime
// `cfg.*_width` fields select how many of those bits are actually active per
// agent (values above the cap are rejected by check_config).
`include "ovip_common_defines.sv"

`ifndef OVIP_AXI_STREAM_MAX_DATA_WIDTH
	`define OVIP_AXI_STREAM_MAX_DATA_WIDTH (128*8)
`endif
`ifndef OVIP_AXI_STREAM_MAX_STRB_WIDTH
	`define OVIP_AXI_STREAM_MAX_STRB_WIDTH (`OVIP_AXI_STREAM_MAX_DATA_WIDTH/8)
`endif
`ifndef OVIP_AXI_STREAM_MAX_KEEP_WIDTH
	`define OVIP_AXI_STREAM_MAX_KEEP_WIDTH (`OVIP_AXI_STREAM_MAX_DATA_WIDTH/8)
`endif
`ifndef OVIP_AXI_STREAM_MAX_ID_WIDTH
	`define OVIP_AXI_STREAM_MAX_ID_WIDTH 8
`endif
`ifndef OVIP_AXI_STREAM_MAX_DEST_WIDTH
	`define OVIP_AXI_STREAM_MAX_DEST_WIDTH 8
`endif
`ifndef OVIP_AXI_STREAM_MAX_USER_WIDTH
	`define OVIP_AXI_STREAM_MAX_USER_WIDTH 1024
`endif

// Soft-default delay caps used by ovip_axi_stream_trans constraints. These set
// the upper bound of the default-randomized range for each kind of delay so a
// randomized item doesn't generate huge timing gaps out of the box.
// Override per call via `with { ... }`, or globally with +define+<name>=<n>.
// A bare `tr.randomize()` is not enough for an item that goes on a bus: the
// item does not know the agent's configuration, so id, dest and the data,
// qualifier and user bits are random over the MAX widths above. Keep them
// inside the configured widths (README, "Writing sequences").
`ifndef OVIP_AXI_STREAM_DELAY_BETWEEN_BEATS_MAX
	`define OVIP_AXI_STREAM_DELAY_BETWEEN_BEATS_MAX 30
`endif
`ifndef OVIP_AXI_STREAM_DELAY_UNTIL_NEXT_TRANS_MAX
	`define OVIP_AXI_STREAM_DELAY_UNTIL_NEXT_TRANS_MAX 30
`endif

`endif
