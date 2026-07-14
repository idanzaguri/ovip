# OVIP ACE

UVM verification IP for **AMBA ACE** and **ACE-Lite** (ARM IHI 0022H),
built as an extension of [`ovip_axi`](../ovip_axi/). One agent covers both
profiles via a runtime `cfg.profile` switch.

---

> # :rotating_light: READ THIS FIRST :rotating_light:
>
> ## **THIS VIP WAS WRITTEN ENTIRELY BY AN AI (Claude, by Anthropic).**
> ## **IT HAS *NOT* BEEN FUNCTIONALLY VERIFIED BY A HUMAN.**
>
> **What that means, concretely:**
>
> - The code **compiles cleanly** on Questa and the coherent-loopback example
>   **runs to `UVM_ERROR : 0`** for basic AR/AW/R traffic with the ACE coherency
>   fields (AxDOMAIN / AxSNOOP, RRESP\[3:2\]). That is the *only* thing that has
>   been observed to work.
> - **The snoop channels (AC / CR / CD), RACK / WACK sequencing, the cache-line
>   and ACE-Lite protocol checks, and the scoreboard have NOT been confirmed in
>   simulation.** In the shipped example the injected snoop does **not** currently
>   complete an observable transaction -- that path is unverified and may be buggy.
> - No regression exists for this VIP. No waveform has been reviewed against the
>   spec. Treat every check and every driven signal as **unproven** until you
>   verify it yourself.
>
> **Do not use this in a sign-off environment as-is.** It is published as a
> starting point for the community to verify and harden. If you want to help,
> see [CONTRIBUTING.md](CONTRIBUTING.md) -- **verifying the VIP is the number-one
> wanted contribution.**

---

## At a glance

`ovip_ace` reuses the entire AXI request/response engine and layers the ACE
additions on top through inheritance and a parameterized virtual-interface type:

| Piece | How it extends AXI |
|---|---|
| `ovip_ace_agent_if` | AXI signals (identical names) + ACE additions: AR/AW DOMAIN/SNOOP/BAR, AWUNIQUE, widened RRESP\[3:0\], AC/CR/CD snoop channels, RACK/WACK. |
| `ovip_ace_trans` | `extends ovip_axi_trans`; adds direction, domain, snoop, bar, awunique, IsShared/PassDirty, and the snoop-request fields. |
| `ovip_ace_agent_config` | `extends ovip_axi_agent_config`; adds `profile`, `cache_line_size`, snoop-channel widths, capability advertisements. |
| `ovip_ace_master_driver` | `extends ovip_axi_master_driver`; drives the AR/AW additions, samples RRESP\[3:2\], responds to snoops (AC->CR/CD), pulses RACK/WACK. |
| `ovip_ace_slave_driver` | `extends ovip_axi_slave_driver`; drives RRESP\[3:2\], injects snoop requests via `push_snoop()`. |
| `ovip_ace_monitor` | `extends ovip_axi_monitor`; reconstructs full ACE transactions, monitors the snoop channels, runs the D3/D5/D11 protocol checks. |
| `ovip_ace_scoreboard` | `extends ovip_axi_scoreboard`; adds a snoop analysis export. |

## Integrating into your environment

```sh
# 1) Tell the filelist where this repo is.
export OVIP_ROOT=/path/to/ovip

# 2) Add ovip_ace.f to your compile step. It pulls in ovip_axi.f transitively.
#    vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_ace/ovip_ace.f
```

See [`ovip_ace.f`](ovip_ace.f) for the VCS / Xcelium invocations.

## Profiles

- **`OVIP_ACE_PROFILE_ACE`** -- the full spec: snoop channels, RACK/WACK,
  RRESP\[3:2\], AWUNIQUE, the full AxSNOOP/AxDOMAIN envelope.
- **`OVIP_ACE_PROFILE_ACE_LITE`** -- IO-coherent subset: no snoop channels, no
  RACK/WACK, RRESP\[3:2\] tied off; permitted transactions restricted to the
  Table D11-1 / D11-2 subset (enforced by the monitor).

## Compile-Time Defines

| Define | Default | Meaning |
|---|---|---|
| `OVIP_ACE_MAX_ACADDR_WIDTH` | `OVIP_AXI_MAX_ADDR_WIDTH` | Snoop address bus wire width. |
| `OVIP_ACE_MAX_CDDATA_WIDTH` | `OVIP_AXI_MAX_DATA_WIDTH` | Snoop data bus wire width. |

The AXI-side width defines (`OVIP_AXI_MAX_DATA_WIDTH`, etc.) apply as usual.

## Example

[`examples/ovip_ace/01_coherent_loopback/`](../../examples/ovip_ace/01_coherent_loopback/)
brings up a master + interconnect/slave ACE agent, runs coherent writes and
reads, and attempts a snoop injection. `make` to run it. (See the banner above
for what is and is not verified.)

## Spec coverage (as written, unverified)

The monitor contains inline checks derived from IHI 0022H: reserved
AxSNOOP/ACSNOOP encodings, domain/snoop consistency (D3.1.1), cache-line-size
addressing (D3.1.6), AWUNIQUE/WriteEvict rules (D3-9 / D2.1.2), the ACE-Lite
permitted subset (D11), snoop-response consistency (D3.7 / D5.4), and RACK/WACK
sequencing (D6.2). **None of these checks has been validated against a known-good
or known-bad stimulus.**

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
