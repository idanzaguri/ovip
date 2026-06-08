`ifndef OVIP_AXI_STREAM_SLAVE_DRIVER__SV
`define OVIP_AXI_STREAM_SLAVE_DRIVER__SV

// Receiver-side driver. AXI-Stream gives the receiver only one wire to
// produce (TREADY), so this driver doesn't pull seq items off a sequencer the
// usual way -- it just walks an `ovip_axi_stream_ready_pattern_t` cycle-by-
// cycle, alternating the TREADY level. New patterns are delivered through
// `tready_pattern_mb` (set by the slave sequence or directly via
// put_tready_pattern); a put preempts whatever pattern is currently running.
class ovip_axi_stream_slave_driver extends uvm_component;

	virtual ovip_axi_stream_agent_if vif;
	ovip_axi_stream_agent_config     cfg;
	string MESSAGE_TAG;

	mailbox#(ovip_axi_stream_ready_pattern_t) tready_pattern_mb;

	`uvm_component_utils(ovip_axi_stream_slave_driver)

	function new(string name = "ovip_axi_stream_slave_driver", uvm_component parent);
		super.new(name, parent);
		tready_pattern_mb = new();
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);

	extern virtual task          rst_monitor();
	extern virtual function void drive_reset_values();
	extern virtual task          tready_driver();
	extern virtual task          play_pattern(ovip_axi_stream_ready_pattern_t pat);

	// Convenience: push a pattern from a test/sequence without going through
	// the mailbox by hand.
	extern virtual function void put_tready_pattern(int unsigned cycles[$], bit loop = 0);

endclass : ovip_axi_stream_slave_driver


function void ovip_axi_stream_slave_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!uvm_config_db#(virtual ovip_axi_stream_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))
	if(!uvm_config_db#(ovip_axi_stream_agent_config)::get(this, "", "cfg", cfg))
		`uvm_fatal("MISSING_CFG", $sformatf("Missing agent config - %s.cfg", get_full_name()))
	MESSAGE_TAG = (cfg.agent_tag == "") ? "" : {cfg.agent_tag, "/"};
endfunction : build_phase


task ovip_axi_stream_slave_driver::run_phase(uvm_phase phase);
	drive_reset_values();
	@(vif.slave_cb iff vif.slave_cb.aresetn);

	forever
	begin
		fork begin
			fork
				rst_monitor();
				tready_driver();
			join_any
			disable fork;
		end join

		drive_reset_values();
		if(vif.slave_cb.aresetn == 1'b0)
			@(vif.slave_cb iff vif.slave_cb.aresetn);
	end
endtask : run_phase


task ovip_axi_stream_slave_driver::rst_monitor();
	@(vif.slave_cb iff vif.slave_cb.aresetn == 1'b0);
endtask : rst_monitor


function void ovip_axi_stream_slave_driver::drive_reset_values();
	if(cfg.tready_en) vif.slave_cb.tready <= 1'b0;
endfunction : drive_reset_values


task ovip_axi_stream_slave_driver::tready_driver();
	ovip_axi_stream_ready_pattern_t cur;

	// Start with the cfg default until something new arrives.
	cur = cfg.default_tready_pattern;
	forever
	begin
		// Pre-empt the currently-running pattern if a new one is waiting.
		void'(tready_pattern_mb.try_get(cur));
		play_pattern(cur);
	end
endtask : tready_driver


// Per the pattern semantics: cycles[i] holds the TREADY level for that many
// cycles; level alternates with the index (even=0, odd=1). When loop=1 the
// queue restarts from the start after the last entry; when loop=0 the final
// level is held until a new pattern preempts us via the mailbox.
task ovip_axi_stream_slave_driver::play_pattern(ovip_axi_stream_ready_pattern_t pat);
	bit level;
	if(pat.cycles.size() == 0) pat = '{cycles:'{0, 1}, loop:0};
	do begin
		for(int ii = 0; ii < pat.cycles.size(); ii++)
		begin
			level = ii[0]; // even index -> 0, odd index -> 1
			repeat(pat.cycles[ii])
			begin
				vif.slave_cb.tready <= level;
				@(vif.slave_cb);
				// Bail if a new pattern arrives mid-play.
				if(tready_pattern_mb.num()) return;
			end
		end
	end
	while(pat.loop);

	// Pattern is one-shot: hold the final level forever (until the mailbox
	// hands us a new pattern, observed by the outer forever-loop's try_get).
	vif.slave_cb.tready <= level;
	wait(tready_pattern_mb.num());
endtask : play_pattern


function void ovip_axi_stream_slave_driver::put_tready_pattern(int unsigned cycles[$], bit loop = 0);
	ovip_axi_stream_ready_pattern_t pat;
	pat.cycles = cycles;
	pat.loop   = loop;
	void'(tready_pattern_mb.try_put(pat));
endfunction : put_tready_pattern

`endif
