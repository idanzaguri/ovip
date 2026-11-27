`ifndef OVIP_CHECK_REPORTS__SV
`define OVIP_CHECK_REPORTS__SV

// How one agent reports its checks. A check is named by its message ID, the
// ID that the README of the VIP lists for it, without the agent tag.
//
// Every OVIP agent config has one object of this class (cfg.check_reports) and
// the two methods cfg.set_check_severity() and cfg.set_check_action() that
// fill it. The agent applies it in connect_phase to itself and to every
// component under it: the monitor, the driver, and the sequencer, through
// which the sequences report.
//
// Only the report of a check changes. The check itself still runs, and what
// it does beside the report stays.
class ovip_check_reports extends uvm_object;

	uvm_severity severities[string]; // message ID -> the severity the check is reported with
	uvm_action   actions[string];    // message ID -> the UVM action of the report

	`uvm_object_utils(ovip_check_reports)

	function new(string name = "ovip_check_reports");
		super.new(name);
	endfunction : new


	// The check `id` is reported with `severity` in place of UVM_WARNING or
	// UVM_ERROR. UVM_INFO prints it as a UVM_INFO line.
	function void set_severity(string id, uvm_severity severity);
		severities[id] = severity;
	endfunction : set_severity


	// The report of the check `id` gets the UVM action `action`.
	// UVM_NO_ACTION prints nothing and counts nothing.
	function void set_action(string id, uvm_action action);
		actions[id] = action;
	endfunction : set_action


	virtual function void do_copy(uvm_object rhs);
		ovip_check_reports c;
		if(!$cast(c, rhs)) `uvm_fatal("CAST_FAILED", "ovip_check_reports::do_copy: rhs is not an ovip_check_reports")
		super.do_copy(rhs);
		severities = c.severities;
		actions    = c.actions;
	endfunction : do_copy


	// Sets the UVM report overrides on `comp` and on every component under it.
	// A monitor or a driver puts "<agent_tag>/" before its message IDs, and a
	// sequence does not, so each ID is set in both forms.
	function void apply(uvm_component comp, string agent_tag = "");
		uvm_component children[$];

		foreach(severities[id])
		begin
			apply_severity(comp, id, severities[id]);
			if(agent_tag != "") apply_severity(comp, {agent_tag, "/", id}, severities[id]);
		end

		foreach(actions[id])
		begin
			apply_action(comp, id, actions[id]);
			if(agent_tag != "") apply_action(comp, {agent_tag, "/", id}, actions[id]);
		end

		comp.get_children(children);
		foreach(children[ii]) apply(children[ii], agent_tag);
	endfunction : apply


	// A check is a UVM_WARNING or a UVM_ERROR. A uvm_fatal is not a check.
	protected function void apply_severity(uvm_component comp, string id, uvm_severity severity);
		comp.set_report_severity_id_override(UVM_WARNING, id, severity);
		comp.set_report_severity_id_override(UVM_ERROR,   id, severity);
	endfunction : apply_severity


	// UVM takes the action of a report by the severity it has after the
	// severity override, so the action is set for all four of them.
	protected function void apply_action(uvm_component comp, string id, uvm_action action);
		comp.set_report_severity_id_action(UVM_INFO,    id, action);
		comp.set_report_severity_id_action(UVM_WARNING, id, action);
		comp.set_report_severity_id_action(UVM_ERROR,   id, action);
		comp.set_report_severity_id_action(UVM_FATAL,   id, action);
	endfunction : apply_action

endclass : ovip_check_reports

`endif
