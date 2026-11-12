# Contributing to ovip_ace

Thanks for your interest in improving ovip_ace! Contributions are welcome --
whether that's verification, a bug fix, a new feature, or documentation.

> **:rotating_light: This VIP was written by an AI (Claude) and has NOT been
> functionally verified by a human.** See the [README](README.md) banner.
> That makes **verification the single most valuable thing you can contribute.**

## How to contribute

1. Fork the repository and create a branch for your change.
2. Make your change (see conventions below).
3. Open a pull request describing **what** changed and **why**. Reference the
   relevant wanted-feature bullet below if your change addresses one.
4. The maintainer reviews each pull request before it is merged.

> **Commit with a GitHub-linked email.** You are credited on the Contributors
> page only when your commits' **author** email is one that is verified on your
> GitHub account (Settings > Emails), or your
> `NNNN+username@users.noreply.github.com` address. Otherwise your name shows in
> the history but not in the contributor list. If you already pushed with the
> wrong email, add and verify it on GitHub and the credit applies retroactively.

By submitting a contribution you agree that it is licensed under the project's
license (Apache-2.0, see [LICENSE](LICENSE)) -- inbound contributions are under
the same terms as the project (Apache-2.0, Section 5).

## Where to start -- wanted features

### :one: Verify the VIP *(by far the most wanted contribution)*

The code compiles and the coherent-loopback example runs to `UVM_ERROR : 0`
with its read data, its snoop and its RACK / WACK checked. An audit fixed the
errors that the CHANGELOG lists and checked each fix with a directed test on
Questa and on Verilator (the constraints of `ovip_ace_trans` on Verilator
only). **Those tests are not in the repository, and there is no regression.**
Bringing this VIP to a trustworthy state is the top priority.

**How to run what exists today:**

```sh
cd examples/ovip_ace/01_coherent_loopback
make SIM=modelsim          # or SIM=vcs / SIM=xcelium
# Watch the UVM Report Summary. Today: UVM_ERROR : 0.
```

Compile the VIP standalone (any simulator) with:

```sh
export OVIP_ROOT=/path/to/ovip
vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_ace/ovip_ace.f    # Questa/Modelsim
```

**Concrete verification tasks, roughly in priority order:**

- **Build a testbench and a regression** for ovip_ace under the standard
  runners, so this VIP is covered the way ovip_axi is. The tasks below say
  what the audit's directed tests covered. Each of them needs a test in the
  repository.
- **The snoop path.** Covered: the AC -> CR (-> CD) handshake between
  `ovip_ace_slave_driver::snoop_request_driver` and
  `ovip_ace_master_driver::snoop_phase_driver` with and without snoop data,
  CD before, with and after CR, an interconnect that waits for CDVALID before
  CRREADY, a master that holds ACREADY HIGH, three snoops in a row, and a reset
  in the middle of a CD burst, with the reports of `snoop_channel_monitor`
  read field by field. Not covered: a real cached master or interconnect.
- **RACK / WACK.** Covered: `rack_wack_driver` (master) sends one acknowledge
  in the cycle after each RLAST or B handshake, and
  `rack_wack_sequencing_monitor` reports an acknowledge with none owed and one
  that is still owed when the test ends, on masters that acknowledge on time,
  never, twice, too early and with nothing to acknowledge.
- **The protocol checks.** Each check in `ovip_ace_monitor` (reserved
  encodings, the AxDOMAIN rules of Tables D3-7 and D3-8, the cache line rules
  of Table D3-10 for reads, AWUNIQUE of Table D3-9, the ACE-Lite subset of D11,
  the snoop response rules of Table D3-22 and D13.2.5, the stability checks)
  was run on legal traffic, where it must pass, and on the illegal case it
  claims to catch. The README section "Spec coverage" lists them.
- **ACE-Lite.** Covered: on an `OVIP_ACE_PROFILE_ACE_LITE` pair RACK / WACK
  stay LOW, `push_snoop()` is refused, and a ReadShared and a WriteBack are
  reported. A DVM transaction in ACE-Lite is not reported.
- **Randomization.** The constraints of `ovip_ace_trans` were checked on
  Verilator only. Run them on a simulator with a full constraint solver.

### Other wanted features

- **Snoop-response scoreboard / cache predictor** -- model the master's cache
  state and check its CRRESP against the legal end-state tables (D4 + D5). The
  `ovip_ace_scoreboard` snoop export is the hook; the predictor is the work.
- **Cache-state tracking (`OVIP_ACE_CACHE_MODEL_TRACK`).** The config knob
  and the state hint fields of `ovip_ace_trans` exist and nothing reads them.
  The cache model itself does not exist.
- **DVM transactions** -- encodings are decoded but DVM message semantics are
  not modelled.
- **Barriers.** Deprecated in ACE5 and not supported. `c_no_barriers` keeps
  AxBAR at 0b00 in a randomized item. Nothing else stops a barrier: an item
  that a test builds with AxBAR\[0\] = 1 goes on the wire with no message and
  is answered as a normal transaction. Add support if a downstream user
  needs it.

### Known gaps

Found by the audit, and not fixed:

- **Transactions with a single R transfer.** CleanUnique, MakeUnique,
  CleanShared, CleanInvalid, MakeInvalid, DVM transactions and read barriers
  complete in one R transfer with RLAST (D3.2.1). The VIP slave answers them
  with ARLEN + 1 beats, and both monitors report a one-beat response as
  "xLAST was asserted on transfer #1", through the length check that they
  inherit from `ovip_axi_monitor`.
- **Evict and write barriers have no write data** (D4.1.1, D4.9.1). The master
  driver drives AWLEN + 1 W beats for them, and the monitor and the VIP slave
  wait for W data.
- **AxCACHE, AxPROT and AxLOCK are not driven.** The enables of the base config
  (`arcache_en`, `awcache_en`, `arprot_en`, `awprot_en`, `arlock_en`,
  `awlock_en`) stay 0, and `make_read()` and `make_write()` do not set
  `axcache`, where Tables D3-3 and D3-10 to D3-12 ask for a Modifiable
  AxCACHE that matches the domain.
- **One snoop at a time.** The snoop monitor and the slave driver follow one
  snoop from its AC handshake to its CR handshake and its last CD beat. The
  protocol allows several outstanding snoops (D6.2).
- **Monitor checks that do not exist.** `ovip_ace_monitor` does not check:
  - the reset values: ACVALID, CRVALID, CDVALID, RACK and WACK LOW while
    ARESETn is LOW (D2.3.3);
  - AxCACHE against AxDOMAIN (Table D3-3);
  - the cache line rules on writes: the constraints of Table D3-10 on
    WriteLineUnique, WriteEvict and Evict, and those of Table D3-12 on
    WriteBack and WriteClean. The monitor checks Table D3-10 on reads only;
  - RRESP[3:2] (IsShared, PassDirty) against the responses that Table D3-15
    permits for each read;
  - the CRRESP rules of Table D3-22, which response a snoop may get. Only
    PassDirty without DataTransfer is checked;
  - ACADDR aligned to the width of the snoop data bus (D3.6.2);
  - the D6.2 ordering between a response, its acknowledge and a snoop to
    the same cache line.

## Coding conventions

SystemVerilog targeting **UVM 1.2**. To keep the code consistent:

- **Naming:** classes/types are prefixed `ovip_ace_`; compile-time defines and
  enum values use the `OVIP_ACE_` namespace (width limits are `OVIP_ACE_MAX_*`).
- **Indentation:** tabs (match the surrounding file).
- **Include guards:** wrap every `.sv` include file in
  `` `ifndef <FILE>__SV `` / `` `define `` / `` `endif ``.
- **Comments:** explain *why* something non-obvious is done. Cite the spec
  section (e.g. `D3.1.6`) for protocol rules.
- Because the VIP is unverified, **prefer adding a check plus a test that proves
  it** over adding an unchecked feature.

## Testing

Please make sure your change compiles and simulates cleanly on at least one
simulator, and -- especially for this VIP -- include a small test or example
that demonstrates the behavior so reviewers can see it actually working.
