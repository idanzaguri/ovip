`ifndef OVIP_AXI_TYPES__SV
`define OVIP_AXI_TYPES__SV

	typedef bit [`OVIP_AXI_MAX_ADDR_WIDTH-1 : 0] ovip_axi_addr_t;
	typedef bit [`OVIP_AXI_MAX_ID_WIDTH  -1 : 0] ovip_axi_id_t;
	typedef bit [`OVIP_AXI_MAX_USER_WIDTH-1 : 0] ovip_axi_user_t;
	typedef bit [`OVIP_AXI_MAX_DATA_WIDTH-1 : 0] ovip_axi_data_t;
	typedef bit [`OVIP_AXI_MAX_STRB_WIDTH-1 : 0] ovip_axi_strb_t;

	typedef enum bit {
		OVIP_AXI_READ_TRANS,
		OVIP_AXI_WRITE_TRANS
	} ovip_axi_transaction_type_t;

	typedef enum bit [1:0] {
		OVIP_AXI_BURST_FIXED = 2'b00,
		OVIP_AXI_BURST_INCR  = 2'b01,
		OVIP_AXI_BURST_WRAP  = 2'b10,
		OVIP_AXI_BURST_RES   = 2'b11
	} ovip_axi_burst_t;

	typedef enum bit [1:0] {
		OVIP_AXI_RESP_OKAY   = 2'b00,
		OVIP_AXI_RESP_EXOKAY = 2'b01,
		OVIP_AXI_RESP_SLVERR = 2'b10,
		OVIP_AXI_RESP_DECERR = 2'b11
	} ovip_axi_resp_t;

	typedef enum bit [2:0] {
		OVIP_PROTOCOL_AXI3,
		OVIP_PROTOCOL_AXI4,
		OVIP_PROTOCOL_AXI4_LITE,
		OVIP_PROTOCOL_ACE,
		OVIP_PROTOCOL_ACE_LITE
	} ovip_axi_protocol_t;

	typedef enum bit {
		OVIP_MASTER_AGENT,
		OVIP_SLAVE_AGENT
	} ovip_agent_dir_t;

	typedef enum bit [1:0] {
		OVIP_AXI_FULL_INTERFACE       = 2'b00,
		OVIP_AXI_READ_ONLY_INTERFACE  = 2'b10,
		OVIP_AXI_WRITE_ONLY_INTERFACE = 2'b01
	} ovip_axi_interface_t;

	// AxSIZE is 3 bits per AXI spec (values 0..7 -> 1B..128B).
	// Widened to 4 bits to allow out-of-spec 256B/512B beats on wide buses.
	typedef enum bit [3:0] {
		OVIP_AXI_SIZE_1B   = 4'b0000,
		OVIP_AXI_SIZE_2B   = 4'b0001,
		OVIP_AXI_SIZE_4B   = 4'b0010,
		OVIP_AXI_SIZE_8B   = 4'b0011,
		OVIP_AXI_SIZE_16B  = 4'b0100,
		OVIP_AXI_SIZE_32B  = 4'b0101,
		OVIP_AXI_SIZE_64B  = 4'b0110,
		OVIP_AXI_SIZE_128B = 4'b0111,
		OVIP_AXI_SIZE_256B = 4'b1000,
		OVIP_AXI_SIZE_512B = 4'b1001
	} ovip_axi_size_t;

	typedef enum int {
		OVIP_AXI_BUS_WIDTH_1B   = 1,
		OVIP_AXI_BUS_WIDTH_2B   = 2,
		OVIP_AXI_BUS_WIDTH_4B   = 4,
		OVIP_AXI_BUS_WIDTH_8B   = 8,
		OVIP_AXI_BUS_WIDTH_16B  = 16,
		OVIP_AXI_BUS_WIDTH_32B  = 32,
		OVIP_AXI_BUS_WIDTH_64B  = 64,
		OVIP_AXI_BUS_WIDTH_128B = 128,
		OVIP_AXI_BUS_WIDTH_256B = 256,
		OVIP_AXI_BUS_WIDTH_512B = 512
	} ovip_axi_bus_width_t;

	typedef enum {
		OVIP_AXI_DATA_START_EV_ADDR_DRIVEN,
		OVIP_AXI_DATA_START_EV_ADDR_SAMPLED,
		OVIP_AXI_DATA_START_EV_BEFORE_ADDR
	} ovip_axi_data_start_event_t;

	typedef enum {
		OVIP_AXI_SCH_ALG_RANDOM,
		OVIP_AXI_SCH_ALG_ROUND_ROBIN,
		OVIP_AXI_SCH_ALG_ROUND_ROBIN_REVERSED,
		OVIP_AXI_SCH_ALG_ALWAYS_LAST,
		OVIP_AXI_SCH_ALG_ALWAYS_FIRST
	} ovip_axi_scheduling_algorithm_t;

	typedef struct {
		int unsigned cycles[$];
		bit loop;
	} ovip_axi_ready_pattern_t;

	// Format for the per-transaction log file (see ovip_axi_trans_logger).
	//   TABLE - fixed-column line built from ovip_axi_trans::log_line()
	//   RAW   - the transaction's convert2string()
	typedef enum bit {
		OVIP_AXI_TRANS_LOG_TABLE,
		OVIP_AXI_TRANS_LOG_RAW
	} ovip_axi_trans_log_format_e;

`endif
