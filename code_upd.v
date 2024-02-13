`default_nettype none

// NOTES TO SELF: Please draw meticulous timing and state diagrams.
// TODO: Add dirty check if needed.
/*
- 8 KB cache =  2048 elements of 32-bit = 512 elements of 128-bit
*/

// magic memory. Can accept reads at any time. Releases random valid outputs after a fixed clock cycles of rden.
// consume writes to oblivion. Release fake results after a few cycles
module memory(
	output reg  [127:0] data_out,
	output wire data_out_valid,
	input  wire [127:0] data_in,
	input  wire [031:0] addr_in,
	input  wire rden, wren,
	// misc. signals
	input  wire clk, reset
);
	integer i;
	parameter DELAY = 5;
	
	reg [127:0] gbg_data = 128'hFB63DA9647CC13DC9913FA22DEADBEEF;
	
	reg [DELAY:0] delay_line;
	
	// alias the input 
	always @(*) delay_line[0] = rden;
	
	always @(posedge clk) begin
		if(reset)
			delay_line[DELAY:1] <= 0;
		else
			delay_line[DELAY:1] <= delay_line[DELAY-1:0];
	end
	
	assign data_out_valid = delay_line[DELAY];
	
	always @(posedge clk) begin
		if(reset)
			data_out <= 128'd0;
		if(delay_line[DELAY-1])
			data_out <= gbg_data ^ data_out[126:0];
	end
endmodule

module cache(
	// cpu-cache interface
	output wire interface_ready,
	output reg  [31:0] data_out,
	output reg  data_out_valid,
	input  wire [31:0] data_in,
	input  wire [31:0] addr_in,			// 2 LSbits are essentially useless.
	input  wire rden, wren,
	// cache-mem interface
	output reg  [031:0] mem_addr,
	output reg  [127:0] evictable_cacheline,
	output reg  eviction_wren, mem_read_valid,
	input  wire [127:0] updated_cacheline,
	input  wire cacheline_update_valid,
	// misc. signals
	input  wire clk, reset
);
	integer i;
	
	reg [31:0] memory_core [0:2047];
	reg [18:0] tag_core [0:511];
	reg line_valid [0:511];					// valid
	
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
	wire [08:0] line_addr = addr_in_muxed[12:4];			// 9 bits for line selection
	wire [10:0] word_addr = addr_in_muxed[12:2];			// 11 bits for word selection.
	wire [01:0] winl_addr = addr_in_muxed[03:2];			// 2 bits for word-in-line address
	
	// ************************************************************* CPU SIDE HANDLING & CACHE_MISS_KICK_OFF ************************************************************* //
	// There was a valid request that caused a cache miss? kickoff the miss_recovery_protocol
	assign cache_miss_kickoff = (rden | wren) & ~cache_hit & ~miss_recovery_mode;			// final AND: masks new kickoffs when in recovery mode
	assign interface_ready = !(cache_miss_kickoff || miss_recovery_mode);
	
	// miss recovery bit driver. We may add state latching logic here.
	always @(posedge clk) begin
		if(reset)
			{addr_in_latched, data_in_latched, wren_latched, rden_latched, miss_recovery_mode} <= {64'd0, 2'b00, 1'b0};
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
		cache_hit = line_valid[line_addr] & (tag_addr == tag_core[line_addr]);
		data_out_valid = rden_muxed & cache_hit;
		// Memory interface
		evictable_cacheline = {
			memory_core[{line_addr, 2'b11}],
			memory_core[{line_addr, 2'b10}],
			memory_core[{line_addr, 2'b01}],
			memory_core[{line_addr, 2'b00}]
		};
	end

	// *** *** *** write driver *** *** *** //
	always @(posedge clk) begin
		if(reset)										// reset the dirty and valid situation for the cache.
			for(i=0; i<512; i=i+1)
				line_valid[i] <= 1'b0;
		else begin
			if(wren_muxed & cache_hit)					// don't worry about the device being ready.
				memory_core[word_addr] <= data_in_muxed;
			else if(cacheline_update_valid) begin
				line_valid[line_addr] <= 1'b1; 
				tag_core[line_addr] <= tag_addr;									// update tag, this should result in a cache hit presently.
				memory_core[{line_addr, 2'b11}] <= updated_cacheline[127-:32];
				memory_core[{line_addr, 2'b10}] <= updated_cacheline[095-:32];
				memory_core[{line_addr, 2'b01}] <= updated_cacheline[063-:32];
				memory_core[{line_addr, 2'b00}] <= updated_cacheline[031-:32];
			end
		end
	end
	
	// *************************************************************** EVICTION CONTROL *************************************************************** //
	// 1. Eviction occurs only in miss_recovery_mode
	// Timing Expectations:
	// CLK 0     -> Issues new read address to the RAM.
	// CLK 1     -> Issues write address to the RAM. Initiates a wait of N cycles.
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
	
	// state driven signals. Is a Mealy machine.
	always @(*) begin
		case(state)
			// speculative read state
			2'b00: begin
				mem_addr = {addr_in[31:4], 4'b0000};
				mem_read_valid = cache_miss_kickoff;			// the kickoff cycle is used to issue a read.
				eviction_wren = 1'b0;
			end
			// Eviction write state.
			2'b01: begin
				mem_addr = {tag_core[line_addr], line_addr, 4'b0000};			// address to be evicted
				mem_read_valid = 1'b0;
				eviction_wren = line_valid[line_addr];
			end
			// Response wait state.
			2'b10: begin
				mem_addr = 32'd0;
				mem_read_valid = 1'b0;
				eviction_wren = 1'b0;
			end
			// default
			default: begin
				mem_addr = 32'dX;
				mem_read_valid = 1'bX;
				eviction_wren = 1'bX;
			end
		endcase
	end
	
endmodule

module testbench;
	integer i = 0;
	reg clk, reset;
	
	// cache-mem interface
	wire [031:0] mem_addr;
	wire [127:0] evictable_cacheline;
	wire eviction_wren, mem_read_valid;
	wire [127:0] updated_cacheline;
	wire cacheline_update_valid;
	
	// cpu-cache interface
	wire interface_ready;
	wire [31:0] data_out;
	wire data_out_valid;
	reg  [31:0] data_in;
	reg  [31:0] addr_in;			// 2 LSbits are essentially useless.
	reg  rden, wren;
	
	cache cache_inst(
		// cpu-cache interface
		.interface_ready(interface_ready),
		.data_out(data_out),
		.data_out_valid(data_out_valid),
		.data_in(data_in),
		.addr_in(addr_in),			// 2 LSbits are essentially useless.
		.rden(rden), .wren(wren),
		// cache-mem interface
		.mem_addr(mem_addr),
		.evictable_cacheline(evictable_cacheline),
		.eviction_wren(eviction_wren),
		.mem_read_valid(mem_read_valid),
		.updated_cacheline(updated_cacheline),
		.cacheline_update_valid(cacheline_update_valid),
		// misc. signals
		.clk(clk), .reset(reset)
	);
	
	memory memory_inst(
		.data_out(updated_cacheline),
		.data_out_valid(cacheline_update_valid),
		.data_in(evictable_cacheline),
		.addr_in(mem_addr),
		.rden(mem_read_valid),
		.wren(eviction_wren),
		// misc. signals
		.clk(clk),
		.reset(reset)
	);
	
	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(0, testbench);
		
		addr_in = 0;
		rden = 0; wren = 0;
		data_in = $random;
		
		#0 clk = 0; reset = 0;
		#1 reset = 1;
		#1 clk = 1;
		#1 clk = 0;
		#1 reset = 0;
		

		
		repeat(200000) begin
			#1 clk = ~clk;
			
			#0.1 i = i+1;
			
			if(i % 10 == 0) begin
				if(i % 30 == 0) begin
					wren = 1;
					data_in = $random;
					addr_in = $random & 13'h1fff;
				end
				else begin
					rden = 1;
				end
			end
			else begin
				rden = 0;
				wren = 0;
			end
				
			#1 clk = ~clk;
			
		end
		
		$finish;
	end
endmodule
