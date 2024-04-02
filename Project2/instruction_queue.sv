module instruction_queue(
	// instruction queue
	output reg  [31:0] instr1, instr2,
	input  wire [01:0] shift_count,			// can be 0, 1 or 2. 2 is coded as 2'b10 or 2'b11. This means one-hot shift indexing works!
	input  wire clk, reset
);
	integer i;

	reg  [07:0] mem_idx;
	reg  [31:0] instr_mem [0:255];

	always @(posedge clk) begin
		if(reset)
			mem_idx <= 8'd0;
		else case(shift_count)
			2'b00: mem_idx <= mem_idx + 0;
			2'b01: mem_idx <= mem_idx + 1;
			2'b10: mem_idx <= mem_idx + 2;
			2'b11: mem_idx <= mem_idx + 2;
		endcase
	end

	always @(*) begin
		instr1 = instr_mem[mem_idx+0];
		instr2 = instr_mem[mem_idx+1];
	end

	// initial state
	initial begin
		for(i=0; i<256; i++)
			instr_mem[i] = 32'h00000013;			// nop
 
			instr_mem[8'h0] = 32'h00b02083;         // lw           x1, 11(x0)              # w0
			instr_mem[8'h1] = 32'h00f02103;         // lw           x2, 15(x0)              # w1
			instr_mem[8'h2] = 32'h01602183;         // lw           x3, 22(x0)              # w2
			instr_mem[8'h3] = 32'h02d02203;         // lw           x4, 45(x0)              # a1
			instr_mem[8'h4] = 32'h03e02283;         // lw           x5, 62(x0)              # a2
			instr_mem[8'h5] = 32'h04f02303;         // lw           x6, 79(x0)              # a3

			instr_mem[8'h6] = 32'h02408533;         // mul          x10, x1, x4
			instr_mem[8'h7] = 32'h025105b3;         // mul          x11, x2, x5
			instr_mem[8'h8] = 32'h00b50833;         // add          x16, x10, x11
			instr_mem[8'h9] = 32'h02618633;         // mul          x12, x3, x6
			instr_mem[8'ha] = 32'h00c80833;         // add          x16, x16, x12

			instr_mem[8'hb] = 32'h002088b3;         // add          x17, x1, x2
			instr_mem[8'hc] = 32'h003888b3;         // add          x17, x17, x3
			
			instr_mem[8'hd] = 32'h03184833;         // div          x16, x16, x17
	end
endmodule
