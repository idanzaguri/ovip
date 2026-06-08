`ifndef OVIP_AXI_STREAM_BASE_SLAVE_SEQUENCE__SV
`define OVIP_AXI_STREAM_BASE_SLAVE_SEQUENCE__SV

// Canonical base for receiver-side sequences. There is no item-port traffic
// to the slave driver (TREADY is pattern-driven), so the base just pulls
// monitor-captured packets off `response_req_port` and exposes two hooks:
//   - process_request(req) -- called once per captured packet; the default
//     is a no-op. Override to inspect the packet, push a new TREADY pattern
//     into the driver via p_sequencer.slave_drv.put_tready_pattern(...), or
//     react any other way to incoming traffic.
//
// The base body() runs forever; the test stops the run via objection
// management, not by exiting the sequence.
class ovip_axi_stream_base_slave_sequence extends uvm_sequence#(ovip_axi_stream_trans);
	`uvm_object_utils(ovip_axi_stream_base_slave_sequence)
	`uvm_declare_p_sequencer(ovip_axi_stream_slave_sequencer)

	function new(string name = "ovip_axi_stream_base_slave_sequence");
		super.new(name);
	endfunction : new

	virtual task body();
		ovip_axi_stream_trans req;
		forever
		begin
			p_sequencer.response_req_port.get(req);
			process_request(req);
		end
	endtask : body

	virtual task process_request(ovip_axi_stream_trans req);
		// no-op by default
	endtask : process_request

endclass : ovip_axi_stream_base_slave_sequence

`endif
