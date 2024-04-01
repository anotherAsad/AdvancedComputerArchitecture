`include "submodules.sv"

module testbench;
	// tomasulo_machine_wireup
	reg  clk, reset;

	// instruction queue
	wire [31:0] instr1, instr2;
	wire [01:0] shift_count;			// can be 0, 1 or 2. 2 is coded as 2'b10 or 2'b11. This means one-hot shift indexing works!

	instruction_queue instruction_queue_inst(
		.instr1(instr1), .instr2(instr2),
		.shift_count(shift_count),
		.clk(clk), .reset(reset) 
	);

	// decoder interface out
	wire [04:0] instr1_rd,  instr2_rd;
	wire [04:0] instr1_rs1, instr2_rs1;
	wire [04:0] instr1_rs2, instr2_rs2;
	wire instr1_valid, instr2_valid;
	// CDB arbitrator interface
	wire instr1_isadd, instr1_ismul, instr1_ismem;	// instruction 1 flags for valid instruction type. One-hot: Only 1 is true.
	wire instr2_isadd, instr2_ismul, instr2_ismem;	// instruction 2 flags for valid instruction type. One-hot: Only 1 is true.
	// status of reservation stations
	wire mem_ready, adder_ready, multiplier_ready;

	dispatch_and_decode_unit dispatch_and_decode_unit_inst(
		// instr queue interface
		.instr1(instr1), .instr2(instr2),
		.shift_count(shift_count),
		// decoder interface out
		.instr1_rd(instr1_rd), .instr2_rd(instr2_rd),
		.instr1_rs1(instr1_rs1), .instr2_rs1(instr2_rs1),
		.instr1_rs2(instr1_rs2), .instr2_rs2(instr2_rs2),
		.instr1_valid(instr1_valid), .instr2_valid(instr2_valid),
		// CDB arbitrator interface
		.instr1_ismem(instr1_ismem), .instr1_isadd(instr1_isadd), .instr1_ismul(instr1_ismul),		// one-hot
		.instr2_ismem(instr2_ismem), .instr2_isadd(instr2_isadd), .instr2_ismul(instr2_ismul),		// one-hot
		// status of reservation stations
		.mem_ready(mem_ready), .adder_ready(adder_ready), .multiplier_ready(multiplier_ready)
	);

	// Effective CDB resolved tag and data.
	wire [23:0] CDB_tag_serialized;
	wire [95:0] CDB_data_serialized;
	wire [07:0] CDB_tag_multiplier, CDB_tag_adder, CDB_tag_mem;				// CDB resolved tag input
	wire [31:0] CDB_data_multiplier, CDB_data_adder, CDB_data_mem;			// CDB resolved data input
	// rd_tag interface.
	wire [7:0] acceptor_tag_add, acceptor_tag_mul, acceptor_tag_mem; 
	wire [7:0] regfile_rd_tag_A, regfile_rd_tag_B; 		// regfile bound rd tags

	CDB_bus_controller CDB_bus_controller_inst(
		// Effective CDB resolved tag and data.
		.CDB_tag_serialized(CDB_tag_serialized),
		.CDB_data_serialized(CDB_data_serialized),
		// CDB resolved tag input
		.CDB_tag_multiplier(CDB_tag_multiplier),
		.CDB_tag_adder(CDB_tag_adder),
		.CDB_tag_mem(CDB_tag_mem),
		.CDB_data_multiplier(CDB_data_multiplier),
		.CDB_data_adder(CDB_data_adder),
		.CDB_data_mem(CDB_data_mem),
		// rd_tag interface.
		.instr1_isadd(instr1_isadd), .instr1_ismul(instr1_ismul), .instr1_ismem(instr1_ismem),	// instruction 1 flags for valid instruction type. One-hot: Only 1 is true.
		.instr2_isadd(instr2_isadd), .instr2_ismul(instr2_ismul), .instr2_ismem(instr2_ismem),	// instruction 2 flags for valid instruction type. One-hot: Only 1 is true.
		.acceptor_tag_add(acceptor_tag_add),
		.acceptor_tag_mul(acceptor_tag_mul),
		.acceptor_tag_mem(acceptor_tag_mem), 
		.regfile_rd_tag_A(regfile_rd_tag_A), .regfile_rd_tag_B(regfile_rd_tag_B)	// regfile bound rd tags
	);

	wire [31:0] dout_r1_A, dout_r2_A, dout_r1_B, dout_r2_B;
	wire dtype_r1_A, dtype_r2_A, dtype_r1_B, dtype_r2_B;

	RegisterFile RegisterFile_inst(
		// instruction port A
		.addr_r1_A(instr1_rs1), .addr_r2_A(instr1_rs2), .addr_rd_A(instr1_rd),
		.instr_valid_A(instr1_valid),
		.rd_tag_A(regfile_rd_tag_A),			// received from arbiter action
		.dout_r1_A(dout_r1_A), .dout_r2_A(dout_r2_A),
		.dtype_r1_A(dtype_r1_A), .dtype_r2_A(dtype_r2_A),		// 0 for data, 1 for tag.
		// instruction port B
		.addr_r1_B(instr2_rs1), .addr_r2_B(instr2_rs2), .addr_rd_B(instr2_rd),
		.instr_valid_B(instr2_valid),
		.rd_tag_B(regfile_rd_tag_B),			// received from arbiter action
		.dout_r1_B(dout_r1_B), .dout_r2_B(dout_r2_B),
		.dtype_r1_B(dtype_r1_B), .dtype_r2_B(dtype_r2_B),		// 0 for data, 1 for tag.
		// CDB input interface
		.CDB_data_serialized(CDB_data_serialized),				// comes from the CDB
		.CDB_tag_serialized(CDB_tag_serialized),
		// misc. signals.
		.en(1'b1), .clk(clk), .reset(reset)
	);

	// *** *** *** *** *** *** MEMORY SETUP *** *** *** *** *** *** //

	wire [31:0] data_in_mem;
	wire [31:0] addr_in_mem;
	wire wren = 1'b0;
	
	source_mux mem_source_mux(
		// instruction 1
		.instr1_rs1(dout_r1_A), .instr1_rs2({20'd0, instr1[31-:12]}),		// has tag in lower byte if needed
		.instr1_dtype_rs1(1'b0), .instr1_dtype_rs2(1'b0),
		// instruction 2
		.instr2_rs1(dout_r1_B), .instr2_rs2({20'd0, instr2[31-:12]}),		// has tag in lower byte if needed
		.instr2_dtype_rs1(1'b0), .instr2_dtype_rs2(1'b0),
		// mux output
		.rs1(data_in_mem), .rs2(addr_in_mem),
		.dtype_rs1(), .dtype_rs2(),
		// instruction sel
		.instr1_active(instr1_ismem),
		.instr2_active(instr2_ismem)
	);

	// mem_unit's tag is tagged as well.
	MemoryUnit MemoryUnit_inst(
		// CDB output interface
		.data_out_valid(),
		.data_out(CDB_data_mem),
		.reg_tag_out(CDB_tag_mem),
		// instruction input interface.
		.data_in(data_in_mem),
		.addr_in(addr_in_mem),
		.rden(instr1_ismem | instr2_ismem),
		.wren(wren),
		.ready_for_instr(mem_ready),
		.acceptor_tag(acceptor_tag_mem),
		.en(1'b1), .clk(clk), .reset(reset)
	);

	// *** *** *** *** *** *** ADDER SETUP *** *** *** *** *** *** //
	wire [31:0] rs1_add, rs2_add;
	wire dtype_rs1_add, dtype_rs2_add;

	source_mux add_source_mux(
		// instruction 1
		.instr1_rs1(dout_r1_A), .instr1_rs2(dout_r2_A),		// has tag in lower byte if needed
		.instr1_dtype_rs1(dtype_r1_A), .instr1_dtype_rs2(dtype_r2_A),
		// instruction 2
		.instr2_rs1(dout_r1_B), .instr2_rs2(dout_r2_B),		// has tag in lower byte if needed
		.instr2_dtype_rs1(dtype_r1_B), .instr2_dtype_rs2(dtype_r2_B),
		// mux output
		.rs1(rs1_add), .rs2(rs2_add),
		.dtype_rs1(dtype_rs1_add), .dtype_rs2(dtype_rs2_add),
		// instruction sel
		.instr1_active(instr1_isadd),
		.instr2_active(instr2_isadd)
	);

	AdditionReservationStation AdditionReservationStation_inst(
		// Register input interface
		.src_in_1(rs1_add), .src_in_2(rs2_add),							// comes from regfile. Lower 8 bits are used for tag if the regfile says so, else this is data.
		.src_in_valid(instr1_isadd | instr2_isadd),						// controlled by decoder.
		.src_in1_type(dtype_rs1_add), .src_in2_type(dtype_rs2_add),		// 0 for data, 1 for tag.
		// CDB input interface
		.CDB_data_serialized(CDB_data_serialized),				// comes from the CDB
		.CDB_tag_serialized(CDB_tag_serialized),
		// CDB data_out interface
		.data_out_valid(),
		.data_out(CDB_data_adder),
		.reg_tag_out(CDB_tag_adder),
		// dispatcher interface
		.ready_for_instr(adder_ready),
		.acceptor_tag(acceptor_tag_add),			// {tag_valid, mem_type, add_type, mul_type, 2'b0, 3'dID}
		// misc. signals
		.en(1'b1), .clk(clk), .reset(reset)
	);

	// *** *** *** *** *** *** MULTIPLIER SETUP *** *** *** *** *** *** //
	wire [31:0] rs1_mul, rs2_mul;
	wire dtype_rs1_mul, dtype_rs2_mul;

	source_mux mul_source_mux(
		// instruction 1
		.instr1_rs1(dout_r1_A), .instr1_rs2(dout_r2_A),		// has tag in lower byte if needed
		.instr1_dtype_rs1(dtype_r1_A), .instr1_dtype_rs2(dtype_r2_A),
		// instruction 2
		.instr2_rs1(dout_r1_B), .instr2_rs2(dout_r2_B),		// has tag in lower byte if needed
		.instr2_dtype_rs1(dtype_r1_B), .instr2_dtype_rs2(dtype_r2_B),
		// mux output
		.rs1(rs1_mul), .rs2(rs2_mul),
		.dtype_rs1(dtype_rs1_mul), .dtype_rs2(dtype_rs2_mul),
		// instruction sel
		.instr1_active(instr1_ismul),
		.instr2_active(instr2_ismul)
	);

	MultiplierReservationStation MultiplierReservationStation_inst(
		// Register input interface
		.src_in_1(rs1_mul), .src_in_2(rs2_mul),							// comes from regfile. Lower 8 bits are used for tag if the regfile says so, else this is data.
		.src_in_valid(instr1_ismul | instr2_ismul),						// controlled by decoder.
		.src_in1_type(dtype_rs1_mul), .src_in2_type(dtype_rs2_mul),		// 0 for data, 1 for tag.
		// CDB input interface
		.CDB_data_serialized(CDB_data_serialized),				// comes from the CDB
		.CDB_tag_serialized(CDB_tag_serialized),
		// CDB data_out interface
		.data_out_valid(),
		.data_out(CDB_data_multiplier),
		.reg_tag_out(CDB_tag_multiplier),
		// dispatcher interface
		.ready_for_instr(multiplier_ready),
		.acceptor_tag(acceptor_tag_mul),			// {tag_valid, mem_type, add_type, mul_type, 2'b0, 3'dID}
		// misc. signals
		.en(1'b1), .clk(clk), .reset(reset)
	);

	
	initial begin
		$dumpfile("test.vcd");
		$dumpvars(0, testbench);

		clk = 0; reset = 0;

		#1 reset = 1;
		#1 clk = 1; #1 clk = 0;
		#1 reset = 0;

		repeat(200)
			#1 clk = ~clk;
	end
endmodule

/*
module memory_testbench;
	integer i;

	wire data_out_valid;
	wire [31:0] data_out;
	wire [07:0] reg_tag_out;
	reg  [31:0] data_in;
	reg  [31:0] addr_in;
	reg  rden, wren;
	// dispatcher interface
	wire ready;
	wire [07:0] acceptor_tag;			// {tag_valid, mem_type, add_type, mul_type, 1'b0, 3'dID}
	// misc. signals
	reg  en, clk, reset;
	
	// mem_unit's tag is tagged as well.
	MemoryUnit MemoryUnit_inst(
		.data_out_valid(data_out_valid),
		.data_out(data_out),
		.reg_tag_out(reg_tag_out),
		.data_in(data_in),
		.addr_in(addr_in),
		.rden(rden), .wren(wren),
		.ready_for_instr(ready),
		.acceptor_tag(acceptor_tag),
		.en(en), .clk(clk), .reset(reset)
	);

	initial begin
		$dumpfile("test.vcd");
		$dumpvars(0, testbench);

		en = 0; clk = 0; reset = 0;

		wren = 0; rden = 0;

		#1 reset = 1;
		#1 clk = 1; #1 clk = 0;
		#1 reset = 0;

		addr_in = 0;
		en = 1; rden = 1;

		repeat(100) begin
			addr_in = addr_in + 1;
			#1 clk = ~clk; #1 clk = ~clk;
		end
	end
endmodule
*/