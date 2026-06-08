`ifndef OVIP_AXI_STREAM_MACROS__SV
`define OVIP_AXI_STREAM_MACROS__SV

// Same idiom as ovip_axi: fork-into-first-of with explicit disable, used by
// the monitor to multiplex reset handling against the long-running channel
// checkers.
`ifndef BEGIN_FIRST_OF
	`define BEGIN_FIRST_OF fork begin fork
	`define END_FIRST_OF   join_any disable fork; end join
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
