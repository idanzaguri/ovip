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
>   `ovip_ace_testbench` (12 self-checking tests in
>   [`ovip-dev`](https://github.com/idanzaguri/ovip-dev)) runs on **Questa and
>   Verilator** (`ovip_ace_trans` randomization constraints on Verilator locally)
>   covering the snoop channels (CR and CD in every legal order, with
>   and without data, back-to-back snoops, a reset in the middle), RACK / WACK,
>   the AxSNOOP / AxDOMAIN / AWUNIQUE and cache-line checks with legal and
>   illegal transactions, the snoop response checks, X/Z and stability checks,
>   `ovip_ace_trans` randomization constraints, mixed AXI/ACE agents, and
>   ACE-Lite.
> - **It has never been run against a real RTL ACE master or interconnect.** The
>   suite runs VIP against VIP and against small testbench drivers, no waveform
>   has been reviewed against the spec by a human, and parts of the spec are not
>   modeled (see [Spec coverage](#spec-coverage)). Treat every check and every
>   driven signal as **unproven** until you verify it yourself.
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

`ovip_ace_agent` sets no global UVM factory override on `ovip_axi_trans`:

- `ovip_ace_monitor` creates `ovip_ace_trans` items directly, the slave-request
  handoff (`send_rsp_req`) and `ovip_axi_scoreboard` (`defensive_copy_expected`)
  preserve the dynamic type via `clone()`, and `ovip_ace_agent` gives its
  `ovip_axi_trans_logger` an `ovip_ace_trans` header prototype.
- A plain `ovip_axi` agent in the same test keeps plain `ovip_axi_trans` items,
  a user type or instance override on `ovip_axi_trans` is not replaced, and
  multiple ACE agents no longer print `[TPREGR]`.
- Plain `ovip_axi` master sequences run on an ACE agent's sequencer send base
  `ovip_axi_trans` items; `ovip_ace_master_driver` drives zero on the ACE AR/AW
  attributes for them, even when `cfg.drive_reset_values_when_idle` is 0. Use
  `ovip_ace_trans` (or `ovip_ace_base_master_sequence`) to drive ACE
  attributes, or set a scoped instance override on
  `{ace_agent.get_full_name(), ".*"}`.
- Comparing a plain `ovip_axi_trans` and an `ovip_ace_trans`: UVM's default
  `uvm_comparer` has `check_type = 1`, which rejects mismatched dynamic types in
  both directions (`[MISCMP]`). With `check_type = 0` (or after copying the AXI
  item into an `ovip_ace_trans`), order still matters: `axi_tr.compare(ace_tr)`
  compares the AXI fields, while `ace_tr.compare(axi_tr)` returns 0 because the
  RHS has no ACE fields. In an `ovip_axi_scoreboard` between a plain AXI agent
  and an ACE agent, either convert expected items to `ovip_ace_trans` or set
  `uvm_default_comparer.check_type = 0` and connect the plain AXI side to
  `exp_ap` (which calls `exp.compare(act)`).

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
(see the [`ovip_axi` README](../ovip_axi/README.md); on Verilator 5.053, pin
`tr_type` in `with` and pre-size `data_beats` and `strb_beats` to `len + 1`
before randomizing a write). No driver checks an item
before it goes on the wire. The monitor reports what it sees there.

## Check Reports

A check is a rule that the VIP tests and reports as a `UVM_ERROR` or a `UVM_WARNING`. Every check has a message ID of its own, so the message ID names the check.

A bench that breaks a rule on purpose changes the report of that check, for one agent, on the agent's config:

```systemverilog
// The bench drives an illegal AxDOMAIN on purpose: print the error as UVM_INFO.
master_cfg.set_check_severity("ACE_MON/AXDOMAIN", UVM_INFO);
// Or print nothing and count nothing.
slave_cfg.set_check_action("ACE_MON/AXDOMAIN", UVM_NO_ACTION);
```

| `cfg` method | Meaning |
|---|---|
| `set_check_severity(id, severity)` | The agent reports the check `id` with `severity` (`UVM_INFO`, `UVM_WARNING`, `UVM_ERROR` or `UVM_FATAL`) in place of its default severity. |
| `set_check_action(id, action)` | The report of the check `id` gets the UVM action `action`. `UVM_NO_ACTION` prints nothing and counts nothing. |

- Give the ID as the tables below show it, without `cfg.agent_tag`. The agent adds the tag where a component uses it.
- Call the methods before the agent's `connect_phase`, where you set the other `cfg` fields. The agent applies them in `connect_phase` to its monitor, its driver and its sequencer. A sequence reports through the sequencer it runs on, so the checks of a sequence are covered.
- Only the report changes. The check still runs, and what it does beside the report stays.
- The setting is per agent. The other agents report the check as before.
- The methods use the UVM report overrides of the components (`set_report_severity_id_override`, `set_report_severity_id_action`). You can call these on a component yourself, for example to change a report during the run. For the monitor, give the ID with the agent tag (`M/ACE_MON/AXDOMAIN`); drivers, sequences and `ovip_axi_trans_logger` report with the plain ID (`cfg.set_check_*` sets both forms).
- A `UVM_FATAL` is not a check: `set_check_severity()` does not change it (`set_check_action()` also sets the `UVM_FATAL` action for the ID so a check promoted to `UVM_FATAL` keeps its configured action).
- `ovip_ace_monitor` extends `ovip_axi_monitor`, and the ACE drivers extend the AXI drivers. So an ACE agent has the checks of `ovip_axi` too, with their `AXI_MON/...` and `TR_CHK/...` IDs (`AXI_MON/XZ_CHECK` and `AXI_MON/STABILITY_CHECK` cover the ACE additions on AR, AW and R and the AC/CR/CD payloads as well; in ACE-Lite, `RRESP` X/Z is checked on `RRESP[1:0]` only). The [ovip_axi README](../ovip_axi/README.md#check-reports) lists them.

### Monitor checks

All are `UVM_ERROR`.

| Message ID | The monitor reports |
|---|---|
| `ACE_MON/ARSNOOP_RESERVED` | A reserved ARSNOOP value. |
| `ACE_MON/AWSNOOP_RESERVED` | A reserved AWSNOOP value. |
| `ACE_MON/ACSNOOP_RESERVED` | A reserved ACSNOOP value. |
| `ACE_MON/AXDOMAIN` | An AxDOMAIN value that the transaction type does not permit. |
| `ACE_MON/CACHE_LINE_BURST` | A cache line transaction with a FIXED burst. |
| `ACE_MON/CACHE_LINE_SIZE` | A cache line transaction that does not transfer one cache line. |
| `ACE_MON/CACHE_LINE_ADDR` | A cache line transaction with an INCR burst whose start address is not aligned to the cache line size. |
| `ACE_MON/ACE_LITE_TRANS` | A transaction type that an ACE-Lite master must not issue. |
| `ACE_MON/AWUNIQUE` | A WriteEvict with AWUNIQUE low, or a WriteClean with AWUNIQUE high. |
| `ACE_MON/WRITE_EVICT_UNSUPPORTED` | A WriteEvict while `cfg.supports_write_evict` is 0. |
| `ACE_MON/CRRESP_DVM_DATA` | CRRESP.DataTransfer set on a DVM snoop. |
| `ACE_MON/CRRESP_PASS_DIRTY` | CRRESP.PassDirty set with CRRESP.DataTransfer clear. |
| `ACE_MON/CD_BEATS` | Snoop data with a number of CD beats that does not match CRRESP.DataTransfer (one cache line when 1, 0 when 0), or a CD beat with no open snoop. |
| `ACE_MON/INCOMPLETE_SNOOP` | A snoop transaction that did not complete before the test ended. |
| `ACE_MON/AC_STABILITY` | An AC payload signal that changed while ACVALID waited for ACREADY. |
| `ACE_MON/CR_STABILITY` | A CRRESP that changed while CRVALID waited for CRREADY. |
| `ACE_MON/CD_STABILITY` | A CD payload signal that changed while CDVALID waited for CDREADY. |
| `ACE_MON/AC_VALID_DEASSERTED` | An ACVALID that fell before ACREADY. |
| `ACE_MON/CR_VALID_DEASSERTED` | A CRVALID that fell before CRREADY. |
| `ACE_MON/CD_VALID_DEASSERTED` | A CDVALID that fell before CDREADY. |
| `ACE_MON/RACK` | A RACK with no completed read that waits for it. |
| `ACE_MON/WACK` | A WACK with no completed write that waits for it. |
| `ACE_MON/RACK_MISSING` | A completed read that got no RACK before the test ended. |
| `ACE_MON/WACK_MISSING` | A completed write that got no WACK before the test ended. |

### Driver and sequence checks

All are `UVM_ERROR`.

| Message ID | Reported by | Reports |
|---|---|---|
| `ACE_MASTER_DRV/SNOOP` | master driver | A snoop response with CRRESP.DataTransfer set and no snoop data beats. |
| `ACE_SLAVE_DRV/SNOOP` | slave driver | `push_snoop()` on an ACE-Lite agent. The snoop is dropped. |
| `ACE_SEQ/MAKE_WRITE` | `ovip_ace_base_master_sequence` | `make_write()` with no data beats. |

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

Every check has a message ID of its own. [Check Reports](#check-reports) lists the IDs and shows how to change the report of a check for one agent.

What `ovip_ace_monitor` reports, from IHI 0022H Part D:

| Channel | Reported as a `uvm_error` |
|---|---|
| AR | A reserved ARSNOOP encoding (Table D3-7). |
| AR | ReadShared, ReadClean, ReadNotSharedDirty, ReadUnique, CleanUnique, MakeUnique, DVMComplete or DVMMessage in a domain that is not Inner or Outer Shareable, or CleanShared, CleanInvalid or MakeInvalid in the System domain (Table D3-7). |
| AR | A cache line read (the six coherent reads above, CleanShared, CleanInvalid, MakeInvalid) that is not one cache line long, that is a FIXED burst, or that is an INCR burst not aligned to the cache line (Table D3-10). A WRAP burst may start at any AxSIZE-aligned address of the line. |
| AW | A reserved AWSNOOP encoding, and a write type in a domain that Table D3-8 does not give it. |
| AW | AWUNIQUE LOW on a WriteEvict, or HIGH on a WriteClean (Table D3-9). A WriteEvict when `cfg.supports_write_evict` is 0. |
| AR, AW | In ACE-Lite: the six coherent reads above, and a write other than WriteNoSnoop, WriteUnique and WriteLineUnique (Tables D11-1, D11-2). |
| AR, AW, R | X or Z at the handshake and payload changes while VALID waits for READY on ARDOMAIN, ARSNOOP, ARBAR, AWDOMAIN, AWSNOOP, AWBAR, AWUNIQUE (ACE profile) and RRESP\[3:2\] (ACE profile; in ACE-Lite `RRESP` X/Z checks `RRESP[1:0]` only). |
| AC, CR, CD | A reserved ACSNOOP encoding (Table D3-19). DataTransfer on a DVM snoop (D13.2.5). PassDirty without DataTransfer (Table D3-22). Snoop data whose CD beat count does not match DataTransfer (one cache line when 1, 0 when 0), or a CD beat with no open snoop. An incomplete snoop when the test ends. |
| AC, CR, CD | A payload that changes (reported once per transfer) or a VALID that falls before the handshake (D3.6.2, D3.7, D3.8), compared over `cfg.acaddr_width` and `cfg.cddata_width` bits. X or Z on a snoop VALID or READY, on the AC/CR/CD payloads at their handshakes, and on RACK or WACK. |
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
