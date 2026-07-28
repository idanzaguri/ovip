`ifndef OVIP_APB_AGENT__SV
`define OVIP_APB_AGENT__SV

class ovip_apb_agent extends uvm_agent;
	ovip_apb_agent_config cfg;
	virtual ovip_apb_agent_if vif;

	ovip_apb_monitor mon;
	ovip_apb_trans_logger trans_logger; // created only when cfg.enable_trans_log

	// Active-only handles. The requester drives transfers from `master_sqr`;
	// the completer is reactive: the monitor forwards each request through
	// its response_req_port, the slave sequence builds the response, and the
	// slave driver plays it out through the normal seq_item path.
	ovip_apb_master_driver              master_drv;
	uvm_sequencer#(ovip_apb_trans)      master_sqr;
	ovip_apb_slave_driver               slave_drv;
	ovip_apb_slave_sequencer            slave_sqr;

	`uvm_component_utils(ovip_apb_agent)

	function new(string name = "ovip_apb_agent", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual function void connect_phase(uvm_phase phase);

endclass : ovip_apb_agent


function void ovip_apb_agent::build_phase(uvm_phase phase);
	if(cfg == null)
		if(!uvm_config_db#(ovip_apb_agent_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("MISSING_CFG", $sformatf("Missing config object - %s.cfg", get_full_name()))
	void'(cfg.check_config());

	is_active = cfg.is_active;
	super.build_phase(phase);

	// Push cfg down to children so each build_phase finds it.
	uvm_config_db#(ovip_apb_agent_config)::set(this, "mon", "cfg", cfg);

	mon = ovip_apb_monitor::type_id::create("mon", this);
	mon.cfg = cfg;

	if(cfg.enable_trans_log)
	begin
		string base = (cfg.agent_tag != "") ? cfg.agent_tag : get_name();
		trans_logger = ovip_apb_trans_logger::type_id::create("trans_logger", this);
		trans_logger.label              = base;
		trans_logger.file_name          = (cfg.trans_log_file != "") ? cfg.trans_log_file : $sformatf("%s_trans.log", base);
		trans_logger.combined_file_name = cfg.trans_log_combined_file;
		trans_logger.format             = cfg.trans_log_format;
	end

	if(get_is_active())
	begin
		if(cfg.agent_type == OVIP_APB_REQUESTER)
		begin
			uvm_config_db#(ovip_apb_agent_config)::set(this, "master_drv", "cfg", cfg);
			master_drv = ovip_apb_master_driver::type_id::create("master_drv", this);
			master_drv.cfg = cfg;
			master_sqr = uvm_sequencer#(ovip_apb_trans)::type_id::create("master_sqr", this);
		end
		else
		begin
			uvm_config_db#(ovip_apb_agent_config)::set(this, "slave_drv", "cfg", cfg);
			slave_drv = ovip_apb_slave_driver::type_id::create("slave_drv", this);
			slave_drv.cfg = cfg;
			slave_sqr = ovip_apb_slave_sequencer::type_id::create("slave_sqr", this);
		end
	end
endfunction : build_phase


function void ovip_apb_agent::connect_phase(uvm_phase phase);
	super.connect_phase(phase);

	if(!uvm_config_db#(virtual ovip_apb_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))

	mon.vif = vif;

	if(trans_logger != null)
		mon.analysis_port.connect(trans_logger.analysis_export);

	if(get_is_active())
	begin
		if(cfg.agent_type == OVIP_APB_REQUESTER)
		begin
			master_drv.vif = vif;
			master_drv.seq_item_port.connect(master_sqr.seq_item_export);
		end
		else
		begin
			slave_drv.vif       = vif;
			slave_drv.seq_item_port.connect(slave_sqr.seq_item_export);
			slave_sqr.cfg       = cfg;
			slave_sqr.slave_drv = slave_drv;
			slave_sqr.response_req_port.connect(mon.response_req_port);
		end
	end
endfunction : connect_phase

`endif
