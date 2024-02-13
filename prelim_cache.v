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