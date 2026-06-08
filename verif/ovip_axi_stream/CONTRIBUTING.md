# Contributing to ovip_axi_stream

Thanks for your interest in improving ovip_axi_stream! Contributions are
welcome — whether that's a bug fix, a new feature, or documentation.

## How to contribute

1. Fork the repository and create a branch for your change.
2. Make your change (see conventions below).
3. Open a pull request describing **what** changed and **why**. Reference
   the relevant wanted-features bullet below or a `CHANGELOG.md` known
   limitation if your change addresses one.
4. The maintainer reviews each pull request before it is merged.

By submitting a contribution you agree that it is licensed under the
project's license (Apache-2.0, see [LICENSE](LICENSE)) — inbound
contributions are under the same terms as the project.

## Coding conventions

The VIP is SystemVerilog targeting **UVM 1.2**:

- **Naming:** classes and types are prefixed `ovip_axi_stream_`; compile-time
  defines, enum values, and other macros use the `OVIP_AXI_STREAM_` namespace
  (width limits are `OVIP_AXI_STREAM_MAX_*`). Keep new public symbols inside
  that namespace.
- **Indentation:** tabs.
- **Include guards:** wrap every `.sv` include file in
  `` `ifndef <FILE>__SV `` / `` `define `` / `` `endif ``.
- **Comments:** explain *why* something non-obvious is done, not *what* the
  code does. Each file opens with a short header describing its purpose and
  where to look next.

## Wanted features

The following are open and welcome as contributions:

- **AXI5 parity (`*CHK` signals) enforcement.** The property and the wires
  are in place; the monitor's odd-parity computation and the master driver's
  parity-bit generation are not. A complete contribution would (1) compute
  per-byte odd parity in the master driver for TDATA, TSTRB, TKEEP, TLAST,
  TID, TDEST, TUSER, TWAKEUP; (2) verify on the receiver-side monitor; (3)
  add a regression test exercising both happy-path parity and a flipped-bit
  failure case (the latter absorbed via expected_errors).
- **Continuous-packets profile runtime enforcement.** The config flag is
  honored at `check_config` time; add the monitor checks that flag null
  bytes within a packet and disallow interleaving when the property is set.
- **Functional coverage groups** on TID/TDEST distribution, TLAST cadence,
  null/position byte frequency, TREADY back-pressure profiles, etc.
- **UVM transaction recording** (`accept_tr` / `begin_tr` / `end_tr`) so
  packets show up as labeled streams in waveform databases.
- **UVM callbacks** on the monitor and drivers for users who need
  injection hooks.

## Reporting issues

Open an issue describing the smallest reproducible scenario. For protocol
questions, point at the relevant section of ARM IHI 0051B if you can — it
keeps the conversation specific.
