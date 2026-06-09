# Changelog

All notable changes to this VIP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

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
- **Continuous-packets profile (spec section 3.3)** -- the config flag is
  honored at `check_config` time; the monitor's runtime enforcement of "no
  null bytes within a packet" is not yet wired up.
- **UVM transaction recording** (`accept_tr` / `begin_tr` / `end_tr`) is
  not wired up.
- **UVM callbacks** on the monitor and drivers are not provided.
- **Functional coverage** -- the VIP ships no covergroups today.
