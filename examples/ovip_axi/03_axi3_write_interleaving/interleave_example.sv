// AXI3 W-channel interleaving.
//
// What this shows:
//   - AXI3 lets W beats from different write transactions be interleaved on
//     the bus, with each beat tagged by `wid` indicating which transaction
//     it belongs to. AXI4 dropped this feature; on AXI4 the W beats of one
//     write must run to completion before the next can start.
//   - The master is configured with `wr_interleave_depth = 2` so two
//     concurrent writes can have their W beats picked alternately by the
//     master driver's scheduler.
//   - The test issues two 4-beat writes with IDs 0 and 1 back-to-back. A
//     small watcher running in `tb_top` prints `wid, wdata, wlast` on every
//     accepted W beat, making the interleave pattern visible.
//   - The slave's monitor reassembles the beats per ID; the base slave
//     sequence writes them to `ovip_mem`. After both writes complete the
//     master reads everything back to confirm both regions hold the
//     correct payload.
//
// Knobs demonstrated:
//   - `cfg.protocol_type = OVIP_PROTOCOL_AXI3`  (AXI4 would forbid this)
//   - `cfg.wr_interleave_depth`                  (concurrent IDs)
//   - `cfg.wr_out_of_order_depth`                (reorder window)
//   - `cfg.wr_scheduling_alg`                    (pick rule among ready beats)

`timescale 1ns/1ps

package interleave_example_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_pkg::*;
	`include "uvm_macros.svh"

	localparam int N_BEATS = 4;
	localparam int N_WRITES = 2;


	class interleave_master_seq extends ovip_axi_base_master_sequence;
		`uvm_object_utils(interleave_master_seq)
		`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

		function new(string name = "interleave_master_seq");
			super.new(name);
		endfunction

		virtual task body();
			// Two writes with different IDs, issued back-to-back.
			// SIZE_4B == bus_width == mem word: no lane shifting, one beat per mem entry.
			for(int kk = 0; kk < N_WRITES; kk++) begin
				ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("wr_id%0d", kk));
				tr.tr_type = OVIP_AXI_WRITE_TRANS;
				tr.addr    = kk * 'h40;        // disjoint regions per write
				tr.id      = kk;
				tr.len     = N_BEATS - 1;      // 4 beats
				tr.size    = OVIP_AXI_SIZE_4B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				for(int bb = 0; bb < N_BEATS; bb++) begin
					// wdata = 0xAABB_<id><beat> -- makes interleaving obvious in the log.
					tr.data_beats.push_back(32'hAABB_0000 | (kk[3:0] << 4) | bb[3:0]);
					tr.strb_beats.push_back(4'hF);
				end
				`uvm_info("ITLV_MST", $sformatf("issuing wr id=%0d addr=0x%0h, 4 beats", tr.id, tr.addr), UVM_LOW)
				send(tr);
			end
			wait_for_responses();

			// Read everything back and verify against mem.
			for(int kk = 0; kk < N_WRITES; kk++) begin
				for(int bb = 0; bb < N_BEATS; bb++) begin
					ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("rd_%0d_%0d", kk, bb));
					tr.tr_type = OVIP_AXI_READ_TRANS;
					tr.addr    = kk * 'h40 + bb * 4;
					tr.id      = kk + 4;       // distinct IDs for the read path
					tr.len     = 0;
					tr.size    = OVIP_AXI_SIZE_4B;
					tr.burst   = OVIP_AXI_BURST_INCR;
					send(tr);
				end
			end
			wait_for_responses();
		endtask
	endclass


	// Subscriber: round-trip check on each read against mem.
	class read_check extends uvm_subscriber#(ovip_axi_trans);
		`uvm_component_utils(read_check)

		ovip_mem mem;

		function new(string name = "read_check", uvm_component parent);
			super.new(name, parent);
		endfunction

		virtual function void write(ovip_axi_trans t);
			if(t.tr_type != OVIP_AXI_READ_TRANS) return;
			if(t.data_beats[0] != mem.read(t.addr))
				`uvm_error("ITLV_DATA", $sformatf("addr=0x%0h: read 0x%0h, mem holds 0x%0h",
			t.addr, t.data_beats[0], mem.read(t.addr)))
		endfunction
	endclass


	class interleave_test extends uvm_test;
		`uvm_component_utils(interleave_test)

		ovip_axi_agent_config master_cfg, slave_cfg;
		ovip_axi_agent        master_agent, slave_agent;
		ovip_mem              mem;
		ovip_axi_base_slave_sequence slave_seq;
		read_check            rd_chk;

		function new(string name = "interleave_test", uvm_component parent = null);
			super.new(name, parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			mem = ovip_mem::type_id::create("mem", this);

			master_cfg = ovip_axi_agent_config::type_id::create("master_cfg");
			master_cfg.agent_type      = OVIP_MASTER_AGENT;
			master_cfg.protocol_type   = OVIP_PROTOCOL_AXI3;  // wid is AXI3-only
			master_cfg.bus_width       = OVIP_AXI_BUS_WIDTH_4B;
			master_cfg.addr_width      = 32;
			master_cfg.is_active       = UVM_ACTIVE;
			master_cfg.wr_out_of_order_depth = N_WRITES;
			master_cfg.wr_interleave_depth   = N_WRITES;
			master_cfg.wr_scheduling_alg     = OVIP_AXI_SCH_ALG_ROUND_ROBIN;
			master_cfg.num_outstanding_wr_transactions = N_WRITES;

			slave_cfg = ovip_axi_agent_config::type_id::create("slave_cfg");
			slave_cfg.agent_type     = OVIP_SLAVE_AGENT;
			slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI3;
			slave_cfg.bus_width      = OVIP_AXI_BUS_WIDTH_4B;
			slave_cfg.addr_width     = 32;
			slave_cfg.is_active      = UVM_ACTIVE;
			// Slave monitor enforces these on observed traffic -- must be at
			// least as big as the master's actual OOO / interleaving level.
			slave_cfg.wr_out_of_order_depth = N_WRITES;
			slave_cfg.wr_interleave_depth   = N_WRITES;

			master_agent = ovip_axi_agent::type_id::create("master_agent", this);
			master_agent.cfg = master_cfg;
			slave_agent = ovip_axi_agent::type_id::create("slave_agent", this);
			slave_agent.cfg = slave_cfg;

			slave_seq = ovip_axi_base_slave_sequence::type_id::create("slave_seq");
			slave_seq.mem = mem;

			rd_chk = read_check::type_id::create("rd_chk", this);
			rd_chk.mem = mem;
		endfunction

		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			master_agent.mon.analysis_port.connect(rd_chk.analysis_export);
		endfunction

		virtual task run_phase(uvm_phase phase);
			super.run_phase(phase);
			fork
				slave_seq.start(slave_agent.sqr);
				w_channel_watcher();   // prints wid per accepted W beat
			join_none
		endtask

		// Logs every accepted W beat -- makes the interleave visible.
		task w_channel_watcher();
			virtual ovip_axi_agent_if vif = master_agent.mon.vif;
			forever begin
				@(vif.monitor_cb iff vif.monitor_cb.aresetn
				&& vif.monitor_cb.wvalid
				&& vif.monitor_cb.wready);
				`uvm_info("ITLV_WATCH",
					$sformatf("W beat: wid=%0d wdata=0x%08h wlast=%0d  t=%0t",
					vif.monitor_cb.wid, vif.monitor_cb.wdata[31:0],
					vif.monitor_cb.wlast, $time),
					UVM_LOW)
			end
		endtask

		virtual task reset_phase(uvm_phase phase);
			super.reset_phase(phase);
			phase.raise_objection(this);
			@(posedge master_agent.mon.vif.aresetn);
			phase.drop_objection(this);
		endtask

		virtual task main_phase(uvm_phase phase);
			interleave_master_seq seq = interleave_master_seq::type_id::create("seq");
			super.main_phase(phase);
			phase.raise_objection(this);
			seq.start(master_agent.sqr);
			#100ns;
			phase.drop_objection(this);
		endtask
	endclass

endpackage : interleave_example_pkg


module tb_top;
import uvm_pkg::*;
import interleave_example_pkg::*;

logic clk = 0;
logic rst_n = 0;
always #500ps clk = ~clk;   // 1 GHz

ovip_axi_agent_if axi_if(clk, rst_n);

initial begin
	uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.master_agent*", "vif", axi_if);
	uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.slave_agent*",  "vif", axi_if);
	run_test("interleave_test");
end

initial begin
	repeat(2) @(posedge clk);
	rst_n = 1;
end
endmodule : tb_top
