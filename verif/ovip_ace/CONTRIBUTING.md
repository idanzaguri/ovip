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

By submitting a contribution you agree that it is licensed under the project's
license (Apache-2.0, see [LICENSE](LICENSE)) -- inbound contributions are under
the same terms as the project (Apache-2.0, Section 5).

## Where to start -- wanted features

### :one: Verify the VIP *(by far the most wanted contribution)*

The code compiles and the coherent-loopback example runs to `UVM_ERROR : 0` for
basic AR/AW/R traffic, but **almost nothing else has been confirmed in
simulation.** Bringing this VIP to a trustworthy state is the top priority.

**How to run what exists today:**

```sh
cd examples/ovip_ace/01_coherent_loopback
make SIM=modelsim          # or SIM=vcs / SIM=xcelium
# Watch the UVM Report Summary. Today: UVM_ERROR : 0 for the read/write path.
```

Compile the VIP standalone (any simulator) with:

```sh
export OVIP_ROOT=/path/to/ovip
vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_ace/ovip_ace.f    # Questa/Modelsim
```

**Concrete verification tasks, roughly in priority order:**

- **Make the snoop path actually work.** In the shipped example the injected
  snoop (`ovip_ace_slave_driver::push_snoop`) does **not** produce an observable
  snoop transaction on the master's `mon.snoop_analysis_port`. Debug the
  AC -> CR (-> CD) handshake between `ovip_ace_slave_driver::snoop_request_driver`
  and `ovip_ace_master_driver::snoop_phase_driver`, add a self-checking example,
  and confirm the monitor's `snoop_channel_monitor` reconstructs it.
- **Confirm RACK / WACK sequencing.** Verify `rack_wack_driver` (master) drives
  single-cycle pulses at the right time and that the monitor's
  `rack_wack_sequencing_monitor` (D6.2) fires correctly on good and bad stimulus.
- **Validate every protocol check with directed pass/fail stimulus.** Each check
  in `ovip_ace_monitor` (reserved encodings, D3.1.1 domain/snoop consistency,
  D3.1.6 cache-line addressing, D3-9 AWUNIQUE, D11 ACE-Lite subset, D3.7/D5.4
  snoop-response consistency) needs a test that (a) passes on legal traffic and
  (b) actually errors on the illegal case it claims to catch.
- **Exercise ACE-Lite.** Bring up an `OVIP_ACE_PROFILE_ACE_LITE` agent and
  confirm the snoop channels / RACK / WACK stay idle and the D11 restrictions fire.
- **Build a regression** for ovip_ace under the standard runners so this VIP is
  covered the way ovip_axi is.

### Other wanted features

- **Snoop-response scoreboard / cache predictor** -- model the master's cache
  state and check its CRRESP against the legal end-state tables (D4 + D5). The
  `ovip_ace_scoreboard` snoop export is the hook; the predictor is the work.
- **Cache-state tracking (`OVIP_ACE_CACHE_MODEL_TRACK`)** -- the config knob and
  monitor cross-check hooks exist; the cache model itself does not.
- **DVM transactions** -- encodings are decoded but DVM message semantics are
  not modelled.
- **Barriers** -- deprecated in ACE5 and currently rejected by config/trans;
  add support if a downstream user needs it.

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
