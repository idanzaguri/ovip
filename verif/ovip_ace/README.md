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
>   **runs to `UVM_ERROR : 0`** and checks its own results: AR/AW/R/B traffic
>   with the ACE coherency fields (AxDOMAIN / AxSNOOP, RRESP\[3:2\]), the read
>   data against the written data, a RACK or WACK for every transaction, and
>   one injected snoop, which both monitors report (`ACE_MON/SNOOP`).
> - An audit found errors in the snoop path, in RACK / WACK and in several
>   monitor checks. They are fixed (see the [CHANGELOG](CHANGELOG.md)), and
>   each fix was checked with a **directed test on Questa and on Verilator**
>   (the constraints of `ovip_ace_trans` on Verilator only). The tests cover
>   the snoop channels (CR and CD in every legal order, with and without data,
>   several snoops, a reset in the middle), RACK / WACK, the AxSNOOP / AxDOMAIN
>   / AWUNIQUE and cache-line checks with legal and illegal transactions, the
>   snoop response checks, and ACE-Lite. **These tests are not in the
>   repository.** They ran VIP against VIP and against small drivers written
>   for one test, never against a real ACE master or interconnect.
> - **No regression exists for this VIP.** No waveform has been reviewed against
>   the spec, and parts of the spec are not modeled (see
>   [Spec coverage](#spec-coverage)). Treat every check and every driven signal
>   as **unproven** until you verify it yourself.
>
> **Do not use this in a sign-off environment as-is.** It is published as a
> starting point for the community to verify and harden. If you want to help,
> see [CONTRIBUTING.md](CONTRIBUTING.md) -- **verifying the VIP is the number-one
> wanted contribution.**

---

Release history is in [CHANGELOG.md](CHANGELOG.md).

---

## At a glance

`ovip_ace` reuses the entire AXI request/response engine and layers the ACE
additions on top through inheritance and a parameterized virtual-interface type:

| Piece | How it extends AXI |
|---|---|
| `ovip_ace_agent_if` | AXI signals (identical names) + ACE additions: AR/AW DOMAIN/SNOOP/BAR, AWUNIQUE, widened RRESP\[3:0\], AC/CR/CD snoop channels, RACK/WACK. |
| `ovip_ace_trans` | `extends ovip_axi_trans`; adds direction, domain, snoop, bar, awunique, IsShared/PassDirty, and the snoop-request fields. `compare()` and `diff()` cover them: the AR/AW/R additions for a master-initiated item, the AC/CR/CD fields alone for a snoop. |
| `ovip_ace_agent_config` | `extends ovip_axi_agent_config`; adds `profile`, `cache_line_size`, snoop-channel widths, capability advertisements. |
| `ovip_ace_master_driver` | `extends ovip_axi_master_driver`; drives the AR/AW additions, samples RRESP\[3:2\], responds to snoops (AC->CR/CD), pulses RACK/WACK. |
| `ovip_ace_slave_driver` | `extends ovip_axi_slave_driver`; drives RRESP\[3:2\], injects snoop requests via `push_snoop()` (ACE profile only; a reset drops the snoops that still wait). |
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

### ACE and plain AXI agents in one test

`ovip_ace_agent::build_phase` sets a UVM factory type override from
`ovip_axi_trans` to `ovip_ace_trans`. The VIP needs it: the `ovip_axi` code
that it inherits creates the items it works on (the copy of each request
that the monitor hands to the slave sequence, the copies of the scoreboard),
and each must be an `ovip_ace_trans` to keep the ACE fields.

The override is global. It is not limited to the ACE agent:

- A plain `ovip_axi` agent in the same test gets `ovip_ace_trans` items too,
  from its monitor and in its slave sequence. Their ACE fields stay at the
  default values and the AXI fields work as usual.
- A type override of `ovip_axi_trans` that the test set before the agent was
  built is replaced.
- Every ACE agent after the first prints the UVM note `[TPREGR]` when it sets
  the override again.

## Profiles

- **`OVIP_ACE_PROFILE_ACE`** -- the full spec: snoop channels, RACK/WACK,
  RRESP\[3:2\], AWUNIQUE, the full AxSNOOP/AxDOMAIN envelope.
- **`OVIP_ACE_PROFILE_ACE_LITE`** -- IO-coherent subset: no snoop channels, no
  RACK/WACK, RRESP\[3:2\] tied off; permitted transactions restricted to the
  Table D11-1 / D11-2 subset. The monitor reports a coherent read or a
  memory-update write that the subset does not have. It does not report a
  DVM transaction.

## Randomizing an `ovip_ace_trans`

The constraints of `ovip_ace_trans` keep a randomized item inside the tables
of IHI 0022H that do not depend on the agent:

| Constraint | What it gives |
|---|---|
| `c_direction_default` | `direction` is `OVIP_ACE_INITIATING` (a soft constraint). Write `direction == OVIP_ACE_SNOOP` in the `with` block for a snoop item. |
| `c_snoop_msb`, `c_snoop_legal` | `snoop` is an ARSNOOP encoding of Table D3-7 for a read, and an AWSNOOP encoding of Table D3-8 for a write. |
| `c_domain_consistent_with_snoop` | `domain` is one that Table D3-7 or D3-8 allows for that transaction type. |
| `c_awunique_default` | Table D3-9: `awunique` is 1 for WriteEvict and 0 for WriteClean. For every other item it is 0 (a soft constraint): write `awunique == 1` to assert it. |
| `c_no_barriers` | `bar` is `OVIP_ACE_BAR_NORMAL_RESPECT`. |

The last four rows are on the AR/AW fields and hold whatever the direction
is: a `with` block that asks for a combination outside the tables makes
`randomize()` fail. A snoop item does not use these fields.

The item does not know the agent's config, so the caller constrains the rest:
the cache line rules of Table D3-10 (address, `len`, `size`, `burst`), the
ACE-Lite subset of Tables D11-1 and D11-2, and the fields of `ovip_axi_trans`
(see the [`ovip_axi` README](../ovip_axi/README.md)). No driver checks an item
before it goes on the wire. The monitor reports what it sees there.

## Compile-Time Defines

| Define | Default | Meaning |
|---|---|---|
| `OVIP_ACE_MAX_ACADDR_WIDTH` | `OVIP_AXI_MAX_ADDR_WIDTH` | Snoop address bus wire width. |
| `OVIP_ACE_MAX_CDDATA_WIDTH` | `OVIP_AXI_MAX_DATA_WIDTH` | Snoop data bus wire width. |
| `OVIP_INPUT_SKEW` | `1step` | Input skew of the interface's clocking blocks (`monitor_cb`, `master_cb`, `slave_cb`): the value from before the clock edge. Shared by every OVIP VIP (`ovip_common/ovip_common_defines.sv`). |
| `OVIP_OUTPUT_SKEW` | `0` | Output skew of the same clocking blocks. |

The AXI-side width defines (`OVIP_AXI_MAX_DATA_WIDTH`, etc.) apply as usual.

## Example

[`examples/ovip_ace/01_coherent_loopback/`](../../examples/ovip_ace/01_coherent_loopback/)
brings up a master + interconnect/slave ACE agent, runs coherent writes and
reads, and injects one snoop. It checks that each read returns the written
data and that the master's monitor reports the snoop. `make` to run it. (See
the banner above for what is and is not verified.)

## Spec coverage

What `ovip_ace_monitor` reports, from IHI 0022H Part D:

| Channel | Reported as a `uvm_error` |
|---|---|
| AR | A reserved ARSNOOP encoding (Table D3-7). |
| AR | ReadShared, ReadClean, ReadNotSharedDirty, ReadUnique, CleanUnique or MakeUnique in a domain that is not Inner or Outer Shareable (Table D3-7). |
| AR | A cache line read (the six above, CleanShared, CleanInvalid, MakeInvalid) that is not one cache line long, that is a FIXED burst, or that is an INCR burst not aligned to the cache line (Table D3-10). A WRAP burst may start at any AxSIZE-aligned address of the line. |
| AW | A reserved AWSNOOP encoding, and a write type in a domain that Table D3-8 does not give it. |
| AW | AWUNIQUE LOW on a WriteEvict, or HIGH on a WriteClean (Table D3-9). A WriteEvict when `cfg.supports_write_evict` is 0. |
| AR, AW | In ACE-Lite: the six coherent reads above, and a write other than WriteNoSnoop, WriteUnique and WriteLineUnique (Tables D11-1, D11-2). |
| AC, CR, CD | A reserved ACSNOOP encoding (Table D3-19). DataTransfer on a DVM snoop (D13.2.5). PassDirty without DataTransfer (Table D3-22). A CD burst that is not one cache line long. |
| AC, CR, CD | A payload that changes or a VALID that falls before the handshake (D3.6.2, D3.7, D3.8), compared over `cfg.acaddr_width` and `cfg.cddata_width` bits. X or Z on a snoop VALID or READY and on RACK or WACK. |
| RACK, WACK | An acknowledge with no completed transaction to acknowledge. A completed read with no RACK, or write with no WACK, when the test ends (D3.3, D3.5). |

The last three rows apply in the ACE profile only. The checks of
`ovip_axi_monitor` run as well. The directed tests named in the banner
exercised every row with legal and illegal stimulus. Of the stability and
X / Z row they covered a change of each payload, a falling ACVALID and X on
RACK.

Limits of what is there:

- The snoop monitor and the slave driver follow one snoop at a time. An AC
  handshake before the previous snoop has its CR handshake and its last CD
  beat is not seen.
- RACK and WACK are counted. They carry no ID, so the monitor cannot tell
  which transaction an acknowledge belongs to, and it does not check the
  D6.2 order between a response, its acknowledge and a snoop to the same
  cache line.
- Nothing else of Part D is checked or modeled: no cache state model, no
  snoop predictor, no DVM or barrier semantics, no AxCACHE, no single-transfer
  responses, no Evict without data. [CONTRIBUTING.md](CONTRIBUTING.md) lists
  the known gaps.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
