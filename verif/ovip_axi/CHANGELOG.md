# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

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
