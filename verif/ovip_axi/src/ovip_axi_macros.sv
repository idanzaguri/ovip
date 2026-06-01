`ifndef OVIP_AXI_MACROS__SV
`define OVIP_AXI_MACROS__SV

`define BEGIN_FIRST_OF fork begin fork
`define END_FIRST_OF join_any disable fork; end join


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
