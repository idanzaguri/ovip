`ifndef OVIP_AXI_AGENT__SV
`define OVIP_AXI_AGENT__SV

class ovip_axi_agent extends uvm_agent;
	ovip_axi_agent_config cfg;

	virtual ovip_axi_agent_if vif;

	ovip_axi_monitor#()     mon;
	ovip_axi_base_driver#() drv;
	ovip_axi_base_sequencer sqr;

	ovip_axi_trans_logger   trans_logger; // created only when cfg.enable_trans_log


	`uvm_component_param_utils(ovip_axi_agent)

	function new(string name = "ovip_axi_agent", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual function void connect_phase(uvm_phase phase);

endclass : ovip_axi_agent


function void ovip_axi_agent::build_phase(uvm_phase phase);
	if(cfg == null)
	begin
		if(!uvm_config_db#(ovip_axi_agent_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("MISSING_CFG", $sformatf("Missing config object - %s.cfg", get_full_name()))
	end
	void'(cfg.check_config());

	is_active = cfg.is_active;

	super.build_phase(phase);

	mon = ovip_axi_monitor#()::type_id::create("mon", this);
	mon.cfg = cfg;

	if(cfg.enable_trans_log)
	begin
		string base = (cfg.agent_tag != "") ? cfg.agent_tag : get_name();
		trans_logger = ovip_axi_trans_logger::type_id::create("trans_logger", this);
		trans_logger.label              = base;
		trans_logger.file_name          = (cfg.trans_log_file != "") ? cfg.trans_log_file : $sformatf("%s_trans.log", base);
		trans_logger.combined_file_name = cfg.trans_log_combined_file;
		trans_logger.format             = cfg.trans_log_format;
	end

	if(get_is_active())
	begin
		if(cfg.agent_type == OVIP_SLAVE_AGENT)
		begin
			drv = ovip_axi_slave_driver#()::type_id::create("drv", this);
			sqr = ovip_axi_slave_sequencer::type_id::create("sqr", this);
		end
		else
		begin
			drv = ovip_axi_master_driver#()::type_id::create("drv", this);
			sqr = ovip_axi_base_sequencer::type_id::create("sqr", this);
		end
		drv.cfg = cfg;
		sqr.cfg = cfg;
	end

endfunction : build_phase

function void ovip_axi_agent::connect_phase(uvm_phase phase);
	super.connect_phase(phase);

	if (!uvm_config_db#(virtual ovip_axi_agent_if)::get(this, "", "vif", vif))
	begin
		`uvm_fatal("MISSING_VIF",$sformatf("Missing virtual interface - %s.vif", this.get_full_name() ))
	end

	vif.is_master = (cfg.agent_type == OVIP_MASTER_AGENT);
	vif.is_active = (get_is_active());

	mon.vif = vif;

	if(trans_logger != null)
		mon.analysis_port.connect(trans_logger.analysis_export);

	if(get_is_active())
	begin
		sqr.vif = vif;
		drv.vif = vif;
		drv.seq_item_port.connect(sqr.seq_item_export);

		if(cfg.agent_type == OVIP_SLAVE_AGENT)
		begin
			ovip_axi_slave_sequencer slv_sqr;
			if(!$cast(slv_sqr, sqr)) `uvm_fatal("CAST_FAILED", "ovip_axi_slave_sequencer")
			slv_sqr.response_req_port.connect(mon.response_req_port);
		end
	end
endfunction : connect_phase

`endif
