`ifndef OVIP_ACE_BASE_MASTER_SEQUENCE__SV
`define OVIP_ACE_BASE_MASTER_SEQUENCE__SV

// Convenience base for ACE master-side stimulus. Inherits the get/put
// bookkeeping (send / wait_for_responses) from ovip_axi_base_master_sequence
// and adds builders that stamp the ACE additions (AxDOMAIN / AxSNOOP / AxBAR)
// onto an ovip_ace_trans.
//
// The builders return the trans without sending it, so a test can tweak fields
// (id, awunique, ...) before calling send(tr). See examples/ovip_ace for use.

class ovip_ace_base_master_sequence extends ovip_axi_base_master_sequence;

	`uvm_object_utils(ovip_ace_base_master_sequence)

	function new(string name = "ovip_ace_base_master_sequence");
		super.new(name);
	endfunction

	// Build an ACE read. `snoop` is ARSNOOP[3:0]; for ReadNoSnoop/ReadOnce use
	// 4'b0000 and pick the domain (NSH/SYS -> ReadNoSnoop, ISH/OSH -> ReadOnce).
	virtual function ovip_ace_trans make_read(
		ovip_axi_addr_t   addr,
		bit [3:0]         snoop,
		ovip_ace_domain_t domain,
		ovip_axi_size_t   size = OVIP_AXI_SIZE_4B,
		bit [7:0]         len  = 0
	);
		ovip_ace_trans tr = ovip_ace_trans::type_id::create("ace_rd");
		tr.tr_type   = OVIP_AXI_READ_TRANS;
		tr.direction = OVIP_ACE_INITIATING;
		tr.addr      = addr;
		tr.len       = len;
		tr.size      = size;
		tr.burst     = OVIP_AXI_BURST_INCR;
		tr.domain    = domain;
		tr.snoop     = snoop;
		tr.bar       = OVIP_ACE_BAR_NORMAL_RESPECT;
		return tr;
	endfunction : make_read

	// Build an ACE write. `snoop` carries AWSNOOP in its low 3 bits (the MSB is
	// ignored on the wire). Provide one data/strb beat per (len+1).
	virtual function ovip_ace_trans make_write(
		ovip_axi_addr_t     addr,
		bit [3:0]           snoop,
		ovip_ace_domain_t   domain,
		ovip_axi_data_t     data_beats[$],
		ovip_axi_strb_t     strb_beats[$],
		ovip_axi_size_t     size = OVIP_AXI_SIZE_4B
	);
		ovip_ace_trans tr = ovip_ace_trans::type_id::create("ace_wr");
		tr.tr_type    = OVIP_AXI_WRITE_TRANS;
		tr.direction  = OVIP_ACE_INITIATING;
		tr.addr       = addr;
		tr.len        = data_beats.size() - 1;
		tr.size       = size;
		tr.burst      = OVIP_AXI_BURST_INCR;
		tr.domain     = domain;
		tr.snoop      = snoop;
		tr.bar        = OVIP_ACE_BAR_NORMAL_RESPECT;
		tr.data_beats = data_beats;
		tr.strb_beats = strb_beats;
		return tr;
	endfunction : make_write

endclass : ovip_ace_base_master_sequence

`endif
