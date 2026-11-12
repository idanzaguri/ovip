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

	// The live bits of each payload signal, from cfg at the start of
	// run_phase, as in the monitor. Applied at drive time, so a field of an
	// item that is wider than its signal never reaches the unused upper bits
	// of the wire. A width of 0 on TID or TDEST keeps the whole wire.
	protected ovip_axi_stream_data_t DATA_MASK;
	protected ovip_axi_stream_strb_t STRB_MASK;
	protected ovip_axi_stream_keep_t KEEP_MASK;
	protected ovip_axi_stream_id_t   ID_MASK;
	protected ovip_axi_stream_dest_t DEST_MASK;
	protected ovip_axi_stream_user_t USER_MASK;

	`uvm_component_utils(ovip_axi_stream_master_driver)

	function new(string name = "ovip_axi_stream_master_driver", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);
	extern virtual function void set_masks();

	extern virtual task          rst_monitor();
	extern virtual function void drive_reset_values();
	extern virtual task          tx_driver();
	extern virtual function bit  check_trans_validity(ovip_axi_stream_trans tr);
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


function void ovip_axi_stream_master_driver::set_masks();
	DATA_MASK = (ovip_axi_stream_data_t'(1) << (cfg.tdata_width * 8)) - 1;
	STRB_MASK = (ovip_axi_stream_strb_t'(1) << cfg.tdata_width) - 1;
	KEEP_MASK = (ovip_axi_stream_keep_t'(1) << cfg.tdata_width) - 1;
	ID_MASK   = (cfg.tid_width   > 0) ? (ovip_axi_stream_id_t'(1)   << cfg.tid_width)   - 1 : '1;
	DEST_MASK = (cfg.tdest_width > 0) ? (ovip_axi_stream_dest_t'(1) << cfg.tdest_width) - 1 : '1;
	USER_MASK = (ovip_axi_stream_user_t'(1) << (cfg.tuser_bits_per_byte * cfg.tdata_width)) - 1;
endfunction : set_masks


task ovip_axi_stream_master_driver::run_phase(uvm_phase phase);
	set_masks();
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
		// Whatever the driver still held is from before the reset: a packet
		// taken but not yet started, or the last one, done, in its gap. Keeping
		// it would send it again after the release.
		req = null;
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
		if(req == null)
		begin
			seq_item_port.get_next_item(req);
			item_in_progress = 1;   // the sequencer's item from here to item_done, so a reset releases it
			@(vif.master_cb);
		end
		item_in_progress = 1;
		if(req.data_beats.size() == 0)
			`uvm_warning({MESSAGE_TAG, "AXIS_DRV"}, "received an item with no beats -- ignoring (a wire-level packet needs at least one transfer).")
		else
		begin
			void'(check_trans_validity(req));
			drive_packet(req);
		end
		seq_item_port.item_done();
		item_in_progress = 0;
		// Inter-transaction gap.
		repeat(req.delay_until_next_trans) @(vif.master_cb);
		seq_item_port.try_next_item(req);
	end
endtask : tx_driver


// Basic sanity only: the monitor verifies the wire-level protocol. A field
// that is wider than the configured width of its signal is flagged here and
// cut to that width at drive time. A signal that is not enabled is not
// driven, so its field is not checked.
function bit ovip_axi_stream_master_driver::check_trans_validity(ovip_axi_stream_trans tr);
	bit err_flag = 0;
	if(cfg.tid_en && cfg.tid_width > 0)
		`OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "AXIS_DRV/TR_CHK"}, "TID", tr.id, cfg.tid_width, err_flag)
	if(cfg.tdest_en && cfg.tdest_width > 0)
		`OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "AXIS_DRV/TR_CHK"}, "TDEST", tr.dest, cfg.tdest_width, err_flag)
	foreach(tr.data_beats[ii])
		`OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "AXIS_DRV/TR_CHK"}, $sformatf("data_beats[%0d]", ii), tr.data_beats[ii], cfg.tdata_width*8, err_flag)
	if(cfg.tkeep_en)
		foreach(tr.keep_beats[ii])
			`OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "AXIS_DRV/TR_CHK"}, $sformatf("keep_beats[%0d]", ii), tr.keep_beats[ii], cfg.tdata_width, err_flag)
	if(cfg.tstrb_en)
		foreach(tr.strb_beats[ii])
			`OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "AXIS_DRV/TR_CHK"}, $sformatf("strb_beats[%0d]", ii), tr.strb_beats[ii], cfg.tdata_width, err_flag)
	if(cfg.tuser_en)
		foreach(tr.user_beats[ii])
			`OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "AXIS_DRV/TR_CHK"}, $sformatf("user_beats[%0d]", ii), tr.user_beats[ii], cfg.tuser_bits_per_byte*cfg.tdata_width, err_flag)
	return err_flag;
endfunction : check_trans_validity


task ovip_axi_stream_master_driver::drive_packet(ovip_axi_stream_trans tr);
	int last = tr.data_beats.size() - 1;
	`uvm_info({MESSAGE_TAG, "AXIS_DRV"}, $sformatf("driving %s", tr.convert2string()), UVM_HIGH)

	for(int ii = 0; ii <= last; ii++)
	begin
		drive_beat(tr, ii, (ii == last));
		// Wait for the receiver to handshake this beat. Without TREADY on the
		// interface it counts as HIGH (spec section 3.1.1): the beat takes one
		// cycle.
		@(vif.master_cb iff (!cfg.tready_en || vif.master_cb.tready == 1'b1));
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
	// signals each beat, each value ANDed with the mask of its signal. Unused
	// bits sit at zero; the receiver ignores everything above its configured
	// width.
	ovip_axi_stream_data_t data_wire;
	ovip_axi_stream_keep_t keep_wire;
	ovip_axi_stream_strb_t strb_wire;
	ovip_axi_stream_user_t user_wire;

	vif.master_cb.tvalid <= 1'b1;

	data_wire = tr.data_beats[beat_index] & DATA_MASK;
	vif.master_cb.tdata <= data_wire;

	// Default: when the trans hasn't supplied TKEEP for this beat, or TKEEP
	// is absent, it is all-ones across the live byte lanes (spec section
	// 3.1.2, "TKEEP defaults to all bits HIGH").
	keep_wire = KEEP_MASK;
	if(cfg.tkeep_en)
	begin
		if(beat_index < tr.keep_beats.size()) keep_wire = tr.keep_beats[beat_index] & KEEP_MASK;
		vif.master_cb.tkeep <= keep_wire;
	end
	if(cfg.tstrb_en)
	begin
		// Default: when the trans hasn't supplied TSTRB for this beat, TSTRB
		// equals the TKEEP of the beat (spec section 3.1.2, "TSTRB = TKEEP"),
		// so a null byte never gets the reserved TKEEP=0 TSTRB=1 combination.
		strb_wire = (beat_index < tr.strb_beats.size()) ? (tr.strb_beats[beat_index] & STRB_MASK) : keep_wire;
		vif.master_cb.tstrb <= strb_wire;
	end

	// TLAST: only on the final beat (and only when the signal is enabled).
	if(cfg.tlast_en) vif.master_cb.tlast <= is_last;

	// Packet-scope: TID/TDEST/TWAKEUP held constant across beats.
	if(cfg.tid_en)   vif.master_cb.tid   <= tr.id   & ID_MASK;
	if(cfg.tdest_en) vif.master_cb.tdest <= tr.dest & DEST_MASK;

	// Per-byte TUSER: the trans stores the full vector of the beat.
	if(cfg.tuser_en && cfg.tuser_bits_per_byte > 0)
	begin
		user_wire = (beat_index < tr.user_beats.size()) ? (tr.user_beats[beat_index] & USER_MASK) : '0;
		vif.master_cb.tuser <= user_wire;
	end

	// TWAKEUP (AXI5): held HIGH across the packet when the trans sets it. The
	// monitor's wakeup_check enforces hold-until-tready.
	if(cfg.twakeup_en) vif.master_cb.twakeup <= tr.wakeup;
endfunction : drive_beat

`endif
