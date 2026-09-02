# Changelog

All notable changes to this VIP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

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
