`ifndef OVIP_GLOBAL_PKG__SV
`define OVIP_GLOBAL_PKG__SV

package ovip_global_pkg;
	timeunit 1ns; timeprecision 1ps;
	import uvm_pkg::*;
	`include "uvm_macros.svh"
	typedef byte ovip_bytestream[$];
	typedef bit ovip_bitstream[$];
endpackage : ovip_global_pkg

`endif
