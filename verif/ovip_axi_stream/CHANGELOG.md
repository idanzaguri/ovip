# Changelog

All notable changes to this VIP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

## [0.3.0] -- 2026-11-12

### Added -- VIP

- `check_undefined_data_lanes` in `ovip_axi_stream_agent_config`, default
  0. With 1 the monitor's X/Z check and stability check cover TDATA and
  TUSER on every lane inside the configured widths, also the TDATA lanes
  of position bytes and the TDATA and TUSER lanes of null bytes.
- With `continuous_packets = 1` and TKEEP present the monitor checks the
  two null-byte rules of spec section 3.3 and reports `AXIS_MON/NULL_BYTE`:
  for a TKEEP bit LOW in a transfer with TLAST LOW, and for a null byte
  below a data byte in a transfer with TLAST HIGH. With the interleave
  check (`AXIS_MON/PKT_SCOPE`) and the `tstrb_en` check of `check_config`
  the flag now covers the three rules of the profile on the monitor side.
  The master driver does not check its items against the profile.

### Changed -- VIP

- By default the monitor's X/Z check and stability check cover TDATA only
  on the lanes of data bytes (TKEEP HIGH and TSTRB HIGH, where an absent
  TKEEP counts as HIGH and an absent TSTRB as TKEEP) and TUSER only on the
  lanes of data bytes and position bytes (TKEEP HIGH). They covered every
  lane, so a transmitter that left the TDATA lane of a null byte or a
  position byte X, or the TUSER bits of a null byte, or changed them while
  the beat waited, got `AXIS_MON/XZ_CHECK` or `AXIS_MON/STABILITY`,
  although that data is not valid (spec sections 2.5.2 and 2.9). Set
  `check_undefined_data_lanes = 1` to keep the checks on every lane.
- The monitor reports `AXIS_MON/PKT_SCOPE` only when `continuous_packets`
  is 1 (spec section 3.3): for a transfer whose TID or TDEST differs from
  the transfer before it, when that one had TLAST LOW. Without the flag
  such a transfer belongs to another stream and is no error. If your link
  must not interleave packets, set `continuous_packets = 1` on the agent.
  A monitor subclass that used the protected `current_tr` uses `open_tr`
  now, the open packets by `{TID, TDEST}`.
- A receiver agent with `tready_en = 0` does not drive TREADY at all. Its
  driver played the TREADY pattern on the wire before, and only left the
  reset value out. `put_tready_pattern` reports a warning on such an agent.
  If the transmitter on your link needs TREADY, set `tready_en = 1` on the
  receiver agent.
- The monitor of an active receiver queues packets for `response_req_port`
  only after the first `get()` call on it. A slave sequence no longer gets
  the packets that completed before it started. Start the slave sequence
  before the traffic it has to see.
- The master driver drives only the configured width of TDATA, TKEEP,
  TSTRB, TID, TDEST and TUSER. It put the whole field of the item on the
  MAX-width wire before, so bits above the width were not zero, and the
  monitor, which looks at the configured width, published another value
  than the item had. A field that is wider than its signal is now cut and
  reported with an `AXIS_DRV/TR_CHK` warning (the so far unused
  `OVIP_AXI_STREAM_CHECK_VALUE_VS_SIGNAL_WIDTH`). If you see the warning,
  fix the item or the width in the agent config.
- A one-shot TREADY pattern whose cycle counts sum to 0 no longer holds
  the level of its last index (`'{0}` held TREADY LOW). It is played as
  always ready, with the `AXIS_DRV/TREADY_PATTERN` warning. To hold TREADY
  LOW use `'{1}` with `loop = 0`.
- `tvalid_assert_time`, `first_beat_time` and `last_beat_time` of
  `ovip_axi_stream_trans` are `realtime` and the monitor fills them from
  `$realtime`. They were `time` and held `$time`, which the 1 ns time unit
  of the package rounds to whole ns. Code that copies them into a `time`
  variable, or prints them with an integer format, has to use `realtime`
  and `%t` or `%f`.
- CONTRIBUTING.md lists interleaved packets from the transmitter as a
  wanted feature, and has a "Known gaps" section: a reset in the time step
  in which a sequence calls `start_item` can end in "Get_next_item called
  twice".

### Removed -- VIP

- The field `tready_pattern` of `ovip_axi_stream_trans`. Nothing read it:
  a pattern set there never reached the receiver. The README named it as a
  third route to set a TREADY pattern. Use `cfg.default_tready_pattern` or
  `put_tready_pattern` of the receiver's slave driver.

### Fixed -- VIP

- The monitor kept one open packet for the whole channel. Interleaved
  streams, which the spec permits transfer by transfer (sections 2.7 and
  4.1), gave a false `AXIS_MON/PKT_SCOPE` and packets with the beats of
  two streams mixed: TID 1, TID 2, TID 1 with TLAST, TID 2 with TLAST came
  out as a three-beat packet and a one-beat packet. The monitor keeps one
  open packet per TID and TDEST pair now (one for the channel when neither
  `tid_en` nor `tdest_en` is set), and a reset drops them all. The master
  driver still sends one item as one packet: it does not interleave.
- With `tstrb_en` set, the master driver drove TSTRB all HIGH for a beat
  that the item has no `strb_beats` entry for. An item with `keep_beats`
  only and a null byte in it went out with the reserved TKEEP=0 TSTRB=1
  combination and the monitor reported `AXIS_MON/BYTE_QUAL`. The driver
  now drives TSTRB equal to the TKEEP of that beat (spec section 3.1.2),
  the default `get_data_bytes()` already used.
- With `tready_en = 0` the master driver still waited for the TREADY wire
  to be 1 and the monitor sampled a transfer only when it was 1, so a link
  without TREADY hung with TVALID HIGH unless the wire was tied HIGH. The
  master driver and the monitor take an absent TREADY as HIGH now (spec
  section 3.1.1): every cycle with TVALID HIGH is a transfer, and the
  monitor's stability and wake-up checks, which watch a waiting beat, do
  not run.
- `ovip_axi_stream_trans::compare()` failed on a queue that only one side
  filled, so the scoreboard reported `AXIS_SB/MISMATCH` on correct
  traffic: with `tkeep_en = 0` and `tstrb_en = 0` the monitor fills no
  `keep_beats` and `strb_beats` while `ovip_axi_stream_simple_packet_seq`
  always does, and with `tuser_en = 1` the monitor fills `user_beats`
  while the sequence does not. `keep_beats`, `strb_beats` and `user_beats`
  are compared only when both items filled them now, as `ovip_axi` does
  for `resp_beats`, and `diff()` follows the same rule.
- The monitor of an active receiver copied every packet into the queue
  behind `response_req_port`, also when no slave sequence read it. Only a
  reset emptied the queue, so it grew with every received packet (50
  packets left 50 copies). Nothing is queued until a reader has called
  `get()`.
- A randomized `ovip_axi_stream_trans` had unrelated random `keep_beats`
  and `strb_beats`, so about a quarter of its bytes had the reserved
  TKEEP=0 TSTRB=1 combination. The new constraint
  `c_no_reserved_byte_qualifier` allows no TSTRB bit where the TKEEP bit of
  the same beat is clear. Turn it off with `constraint_mode(0)` to
  randomize a reserved byte on purpose. The item still does not know the
  agent's configuration: the README ("Writing sequences") says what a bare
  `randomize()` leaves to the user, and what it gives on Verilator.
- The monitor's wake-up check took a reset under a waiting beat as
  "TWAKEUP deasserted before TREADY" (`AXIS_MON/WAKEUP`), when the
  transmitter dropped TWAKEUP with the reset, as an asynchronously reset
  one does. The check now ends the transfer on an edge where ARESETn is
  low, as the stability check does since 0.2.0.
- The monitor's exit-from-reset check reported `AXIS_MON/RESET` with no
  reset before it, on a bench that holds ARESETn HIGH from time 0: it took
  the first clock edge with ARESETn HIGH as an exit from reset, and it
  took a TVALID that is still X or Z there as asserted. The master
  driver's first drive reaches the wire at the first clock edge, so such
  a bench got the error with no traffic at all. The check now runs only
  after ARESETn was sampled LOW once, and flags TVALID only when it is 1.
- A TREADY pattern with `loop = 1` whose cycle counts are all 0 was an
  endless loop in zero time in the slave driver: the simulation stopped
  advancing. A pattern whose counts sum to 0 now falls back to always
  ready with an `AXIS_DRV/TREADY_PATTERN` warning, as the `ovip_axi`
  drivers do for their ready patterns.
- The monitor's X/Z reports on TVALID, TREADY, TLAST and TWAKEUP had the
  message ID `AXIS_MON/XZ_CHECK` without the `agent_tag` prefix that every
  other monitor report has. `OVIP_AXI_STREAM_MON_XZ_CHECK` puts the prefix
  in front now.
- `ovip_axi_stream_simple_packet_seq` built 32-bit data for every bus
  width, so on a bus of less than 4 bytes the scoreboard reported
  `AXIS_SB/MISMATCH` on its packets. The data is cut to `tdata_width`
  bytes. The comment of `tdata_width` said the width comes from the agent
  config: it is the sequence's own field, and the user sets it.
- Documentation. The README ("AXI5 parity" row), CONTRIBUTING, the header
  of the monitor and the comment of `parity_en` said that the parity
  property is declared, that the check signals are wired through, and that
  the monitor checks parity when `parity_en` is set. None of it exists:
  the interface has no check signals, nothing generates or checks parity,
  and `parity_en` is read only by `check_config`. The text says so now,
  and CONTRIBUTING names the ten check signals of spec Table 5-1.
- README: no text said what a reset does. The new section "Reset" says
  what the master driver, the receiver and the monitor do at a reset, when
  a test may call `stop_sequences()` on the transmitter's sequencer, and
  that `put_tready_pattern` belongs in a thread synchronized to the
  clocking block.
- The comments of `drive_reset_values_when_idle`,
  `num_outstanding_transactions` and `tr_timeout_us` in
  `ovip_axi_stream_agent_config` described a driver behavior, a cap on
  open packets and a watchdog. Nothing reads the three fields. Each
  comment now says that the field has no effect in this version.
- `NOTICE` named ovip_axi in its first line. It names ovip_axi_stream now.
- Comments. `tvalid_assert_time` of `ovip_axi_stream_trans` holds the
  time of the first handshake of the packet, as `first_beat_time` does, not
  the time TVALID rose; the comments in the item and in the monitor say so
  now. The comments of `bus_width` and `tuser_bits_per_byte` said that the
  drivers set or use them: only the monitor sets them. The comment of
  `exit_from_reset_check` names the edges T2 and T3 of spec Figure 2-4,
  not T1 and T2. In `ovip_axi_stream_simple_packet_seq` a packet past the
  end of `ids` or `dests` gets 0, not the last element.
- A `vif` that was set in `uvm_config_db` for the agent's path only ended
  in `UVM_FATAL MISSING_VIF`: the agent read it in `connect_phase`, and the
  monitor and the drivers read it from `uvm_config_db` themselves in
  `build_phase`. The agent now gets `vif` in `build_phase` and sets it for
  its monitor and drivers, as it does with `cfg`. A `vif` set with a
  wildcard below the agent path still works.
- The monitor's X/Z check on TVALID and TREADY ran on the edge where
  ARESETn is first sampled LOW. Whether X or Z there was reported
  (`AXIS_MON/XZ_CHECK`) depended on the order in which the check and the
  reset thread woke on that edge. The check skips that edge now, as the
  stability check does.
- The README says that every source file opens with a short header.
  `ovip_axi_stream_agent.sv`, `ovip_axi_stream_agent_config.sv`,
  `ovip_axi_stream_defines.sv`, `ovip_axi_stream_pkg.sv` and
  `ovip_axi_stream_types.sv` had none. They have one now.

### Added -- testbench

- `ovip_axi_stream_interleave_test`: streams interleaved transfer by
  transfer, by TID and by TDEST, each collected as its own packet and
  matched by the scoreboard, and a reset with two packets open. The
  transmitter agent is passive and the test drives the transfers through
  `master_cb` (`wire_transfer` in the base test).
- `ovip_axi_stream_continuous_packets_test`: with `continuous_packets = 1`,
  packets in a row give no error, interleaved packets give
  `AXIS_MON/PKT_SCOPE`, and a null byte within a packet gives
  `AXIS_MON/NULL_BYTE`, where null bytes above the data bytes of the last
  transfer give none.
- `ovip_axi_stream_byte_qual_default_test`: the TKEEP and TSTRB the master
  driver drives for items with `keep_beats` only, with no qualifier queue
  and with both queues.
- `ovip_axi_stream_no_tready_test`: `tready_en = 0` on both agents and
  nothing driving the wire. The packets go out one beat per cycle and the
  scoreboard matches them.
- `ovip_axi_stream_compare_test`: the scoreboard on a link with TKEEP and
  TSTRB absent and TUSER present, and `compare()` and `diff()` called
  directly with a queue that one side did not fill.
- `ovip_axi_stream_response_req_test`: the queue behind `response_req_port`
  stays empty with no slave sequence, and a slave sequence gets the
  packets sent after it started.
- `ovip_axi_stream_width_test`: a 2-byte bus with 4 bits of TID and of
  TDEST and 2 TUSER bits per byte. The packets of
  `ovip_axi_stream_simple_packet_seq` match, an item that is too wide in
  six fields gives six `AXIS_DRV/TR_CHK` warnings and arrives cut, and no
  wire carries a bit above its width.
- `ovip_axi_stream_undefined_lanes_test` and
  `ovip_axi_stream_undefined_lanes_checked_test`: X and one-cycle changes
  on the TDATA and TUSER lanes of null bytes, position bytes and data
  bytes, with `check_undefined_data_lanes` 0 and 1. X held on a data byte
  through a wait gives no `AXIS_MON/STABILITY`.
- `ovip_axi_stream_wakeup_reset_test`: AXI5-Stream agents with TWAKEUP, a
  reset under a waiting beat with TVALID and TWAKEUP dropped with it, then
  a packet with TWAKEUP HIGH after the release.
- `ovip_axi_stream_exit_from_reset_test`: TVALID HIGH before the first
  reset and TVALID Z on an exit edge give no error, and TVALID HIGH on an
  exit edge gives `AXIS_MON/RESET`. TVALID Z on the edge where ARESETn is
  first sampled LOW gives no `AXIS_MON/XZ_CHECK`.
- `ovip_axi_stream_tready_pattern_test`: patterns whose counts sum to 0
  give the warning and always ready.
- `ovip_axi_stream_agent_tag_test`: with `agent_tag` set, a reserved byte
  and X on TLAST are reported with the tag in front of the message ID.

## [0.2.0] -- 2026-10-26

### Changed -- VIP

- `ovip_axi_stream_pkg` declares `timeunit 1ns; timeprecision 1ps;`. The
  package took the time unit of the compilation unit before (the simulator's
  default, or an earlier `timescale` in the compile order); `$time` and
  `$realtime` in log lines and transaction time stamps are in ns on every
  simulator now. Verilator no longer reports `TIMESCALEMOD` for it.

- The interface's clocking blocks (`monitor_cb`, `master_cb`, `slave_cb`)
  take their skews from `OVIP_INPUT_SKEW` and `OVIP_OUTPUT_SKEW`
  (`ovip_common/ovip_common_defines.sv`, overridable with `+define+`)
  instead of the hard-coded `input #1step output #0`. The defaults are the
  same values, so nothing changes unless you override them.

### Fixed -- VIP

- The master driver sent a packet from before a reset again after the
  release, and then called `item_done()` with no item outstanding (a
  UVM_FATAL). It kept the item it held when the reset came: one taken from
  the sequencer but not yet started, or the last one, done, in its gap
  before the next. It now marks an item in progress as soon as it takes it,
  so the reset releases it, and drops whatever it held at every reset.
  Found by logion_tb's reset test on a NoC's stream transmitter.
- The monitor's stability check took a reset under a waiting beat as
  "TVALID deasserted before TREADY", when the transmitter dropped TVALID
  with the reset, as an asynchronously reset one does. The check thread and
  `rst_monitor` wake on that edge in either order; the check now ends the
  transfer on an edge where ARESETn is low.
- The monitor's reset check flagged TVALID on the first cycle of a reset in
  the middle of a packet (`AXIS_MON/RESET`). A synchronous transmitter sees
  the reset on that same edge, so TVALID cannot be low yet. The check now
  gives the first reset cycle grace, as `ovip_axi`'s monitor does, and
  checks every reset cycle after it, not only the first.

### Added -- testbench

- `ovip_axi_stream_mid_test_reset_test`: a reset in the middle of a packet,
  then packets after the release, each matched by the scoreboard.
- `ovip_axi_stream_mid_test_reset_gap_test`: a reset in the gap after a
  packet, and one under a waiting beat with TVALID dropped with it; after
  each release, nothing from before the reset may arrive.

## [0.1.2] -- 2026-10-05

### Fixed -- VIP

- The monitor's checks and samples look at the configured width of each
  signal only (`tdata_width`, `tid_width`, `tdest_width`,
  `tuser_bits_per_byte`), through masks like ovip_axi's. It used the whole
  MAX-width wire, so a receiver whose DUT port drives only the low bits
  reported X on TDATA, TKEEP and TID and a TID change inside every packet
  (seen on the logion_tb stream test, axis_cnt's `disp`). A width of 0 on
  TID or TDEST keeps the whole wire, as before.

## [0.1.1] -- 2026-09-02

### Fixed -- VIP

- The master driver now aligns to the clocking event before driving an item a
  sequence delivered mid-cycle (a #-timed test, or any sequence not
  synchronized to the bus clock). Unaligned entry meant the first beat
  de-phased from the clocking event and was lost against a receiver already
  holding TREADY high. A held item from `try_next_item` skips the alignment,
  so back-to-back operation is unchanged: the next transfer still starts on
  the completion edge.

## [0.1.0] -- 2026-06-09

Initial release. The VIP ships with both AXI4-Stream and AXI5-Stream support.

### Added -- VIP

- Transmitter (`OVIP_AXI_STREAM_TRANSMITTER`) and Receiver
  (`OVIP_AXI_STREAM_RECEIVER`) agents (`ovip_axi_stream_agent`), each
  switchable between active and passive.
- Single point-to-point channel covering the full AXI4-Stream + AXI5-Stream
  signal set: TDATA, TSTRB, TKEEP, TLAST, TID, TDEST, TUSER, plus the AXI5
  TWAKEUP. Each signal is gated by a per-agent `*_en` flag.
- Per-byte TUSER (`tuser_bits_per_byte * tdata_width` total) with the
  spec-section-2.9 indexing exposed via
  `ovip_axi_stream_trans::get_tuser_for_byte`.
- Monitor with all spec checks inline: XZ on TVALID/TREADY at every cycle,
  XZ on payload while TVALID is HIGH, TVALID + payload stability between
  assertion and handshake (spec section 2.2), TKEEP=0 + TSTRB=1 reserved
  combination (spec section 2.5.3), TID and TDEST stable within a packet
  (spec section 2.6), TVALID LOW during reset, exit-from-reset rule (spec
  section 2.8.2), AXI5 TWAKEUP hold-until-TREADY (spec section 2.3).
- Per-receiver TREADY pattern API (`ovip_axi_stream_ready_pattern_t`,
  `default_tready_pattern`, per-transaction override, `put_tready_pattern`
  helper) -- same shape as the ovip_axi ready patterns.
- `ovip_axi_stream_trans` with per-beat queues for data / keep / strb /
  user, packet-scope id / dest / wakeup, observability timestamps,
  do_copy / do_compare (interface-signal-only) / diff() framework, and a
  `get_data_bytes(bit include_position_bytes=0)` helper that filters out
  null (TKEEP=0) and -- optionally -- position (TSTRB=0) bytes.
- `ovip_axi_stream_scoreboard` with per-TID FIFOs of expected packets,
  defensive_copy_expected knob (default off), `trans.diff()`-formatted
  mismatch reports, and end-of-test orphan / unexpected / matched counters.
- Sequence library: `ovip_axi_stream_base_master_sequence` (send + body
  template), `ovip_axi_stream_base_slave_sequence` (forever response-port
  consumer with a `process_request` hook),
  `ovip_axi_stream_simple_packet_seq` (configurable N-packet builder).
- Apache-2.0 licensed; portable across Modelsim/Questa, VCS, Xcelium.

### Added -- integration / tooling

- **`ovip_axi_stream.f`** -- single compile filelist; set `OVIP_ROOT`,
  add `-f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f` to the
  compile step.
- Cross-simulator portability: Modelsim/Questa, VCS, Xcelium all supported.
- `examples/ovip_axi_stream/01_loopback/` -- hello-world: T -> R round-trip,
  `UVM_ERROR : 0` is the success criterion.
- `examples/ovip_axi_stream/02_rx_to_mem/` -- receiver-side subscriber pulls
  `trans.get_data_bytes()` and writes into `ovip_mem` at a running address;
  the test reads the bytes back out of mem and verifies them.

### Known limitations

These are tracked in [CONTRIBUTING.md](CONTRIBUTING.md) as wanted-features:

- **AXI5 parity (`*CHK` signals)** -- the property is declared
  (`Check_Type = Odd_Parity_Byte_All`) and the signals are wired through
  the interface and reserved on the trans, but the monitor's odd-parity
  computation and the master driver's parity-bit generation ship in a
  follow-up release.
- **UVM transaction recording** (`accept_tr` / `begin_tr` / `end_tr`) is
  not wired up.
- **UVM callbacks** on the monitor and drivers are not provided.
- **Functional coverage** -- the VIP ships no covergroups today.
