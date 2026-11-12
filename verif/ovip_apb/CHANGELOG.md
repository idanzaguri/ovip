# Changelog

All notable changes to this VIP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

## [0.4.0] -- 2026-11-12

### Added -- VIP

- `check_undefined_data_lanes` in `ovip_apb_agent_config`, 0 by default.
  With 1 the monitor checks every lane of PWDATA inside the data width for
  X/Z and for stability, whatever PSTRB says, as it did up to 0.3.0. See
  the change below.
- The monitor reports PSEL and PENABLE both HIGH while no transfer is in
  progress, an ACCESS cycle with no SETUP cycle before it (spec section
  4.1), as `APB_MON/FSM`, "PSEL and PENABLE HIGH with no transfer in
  progress". It was not checked: a requester that raises the two together
  got no message and no PREADY. It is one report per occurrence, on the
  first such cycle. PENABLE left HIGH after a completion keeps its own
  report and gets no second one.

### Changed -- VIP

- The monitor checks PWDATA for X/Z and for stability only on the lanes
  whose PSTRB bit is HIGH, the lanes that must be valid in a write (spec
  Appendix A.1). It checked every lane inside the data width, so a
  requester that leaves a lane with a LOW strobe at X, or changes it
  during the transfer, got `APB_MON/XZ_CHECK` and `APB_MON/STABILITY`
  errors on legal traffic: one write with PSTRB 4'b0011 and X on
  PWDATA[31:16] gave 10. An agent with `pstrb_en = 0` has no such lane
  and is checked on every lane as before. To keep the checks on every
  lane, set `cfg.check_undefined_data_lanes = 1`.
- `ovip_apb_base_slave_sequence`, for the three fixes of it below. `min_ws`
  and `max_ws` hold `WS_FROM_CFG` (all ones), not 0, until `body()` starts:
  the new `apply_default_wait_states()` then gives cfg's default to a knob
  still at that value. A subclass with a `body()` of its own calls it
  first. The protected `decompose_addr` and the memory word size it used
  are gone: a subclass that called it uses `bus_aligned_addr(req)`. A
  write with every strobe LOW no longer creates the line in the memory.
- `setup_time` and `complete_time` of `ovip_apb_trans` are `realtime`
  fields, filled from `$realtime`: ns with their fraction. They were
  `time` fields filled from `$time`, whole ns, so on a clock with edges
  off whole ns a completion at 7.5 ns was stamped 8. Code that copies them
  into a `time` variable or prints them with `%t` or `%0d` needs a change:
  the value is a real number of ns, `%0.3f` prints it.
- The transaction logger prints its times itself, in ns with three
  decimals, and no longer calls `$timeformat`. It set the `%t` format of
  the whole simulation at start of simulation, so with a logger on, every
  `%t` of the testbench and the time in UVM's messages changed to three
  decimals. The log lines look as before. A testbench that relied on that
  format calls `$timeformat(-9, 3, "ns", 0)` itself.
- `cfg.is_active` alone decides whether an agent is active. The agent
  took an `is_active` from the UVM config DB over it, while its monitor
  read the cfg. With the two different, a completer ended at build in
  "Cannot connect to null port handle". Set `cfg.is_active`: an
  `is_active` in the config DB is no longer used.
- CONTRIBUTING.md has a "Known gaps" section: a reset in the time step in
  which a sequence calls `start_item` can end in "Get_next_item called
  twice".

### Fixed -- VIP

- The stability check of PWDATA compared the wire with a 2-state copy of
  the SETUP value, so an X or Z bit that never changed was reported as
  "PWDATA changed during a write transfer" on every ACCESS cycle, next to
  its `APB_MON/XZ_CHECK`. A bit that stays X or Z is no longer a change.
- A reset in the requester's idle gap after a transfer (an item with
  `delay_until_next_trans` above 0) made the master driver drive the
  finished transfer a second time after the release, and the run then ended
  in `UVM_FATAL`, "Item_done() called with no outstanding requests". The
  driver kept the finished item through the reset. It drops the item it
  holds at every reset now. It also releases an item it took and has not
  started yet (it waits for the clock edge) when the reset comes on that
  edge: the item is completed to the sequencer and never driven, like a
  transfer the reset cuts.
- After a requester broke the operating states (a SETUP of two cycles, or
  an ACCESS left while PREADY was LOW and followed by a new SETUP), the
  completer answered every later transfer with the response built for the
  request before it, and nothing reported it after the first `APB_MON/FSM`.
  The monitor forwards a request for the SETUP cycle it sees inside the
  broken transfer, and the slave driver did not read PSEL and PENABLE while
  it drove a response, so it took no item for that request. In two cases
  the requester then waited for PREADY with no end: a SETUP of two cycles
  answered with no wait states (PREADY came in the second SETUP cycle),
  and PENABLE X on a SETUP cycle (the driver took no item at all). The
  slave driver now reads PSEL and PENABLE on every cycle of a response,
  with the tests the monitor uses: a cycle that is not ACCESS ends the
  response, and when it is a SETUP cycle the response to the new request
  starts on that edge.
- `apb_write` with its default `strb` argument (all ones) made the master
  driver print "Argument 0xf exceeds the configured width of PSTRB" for
  every write on an 8-bit or 16-bit bus (`data_width` 1 or 2). The data
  was right: the driver masks the strobes to the bus width. The driver no
  longer checks `strb` on an agent with `pstrb_en = 0`, where it is not
  driven, and it takes all ones as every lane of the bus. A strobe with a
  bit above the bus width that is not all ones still gets the warning.
- `ovip_apb_base_slave_sequence` answered OKAY to a read with PSTRB
  active, although its header promises PSLVERR for a request the monitor
  flags (`tr.monitor_error`). The monitor forwarded its copy of the
  request before it ran the check that sets the flag. The check runs
  first now: such a read is answered PSLVERR with read data 0, and the
  transaction on `analysis_port_cont` has the flag when it is published.
- The monitor checked that PSTRB is LOW in a read (spec section 3.2) on
  the SETUP cycle only. A PSTRB that goes active in the ACCESS cycles was
  not reported. `APB_MON/READ_STRB` covers every cycle of a read now, with
  one report per cycle.
- `ovip_apb_base_slave_sequence` set itself up in `pre_body()`. Started
  with `call_pre_post = 0`, as the `uvm_do` macros start a sequence, it
  kept a memory word size of 0 and every transfer landed on memory word 0
  with no message: a read of 0x10 returned the data written to 0x20. The
  setup is at the start of `body()` now.
- `min_ws` and `max_ws` of the base slave sequence, assigned or randomized
  before `start()`, were overwritten with the cfg defaults: 7 and 7 became
  0 and 3. Only `set_wait_states()` kept its values. A knob that was set
  keeps its value now, also when it was set to 0.
- With `data_width` 1 or 2 and a valid range of the memory that ends
  inside a 4-byte word, the base slave sequence answered OKAY to a
  transfer inside the range while `ovip_mem` reported `MEM/OUT_OF_RANGE`
  and did nothing: the write was lost and the read returned 0. The
  sequence checked the `data_width` bytes of the transfer and then
  accessed the whole memory word. It reads and writes those bytes only
  now, with `read_bytestream` and `write_bytestream`.
- The transaction log (`cfg.enable_trans_log`, TABLE format) wrote its
  waits column 50 characters wide, against 5 in the header, so every
  `setup_time` stood 45 characters to the right of its name. The column
  is 5 wide now.
- A SETUP cycle sampled on the same clock edge as PRESETn LOW could be
  taken as the start of a transfer: X/Z checks, a transaction on
  `analysis_port_cont`, a request forwarded to the slave sequence. It
  depended on which thread of the monitor the simulator woke first on
  that edge. 0.3.0 fixed the later edges of a transfer only. The monitor
  now tests PRESETn where it detects a SETUP cycle, from IDLE and on the
  cycle after a completion, and the slave driver does the same.
- The master driver set `transaction_finished` of an item at its
  completion and never cleared it, so an item that was sent a second time
  and cut by a reset still read 1. The driver clears the flag when it
  takes an item: after `send()` it is 1 for a transfer that completed and
  0 for an item that a reset released.
- The `SLAVE_SEQ/OUT_OF_RANGE` report said "answering PSLVERR" also on an
  agent with `pslverr_en = 0`, where the wire shows OKAY. It says
  "answering OKAY (this agent has no PSLVERR)" there now.
- `ovip_apb_agent_config` had no `do_copy`, so `cfg.clone()` and `copy()`
  gave a config with every field at its default. They carry every field
  now.
- Documentation. `NOTICE` named ovip_axi in its first line. The README
  table of compile-time defines lacked `OVIP_APB_MAX_STRB_WIDTH`. The
  comment of `ovip_apb_trans::bus_width` named drivers and printers: only
  the monitor sets the field, and nothing reads it.
- README and the comment in `ovip_apb_defines.sv`: a bare `tr.randomize()`
  of an `ovip_apb_trans` is not inside the agent's widths. The item does
  not know the cfg, so with `addr_width = 16` every randomized item got
  the PADDR width warning of the master driver. Both now say what a
  sequence has to constrain: `addr` inside `addr_width` and aligned, and
  on a narrow bus `wdata` and `strb`. The README has an example.
- `log_line()` of `ovip_apb_trans` printed the resp of an OKAY transfer as
  "  OKAY" on Verilator, and `convert2string()` printed "resp=  OKAY" and
  "APB  READ" on every simulator. A conditional of two string literals of
  different length is a packed value of the longer width, so the shorter
  one got leading zero bytes. Both functions take the texts from two small
  functions now, `dir_text()` and `resp_text()`, which return a string.
- The `SLAVE_SEQ/OUT_OF_RANGE` error of `ovip_apb_base_slave_sequence`
  printed "read" with a leading space on VCS: the text came from a
  conditional of "write" and "read", two string literals of different
  length. It is set with `if` now.
- The stability check of the monitor compared PADDR and PSTRB in the
  ACCESS cycles with the `addr` and `strb` of the item, which hold 0 where
  the SETUP cycle had an X or a Z. So an X that stayed on PADDR or PSTRB
  was reported as a change (`APB_MON/STABILITY`), on top of its
  `APB_MON/XZ_CHECK`. Both are compared with their SETUP cycle values now,
  as PWDATA is.
- A `vif` that was set in `uvm_config_db` for the agent's path only ended
  in `UVM_FATAL MISSING_VIF`: the agent read it in `connect_phase`, and the
  monitor and the drivers read it from `uvm_config_db` themselves in
  `build_phase`. The agent now gets `vif` in `build_phase` and sets it for
  its monitor and drivers, as it does with `cfg`. A `vif` set with a
  wildcard below the agent path, as the README shows, still works.

### Added -- testbench

- `ovip_apb_mid_test_reset_gap_test`: a reset in the gap after a transfer,
  and a reset on the clock edge the driver waits for with a new item. The
  sequences keep running; the bus must carry their transfers and no other.
  A third reset cuts, in ACCESS, an item that finished once before: its
  `transaction_finished` must read 0.
- `ovip_apb_fsm_violation_test`: reads that the test drives on the wires
  with a SETUP of two cycles (0 to 3 wait states), an ACCESS cut short by
  a new SETUP or by IDLE, PSEL and PENABLE HIGH for three cycles with no
  SETUP and for three cycles after a completion, and PENABLE X on SETUP.
  Each is an expected `APB_MON` error, one per monitor; the read after it
  and the legal traffic after that must return the data of their own
  addresses.
- `ovip_apb_undefined_data_lanes_test` and
  `ovip_apb_undefined_data_lanes_no_pstrb_test`: writes that the test
  drives on the wires with PSTRB 4'b0011 and an X, or a change, on PWDATA.
  On the lanes with a LOW strobe both are clean by default and reported
  with `check_undefined_data_lanes`; on a lane with a HIGH strobe, and on
  every lane of agents with no PSTRB, they are always reported. An X that
  stays must give `APB_MON/XZ_CHECK` and no `APB_MON/STABILITY`, on PWDATA,
  on PADDR and, with PSTRB, on PSTRB.
- `ovip_apb_narrow_bus_test` (16-bit bus, APB4 with PSTRB) and
  `ovip_apb_narrow_bus_apb3_test` (8-bit bus, APB3 agents with no PSTRB
  and no PPROT): eight writes with the default strobes of `apb_write` and
  their read-backs, with no `APB_DRV/TR_CHK` warning, then one write with
  a strobe bit above the bus width, which warns only where PSTRB exists.
  The memory has the valid range [0, 0x102): the last bus word inside it
  is written and read back, the first one outside is answered PSLVERR.
- `ovip_apb_read_strb_test`: reads that the test drives on the wires
  with PSTRB active. On the SETUP cycle: `APB_MON/READ_STRB` is expected
  from both monitors, the completer must answer PSLVERR with data 0, and
  a legal read of the same address after it OKAY with the data. On the
  three ACCESS cycles only: the error is expected on each of them.
- `ovip_apb_slave_seq_knobs_test`: `min_ws` and `max_ws` assigned to 0
  before `start()`, against a cfg default of 2 to 2; every transfer must
  have no wait state. `ovip_apb_slave_seq_no_pre_body_test`: the sequence
  started with `call_pre_post = 0` and its knobs left alone; every
  transfer must have 2 wait states and the read-backs their own data.
- `ovip_apb_trans_log_test`: both agents with `enable_trans_log`. A line
  of `log_line()` must have its waits and setup_time columns under their
  names in `log_header()`, a `setup_time` of 7.5 must be logged as
  7.500ns, and `%t` must keep the format that `tb.sv` set. The test also
  reads the two log files back, the header and one line per transfer
  (not on Verilator). The resp column of an OKAY line starts with OKAY
  under its name, and `convert2string()` has "resp=OKAY".
- `ovip_apb_reset_on_setup_test`: a reset sampled on the same edge as a
  SETUP cycle, from IDLE and back to back, each on an even and on an odd
  clock cycle. Neither monitor may publish that SETUP on
  `analysis_port_cont`, and the traffic after the release is checked.
- `ovip_apb_slave_out_of_range_no_pslverr_test`: the out-of-range test on
  agents with `pslverr_en = 0`. A refused transfer shows OKAY, reads 0 and
  leaves the memory untouched, and the report must not say "answering
  PSLVERR". `ovip_apb_slave_out_of_range_test` checks that it does say so
  with PSLVERR.
- `ovip_apb_agent_config_test`: a config with each of its 18 fields away
  from its default is cloned, and the clone compared field by field. The
  completer's cfg says passive and the config DB says active: the agent
  must be passive, with no driver and no sequencer.

### Changed -- testbench

- `ovip_apb_error_response_test` checks what its header says: the memory
  at the address of the errored write must hold the word it had before
  the write. The test read back another address, so a completer that
  commits an errored write passed it.

## [0.3.0] -- 2026-10-26

### Added -- VIP

- `randomize_idle_payload` in `ovip_apb_agent_config`, requester only:
  random PADDR, PWRITE, PWDATA, and PSTRB and PPROT where present, while
  PSEL is LOW, at reset and after every transfer. A completer that takes
  a payload signal while PSEL is LOW then shows it. Off by default. Asked
  for by logion_tb, whose read-only APB requesters never toggled PWRITE
  or PWDATA at the NoC's port. `ovip_apb_idle_payload_test`.

### Changed -- VIP

- `ovip_apb_pkg` declares `timeunit 1ns; timeprecision 1ps;`. The
  package took the time unit of the compilation unit before (the simulator's
  default, or an earlier `timescale` in the compile order); `$time` and
  `$realtime` in log lines and transaction time stamps are in ns on every
  simulator now. Verilator no longer reports `TIMESCALEMOD` for it.

- The completer driver's `vif.slave_cb.triggered` check (an item answered
  off the SETUP edge) is compiled out on Verilator, under `ifndef VERILATOR`,
  the same way it is on Xcelium: neither accepts `.triggered` on a clocking
  block. Nothing changes on Questa or VCS.

- The interface's clocking blocks (`monitor_cb`, `master_cb`, `slave_cb`)
  take their skews from `OVIP_INPUT_SKEW` and `OVIP_OUTPUT_SKEW`
  (`ovip_common/ovip_common_defines.sv`, overridable with `+define+`)
  instead of the hard-coded `input #1step output #0`. The defaults are the
  same values, so nothing changes unless you override them.

### Fixed -- VIP

- The monitor took a reset in the middle of a transfer as a protocol error
  (`APB_MON/FSM`, "PSEL deasserted after the SETUP cycle" or "PSEL/PENABLE
  deasserted while PREADY was LOW") when the requester dropped PSEL with
  the reset, as an asynchronously reset one does. The transfer thread and
  `rst_monitor` wake on the same edge in either order. The transfer thread
  now ends the transfer quietly on any edge where PRESETn is low. Found by
  logion_tb's reset test on a NoC's APB completers.

### Added -- testbench

- `ovip_apb_mid_test_reset_test`: a reset while a transfer waits in ACCESS,
  PSEL dropped with it, then traffic after the release.
- `ovip_apb_idle_payload_test`: write and read-back traffic with random
  gaps from a requester with `randomize_idle_payload`; the idle cycles
  must show PWRITE HIGH and PADDR and PWDATA non-zero.

## [0.2.0] -- 2026-10-05

### Added -- VIP

- `ovip_apb_base_slave_sequence` answers PSLVERR to a transfer outside the
  backing memory's valid ranges (`ovip_mem::add_valid_range`), with the
  memory untouched and a read of 0, and reports it as
  `SLAVE_SEQ/OUT_OF_RANGE` unless `report_out_of_range` is cleared.
  `request_in_range(req)` is the hook. With no range set on the memory
  nothing changes. `ovip_apb_slave_out_of_range_test`.

## [0.1.1] -- 2026-09-02

### Fixed -- VIP

- The master driver now aligns to the clocking event before driving an item a
  sequence delivered mid-cycle (a #-timed test, or any sequence not
  synchronized to the bus clock). Unaligned entry meant the SETUP cycle folded
  into the ACCESS edge (PSEL and PENABLE rising together), and a spec-correct
  completer ignored the transfer. A held item from `try_next_item` skips the
  alignment, so back-to-back operation is unchanged: the next transfer still
  starts on the completion edge.

## [0.1.0] -- 2026-07-26

Initial release. The VIP ships with APB3 and APB4 support (ARM IHI 0024E).

### Added -- VIP

- Requester (`OVIP_APB_REQUESTER`) and Completer (`OVIP_APB_COMPLETER`)
  agents (`ovip_apb_agent`), each switchable between active and passive.
- Full APB4 signal set: PSEL, PENABLE, PADDR, PWRITE, PWDATA, PREADY, PRDATA,
  plus the optional PSLVERR (APB3+) and PSTRB / PPROT (APB4), each gated by a
  per-agent `*_en` flag. Protocol selection (`OVIP_APB_PROTOCOL_APB3` /
  `OVIP_APB_PROTOCOL_APB4`) rejects APB4-only signals on APB3 agents.
- Requester master driver with zero-wait-state and back-to-back transfer
  support; PRDATA/PSLVERR are sampled back into the sequence item so
  `send()` doubles as a blocking read.
- Reactive completer: the monitor forwards each request on the SETUP cycle
  through `response_req_port`; the memory-backed base slave sequence
  (`ovip_apb_base_slave_sequence` + `ovip_mem`) answers with read data,
  wait states, and optional SLVERR in zero simulation time.
- Monitor with all spec checks inline: X/Z per the Appendix A validity
  rules, SETUP-is-one-cycle and PENABLE FSM rules (section 4.1), request
  stability while PREADY extends the transfer (section 3.1.2), PSTRB
  all-LOW on reads (section 3.2), PENABLE deassertion at end of transfer.
- In-order scoreboard (`ovip_apb_scoreboard`) with `trans.diff()`-formatted
  mismatch reports.
- Per-transaction logging (`ovip_apb_trans_logger`): per-agent file plus
  optional combined multi-agent file, enabled via `cfg.enable_trans_log`.
- Sequence library: `ovip_apb_base_master_sequence` (blocking
  `apb_write` / `apb_read` helpers), `ovip_apb_base_slave_sequence`
  (memory-backed, with SLVERR / wait-state hooks), and
  `ovip_apb_simple_rw_seq` (self-checking random write/read-back traffic).

### Known limitations

- APB5 features are intentionally out of scope: PWAKEUP, user signaling
  (PAUSER/PWUSER/PRUSER/PBUSER), interface parity check signals, and
  PNSE/RME. The interface wires and config gating for them do not exist in
  this VIP; adding them later is an additive change.
- APB2 (no PREADY/PSLVERR) is not modeled.
- One PSEL per interface: multi-completer PSELx decoding is left to the
  user's interconnect model.
