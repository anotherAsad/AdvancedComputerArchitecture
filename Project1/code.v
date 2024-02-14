`include "cache.v"

/*	INTENT OF DESIGN
1. Relays signals from both caches to each other.
2. Buffers/arbitrates between read/write requests of both L1s bound for L2.
*/

// magic memory. Can accept reads at any time. Releases random valid outputs after a fixed clock cycles of rden.
// consume writes to oblivion. Release fake results after a few cycles.
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
		else if(delay_line[DELAY-1])
			data_out <= gbg_data ^ {data_out[126:0], data_out[127]};
	end
endmodule

module testbench;
	integer i = 0;
	reg clk, reset;
	
	// cache-mem interface
	wire [031:0] mem_addr_a, mem_addr_b;
	wire [127:0] evictable_cacheline_a, evictable_cacheline_b;
	wire eviction_wren_a, mem_read_valid_a;
	wire eviction_wren_b, mem_read_valid_b;
	wire [127:0] updated_cacheline_a, updated_cacheline_b;
	wire cacheline_update_valid_a, cacheline_update_valid_b;
	
	// cpu-cache interface
	wire interface_ready_a, interface_ready_b;
	wire [31:0] data_out_a, data_out_b;
	wire data_out_valid_a, data_out_valid_b;
	reg  [31:0] data_in_a, data_in_b;
	reg  [31:0] addr_in_a, addr_in_b;			// 2 LSbits are essentially useless.
	reg  rden_a, rden_b, wren_a, wren_b;
	

	wire [31:0] hotlink_addr_AtoB, hotlink_addr_BtoA;
	wire hotlink_invl_AtoB, hotlink_read_AtoB;
	wire hotlink_invl_BtoA, hotlink_read_BtoA;
	wire hotlink_wren_AtoB, hotlink_wren_BtoA;

	wire valid_interrupt_received_a, valid_interrupt_received_b;
	wire hotlink_interrupt_a, hotlink_interrupt_b;

	interrupt_arbiter interrupt_arbiter_inst(
		.hotlink_interrupt_L1a(hotlink_interrupt_a),
		.hotlink_interrupt_L1b(hotlink_interrupt_b),
		.irq_L1a(valid_interrupt_received_a),
		.irq_L1b(valid_interrupt_received_b)
	);

	L1_cache L1a(
		.interface_ready(interface_ready_a),
		.data_out(data_out_a),
		.data_out_valid(data_out_valid_a),
		.data_in(data_in_a),
		.addr_in(addr_in_a),			// 2 LSbits are essentially useless.
		.rden(rden_a), .wren(wren_a),
		// cache-snooper interface
		.snooper_addr(mem_addr_a),
		.evictable_cacheline(evictable_cacheline_a),
		.eviction_wren(eviction_wren_a),
		.snooper_read_valid(mem_read_valid_a),
		.updated_cacheline(updated_cacheline_a),
		.cacheline_update_valid(cacheline_update_valid_a),		// also serves as an address override.
		// hotlink input port
		.hotlink_addr_in(hotlink_addr_BtoA),		// used only for invalidation and read.
		.hotlink_invl_in(hotlink_invl_BtoA),
		.hotlink_read_in(hotlink_read_BtoA),
		.hotlink_wren_out(hotlink_wren_AtoB),				// responds with data on 'evictable cacheline' if read request matches.
		// hotlink output port
		.hotlink_addr_out(hotlink_addr_AtoB),		// used only for invalidation and read.
		.hotlink_invl_out(hotlink_invl_AtoB),
		.hotlink_read_out(hotlink_read_AtoB),
		.hotlink_wren_in(hotlink_wren_BtoA),				// tells if there was a horizontal hit, and the neighbor returned data
		// misc. signals
		.valid_interrupt_received(valid_interrupt_received_a),
		.hotlink_interrupt(hotlink_interrupt_a),
		.clk(clk), .reset(reset)
	);

	L1_cache L1b(
		.interface_ready(interface_ready_b),
		.data_out(data_out_b),
		.data_out_valid(data_out_valid_b),
		.data_in(data_in_b),
		.addr_in(addr_in_b),			// 2 LSbits are essentially useless.
		.rden(rden_b), .wren(wren_b),
		// cache-snooper interface
		.snooper_addr(mem_addr_b),
		.evictable_cacheline(evictable_cacheline_b),
		.eviction_wren(eviction_wren_b),
		.snooper_read_valid(mem_read_valid_b),
		.updated_cacheline(updated_cacheline_b),
		.cacheline_update_valid(cacheline_update_valid_b),		// also serves as an address override.
		// hotlink input port
		.hotlink_addr_in(hotlink_addr_AtoB),		// used only for invalidation and read.
		.hotlink_invl_in(hotlink_invl_AtoB),
		.hotlink_read_in(hotlink_read_AtoB),
		.hotlink_wren_out(hotlink_wren_BtoA),				// responds with data on 'evictable cacheline' if read request matches.
		// hotlink output port
		.hotlink_addr_out(hotlink_addr_BtoA),		// used only for invalidation and read.
		.hotlink_invl_out(hotlink_invl_BtoA),
		.hotlink_read_out(hotlink_read_BtoA),
		.hotlink_wren_in(hotlink_wren_AtoB),				// tells if there was a horizontal hit, and the neighbor returned data
		// misc. signals
		.valid_interrupt_received(valid_interrupt_received_b),
		.hotlink_interrupt(hotlink_interrupt_b),
		.clk(clk), .reset(reset)
	);
	
	
	memory memory_inst_A(
		.data_out(updated_cacheline_a),
		.data_out_valid(cacheline_update_valid_a),
		.data_in(evictable_cacheline_a),
		.addr_in(mem_addr_a),
		.rden(mem_read_valid_a),
		.wren(eviction_wren_a),
		// misc. signals
		.clk(clk),
		.reset(reset)
	);

	memory memory_inst_B(
		.data_out(updated_cacheline_b),
		.data_out_valid(cacheline_update_valid_b),
		.data_in(evictable_cacheline_b),
		.addr_in(mem_addr_b),
		.rden(mem_read_valid_b),
		.wren(eviction_wren_b),
		// misc. signals
		.clk(clk),
		.reset(reset)
	);
	
	reg [15:0] temp [0:7];

	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(0, testbench);

		temp[0] = 16'hABCD;
		temp[1] = 16'h1234;
		temp[2] = 16'h3462;
		temp[3] = 16'h2398;
		temp[4] = 16'h2438;
		temp[5] = 16'h0974;
		temp[6] = 16'h6758;
		temp[7] = 16'hBF76;
		
		addr_in_a = 0;
		rden_a = 0; wren_a = 0;
		data_in_a = $random;

		addr_in_b = 0;
		rden_b = 0; wren_b = 0;
		data_in_b = $random;

		#0 clk = 0; reset = 0;
		#1 reset = 1;
		#1 clk = 1;
		#1 clk = 0;
		#1 reset = 0;

		repeat(80000) begin
			#1 clk = ~clk;
			
			#0.1 i = i+1;
			
			if(i % 10 == 0) begin
				addr_in_a = $random & 13'hfff;
				if(i % 30 == 0) begin
					wren_a = 0;//interface_ready_a ? 1 : 0;
					data_in_a = 0;//$random;
				end
				else begin
					rden_a = interface_ready_a ? 1 : 0;
				end
			end
			else begin
				rden_a = 0;
				wren_a = 0;
			end

			// P_b action
			
			//temp = addr_in_a;
			//addr_in_b = addr_in_a;

			if(i % 10 == 0) begin
				addr_in_b = $random & 13'hfff;
				rden_b = interface_ready_b ? 1 : 0;
			end
			else
				rden_b = 0;
				
			#1 clk = ~clk;
		end
		
		$finish;
	end
endmodule

