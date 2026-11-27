`ifndef OVIP_AXI_STREAM_SCOREBOARD__SV
`define OVIP_AXI_STREAM_SCOREBOARD__SV

// Reference scoreboard for ovip_axi_stream traffic. Receives "expected"
// packets on exp_ap (typically from a predictor or a transmitter-side mirror)
// and "actual" packets on act_ap (typically from the receiver-side monitor's
// analysis port) and pairs them off per stream ({TID, TDEST}), in the order
// each side delivers them: AXI-Stream preserves ordering within a stream
// (spec section 2.7 and 4.2).
//
// The two sides may arrive in any order. A packet whose partner is not there
// yet waits in a per-{id, dest} FIFO and is compared when the partner arrives.
//
// Mismatches raise UVM_ERROR (AXIS_SB/MISMATCH) built from
// ovip_axi_stream_trans::diff(), so the log shows which interface-signal
// fields disagreed. What never paired up is reported at check_phase: an
// expected packet with no actual one as AXIS_SB/ORPHAN, an actual packet with
// no expected one as AXIS_SB/UNEXPECTED. report_phase prints the four counters.
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

	typedef bit [`OVIP_AXI_STREAM_MAX_ID_WIDTH + `OVIP_AXI_STREAM_MAX_DEST_WIDTH - 1 : 0] stream_key_t;

	// Per-stream ({id, dest}) FIFOs of expected packets and of actual packets
	// that arrived before their expected one. For one stream only one side waits.
	protected ovip_axi_stream_trans expected[stream_key_t][$];
	protected ovip_axi_stream_trans actual[stream_key_t][$];

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


	protected virtual function void compare_pair(ovip_axi_stream_trans exp, ovip_axi_stream_trans act);
		if(exp.compare(act)) begin
			matched++;
		end
		else begin
			mismatches++;
			`uvm_error("AXIS_SB/MISMATCH",
				$sformatf("packet mismatch (%s):\n%s", exp.convert2string(), exp.diff(act)))
		end
	endfunction : compare_pair


	virtual function void write_exp(ovip_axi_stream_trans t);
		ovip_axi_stream_trans entry;
		stream_key_t key;
		if(defensive_copy_expected) begin
			if(!$cast(entry, t.clone())) `uvm_fatal("CAST_FAILED", "ovip_axi_stream_scoreboard::write_exp: clone failed")
			entry.set_name("exp_cp");
		end
		else begin
			entry = t;
		end
		key = {entry.id, entry.dest};
		if(actual.exists(key) && actual[key].size())
			compare_pair(entry, actual[key].pop_front());
		else
			expected[key].push_back(entry);
	endfunction : write_exp


	virtual function void write_act(ovip_axi_stream_trans t);
		stream_key_t key = {t.id, t.dest};
		if(expected.exists(key) && expected[key].size())
			compare_pair(expected[key].pop_front(), t);
		else
			actual[key].push_back(t);
	endfunction : write_act


	virtual function void check_phase(uvm_phase phase);
		ovip_axi_stream_trans tr;
		super.check_phase(phase);
		foreach(expected[key]) while(expected[key].size()) begin
			tr = expected[key].pop_front();
			`uvm_error("AXIS_SB/ORPHAN", $sformatf("expected packet never arrived: %s", tr.convert2string()))
			orphans++;
		end
		foreach(actual[key]) while(actual[key].size()) begin
			tr = actual[key].pop_front();
			`uvm_error("AXIS_SB/UNEXPECTED",
				$sformatf("packet id=%0d dest=%0d arrived with no expected match: %s",
					tr.id, tr.dest, tr.convert2string()))
			unexpected++;
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
