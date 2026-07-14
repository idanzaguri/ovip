`ifndef OVIP_ACE_DEFINES__SV
`define OVIP_ACE_DEFINES__SV

`ifdef OVIP_ACE_INCLUDE_USER_DEFINES
	`include "ovip_ace_user_defines.sv"
`endif

// Physical wire widths for the ACE additions. The agent's runtime cfg fields
// pick how many of these bits are actually active per agent; values above the
// limit are rejected by check_config. Bumping a limit costs sim memory but
// unlocks larger runtime widths.

// Snoop address bus -- typically same as AXI addr (defaults to MAX_ADDR_WIDTH
// from ovip_axi). Declared independently so an agent that wants a narrower AC
// channel doesn't have to widen its AXI addr at the same time.
`ifndef OVIP_ACE_MAX_ACADDR_WIDTH
	`define OVIP_ACE_MAX_ACADDR_WIDTH `OVIP_AXI_MAX_ADDR_WIDTH
`endif

// Snoop data bus -- spec D3.8 permits this to be narrower than the AXI read
// data bus when snoop hit-rate is low and latency is not critical. Defaulting
// to the AXI bus width keeps it simple.
`ifndef OVIP_ACE_MAX_CDDATA_WIDTH
	`define OVIP_ACE_MAX_CDDATA_WIDTH `OVIP_AXI_MAX_DATA_WIDTH
`endif

`endif
