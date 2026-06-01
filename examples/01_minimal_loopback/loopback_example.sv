// Minimal hello-world for the ovip_axi VIP.
//
// What this shows:
//   - A master + slave agent instantiated on the same interface.
//   - A small master sequence that sends 4 writes then 4 reads.
//   - The slave sequence backs the bus with `ovip_mem` (memory loopback).
//   - At end-of-test, every read returns the value that was written, so the
//     UVM Report Summary shows 0 errors / 0 fatals.
//
// Nothing in this file is required from the in-repo testbench
// (`verif/ovip_axi_testbench/`). Everything that comes from outside is the
// VIP packages and UVM-1.2.

`timescale 1ns/1ps

package loopback_example_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_pkg::*;
	`include "uvm_macros.svh"


	// The master sequence: 4 writes, then 4 reads, both at the same addresses.
	class loopback_master_seq extends ovip_axi_base_master_sequence;
		`uvm_object_utils(loopback_master_seq)
		`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

		function new(string name = "loopback_master_seq");
			super.new(name);
		endfunction

		virtual task body();
			// Four single-beat writes at consecutive aligned addresses.
			for(int ii = 0; ii < 4; ii++) begin
				ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("wr_%0d", ii));
				tr.tr_type    = OVIP_AXI_WRITE_TRANS;
				tr.addr       = ii * 'h10;
				tr.id         = ii;
				tr.len        = 0;                 // single-beat
				tr.size       = OVIP_AXI_SIZE_4B;
				tr.burst      = OVIP_AXI_BURST_INCR;
				tr.data_beats = '{32'hDEAD_0000 + ii};
				tr.strb_beats = '{8'h0F};          // 4 active byte lanes
				send(tr);
			end

			// Four matching reads.
			for(int ii = 0; ii < 4; ii++) begin
				ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("rd_%0d", ii));
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.addr    = ii * 'h10;
				tr.id      = ii;
				tr.len     = 0;
				tr.size    = OVIP_AXI_SIZE_4B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				send(tr);
			end

			wait_for_responses();
		endtask
	endclass


	// The test: bring up the two agents, kick off the slave responder (default
	// base_slave_sequence does memory-backed loopback), then run the master seq.
	class loopback_test extends uvm_test;
		`uvm_component_utils(loopback_test)

		ovip_axi_agent_config master_cfg, slave_cfg;
		ovip_axi_agent        master_agent, slave_agent;
		ovip_mem              mem;
		ovip_axi_base_slave_sequence slave_seq;

		function new(string name = "loopback_test", uvm_component parent = null);
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

			slave_cfg = ovip_axi_agent_config::type_id::create("slave_cfg");
			slave_cfg.agent_type = OVIP_SLAVE_AGENT;
			slave_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_8B;
			slave_cfg.addr_width = 32;
			slave_cfg.is_active  = UVM_ACTIVE;

			master_agent = ovip_axi_agent::type_id::create("master_agent", this);
			master_agent.cfg = master_cfg;
			slave_agent = ovip_axi_agent::type_id::create("slave_agent", this);
			slave_agent.cfg = slave_cfg;

			slave_seq = ovip_axi_base_slave_sequence::type_id::create("slave_seq");
			slave_seq.mem = mem;
		endfunction

		// Slave responder lives for the run phase as a background process.
		virtual task run_phase(uvm_phase phase);
			super.run_phase(phase);
			fork
				slave_seq.start(slave_agent.sqr);
			join_none
		endtask

		// Wait for reset to deassert before starting stimulus.
		virtual task reset_phase(uvm_phase phase);
			super.reset_phase(phase);
			phase.raise_objection(this);
			@(posedge master_agent.mon.vif.aresetn);
			phase.drop_objection(this);
		endtask

		virtual task main_phase(uvm_phase phase);
			loopback_master_seq seq = loopback_master_seq::type_id::create("seq");
			super.main_phase(phase);
			phase.raise_objection(this);
			seq.start(master_agent.sqr);
			phase.drop_objection(this);
		endtask
	endclass

endpackage : loopback_example_pkg


module tb_top;
import uvm_pkg::*;
import loopback_example_pkg::*;

logic clk = 0;
logic rst_n = 0;
always #500ps clk = ~clk;   // 1 GHz

// Master and slave share a single interface (no DUT between them -- the
// loopback runs entirely inside the VIP).
ovip_axi_agent_if axi_if(clk, rst_n);

initial begin
	uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.master_agent*", "vif", axi_if);
	uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.slave_agent*",  "vif", axi_if);
	run_test("loopback_test");
end

// Reset pulse: low for a few cycles, then high for the rest of the run.
initial begin
	repeat(2) @(posedge clk);
	rst_n = 1;
end
endmodule : tb_top
