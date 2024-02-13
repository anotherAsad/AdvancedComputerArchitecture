module true_dualport_mem(
	// port A. width 128 bits. Does not need tag.
	output wire [018:0] tag_out,					// tag_out is a function of addr_A
	output wire [031:0] data_out_A,
	output wire data_out_valid_A,
	input  wire [031:0] data_in_A,
	input  wire [029:0] addr_A,
	input  wire wren_A,
	// port B
	output wire [127:0] data_out_B,
	output wire dirty, valid_B,
	input  wire [127:0] data_in_B,
	input  wire [027:0] addr_B,
	input  wire wren_B,
	// misc signals
	input  wire clk, reset
);
	// parameters defined from the reference of port A.
	parameter ADDR_LEN_A = 11;				// 2048 * 32 bit entries
	parameter SIZE_A = 2**ADDR_LEN_A;
	parameter ADDR_LEN_B = 9;				// 512 * 128 bit entries
	parameter SIZE_B = 2**ADDR_LEN_B;

	integer i;

	// memory core defined from reference of port A
	reg [31:0] memory_core [0:SIZE_A-1];
	// tag and dirty/valid defined from reference of port B
	reg [18:0] tag_field [0:SIZE_B-1];
	reg [01:0] field_dirty_valid [0:SIZE_B-1];

	// mixed port write driver. Port B has final precedence. Should not bear any impact on the global design.
	always @(posedge clk) begin
		if(reset)
			for(i=0; i<SIZE_B; i+=1)
				field_dirty_valid[i] <= 2'b00;
		else begin
			// Write from CPU. Should set dirty bit.
			if(wren_A) begin
				field_dirty_valid[addr_A[10:2]] <= 2'b11;		// if processor writes. The new data is dirty as well as valid.
				memory_core[addr_A[10:0]] <= data_in_A;
			end
			// Write from memory. Should clear dirty bit.
			if(wren_B) begin
				field_dirty_valid[addr_B[8:0]] <= 2'b01;
				memory_core[{addr_B[8:0], 2'b00}] <= data_in_B[031:00];		// LSWord
				memory_core[{addr_B[8:0], 2'b01}] <= data_in_B[063:32];		
				memory_core[{addr_B[8:0], 2'b10}] <= data_in_B[095:64];		
				memory_core[{addr_B[8:0], 2'b11}] <= data_in_B[127:96];		// MSWord
			end
		end
	end

	// mixed port read driver
	always @(*) begin
		data_out_B = 
	end



endmodule

// Cache memory. 1 clk write latency. 0 clk read latency.
module cache_mem(
	output wire [127:0] data_out,		// 16 bytes
	output wire [18:0] tag_out,
	output wire dirty, valid,
	input  wire [127:0] data_in,
	input  wire [27:0] addr,		// 28 bit addr. 9 bit local, 19 bit tag.
	// control sigs
	input wren, mark_dirty,
	input clk, reset				// reset should only reconfig valid and dirty?
);
	parameter ADDR_LEN = 9;				// 512 * 128 bit cache
	parameter SIZE = 2**ADDR_LEN;
	integer i;

	reg [146:0] memory_core [0:SIZE-1];				// 19 + 128. 19 MSbits used to save Tag.
	reg [001:0] field_dirty_valid [0:SIZE-1];

	// memory_core and field_dirty_valid write driver
	// Intent-of-design {valid}: All locations start with valid bit cleared. Valid bit is monotonically rising.
	// Intent-of-design {dirty}: If a location is overwritten by TB, it is marked dirty. If it is fetched from the RAM, it starts as marked clean.
	always @(posedge clk) begin
		if(reset)
			for(i=0; i<SIZE; i+=1)
				field_dirty_valid[i] <= 2'b00;
		else begin
			if(wren) begin
				field_dirty_valid[addr[8:0]] <= {mark_dirty, 1'b1};
				memory_core[addr[8:0]] <= {addr[27:9], data_in};
			end
		end
	end

	// read driver
	always @(*) begin
		data_out = memory_core[addr[ADDR_LEN-1:0]][127:000];
		tag_out  = memory_core[addr[ADDR_LEN-1:0]][146:128];
		{dirty, valid} = field_dirty_valid;
	end
endmodule

// Implements a cache controller and encapsulates cache_mem.
module cache(
	// CPU PORT
	output wire [31:0] data_out,
	output wire data_out_valid,
	output wire ready,
	input  wire [31:0] data_in,
	input  wire [31:0] addr,
	input  wire wren
	// misc. signals
	input  wire clk, reset
);
	integer i;

	// cache port
	wire [18:0] tag_out;
	wire [127:0] cache_line_out, cache_line_in;		// 16 bytes
	wire dirty, valid;
	wire [127:0] data_in;
	wire [27:0] addr;		// 28 bit addr. 9 bit local, 19 bit tag.
	wire wren, mark_dirty;

	cache_mem cache_mem_inst(
		.tag_out(tag_out),
		.data_out(cache_line_out),
		.data_in(cache_line_in),
		.addr(addr[31:4]),
		.dirty(dirty), .valid(valid),		// outputs
		.wren(wren), .mark_dirty(mark_dirty)
		// misc sigs
		.clk(clk), .reset(reset)
	);

	/* *** *** *** CACHE LINE TO CPU WORD MUX *** *** *** */
	always @(*) case(addr[3:2])

	endcase

endmodule

// Magic memory. Swallows the write requests into a void. 
module magic_mem(
	output wire [127:0] data_out,
	output wire data_out_valid, ready,
	input  wire [127:0] data_in,
	input  wire [031:0] addr,
	input  wire wren, rd,
	input  wire clk
);
	parameter CAS_LATENCY = 5;
	integer i;
	reg [CAS_LATENCY-1:0] delay_line;

	// CAS latency modelling system
	always @(*) delay_line[0] = rd;

	always @(posedge clk) begin
		for(i=1; i<=CAS_LATENCY-1; i+=1)
			delay_line[i] = delay_line[i-1];
	end
	
	assign data_out_valid = delay_line[CAS_LATENCY-1];

	// random output system
	always @(posedge clk) begin
		if(delay_line[CAS_LATENCY-2])
			data_out = $random;
		else
			data_out = 128'd0;
	end
endmodule

module cache_controller(
	// CACHE PORT
	output wire [31:0] data_out,
	output wire data_out_valid,
	input  wire [31:0] data_in,
	input  wire [31:0] addr,
	input  wire wren,
	// MEMORY PORT
	// misc. signals
	input  wire clk, reset
);
endmodule

module testbench;
	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(0, testbench);
		$finish;
	end
endmodule