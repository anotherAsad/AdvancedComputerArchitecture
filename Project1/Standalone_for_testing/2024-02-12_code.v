`default_nettype none

/* INTENT OF DESIGN:
1. Hotlink interrupts given absolute priority.
2. Do not ever ever update memory core (and periphernalia like tag_core and MESI_core) if there is a hotlink interrupt.
3. In the north, processor, and in south, the snooper/L2 nexus is responsible to issue requests only when this module is ready. [interface_ready is for both Processor and Snooper/L2]
*/

module cache(
	// cpu-cache interface
	output wire interface_ready,
	output reg  [31:0] data_out,
	output reg  data_out_valid,
	input  wire [31:0] data_in,
	input  wire [31:0] addr_in,			// 2 LSbits are essentially useless.
	input  wire rden, wren,
	// cache-snooper interface
	output reg  [031:0] snooper_addr,
	output reg  [127:0] evictable_cacheline,	// used to provide requested data for sister processor as well
	output reg  eviction_wren, mem_read_valid,
	input  wire [127:0] updated_cacheline,
	input  wire cacheline_update_valid,			// also serves as an address override.
	// hotlink input port
	input  wire [031:0] hotlink_addr_in,		// used only for invalidation and read.
	input  wire hotlink_invl_in, hotlink_read_in,
	output wire hotlink_out_valid,				// responds with data on 'evictable cacheline' if read request matches.
	// hotlink output port
	output wire [031:0] hotlink_addr_out,		// used only for invalidation and read.
	output wire hotlink_invl_out, hotlink_read_out,
	input  wire hotlink_wren_in,				// tells if there was a horizontal hit, and the neighbor returned data
	// misc. signals
	input  wire clk, reset
);
	integer i;
	
	reg [31:0] memory_core [0:2047];
	reg [18:0] tag_core [0:511];

	// MESI protocol state registers. Implemented in one-hot mode.
	reg M [0:511];
	reg E [0:511];
	reg S [0:511];
	reg I [0:511];

	// latchables for miss handling
	reg  [31:0] addr_in_latched, data_in_latched;
	reg  wren_latched, rden_latched;
	
	// internal, muxed signals
	reg  [31:0] addr_in_muxed, data_in_muxed;
	reg  wren_muxed, rden_muxed;
	
	reg  miss_recovery_mode;
	reg  cache_hit;
	wire cache_miss_kickoff;
	
	// address breakdown for simplicity at zero cost.
	wire [18:0] tag_addr  = addr_in_muxed[31-:19];		// 19 bits for tag
	wire [08:0] line_addr = addr_in_muxed[12:4];		// 9 bits for line selection
	wire [10:0] word_addr = addr_in_muxed[12:2];		// 11 bits for word selection.

	// *** *** *** hotlink signals *** *** *** //
	wire [8:0] MESI_addr;

	wire hotlink_addr_hit = ~I[MESI_addr] && (hotlink_addr_in[31-:19] == tag_core[MESI_addr]);
	wire invl_auth = hotlink_invl_in && hotlink_addr_hit;
	wire read_auth = hotlink_read_in && hotlink_addr_hit;
	wire hotlink_interrupt = invl_auth | read_auth;

	// MESI_addr is the addr for MESI core
	assign MESI_addr = (hotlink_interrupt) ? hotlink_addr_in[12:4] : line_addr;
	assign hotlink_out_valid = read_auth;

	// hotlink output port signals
	assign hotlink_addr_out = addr_in_muxed;		// handles outgoing read request and invalidation requests. Is the very same as requested by CPU.
	assign hotlink_read_out = cache_miss_kickoff;	// if there is a cache miss, we issue a read to the sister processor
	assign hotlink_invl_out = S[MESI_addr] & wren_muxed & cache_hit & ~hotlink_interrupt;		// if a shared block is going to get updated.

	// **************************************************** CPU SIDE HANDLING & CACHE_MISS_KICK_OFF **************************************************** //
	// There was a valid request that caused a cache miss? kickoff the miss_recovery_protocol
	assign cache_miss_kickoff = (rden | wren) & ~cache_hit & ~miss_recovery_mode;			// final ANDs: masks new kickoffs when in recovery mode
	assign interface_ready = !(miss_recovery_mode | hotlink_interrupt);
	
	// miss recovery bit driver. We may add state latching logic here.
	always @(posedge clk) begin
		if(reset)
			{addr_in_latched, data_in_latched, wren_latched, rden_latched, miss_recovery_mode} <= {64'd0, 2'b00, 1'b0};
		if(!hotlink_interrupt) begin				// don't do anything if there is an interrupt on hotlink.
			else if(cache_miss_kickoff) begin
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

	// *** *** *** read driver *** *** *** //
	always @(*) begin
		// CPU interface														
		data_out = memory_core[word_addr];
		cache_hit = ~I[line_addr] & (tag_addr == tag_core[MESI_addr]);		// not invalid and tags match
		data_out_valid = rden_muxed & cache_hit;
		// Memory interface
		evictable_cacheline = {
			memory_core[{MESI_addr, 2'b11}],
			memory_core[{MESI_addr, 2'b10}],
			memory_core[{MESI_addr, 2'b01}],
			memory_core[{MESI_addr, 2'b00}]
		};
	end

	// *** *** *** write driver *** *** *** //
	// This logic elegantly hangles the updates from sister processor. Even in the clk0, the line_addr is valid,
	// and caters well for cacheline update target. WARN: this means the miss handler must return as soon as possible.
	always @(posedge clk) begin
		if(wren_muxed & cache_hit & ~hotlink_interrupt) begin	// don't worry about the device being ready, but don't update mem_core if there is an interrupt.
			memory_core[word_addr] <= data_in_muxed;
		end
		else if((cacheline_update_valid & ~hotlink_interrupt) | hotlink_wren_in) begin
			tag_core[line_addr] <= tag_addr;									// update tag, this should result in a cache hit presently.
			memory_core[{line_addr, 2'b11}] <= updated_cacheline[127-:32];
			memory_core[{line_addr, 2'b10}] <= updated_cacheline[095-:32];
			memory_core[{line_addr, 2'b01}] <= updated_cacheline[063-:32];
			memory_core[{line_addr, 2'b00}] <= updated_cacheline[031-:32];
		end
	end

	// *** *** *** MESI core write driver *** *** *** //
	always @(posedge clk) begin
		if(reset)										// invalidate all cachelines in the beginning
			for(i=0; i<512; i=i+1)
				{M[i], E[i], S[i], I[i]} <= 4'b0001;
		else begin
			if(wren_muxed & cache_hit & ~hotlink_interrupt) begin
				M[MESI_addr] <= 1'b1;
				E[MESI_addr] <= 1'b0;
				S[MESI_addr] <= 1'b0;
				I[MESI_addr] <= 1'b0;
			end
			if(hotlink_wren_in | read_auth) begin	// Shared flag when both cores have a common cacheline due to : (1) issuing a valid read request (2) when servicing a read request 
				M[MESI_addr] <= 1'b0;
				E[MESI_addr] <= 1'b0;
				S[MESI_addr] <= 1'b1;
				I[MESI_addr] <= 1'b0;
			end
			else if(cacheline_update_valid & ~hotlink_interrupt) begin
				M[MESI_addr] <= 1'b0;
				E[MESI_addr] <= 1'b1;
				S[MESI_addr] <= 1'b0;
				I[MESI_addr] <= 1'b0;
			end
			else if(invl_auth) begin
				M[MESI_addr] <= 1'b0;
				E[MESI_addr] <= 1'b0;
				S[MESI_addr] <= 1'b0;
				I[MESI_addr] <= 1'b1;
			end
		end
	end

	// *************************************************************** EVICTION CONTROL *************************************************************** //
	// WARN: Should take special care about the eviction of a cacheline on a miss, because southbound databus (evictable) has to manage hotlink reads too.
	// ************************************************************************************************************************************************ //
	// Timing Expectations:
	// CLK 0     -> Issues new read address to NEIGHBOR, if fails, issue it to RAM.
	// CLK 1     -> Issues write address to the RAM for eviction. Initiates a wait of N cycles.
	// CLK N+1   -> Captures the incoming data. When done, cache_hit becomes active. Potential cache writes are done.
	// CLK N+2   -> Miss recovery mode is finished.
	
	reg [1:0] state;

	// State control logic.
	always @(posedge clk) begin
		if(reset)
			state <= 2'b00;
		else begin
			case(state)
				2'b00: state <= cache_miss_kickoff ? 2'b01 : 2'b00;			// read state
				2'b01: state <= cacheline_update_valid ? 2'b00 : 2'b10;		// moves to wait state, or bypasses wait state and jumps straight back to speculative read state.
				2'b10: state <= cacheline_update_valid ? 2'b00 : 2'b10;		// waits for cacheline_update_valid, then moves to to speculative read state.
				default: state <= 2'bXX;									// if you are at 2'b11, I don't care where you go. just don't waste my logic elements.
			endcase
		end
	end
	
endmodule
