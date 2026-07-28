# Contributing to ovip_apb

Thanks for your interest in improving ovip_apb! Contributions are
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

- **Naming:** classes and types are prefixed `ovip_apb_`; compile-time
  defines, enum values, and other macros use the `OVIP_APB_` namespace
  (width limits are `OVIP_APB_MAX_*`). Keep new public symbols inside
  that namespace.
- **Indentation:** tabs.
- **Include guards:** wrap every `.sv` include file in
  `` `ifndef <FILE>__SV `` / `` `define `` / `` `endif ``.
- **Comments:** explain *why* something non-obvious is done, not *what* the
  code does. Each file opens with a short header describing its purpose and
  where to look next.

## Wanted features

The following are open and welcome as contributions:

- **APB5 support (as an opt-in protocol mode).** PWAKEUP wake-up signaling,
  user signaling (PAUSER/PWUSER/PRUSER/PBUSER), interface parity (`*CHK`
  signals, Check_Type = Odd_Parity_Byte_All per chapter 5), and PNSE/RME.
  These were deliberately left out of the initial release (see
  `CHANGELOG.md`); a contribution should add the wires at MAX width, gate
  them behind `cfg.*_en` + a new `OVIP_APB_PROTOCOL_APB5` enum value, and
  ship regression tests per feature.
- **Multi-completer PSELx modeling** (an address-decode layer that maps one
  requester agent onto several completer interfaces).
- **Functional coverage groups** on address distribution, wait-state
  profiles, SLVERR frequency, strobe patterns, PPROT values, etc.
- **UVM transaction recording** (`accept_tr` / `begin_tr` / `end_tr`) so
  transfers show up as labeled streams in waveform databases.
- **UVM callbacks** on the monitor and drivers for users who need
  injection hooks.

## Reporting issues

Open an issue describing the smallest reproducible scenario. For protocol
questions, point at the relevant section of ARM IHI 0024E if you can -- it
keeps the conversation specific.
