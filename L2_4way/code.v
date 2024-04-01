`default_nettype none
`include "L2_cache_4way.v"

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
			data_out <= gbg_data ^ data_out[126:0];
	end
endmodule


module testbench;
	integer i = 0;
	integer j = 0;
	reg clk, reset;
	
	// cache-mem interface
	wire [031:0] mem_addr;
	wire [127:0] evictable_cacheline;
	wire eviction_wren, mem_read_valid;
	wire [127:0] updated_cacheline;
	wire cacheline_update_valid;
	
	// cpu-cache interface
	wire interface_ready;
	wire [127:0] data_out;
	wire data_out_valid;
	reg  [127:0] data_in;
	reg  [031:0] addr_in;			// 2 LSbits are essentially useless.
	reg  rden, wren;
	
	L2_cache L2_cache_inst(
		// cpu-cache interface
		.interface_ready(interface_ready),
		.data_out(data_out),
		.data_out_valid(data_out_valid),
		.data_in(data_in),
		.addr_in(addr_in),			// 2 LSbits are essentially useless.
		.rden(rden), .wren(wren),
		// cache-mem interface
		.snooper_addr(mem_addr),
		.evictable_cacheline(evictable_cacheline),
		.eviction_wren(eviction_wren),
		.snooper_read_valid(mem_read_valid),
		.updated_cacheline(updated_cacheline),
		.cacheline_update_valid(cacheline_update_valid),
		// hotlink input port
		.hotlink_addr_in(32'b0),		// used only for invalidation and read.
		.hotlink_invl_in(1'b0),
		.hotlink_read_in(1'b0),
		.hotlink_wren_out(),
		// hotlink output port
		.hotlink_addr_out(),		// used only for invalidation and read.
		.hotlink_invl_out(),
		.hotlink_read_out(),
		.hotlink_wren_in(1'b0),
		// interrupt port
		.valid_interrupt_received(),
		.hotlink_interrupt(1'b0),	
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

	reg [18:0] tag_list [0:3];
	
	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(0, testbench);

		tag_list[0] = 19'h6F76D;
		tag_list[1] = 19'h473A6;
		tag_list[2] = 19'h6973C;
		tag_list[3] = 19'h2D74B;
		
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
				j = i/10;

				case(i/10)
					1: begin
						addr_in = {tag_list[0], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					2: begin
						addr_in = {tag_list[1], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					3: begin
						addr_in = {tag_list[2], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					4: begin
						addr_in = {tag_list[3], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					// Read again

					5: begin
						addr_in = {tag_list[0], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					6: begin
						addr_in = {tag_list[1], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					7: begin
						addr_in = {tag_list[2], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					8: begin
						addr_in = {tag_list[3], 9'h10, 4'b0000};
						wren = 0;
						data_in = $random;
						rden = 1;
					end

					// Modify

					9: begin
						addr_in = {tag_list[0], 9'h10, 4'b0000};
						wren = 1;
						data_in = $random;
						rden = 0;
					end

					10: begin
						addr_in = {tag_list[1], 9'h10, 4'b0000};
						wren = 1;
						data_in = $random;
						rden = 0;
					end

					11: begin
						addr_in = {tag_list[2], 9'h10, 4'b0000};
						wren = 1;
						data_in = $random;
						rden = 0;
					end

					12: begin
						addr_in = {tag_list[3], 9'h10, 4'b0000};
						wren = 1;
						data_in = $random;
						rden = 0;
					end
		
				endcase
			end
			else begin
				addr_in = addr_in;
				wren = 0;
				data_in = data_in;
				rden = 0;
			end
				
			#1 clk = ~clk;
			
		end
		
		$finish;
	end
endmodule
