# Contributing to ovip_axi_stream

Thanks for your interest in improving ovip_axi_stream! Contributions are
welcome -- whether that's a bug fix, a new feature, or documentation.

## How to contribute

1. Fork the repository and create a branch for your change.
2. Make your change (see conventions below).
3. Open a pull request describing **what** changed and **why**. Reference
   the relevant wanted-features bullet below or a `CHANGELOG.md` known
   limitation if your change addresses one.
4. The maintainer reviews each pull request before it is merged.

> **Commit with a GitHub-linked email.** You are credited on the Contributors
> page only when your commits' **author** email is one that is verified on your
> GitHub account (Settings > Emails), or your
> `NNNN+username@users.noreply.github.com` address. Otherwise your name shows in
> the history but not in the contributor list. If you already pushed with the
> wrong email, add and verify it on GitHub and the credit applies retroactively.

By submitting a contribution you agree that it is licensed under the
project's license (Apache-2.0, see [LICENSE](LICENSE)) -- inbound
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

- **AXI5 parity (`Check_Type = Odd_Parity_Byte_All`, spec chapter 5).**
  Nothing of it exists yet. The interface has none of the ten check signals
  of spec Table 5-1 (TVALIDCHK, TREADYCHK, TDATACHK, TSTRBCHK, TKEEPCHK,
  TLASTCHK, TIDCHK, TDESTCHK, TUSERCHK, TWAKEUPCHK), nothing generates or
  checks parity, and `cfg.parity_en` is read only by `check_config`. A
  complete contribution would (1) add the ten check signals to the
  interface and its clocking blocks; (2) drive odd parity on them in the
  master driver (TVALIDCHK, TDATACHK, TSTRBCHK, TKEEPCHK, TLASTCHK, TIDCHK,
  TDESTCHK, TUSERCHK, TWAKEUPCHK) and in the slave driver (TREADYCHK);
  (3) check every check signal in the monitor when `parity_en` is set; (4)
  add a regression test with correct parity and with a flipped bit (the
  latter absorbed via expected_errors).
- **Interleaved packets from the transmitter.** The master driver sends
  each `ovip_axi_stream_trans` as one whole packet, so the transfers of
  packets with a different TID or TDEST never interleave on the wire. The
  monitor already keeps one open packet per TID and TDEST pair (spec
  section 2.7), so only the driver side is missing.
- **Functional coverage groups** on TID/TDEST distribution, TLAST cadence,
  null/position byte frequency, TREADY back-pressure profiles, etc.
- **UVM transaction recording** (`accept_tr` / `begin_tr` / `end_tr`) so
  packets show up as labeled streams in waveform databases.
- **UVM callbacks** on the monitor and drivers for users who need
  injection hooks.

## Known gaps

- **A reset in the time step of a `start_item`.** When a reset kills the
  master driver while it waits in `get_next_item`, in the same time step in
  which a sequence calls `start_item`, the next `get_next_item` can end in
  the UVM error "Get_next_item called twice". It was found by reading
  `src/ovip_axi_stream_master_driver.sv`; no test hits it.

## Reporting issues

Open an issue describing the smallest reproducible scenario. For protocol
questions, point at the relevant section of ARM IHI 0051B if you can -- it
keeps the conversation specific.
