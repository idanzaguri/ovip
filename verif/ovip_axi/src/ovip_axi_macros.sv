`ifndef OVIP_AXI_MACROS__SV
`define OVIP_AXI_MACROS__SV

// Family-wide fork idiom comes from ovip_common; this VIP uses the prefixed
// `OVIP_BEGIN_FIRST_OF / `OVIP_END_FIRST_OF form internally. The unprefixed
// aliases below are DEPRECATED and kept only so existing user code compiles.
`include "ovip_common_macros.sv"
`ifndef BEGIN_FIRST_OF
	`define BEGIN_FIRST_OF `OVIP_BEGIN_FIRST_OF
	`define END_FIRST_OF   `OVIP_END_FIRST_OF
`endif


`define OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH(tag, signal, value, width, err_flag)\
begin\
if((value)>>(width))\
begin\
	`uvm_warning(tag, $sformatf("Argument 0x%0x exceeds the configured width of %s (%0d bits)", value, signal, width))\
	err_flag = 1;\
end\
end


`define OVIP_AXI_MON_XZ_CHECK(signal, name)\
	if(^(vif.monitor_cb.signal) === 1'bx)\
		`uvm_error("AXI_MON/XZ_CHECK", $sformatf("Signal %s contains X's or Z's`",`"name`"))


`define OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(field, name)\
begin\
	if(sampling_array[0].field != sampling_array[1].field)\
		`uvm_error("AXI_MON/STABILITY_CHECK", $sformatf("Signal %s was changed before being sampled!",`"name`"))\
end

`endif
