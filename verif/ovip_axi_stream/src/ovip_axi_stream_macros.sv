`ifndef OVIP_AXI_STREAM_MACROS__SV
`define OVIP_AXI_STREAM_MACROS__SV

// Family-wide fork idiom comes from ovip_common; this VIP uses the prefixed
// `OVIP_BEGIN_FIRST_OF / `OVIP_END_FIRST_OF form internally. The unprefixed
// aliases below are DEPRECATED and kept only so existing user code compiles.
`include "ovip_common_macros.sv"
`ifndef BEGIN_FIRST_OF
	`define BEGIN_FIRST_OF `OVIP_BEGIN_FIRST_OF
	`define END_FIRST_OF   `OVIP_END_FIRST_OF
`endif

// Bounds-check a value against the runtime-configured signal width. Used by
// the master driver before sampling a transaction onto the bus.
`define OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH(tag, signal, value, width, err_flag) \
begin \
	if((value) >> (width)) \
	begin \
		`uvm_warning(tag, $sformatf("Argument 0x%0x exceeds the configured width of %s (%0d bits)", value, signal, width)) \
		err_flag = 1; \
	end \
end

// XZ check helper used inline in the monitor.
`define OVIP_AXI_STREAM_MON_XZ_CHECK(signal, name) \
	if(^(vif.monitor_cb.signal) === 1'bx) \
		`uvm_error("AXIS_MON/XZ_CHECK", $sformatf("Signal %s contains X's or Z's", `"name`"))

`endif
