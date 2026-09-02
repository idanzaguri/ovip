`ifndef OVIP_APB_MASTER_DRIVER__SV
`define OVIP_APB_MASTER_DRIVER__SV

// Requester-side driver. Each ovip_apb_trans becomes one transfer on the
// wire: a single SETUP cycle (PSEL HIGH, PENABLE LOW, address/control/write
// payload valid), then ACCESS cycles (PENABLE HIGH) until the completer
// asserts PREADY. At completion the driver samples PRDATA/PSLVERR back into
// the request object, so a requester sequence sees read data and the error
// response as soon as send() returns.
//
// Back-to-back support: after completion the driver schedules idle values,
// but when the next item arrives in zero simulation time (and the finished
// item's delay_until_next_trans is 0) the new SETUP assignments overwrite the
// idle ones in the same timestep, producing the spec's direct
// completion-to-SETUP transition with no IDLE cycle.
class ovip_apb_master_driver extends uvm_driver#(ovip_apb_trans);

	virtual ovip_apb_agent_if vif;
	ovip_apb_agent_config     cfg;
	string MESSAGE_TAG;

	protected bit item_in_progress;

	// Signal masks derived from cfg widths, applied at drive time so a
	// too-wide field never leaks onto reserved wire bits.
	protected ovip_apb_addr_t ADDR_MASK;
	protected ovip_apb_data_t DATA_MASK;
	protected ovip_apb_strb_t STRB_MASK;

	`uvm_component_utils(ovip_apb_master_driver)

	function new(string name = "ovip_apb_master_driver", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);

	extern virtual task          rst_monitor();
	extern virtual function void drive_reset_values();
	extern virtual task          tx_driver();
	extern virtual task          drive_transfer(ovip_apb_trans tr);
	extern virtual function bit  check_trans_validity(ovip_apb_trans tr);

endclass : ovip_apb_master_driver


function void ovip_apb_master_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!uvm_config_db#(virtual ovip_apb_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))
	if(!uvm_config_db#(ovip_apb_agent_config)::get(this, "", "cfg", cfg))
		`uvm_fatal("MISSING_CFG", $sformatf("Missing agent config - %s.cfg", get_full_name()))
	MESSAGE_TAG = (cfg.agent_tag == "") ? "" : {cfg.agent_tag, "/"};

	ADDR_MASK = (ovip_apb_addr_t'(1) << cfg.addr_width)   - 1;
	DATA_MASK = (ovip_apb_data_t'(1) << cfg.data_width*8) - 1;
	STRB_MASK = (ovip_apb_strb_t'(1) << cfg.data_width)   - 1;
endfunction : build_phase


task ovip_apb_master_driver::run_phase(uvm_phase phase);
	drive_reset_values();
	`uvm_info({MESSAGE_TAG, "APB_DRV"}, "waiting for reset deassertion", UVM_HIGH)
	@(vif.master_cb iff vif.master_cb.presetn);
	`uvm_info({MESSAGE_TAG, "APB_DRV"}, "reset deasserted", UVM_HIGH)

	forever
	begin
		`OVIP_BEGIN_FIRST_OF
			rst_monitor();
			tx_driver();
		`OVIP_END_FIRST_OF

		drive_reset_values();
		if(item_in_progress)
		begin
			// Release the sequencer if a transfer was killed by reset.
			`uvm_info({MESSAGE_TAG, "APB_DRV"}, "Reset killed an in-flight transfer -- completing it to release the sequencer", UVM_LOW)
			seq_item_port.item_done();
			item_in_progress = 0;
			req = null;
		end
		if(vif.master_cb.presetn == 1'b0)
			@(vif.master_cb iff vif.master_cb.presetn);
	end
endtask : run_phase


task ovip_apb_master_driver::rst_monitor();
	@(vif.master_cb iff vif.master_cb.presetn == 1'b0);
endtask : rst_monitor


function void ovip_apb_master_driver::drive_reset_values();
	vif.master_cb.psel    <= 1'b0;
	vif.master_cb.penable <= 1'b0;
	vif.master_cb.paddr   <= '0;
	vif.master_cb.pwrite  <= 1'b0;
	vif.master_cb.pwdata  <= '0;
	vif.master_cb.pstrb   <= '0;
	vif.master_cb.pprot   <= '0;
endfunction : drive_reset_values


task ovip_apb_master_driver::tx_driver();
	forever
	begin
		if(req == null)
		begin
			seq_item_port.get_next_item(req);
			@(vif.master_cb);
		end
		item_in_progress = 1;
		void'(check_trans_validity(req));
		drive_transfer(req);
		seq_item_port.item_done();
		item_in_progress = 0;

		// Post-transfer state: schedule idle values now. When try_next_item
		// hands over the next item in ZERO time (we are still at the
		// completion edge), its SETUP assignments overwrite these in the
		// same timestep -- PSEL never drops: the spec's direct
		// completion-to-SETUP transition, at no alignment cost.
		if(cfg.drive_reset_values_when_idle)
			drive_reset_values();
		else
		begin
			vif.master_cb.psel    <= 1'b0;
			vif.master_cb.penable <= 1'b0;
		end

		repeat(req.delay_until_next_trans) @(vif.master_cb);
		seq_item_port.try_next_item(req);
	end
endtask : tx_driver


task ovip_apb_master_driver::drive_transfer(ovip_apb_trans tr);
	`uvm_info({MESSAGE_TAG, "APB_DRV"}, $sformatf("driving %s", tr.convert2string()), UVM_HIGH)

	// SETUP phase: PSEL HIGH, PENABLE LOW, address/control/payload valid.
	vif.master_cb.psel    <= 1'b1;
	vif.master_cb.penable <= 1'b0;
	vif.master_cb.paddr   <= tr.addr & ADDR_MASK;
	vif.master_cb.pwrite  <= tr.write;
	if(cfg.pprot_en) vif.master_cb.pprot <= tr.prot;
	if(tr.write)
	begin
		vif.master_cb.pwdata <= tr.wdata & DATA_MASK;
		// PSTRB absent -> all byte lanes are valid for a write (spec table
		// 3-1: tie the completer's PSTRB inputs to PWRITE); we drive the
		// all-ones equivalent so a mixed-presence link still sees full lanes.
		vif.master_cb.pstrb <= cfg.pstrb_en ? (tr.strb & STRB_MASK) : STRB_MASK;
	end
	else
	begin
		// Spec section 3.2: PSTRB must not be active during a read transfer.
		vif.master_cb.pwdata <= '0;
		vif.master_cb.pstrb  <= '0;
	end
	tr.setup_time = $time;
	@(vif.master_cb);

	// ACCESS phase: PENABLE HIGH, everything else held stable until PREADY.
	vif.master_cb.penable <= 1'b1;
	@(vif.master_cb iff vif.master_cb.pready == 1'b1);

	// Completion: sample the response back into the request object.
	if(!tr.write)
		tr.rdata = vif.master_cb.prdata & DATA_MASK;
	tr.slverr = cfg.pslverr_en ? bit'(vif.master_cb.pslverr) : 1'b0;
	tr.complete_time        = $time;
	tr.transaction_finished = 1;
endtask : drive_transfer


// Basic sanity only -- the monitor fully verifies the wire-level protocol.
// Too-wide fields are flagged here and masked at drive time.
function bit ovip_apb_master_driver::check_trans_validity(ovip_apb_trans tr);
	bit err_flag = 0;
	`OVIP_APB_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "APB_DRV/TR_CHK"}, "PADDR", tr.addr, cfg.addr_width, err_flag)
	if(tr.write)
	begin
		`OVIP_APB_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "APB_DRV/TR_CHK"}, "PWDATA", tr.wdata, cfg.data_width*8, err_flag)
		`OVIP_APB_CHECK_VALUE_VS_SIGNAL_WIDTH({MESSAGE_TAG, "APB_DRV/TR_CHK"}, "PSTRB",  tr.strb,  cfg.data_width,   err_flag)
	end
	else if(tr.strb != 0)
	begin
		`uvm_warning({MESSAGE_TAG, "APB_DRV/TR_CHK"}, "strb != 0 on a read transfer -- PSTRB will be driven LOW per spec section 3.2")
		err_flag = 1;
	end
	return err_flag;
endfunction : check_trans_validity

`endif
