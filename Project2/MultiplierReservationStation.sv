
// Be Careful: You have to do an ordered retirement of all operations.
module MultiplierReservationStation(
	// Register input interface
	input  wire [31:0] src_in_1, src_in_2,		// comes from regfile. Lower 8 bits are used for tag if the regfile says so, else this is data.
	input  wire src_in_valid,					// controlled by decoder.
	input  wire src_in1_type, src_in2_type,		// 0 for data, 1 for tag.
	// CDB input interface
	input  wire [127:0] CDB_data_serialized,				// comes from the CDB
	input  wire [031:0] CDB_tag_serialized,
	// CDB data_out interface
	output reg  data_out_valid,
	output reg  [31:0] data_out,
	output reg  [07:0] reg_tag_out,
	// dispatcher interface
	output wire ready_for_instr,
	output wire [07:0] acceptor_tag,			// {tag_valid, mem_type, add_type, mul_type, div_type, 3'dID}
	// misc. signals
	input  wire en, clk, reset
);
	integer i, j;

	reg  [07:0] CDB_offload;

	// record keeping memory
	reg  [00:0] mult_busy [0:7];			// 00 -> free, 01 -> working
	reg  [02:0] mult_cntr [0:7];
	
	reg  [00:0] src1_valid [0:7];
	reg  [07:0] src1_intag [0:7];
	reg  [31:0] src1_value [0:7];

	reg  [00:0] src2_valid [0:7];
	reg  [07:0] src2_intag [0:7];
	reg  [31:0] src2_value [0:7];

	// CDB ser-des
	wire [31:0] data_in_CDB [0:3];				// comes from the CDB
	wire [07:0] tag_in_CDB [0:3];

	assign {tag_in_CDB[0], tag_in_CDB[1], tag_in_CDB[2], tag_in_CDB[3]} = CDB_tag_serialized;
	assign {data_in_CDB[0], data_in_CDB[1], data_in_CDB[2], data_in_CDB[3]} = CDB_data_serialized;

	// *** *** *** *** *** *** *** MULT AVAILABILITY HANDLING *** *** *** *** *** *** *** //
	reg  [03:0] next_mult_ID;

	// priority encoder. Semi-clever.
	always @(*) begin
		next_mult_ID = 8;			// no one is free. Tag is invalid.

		for(i=7; i>=0; i-=1)
			if(~mult_busy[i])
				next_mult_ID = i;
	end

	assign ready_for_instr = (next_mult_ID != 4'd8);
	assign acceptor_tag = {ready_for_instr, 4'b0010, next_mult_ID[2:0]};		// {tag_valid, mem_type, add_type, mul_type, div_type, 3'dID}

	// *** *** *** *** *** *** *** MULT OPERATION HANDLING *** *** *** *** *** *** *** //
	always @(posedge clk) begin
		for(i=0; i<8; i+=1) begin
			if(reset) begin
				{mult_busy[i], mult_cntr[i]} <= 4'd0;
				{src1_valid[i], src1_value[i], src1_intag[i]} <= 41'h0;
				{src2_valid[i], src2_value[i], src2_intag[i]} <= 41'h0;
			end
			else if(en) begin
				// source population from regfile
				if(src_in_valid && (next_mult_ID == i)) begin							// if this was a valid add instruction.
					// set this mult to busy
					mult_busy[i] <= 1'b1;

					// populate the source 1 operands initially. Sourced from regfile this one time.  
					if(src_in1_type == 1'b0) begin					// if regfile gives data
						src1_valid[i] <= 1'b1;
						src1_value[i] <= src_in_1;
						src1_intag[i] <= {1'b0, 7'h0};
					end
					else begin
						// default to set this source set into waiting mode.
						src1_valid[i] <= 1'b0;
						src1_value[i] <= 0;
						src1_intag[i] <= src_in_1[7:0];

						// override due to tag_match over CDB in the same cycle. This is a beautiful corner case.
						for(j=0; j<4; j+=1) begin
							if(tag_match(src_in_1[7:0], tag_in_CDB[j])) begin
								src1_valid[i] <= 1'b1;
								src1_value[i] <= data_in_CDB[j];
								src1_intag[i] <= {1'b0, 7'h0};
							end
						end
					end

					// populate the source 2 operands initially. Sourced from regfile this one time.  
					if(src_in2_type == 1'b0) begin					// if regfile gives data
						src2_valid[i] <= 1'b1;
						src2_value[i] <= src_in_2;
						src2_intag[i] <= {1'b0, 7'h0};
					end
					else begin
						src2_valid[i] <= 1'b0;
						src2_value[i] <= 0;
						src2_intag[i] <= src_in_2[7:0];

						// override due to tag_match over CDB in the same cycle. This is a beautiful corner case.
						for(j=0; j<4; j+=1) begin
							if(tag_match(src_in_2[7:0], tag_in_CDB[j])) begin
								src2_valid[i] <= 1'b1;
								src2_value[i] <= data_in_CDB[j];
								src2_intag[i] <= {1'b0, 7'h0};
							end
						end
					end
				end
				else if(src1_valid[i] && src2_valid[i]) begin
					if(mult_cntr[i] < 6)									// this marks the off-load time
						mult_cntr[i] <= mult_cntr[i] + 3'd1;
					else if(CDB_offload[i]) begin
						mult_busy[i] <= 1'b0;
						mult_cntr[i] <= 3'd0;

						src1_valid[i] <= 1'b0;
						src1_value[i] <= 32'd0;
						src1_intag[i] <= 8'd0;

						src2_valid[i] <= 1'b0;
						src2_value[i] <= 32'd0;
						src2_intag[i] <= 8'd0;
					end
				end
				else begin			// CDB based source population control
					for(j=0; j<4; j+=1) begin
						// operate on tag matches for src1
						if(!src1_valid[i] && tag_match(src1_intag[i], tag_in_CDB[j])) begin
							src1_valid[i] <= 1'b1;
							src1_value[i] <= data_in_CDB[j];
							src1_intag[i] <= {1'b0, 7'h0};
						end
						// operate on tag matches for src2
						if(!src2_valid[i] && tag_match(src2_intag[i], tag_in_CDB[j])) begin
							src2_valid[i] <= 1'b1;
							src2_value[i] <= data_in_CDB[j];
							src2_intag[i] <= {1'b0, 7'h0};
						end
					end
				end
			end
		end
	end

	// *** *** *** *** *** *** *** CDB OFFLOAD CONTROL *** *** *** *** *** *** *** //
	// priority decoder. Semi-clever.
	always @(*) begin
		// default value
		data_out = 32'd0;
		reg_tag_out = {1'b0, 3'b000, 1'b0, 3'b000};
		data_out_valid = 1'b0;

		for(i=0; i<8; i+=1) begin
			// if this unit is done working, and the sister unit is already free: raise the offload flag.
			CDB_offload[i] = !data_out_valid && mult_busy[i] && (mult_cntr[i] == 3'd6);

			// for corresponding offload flag, display data outside.
			if(CDB_offload[i]) begin
				data_out = src1_value[i] * src2_value[i];
				reg_tag_out = {1'b1, 4'b0010, i[2:0]};		// {tag_valid, mem_type, add_type, mul_type, div_type, 3'dID}
				data_out_valid = 1'b1;
			end
		end
	end

	// *** *** *** *** *** *** *** VISIBILITY INTO UNIT 1 *** *** *** *** *** *** *** //
	wire zCDB_offload_u1 = CDB_offload[0];
	wire [00:0] zmult_busy_u1 = mult_busy[0];		
	wire [02:0] zmult_cntr_u1 = mult_cntr[0];
	
	wire [00:0] zsrc1_valid_u1 = src1_valid[0];
	wire [07:0] zsrc1_intag_u1 = src1_intag[0];
	wire [31:0] zsrc1_value_u1 = src1_value[0];

	wire [00:0] zsrc2_valid_u1 = src2_valid[0];
	wire [07:0] zsrc2_intag_u1 = src2_intag[0];
	wire [31:0] zsrc2_value_u1 = src2_value[0];
endmodule
