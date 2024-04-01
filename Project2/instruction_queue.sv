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
 
		instr_mem[8'h00] = 32'h00702383;			// li		x7, 7
		instr_mem[8'h01] = 32'h00502283;			// li		x5, 5
		instr_mem[8'h02] = 32'h007280b3;			// add		x1, x5, x7
		instr_mem[8'h03] = 32'h005080b3;			// add		x1, x1, x5
		instr_mem[8'h04] = 32'h02728133;			// mul		x2, x5, x7
	end
endmodule
