`ifndef OVIP_APB_MACROS__SV
`define OVIP_APB_MACROS__SV

// Family-wide fork idiom (`OVIP_BEGIN_FIRST_OF / `OVIP_END_FIRST_OF) comes
// from ovip_common; this VIP uses the prefixed form exclusively.
`include "ovip_common_macros.sv"

// Bounds-check a value against the runtime-configured signal width. Used by
// the master driver before sampling a transaction onto the bus.
`define OVIP_APB_CHECK_VALUE_VS_SIGNAL_WIDTH(tag, signal, value, width, err_flag) \
begin \
	if((value) >> (width)) \
	begin \
		`uvm_warning(tag, $sformatf("Argument 0x%0x exceeds the configured width of %s (%0d bits)", value, signal, width)) \
		err_flag = 1; \
	end \
end

// XZ check helper used inline in the monitor.
`define OVIP_APB_MON_XZ_CHECK(signal, name) \
	if(^(vif.monitor_cb.signal) === 1'bx) \
		`uvm_error({MESSAGE_TAG, "APB_MON/XZ_CHECK"}, $sformatf("Signal %s contains X's or Z's", `"name`"))

`endif
