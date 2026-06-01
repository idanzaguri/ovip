# Contributing to ovip_axi

Thanks for your interest in improving ovip_axi! Contributions are welcome —
whether that's a bug fix, a new feature, or documentation.

## How to contribute

1. Fork the repository and create a branch for your change.
2. Make your change (see conventions below).
3. Open a pull request describing **what** changed and **why**. Reference
   the relevant wanted-features bullet below or a `CHANGELOG.md` known
   limitation if your change addresses one.
4. The maintainer reviews each pull request before it is merged.

By submitting a contribution you agree that it is licensed under the project's
license (Apache-2.0, see [LICENSE](LICENSE)) — inbound contributions are under
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
  does. Avoid leaving `FIXME`/`TODO` markers in merged code — if the work is
  worth tracking, open an issue or add it to the wanted-features list below.
- Don't change existing public behavior unless that *is* the change; if you do,
  call it out clearly in the PR.

## Testing

The VIP targets a standard SystemVerilog + UVM 1.2 simulator. Please make sure
your change compiles and simulates cleanly, and—where it makes sense—include a
small test or example that exercises the new behavior so reviewers can see it
working.

## Where to start — wanted features

A few open items that are well-scoped for a new contributor:

- **UVM transaction recording** *(great first feature)* — add `accept_tr` /
  `begin_tr` / `end_tr` calls in the master driver (and the slave, for symmetry)
  so transactions show up as labeled streams in the waveform database — a big
  debug win. Natural anchor points: `accept_tr` when a request enters the
  driver's accept FIFO, `begin_tr` when the channel starts driving, `end_tr`
  on the response (rdata last beat / bresp). Manual recording typically pairs
  with `+define+UVM_DISABLE_AUTO_ITEM_RECORDING` to avoid duplicate
  auto-recorded items. While you're there, consider replacing the custom
  `addr/data/resp_phase_time` fields in `ovip_axi_trans` with UVM's built-in
  `begin_time`/`end_time` (which the recording API populates).
- **UVM callbacks on the monitor and drivers** — add `uvm_callback` hooks
  (e.g. via `` `uvm_register_cb ``/`` `uvm_do_callbacks ``) at well-defined points
  such as pre/post transaction drive and pre/post sample. This lets users extend
  the VIP — error injection, transaction observation/modification, custom
  coverage — without subclassing or editing the VIP itself.
- **Functional coverage** — the VIP ships no covergroups today. A monitor-side
  coverage subscriber (gated behind a compile-time define like
  `OVIP_AXI_ENABLE_COVERAGE` so it stays opt-in) would let downstream users
  measure protocol coverage without rolling their own. The monitor's analysis
  port sees every committed transaction, so that's the natural home for the
  covergroups. Suggested coverpoints: burst type, size, len, response code,
  narrow vs. wide transfer, address alignment within `burst_size`, the
  out-of-order/interleave depth actually exercised, and bursts close to a 4 KiB
  boundary. Useful crosses: burst type × size, burst type × bus_width,
  resp × tr_type. Keep covergroups off by default — they carry real simulation
  cost.
- **WRAP burst support** — currently a `uvm_fatal`; both the driver/monitor
  implementation and the docs are missing. This work also covers byte-lane
  auto-alignment for WRAP (the address wraps mid-burst, so the lane offset
  per beat is non-trivial). While you're in this area, please also audit the
  one open FIXED corner — `burst_size == bus_width` with
  `auto_byte_lanes_alignment = 1` — which is documented as a known limitation
  in the README's "Byte-Lane Alignment" section.
See [CHANGELOG.md](CHANGELOG.md) "Known limitations" for the full list of
gaps tracked against this release.
