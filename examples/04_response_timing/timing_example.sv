// Response-timing knobs.
//
// What this shows:
//   - The slave inserts a configurable gap between WLAST and BRESP on writes
//     (via `bresp_delay`), and a configurable per-beat staircase on reads
//     (via `data_delay[$]`).
//   - A live watcher in `tb_top` prints `[t=...]` lines for every channel
//     handshake (AR/AW/W/R/BRESP), so the gaps imposed by these knobs are
//     directly readable in the log.
//   - The transaction-data path is plain loopback: writes land in
//     `ovip_mem`, reads come back from it; the test asserts every read
//     returns what was written.
//
// Knobs demonstrated:
//   - Slave-side `bresp_delay`     -- cycles between WLAST sample and BRESP drive.
//   - Slave-side `data_delay[ii]`  -- per-beat gap before the i-th read beat
//                                     is driven; `[0]` is the gap between AR
//                                     handshake and the first R beat.
//   - For per-cycle ready-pattern control see the VIP README "Ready Patterns"
//     section -- those knobs are orthogonal and apply to AWREADY/WREADY/etc.

`timescale 1ns/1ps

package timing_example_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_pkg::*;
	`include "uvm_macros.svh"

	localparam int N_BEATS    = 4;
	localparam int BRESP_GAP  = 10;            // cycles after WLAST -> BRESP
	localparam int RDATA_GAP0 = 6;             // cycles AR-handshake -> first R
	localparam int RDATA_GAPN = 2;             // cycles between subsequent R beats


	// Slave: BRESP and per-beat read delays pinned to constants for reproducible logs.
	class timing_slave_seq extends ovip_axi_base_slave_sequence;
		`uvm_object_utils(timing_slave_seq)
		`uvm_declare_p_sequencer(ovip_axi_slave_sequencer)

		function new(string name = "timing_slave_seq");
			super.new(name);
		endfunction

		virtual function int get_bresp_delay();
			return BRESP_GAP;
		endfunction

		// data_delay[0] = AR -> first-R gap; data_delay[i>0] = inter-beat gap.
		virtual function void set_read_trans_delays(ovip_axi_trans tr);
			tr.data_delay.delete();
			tr.data_delay.push_back(RDATA_GAP0);
			repeat(tr.len) tr.data_delay.push_back(RDATA_GAPN);
		endfunction
	endclass


	class timing_master_seq extends ovip_axi_base_master_sequence;
		`uvm_object_utils(timing_master_seq)
		`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

		function new(string name = "timing_master_seq");
			super.new(name);
		endfunction

		virtual task body();
			// Write: 4-beat INCR burst at addr 0.
		begin
		ovip_axi_trans tr = ovip_axi_trans::type_id::create("wr");
		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.addr    = 'h0;
		tr.id      = 0;
		tr.len     = N_BEATS - 1;
		tr.size    = OVIP_AXI_SIZE_4B;
		tr.burst   = OVIP_AXI_BURST_INCR;
		for(int bb = 0; bb < N_BEATS; bb++) begin
			tr.data_beats.push_back(32'hC0DE_0000 | bb);
			tr.strb_beats.push_back(4'hF);
		end
		`uvm_info("TIMING_MST", $sformatf("issuing wr addr=0x%0h, 4 beats", tr.addr), UVM_LOW)
		send(tr);
	end

	// Wait for the write to retire -- otherwise the slave samples `mem`
	// before the write commits (default `wr_mem_update_on_bresp = 1`).
	wait_for_responses();

	// Read: same region, expect the same payload.
begin
ovip_axi_trans tr = ovip_axi_trans::type_id::create("rd");
tr.tr_type = OVIP_AXI_READ_TRANS;
tr.addr    = 'h0;
tr.id      = 1;
tr.len     = N_BEATS - 1;
tr.size    = OVIP_AXI_SIZE_4B;
tr.burst   = OVIP_AXI_BURST_INCR;
`uvm_info("TIMING_MST", $sformatf("issuing rd addr=0x%0h, 4 beats", tr.addr), UVM_LOW)
send(tr);
	    end

	    wait_for_responses();
    endtask
    endclass


    // Subscriber: per-beat round-trip check on the read.
    class rd_check extends uvm_subscriber#(ovip_axi_trans);
	    `uvm_component_utils(rd_check)

	    function new(string name = "rd_check", uvm_component parent);
		    super.new(name, parent);
	    endfunction

	    virtual function void write(ovip_axi_trans t);
		    if(t.tr_type != OVIP_AXI_READ_TRANS) return;
		    foreach(t.data_beats[bb])
			    if(t.data_beats[bb] != (32'hC0DE_0000 | bb))
				    `uvm_error("TIMING_DATA",
			    $sformatf("beat[%0d]: read 0x%0h, expected 0x%0h",
			    bb, t.data_beats[bb], 32'hC0DE_0000 | bb))
		    endfunction
	    endclass


	    class timing_test extends uvm_test;
		    `uvm_component_utils(timing_test)

		    ovip_axi_agent_config master_cfg, slave_cfg;
		    ovip_axi_agent        master_agent, slave_agent;
		    ovip_mem              mem;
		    timing_slave_seq      slave_seq;
		    rd_check              chk;

		    function new(string name = "timing_test", uvm_component parent = null);
			    super.new(name, parent);
		    endfunction

		    function void build_phase(uvm_phase phase);
			    super.build_phase(phase);

			    mem = ovip_mem::type_id::create("mem", this);

			    master_cfg = ovip_axi_agent_config::type_id::create("master_cfg");
			    master_cfg.agent_type = OVIP_MASTER_AGENT;
			    master_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_4B;
			    master_cfg.addr_width = 32;
			    master_cfg.is_active  = UVM_ACTIVE;

			    slave_cfg = ovip_axi_agent_config::type_id::create("slave_cfg");
			    slave_cfg.agent_type = OVIP_SLAVE_AGENT;
			    slave_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_4B;
			    slave_cfg.addr_width = 32;
			    slave_cfg.is_active  = UVM_ACTIVE;

			    master_agent = ovip_axi_agent::type_id::create("master_agent", this);
			    master_agent.cfg = master_cfg;
			    slave_agent = ovip_axi_agent::type_id::create("slave_agent", this);
			    slave_agent.cfg = slave_cfg;

			    slave_seq = timing_slave_seq::type_id::create("slave_seq");
			    slave_seq.mem = mem;

			    chk = rd_check::type_id::create("chk", this);
		    endfunction

		    function void connect_phase(uvm_phase phase);
			    super.connect_phase(phase);
			    master_agent.mon.analysis_port.connect(chk.analysis_export);
		    endfunction

		    virtual task run_phase(uvm_phase phase);
			    super.run_phase(phase);
			    fork
				    slave_seq.start(slave_agent.sqr);
				    channel_watcher();
			    join_none
		    endtask

		    // Five concurrent watchers, one per channel handshake. Logs t=... per beat
		    // so the BRESP_GAP / RDATA_GAP* values are directly readable.
		    task channel_watcher();
			    virtual ovip_axi_agent_if vif = master_agent.mon.vif;
			    fork
				    forever begin
					    @(vif.monitor_cb iff vif.monitor_cb.aresetn
					    && vif.monitor_cb.awvalid
					    && vif.monitor_cb.awready);
					    `uvm_info("WATCH_AW", $sformatf("aw handshake t=%0t", $time), UVM_LOW)
				    end
				    forever begin
					    @(vif.monitor_cb iff vif.monitor_cb.aresetn
					    && vif.monitor_cb.wvalid
					    && vif.monitor_cb.wready);
					    `uvm_info("WATCH_W ", $sformatf("w beat wdata=0x%08h wlast=%0d t=%0t",
						    vif.monitor_cb.wdata[31:0], vif.monitor_cb.wlast, $time), UVM_LOW)
				    end
				    forever begin
					    @(vif.monitor_cb iff vif.monitor_cb.aresetn
					    && vif.monitor_cb.bvalid
					    && vif.monitor_cb.bready);
					    `uvm_info("WATCH_B ", $sformatf("bresp t=%0t", $time), UVM_LOW)
				    end
				    forever begin
					    @(vif.monitor_cb iff vif.monitor_cb.aresetn
					    && vif.monitor_cb.arvalid
					    && vif.monitor_cb.arready);
					    `uvm_info("WATCH_AR", $sformatf("ar handshake t=%0t", $time), UVM_LOW)
				    end
				    forever begin
					    @(vif.monitor_cb iff vif.monitor_cb.aresetn
					    && vif.monitor_cb.rvalid
					    && vif.monitor_cb.rready);
					    `uvm_info("WATCH_R ", $sformatf("r beat rdata=0x%08h rlast=%0d t=%0t",
						    vif.monitor_cb.rdata[31:0], vif.monitor_cb.rlast, $time), UVM_LOW)
				    end
			    join
		    endtask

		    virtual task reset_phase(uvm_phase phase);
			    super.reset_phase(phase);
			    phase.raise_objection(this);
			    @(posedge master_agent.mon.vif.aresetn);
			    phase.drop_objection(this);
		    endtask

		    virtual task main_phase(uvm_phase phase);
			    timing_master_seq seq = timing_master_seq::type_id::create("seq");
			    super.main_phase(phase);
			    phase.raise_objection(this);
			    seq.start(master_agent.sqr);
			    #100ns;
			    phase.drop_objection(this);
		    endtask
	    endclass

    endpackage : timing_example_pkg


    module tb_top;
    import uvm_pkg::*;
    import timing_example_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    always #500ps clk = ~clk;   // 1 GHz

    ovip_axi_agent_if axi_if(clk, rst_n);

    initial begin
	    uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.master_agent*", "vif", axi_if);
	    uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.slave_agent*",  "vif", axi_if);
	    run_test("timing_test");
    end

    initial begin
	    repeat(2) @(posedge clk);
	    rst_n = 1;
    end
    endmodule : tb_top
