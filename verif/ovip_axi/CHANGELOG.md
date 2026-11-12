# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

## [0.6.0] -- 2026-11-12

### Added -- VIP

- On AXI4 the monitor reports a reserved AxCACHE value, one that Table A4-5
  of the spec does not list (`0b0100`, `0b0101`, `0b1000`, `0b1001`,
  `0b1100`, `0b1101`), as `AXI_MON/WR` or `AXI_MON/RD`, when the agent has
  the signal (`awcache_en`, `arcache_en`). AxCACHE was sampled and never
  checked. AXI3 agents are not checked.
- The monitor checks the exit from reset: a VALID that is high on the first
  rising clock edge where ARESETn is high after a reset is
  `AXI_MON/BAD_VALIDATOR` (spec A3.1.2, Figure A3-1). It was not checked.
  The channel threads of the monitor started on that edge and waited for
  the next one, so a handshake on it was lost and the errors that followed
  named other things. They take a handshake on that edge now. The check
  runs once ARESETn was sampled low, and reports a `1` only.
- On AXI3 the monitor checks WID. An X or Z on WID at a W handshake is
  `AXI_MON/XZ_CHECK`, and a change of WID while WVALID waits for WREADY is
  `AXI_MON/STABILITY_CHECK`. WID had neither check: an X on it was read as
  ID 0, the beat went to a wrong write, and the errors that followed did not
  name WID.
- `ovip_axi_trans.dropped_by_reset`: 1 on an item that the master driver
  gave back at a reset before its transaction completed, 0 on every item
  that completed. The driver clears it when it takes an item.
- `ovip_axi_master_driver`: `held_items[$]`, the items the driver took from
  the sequencer and did not give back yet. `return_item(tr)` gives a
  completed item back and takes it off that list. `return_dropped_items()`
  gives back the rest after a reset. `ovip_axi_base_driver` has
  `return_dropped_items()` as an empty hook that `run_phase` calls after a
  reset. A driver subclass that completes an item itself calls
  `return_item(tr)` where it called `seq_item_port.put(tr)`.

### Changed -- VIP

- AXI3 write data order follows spec A5.3.3: the first W beat of each write
  comes in the order of the AW handshakes.
  - The W scheduler of a master starts the data of a write only when every
    write before it in its queue has started. With `wr_out_of_order_depth`
    above 1 it could start the data of a later AW first, which AXI3
    forbids. The beats of the writes that have started still interleave,
    up to `wr_interleave_depth`. The new `cfg.allow_wdata_out_of_aw_order`
    (master only, AXI3 only, default `0`) brings the old scheduling back,
    to inject the error.
  - The monitor reports a first W beat that is out of the AW order as
    `AXI_MON/WDATA_OOO`, also when the beat comes before its own AW. It
    tested every W beat against `wr_out_of_order_depth`: with a depth of 1
    legal interleaving was reported, and with a larger depth a first W beat
    ahead of an older AW passed. The monitor no longer uses
    `wr_out_of_order_depth`, and the text of `AXI_MON/WDATA_OOO` changed.
  - A bench whose AXI3 master sent write data ahead of older AWs through
    `wr_out_of_order_depth` now gets the data in AW order. To keep the old
    traffic it sets `allow_wdata_out_of_aw_order` and expects the error.
- The monitor tests BVALID and RVALID against the handshakes they depend
  on (spec A3.3.1) on the first clock edge where they are high. It tested
  them at their own handshake, so a BVALID before the last W handshake, and
  an RVALID before the AR handshake, passed when the response was accepted
  late enough. The handshakes must be on an earlier edge: a response on the
  edge of the handshake it depends on is an error, where the result
  depended on the order of the monitor's threads. The texts of
  `AXI_MON/BRESP` and `AXI_MON/RDATA` changed with it: "Unexpected BRESP:
  ..." and "Data phase encountered without a corresponding address phase"
  are now "BVALID is high for ID ..., and no write with this ID ..." and
  "RVALID is high for ID ..., and no read with this ID ...". A bench that
  matches the old texts has to match the new ones.
- The README says that the monitor expects the AW handshake before the
  write response on AXI3 too, which is stricter than AXI3 requires (spec
  A3.3.2), and the `AXI_MON/BRESP` message says it on an AXI3 agent. The
  check itself is as it was.
- The X/Z check and the stability check of the monitor skip the data bytes
  that AXI leaves undefined: a WDATA byte whose WSTRB bit is low, and an
  RDATA byte lane that the read beat does not use. Both checks covered the
  whole data bus, so a DUT that leaves an X under a low strobe or on an
  unused lane failed, and the only way out was
  `OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS`, which removes every
  payload check. The new `cfg.check_undefined_data_lanes` (default `0`)
  brings the whole-bus checks back: a bench that wants them sets it to `1`.
- The four phase time stamps of `ovip_axi_trans` (`addr_phase_time`,
  `data_phase_begin_time`, `data_phase_time`, `resp_phase_time`) are
  `realtime` and the monitor fills them from `$realtime`. They were `time`,
  filled from `$time`, which rounds to a whole ns in `ovip_axi_pkg`: on a
  clock whose edges fall on half a ns every stamp was 0.5 ns late, and the
  transaction log showed 9.000ns for a transfer at 8.500ns. Code that copies
  a stamp into a `time` variable still gets the rounded value. Declare the
  variable `realtime` to keep the fraction.
- The transaction log prints its times in ns with three decimals
  (`17.500ns`) by itself, and `ovip_axi_trans_logger` no longer calls
  `$timeformat(-9, 3, "ns", 0)`. An agent with `enable_trans_log` changed
  the `%t` format of the whole simulation before. A bench that relied on it
  calls `$timeformat` itself.
- After a reset the master driver gives back every item it took from the
  sequencer and did not complete: with `seq_item_port.put()`, with
  `dropped_by_reset` set, one at a time, in the order it took them. Before,
  it dropped them with no put, so a sequence in `get_response()` or
  `wait_for_responses()` waited for ever and a bench had to kill it. Such
  a sequence goes on now. What to do: a sequence that uses `resp` or the
  read data of a response checks `dropped_by_reset` first. A bench that
  starts new sequences after a reset still kills the old ones, or they go
  on beside the new ones. `ovip_axi_bytestream_sequence::all_okay()` is 0
  when a reset dropped one of its bursts. README "A reset while items are
  in flight".
- AXI3 agents enforce the AXI3 burst length: 16 transfers at most, for
  every burst type (spec A3.4.1). Nothing limited it before. The master
  driver refuses an item with `len` above 15 (`TR_CHK`, then UVM_FATAL
  unless `trust_me_i_am_an_engineer` is set). The monitor reports a longer
  INCR burst ("The length of an AXI3 burst must not exceed 16") and marks
  it `monitor_error`, so the base slave sequence answers SLVERR.
  `ovip_axi_bytestream_sequence` cuts its bursts to 16 beats. What to do:
  a bench that sends longer bursts on agents left at the default
  `protocol_type` sends AXI4 traffic, and sets
  `protocol_type = OVIP_PROTOCOL_AXI4` on both agents. `len_width` stays as
  it is: `check_config` does not require 4 on AXI3.
- `check_config` reports an AXI4-Lite agent whose `bus_width` is not 4B or
  8B: AXI4-Lite has a data bus of 32 or 64 bits (spec B1.1.2). It took any
  width before. What to do: give an AXI4-Lite agent one of the two widths.
- `ovip_axi_scoreboard` reports an actual transaction with no expected one
  (`AXI_SB/UNEXPECTED`) at `check_phase`, where it reported it on arrival.
  See the fix below. What to do: nothing, unless a bench relied on the
  time of that message.
- CONTRIBUTING.md lists four more wanted features: exclusive access, AXI3
  locked access, WUSER and RUSER per beat, and the low-power interface.

### Fixed -- VIP

- Every `AXI_MON` message ID of the monitor carries the `agent_tag` prefix.
  The X/Z check, the stability check, `AXI_MON/INCOMPLETE_RD_TRANS`,
  `AXI_MON/INCOMPLETE_WR_TRANS`, the `AXI_MON/INVALID_WSTRB` of a single
  beat and the AXI4-Lite EXOKAY error were reported without it, so with two
  tagged agents these IDs did not name their agent. With an empty
  `agent_tag` no ID changes.
- The X/Z check and the stability check of RRESP run on every R beat and
  compare the RRESP of the cycle. They ran only on a beat with RLAST, and
  the stability check compared `resp` of its two sampling items, which is
  the worst response an item has ever sampled. An X or a change of RRESP on
  a beat that is not the last was not reported, and the X was stored as
  OKAY. After one stalled SLVERR beat a later change was not reported, and
  after one real change every later stalled last beat was reported twice.
- The monitor counts an outstanding write down only when its response
  matched a write. A BRESP with no write took the count below zero, and
  with `num_outstanding_wr_transactions` set every later address was
  reported as `AXI_MON/OUTSTANDING_EXCEED` with 4294967295 writes. The
  message of the total limit prints `num_outstanding_transactions`, where
  it printed `num_outstanding_rd_transactions`.
- The monitor reports a burst with one beat too many in every order of the
  phases. An xLAST after beat AxLEN+1 was not reported, and the beats of a
  write whose data starts before its address were counted at the AW only
  when WLAST had come. Such a write with AWLEN+1 beats and no WLAST, then
  one more beat with WLAST, passed. Now the AW reports "Missing xLAST" and
  the late beat reports "xLAST was asserted on transfer #N", for a write
  and for a read.
- The monitor writes an item to `analysis_port_cont` after it sampled the
  first phase of the transaction. `new_transaction()` wrote it right after
  it made the item, with no field set: a write arrived as
  `OVIP_AXI_READ_TRANS` with no address. The write is in the new
  `send_new_transaction()`, which the channel threads call. A subclass
  whose `new_transaction()` writes to the port itself is not changed by it.
- `cfg.tr_timeout_us = 0` turns the transaction watchdog of the monitor
  off. It ended the simulation with `AXI_MON/TIMEOUT` on the first
  transaction. The README documents the field, which it did not name: the
  unit is microseconds of simulation time, the default is 50, and the
  watchdog ends the run with a `UVM_FATAL`, in a passive monitor too.
- `ovip_axi_base_slave_sequence` sets up its memory backing at the start
  of `body()` too, in the new `setup_mem_backing()`. It did so in
  `pre_body()` only, which a start with `call_pre_post = 0` skips, as the
  `uvm_do` macros do for a child sequence: the first request then hit a
  null handle. A subclass whose `body()` does not call `super.body()` and
  that is started this way calls `setup_mem_backing()` itself.
- `ovip_axi_base_slave_sequence` serves a request at the edge of a valid
  range that starts or ends inside a 4-byte memory word. `request_in_range`
  tests the bytes of the burst and found it in range, and the write and
  the read then went through `ovip_mem::write()` and `read()`, which refuse
  a word that is partly outside: the request was answered OKAY, the write
  was dropped, the read returned 0, and the memory reported
  `MEM/OUT_OF_RANGE`. Such a word now goes byte by byte through the
  bytestream functions of the memory, in the new `write_word_to_mem()` and
  `read_word_from_mem()`. A word that is all valid goes through `write()`
  and `read()` as before.
- Two message texts of the monitor. `AXI_MON/AWLEN_MISMATCH` printed one
  transfer less than the data phase had: 11 beats were "a total of 10
  transfers". "Missing xLAST" printed AxLEN plus 1 under the name AWLEN,
  also for a read: an AxLEN of 1 was "AWLEN=2", and is "AxLEN=1" now.
- `ovip_axi_simple_wr_bursts_seq` kept the wrong number of strobe bits on a
  beat that starts inside its size: the first beat of an unaligned burst,
  and every beat of an unaligned FIXED burst. With the address `u` bytes
  into the beat it kept `u` bits, and the beat carries `size - u` bytes. A
  beat that starts above half its size drove WSTRB on lanes outside the
  transfer (`AXI_MON/INVALID_WSTRB` on a narrow transfer), and one that
  starts below half never strobed its upper bytes. It keeps `size - u`
  bits now.
- The master driver refused a read whose `data_delay` has entries.
  `check_trans_validity` compared `data_delay.size()` with
  `data_beats.size()` for a read too, and a read request has no data
  beats. Every randomized read ended in UVM_FATAL, because the constraints
  of `ovip_axi_trans` give one `data_delay` entry per beat. The check
  applies to writes only now.
- `ovip_axi_scoreboard` depended on the arrival order: an actual
  transaction that arrived before its expected one was `AXI_SB/UNEXPECTED`,
  and the expected one became `AXI_SB/ORPHAN`. Two monitors publish a
  transaction when it completes, and it completes on the slave side of a
  DUT first, so the wiring of the header (expected from the master side,
  actual from the slave side) failed on every transaction. An actual item
  now waits in a FIFO per direction and ID, as the expected items do, and
  is compared when its expected item arrives. `check_phase` reports what is
  left on either side. The compare is in the new protected function
  `compare_pair()`. README: a new section "Scoreboard".
- `ovip_axi_simple_rd_bursts_seq` gave burst `ii` the ID `ii` with no
  mask, so more bursts than `2^rd_id_width` ended in UVM_FATAL at the first
  ID that does not fit. It masks the ID with `rd_id_width` now, as
  `ovip_axi_simple_wr_bursts_seq` does with `wr_id_width`.
- `ovip_axi_bytestream_sequence` sent one burst for a stream of no bytes.
  A read with `read_size` 0 read one beat at address 0, and a write with
  empty `data` ended in UVM_FATAL (a burst with no data beats). Such a
  stream sends no burst now, and the sequence returns at once.
- `ovip_axi_agent` was registered with `uvm_component_param_utils`, the
  macro for a class with parameters, which gives the factory no type name.
  `get_type_name()` returned "uvm_agent", and a factory override or a
  creation by the name `ovip_axi_agent` failed. It uses
  `uvm_component_utils` now.
- README "Address & Data Channels Timing Dependency": with
  `DATA_START_EV_BEFORE_ADDR`, AWVALID rises `addr_phase_delay` cycles
  after WVALID, and one cycle after it at the least, so 0 and 1 give the
  same gap. The text did not say so, and the figure showed a gap of 3
  cycles under the label `addr_phase_delay = 2`. Its label is 3 now, in
  `wavedrom/data_start_ev_before_addr.json5` and in the `.svg`. The driver
  is not changed.
- README "Byte-Lane Alignment": with `auto_byte_lanes_alignment = 1` the
  user fills `strb_beats[i]` at bit 0, one bit per byte the beat carries,
  and the driver shifts it to the lane. The text said that the strobes are
  derived from `size` and the address, and the table called
  `strb_beats[0]` "don't care (VIP computes)". The driver never computed or
  masked them: a write with no `strb_beats` is UVM_FATAL, and one with all
  bits set drives WSTRB outside the transfer.
- README "Randomization Limits" showed
  `tr.randomize() with { addr inside {...}; len < 4; }`, and the 0.1.0
  notes call `ovip_axi_trans` constrained-random ready. Such an item is
  not legal for an agent. The constraints of the item do not know the
  agent's widths, its bus width, its protocol or the 4KB rule, and the
  master driver ends the run on most of what comes out. The new part
  "What `randomize()` leaves to you" lists what to constrain: `id`, the
  user fields, `addr` and the data inside the widths, `size`, `len`, the
  4KB page, the strobes and `data_start_event`. Its example is an item
  that the driver takes. No constraint was added to the item.
- README: `protocol_type`, `interface_type`, `len_width`,
  `wr_resp_out_of_order_depth` and `trust_me_i_am_an_engineer` were in no
  document. The new section "Agent Configuration" has the first three, the
  scheduler table has the fourth, and "Items the driver refuses" has the
  fifth. `protocol_type` defaults to AXI3, and the config class now writes
  that default out. Set it on every agent: an agent left at the default
  beside an AXI4 master never completes a write with a non-zero AWID.
- `ovip_axi_bytestream_sequence` did its setup in `pre_body()`, which UVM
  does not call for a sequence started with `call_pre_post = 0`. That is
  how `uvm_do` and `uvm_send` start a child sequence. The bytes per beat
  then stayed 0, the split of the stream never ended, and the simulation
  hung in zero time. The setup is now `init_stream()`, which `body()`
  calls first. A subclass that overrode `pre_body()` to change the setup
  overrides `init_stream()` now.
- `ovip_axi_agent_config` had no `do_copy`, so `cfg.clone()` and `copy()`
  gave a config with every field at its default. They carry every field
  now, `check_undefined_data_lanes` and `allow_wdata_out_of_aw_order`
  among them.
- `check_config` took a config with no `bus_width` or no `addr_width`
  (both have no default) and a scheduler depth of 0 or less. It reports
  each of them with `AXI_CFG` now. The checks that a depth is 1 on
  AXI4-Lite, and on an AXI4 master, report a depth above 1 only, so a
  depth of 0 gets one error. On AXI4-Lite an unset `bus_width` gets the
  new error only, not the one for a width other than 4B or 8B.
- The master driver filled `data_beats` of a read from its R beats on
  top of what the item held, so a read item sent a second time kept the
  beats of the first send past its own: sent with 4 beats and then with 2,
  it came back with 4. The driver now clears `data_beats` of every read it
  accepts.
- `ovip_axi_simple_wr_bursts_seq` and `ovip_axi_simple_rd_bursts_seq` drew
  a burst with no `addr` at a fully random address. An INCR burst then
  crossed a 4KB page when the address was near the page end, and a WRAP
  burst was not aligned to its beat size, and the monitors reported both.
  The random address now keeps an INCR burst inside its 4KB page and
  aligns a WRAP burst to its beat size. An INCR burst longer than 4KB
  cannot fit: it starts at the page start, with a `BAD_USE` warning. An
  `addr` that the caller gives is used as it is.
- At reset the master driver and the slave driver drove the VALID and
  READY of all five channels to 0, also on an agent whose
  `interface_type` is read-only or write-only. Such an agent drove the
  wires of channels it does not have, where another component may drive
  them. Each driver now drives only the channels of its `interface_type`.
- Documentation. CONTRIBUTING listed WRAP burst support as a wanted
  feature: WRAP is implemented, and the item is removed. The README named
  the path of the sequences `src/seq/`: it is `src/seqlib/`. It also said
  that every source file opens with a short header, which is not true;
  it says "some" now.
- README: `OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS` turns off
  the X/Z checks on the payload signals and the stability checks. The
  X/Z check on every VALID and READY stays on, which the README did not
  say. The header of `ovip_axi_base_slave_sequence.sv` named a
  `uvm_fatal` for FIXED and WRAP bursts wider than a memory word, which
  the sequence does not have; the sentence is removed.
- The example `03_axi3_write_interleaving` said that the slave monitor
  enforces `wr_interleave_depth` and `wr_out_of_order_depth`. The monitor
  checks that the first W beats follow the AW order (`AXI_MON/WDATA_OOO`)
  and that the interleaving stays inside `wr_interleave_depth`
  (`AXI_MON/INTERLEAVING_EXCEED`), and does not use
  `wr_out_of_order_depth`. The README and the comment of the example say
  that now, and the example no longer sets `wr_out_of_order_depth` on its
  slave.
- README "Bytes under a low strobe" said that by default the master drives
  zero on a WDATA byte whose WSTRB bit is low. The master drives the data
  of the sequence there: on a byte under a strobe hole the byte of
  `data_beats`, and above a beat's window the bits of `data_beats` above
  the beat's bytes. Only the lanes below a shifted beat are zero. The
  text says that now. The driver is not changed.

### Added -- testbench

- `ovip_axi_slave_seq_call_pre_post_test`: the base slave sequence started
  with `call_pre_post = 0` serves a write and its read-back.
- `ovip_axi3_wr_in_aw_order_test`: the traffic of `ovip_axi3_wr_ooo_test`
  with a reorder window of ten writes and without the error injection bit.
  The first W beats follow the AW order and no monitor reports anything.
- `ovip_axi_trans_log_test`: an item stamped at 17.5 ns prints `17.500ns`
  in `log_line()`, and the lines that a master's logger writes carry their
  five times in that form and in order.
- `ovip_axi_monitor_checks_test`: scripted traffic on two passive agents
  with the tags `M` and `S`, for the checks of the monitor that the VIP's
  own drivers do not reach. Every expected error names its monitor by the
  tag in the message ID. It also changes an undefined and a defined byte of
  a stalled W beat and R beat, with `check_undefined_data_lanes` at 0 and
  at 1. `ovip_axi3_monitor_checks_test` is the same on AXI3.
- `ovip_axi_simple_bursts_seq_test`: unaligned writes of 2B, 4B and 8B
  beats through `ovip_axi_simple_wr_bursts_seq`, INCR and FIXED, at an
  offset below, at and above half the beat. It checks the strobes of the
  short beats and the bytes in the memory. Then six reads through
  `ovip_axi_simple_rd_bursts_seq` on agents with 2 read ID bits. Then
  writes and reads with no `addr`, INCR of 256 beats and WRAP of 16, each
  inside its 4KB page or aligned to its beat.
- `ovip_axi_master_item_test`: reads built by hand with one `data_delay`
  entry per beat complete with the bytes of the memory. The example of the
  README section "Byte-Lane Alignment" gives the WDATA and WSTRB that the
  section shows. A read item sent again with fewer beats comes back with
  the beats of the second read only.
- `ovip_axi_mid_test_reset_dropped_items_test`: a sequence with twelve
  items in every stage of the master driver gets each one back once at a
  reset, eleven of them with `dropped_by_reset`. It then runs traffic
  after the release and after a second reset. A bytestream write that a
  third reset cuts returns with `all_okay()` 0, and its bytes go through
  afterwards.
- `ovip_axi_scoreboard_test`: a scoreboard on the two monitors of the
  testbench in each role matches every transaction, and one fed by hand
  shows a match in both arrival orders, a mismatch, an orphan and an
  unexpected item.
- `ovip_axi_agent_config_test`: `check_config` on configs built by hand.
  A new config is AXI3 with the full interface, and an AXI4-Lite config is
  taken with a 4B or 8B bus only. The agent has its type name in the
  factory. A clone of a config with every field away from its default has
  every value. An unset `bus_width` or `addr_width` and each depth at 0
  give their error. The two agents of the test have a read-only interface,
  and the VALID and READY wires of the write channels stay Z.
- `ovip_axi3_burst_len_test`: on AXI3 agents a byte stream goes in bursts
  of 16 beats at most, a burst of 16 beats completes, and a write and a
  read of 32 beats give the driver's warning, the error of both monitors
  and SLVERR.

### Changed -- testbench

- `ovip_axi3_wr_ooo_test` is a negative test: its master sets
  `allow_wdata_out_of_aw_order`, and both monitors report the nine first W
  beats that are out of the AW order. `ovip_axi3_wr_interleaving_test`
  expects 10 `AXI_MON/INTERLEAVING_EXCEED` errors, where it expected 82:
  the ten writes start their data one after the other, in AW order.
- `ovip_axi_signal_stability_test` checks that its two RRESP errors come on
  the two cycles where RRESP changes, and has a new block: a read whose
  RRESP changes on a stalled beat that is not the last (one error per
  monitor), then a last beat that waits and changes nothing (no error).
  `ovip_axi_xz_test` expects the RRESP X/Z error on both beats of its read.
- `ovip_axi_xz_test` runs on AXI3, where it ran on AXI4, and forces an X on
  WID too. `ovip_axi_signal_stability_test` sets AXI3, which was its
  default, and expects the WID change of its W block.
- `ovip_axi_xz_test` sets `check_undefined_data_lanes` for its write part,
  whose X is on a WDATA byte with an X strobe. Its new last part puts an X
  on an unstrobed WDATA byte and on an unused RDATA lane: no error by
  default, one error each with the bit set.
- `ovip_axi_signal_stability_test` expects the `AXI_MON/BRESP` and
  `AXI_MON/RDATA` error of its B block and of its second R block, which
  raise BVALID and RVALID with no write and no read.
- `ovip_axi_slave_out_of_range_test` gives its memory a second range,
  [0x1001, 0x1102), and writes and reads its first byte, its last byte and
  its last two bytes. The bytes next to it are refused.
- `ovip_axi_bad_dba_test` and `ovip_axi_data_before_address_test` expect
  the real transfer count in the `AXI_MON/AWLEN_MISMATCH` text (11 and 10,
  where they expected 10 and 9).
- `ovip_mem_test`: on EDA Playground (the bundle's `eda_tb.sv` defines
  `OVIP_EDA_PLAYGROUND`) the write_bytestream benchmark runs rounds for 15 s
  of wall time instead of the 1000 rounds that ran past the site's runtime
  cap, and prints a `ROUNDS:` line with the calls per second. Locally it
  still runs 1000 rounds.
- `ovip_axi_bytestream_test` and `ovip_axi_bytestream_lite_test`: a round
  that runs the sequence as the child of another sequence, started with
  `call_pre_post = 0`, and a round with streams of no bytes.
- `ovip_axi_mid_test_reset_inflight_test` and
  `ovip_axi_mid_test_reset_async_valid_test` set
  `protocol_type = OVIP_PROTOCOL_AXI4` on both agents. Their bursts of 65
  and 64 beats are AXI4 traffic, and they ran on the default AXI3.
- `ovip_axi_bytestream_test` sets the ", AXI4-Lite" part of its first
  message with `if`, not with a conditional of two string literals: on VCS
  the full AXI4 run printed 11 spaces there.

## [0.5.0] -- 2026-10-26

### Added -- VIP

- `ovip_axi_simple_wr_bursts_seq.qos[$]`: the AxQOS of each burst, in the
  same order as `addr`, `len` and `size`. Burst `ii` takes `qos[ii]`, so one
  sequence can drive a master in several service classes. A burst past the
  end of the list keeps AxQOS 0, as before; an empty list changes nothing.

### Changed -- VIP

- `ovip_axi_pkg` declares `timeunit 1ns; timeprecision 1ps;`. The
  package took the time unit of the compilation unit before (the simulator's
  default, or an earlier `timescale` in the compile order); `$time` and
  `$realtime` in log lines and transaction time stamps are in ns on every
  simulator now. Verilator no longer reports `TIMESCALEMOD` for it.

- The slave driver's `vif.slave_cb.triggered` check in `transaction_acceptor`
  (an item returned off a `slave_cb` edge, with its one-cycle wait and the
  `SLAVE_DRV` warning) is compiled out on Verilator, under `ifndef VERILATOR`,
  the same way it is on Xcelium: neither accepts `.triggered` on a clocking
  block. Nothing changes on Questa or VCS.

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

### Fixed -- VIP

- A WRAP burst's per-beat byte lanes went negative on an address with bit
  63 set ("Active byte lanes are [-4:-4]"), and the slave then placed its
  read data on those lanes. The lane math used a signed `longint`, which the
  2^31 fix moved to, and an address at or above 2^63 is negative there. It
  is unsigned 64-bit now. Found by noc_proj's design fuzzer: under its
  msb_slice target scheme a 64-bit address puts the slave select in the top
  bits.
- The monitor's stability checks took a reset under VALID as "xVALID was
  de-asserted before the transfer was sampled", and as a payload "changed
  before being sampled", when the other side dropped VALID with the reset,
  as an asynchronously reset slave or master does. The check thread and
  `rst_monitor` wake on that edge in either order. Each check now ends the
  transfer on an edge where ARESETn is low. Found by logion_tb's reset test
  on a NoC's master port.

### Added -- testbench

- `ovip_axi_mid_test_reset_async_valid_test`: a reset while an R beat waits
  for RREADY, RVALID dropped with it, then traffic after the release.

## [0.4.0] -- 2026-10-05

### Added -- VIP

- `ovip_axi_trans.resp_beats[$]`: the RRESP of every beat of a read, in
  beat order. The master driver and the monitor fill it beat by beat, and
  `resp` is now the WORST of the beats (DECERR over SLVERR over EXOKAY
  over OKAY) instead of the last beat's RRESP. An error on a middle beat
  was invisible before: the last beat overwrote it. A slave sequence may
  fill `resp_beats` to answer beats differently; the slave driver drives
  each beat from its entry, and from `resp` on every beat when the list
  is empty, as before. The driver now drives RRESP on every beat of a
  burst, not only the last. A write, and a single-beat read, are
  unchanged. `ovip_axi_rresp_per_beat_test` is the proof; the transaction
  log marks a mixed read with `*` after the response and lists the beats.
- `ovip_axi_base_slave_sequence` answers SLVERR to a request outside the
  backing memory's valid ranges (`ovip_mem::add_valid_range`), with the
  memory untouched and zero read beats, and reports it as
  `SLAVE_SEQ/OUT_OF_RANGE` unless `report_out_of_range` is cleared.
  `request_in_range(tr)` is the hook: INCR the span of the size-aligned
  containers, WRAP the aligned window, FIXED one container. With no range
  set on the memory nothing changes. `ovip_axi_slave_out_of_range_test`.

- `ovip_axi_bytestream_sequence` grew into the data-level sequence a bench
  drives traffic with: `burst` (INCR, or FIXED for a packet into one data
  register: beat k carries bytes k*size.. of the stream, at most 16 beats
  per burst), `max_len` (a cap on the beats per burst, for a slave or a
  fabric that takes less than the port), `size` defaulting to the bus
  width, one beat of the bus width per burst on an AXI4-Lite port whatever
  the caller asked, and `trans[$]`, the bursts with their responses after
  `start` returns, summed up by `worst_resp()` and `all_okay()`. It now
  extends `ovip_axi_base_master_sequence`, so the response queue is
  unbounded (it was 100 deep; a stream of more bursts lost responses) --
  a base-class change, so a sequence that extends this one inherits a
  different parent. The
  INCR split now cuts on the 4 KiB distance, so a cap that is not a power
  of two works. Timing per burst too: `data_start_event` and
  `max_addr_phase_delay` (where a write's data starts against its
  address), and `rready_pattern` / `bready_pattern` applied to every burst
  when set, beside the existing `max_data_delay` and `max_addr_delay`; the
  test drives them at random. `ovip_axi_bytestream_test` (random bus width and alignment
  per seed: strobe holes, caps, FIXED both ways against a slave that logs
  the beats) and `ovip_axi_bytestream_lite_test` are the proof.
- `ovip_axi_base_slave_sequence` writes and reads a FIXED burst through its
  INCR path one beat at a time, so a FIXED beat may be wider than the
  memory word (it was refused with `MISSING_FEATURE` above the word size,
  4 bytes by default).
- Four switches that drive what AXI leaves undefined, so a DUT that relies
  on OVIP's well-behaved default shows the bug instead of passing. Each is
  off by default, so an agent that sets none behaves exactly as before. The
  four, with the README section that describes each and the test that proves
  it:
  - `cfg.randomize_unstrobed_wdata` (master) -- a random value on every
    WDATA byte whose WSTRB bit is low, inside or outside the beat's byte
    window, instead of zero. It exposes a write packer that ORs whole WDATA
    words into one flit. "Bytes under a low strobe";
    `ovip_axi_unstrobed_wdata_test`.
  - `cfg.randomize_unused_rdata` (slave) -- a random value on every RDATA
    lane a narrow or unaligned beat does not use, instead of zero. A beat
    uses its size-aligned container, so this is every lane outside it. It
    exposes a read packer that ORs whole RDATA words. An AXI4-Lite read uses
    the whole bus, so the switch does nothing there. "Lanes a read beat does
    not use"; `ovip_axi_unused_rdata_test` and its `_no_auto_align` variant.
  - `cfg.randomize_idle_payload` (master and slave) -- random values on a
    channel's payload while its VALID is low (AW, W and AR at a master; B
    and R at a slave), at reset and after every handshake, instead of zero
    or the last value. It works with or without
    `drive_reset_values_when_idle`. It exposes an interface that takes a
    field before its handshake, such as one reading BRESP while BVALID is
    low. "Payload while VALID is low"; `ovip_axi_idle_payload_test`.
  - `cfg.awready_waits_for_wvalid` (slave, read at the start of the run) --
    AWREADY follows its ready pattern only while a write burst has offered
    WVALID ahead of its AW, counting WVALID high now or W beats the slave
    already took. AXI permits this and forbids a master to wait for AWREADY
    before WVALID, so such a master hangs and a watchdog or the transaction
    timeout names it. That includes this VIP's own
    `DATA_START_EV_ADDR_SAMPLED`. "A slave that waits for WVALID";
    `ovip_axi_awready_waits_for_wvalid_test`.

### Fixed -- VIP

- The master driver no longer lets a later write's AW overtake a parked
  data-before-address write: while such a write waits for its AW, no other
  AW is issued. Its W beats were already queued in order, and AXI pairs W
  bursts with AWs in order, so the overtaking AW took that write's data
  (the monitor reported INVALID_WSTRB or a missing WLAST, and a slave
  wrote one write's bytes at the other's address). It showed with several
  writes in flight whose `data_start_event` differed. The bytestream test's
  concurrent round is the proof.
- `ovip_axi_base_slave_sequence` writes and reads a WRAP burst through its
  INCR path one beat at a time, like FIXED, so a WRAP beat may be wider
  than the memory word (it was refused with `MISSING_FEATURE`).
- `ovip_axi_base_slave_sequence::write_transaction_to_mem` and
  `populate_data_from_mem` are virtual now, as their comments promised: a
  subclass that overrides them was not called from the base body.
- The monitor no longer X/Z-checks AWID, ARID, BID and RID on an AXI4-Lite
  agent: a Lite port has no ID pins, so an undriven ID wire is the normal
  state there, and a bench had to tie them to keep the check quiet.
- An AXI4-Lite agent now drives and samples AWPROT and ARPROT, which
  AXI4-Lite has (IHI0022 B1.1). The master driver returned before driving
  them, and the monitor returned before sampling, X-checking and
  stability-checking them. So a Lite master left AxPROT floating and a Lite
  monitor always reported 0. They stay gated by `awprot_en` and
  `arprot_en`, so an agent that does not enable them is unchanged.

## [0.3.1] -- 2026-09-28

### Fixed -- VIP

- An unaligned full-width FIXED burst now keeps every beat on its first
  beat's byte lanes, as AXI A3.4.1 requires. Both drivers and the monitor
  placed and sampled beats 1..N of a full-width burst from lane 0. That is
  right for INCR and WRAP, but a FIXED burst repeats its address. A
  VIP-to-VIP test could not see it, because both ends made the same error,
  so `ovip_axi_fixed_full_width_alignment_test` now also runs an unaligned
  burst and checks its lanes on the bus. The monitor now checks the strobes
  of every FIXED beat against those lanes, so a manually aligned full-width
  FIXED burst that put beats 1..N on lane 0 now reports `INVALID_WSTRB`.
- The WRAP byte-lane calculation is done in 64 bits. On an address at or
  above 2^31 a 32-bit `int` overflowed, the modulo went negative, and the
  byte lanes came out as `[-1:-2]`.

## [0.3.0] -- 2026-07-28

### Added -- VIP

- Per-transaction logging: `cfg.enable_trans_log` makes an agent write one line
  per completed transaction (with address / data / response phase timestamps) to
  a per-agent file, and `cfg.trans_log_combined_file` optionally appends to a
  shared, time-ordered combined log. Off by default; works on active and passive
  agents (and on ACE agents, which append coherency columns).
- `extra_forks()` hook on the base driver and monitor, so an extending VIP can
  add its own concurrent threads without copying the AXI ones.

### Changed -- VIP

- The four classes that hold a virtual-interface handle -- `ovip_axi_base_driver`,
  `ovip_axi_master_driver`, `ovip_axi_slave_driver` and `ovip_axi_monitor` -- are
  now parameterized on that type (`#(type IF_T = virtual ovip_axi_agent_if)`), so
  a VIP with a wider interface can reuse the AXI driving and sampling logic.
  The default keeps existing code working unchanged: a bare
  `ovip_axi_master_driver` still means `#(virtual ovip_axi_agent_if)`.
- References to the parameterized classes now carry an explicit `#()`, which
  strict parsers require.

## [0.2.0] -- 2026-06-08

### Changed -- VIP (breaking)

- Renamed the shared public types `bytestream` → `ovip_bytestream` and
  `bitstream` → `ovip_bitstream` (defined in `ovip_global_pkg`). All `ovip_axi`
  references -- notably `ovip_axi_bytestream_sequence.data` -- now use the
  prefixed names. Generic, unprefixed type names in a wildcard-imported package
  collide with user/other-library symbols; the `ovip_`-prefix matches the rest
  of the public API and is collision-safe. Update any code referencing the old
  names. The method names `read_bytestream`/`write_bytestream` are unchanged.

## [0.1.0] -- 2026-05-31

Initial public release.

### Added -- VIP

- Master and slave agents (`ovip_axi_agent`) configurable as active or passive.
- Protocol support: AXI3, AXI4, AXI4-Lite. (ACE / ACE-Lite enum values exist
  but the protocol is not implemented -- see "Known limitations" below.)
- Configurable bus width 1B-512B (out-of-spec ≥256B requires `size_width=4`).
- Configurable address, ID, and `*user` widths via runtime `cfg.*_width` and
  compile-time `OVIP_AXI_MAX_*` caps.
- Burst types: INCR, FIXED, and WRAP (all spec-legal lengths, narrow and
  full-width transfers). Monitor enforces WRAP's spec rules (length ∈
  {2,4,8,16}, start address aligned to `burst_size`).
- Byte-lane alignment with `cfg.auto_byte_lanes_alignment` -- user supplies
  lane-0-aligned data and the VIP shifts to the right byte lanes for narrow
  and unaligned transfers.
- Out-of-order completion (`*_out_of_order_depth`) and AXI3 W-channel
  interleaving (`wr_interleave_depth`), with five scheduling algorithms.
- Outstanding-transaction limits (`num_outstanding_*_transactions`) checked
  by the monitor with the `AXI_MON/OUTSTANDING_EXCEED` error.
- Per-transaction timing knobs: `bresp_delay`, `data_delay[]`,
  `addr_phase_delay`, `delay_until_next_addr`, `delay_until_next_data`.
- Ready-pattern API: struct `{cycles[$], loop}` with three delivery routes
  (config defaults, transaction field, driver helper `put_<chan>ready_pattern`).
- Three data-start events: `ADDR_DRIVEN`, `ADDR_SAMPLED`, `BEFORE_ADDR`.
- Mid-test reset support -- drivers, monitor, and base slave sequence all
  drop in-flight state and re-arm cleanly on `aresetn` cycling mid-run.
- Monitor X/Z and signal-stability checks (`OVIP_AXI_DISABLE_*` define to
  opt out; **on by default**).
- `ovip_axi_trans` is constrained-random ready: `rand` qualifiers on all
  payload/timing fields, with soft default caps controlled by per-field
  compile-time defines (`OVIP_AXI_TRANS_*_DELAY_MAX`).
- `ovip_mem` -- simple word-addressed associative-array memory model with
  byte-enable writes and a bytestream API.
- Base sequences:
  - `ovip_axi_base_master_sequence` -- `send()` + `wait_for_responses()` over
    the master's get/put driver model.
  - `ovip_axi_base_slave_sequence` -- memory-backed loopback, monitor_error →
    SLVERR auto-handling, configurable BRESP/RDATA timing, mid-test-reset
    survival, optional immediate-vs-deferred memory commit
    (`wr_mem_update_on_bresp`).

### Added -- integration / tooling

- **`ovip_axi.f`** -- single compile filelist that integrates the VIP into any
  Modelsim/Questa, VCS, or Xcelium flow. User sets `OVIP_ROOT` and adds
  `-f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f` to their existing compile step.
  See the README "Integrating into your environment" section.
- Cross-simulator portability: Modelsim/Questa, VCS, Xcelium all supported.
- `examples/ovip_axi/01_minimal_loopback/` -- self-contained hello-world with a
  multi-simulator `Makefile`. No external dependencies beyond a UVM-1.2
  simulator.

### Known limitations

These are tracked in [CONTRIBUTING.md](CONTRIBUTING.md) as wanted-features:

- **ACE / ACE-Lite** protocols are enum values only -- no functional
  implementation.
- **UVM transaction recording** (`accept_tr`/`begin_tr`/`end_tr`) is not
  wired up -- transactions don't show up as labeled streams in the waveform
  database.
- **UVM callbacks** on the monitor and drivers are not provided.
- **Functional coverage** -- the VIP ships no covergroups today.
