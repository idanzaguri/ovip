// Out-of-order read responses.
//
// What this shows:
//   - The master issues 4 reads in order, with IDs 0..3, to four different
//     addresses. Each address has been pre-seeded with a distinct value.
//   - A custom slave sequence assigns a per-ID read-data delay so that the
//     LAST-issued read becomes ready FIRST. With `rd_out_of_order_depth = 4`,
//     the slave returns responses in reverse-issued order (3, 2, 1, 0).
//   - A simple subscriber on the master agent's analysis port logs each
//     response as it arrives, so the log makes the out-of-order completion
//     visible.
//   - Round-trip checking: each completed read is compared against the
//     value placed in memory at its address; mismatches raise a UVM_ERROR.
//
// Knobs demonstrated:
//   - `cfg.rd_out_of_order_depth`         (slave-side reorder window)
//   - `cfg.rd_scheduling_alg`             (per-cycle pick among ready set)
//   - per-transaction `data_delay[$]`     (set by `set_read_trans_delays`)

`timescale 1ns/1ps

package ooo_reads_example_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_pkg::*;
	`include "uvm_macros.svh"

	localparam int N_READS = 4;

	// Slave: memory loopback with per-ID read delay that reverses response order.
	class ooo_slave_seq extends ovip_axi_base_slave_sequence;
		`uvm_object_utils(ooo_slave_seq)
		`uvm_declare_p_sequencer(ovip_axi_slave_sequencer)

		function new(string name = "ooo_slave_seq");
			super.new(name);
		endfunction

		virtual function void set_read_trans_delays(ovip_axi_trans tr);
			// Per-ID delay: id=3 ripens first (0 cycles), id=0 last. The 4-cycle
			// gap dominates the 1-cycle stagger between ARs, so dispatch is 3,2,1,0.
			int d = int'(N_READS - 1 - tr.id) * 4;
			tr.data_delay.delete();
			tr.data_delay.push_back(d);
			repeat(tr.len) tr.data_delay.push_back(0);
			`uvm_info("OOO_SLV", $sformatf("id=%0d -> data_delay[0]=%0d", tr.id, d), UVM_LOW)
		endfunction
	endclass


	// Master: 4 reads, IDs 0..3, addresses 0x00..0x30, issued back-to-back.
	class ooo_master_seq extends ovip_axi_base_master_sequence;
		`uvm_object_utils(ooo_master_seq)
		`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

		function new(string name = "ooo_master_seq");
			super.new(name);
		endfunction

		virtual task body();
			for(int ii = 0; ii < N_READS; ii++) begin
				ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("rd_%0d", ii));
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.addr    = ii * 'h10;
				tr.id      = ii;
				tr.len     = 0;
				tr.size    = OVIP_AXI_SIZE_4B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				`uvm_info("OOO_MST", $sformatf("issuing rd id=%0d addr=0x%0h at t=%0t", tr.id, tr.addr, $time), UVM_LOW)
				send(tr);
			end
			wait_for_responses();
		endtask
	endclass


	// Subscriber: log each completed read in arrival order, check it round-trips.
	class read_response_logger extends uvm_subscriber#(ovip_axi_trans);
		`uvm_component_utils(read_response_logger)

		ovip_mem mem;

		function new(string name = "read_response_logger", uvm_component parent);
			super.new(name, parent);
		endfunction

		virtual function void write(ovip_axi_trans t);
			if(t.tr_type != OVIP_AXI_READ_TRANS) return;
			`uvm_info("OOO_LOG", $sformatf("got resp id=%0d addr=0x%0h data=0x%0h at t=%0t",
			t.id, t.addr, t.data_beats[0], $time), UVM_LOW)
			if(t.data_beats[0] != mem.read(t.addr))
				`uvm_error("OOO_DATA", $sformatf("id=%0d addr=0x%0h: read 0x%0h, expected 0x%0h",
			t.id, t.addr, t.data_beats[0], mem.read(t.addr)))
		endfunction
	endclass


	class ooo_test extends uvm_test;
		`uvm_component_utils(ooo_test)

		ovip_axi_agent_config master_cfg, slave_cfg;
		ovip_axi_agent        master_agent, slave_agent;
		ovip_mem              mem;
		ooo_slave_seq         slave_seq;
		read_response_logger  logger;

		function new(string name = "ooo_test", uvm_component parent = null);
			super.new(name, parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			mem = ovip_mem::type_id::create("mem", this);

			master_cfg = ovip_axi_agent_config::type_id::create("master_cfg");
			master_cfg.agent_type = OVIP_MASTER_AGENT;
			master_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_8B;
			master_cfg.addr_width = 32;
			master_cfg.is_active  = UVM_ACTIVE;
			// Master outstanding-rd queue: must hold all four ARs back-to-back.
			master_cfg.rd_out_of_order_depth = N_READS;
			master_cfg.num_outstanding_rd_transactions = N_READS;

			slave_cfg = ovip_axi_agent_config::type_id::create("slave_cfg");
			slave_cfg.agent_type = OVIP_SLAVE_AGENT;
			slave_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_8B;
			slave_cfg.addr_width = 32;
			slave_cfg.is_active  = UVM_ACTIVE;
			// Slave reorder window: 1 = in-order, N = up to N may overtake.
			slave_cfg.rd_out_of_order_depth = N_READS;
			slave_cfg.rd_scheduling_alg     = OVIP_AXI_SCH_ALG_ALWAYS_FIRST;
			slave_cfg.num_outstanding_rd_transactions = N_READS;

			master_agent = ovip_axi_agent::type_id::create("master_agent", this);
			master_agent.cfg = master_cfg;
			slave_agent = ovip_axi_agent::type_id::create("slave_agent", this);
			slave_agent.cfg = slave_cfg;

			slave_seq = ooo_slave_seq::type_id::create("slave_seq");
			slave_seq.mem = mem;

			logger = read_response_logger::type_id::create("logger", this);
			logger.mem = mem;
		endfunction

		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			master_agent.mon.analysis_port.connect(logger.analysis_export);
		endfunction

		// Pre-seed memory with distinct values.
		function void end_of_elaboration_phase(uvm_phase phase);
			super.end_of_elaboration_phase(phase);
			for(int ii = 0; ii < N_READS; ii++)
				mem.write(ii * 'h10, 32'hCAFE_0000 + ii);
		endfunction

		virtual task run_phase(uvm_phase phase);
			super.run_phase(phase);
			fork
				slave_seq.start(slave_agent.sqr);
			join_none
		endtask

		virtual task reset_phase(uvm_phase phase);
			super.reset_phase(phase);
			phase.raise_objection(this);
			@(posedge master_agent.mon.vif.aresetn);
			phase.drop_objection(this);
		endtask

		virtual task main_phase(uvm_phase phase);
			ooo_master_seq seq = ooo_master_seq::type_id::create("seq");
			super.main_phase(phase);
			phase.raise_objection(this);
			seq.start(master_agent.sqr);
			#100ns; // settle window so the last analysis_port write lands before final_phase

			phase.drop_objection(this);
		endtask
	endclass

endpackage : ooo_reads_example_pkg


module tb_top;
import uvm_pkg::*;
import ooo_reads_example_pkg::*;

logic clk = 0;
logic rst_n = 0;
always #500ps clk = ~clk;   // 1 GHz

ovip_axi_agent_if axi_if(clk, rst_n);

initial begin
	uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.master_agent*", "vif", axi_if);
	uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.slave_agent*",  "vif", axi_if);
	run_test("ooo_test");
end

initial begin
	repeat(2) @(posedge clk);
	rst_n = 1;
end
endmodule : tb_top
