// Does not
module L2_cache(
	// upstream interface
	output wire interface_ready,
	output reg  [127:0] data_out,
	output reg  data_out_valid,
	input  wire [127:0] data_in,
	input  wire [31:0] addr_in,			// 2 LSbits are essentially useless.
	input  wire rden, wren,
	// downstream interface
	output reg  [031:0] snooper_addr,
	output reg  [127:0] evictable_cacheline,	// used to provide requested data for sister processor as well
	output reg  eviction_wren, snooper_read_valid,
	input  wire [127:0] updated_cacheline,
	input  wire cacheline_update_valid,			// also serves as an address override.
	// hotlink input port
	input  wire [031:0] hotlink_addr_in,		// used only for invalidation and read.
	input  wire hotlink_invl_in, hotlink_read_in,
	output wire hotlink_wren_out,				// responds with data on 'evictable cacheline' if read request matches.
	// hotlink output port
	output wire [031:0] hotlink_addr_out,		// used only for invalidation and read.
	output wire hotlink_invl_out, hotlink_read_out,
	input  wire hotlink_wren_in,				// tells if there was a horizontal hit, and the neighbor returned data
	// misc. signals
	output wire valid_interrupt_received,
	input  wire hotlink_interrupt,
	input  wire clk, reset
);
	integer i, j;
	
	reg [127:0] memory_core [0:511][0:3];
	reg [18:0] tag_core [0:511][0:3];

	// MESI protocol state registers. Implemented in one-hot mode.
	reg M [0:511][0:3];
	reg E [0:511][0:3];
	reg S [0:511][0:3];
	reg I [0:511][0:3];

	// latchables for miss handling
	reg  [31:0] addr_in_latched, data_in_latched;
	reg  wren_latched, rden_latched;
	
	// internal, muxed signals
	reg  [31:0] addr_in_muxed, data_in_muxed;
	reg  wren_muxed, rden_muxed;
	
	reg  miss_recovery_mode;
	reg  cache_hit;
	wire cache_miss_kickoff;
	reg  assert_eviction;
	
	// address breakdown for simplicity at zero cost.
	wire [18:0] tag_addr  = addr_in_muxed[31-:19];		// 19 bits for tag
	wire [08:0] line_addr = addr_in_muxed[12:4];		//  9 bits for line selection

	// *** *** *** hotlink signals *** *** *** //
	wire [8:0] MESI_addr;

	// hotlink_addr_hit is very, very costly in terms of resources.
	wire hotlink_addr_hit_0 = ~I[hotlink_addr_in[12:4]][0] && (hotlink_addr_in[31-:19] == tag_core[hotlink_addr_in[12:4]][0]);
	wire hotlink_addr_hit_1 = ~I[hotlink_addr_in[12:4]][1] && (hotlink_addr_in[31-:19] == tag_core[hotlink_addr_in[12:4]][1]);
	wire hotlink_addr_hit_2 = ~I[hotlink_addr_in[12:4]][2] && (hotlink_addr_in[31-:19] == tag_core[hotlink_addr_in[12:4]][2]);
	wire hotlink_addr_hit_3 = ~I[hotlink_addr_in[12:4]][3] && (hotlink_addr_in[31-:19] == tag_core[hotlink_addr_in[12:4]][3]);

	wire hotlink_addr_hit = hotlink_addr_hit_0 | hotlink_addr_hit_1 | hotlink_addr_hit_2 | hotlink_addr_hit_3;

	wire invl_auth = hotlink_invl_in && hotlink_addr_hit;
	wire read_auth = hotlink_read_in && hotlink_addr_hit;
	assign valid_interrupt_received = invl_auth | read_auth;
	// [redefined as an input] hotlink_interrupt = invl_auth | read_auth;

	wire modify_condition = wren_muxed & cache_hit & ~hotlink_interrupt;		// condition for setting modify flag.

	// MESI_addr is the addr for MESI core
	assign MESI_addr = (hotlink_interrupt) ? hotlink_addr_in[12:4] : line_addr;
	assign hotlink_wren_out = read_auth & hotlink_interrupt;

	// hotlink output port signals
	assign hotlink_addr_out = addr_in_muxed;		// handles outgoing read request and invalidation requests. Is the very same as requested by CPU.
	assign hotlink_read_out = cache_miss_kickoff;	// if there is a cache miss, we issue a read to the sister processor
	assign hotlink_invl_out = modify_condition && (		// if a shared block is going to get updated. || if there is a hotlink interrupt, we can not send one from here in the same cycle
		S[line_addr][0] | S[line_addr][1] |
		S[line_addr][2] | S[line_addr][3]
	);
	// **************************************************** CPU SIDE HANDLING & CACHE_MISS_KICK_OFF **************************************************** //
	// There was a valid request that caused a cache miss? kickoff the miss_recovery_protocol
	assign cache_miss_kickoff = (rden | wren) & ~cache_hit & ~miss_recovery_mode & ~hotlink_interrupt;	// final ANDs: masks new kickoffs when in recovery mode
	assign interface_ready = !(miss_recovery_mode | hotlink_interrupt | assert_eviction);
	
	// miss recovery bit driver. We may add state latching logic here.
	always @(posedge clk) begin
		if(reset)
			{addr_in_latched, data_in_latched, wren_latched, rden_latched, miss_recovery_mode} <= {64'd0, 2'b00, 1'b0};
		else if(!hotlink_interrupt) begin				// don't do anything if there is an interrupt on hotlink.
			if(cache_miss_kickoff) begin
				miss_recovery_mode <= 1'b1;
				addr_in_latched <= addr_in;
				data_in_latched <= data_in;
				wren_latched <= wren;
				rden_latched <= rden;
			end
			else if(miss_recovery_mode & cache_hit)	begin		// miss_recovery mode should override input mux.
				miss_recovery_mode <= 1'b0;
				addr_in_latched <= 32'd0;
				data_in_latched <= 32'd0;
				wren_latched <= 1'b0;
				rden_latched <= 1'b0;
			end
		end
	end
	
	// Input signal mux description
	always @(*) begin
		if(miss_recovery_mode) begin
			addr_in_muxed = addr_in_latched;
			data_in_muxed = data_in_latched;
			wren_muxed = wren_latched;
			rden_muxed = rden_latched;
		end
		else begin
			addr_in_muxed = addr_in;
			data_in_muxed = data_in;
			wren_muxed = wren;
			rden_muxed = rden;
		end
	end

	reg  cache_hit_0, cache_hit_1, cache_hit_2, cache_hit_3;
	reg  [1:0] hit_idx;

	// cache hit index fetch
	always @(*) begin
		if(cache_hit_0)
			hit_idx <= 2'd0;
		else if(cache_hit_1)
			hit_idx <= 2'd1;
		else if(cache_hit_2)
			hit_idx <= 2'd2;
		else if(cache_hit_3)
			hit_idx <= 2'd3;
		else
			hit_idx <= 2'd0;
	end

	// *** *** *** read driver *** *** *** //
	always @(*) begin
		// CPU interface														
		data_out = memory_core[line_addr][hit_idx];
		cache_hit_0 = ~I[line_addr][0] & (tag_addr == tag_core[line_addr][0]);		// not invalid and tags match
		cache_hit_1 = ~I[line_addr][1] & (tag_addr == tag_core[line_addr][1]);		// not invalid and tags match
		cache_hit_2 = ~I[line_addr][2] & (tag_addr == tag_core[line_addr][2]);		// not invalid and tags match
		cache_hit_3 = ~I[line_addr][3] & (tag_addr == tag_core[line_addr][3]);		// not invalid and tags match
		
		cache_hit = cache_hit_0 | cache_hit_1 | cache_hit_2 | cache_hit_3;		// not invalid and tags match

		data_out_valid = rden_muxed & cache_hit;

		// Memory interface
		if(cache_hit_0)
			evictable_cacheline = memory_core[MESI_addr][0];
		else if(cache_hit_1)
			evictable_cacheline = memory_core[MESI_addr][1];
		else if(cache_hit_2)
			evictable_cacheline = memory_core[MESI_addr][2];
		else
			evictable_cacheline = memory_core[MESI_addr][3];
	end

	// *** *** *** write driver *** *** *** //
	// This logic elegantly hangles the updates from sister processor. Even in the clk0, the line_addr is valid,
	// and caters well for cacheline update target. WARN: this means the miss handler must return as soon as possible.
	// Moreover, observe this module is not exclusively masked with ~hotlink_interrupt as enable. However, modify_condition implicitly is.
	always @(posedge clk) begin
		if(modify_condition) begin	// don't worry about the device being ready, but don't update mem_core if there is an interrupt.
			if(cache_hit)
				memory_core[line_addr][hit_idx] <= data_in_muxed;
		end
		else if((cacheline_update_valid & ~hotlink_interrupt) | hotlink_wren_in) begin			// sister cache gives a signal to write, while asserting an interrupt.
			// update tag, this should result in a cache hit presently.
			tag_core[line_addr][3] <= tag_core[line_addr][2];
			tag_core[line_addr][2] <= tag_core[line_addr][1];
			tag_core[line_addr][1] <= tag_core[line_addr][0];
			tag_core[line_addr][0] <= tag_addr;

			// LRU update
			memory_core[line_addr][3] <= memory_core[line_addr][2];
			memory_core[line_addr][2] <= memory_core[line_addr][1];
			memory_core[line_addr][1] <= memory_core[line_addr][0];
			memory_core[line_addr][0] <= updated_cacheline;
		end
	end

	reg [1:0] hotlink_hit_idx;

	always @(*) begin
		if(hotlink_addr_hit_0)
			hotlink_hit_idx <= 2'd0;
		else if(hotlink_addr_hit_0)
			hotlink_hit_idx <= 2'd1;
		else if(hotlink_addr_hit_0)
			hotlink_hit_idx <= 2'd2;
		else if(hotlink_addr_hit_0)
			hotlink_hit_idx <= 2'd3;
		else
			hotlink_hit_idx <= 2'd0;
	end


	// *** *** *** MESI core write driver *** *** *** //
	always @(posedge clk) begin
		if(reset)										// invalidate all cachelines in the beginning
			for(i=0; i<512; i=i+1) begin
				for(j=0; j<4; j+=1)
					{M[i][j], E[i][j], S[i][j], I[i][j]} <= 4'b0001;
			end
		else begin
			if(modify_condition) begin
				M[MESI_addr][hit_idx] <= 1'b1;
				E[MESI_addr][hit_idx] <= 1'b0;
				S[MESI_addr][hit_idx] <= 1'b0;
				I[MESI_addr][hit_idx] <= 1'b0;
			end
			if(hotlink_wren_in | (read_auth & hotlink_interrupt)) begin	// Shared flag when both cores have a common cacheline due to : (1) issuing a valid read request (2) when servicing a read request 
				// Is an incoming or outgoing share.
				M[MESI_addr][hotlink_hit_idx] <= 1'b0;
				E[MESI_addr][hotlink_hit_idx] <= 1'b0;
				S[MESI_addr][hotlink_hit_idx] <= 1'b1;
				I[MESI_addr][hotlink_hit_idx] <= 1'b0;
			end
			else if(cacheline_update_valid & ~hotlink_interrupt) begin
				// is an update from downstream
				for(i=1; i<4; i+=1) begin
					M[MESI_addr][i] <= M[MESI_addr][i-1];
					E[MESI_addr][i] <= E[MESI_addr][i-1];
					S[MESI_addr][i] <= S[MESI_addr][i-1];
					I[MESI_addr][i] <= I[MESI_addr][i-1];
				end

				M[MESI_addr][0] <= 1'b0;
				E[MESI_addr][0] <= 1'b1;
				S[MESI_addr][0] <= 1'b0;
				I[MESI_addr][0] <= 1'b0;
			end
			else if(invl_auth & hotlink_interrupt) begin			// mask with interrupt to be sure about interrupt validity in L1b	
				// Is an incoming invalidation
				M[MESI_addr][hotlink_hit_idx] <= 1'b0;
				E[MESI_addr][hotlink_hit_idx] <= 1'b0;
				S[MESI_addr][hotlink_hit_idx] <= 1'b0;
				I[MESI_addr][hotlink_hit_idx] <= 1'b1;
			end
		end
	end

	// *********************************************************** EVICTION & READ  CONTROL *********************************************************** //
	// WARN: Should take special care about the eviction of a cacheline on a miss, because southbound databus (evictable) has to manage hotlink reads too.
	// ************************************************************************************************************************************************ //
	// Timing Expectations:
	// CLK 0   -> Issue new read address to NEIGHBOR, if fails, issue it to RAM. At any rate, prepare for eviction of new data.
	// CLK 1   -> Issues write address to the RAM for eviction. Initiates a wait of N cycles. || if NEIGHBOR tries to access, the cycle goes empty.
	// CLK N+1 -> Captures the incoming data. When done, cache_hit becomes active. Potential cache writes are done.
	// CLK N+2 -> Miss recovery mode is finished.
	always @(posedge clk or posedge reset) begin
		if(reset)
			assert_eviction <= 1'b0;
		else if(!hotlink_interrupt) begin
			if(cache_miss_kickoff & M[MESI_addr][hit_idx])
				assert_eviction <= 1'b1;
			else if(assert_eviction)
				assert_eviction <= 1'b0;
		end
	end

	// eviction address control. Doesn't matter if the neighbor is causing an interrupt, get rid of the evictable as soon as you can.
	always @(*) begin
		if(cache_miss_kickoff) begin										// if NEIGHBOR accesses, cache miss kickoff goes low.
			snooper_addr = {addr_in[31:4], 4'b0000};
			snooper_read_valid = ~hotlink_wren_in;
			eviction_wren = 1'b0;
		end
		else if(assert_eviction) begin										// if NEIGHBOR accesses, all output signals are low.
			snooper_addr = {tag_core[line_addr][hit_idx], line_addr, 4'b0000};
			snooper_read_valid = 1'b0;
			eviction_wren = ~hotlink_interrupt;
		end
		else begin
			snooper_addr = 32'd0;
			snooper_read_valid = 1'b0;
			eviction_wren = 1'b0;
		end
	end

	wire [018:0] tag_0x10_0 = tag_core[9'h10][0];
	wire [018:0] tag_0x10_1 = tag_core[9'h10][1];
	wire [018:0] tag_0x10_2 = tag_core[9'h10][2];
	wire [018:0] tag_0x10_3 = tag_core[9'h10][3];

	wire [127:0] mem_0x10_0 = memory_core[9'h10][0];
	wire [127:0] mem_0x10_1 = memory_core[9'h10][1];
	wire [127:0] mem_0x10_2 = memory_core[9'h10][2];
	wire [127:0] mem_0x10_3 = memory_core[9'h10][3];

	wire [03:0] MESI_0x10_0 = {M[9'h10][0], E[9'h10][0], S[9'h10][0], I[9'h10][0]};
	wire [03:0] MESI_0x10_1 = {M[9'h10][1], E[9'h10][1], S[9'h10][1], I[9'h10][1]};
	wire [03:0] MESI_0x10_2 = {M[9'h10][2], E[9'h10][2], S[9'h10][2], I[9'h10][2]};
	wire [03:0] MESI_0x10_3 = {M[9'h10][3], E[9'h10][3], S[9'h10][3], I[9'h10][3]};

	initial begin
		for(i = 0; i<512; i+=1) begin
			for(j = 0; j<4; j+=1) begin
				tag_core[i][j] <= 32'd0;
				memory_core[i][j] <= 128'd0;
				M[i][j] <= 1'b0;
				E[i][j] <= 1'b0;
				S[i][j] <= 1'b0;
				I[i][j] <= 1'b0;
			end
		end
	end
endmodule