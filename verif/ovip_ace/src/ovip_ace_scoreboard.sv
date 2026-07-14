`ifndef OVIP_ACE_SCOREBOARD__SV
`define OVIP_ACE_SCOREBOARD__SV

// Reference scoreboard for ovip_ace traffic. Inherits the whole AXI
// expected/actual pairing (per-direction, per-ID FIFOs) from
// ovip_axi_scoreboard and adds a third analysis export for reconstructed snoop
// transactions (direction == SNOOP) coming off the monitor's snoop_analysis_port.
//
// v0.1 only counts snoops and logs them; a full snoop predictor (checking the
// master's CRRESP against a modelled cache state) is a CONTRIBUTING.md
// wanted-feature. Because ovip_ace_trans is an ovip_axi_trans, the inherited
// exp_ap / act_ap exports accept ACE transactions unchanged.
//
// Typical wiring:
//     predictor.analysis_port.connect(scoreboard.exp_ap);
//     slave_agent.mon.analysis_port.connect(scoreboard.act_ap);
//     master_agent.mon.snoop_analysis_port.connect(scoreboard.snoop_ap);

`uvm_analysis_imp_decl(_snoop)

class ovip_ace_scoreboard extends ovip_axi_scoreboard;

	`uvm_component_utils(ovip_ace_scoreboard)

	uvm_analysis_imp_snoop#(ovip_ace_trans, ovip_ace_scoreboard) snoop_ap;

	int snoops_observed = 0;

	function new(string name = "ovip_ace_scoreboard", uvm_component parent = null);
		super.new(name, parent);
		snoop_ap = new("snoop_ap", this);
	endfunction

	// Observe a reconstructed snoop. The monitor already ran the D3.7 / D5
	// consistency checks; here we just account for it.
	virtual function void write_snoop(ovip_ace_trans t);
		snoops_observed++;
		`uvm_info("ACE_SB/SNOOP", t.convert2string(), UVM_HIGH)
	endfunction

	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("ACE_SB/REPORT", $sformatf("snoops_observed=%0d", snoops_observed), UVM_LOW)
	endfunction

endclass

`endif
