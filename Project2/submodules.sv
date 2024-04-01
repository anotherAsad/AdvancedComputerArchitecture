`default_nettype none

function tag_match(input [7:0] tagA, tagB);
	tag_match = (tagA[7] && tagB[7]) && (tagA == tagB);
endfunction

`include "MemoryUnit.sv"
`include "AdderReservationStation.sv"
`include "MultiplierReservationStation.sv"
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
	output wire instr1_ismem, instr1_isadd, instr1_ismul,		// one-hot
	output wire instr2_ismem, instr2_isadd, instr2_ismul,		// one-hot
	input  wire CDB_issued_stall,							// dispatch stall from CDB_arbitrator should end up here.
	// status of reservation stations
	input  wire mem_ready, adder_ready, multiplier_ready
);
	reg  [02:0] instr1_type, instr2_type;

	// ascertain if instruction 1 is consumable.
	wire instr1_ready_if_mem = (instr1_type == 2'b00) && mem_ready;
	wire instr1_ready_if_add = (instr1_type == 2'b10) && adder_ready;
	wire instr1_ready_if_mul = (instr1_type == 2'b11) && multiplier_ready;

	wire instr1_consumable = instr1_ready_if_mem | instr1_ready_if_add | instr1_ready_if_mul;

	// ascertain if instruction 2 is consumable.
	wire instr2_ready_if_mem = (instr2_type == 2'b00) && !(instr1_type == 2'b00) && mem_ready;		// will cause instr2 to lag if instr1 is mem type
	wire instr2_ready_if_add = (instr2_type == 2'b10) && !(instr1_type == 2'b10) && adder_ready;	// will cause instr2 to lag if instr1 is add type
	wire instr2_ready_if_mul = (instr2_type == 2'b11) && !(instr1_type == 2'b11) && multiplier_ready;

	// STALLS FOR HAZARD AVOIDANCE 
	// Ensure that two instructions with same destination are not issued at once.
	// Ensure that ins2 doesn't use instr1_rd as as instr2_rs1 or instr2_rs2. This will cause wrong rs fetch by ins2.
	wire instr_destination_conflict = (
		(instr1_rd == instr2_rd) |
		((instr2_type != 2'b00) & (instr1_rd == instr2_rs1)) |			// ins2 is not a mem instr and still has the conflict.
		((instr2_type != 2'b00) & (instr1_rd == instr2_rs2))			// ins2 is not a mem instr and still has the conflict.
	);

	wire instr2_consumable = !instr_destination_conflict && (instr2_ready_if_mem | instr2_ready_if_add | instr2_ready_if_mul);

	// an instruction is valid if it is consumable and there is the CDB bus does not have any pending writes.
	assign instr1_valid = instr1_consumable & ~CDB_issued_stall;
	assign instr2_valid = instr2_consumable & ~CDB_issued_stall;
	assign shift_count = {instr2_valid, instr1_valid};		// outputs in one-hot encoding

	// *** *** *** *** Decoder Wire-up *** *** *** *** //
	// preliminary decoder wire-up
	wire [2:0] instr1_funct3 = instr1[14:12];
	wire [6:0] instr1_opcode = instr1[06:00];

	wire [2:0] instr2_funct3 = instr2[14:12];
	wire [6:0] instr2_opcode = instr2[06:00];

	always @(*) begin
		case({instr1_funct3, instr1_opcode})
			{3'b010, 7'b0000011}: instr1_type = 2'b00;		// ld
			{3'b011, 7'b0100011}: instr1_type = 2'b01;		// sd
			{3'b000, 7'b0110011}: instr1_type = instr1[25] ? 2'b11 : 2'b10;
			// {3'b000, 7'b0110111}: instr1_type = 2'b11;		// mul
			default: instr1_type = 3'b100;
		endcase

		case({instr2_funct3, instr2_opcode})
			{3'b010, 7'b0000011}: instr2_type = 2'b00;		// ld
			{3'b011, 7'b0100011}: instr2_type = 2'b01;		// sd
			{3'b000, 7'b0110011}: instr2_type = instr2[25] ? 2'b11 : 2'b10;		// func7[0] ? mul : add
			// {3'b000, 7'b0110111}: instr2_type = 2'b11;		// mul
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

// 1. Arbitrates CDB outputs, and 2. chooses right tags for reg_file rd renaming.
module CDB_arbitrator(
	output wire dispatch_stall,				// stall further dispatches in case of multiple CDB writes.
	// Effective CDB resolved tag and data.
	output reg  [07:0] tag_in_effect,
	output reg  [31:0] data_in_effect,
	input  wire [07:0] CDB_tag_multiplier, CDB_tag_adder, CDB_tag_mem,		// CDB resolved tag input
	input  wire [31:0] CDB_data_multiplier, CDB_data_adder, CDB_data_mem,	// CDB resolved data input
	// rd_tag interface.
	input  wire instr1_isadd, instr1_ismul, instr1_ismem,	// instruction 1 flags for valid instruction type. One-hot: Only 1 is true.
	input  wire instr2_isadd, instr2_ismul, instr2_ismem,	// instruction 2 flags for valid instruction type. One-hot: Only 1 is true.
	input  wire [07:0] acceptor_tag_add, acceptor_tag_mul, acceptor_tag_mem, 
	output reg  [07:0] regfile_rd_tag_A, regfile_rd_tag_B, 		// regfile bound rd tags
	// misc. signals
	input  wire en, clk, reset
);
	// assert dispatch stall if more than two tags are valid. The following assigmnent implements the truth table for stalls
	assign dispatch_stall = CDB_tag_multiplier[7] ? (CDB_tag_adder [7] | CDB_tag_mem[7]) : (CDB_tag_adder [7] & CDB_tag_mem[7]);

	// *** *** *** *** CDB BUS MUX *** *** *** *** //
	// Effective tag mux. Do not worry about hazards, register renaming/tagging at decode time has taken care of it.
	always @(*) begin
		if(CDB_tag_multiplier[7]) begin
			tag_in_effect  <= CDB_tag_multiplier;
			data_in_effect <= CDB_data_multiplier;
		end
		else if(CDB_tag_adder[7]) begin
			tag_in_effect  <= CDB_tag_adder;
			data_in_effect <= CDB_data_adder;
		end
		else if(CDB_tag_mem[7]) begin
			tag_in_effect  <= CDB_tag_mem;
			data_in_effect <= CDB_data_mem;
		end
		else begin
			tag_in_effect  <= 8'd0;
			data_in_effect <= 32'd0;
		end
	end

	// *** *** *** *** RD TAG ROUTING *** *** *** *** //
	// if instruction 1 is valid, choose the correct tag routs && assert valid signal to the required operational unit.
	always @(*) begin 
		if(instr1_isadd)
			regfile_rd_tag_A = acceptor_tag_add;
		else if(instr1_ismul)
			regfile_rd_tag_A = acceptor_tag_mul;
		else if(instr1_ismem)
			regfile_rd_tag_A = acceptor_tag_mem;
		else
			regfile_rd_tag_A = 8'd0;

		if(instr2_isadd)
			regfile_rd_tag_B = acceptor_tag_add;
		else if(instr2_ismul)
			regfile_rd_tag_B = acceptor_tag_mul;
		else if(instr2_ismem)
			regfile_rd_tag_B = acceptor_tag_mem;
		else
			regfile_rd_tag_B = 8'd0;
	end
endmodule

/*	dispatch_stall truth table
		* + m | stall
		0 0 0 = 0
		0 0 1 = 0
		0 1 0 = 0
		0 1 1 = 1
		1 0 0 = 0
		1 0 1 = 1
		1 1 0 = 1
		1 1 1 = 1
*/