`ifndef OVIP_AXI_STREAM_TYPES__SV
`define OVIP_AXI_STREAM_TYPES__SV

	typedef bit [`OVIP_AXI_STREAM_MAX_DATA_WIDTH-1 : 0] ovip_axi_stream_data_t;
	typedef bit [`OVIP_AXI_STREAM_MAX_STRB_WIDTH-1 : 0] ovip_axi_stream_strb_t;
	typedef bit [`OVIP_AXI_STREAM_MAX_KEEP_WIDTH-1 : 0] ovip_axi_stream_keep_t;
	typedef bit [`OVIP_AXI_STREAM_MAX_ID_WIDTH  -1 : 0] ovip_axi_stream_id_t;
	typedef bit [`OVIP_AXI_STREAM_MAX_DEST_WIDTH-1 : 0] ovip_axi_stream_dest_t;
	typedef bit [`OVIP_AXI_STREAM_MAX_USER_WIDTH-1 : 0] ovip_axi_stream_user_t;

	// Two protocol issues in the spec: AXI4-Stream (issue A) is the baseline;
	// AXI5-Stream (issue B) adds optional wake-up signaling and per-byte odd
	// parity check signals. Selecting the protocol gates which signals and
	// checks the agent is allowed to use.
	typedef enum bit {
		OVIP_AXI_STREAM_PROTOCOL_AXI4S,
		OVIP_AXI_STREAM_PROTOCOL_AXI5S
	} ovip_axi_stream_protocol_t;

	// Spec calls these Transmitter and Receiver. The Transmitter drives every
	// signal except TREADY; the Receiver drives TREADY only (and consumes the
	// rest). A passive agent of either flavor just snoops the wires.
	typedef enum bit {
		OVIP_AXI_STREAM_TRANSMITTER,
		OVIP_AXI_STREAM_RECEIVER
	} ovip_axi_stream_agent_type_t;

	// The four legal combinations of TKEEP/TSTRB plus the reserved one (which
	// the monitor flags as a protocol error -- see ARM IHI 0051B section 2.5.3).
	typedef enum bit [1:0] {
		OVIP_AXI_STREAM_BYTE_DATA     = 2'b11, // TKEEP=1, TSTRB=1
		OVIP_AXI_STREAM_BYTE_POSITION = 2'b10, // TKEEP=1, TSTRB=0
		OVIP_AXI_STREAM_BYTE_NULL     = 2'b00, // TKEEP=0, TSTRB=0
		OVIP_AXI_STREAM_BYTE_RESERVED = 2'b01  // TKEEP=0, TSTRB=1 (illegal)
	} ovip_axi_stream_byte_qualifier_t;

	// Receiver-side TREADY pattern -- same shape as ovip_axi's ready patterns
	// so users see one mental model across the OVIP family. `cycles` lists the
	// number of cycles to hold each level, the level alternates with the index
	// (even = 0, odd = 1), and `loop` decides whether the final element is
	// held or the queue restarts from the beginning.
	typedef struct {
		int unsigned cycles[$];
		bit          loop;
	} ovip_axi_stream_ready_pattern_t;

`endif
