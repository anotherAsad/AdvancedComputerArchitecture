`default_nettype none

function tag_match(input [7:0] tagA, tagB);
	tag_match = (tagA[7] && tagB[7]) && (tagA == tagB);
endfunction

`include "MemoryUnit.sv"
`include "AdderReservationStation.sv"
`include "MultiplierReservationStation.sv"
`include "DividerReservationStation.sv"
`include "RegisterFile.sv"
`include "instruction_queue.sv"

// 1. Dispatch controller for upstream instruction queue.
// checks if instr1 can be consumed. If yes, checks if instr2 can be consumed.
// Asserts corresponding shift_count to instruction_queue.
// 2. Decoder for downstream units & CDB bus.
// Decodes instructions for operational units.
module dispatch_and_decode_unit(
	// instr queue interface
	input  wire [31:0] instr1, instr2,
	output wire [1:0] shift_count,
	// decoder interface out. Primarily towards Register File
	output wire [04:0] instr1_rd,  instr2_rd,
	output wire [04:0] instr1_rs1, instr2_rs1,
	output wire [04:0] instr1_rs2, instr2_rs2,
	output wire instr1_valid, instr2_valid,
	// CDB arbitrator interface
	output wire instr1_ismem, instr1_isadd, instr1_ismul, instr1_isdiv,		// one-hot
	output wire instr2_ismem, instr2_isadd, instr2_ismul, instr2_isdiv,		// one-hot
	// status of reservation stations
	input  wire mem_ready, adder_ready, multiplier_ready, divider_ready
);
	reg  [02:0] instr1_type, instr2_type;

	// ascertain if instruction 1 is consumable.
	wire instr1_ready_if_mem = (instr1_type == 3'b000) && mem_ready;
	wire instr1_ready_if_add = (instr1_type == 3'b010) && adder_ready;
	wire instr1_ready_if_mul = (instr1_type == 3'b011) && multiplier_ready;
	wire instr1_ready_if_div = (instr1_type == 3'b111) && divider_ready;

	wire instr1_consumable = instr1_ready_if_mem | instr1_ready_if_add | instr1_ready_if_mul | instr1_ready_if_div;

	// ascertain if instruction 2 is consumable.
	wire instr2_ready_if_mem = (instr2_type == 3'b000) && !(instr1_type == 3'b000) && mem_ready;		// will cause instr2 to lag if instr1 is mem type
	wire instr2_ready_if_add = (instr2_type == 3'b010) && !(instr1_type == 3'b010) && adder_ready;	// will cause instr2 to lag if instr1 is add type
	wire instr2_ready_if_mul = (instr2_type == 3'b011) && !(instr1_type == 3'b011) && multiplier_ready;
	wire instr2_ready_if_div = (instr2_type == 3'b111) && !(instr1_type == 3'b111) && divider_ready;

	// STALLS FOR HAZARD AND RACE CONDITION AVOIDANCE 
	// Ensure that two instructions with same destination are not issued at once.
	// Ensure that ins2 doesn't use instr1_rd as as instr2_rs1 or instr2_rs2. This will cause wrong rs fetch by ins2.
	wire instr_destination_conflict = (
		(instr1_rd == instr2_rd) |
		((instr2_type != 3'b000) & (instr1_rd == instr2_rs1)) |			// ins2 is not a mem instr and still has the conflict.
		((instr2_type != 3'b000) & (instr1_rd == instr2_rs2))			// ins2 is not a mem instr and still has the conflict.
	);

	wire instr2_consumable = !instr_destination_conflict && (instr2_ready_if_mem | instr2_ready_if_add | instr2_ready_if_mul | instr2_ready_if_div);

	// Used to have a CDB issued stall mask. Not needed with parallel implementation.
	assign instr1_valid = instr1_consumable;
	assign instr2_valid = instr2_consumable;
	assign shift_count = {instr2_valid, instr1_valid};		// outputs in one-hot encoding

	// *** *** *** *** Decoder Wire-up *** *** *** *** //
	// preliminary decoder wire-up
	wire [2:0] instr1_funct3 = instr1[14:12];
	wire [6:0] instr1_opcode = instr1[06:00];

	wire [2:0] instr2_funct3 = instr2[14:12];
	wire [6:0] instr2_opcode = instr2[06:00];

	always @(*) begin
		case({instr1_funct3, instr1_opcode})
			{3'b010, 7'b0000011}: instr1_type = 3'b000;		// ld
			{3'b011, 7'b0100011}: instr1_type = 3'b001;		// sd
			{3'b000, 7'b0110011}: instr1_type = instr1[25] ? 3'b011 : 3'b010;	// func7[0] ? mul : add
			{3'b100, 7'b0110011}: instr1_type = 3'b111;		// div
			default: instr1_type = 3'b100;
		endcase

		case({instr2_funct3, instr2_opcode})
			{3'b010, 7'b0000011}: instr2_type = 2'b00;		// ld
			{3'b011, 7'b0100011}: instr2_type = 2'b01;		// sd
			{3'b000, 7'b0110011}: instr2_type = instr2[25] ? 2'b11 : 2'b10;		// func7[0] ? mul : add
			{3'b100, 7'b0110011}: instr2_type = 3'b111;		// div
			default: instr2_type = 3'b100;
		endcase
	end

	// register wire-up
	assign instr1_rd = instr1[11:7];
	assign instr2_rd = instr2[11:7];

	assign instr1_rs1 = instr1[19:15];
	assign instr2_rs1 = instr2[19:15];

	assign instr1_rs2 = instr1[24:20];
	assign instr2_rs2 = instr2[24:20];

	// operational unit control
	assign instr1_ismem = instr1_valid & instr1_ready_if_mem;
	assign instr2_ismem = instr2_valid & instr2_ready_if_mem;

	assign instr1_isadd = instr1_valid & instr1_ready_if_add;
	assign instr2_isadd = instr2_valid & instr2_ready_if_add;

	assign instr1_ismul = instr1_valid & instr1_ready_if_mul;
	assign instr2_ismul = instr2_valid & instr2_ready_if_mul;

	assign instr1_isdiv = instr1_valid & instr1_ready_if_div;
	assign instr2_isdiv = instr2_valid & instr2_ready_if_div;
endmodule

module source_mux(
	input  wire [31:0] instr1_rs1, instr1_rs2,		// has tag in lower byte if needed
	input  wire instr1_dtype_rs1, instr1_dtype_rs2,
	input  wire [31:0] instr2_rs1, instr2_rs2,		// has tag in lower byte if needed
	input  wire instr2_dtype_rs1, instr2_dtype_rs2,
	output reg  [31:0] rs1, rs2,
	output reg  dtype_rs1, dtype_rs2,
	input  wire instr1_active, instr2_active
);
	// instr1 is the default case
	always @(*) begin
		if(instr2_active) begin
			rs1 <= instr2_rs1;
			rs2 <= instr2_rs2;
			dtype_rs1 <= instr2_dtype_rs1;
			dtype_rs2 <= instr2_dtype_rs2;
		end
		else begin
			rs1 <= instr1_rs1;
			rs2 <= instr1_rs2;
			dtype_rs1 <= instr1_dtype_rs1;
			dtype_rs2 <= instr1_dtype_rs2;
		end
	end
endmodule

// 1. organizes CDB outputs, and 2. chooses right tags for reg_file rd renaming.
module CDB_bus_controller(
	// Effective CDB resolved tag and data.
	output wire [031:0] CDB_tag_serialized,
	output wire [127:0] CDB_data_serialized,
	input  wire [007:0] CDB_tag_multiplier, CDB_tag_adder, CDB_tag_mem,	CDB_tag_divider,		// CDB resolved tag input
	input  wire [031:0] CDB_data_multiplier, CDB_data_adder, CDB_data_mem, CDB_data_divider,	// CDB resolved data input
	// rd_tag interface.
	input  wire instr1_isadd, instr1_ismul, instr1_ismem, instr1_isdiv,	// instruction 1 flags for valid instruction type. One-hot: Only 1 is true.
	input  wire instr2_isadd, instr2_ismul, instr2_ismem, instr2_isdiv,	// instruction 2 flags for valid instruction type. One-hot: Only 1 is true.
	input  wire [07:0] acceptor_tag_add, acceptor_tag_mul, acceptor_tag_mem, acceptor_tag_div,
	output reg  [07:0] regfile_rd_tag_A, regfile_rd_tag_B 		// regfile bound rd tags
);
	// *** *** *** *** CDB BUS routing *** *** *** *** //
	reg  [07:0] CDB_tag [0:3];
	reg  [31:0] CDB_data [0:3];

	// Effective tag routing. Do not worry about hazards, register renaming/tagging at decode time has taken care of it.
	always @(*) begin
		CDB_tag[0]  <= CDB_tag_multiplier;
		CDB_data[0] <= CDB_data_multiplier;
		CDB_tag[1]  <= CDB_tag_adder;
		CDB_data[1] <= CDB_data_adder;
		CDB_tag[2]  <= CDB_tag_mem;
		CDB_data[2] <= CDB_data_mem;
		CDB_tag[3]  <= CDB_tag_divider;
		CDB_data[3] <= CDB_data_divider;
	end

	assign CDB_tag_serialized  = {CDB_tag[0], CDB_tag[1], CDB_tag[2], CDB_tag[3]};
	assign CDB_data_serialized = {CDB_data[0], CDB_data[1], CDB_data[2], CDB_data[3]};

	// *** *** *** *** RD TAG ROUTING *** *** *** *** //
	// if instruction 1 is valid, choose the correct tag routs && assert valid signal to the required operational unit.
	always @(*) begin 
		if(instr1_isadd)
			regfile_rd_tag_A = acceptor_tag_add;
		else if(instr1_ismul)
			regfile_rd_tag_A = acceptor_tag_mul;
		else if(instr1_ismem)
			regfile_rd_tag_A = acceptor_tag_mem;
		else if(instr1_isdiv)
			regfile_rd_tag_A = acceptor_tag_div;
		else
			regfile_rd_tag_A = 8'd0;

		if(instr2_isadd)
			regfile_rd_tag_B = acceptor_tag_add;
		else if(instr2_ismul)
			regfile_rd_tag_B = acceptor_tag_mul;
		else if(instr2_ismem)
			regfile_rd_tag_B = acceptor_tag_mem;
		else if(instr2_isdiv)
			regfile_rd_tag_B = acceptor_tag_div;
		else
			regfile_rd_tag_B = 8'd0;
	end
endmodule