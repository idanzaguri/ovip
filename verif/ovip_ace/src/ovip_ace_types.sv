`ifndef OVIP_ACE_TYPES__SV
`define OVIP_ACE_TYPES__SV

	// Wire-sized typedefs for the ACE-only signals.
	typedef bit [`OVIP_ACE_MAX_ACADDR_WIDTH-1 : 0] ovip_ace_acaddr_t;
	typedef bit [`OVIP_ACE_MAX_CDDATA_WIDTH-1 : 0] ovip_ace_cddata_t;

	// Profile selector. ACE is the full spec; ACE_LITE drops the snoop
	// channels, RACK/WACK, the RRESP[3:2] extension and the AWUNIQUE signal,
	// and restricts the permitted AxSNOOP/AxDOMAIN combinations to the
	// IO-coherent subset (Tables D11-1, D11-2).
	typedef enum bit {
		OVIP_ACE_PROFILE_ACE      = 1'b0,
		OVIP_ACE_PROFILE_ACE_LITE = 1'b1
	} ovip_ace_profile_t;

	// One ovip_ace_trans carries either a master-initiated transaction
	// (AR/AW originated, response on R/B + RACK/WACK) or a snoop request
	// (AC originated by the interconnect, response from the master on CR/CD).
	// The driver and monitor branch on this field.
	typedef enum bit {
		OVIP_ACE_INITIATING = 1'b0,
		OVIP_ACE_SNOOP      = 1'b1
	} ovip_ace_direction_t;

	// AxDOMAIN[1:0] encoding -- spec D3.1.1 Table D3-2.
	typedef enum bit [1:0] {
		OVIP_ACE_DOMAIN_NON_SHAREABLE   = 2'b00,
		OVIP_ACE_DOMAIN_INNER_SHAREABLE = 2'b01,
		OVIP_ACE_DOMAIN_OUTER_SHAREABLE = 2'b10,
		OVIP_ACE_DOMAIN_SYSTEM          = 2'b11
	} ovip_ace_domain_t;

	// AxBAR[1:0] encoding -- spec D3.1.2 Table D3-5. Barriers are deprecated
	// in ACE5 and not supported in this VIP version; declared for completeness
	// and so check_config can flag any non-normal value.
	typedef enum bit [1:0] {
		OVIP_ACE_BAR_NORMAL_RESPECT = 2'b00,
		OVIP_ACE_BAR_MEMORY_BARRIER = 2'b01,
		OVIP_ACE_BAR_NORMAL_IGNORE  = 2'b10,
		OVIP_ACE_BAR_SYNC_BARRIER   = 2'b11
	} ovip_ace_bar_t;

	// ARSNOOP[3:0] encoding for the read address channel -- spec D3.1.3
	// Table D3-7 + Appendix G4 Table G4-1 (ACE column). All unused encodings
	// are Reserved.
	typedef enum bit [3:0] {
		// 0b0000 is overloaded: ReadNoSnoop when AxDOMAIN is NSH/SYS;
		// ReadOnce when AxDOMAIN is ISH/OSH. Same field, different name.
		OVIP_ACE_ARSNOOP_READ_NO_SNOOP_OR_READ_ONCE = 4'b0000,
		OVIP_ACE_ARSNOOP_READ_SHARED                = 4'b0001,
		OVIP_ACE_ARSNOOP_READ_CLEAN                 = 4'b0010,
		OVIP_ACE_ARSNOOP_READ_NOT_SHARED_DIRTY      = 4'b0011,
		OVIP_ACE_ARSNOOP_READ_UNIQUE                = 4'b0111,
		OVIP_ACE_ARSNOOP_CLEAN_SHARED               = 4'b1000,
		OVIP_ACE_ARSNOOP_CLEAN_INVALID              = 4'b1001,
		OVIP_ACE_ARSNOOP_CLEAN_UNIQUE               = 4'b1011,
		OVIP_ACE_ARSNOOP_MAKE_UNIQUE                = 4'b1100,
		OVIP_ACE_ARSNOOP_MAKE_INVALID               = 4'b1101,
		OVIP_ACE_ARSNOOP_DVM_COMPLETE               = 4'b1110,
		OVIP_ACE_ARSNOOP_DVM_MESSAGE                = 4'b1111
	} ovip_ace_arsnoop_t;

	// AWSNOOP[2:0] encoding for the write address channel -- spec D3.1.3
	// Table D3-8 + Appendix G4 Table G4-2 (ACE column).
	typedef enum bit [2:0] {
		// 0b000 is overloaded: WriteNoSnoop when AxDOMAIN is NSH/SYS;
		// WriteUnique (partial line) when AxDOMAIN is ISH/OSH.
		OVIP_ACE_AWSNOOP_WRITE_NO_SNOOP_OR_WRITE_UNIQUE = 3'b000,
		OVIP_ACE_AWSNOOP_WRITE_LINE_UNIQUE              = 3'b001,
		OVIP_ACE_AWSNOOP_WRITE_CLEAN                    = 3'b010,
		OVIP_ACE_AWSNOOP_WRITE_BACK                     = 3'b011,
		OVIP_ACE_AWSNOOP_EVICT                          = 3'b100,
		OVIP_ACE_AWSNOOP_WRITE_EVICT                    = 3'b101
	} ovip_ace_awsnoop_t;

	// ACSNOOP[3:0] encoding for the snoop address channel -- spec D3.6.2
	// Table D3-19. Strict subset of ARSNOOP (D5.1.1).
	typedef enum bit [3:0] {
		OVIP_ACE_ACSNOOP_READ_ONCE             = 4'b0000,
		OVIP_ACE_ACSNOOP_READ_SHARED           = 4'b0001,
		OVIP_ACE_ACSNOOP_READ_CLEAN            = 4'b0010,
		OVIP_ACE_ACSNOOP_READ_NOT_SHARED_DIRTY = 4'b0011,
		OVIP_ACE_ACSNOOP_READ_UNIQUE           = 4'b0111,
		OVIP_ACE_ACSNOOP_CLEAN_SHARED          = 4'b1000,
		OVIP_ACE_ACSNOOP_CLEAN_INVALID         = 4'b1001,
		OVIP_ACE_ACSNOOP_MAKE_INVALID          = 4'b1101,
		OVIP_ACE_ACSNOOP_DVM_COMPLETE          = 4'b1110,
		OVIP_ACE_ACSNOOP_DVM_MESSAGE           = 4'b1111
	} ovip_ace_acsnoop_t;

	// Five-state cache model -- spec D1.2.3 Table D1-1.
	typedef enum bit [2:0] {
		OVIP_ACE_CACHE_STATE_INVALID      = 3'b000, // I
		OVIP_ACE_CACHE_STATE_UNIQUE_CLEAN = 3'b001, // UC
		OVIP_ACE_CACHE_STATE_UNIQUE_DIRTY = 3'b010, // UD
		OVIP_ACE_CACHE_STATE_SHARED_CLEAN = 3'b011, // SC
		OVIP_ACE_CACHE_STATE_SHARED_DIRTY = 3'b100  // SD
	} ovip_ace_cache_state_t;

	// Master-side cache tracking mode. STATELESS is the default -- sequences
	// drive whatever they want, no self-checking against a cache model.
	typedef enum bit {
		OVIP_ACE_CACHE_MODEL_STATELESS = 1'b0,
		OVIP_ACE_CACHE_MODEL_TRACK     = 1'b1
	} ovip_ace_cache_model_t;

	// CRRESP[4:0] decoded bits -- spec D3.7 Table D3-21.
	typedef struct packed {
		bit was_unique;    // [4]
		bit is_shared;     // [3]
		bit pass_dirty;    // [2]
		bit error;         // [1]
		bit data_transfer; // [0]
	} ovip_ace_crresp_t;

`endif
