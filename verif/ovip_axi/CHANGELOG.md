# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases — those
breaks are called out explicitly in their changelog entry.

## [0.2.0] — 2026-06-08

### Changed — VIP (breaking)

- Renamed the shared public types `bytestream` → `ovip_bytestream` and
  `bitstream` → `ovip_bitstream` (defined in `ovip_global_pkg`). All `ovip_axi`
  references — notably `ovip_axi_bytestream_sequence.data` — now use the
  prefixed names. Generic, unprefixed type names in a wildcard-imported package
  collide with user/other-library symbols; the `ovip_`-prefix matches the rest
  of the public API and is collision-safe. Update any code referencing the old
  names. The method names `read_bytestream`/`write_bytestream` are unchanged.

## [0.1.0] — 2026-05-31

Initial public release.

### Added — VIP

- Master and slave agents (`ovip_axi_agent`) configurable as active or passive.
- Protocol support: AXI3, AXI4, AXI4-Lite. (ACE / ACE-Lite enum values exist
  but the protocol is not implemented — see "Known limitations" below.)
- Configurable bus width 1B–512B (out-of-spec ≥256B requires `size_width=4`).
- Configurable address, ID, and `*user` widths via runtime `cfg.*_width` and
  compile-time `OVIP_AXI_MAX_*` caps.
- Burst types: INCR, FIXED, and WRAP (all spec-legal lengths, narrow and
  full-width transfers). Monitor enforces WRAP's spec rules (length ∈
  {2,4,8,16}, start address aligned to `burst_size`).
- Byte-lane alignment with `cfg.auto_byte_lanes_alignment` — user supplies
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
- Mid-test reset support — drivers, monitor, and base slave sequence all
  drop in-flight state and re-arm cleanly on `aresetn` cycling mid-run.
- Monitor X/Z and signal-stability checks (`OVIP_AXI_DISABLE_*` define to
  opt out; **on by default**).
- `ovip_axi_trans` is constrained-random ready: `rand` qualifiers on all
  payload/timing fields, with soft default caps controlled by per-field
  compile-time defines (`OVIP_AXI_TRANS_*_DELAY_MAX`).
- `ovip_mem` — simple word-addressed associative-array memory model with
  byte-enable writes and a bytestream API.
- Base sequences:
  - `ovip_axi_base_master_sequence` — `send()` + `wait_for_responses()` over
    the master's get/put driver model.
  - `ovip_axi_base_slave_sequence` — memory-backed loopback, monitor_error →
    SLVERR auto-handling, configurable BRESP/RDATA timing, mid-test-reset
    survival, optional immediate-vs-deferred memory commit
    (`wr_mem_update_on_bresp`).

### Added — integration / tooling

- **`ovip_axi.f`** — single compile filelist that integrates the VIP into any
  Modelsim/Questa, VCS, or Xcelium flow. User sets `OVIP_ROOT` and adds
  `-f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f` to their existing compile step.
  See the README "Integrating into your environment" section.
- Cross-simulator portability: Modelsim/Questa, VCS, Xcelium all supported.
- `examples/01_minimal_loopback/` — self-contained hello-world with a
  multi-simulator `Makefile`. No external dependencies beyond a UVM-1.2
  simulator.

### Known limitations

These are tracked in [CONTRIBUTING.md](CONTRIBUTING.md) as wanted-features:

- **ACE / ACE-Lite** protocols are enum values only — no functional
  implementation.
- **UVM transaction recording** (`accept_tr`/`begin_tr`/`end_tr`) is not
  wired up — transactions don't show up as labeled streams in the waveform
  database.
- **UVM callbacks** on the monitor and drivers are not provided.
- **Functional coverage** — the VIP ships no covergroups today.
