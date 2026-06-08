`ifndef OVIP_AXI_STREAM_SCOREBOARD__SV
`define OVIP_AXI_STREAM_SCOREBOARD__SV

// Reference scoreboard for ovip_axi_stream traffic. Receives "expected"
// packets (typically from a predictor or a transmitter-side mirror) and
// "actual" packets (typically from the receiver-side monitor's analysis port)
// and pairs them off per TID. Expected entries are sorted into per-TID FIFOs
// so AXI-Stream's same-source in-order rule is respected.
//
// Mismatches raise UVM_ERROR built from ovip_axi_stream_trans::diff(), so the
// log shows exactly which interface-signal fields disagreed. Orphans and
// unexpected actuals are counted separately and reported at end-of-test.
//
// Typical wiring:
//     predictor.analysis_port.connect(scoreboard.exp_ap);
//     receiver_agent.mon.analysis_port.connect(scoreboard.act_ap);


class ovip_axi_stream_scoreboard extends uvm_component;
	`uvm_analysis_imp_decl(_exp)
	`uvm_analysis_imp_decl(_act)

	`uvm_component_utils(ovip_axi_stream_scoreboard)

	uvm_analysis_imp_exp#(ovip_axi_stream_trans, ovip_axi_stream_scoreboard) exp_ap;
	uvm_analysis_imp_act#(ovip_axi_stream_trans, ovip_axi_stream_scoreboard) act_ap;

	// Per-TID FIFO of expected packets. AXI-Stream is single-channel and
	// ordering is preserved across the bus (spec section 4.2), so per-TID
	// in-order match-up is sufficient.
	protected ovip_axi_stream_trans expected[ovip_axi_stream_id_t][$];

	// Default off -- assumes a well-behaved predictor that builds a fresh
	// trans per prediction and never mutates a published handle. Flip to 1
	// if the producer reuses transaction objects between writes.
	bit defensive_copy_expected = 0;

	int matched    = 0;
	int mismatches = 0;
	int unexpected = 0;
	int orphans    = 0;

	function new(string name = "ovip_axi_stream_scoreboard", uvm_component parent = null);
		super.new(name, parent);
		exp_ap = new("exp_ap", this);
		act_ap = new("act_ap", this);
	endfunction : new


	virtual function void write_exp(ovip_axi_stream_trans t);
		ovip_axi_stream_trans entry;
		if(defensive_copy_expected) begin
			entry = ovip_axi_stream_trans::type_id::create("exp_cp");
			entry.copy(t);
		end
		else begin
			entry = t;
		end
		expected[entry.id].push_back(entry);
	endfunction : write_exp


	virtual function void write_act(ovip_axi_stream_trans t);
		ovip_axi_stream_trans exp;
		if(!expected.exists(t.id) || expected[t.id].size() == 0) begin
			`uvm_error("AXIS_SB/UNEXPECTED",
				$sformatf("packet id=%0d arrived with no expected match: %s", t.id, t.convert2string()))
			unexpected++;
			return;
		end
		exp = expected[t.id].pop_front();
		if(exp.compare(t)) begin
			matched++;
		end
		else begin
			mismatches++;
			`uvm_error("AXIS_SB/MISMATCH",
				$sformatf("packet mismatch (%s):\n%s", exp.convert2string(), exp.diff(t)))
		end
	endfunction : write_act


	virtual function void check_phase(uvm_phase phase);
		ovip_axi_stream_trans tr;
		super.check_phase(phase);
		foreach(expected[id]) while(expected[id].size()) begin
			tr = expected[id].pop_front();
			`uvm_error("AXIS_SB/ORPHAN", $sformatf("expected packet never arrived: %s", tr.convert2string()))
			orphans++;
		end
	endfunction : check_phase


	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("AXIS_SB/REPORT",
			$sformatf("matched=%0d mismatches=%0d unexpected=%0d orphans=%0d",
				matched, mismatches, unexpected, orphans), UVM_LOW)
	endfunction : report_phase

endclass : ovip_axi_stream_scoreboard

`endif
