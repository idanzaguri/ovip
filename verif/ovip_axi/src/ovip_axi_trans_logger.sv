`ifndef OVIP_AXI_TRANS_LOGGER__SV
`define OVIP_AXI_TRANS_LOGGER__SV

// ovip_axi_trans_logger -- writes one text line per completed transaction to a
// per-agent log file (and, optionally, a shared combined file). It subscribes
// to the monitor's analysis_port, which fires once per completed transaction,
// so each line carries the full transaction plus its phase timestamps
// (addr / data-begin / data-end / response). Works on active and passive agents.
//
// The agent instantiates and connects this automatically when
// cfg.enable_trans_log is set; see ovip_axi_agent. Because it is a
// uvm_subscriber#(ovip_axi_trans) and log_line() is virtual, an ACE agent gets
// the coherency columns for free (the trans is an ovip_ace_trans subclass).
//
// Combined file: several loggers given the same combined path share one file
// handle (kept in a static map keyed by path) so their lines interleave in
// simulation-time order into a single file. First opener writes the header;
// the file is closed once the last logger using it reaches final_phase.

class ovip_axi_trans_logger extends uvm_subscriber #(ovip_axi_trans);

	`uvm_component_utils(ovip_axi_trans_logger)

	// Set by the agent from cfg before start_of_simulation.
	string                      label = "";              // per-line agent label
	string                      file_name = "";          // per-agent file (empty => disabled)
	string                      combined_file_name = ""; // shared file (empty => none)
	ovip_axi_trans_log_format_e format = OVIP_AXI_TRANS_LOG_TABLE;

	protected int fd = 0;

	// Shared combined-file handles + refcounts, keyed by path.
	protected static int _combined_fd[string];
	protected static int _combined_refs[string];

	// Set a readable %t format (nanoseconds) once, for the timestamp columns.
	protected static bit _timeformat_set = 0;

	function new(string name = "ovip_axi_trans_logger", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	extern virtual function void start_of_simulation_phase(uvm_phase phase);
	extern virtual function void write(ovip_axi_trans t);
	extern virtual function void final_phase(uvm_phase phase);

	// Build the full line: completion time + agent label + the trans's columns.
	protected virtual function string format_line(ovip_axi_trans t);
		string body = (format == OVIP_AXI_TRANS_LOG_RAW) ? t.convert2string() : t.log_line();
		return $sformatf("%-11s %-9s %s", $sformatf("%0t", $time), label, body);
	endfunction : format_line

endclass : ovip_axi_trans_logger


function void ovip_axi_trans_logger::start_of_simulation_phase(uvm_phase phase);
	// A factory-created trans so the header matches the actual (possibly ACE)
	// transaction type via the agent's type override.
	ovip_axi_trans hdr = ovip_axi_trans::type_id::create("log_hdr");
	string header = $sformatf("%-11s %-9s %s", "end_time", "agent", hdr.log_header());
	super.start_of_simulation_phase(phase);

	// Human-readable nanosecond timestamps for the %t columns (set once).
	if(!_timeformat_set)
	begin
		$timeformat(-9, 3, "ns", 0);
		_timeformat_set = 1;
	end

	if(file_name != "")
	begin
		fd = $fopen(file_name, "w");
		if(fd == 0)
			`uvm_warning("AXI_LOG", $sformatf("could not open transaction log '%s'", file_name))
		else if(format == OVIP_AXI_TRANS_LOG_TABLE)
			$fdisplay(fd, "%s", header);
	end

	if(combined_file_name != "")
	begin
		if(!_combined_fd.exists(combined_file_name))
		begin
			int cfd = $fopen(combined_file_name, "w");
			if(cfd == 0)
				`uvm_warning("AXI_LOG", $sformatf("could not open combined transaction log '%s'", combined_file_name))
			_combined_fd[combined_file_name]   = cfd;
			_combined_refs[combined_file_name] = 0;
			if(cfd != 0 && format == OVIP_AXI_TRANS_LOG_TABLE)
				$fdisplay(cfd, "%s", header);
		end
		_combined_refs[combined_file_name]++;
	end
endfunction : start_of_simulation_phase


function void ovip_axi_trans_logger::write(ovip_axi_trans t);
	string line = format_line(t);
	if(fd != 0)
		$fdisplay(fd, "%s", line);
	if(combined_file_name != "" && _combined_fd.exists(combined_file_name) && _combined_fd[combined_file_name] != 0)
		$fdisplay(_combined_fd[combined_file_name], "%s", line);
endfunction : write


function void ovip_axi_trans_logger::final_phase(uvm_phase phase);
	super.final_phase(phase);
	if(fd != 0)
	begin
		$fclose(fd);
		fd = 0;
	end
	if(combined_file_name != "" && _combined_refs.exists(combined_file_name))
	begin
		_combined_refs[combined_file_name]--;
		if(_combined_refs[combined_file_name] <= 0)
		begin
			if(_combined_fd[combined_file_name] != 0) $fclose(_combined_fd[combined_file_name]);
			_combined_fd.delete(combined_file_name);
			_combined_refs.delete(combined_file_name);
		end
	end
endfunction : final_phase

`endif
