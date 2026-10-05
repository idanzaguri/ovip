`ifndef OVIP_MEM_SPACE__SV
`define OVIP_MEM_SPACE__SV

// A memory space built from memories, with an address map.
//
// The masters of a system see one address space. Each slave sees its own
// linear space, and the map between the two belongs to the system: a region
// of the system space lands on one slave at an offset, or is striped over
// several slaves in round-robin chunks (memory interleaving). This class
// holds one ovip_mem per slave and the map, and offers the system-space
// accesses that split a range at every map boundary and gather the pieces.
// The slaves keep using their own ovip_mem directly, with their own
// addresses; nothing on the slave side translates.
//
//   ovip_mem_space space = ovip_mem_space::type_id::create("space", this);
//   a = space.add_sub(mem_a, "A");
//   b = space.add_sub(mem_b, "B");
//   space.add_region("ram",  'h1000_0000, 'h1000, a, 'h1000_0000);  // A sees the system address
//   space.add_region("regs", 'h2000_0000, 'h100,  b, 0);             // B sees the offset
//   space.add_striped_region("ddr", 'h8000_0000, 'h1000_0000, '{c, d, e, f}, 512);
//   space.write_bytestream('h1000_0FF8, data);   // splits where the map does
//
// A striped region of granule G over N subs puts chunk k, the bytes
// [base + k*G, base + (k+1)*G), on sub (k mod N) at sub address
// sub_base + (k div N)*G. Every sub holds its chunks packed back to back,
// which is what a slave of an interleaved memory sees.
//
// Two regions may name the same sub with the same sub_base: that is an
// alias, two system ranges on one set of bytes, and a write through one
// reads back through the other. Regions never overlap in the system space;
// add_region refuses one that does. A system address no region covers is a
// hole: resolve() returns 0, covers() returns 0, and an access that touches
// one reports MEM_SPACE/HOLE and does nothing.
//
// Every region also bounds its sub-memory: add_region and add_striped_region
// give the sub the range the region occupies in it (ovip_mem::add_valid_range),
// so a slave VIP that writes its memory outside what it owns is named by
// MEM/OUT_OF_RANGE at that moment, not at the end of the test.
//
// write() and read() here take any byte address, unlike ovip_mem's, which
// need a word-aligned one.

class ovip_mem_space extends uvm_component;
	typedef ovip_mem::addr_t        addr_t;
	typedef ovip_mem::word_t        word_t;
	typedef ovip_mem::byte_enable_t byte_enable_t;

	typedef struct {
		string name;
		addr_t base;       // the region's first system address
		addr_t size;       // bytes: the region is [base, base + size)
		int    subs[$];    // one sub: a linear region; several: striped over them, round robin
		addr_t sub_base;   // the sub address of the region's first byte (of chunk 0 on a striped region)
		int    granule;    // bytes per chunk on a striped region; 0 on a linear one
	} region_t;

	ovip_mem subs[$];
	string   sub_names[$];
	protected region_t regions[$];   // sorted by base; never overlapping

	static ovip_bitstream empty_bitstream = '{};

	`uvm_component_utils(ovip_mem_space)

	function new(string name = "ovip_mem_space", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	// The map
	extern virtual function int  add_sub(ovip_mem m, string name = "");
	extern virtual function void add_region(string name, addr_t base, addr_t size, int sub, addr_t sub_base);
	extern virtual function void add_striped_region(string name, addr_t base, addr_t size, int stripe_subs[$], int granule, addr_t sub_base = 0);
	extern virtual function int  num_regions();
	extern virtual function region_t get_region(int index);
	extern virtual function string map2string();

	// Where one system byte lives: its sub and sub address, and how many
	// bytes from it on stay in the same piece (to the end of the region, or
	// of the chunk on a striped region). 0 when no region covers it.
	extern virtual function bit resolve(addr_t addr, output int sub, output addr_t sub_addr, output addr_t run);
	// 1 when every byte of [addr, addr + size) is covered.
	extern virtual function bit covers(addr_t addr, addr_t size);

	// System-space accesses, split at every map boundary.
	extern virtual function void write_bytestream(addr_t addr, ref ovip_bytestream data, ref ovip_bitstream byte_enable = empty_bitstream);
	extern virtual function ovip_bytestream read_bytestream(addr_t addr, int size);
	extern virtual function void write(addr_t addr, word_t data, byte_enable_t byte_enable = -1);
	extern virtual function word_t read(addr_t addr);
	// Random bytes over a range: a read of memory nobody wrote returns what
	// this put there, so it is predictable.
	extern virtual function void fill_random(addr_t addr, addr_t size);

	// Compare sub by sub against another space with the same subs (the
	// shadow of this one). Returns the mismatch count; see ovip_mem::compare.
	extern virtual function int compare(ovip_mem_space other, string tag = "", int max_report = 16);

	extern protected virtual function bit  insert_region(region_t r);
	extern protected virtual function int  region_at(addr_t addr);
endclass : ovip_mem_space


function int ovip_mem_space::add_sub(ovip_mem m, string name = "");
	if (m == null) `uvm_fatal("MEM_SPACE/BAD_SUB", "add_sub: the sub-memory is null")
	subs.push_back(m);
	sub_names.push_back((name == "") ? m.get_name() : name);
	return subs.size() - 1;
endfunction : add_sub


function void ovip_mem_space::add_region(string name, addr_t base, addr_t size, int sub, addr_t sub_base);
	region_t r;
	r.name = name; r.base = base; r.size = size; r.subs = '{sub}; r.sub_base = sub_base; r.granule = 0;
	if (!insert_region(r)) return;
	subs[sub].add_valid_range(sub_base, size);
endfunction : add_region


function void ovip_mem_space::add_striped_region(string name, addr_t base, addr_t size, int stripe_subs[$], int granule, addr_t sub_base = 0);
	region_t r;
	if (granule <= 0)
	begin
		`uvm_fatal("MEM_SPACE/BAD_REGION", $sformatf("region '%s': a striped region needs a granule above 0, got %0d", name, granule))
		return;
	end
	if (stripe_subs.size() == 0)
	begin
		`uvm_fatal("MEM_SPACE/BAD_REGION", $sformatf("region '%s': a striped region needs at least one sub", name))
		return;
	end
	r.name = name; r.base = base; r.size = size; r.subs = stripe_subs; r.sub_base = sub_base; r.granule = granule;
	if (!insert_region(r)) return;
	// each sub holds its chunks packed from sub_base: chunk k lands on sub
	// (k mod N) at (k div N)*granule, and the last chunk may be partial
	begin
		int    n = stripe_subs.size();
		addr_t chunks = (size + granule - 1) / granule;
		foreach (stripe_subs[j])
		begin
			addr_t count, last, last_size;
			if (chunks <= j) continue;
			count     = (chunks - 1 - j) / n + 1;          // chunks j, j+n, ... below `chunks`
			last      = j + n * (count - 1);               // the sub's last chunk index
			last_size = (last == chunks - 1 && size % granule != 0) ? size % granule : granule;
			subs[stripe_subs[j]].add_valid_range(sub_base, (count - 1) * granule + last_size);
		end
	end
endfunction : add_striped_region


// Insert a region sorted by base; 0 (and a fatal) when it is refused. The
// refusals return as well, so a report catcher that demotes the fatal in a
// test still leaves the map untouched.
function bit ovip_mem_space::insert_region(region_t r);
	if (r.size == 0)
	begin
		`uvm_fatal("MEM_SPACE/BAD_REGION", $sformatf("region '%s': size 0", r.name))
		return 0;
	end
	if (r.base + r.size - 1 < r.base)
	begin
		`uvm_fatal("MEM_SPACE/BAD_REGION", $sformatf("region '%s': 0x%0h + 0x%0h wraps the address space", r.name, r.base, r.size))
		return 0;
	end
	foreach (r.subs[i])
		if (r.subs[i] < 0 || r.subs[i] >= subs.size())
		begin
			`uvm_fatal("MEM_SPACE/BAD_REGION", $sformatf("region '%s': sub %0d does not exist (%0d subs)", r.name, r.subs[i], subs.size()))
			return 0;
		end
	foreach (regions[i])
		if (r.base < regions[i].base + regions[i].size && regions[i].base < r.base + r.size)
		begin
			`uvm_fatal("MEM_SPACE/OVERLAP", $sformatf("region '%s' [0x%0h, 0x%0h) overlaps region '%s' [0x%0h, 0x%0h)",
				r.name, r.base, r.base + r.size, regions[i].name, regions[i].base, regions[i].base + regions[i].size))
			return 0;
		end
	foreach (regions[i])
		if (regions[i].base > r.base)
		begin
			regions.insert(i, r);
			return 1;
		end
	regions.push_back(r);
	return 1;
endfunction : insert_region


function int ovip_mem_space::num_regions();
	return regions.size();
endfunction : num_regions


function ovip_mem_space::region_t ovip_mem_space::get_region(int index);
	return regions[index];
endfunction : get_region


function string ovip_mem_space::map2string();
	string s = "";
	foreach (regions[i])
	begin
		region_t r = regions[i];
		if (r.granule == 0)
			s = {s, $sformatf("  %-12s [0x%0h, 0x%0h)  -> %s at 0x%0h\n", r.name, r.base, r.base + r.size, sub_names[r.subs[0]], r.sub_base)};
		else
		begin
			string names = "";
			foreach (r.subs[j]) names = {names, (j ? "," : ""), sub_names[r.subs[j]]};
			s = {s, $sformatf("  %-12s [0x%0h, 0x%0h)  -> striped over %s, %0d bytes a chunk, from 0x%0h\n", r.name, r.base, r.base + r.size, names, r.granule, r.sub_base)};
		end
	end
	return s;
endfunction : map2string


function int ovip_mem_space::region_at(addr_t addr);
	foreach (regions[i])
		if (addr >= regions[i].base && addr - regions[i].base < regions[i].size)
			return i;
	return -1;
endfunction : region_at


function bit ovip_mem_space::resolve(addr_t addr, output int sub, output addr_t sub_addr, output addr_t run);
	int i = region_at(addr);
	addr_t off;
	sub = -1; sub_addr = 0; run = 0;
	if (i < 0) return 0;
	off = addr - regions[i].base;
	if (regions[i].granule == 0)
	begin
		sub      = regions[i].subs[0];
		sub_addr = regions[i].sub_base + off;
		run      = regions[i].size - off;
	end
	else
	begin
		addr_t chunk  = off / regions[i].granule;
		addr_t in_chunk = off % regions[i].granule;
		int    n      = regions[i].subs.size();
		sub      = regions[i].subs[chunk % n];
		sub_addr = regions[i].sub_base + (chunk / n) * regions[i].granule + in_chunk;
		run      = regions[i].granule - in_chunk;
		if (run > regions[i].size - off) run = regions[i].size - off;
	end
	return 1;
endfunction : resolve


function bit ovip_mem_space::covers(addr_t addr, addr_t size);
	addr_t pos = 0;
	int sub; addr_t sub_addr, run;
	while (pos < size)
	begin
		if (!resolve(addr + pos, sub, sub_addr, run)) return 0;
		pos += run;
	end
	return 1;
endfunction : covers


function void ovip_mem_space::write_bytestream(addr_t addr, ref ovip_bytestream data, ref ovip_bitstream byte_enable = empty_bitstream);
	int size = data.size();
	int pos = 0;
	bit has_be = (byte_enable.size() != 0);
	if (has_be && byte_enable.size() != size)
	begin
		`uvm_error("MEM_SPACE/BAD_ACCESS", $sformatf("write at 0x%0h: %0d data bytes but %0d byte enables", addr, size, byte_enable.size()))
		return;
	end
	if (!covers(addr, size))
	begin
		`uvm_error("MEM_SPACE/HOLE", $sformatf("write of %0d bytes at 0x%0h touches an address no region covers; nothing written", size, addr))
		return;
	end
	while (pos < size)
	begin
		int sub; addr_t sub_addr, run;
		int piece;
		ovip_bytestream chunk;
		ovip_bitstream  chunk_be;
		void'(resolve(addr + pos, sub, sub_addr, run));
		piece = (run < size - pos) ? int'(run) : size - pos;
		for (int i = 0; i < piece; i++)
		begin
			chunk.push_back(data[pos + i]);
			if (has_be) chunk_be.push_back(byte_enable[pos + i]);
		end
		if (has_be) subs[sub].write_bytestream(sub_addr, chunk, chunk_be);
		else        subs[sub].write_bytestream(sub_addr, chunk);
		pos += piece;
	end
endfunction : write_bytestream


function ovip_bytestream ovip_mem_space::read_bytestream(addr_t addr, int size);
	ovip_bytestream out;
	int pos = 0;
	if (!covers(addr, size))
	begin
		`uvm_error("MEM_SPACE/HOLE", $sformatf("read of %0d bytes at 0x%0h touches an address no region covers; nothing read", size, addr))
		return out;
	end
	while (pos < size)
	begin
		int sub; addr_t sub_addr, run;
		int piece;
		ovip_bytestream part;
		void'(resolve(addr + pos, sub, sub_addr, run));
		piece = (run < size - pos) ? int'(run) : size - pos;
		part = subs[sub].read_bytestream(sub_addr, piece);
		foreach (part[i]) out.push_back(part[i]);
		pos += piece;
	end
	return out;
endfunction : read_bytestream


function void ovip_mem_space::write(addr_t addr, word_t data, byte_enable_t byte_enable = -1);
	ovip_bytestream bytes;
	ovip_bitstream  be;
	for (int i = 0; i < ovip_mem::WORD_SIZE; i++)
	begin
		bytes.push_back(data[i*8 +: 8]);
		be.push_back(byte_enable[i]);
	end
	write_bytestream(addr, bytes, be);
endfunction : write


function ovip_mem_space::word_t ovip_mem_space::read(addr_t addr);
	word_t w = 0;
	ovip_bytestream bytes = read_bytestream(addr, ovip_mem::WORD_SIZE);
	foreach (bytes[i]) w[i*8 +: 8] = bytes[i];
	return w;
endfunction : read


function void ovip_mem_space::fill_random(addr_t addr, addr_t size);
	ovip_bytestream bytes;
	repeat (size) bytes.push_back($urandom);
	write_bytestream(addr, bytes);
endfunction : fill_random


function int ovip_mem_space::compare(ovip_mem_space other, string tag = "", int max_report = 16);
	int mismatches = 0;
	string who = (tag == "") ? get_name() : tag;
	if (other == null || other.subs.size() != subs.size())
	begin
		`uvm_error("MEM_SPACE/COMPARE", $sformatf("%s: the other space has %0d subs, this one %0d", who, (other == null) ? 0 : other.subs.size(), subs.size()))
		return 1;
	end
	foreach (subs[i])
		mismatches += subs[i].compare(other.subs[i], {who, "/", sub_names[i]}, max_report);
	return mismatches;
endfunction : compare

`endif
