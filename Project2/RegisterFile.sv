module RegisterFile(
	// instruction port A
	input  wire [04:0] addr_r1_A, addr_r2_A, addr_rd_A,
	input  wire instr_valid_A,
	input  wire [07:0] rd_tag_A,			// received from arbiter action
	output reg  [31:0] dout_r1_A, dout_r2_A,
	output reg  dtype_r1_A, dtype_r2_A,		// 0 for data, 1 for tag.
	// instruction port B
	input  wire [04:0] addr_r1_B, addr_r2_B, addr_rd_B,
	input  wire instr_valid_B,
	input  wire [07:0] rd_tag_B,			// received from arbiter action
	output reg  [31:0] dout_r1_B, dout_r2_B,
	output reg  dtype_r1_B, dtype_r2_B,		// 0 for data, 1 for tag.
	// CDB input interface
	input  wire [127:0] CDB_data_serialized,				// comes from the CDB
	input  wire [031:0] CDB_tag_serialized,
	// misc. signals.
	input  wire en, clk, reset
);
	integer i, j;

	reg  [31:0] reg_array [0:31];
	reg  [00:0] reg_valid [0:31];
	reg  [07:0] reg_intag [0:31];		// the arbiter tells us who to expect.

	// CDB ser-des
	wire [31:0] data_in_CDB [0:3];				// comes from the CDB
	wire [07:0] tag_in_CDB [0:3];

	assign {tag_in_CDB[0], tag_in_CDB[1], tag_in_CDB[2],  tag_in_CDB[3]} = CDB_tag_serialized;
	assign {data_in_CDB[0], data_in_CDB[1], data_in_CDB[2], data_in_CDB[3]} = CDB_data_serialized;

	// *** *** *** *** *** *** *** REG FILE OUTPUT CONTROL *** *** *** *** *** *** *** //
	always @(*) begin
		// For instrA
		if(instr_valid_A) begin
			// for r1
			if(reg_valid[addr_r1_A]) begin
				dout_r1_A  <= reg_array[addr_r1_A];
				dtype_r1_A <= 1'b0;
			end
			else begin
				dout_r1_A  <= reg_intag[addr_r1_A];
				dtype_r1_A <= 1'b1;
			end

			// for r2
			if(reg_valid[addr_r2_A]) begin
				dout_r2_A  <= reg_array[addr_r2_A];
				dtype_r2_A <= 1'b0;
			end
			else begin
				dout_r2_A  <= reg_intag[addr_r2_A];
				dtype_r2_A <= 1'b1;
			end
		end
		else begin
			dout_r1_A  <= 32'd0;
			dtype_r1_A <= 1'b0;
			dout_r2_A  <= 32'd0;
			dtype_r2_A <= 1'b0;
		end

		// For instrB
		if(instr_valid_B) begin
			// for r1
			if(reg_valid[addr_r1_B]) begin
				dout_r1_B  <= reg_array[addr_r1_B];
				dtype_r1_B <= 1'b0;
			end
			else begin
				dout_r1_B  <= reg_intag[addr_r1_B];
				dtype_r1_B <= 1'b1;
			end

			// for r2
			if(reg_valid[addr_r2_B]) begin
				dout_r2_B  <= reg_array[addr_r2_B];
				dtype_r2_B <= 1'b0;
			end
			else begin
				dout_r2_B  <= reg_intag[addr_r2_B];
				dtype_r2_B <= 1'b1;
			end
		end
		else begin
			dout_r1_B  <= 32'd0;
			dtype_r1_B <= 1'b0;
			dout_r2_B  <= 32'd0;
			dtype_r2_B <= 1'b0;
		end
	end

	// *** *** *** *** *** *** *** REG FILE INPUT CONTROL *** *** *** *** *** *** *** //
	always @(posedge clk) begin
		for(i=0; i<32; i+=1) begin
			if(reset)
				{reg_array[i], reg_valid[i], reg_intag[i]} <= {i[31:0], 1'b1, 8'd0};
			else if(en) begin
				// CDB initiated resolution.
				for(j=0; j<4; j+=1) begin
					if(tag_match(reg_intag[i], tag_in_CDB[j])) begin
						reg_array[i] <= data_in_CDB[j];
						reg_valid[i] <= 1'b1;
						reg_intag[i] <= 8'd0;
					end
				end
				// Invalidation and renaming. Renaming is prioritised over CDB resolution, because that is better.
				if(instr_valid_A && (i == addr_rd_A)) begin
					reg_array[i] <= 32'd0;
					reg_valid[i] <= 1'b0; 
					reg_intag[i] <= rd_tag_A;
				end
				else if(instr_valid_B && (i == addr_rd_B)) begin
					reg_array[i] <= 32'd0;
					reg_valid[i] <= 1'b0; 
					reg_intag[i] <= rd_tag_B; 
				end
			end
		end
	end

	wire [07:0] abc = reg_intag[16];
	wire [07:0] def = reg_intag[17];

endmodule