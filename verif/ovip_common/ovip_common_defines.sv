`ifndef OVIP_COMMON_DEFINES__SV
`define OVIP_COMMON_DEFINES__SV

// Clocking-block skews of every OVIP interface: the
// `default input #... output #...;` of the monitor_cb, master_cb and slave_cb
// of ovip_apb, ovip_axi, ovip_axi_stream and ovip_ace. Override both, or
// either, on the compile line:
//     +define+OVIP_INPUT_SKEW=0 +define+OVIP_OUTPUT_SKEW=0
`ifndef OVIP_INPUT_SKEW
	`define OVIP_INPUT_SKEW 1step
`endif
`ifndef OVIP_OUTPUT_SKEW
	`define OVIP_OUTPUT_SKEW 0
`endif

`endif // OVIP_COMMON_DEFINES__SV
