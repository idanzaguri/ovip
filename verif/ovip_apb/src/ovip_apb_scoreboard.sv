`ifndef OVIP_APB_SCOREBOARD__SV
`define OVIP_APB_SCOREBOARD__SV

// Reference scoreboard for ovip_apb traffic. Receives "expected" transfers
// (typically from the requester-side monitor or a predictor) and "actual"
// transfers (typically from the completer-side monitor) and pairs them off
// in order -- APB is non-pipelined and strictly ordered, so a single FIFO per
// side is sufficient.
//
// Both sides are queued and matched as soon as a pair is available, so the
// scoreboard is insensitive to which monitor publishes first within the same
// completion timestep.
//
// Mismatches raise UVM_ERROR built from ovip_apb_trans::diff(), so the log
// shows exactly which interface-signal fields disagreed. Orphans on either
// side are flagged at check_phase.
//
// Typical wiring:
//     requester_agent.mon.analysis_port.connect(scoreboard.exp_ap);
//     completer_agent.mon.analysis_port.connect(scoreboard.act_ap);
class ovip_apb_scoreboard extends uvm_component;
	`uvm_analysis_imp_decl(_exp)
	`uvm_analysis_imp_decl(_act)

	`uvm_component_utils(ovip_apb_scoreboard)

	uvm_analysis_imp_exp#(ovip_apb_trans, ovip_apb_scoreboard) exp_ap;
	uvm_analysis_imp_act#(ovip_apb_trans, ovip_apb_scoreboard) act_ap;

	protected ovip_apb_trans expected[$];
	protected ovip_apb_trans actual[$];

	// Default off -- assumes a well-behaved producer that builds a fresh
	// trans per publication and never mutates a published handle. Flip to 1
	// if the producer reuses transaction objects between writes.
	bit defensive_copy_expected = 0;

	int matched    = 0;
	int mismatches = 0;
	int orphans    = 0;

	function new(string name = "ovip_apb_scoreboard", uvm_component parent = null);
		super.new(name, parent);
		exp_ap = new("exp_ap", this);
		act_ap = new("act_ap", this);
	endfunction : new


	virtual function void write_exp(ovip_apb_trans t);
		ovip_apb_trans entry;
		if(defensive_copy_expected)
		begin
			entry = ovip_apb_trans::type_id::create("exp_cp");
			entry.copy(t);
		end
		else
		begin
			entry = t;
		end
		expected.push_back(entry);
		try_match();
	endfunction : write_exp


	virtual function void write_act(ovip_apb_trans t);
		actual.push_back(t);
		try_match();
	endfunction : write_act


	protected virtual function void try_match();
		while(expected.size() && actual.size())
		begin
			ovip_apb_trans exp = expected.pop_front();
			ovip_apb_trans act = actual.pop_front();
			if(exp.compare(act))
			begin
				matched++;
			end
			else
			begin
				mismatches++;
				`uvm_error("APB_SB/MISMATCH",
					$sformatf("transfer mismatch (%s):\n%s", exp.convert2string(), exp.diff(act)))
			end
		end
	endfunction : try_match


	virtual function void check_phase(uvm_phase phase);
		ovip_apb_trans tr;
		super.check_phase(phase);
		while(expected.size())
		begin
			tr = expected.pop_front();
			`uvm_error("APB_SB/ORPHAN", $sformatf("expected transfer never arrived: %s", tr.convert2string()))
			orphans++;
		end
		while(actual.size())
		begin
			tr = actual.pop_front();
			`uvm_error("APB_SB/ORPHAN", $sformatf("actual transfer had no expected match: %s", tr.convert2string()))
			orphans++;
		end
	endfunction : check_phase


	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("APB_SB/REPORT",
			$sformatf("matched=%0d mismatches=%0d orphans=%0d", matched, mismatches, orphans), UVM_LOW)
	endfunction : report_phase

endclass : ovip_apb_scoreboard

`endif
