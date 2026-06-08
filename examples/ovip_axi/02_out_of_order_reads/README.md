# Out-of-Order Reads — `ovip_axi` example

Shows how a slave can return read responses in an order different from the order the master issued them, using the VIP's reorder window (`rd_out_of_order_depth`) plus per-transaction read-data delays. The master issues four reads with IDs 0..3 in order; the slave responds **3, 2, 1, 0**.

## What it demonstrates

- **`cfg.rd_out_of_order_depth`** on the slave — the reorder window the slave is allowed to look at when picking which response to drive next. `1` would force strict in-order; here we set it to 4 so all four reads are eligible at once.
- **`cfg.rd_scheduling_alg`** — `OVIP_AXI_SCH_ALG_ALWAYS_FIRST` here, but in this example only one transaction is ripe at a time (delays are staggered), so the algorithm choice doesn't change the outcome. Switch to `OVIP_AXI_SCH_ALG_RANDOM` to see random ordering.
- **Per-transaction `data_delay[$]`**, set by overriding `set_read_trans_delays(tr)` in a slave-sequence subclass. Each transaction's delay is computed from its ID so id=3 ripens first and id=0 last.
- **Monitor analysis port subscription** — a tiny `uvm_subscriber` on the master agent's analysis port prints each response in arrival order and checks the data against pre-seeded memory.

## Files

| | |
|---|---|
| `ooo_reads_example.sv` | All-in-one: custom slave sequence, master sequence, response logger, test, and `tb_top`. |
| `Makefile` | Same `SIM=modelsim/vcs/xcelium` knob as the other examples. |

## Running

```sh
make             # default: SIM=modelsim
```

## Expected output

The log shows the issue/arrival contrast directly:

```
[OOO_MST] issuing rd id=0 addr=0x0  ...
[OOO_MST] issuing rd id=1 addr=0x10 ...
[OOO_MST] issuing rd id=2 addr=0x20 ...
[OOO_MST] issuing rd id=3 addr=0x30 ...
[OOO_SLV] id=0 -> data_delay[0]=12
[OOO_SLV] id=1 -> data_delay[0]=8
[OOO_SLV] id=2 -> data_delay[0]=4
[OOO_SLV] id=3 -> data_delay[0]=0
[OOO_LOG] got resp id=3 addr=0x30 data=0xcafe0003 ...
[OOO_LOG] got resp id=2 addr=0x20 data=0xcafe0002 ...
[OOO_LOG] got resp id=1 addr=0x10 data=0xcafe0001 ...
[OOO_LOG] got resp id=0 addr=0x0  data=0xcafe0000 ...
UVM_ERROR : 0
UVM_FATAL : 0
```

`UVM_ERROR : 0` is the success criterion — every read returned the value pre-seeded in memory for its address, regardless of the order it arrived.

## What to read next

- **Eligibility rules and scheduling algorithms** are documented in the VIP README's *"Out-of-Order, Interleaving & Scheduling"* section.
- **Slave-sequence hooks** like `set_read_trans_delays` are described in the *"Slave sequences (zero-time response rule)"* section of the same README.
