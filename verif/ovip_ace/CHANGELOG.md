# Changelog -- ovip_ace

All notable changes to this VIP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

## [0.2.0] -- 2026-11-12

### Changed

- `ovip_ace_monitor` reports in `report_phase` every completed read that got
  no RACK and every completed write that got no WACK ("N completed read
  transaction(s) got no RACK before the test ended"). A master that never
  acknowledged passed in silence before. The acknowledge comes in the cycle
  after the last R beat or the B response, so a test has to run at least one
  more clock cycle after its last response. A reset drops what was owed.
- A randomized `ovip_ace_trans` is a master-initiated item unless the caller
  says otherwise: the new `c_direction_default` is a soft
  `direction == OVIP_ACE_INITIATING`. `direction` was free before, and a
  bare `randomize()` could return a snoop item, which the master driver put
  on AR or AW as an AXI transaction. A sequence that wants a snoop item
  writes `direction == OVIP_ACE_SNOOP` in its `with` block.
- The example `examples/ovip_ace/01_coherent_loopback` checks its own
  results. It never compared read data before, and its reads ran while the
  writes were still waiting for their responses: they returned the init
  pattern of the memory. The sequence waits for the write responses before
  it reads and reports a `uvm_error` if a read does not return the written
  data, and the test reports a `uvm_error` if the master's monitor does not
  report exactly one snoop.

### Fixed

- The monitor never reported a snoop. `ovip_ace_monitor::extra_forks()`
  called `rack_wack_sequencing_monitor()` and `snoop_channel_monitor()` in
  one fork branch, and the first one never returns, so the second one never
  started. The CR and CD stability checks sat behind the AC one in the same
  way. Each task is a fork branch of its own now. `snoop_analysis_port`
  carries the snoops, `check_snoop()` and the CR and CD stability checks
  run, and the example prints `ACE_MON/SNOOP` from both monitors. A
  testbench can see errors from these checks that were hidden before.
- The monitor reported a legal cache line read with a WRAP burst (ReadShared,
  ReadClean, ReadNotSharedDirty, ReadUnique, CleanUnique, MakeUnique,
  CleanShared, CleanInvalid, MakeInvalid) as "must use an INCR burst", and
  as "must be aligned to the cache line size" when it started inside the
  line. The VIP slave then answered it with SLVERR. Table D3-10 allows WRAP
  with the address aligned to AxSIZE. The monitor reports only a FIXED burst
  now, and requires the cache line alignment only of an INCR burst.
- The monitor reported a Non-shareable WriteClean, WriteBack or WriteEvict
  as "must use Inner/Outer Shareable AxDOMAIN". The VIP slave then answered
  it with SLVERR and did not commit the write to its memory. Table D3-8
  allows the Non-shareable domain for these three. The monitor checks each
  write type against the domains of the table now: WriteLineUnique and Evict
  need Inner or Outer Shareable, and WriteClean, WriteBack and WriteEvict
  must not use System.
- The AWUNIQUE rule was the reverse of Table D3-9. The monitor reported
  AWUNIQUE HIGH on every write but WriteEvict, and accepted a WriteEvict
  with AWUNIQUE LOW. It reports a WriteEvict with AWUNIQUE LOW and a
  WriteClean with AWUNIQUE HIGH now, and nothing else: the other writes may
  assert it. `ovip_ace_trans::c_awunique_default` follows the same table:
  1 for WriteEvict, 0 for WriteClean, and 0 for the other writes unless the
  caller constrains `awunique` to 1.
- `ovip_ace_monitor::snoop_channel_monitor` waited for the CR handshake and
  looked for CD beats only after it. A master may send CD before, with or
  after CR (D3.9). With CRVALID and CDVALID in one cycle the monitor lost
  the first beat and reported "7 CD beats; expected 8". With all the CD
  beats before CR it gave a snoop the data of the next one and never
  reported that next snoop. It takes the CR handshake and the CD beats of a
  snoop in any order now. It still follows one snoop at a time: an AC
  handshake before the previous snoop is complete is not seen.
- The master driver asserted CDVALID only after the CR handshake. A master
  must not wait for CRREADY before it asserts CDVALID, and an interconnect
  may wait for CDVALID before it asserts CRREADY (D3.9): against such an
  interconnect the snoop never ended. `snoop_phase_driver` drives the CR
  response and the CD beats at the same time now, and neither waits for the
  handshake of the other. Against the VIP slave driver the handshakes fall
  on the same clock edges as before, and CDVALID rises one cycle earlier.
- A snoop given to `ovip_ace_slave_driver::push_snoop()` could vanish when
  the master held ACREADY HIGH: ACVALID never rose, nothing was reported,
  and the driver then waited for a CR response forever, so no later snoop
  went out either. It happened when `push_snoop()` was called between clock
  edges or from a thread woken by `@(posedge aclk)`. `snoop_request_driver`
  waits for the clock edge before it drives AC now. ACVALID rises one clock
  later than before for a snoop that was pushed on a clock edge.
- The ACE slave driver drove RRESP[1:0] from `resp` on every beat, so the
  per-beat responses that a slave sequence puts in `resp_beats` (an
  `ovip_axi` feature) were lost: `resp_beats = {OKAY, SLVERR}` went out as
  OKAY on both beats. RRESP[1:0] is the response of the beat now, as in
  `ovip_axi_slave_driver`, and RRESP[3:2] still carry IsShared and
  PassDirty on every beat.
- The AC and CD stability checks compared the whole ACADDR and CDDATA wire
  with a 2-state copy. An interconnect that drives `acaddr_width` bits and
  leaves the wires above them undriven got "AC payload changed before
  ACREADY" in every wait cycle, and a master with a narrow CDDATA got the
  same on CD. The checks compare the bits inside `cfg.acaddr_width` and
  `cfg.cddata_width` now, and the AC, CR and CD checks keep 4-state copies:
  a bit that holds X or Z in both cycles is not reported as a change.
- The monitor reported RACK or WACK HIGH in two consecutive cycles as "must
  be asserted for exactly one cycle" and did not count the second cycle. A
  master that acknowledges in the cycle after each handshake does that
  whenever two transactions complete in consecutive cycles. Each HIGH cycle
  is one acknowledge now, and only an acknowledge with none owed is an
  error. The monitor takes the acknowledge of an edge before it counts a
  handshake of the same edge, so an acknowledge in the cycle of its own
  handshake is reported. Four threads raced on that edge before, and the
  result depended on their order.
- The master driver sent at most one RACK or WACK every two cycles, the
  first one two cycles after the handshake, so with responses in
  consecutive cycles the acknowledges fell behind without limit. It sends
  one acknowledge per completed transaction in the cycle after its last
  handshake now: back-to-back completions give RACK or WACK HIGH in
  consecutive cycles.
- An ACE-Lite master drove RACK and WACK. ACE-Lite has neither signal
  (D11.1). `rack_wack_driver` runs in the ACE profile only now, and an
  ACE-Lite master leaves both wires LOW.
- A `build_snoop_response()` override that set `snoop_resp.data_transfer`
  and left `snoop_data_beats` empty sent CRRESP with DataTransfer HIGH and
  no CD beat. The slave driver then waited for CD forever, later snoops
  were never driven, and nothing was reported. The master driver reports
  `ACE_MASTER_DRV/SNOOP` as a `uvm_error` now and sends the response with
  DataTransfer cleared. The other CRRESP bits go out as the hook set them.
- `randomize()` of an `ovip_ace_trans` returned reserved ARSNOOP and AWSNOOP
  encodings and domains that the transaction type does not allow:
  `c_domain_consistent_with_snoop` was true for every value, and nothing
  constrained `snoop` but its top bit on a write. The new `c_snoop_legal`
  keeps `snoop` to the encodings of Tables D3-7 and D3-8, and
  `c_domain_consistent_with_snoop` now holds the domain rules of the same
  tables. These two, `c_snoop_msb`, `c_no_barriers` and `c_awunique_default`
  no longer depend on `direction`: a `with` block that asks for a
  combination outside the tables makes `randomize()` fail, where it used to
  pass by turning the item into a snoop. The comments in `ovip_ace_trans.sv`
  and `ovip_ace_agent_config.sv` named a `check_trans_validity` hook of the
  ACE master driver that never existed. They say what the constraints cover
  and what the caller has to constrain (README, "Randomizing an
  `ovip_ace_trans`").
- `compare()` of two `ovip_ace_trans` looked at the AXI fields only: a
  ReadShared in the Inner Shareable domain equalled a ReadUnique in the
  Outer Shareable domain with IsShared and PassDirty set, and
  `ovip_ace_scoreboard` counted the pair as matched. Two snoops with
  different addresses, types or responses were equal as well.
  `ovip_ace_trans` has its own `do_compare()` and `diff()` now. The two
  items must have the same `direction`. A master-initiated item also
  compares `domain`, `snoop`, `bar`, and `awunique` on a write or
  `is_shared` and `pass_dirty` on a read. A snoop compares `snoop_addr`,
  `acsnoop_code`, `acprot`, `snoop_resp` and `snoop_data_beats`, and none of
  the AXI fields. A scoreboard that passed may report `AXI_SB/MISMATCH` now.
- `vlog -sv -f ovip_ace.f` without `-mfcu` failed with 76 errors:
  `ovip_ace_pkg.sv` uses the macros of `ovip_axi_macros.sv` and did not
  include the file, so it compiled only when an earlier file of the same
  compilation unit had defined them. It includes the file now, as
  `ovip_axi_pkg.sv` does, and the filelist compiles with and without
  `-mfcu`.
- `convert2string()` and `log_line()` of a snoop printed the unused AXI
  fields (`OVIP_AXI_READ_TRANS, ID=0x0, ADDR=0x0, ...`) and neither the
  snoop address nor ACPROT, and a reserved ACSNOOP printed as `Snoop:` with
  no value. A snoop prints `ACADDR`, `ACPROT`, CRRESP and the number of CD
  beats now, its `log_line()` keeps the columns of the table (`SN` in the
  `dir` column), and a reserved code prints as `Snoop:Reserved(0100)`. The
  `ACE_MON/SNOOP` lines of the monitor have the new format.
- A snoop that waited in the mailbox of `ovip_ace_slave_driver` survived a
  reset and was driven after it. The driver empties the mailbox on reset
  now (and when its `run_phase` starts), as the base driver does with its
  ready patterns.
- `push_snoop()` on an ACE-Lite agent queued the snoop forever with no
  message: the profile has no snoop channels and no thread takes it. It
  reports `ACE_SLAVE_DRV/SNOOP` as a `uvm_error` now and drops the snoop.
- `ovip_ace_base_master_sequence::make_write()` with an empty data queue
  returned an item with `len` 255: the size minus one wrapped in the 8-bit
  field. It reports `ACE_SEQ/MAKE_WRITE` as a `uvm_error` now and builds the
  item with `len` 0.
- Comments described an effect for fields that nothing uses. They now say
  that the fields have no effect in this version: `supports_snoop_filter`,
  `broadcast_inner_en`, `broadcast_outer_en` and `broadcast_cache_maint_en`
  of `ovip_ace_agent_config`, and `expected_start_state`,
  `expected_end_state` and `state_hint_valid` of `ovip_ace_trans`.
- README: the factory type override that `ovip_ace_agent` sets, from
  `ovip_axi_trans` to `ovip_ace_trans`, is global, and the README did not
  say so. A plain `ovip_axi` agent in the same test gets `ovip_ace_trans`
  items, and an override of `ovip_axi_trans` that the test set earlier is
  replaced. The code is unchanged.
- Two monitor messages cited the wrong place: "DVM must not transfer data
  (D5.4)" and "PassDirty set without DataTransfer (Table D3-21)". Part D has
  no D5.4. The DVM rule is in D13.2.5 and the PassDirty rule in Table D3-22,
  and the messages, the comments and the docs cite those now.
- README and CONTRIBUTING: the banner and the task list say what the example
  checks and what the directed tests of the audit covered. "Spec coverage"
  lists each monitor check as it is now, with its limits. CONTRIBUTING gets
  a "Known gaps" section with what the audit found and did not fix: the
  transactions with a single R transfer, Evict and write barriers without W
  data, AxCACHE, one snoop at a time, and the monitor checks that do not
  exist (reset values on AC, CR and CD and of RACK and WACK, AxCACHE
  against AxDOMAIN, the cache line rules on writes, RRESP[3:2] per Table
  D3-15, the CRRESP rules of Table D3-22, ACADDR alignment, the D6.2
  ordering). It said that barriers are "rejected by
  config/trans": an item built with AxBAR\[0\] = 1 goes on the wire with no
  message.
- Comments: `ovip_ace_types.sv` no longer says that `check_config` flags a
  barrier AxBAR, and the header of `ovip_ace_slave_driver.sv` no longer
  describes a RACK / WACK counter that the file does not have.
- `analysis_port_cont` of the monitor got a new transaction when it was
  created, before its type and its first phase were sampled, so a
  subscriber saw every write as a read with empty fields. The item is
  written after its first phase now, through the `send_new_transaction`
  hook that `ovip_axi_monitor` has for it.
- `cfg.clone()` and `copy()` of an `ovip_ace_agent_config` gave a config
  with every field at its default: neither it nor `ovip_axi_agent_config`
  had a `do_copy`. They carry every field now: the AXI fields through the
  new `do_copy` of `ovip_axi_agent_config`, and the ACE fields (`profile`,
  `cache_line_size`, `acaddr_width`, `cddata_width`, `cache_model` and the
  rest) through the new `do_copy` of `ovip_ace_agent_config`.

## [0.1.2] -- 2026-10-26

### Changed -- VIP

- `ovip_ace_pkg` declares `timeunit 1ns; timeprecision 1ps;`. The
  package took the time unit of the compilation unit before (the simulator's
  default, or an earlier `timescale` in the compile order); `$time` and
  `$realtime` in log lines and transaction time stamps are in ns on every
  simulator now. Verilator no longer reports `TIMESCALEMOD` for it.

- The interface's clocking blocks (`monitor_cb`, `master_cb`, `slave_cb`)
  take their skews from `OVIP_INPUT_SKEW` and `OVIP_OUTPUT_SKEW`
  (`ovip_common/ovip_common_defines.sv`, overridable with `+define+`),
  where they had `localparam INPUT_SKEW = 0; OUTPUT_SKEW = 0;` that nothing
  could override. The default input skew is `1step`: an input is sampled
  with its value from before the clock edge, as a synchronous receiver
  sees it. `#0` sampled after the edge's own updates, and Verilator does
  exactly that: a VALID dropped at the sampling edge was reported by the
  monitor's stability check as "de-asserted before the transfer was
  sampled" (noc_proj's bench on Verilator 5.053; Questa passed the same
  seed). `+define+OVIP_INPUT_SKEW=0` restores the old sampling.

## [0.1.1] -- 2026-07-28

### Fixed

- `ovip_ace_trans::c_snoop_msb` nested one implication inside another and
  wrapped it in parentheses. `->` is only valid as a constraint expression, so
  VCS and Xcelium both rejected the file outright ("syntax error, token is
  `->`" / "expecting a right parenthesis") while Questa accepted it. The
  constraint is now a single implication over the same condition, so the VIP
  compiles on all three.

## [0.1.0] -- 2026-07-14

Initial release, covering AMBA ACE and ACE-Lite (ARM IHI 0022H) as an
extension of `ovip_axi`, with one agent serving both profiles through a
runtime `cfg.profile` switch. See [README.md](README.md) for the feature list,
the spec-coverage table, and -- importantly -- what has and has not been
verified: this VIP was written by an AI and has not been functionally verified
by a human, so the snoop channels, RACK/WACK sequencing, cache-line and
ACE-Lite checks and the scoreboard are all unproven.
