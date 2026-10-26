# Changelog -- ovip_ace

All notable changes to this VIP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions before 1.0.0 may include breaking changes between minor releases -- those
breaks are called out explicitly in their changelog entry.

## [Unreleased]

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
