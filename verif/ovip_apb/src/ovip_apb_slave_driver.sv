`ifndef OVIP_APB_SLAVE_DRIVER__SV
`define OVIP_APB_SLAVE_DRIVER__SV

// Completer-side driver. APB is non-pipelined with exactly one transfer in
// flight, so this is a straight reactive loop with no outstanding queues:
//
//   1. Wait for a SETUP cycle to be sampled (PSEL HIGH, PENABLE LOW). The
//      monitor sampled the same edge and forwarded the request through
//      response_req_port to the slave sequence.
//   2. Fetch the sequence's response item (rdata / slverr / num_wait_states).
//      The slave sequence must produce it in zero simulation time -- the
//      same rule as the ovip_axi slave stack.
//   3. Hold PREADY LOW for num_wait_states ACCESS cycles, then drive PREADY
//      HIGH together with PRDATA (reads) and PSLVERR.
//   4. After the completion cycle, return to idle levels and item_done().
class ovip_apb_slave_driver extends uvm_driver#(ovip_apb_trans);

	virtual ovip_apb_agent_if vif;
	ovip_apb_agent_config     cfg;
	string MESSAGE_TAG;

	protected bit item_in_progress;

	protected ovip_apb_data_t DATA_MASK;

	`uvm_component_utils(ovip_apb_slave_driver)

	function new(string name = "ovip_apb_slave_driver", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);

	extern virtual task          rst_monitor();
	extern virtual function void drive_reset_values();
	extern virtual task          response_driver();
	extern virtual task          drive_response(ovip_apb_trans tr);

endclass : ovip_apb_slave_driver


function void ovip_apb_slave_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!uvm_config_db#(virtual ovip_apb_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))
	if(!uvm_config_db#(ovip_apb_agent_config)::get(this, "", "cfg", cfg))
		`uvm_fatal("MISSING_CFG", $sformatf("Missing agent config - %s.cfg", get_full_name()))
	MESSAGE_TAG = (cfg.agent_tag == "") ? "" : {cfg.agent_tag, "/"};

	DATA_MASK = (ovip_apb_data_t'(1) << cfg.data_width*8) - 1;
endfunction : build_phase


task ovip_apb_slave_driver::run_phase(uvm_phase phase);
	drive_reset_values();
	@(vif.slave_cb iff vif.slave_cb.presetn);

	forever
	begin
		`OVIP_BEGIN_FIRST_OF
			rst_monitor();
			response_driver();
		`OVIP_END_FIRST_OF

		drive_reset_values();
		if(item_in_progress)
		begin
			// Release the sequencer if a response was killed by reset.
			`uvm_info({MESSAGE_TAG, "APB_SLAVE_DRV"}, "Reset killed an in-flight response -- completing it to release the sequencer", UVM_LOW)
			seq_item_port.item_done();
			item_in_progress = 0;
		end
		if(vif.slave_cb.presetn == 1'b0)
			@(vif.slave_cb iff vif.slave_cb.presetn);
	end
endtask : run_phase


task ovip_apb_slave_driver::rst_monitor();
	@(vif.slave_cb iff vif.slave_cb.presetn == 1'b0);
endtask : rst_monitor


function void ovip_apb_slave_driver::drive_reset_values();
	vif.slave_cb.pready  <= 1'b0;
	vif.slave_cb.prdata  <= '0;
	vif.slave_cb.pslverr <= 1'b0;
endfunction : drive_reset_values


task ovip_apb_slave_driver::response_driver();
	forever
	begin
		// SETUP cycle sampled. The monitor pushed the request to the slave
		// sequence at this same edge; the sequence answers in zero time.
		@(vif.slave_cb iff (vif.slave_cb.psel == 1'b1 && vif.slave_cb.penable == 1'b0));

		seq_item_port.get_next_item(req);
		item_in_progress = 1;

		// Timing note: to complete with zero wait states we must still be
		// aligned to the clocking-block event the SETUP was sampled on. This
		// holds as long as the slave sequence does not consume simulation
		// time between getting the request and finishing the response item.
		`ifndef XCELIUM
		if(!vif.slave_cb.triggered)
		begin
			`uvm_warning({MESSAGE_TAG, "APB_SLAVE_DRV"}, "Slave sequence returned an item off the clocking-block edge; response timing shifts by the cycles consumed.")
		end
		`endif

		drive_response(req);

		seq_item_port.item_done();
		item_in_progress = 0;
	end
endtask : response_driver


task ovip_apb_slave_driver::drive_response(ovip_apb_trans tr);
	// Wait states: PREADY LOW for the requested number of ACCESS cycles.
	repeat(tr.num_wait_states)
	begin
		vif.slave_cb.pready <= 1'b0;
		@(vif.slave_cb);
	end

	// Completion cycle: PREADY HIGH with the response payload.
	vif.slave_cb.pready <= 1'b1;
	if(!tr.write)
		vif.slave_cb.prdata <= tr.rdata & DATA_MASK;
	if(cfg.pslverr_en)
		vif.slave_cb.pslverr <= tr.slverr;
	@(vif.slave_cb);

	tr.transaction_finished = 1;
	if(cfg.drive_reset_values_when_idle)
		drive_reset_values();
	else
		vif.slave_cb.pready <= 1'b0;
endtask : drive_response

`endif
