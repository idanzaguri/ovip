`ifndef OVIP_AXI_STREAM_MASTER_DRIVER__SV
`define OVIP_AXI_STREAM_MASTER_DRIVER__SV

// Transmitter-side driver. Each `ovip_axi_stream_trans` becomes one packet on
// the wire: per-beat TDATA/TSTRB/TKEEP/TUSER from the trans queues, with
// TLAST asserted only on the last beat, and TID/TDEST/TWAKEUP held constant
// across the packet (per spec sections 2.6 / 2.3). Inter-beat and inter-
// transaction gaps come straight from the trans's embedded timing knobs.
class ovip_axi_stream_master_driver extends uvm_driver#(ovip_axi_stream_trans);

	virtual ovip_axi_stream_agent_if vif;
	ovip_axi_stream_agent_config     cfg;
	string MESSAGE_TAG;

	protected bit item_in_progress;

	`uvm_component_utils(ovip_axi_stream_master_driver)

	function new(string name = "ovip_axi_stream_master_driver", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);

	extern virtual task          rst_monitor();
	extern virtual function void drive_reset_values();
	extern virtual task          tx_driver();
	extern virtual task          drive_packet(ovip_axi_stream_trans tr);
	extern virtual function void drive_beat(ovip_axi_stream_trans tr, int beat_index, bit is_last);

endclass : ovip_axi_stream_master_driver


function void ovip_axi_stream_master_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!uvm_config_db#(virtual ovip_axi_stream_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))
	if(!uvm_config_db#(ovip_axi_stream_agent_config)::get(this, "", "cfg", cfg))
		`uvm_fatal("MISSING_CFG", $sformatf("Missing agent config - %s.cfg", get_full_name()))
	MESSAGE_TAG = (cfg.agent_tag == "") ? "" : {cfg.agent_tag, "/"};
endfunction : build_phase


task ovip_axi_stream_master_driver::run_phase(uvm_phase phase);
	drive_reset_values();
	`uvm_info({MESSAGE_TAG, "AXIS_DRV"}, "waiting for reset deassertion", UVM_HIGH)
	@(vif.master_cb iff vif.master_cb.aresetn);
	`uvm_info({MESSAGE_TAG, "AXIS_DRV"}, "reset deasserted", UVM_HIGH)

	forever
	begin
		fork begin
			fork
				rst_monitor();
				tx_driver();
			join_any
			disable fork;
		end join

		drive_reset_values();
		if(item_in_progress)
		begin
			// Release the sequencer if a packet was killed by reset.
			`uvm_info({MESSAGE_TAG, "AXIS_DRV"}, "Reset killed an in-flight packet -- completing it to release the sequencer", UVM_LOW)
			seq_item_port.item_done();
			item_in_progress = 0;
		end
		if(vif.master_cb.aresetn == 1'b0)
			@(vif.master_cb iff vif.master_cb.aresetn);
	end
endtask : run_phase


task ovip_axi_stream_master_driver::rst_monitor();
	@(vif.master_cb iff vif.master_cb.aresetn == 1'b0);
endtask : rst_monitor


function void ovip_axi_stream_master_driver::drive_reset_values();
	vif.master_cb.tvalid  <= 1'b0;
	vif.master_cb.tdata   <= '0;
	vif.master_cb.tstrb   <= '0;
	vif.master_cb.tkeep   <= '0;
	vif.master_cb.tlast   <= 1'b0;
	vif.master_cb.tid     <= '0;
	vif.master_cb.tdest   <= '0;
	vif.master_cb.tuser   <= '0;
	vif.master_cb.twakeup <= 1'b0;
endfunction : drive_reset_values


task ovip_axi_stream_master_driver::tx_driver();
	forever
	begin
		seq_item_port.get_next_item(req);
		item_in_progress = 1;
		if(req.data_beats.size() == 0)
			`uvm_warning({MESSAGE_TAG, "AXIS_DRV"}, "received an item with no beats -- ignoring (a wire-level packet needs at least one transfer).")
		else
			drive_packet(req);
		seq_item_port.item_done();
		item_in_progress = 0;
		// Inter-transaction gap.
		repeat(req.delay_until_next_trans) @(vif.master_cb);
	end
endtask : tx_driver


task ovip_axi_stream_master_driver::drive_packet(ovip_axi_stream_trans tr);
	int last = tr.data_beats.size() - 1;
	`uvm_info({MESSAGE_TAG, "AXIS_DRV"}, $sformatf("driving %s", tr.convert2string()), UVM_HIGH)

	for(int ii = 0; ii <= last; ii++)
	begin
		drive_beat(tr, ii, (ii == last));
		// Wait for the receiver to handshake this beat.
		@(vif.master_cb iff vif.master_cb.tready == 1'b1);
		drive_reset_values();

		// Inter-beat gap (skipped after the last beat -- that's
		// delay_until_next_trans territory).
		if(ii != last)
		begin
			if(ii < tr.delay_between_beats.size())
				repeat(tr.delay_between_beats[ii]) @(vif.master_cb);
			else
				repeat($urandom_range(tr.max_delay_between_beats, tr.min_delay_between_beats)) @(vif.master_cb);
		end
	end
endtask : drive_packet


function void ovip_axi_stream_master_driver::drive_beat(ovip_axi_stream_trans tr, int beat_index, bit is_last);
	// SV bit-slice ranges must be constant, so we drive the full-MAX-width
	// signals each beat. Unused bits sit at zero (or all-ones for the
	// "missing TKEEP/TSTRB defaults to HIGH" case); the receiver ignores
	// everything above its configured width.
	ovip_axi_stream_data_t data_wire;
	ovip_axi_stream_keep_t keep_wire;
	ovip_axi_stream_strb_t strb_wire;
	ovip_axi_stream_user_t user_wire;

	vif.master_cb.tvalid <= 1'b1;

	data_wire = (cfg.tdata_width > 0) ? tr.data_beats[beat_index] : '0;
	vif.master_cb.tdata <= data_wire;

	if(cfg.tkeep_en)
	begin
		// Default: when the trans hasn't supplied TKEEP for this beat, drive
		// all-ones across the live byte lanes (matches the spec's "TKEEP
		// absent -> default HIGH" rule).
		keep_wire = (beat_index < tr.keep_beats.size()) ? tr.keep_beats[beat_index]
		                                                : (ovip_axi_stream_keep_t'(1) << cfg.tdata_width) - 1;
		vif.master_cb.tkeep <= keep_wire;
	end
	if(cfg.tstrb_en)
	begin
		strb_wire = (beat_index < tr.strb_beats.size()) ? tr.strb_beats[beat_index]
		                                                : (ovip_axi_stream_strb_t'(1) << cfg.tdata_width) - 1;
		vif.master_cb.tstrb <= strb_wire;
	end

	// TLAST: only on the final beat (and only when the signal is enabled).
	if(cfg.tlast_en) vif.master_cb.tlast <= is_last;

	// Packet-scope: TID/TDEST/TWAKEUP held constant across beats.
	if(cfg.tid_en)   vif.master_cb.tid   <= tr.id;
	if(cfg.tdest_en) vif.master_cb.tdest <= tr.dest;

	// Per-byte TUSER -- trans stores the full vector; drive straight through.
	if(cfg.tuser_en && cfg.tuser_bits_per_byte > 0)
	begin
		user_wire = (beat_index < tr.user_beats.size()) ? tr.user_beats[beat_index] : '0;
		vif.master_cb.tuser <= user_wire;
	end

	// TWAKEUP (AXI5): held HIGH across the packet when the trans sets it. The
	// monitor's wakeup_check enforces hold-until-tready.
	if(cfg.twakeup_en) vif.master_cb.twakeup <= tr.wakeup;
endfunction : drive_beat

`endif
