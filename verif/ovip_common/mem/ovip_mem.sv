`ifndef OVIP_MEM__SV
`define OVIP_MEM__SV

class ovip_mem extends uvm_component;
	parameter WORD_SIZE = 4; // must be power of 2
	parameter MAX_ADDR_WIDTH = 64;

	typedef bit [WORD_SIZE*8-1:0] word_t;
	typedef bit [WORD_SIZE-1:0] byte_enable_t;
	typedef bit [MAX_ADDR_WIDTH-1:0] addr_t;

	// Associative array for memory
	protected word_t mem [addr_t];

	// Fill value written to a line on its first access. When randomize_uninitialized
	// is set, each new line is filled with random bytes instead of init_pattern.
	word_t init_pattern = 'hdeadbeef;
	bit randomize_uninitialized = 0;

	// The valid ranges. With none set every address is valid, as always.
	// Once any is set, an access that touches a byte outside all of them
	// reports MEM/OUT_OF_RANGE and does nothing: a slave's memory is then
	// bounded to the ranges the slave owns, and a transaction delivered to
	// the wrong place is named the moment it arrives. ovip_mem_space sets
	// them from its map.
	typedef struct { addr_t base; addr_t size; } range_t;
	protected range_t valid_ranges[$];

	`uvm_component_utils(ovip_mem)

	function new(string name = "ovip_mem", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function int get_word_size();
		return WORD_SIZE;
	endfunction : get_word_size

	// Function to check if address is word-aligned
	extern virtual function bit is_word_aligned(addr_t addr);

	// Function to align address to WORD_SIZE
	extern virtual function addr_t align_address_to_word_size(addr_t addr);

	// Function to initialize memory line if not already done
	extern virtual function void init_mem_line_if_not_exists(addr_t addr);

	// Function to prepare for memory access
	extern virtual function void prepare_for_access(addr_t addr);

	// Write function with byte enable
	extern virtual function void write(addr_t addr, word_t data, byte_enable_t byte_enable = -1);

	// Same as write() but skips the alignment check. Hot path for
	// write_bytestream where the address is provably word-aligned.
	extern local function void write_aligned(addr_t addr, word_t data, byte_enable_t byte_enable);

	// Read function
	extern virtual function word_t read(addr_t addr);

	// Function to read a bytestream
	extern virtual function ovip_bytestream read_bytestream(addr_t addr, int size = WORD_SIZE);

	// Function to write a bytestream
	// when byte_enable is {}, assuming that all 1's
	static ovip_bitstream empty_bitstream = '{};
	extern virtual function void write_bytestream(addr_t addr, ref ovip_bytestream data, ref ovip_bitstream byte_enable = empty_bitstream);

	// Basic memory dump (debug).
	extern virtual function void print();

	// The valid ranges: add one, count them, and test a range of bytes
	// against them (1 when none is set, or every byte of [addr, addr + size)
	// lies in some range).
	extern virtual function void add_valid_range(addr_t base, addr_t size);
	extern virtual function int  num_valid_ranges();
	extern virtual function bit  is_valid(addr_t addr, addr_t size = 1);
	extern protected virtual function bit refuse_if_invalid(addr_t addr, addr_t size, string what);

	// The lines touched so far: how many, whether one exists, and all of
	// them in ascending order. A line is WORD_SIZE bytes at an aligned
	// address, created on its first access.
	extern virtual function int num_lines();
	extern virtual function bit line_exists(addr_t addr);
	extern virtual function void get_lines(ref addr_t lines[$]);

	// Compare the lines of two memories. A line whose word differs, or that
	// one side touched and the other did not, is one mismatch. Returns the
	// count; reports the first max_report of them as uvm_error, tagged.
	extern virtual function int compare(ovip_mem other, string tag = "", int max_report = 16);

endclass : ovip_mem


function bit ovip_mem::is_word_aligned(addr_t addr);
	return addr % WORD_SIZE == 0;
endfunction : is_word_aligned


function ovip_mem::addr_t ovip_mem::align_address_to_word_size(addr_t addr);
	return addr & ~(WORD_SIZE - 1);
endfunction : align_address_to_word_size


function void ovip_mem::init_mem_line_if_not_exists(addr_t addr);
	if (mem.exists(addr)) return;
	if (randomize_uninitialized)
	begin
		word_t w;
		for (int i = 0; i < WORD_SIZE; i++) w[i*8+:8] = $urandom;
		mem[addr] = w;
	end
	else
		mem[addr] = init_pattern;
endfunction : init_mem_line_if_not_exists


function void ovip_mem::prepare_for_access(addr_t addr);
	if (!is_word_aligned(addr))
		`uvm_fatal("MEM_REGION/BAD_ACCESS", $sformatf("Unaligned access at address %0d", addr))
	init_mem_line_if_not_exists(addr);
endfunction : prepare_for_access


function void ovip_mem::write(addr_t addr, word_t data, byte_enable_t byte_enable = -1);
	if (refuse_if_invalid(addr, WORD_SIZE, "write")) return;
	prepare_for_access(addr);
	write_aligned(addr, data, byte_enable);
endfunction : write


// Inner helper: assumes the address has already been word-aligned by the
// caller, so the alignment check is skipped. write_bytestream calls this on
// the hot path.
function void ovip_mem::write_aligned(addr_t addr, word_t data, byte_enable_t byte_enable);
	word_t mask;
	init_mem_line_if_not_exists(addr);
	if (&byte_enable) // All bytes enabled -- single full-word write.
	begin
		mem[addr] = data;
		return;
	end

	// Partial byte-enable: build a byte-level mask in a local variable, then
	// do one read-modify-write on the associative-array entry. The earlier
	// per-byte `mem[addr][i*8+:8] = data[i*8+:8]` form looks like an in-place
	// edit but in most simulators expands to a read-modify-write per byte,
	// which dominates this function's cost when byte_enables are sparse.
	for (int i = 0; i < WORD_SIZE; i++)
		if (byte_enable[i]) mask[i*8 +: 8] = '1;
	mem[addr] = (mem[addr] & ~mask) | (data & mask);
endfunction : write_aligned


function ovip_mem::word_t ovip_mem::read(addr_t addr);
	if (refuse_if_invalid(addr, WORD_SIZE, "read")) return '0;
	prepare_for_access(addr);
	return mem[addr];
endfunction : read


function ovip_bytestream ovip_mem::read_bytestream(addr_t addr, int size = WORD_SIZE);
	ovip_bytestream rd_data;
	int byte_offset = addr % WORD_SIZE;
	int num_full_words = int'($ceil( (size + byte_offset) / real'(WORD_SIZE) ));
	int produced = 0;
	if (refuse_if_invalid(addr, size, "read")) return rd_data;
	addr -= byte_offset; // word-align

	for (int i = 0; i < num_full_words; i++)
	begin
		word_t w = read(addr);
		int start_byte = (i == 0) ? byte_offset : 0;
		for (int j = start_byte; j < WORD_SIZE && produced < size; j++) begin
			rd_data.push_back(w[j*8 +: 8]);
			produced++;
		end
		addr += WORD_SIZE;
	end

	return rd_data;
endfunction : read_bytestream


function void ovip_mem::write_bytestream(addr_t addr, ref byte data[$], ref bit byte_enable[$] = empty_bitstream);
	int byte_offset = addr % WORD_SIZE; // Calculate byte offset within the first word
	int size = data.size();
	int num_full_words;                 // the whole words after the first, partial one: set below
	int data_offset = 0;
	word_t word;
	byte_enable_t strobe;
	// Hoisted out of the per-byte loops -- this never changes during the call.
	bit all_bytes_enabled = (byte_enable.size() == 0);

	// Copy the input queues into local unpacked dynamic arrays. Indexed
	// access on unpacked arrays is materially faster than on queues in most
	// simulators, and we touch each element O(1) times in the inner loops
	// below. The copy is one bulk memcpy each, so the net is a win at this
	// scale even with the upfront alloc.
	byte data_arr[] = new[size];
	bit  be_arr[]   = new[byte_enable.size()];
	if (refuse_if_invalid(addr, size, "write")) return;
	foreach(data[i])        data_arr[i] = data[i];
	foreach(byte_enable[i]) be_arr[i]   = byte_enable[i];

	addr -= addr%WORD_SIZE; // Make address word-aligned

	// Write the first word
	if (byte_offset != 0 || size < WORD_SIZE)
	begin
		strobe = 0;
		for (int i = byte_offset; i < WORD_SIZE && i - byte_offset < size; i++)
		begin
			if (all_bytes_enabled || be_arr[i-byte_offset])
			begin
				word[i*8+:8] = data_arr[i - byte_offset];
				strobe[i] = 1'b1;
			end
		end

		if (|strobe) write_aligned(addr, word, strobe); // Skip the no-op when nothing is enabled.
		addr += WORD_SIZE; // Move to the next word
		data_offset = WORD_SIZE-byte_offset;
	end

	// Write the full words: what is left after the first word, in whole words.
	// (The old count, ceil((size - offset) / WORD_SIZE) - 1, was one short
	// for a large offset, so the last-word branch indexed past the word, and
	// one too many for a small one, so a zero byte was written past the
	// stream.)
	num_full_words = (size > data_offset) ? (size - data_offset) / WORD_SIZE : 0;
	for (int i = 0; i < num_full_words; i++) begin
		strobe = 0;

		for (int j = 0; j < WORD_SIZE; j++)
		begin
			if (all_bytes_enabled || be_arr[data_offset + j])
			begin
				word[j*8+:8] = data_arr[data_offset + j];
				strobe[j] = 1'b1;
			end
		end
		if (|strobe) write_aligned(addr, word, strobe);
		addr += WORD_SIZE; // Move to the next word
		data_offset += WORD_SIZE;
	end

	// Write the last word.
	// (Previously this branch indexed `byte_enable[byte_offset + i]` -- the
	// initial unalignment offset rather than the running `data_offset`. With
	// an unaligned start and a size that's not a multiple of WORD_SIZE the
	// last byte got its strobe from the wrong position. Fixed here.)
	if (size > data_offset) begin
		strobe = 0;
		for (int i = 0; data_offset + i < size; i++)
		begin
			if (all_bytes_enabled || be_arr[data_offset + i])
			begin
				word[i*8+:8] = data_arr[data_offset + i];
				strobe[i] = 1'b1;
			end
		end
		if (|strobe) write_aligned(addr, word, strobe);
	end
endfunction : write_bytestream


function void ovip_mem::print();
	$display("Memory contents:");
	foreach (mem[addr]) begin
		$display("Address: %0d, Data: %h", addr, mem[addr]);
	end
endfunction : print


function void ovip_mem::add_valid_range(addr_t base, addr_t size);
	range_t r;
	if (size == 0)
	begin
		`uvm_error("MEM/BAD_RANGE", $sformatf("%s: a valid range of size 0 at 0x%0h", get_name(), base))
		return;
	end
	r.base = base; r.size = size;
	foreach (valid_ranges[i])
		if (valid_ranges[i].base > base)
		begin
			valid_ranges.insert(i, r);
			return;
		end
	valid_ranges.push_back(r);
endfunction : add_valid_range


function int ovip_mem::num_valid_ranges();
	return valid_ranges.size();
endfunction : num_valid_ranges


function bit ovip_mem::is_valid(addr_t addr, addr_t size = 1);
	addr_t pos = addr;
	if (valid_ranges.size() == 0) return 1;
	while (pos < addr + size)
	begin
		// the farthest end among the ranges holding `pos`; ranges may touch or overlap
		addr_t best = 0;
		bit found = 0;
		foreach (valid_ranges[i])
			if (pos >= valid_ranges[i].base && pos - valid_ranges[i].base < valid_ranges[i].size)
			begin
				addr_t e = valid_ranges[i].base + valid_ranges[i].size;
				if (!found || e > best) best = e;
				found = 1;
			end
		if (!found) return 0;
		pos = best;
	end
	return 1;
endfunction : is_valid


function bit ovip_mem::refuse_if_invalid(addr_t addr, addr_t size, string what);
	if (is_valid(addr, size)) return 0;
	`uvm_error("MEM/OUT_OF_RANGE", $sformatf("%s: %s of %0d byte(s) at 0x%0h touches an address outside the %0d valid range(s); nothing done",
		get_name(), what, size, addr, valid_ranges.size()))
	return 1;
endfunction : refuse_if_invalid


function int ovip_mem::num_lines();
	return mem.num();
endfunction : num_lines


function bit ovip_mem::line_exists(addr_t addr);
	return mem.exists(align_address_to_word_size(addr));
endfunction : line_exists


function void ovip_mem::get_lines(ref addr_t lines[$]);
	addr_t a;
	lines.delete();
	if (mem.first(a))
		do lines.push_back(a); while (mem.next(a));
endfunction : get_lines


function int ovip_mem::compare(ovip_mem other, string tag = "", int max_report = 16);
	int mismatches = 0;
	addr_t a;
	string who = (tag == "") ? get_name() : tag;
	if (mem.first(a))
		do begin
			if (!other.mem.exists(a))
			begin
				mismatches++;
				if (mismatches <= max_report)
					`uvm_error("MEM/COMPARE", $sformatf("%s: line 0x%0h is %h here and was never touched there", who, a, mem[a]))
			end
			else if (other.mem[a] !== mem[a])
			begin
				mismatches++;
				if (mismatches <= max_report)
					`uvm_error("MEM/COMPARE", $sformatf("%s: line 0x%0h is %h here and %h there", who, a, mem[a], other.mem[a]))
			end
		end while (mem.next(a));
	if (other.mem.first(a))
		do begin
			if (!mem.exists(a))
			begin
				mismatches++;
				if (mismatches <= max_report)
					`uvm_error("MEM/COMPARE", $sformatf("%s: line 0x%0h is %h there and was never touched here", who, a, other.mem[a]))
			end
		end while (other.mem.next(a));
	return mismatches;
endfunction : compare

`endif
