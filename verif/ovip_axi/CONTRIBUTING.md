# Contributing to ovip_axi

Thanks for your interest in improving ovip_axi! Contributions are welcome --
whether that's a bug fix, a new feature, or documentation.

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

By submitting a contribution you agree that it is licensed under the project's
license (Apache-2.0, see [LICENSE](LICENSE)) -- inbound contributions are under
the same terms as the project (Apache-2.0, Section 5).

## Coding conventions

The VIP is SystemVerilog targeting **UVM 1.2**. To keep the code consistent:

- **Naming:** classes and types are prefixed `ovip_axi_`; compile-time defines,
  enum values, and other macros use the `OVIP_AXI_` namespace (width limits are
  `OVIP_AXI_MAX_*`). Keep new public symbols inside that namespace.
- **Indentation:** tabs (match the surrounding file).
- **Include guards:** wrap every `.sv` include file in
  `` `ifndef <FILE>__SV `` / `` `define `` / `` `endif ``.
- **Comments:** explain *why* something non-obvious is done, not *what* the code
  does. Avoid leaving `FIXME`/`TODO` markers in merged code -- if the work is
  worth tracking, open an issue or add it to the wanted-features list below.
- Don't change existing public behavior unless that *is* the change; if you do,
  call it out clearly in the PR.

## Testing

The VIP targets a standard SystemVerilog + UVM 1.2 simulator. Please make sure
your change compiles and simulates cleanly, and -- where it makes sense -- include a
small test or example that exercises the new behavior so reviewers can see it
working.

## Where to start -- wanted features

A few open items that are well-scoped for a new contributor:

- **UVM transaction recording** *(great first feature)* -- add `accept_tr` /
  `begin_tr` / `end_tr` calls in the master driver (and the slave, for symmetry)
  so transactions show up as labeled streams in the waveform database -- a big
  debug win. Natural anchor points: `accept_tr` when a request enters the
  driver's accept FIFO, `begin_tr` when the channel starts driving, `end_tr`
  on the response (rdata last beat / bresp). Manual recording typically pairs
  with `+define+UVM_DISABLE_AUTO_ITEM_RECORDING` to avoid duplicate
  auto-recorded items. While you're there, consider replacing the custom
  `addr/data/resp_phase_time` fields in `ovip_axi_trans` with UVM's built-in
  `begin_time`/`end_time` (which the recording API populates).
- **UVM callbacks on the monitor and drivers** -- add `uvm_callback` hooks
  (e.g. via `` `uvm_register_cb ``/`` `uvm_do_callbacks ``) at well-defined points
  such as pre/post transaction drive and pre/post sample. This lets users extend
  the VIP -- error injection, transaction observation/modification, custom
  coverage -- without subclassing or editing the VIP itself.
- **Functional coverage** -- the VIP ships no covergroups today. A monitor-side
  coverage subscriber (gated behind a compile-time define like
  `OVIP_AXI_ENABLE_COVERAGE` so it stays opt-in) would let downstream users
  measure protocol coverage without rolling their own. The monitor's analysis
  port sees every committed transaction, so that's the natural home for the
  covergroups. Suggested coverpoints: burst type, size, len, response code,
  narrow vs. wide transfer, address alignment within `burst_size`, the
  out-of-order/interleave depth actually exercised, and bursts close to a 4 KiB
  boundary. Useful crosses: burst type × size, burst type × bus_width,
  resp × tr_type. Keep covergroups off by default -- they carry real simulation
  cost.
- **WRAP burst support** -- currently a `uvm_fatal`; both the driver/monitor
  implementation and the docs are missing. This work also covers byte-lane
  auto-alignment for WRAP (the address wraps mid-burst, so the lane offset
  per beat is non-trivial). While you're in this area, please also audit the
  one open FIXED corner -- `burst_size == bus_width` with
  `auto_byte_lanes_alignment = 1` -- which is documented as a known limitation
  in the README's "Byte-Lane Alignment" section.
- **Random values where AXI leaves them undefined, and a slave that waits for
  WVALID**: four switches, all off by default. OVIP drives zero on the lanes
  AXI leaves undefined, and zero or the last value on a channel while its VALID
  is low. Its slave raises AWREADY without looking at WVALID. A NoC that ORs or
  samples those values then passes. logion_formal found four such bugs that
  logion_tb's whole-NoC bench missed this way (idanzaguri/logion_formal #1, #3,
  #5 and #6). The four switches:
  1. **Master: random WDATA bytes where WSTRB is low**: done, as
     `cfg.randomize_unstrobed_wdata` (the README's "Bytes under a low
     strobe"). It exposes a write packer that ORs whole WDATA words into a
     flit (logion_formal FV-1).
  2. **Slave: random RDATA bytes on the lanes a narrow beat does not use**:
     done, as `cfg.randomize_unused_rdata` (the README's "Lanes a read beat
     does not use"). It exposes a read packer that ORs whole RDATA words
     (FV-6).
  3. **Random payload while VALID is low**: done, as
     `cfg.randomize_idle_payload` (the README's "Payload while VALID is
     low"). It exposes an interface that takes a field before its handshake,
     such as BRESP while BVALID is low (FV-5).
  4. **Slave: AWREADY only once WVALID has shown**: done, as
     `cfg.awready_waits_for_wvalid` (the README's "A slave that waits for
     WVALID"). It exposes a master that waits for AWREADY before WVALID:
     FV-3's slave NIs, and OVIP's own `DATA_START_EV_ADDR_SAMPLED`. Such a
     master hangs, so a watchdog or the transaction timeout reports it.
See [CHANGELOG.md](CHANGELOG.md) "Known limitations" for the full list of
gaps tracked against this release.
