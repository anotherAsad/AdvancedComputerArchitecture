`include "L1_cache.v"
`include "L2_cache.v"
`include "snooper.v"
`include "complexes.v"

module testbench;
	integer i = 0;
	reg clk, reset;

	wire pause_processors = pause_processors_L1_a | pause_processors_L1_b | pause_processors_L2;
	
	// cpu-cache interface
	wire interface_ready_a, interface_ready_b;
	wire [31:0] data_out_a, data_out_b;
	wire data_out_valid_a, data_out_valid_b;
	reg  [31:0] data_in_a, data_in_b;
	reg  [31:0] addr_in_a, addr_in_b;			// 2 LSbits are essentially useless.
	reg  rden_a, rden_b, wren_a, wren_b;

	// Snooper-memory bindings
	wire [031:0] mem_addr_StoD_a;		// StoD is snooper to Downstream
	wire [127:0] cacheline_StoD_a, cacheline_DtoS_a; 
	wire wren_StoD_a, rden_StoD_a, valid_DtoS_a;
	wire downstream_enable_a;
	wire client_id_StoD_a, client_id_DtoS_a;

	wire pause_processors_L1_a, pause_processors_L1_b;

	// Wraps two L1s and a snooper. Provides interface to a memory.
	L1_complex L1_complex_a(
		// cpu-cache interface
		.interface_ready_a(interface_ready_a),
		.interface_ready_b(interface_ready_b),
		.data_out_a(data_out_a),
		.data_out_b(data_out_b),
		.data_out_valid_a(data_out_valid_a),
		.data_out_valid_b(data_out_valid_b),
		.data_in_a(data_in_a),
		.data_in_b(data_in_b),
		.addr_in_a(addr_in_a),				// 2 LSbits are essentially useless.
		.addr_in_b(addr_in_b),			
		.rden_a(rden_a), .rden_b(rden_b),
		.wren_a(wren_a), .wren_b(wren_b),
		// snooper-downstream interface
		.mem_addr_StoD(mem_addr_StoD_a),		// StoD is snooper to Downstream
		.cacheline_StoD(cacheline_StoD_a),
		.cacheline_DtoS(cacheline_DtoS_a),
		.wren_StoD(wren_StoD_a),
		.rden_StoD(rden_StoD_a),
		.valid_DtoS(valid_DtoS_a),
		.downstream_enable(downstream_enable_a),
		.client_id_DtoS(client_id_DtoS_a),
		.client_id_StoD(client_id_StoD_a),
		// misc. signals
		.pause_processors(pause_processors_L1_a),
		.clk(clk), .reset(reset)
	);

	// cpu-cache interface
	wire interface_ready_c, interface_ready_d;
	wire [31:0] data_out_c, data_out_d;
	wire data_out_valid_c, data_out_valid_d;
	reg  [31:0] data_in_c, data_in_d;
	reg  [31:0] addr_in_c, addr_in_d;			// 2 LSbits are essentially useless.
	reg  rden_c, rden_d, wren_c, wren_d;

	// Snooper-memory bindings
	wire [031:0] mem_addr_StoD_b;		// StoD is snooper to Downstream
	wire [127:0] cacheline_StoD_b, cacheline_DtoS_b; 
	wire wren_StoD_b, rden_StoD_b, valid_DtoS_b;
	wire downstream_enable_b;
	wire client_id_StoD_b, client_id_DtoS_b;

	// Wraps two L1s and a snooper. Provides interface to a memory.
	L1_complex L1_complex_b(
		// cpu-cache interface
		.interface_ready_a(interface_ready_c),
		.interface_ready_b(interface_ready_d),
		.data_out_a(data_out_c),
		.data_out_b(data_out_d),
		.data_out_valid_a(data_out_valid_c),
		.data_out_valid_b(data_out_valid_d),
		.data_in_a(data_in_c),
		.data_in_b(data_in_d),
		.addr_in_a(addr_in_c),				// 2 LSbits are essentially useless.
		.addr_in_b(addr_in_d),			
		.rden_a(rden_c), .rden_b(rden_d),
		.wren_a(wren_c), .wren_b(wren_d),
		// snooper-downstream interface
		.mem_addr_StoD(mem_addr_StoD_b),		// StoD is snooper to Downstream
		.cacheline_StoD(cacheline_StoD_b),
		.cacheline_DtoS(cacheline_DtoS_b),
		.wren_StoD(wren_StoD_b),
		.rden_StoD(rden_StoD_b),
		.valid_DtoS(valid_DtoS_b),
		.downstream_enable(downstream_enable_b),
		.client_id_DtoS(client_id_DtoS_b),
		.client_id_StoD(client_id_StoD_b),
		// misc. signals
		.pause_processors(pause_processors_L1_b),
		.clk(clk), .reset(reset)
	);

	//////////////////////// THIS IS THE LEVEL 2 ////////////////////////
	// Wraps two L2s and a snooper. Provides interface to a memory.
	wire interface_ready_L2_a, interface_ready_L2_b;
	// Snooper-memory bindings
	wire [031:0] mem_addr_StoD_L2;		// StoD is snooper to Downstream
	wire [127:0] cacheline_StoD_L2, cacheline_DtoS_L2; 
	wire wren_StoD_L2, rden_StoD_L2, valid_DtoS_L2;
	wire downstream_enable_L2;
	wire client_id_StoD_L2, client_id_DtoS_L2;

	wire pause_processors_L2;

	L2_complex L2_complex_b(
		// cpu-cache interface
		.client_id_in_a(client_id_StoD_a), .client_id_in_b(client_id_StoD_b),
		.client_id_out_a(client_id_DtoS_a), .client_id_out_b(client_id_DtoS_b),
		.interface_ready_a(interface_ready_L2_a),		// dummy
		.interface_ready_b(interface_ready_L2_b),		// dummy
		.data_out_a(cacheline_DtoS_a),
		.data_out_b(cacheline_DtoS_b),
		.data_out_valid_a(valid_DtoS_a),
		.data_out_valid_b(valid_DtoS_b),
		.data_in_a(cacheline_StoD_a),
		.data_in_b(cacheline_StoD_b),
		.addr_in_a(mem_addr_StoD_a),				// 2 LSbits are essentially useless.
		.addr_in_b(mem_addr_StoD_b),			
		.rden_a(rden_StoD_a), .rden_b(rden_StoD_b),
		.wren_a(wren_StoD_a), .wren_b(wren_StoD_b),
		// snooper-downstream interface
		.mem_addr_StoD(mem_addr_StoD_L2),		// StoD is snooper to Downstream
		.cacheline_StoD(cacheline_StoD_L2),
		.cacheline_DtoS(cacheline_DtoS_L2),
		.wren_StoD(wren_StoD_L2),
		.rden_StoD(rden_StoD_L2),
		.valid_DtoS(valid_DtoS_L2),
		.downstream_enable(downstream_enable_L2),
		.client_id_DtoS(client_id_DtoS_L2),
		.client_id_StoD(client_id_StoD_L2),
		// misc. signals
		.pause_processors(pause_processors_L2),
		.clk(clk), .reset(reset)
	);

	memory memory_inst(
		.data_out(cacheline_DtoS_L2),
		.data_out_valid(valid_DtoS_L2),
		.data_in(cacheline_StoD_L2),
		.addr_in(mem_addr_StoD_L2),
		.rden(rden_StoD_L2),
		.wren(wren_StoD_L2),
		.en(downstream_enable_L2),
		// misc. signals
		.client_id_in(client_id_StoD_L2),
		.client_id_out(client_id_DtoS_L2),
		.clk(clk),
		.reset(reset)
	);
	
	reg [15:0] temp [0:7];

	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(0, testbench);

		temp[0] = 16'hABCD;
		temp[1] = 16'h1234;
		temp[2] = 16'h3462;
		temp[3] = 16'h2398;
		temp[4] = 16'h2438;
		temp[5] = 16'h0974;
		temp[6] = 16'h6758;
		temp[7] = 16'hBF76;
		
		addr_in_a = 13'h2b1;
		rden_a = 0; wren_a = 0;
		data_in_a = $random;

		addr_in_b = 0;
		rden_b = 0; wren_b = 0;
		data_in_b = $random;

		addr_in_c = 0;
		rden_c = 0; wren_c = 0;
		data_in_c = $random;

		addr_in_d = 0;
		rden_d = 0; wren_d = 0;
		data_in_d = $random;


		#0 clk = 0; reset = 0;
		#1 reset = 1;
		#1 clk = 1;
		#1 clk = 0;
		#1 reset = 0;

		repeat(80000) begin
			#1 clk = ~clk;
			
			#0.1 i = i+1;
			
			// P_a action
			if(i % 10 == 0) begin
				addr_in_a = $random & 13'h1fff;
				rden_a = interface_ready_a & ~pause_processors ? 1 : 0;
			end
			else begin
				rden_a = 0;
				wren_a = 0;
			end

			// P_b action
			if(i % 10 == 1) begin
				addr_in_b = $random & 13'h1fff;
				rden_b = interface_ready_b & ~pause_processors ? 1 : 0;
			end
			else
				rden_b = 0;

			// P_c action
			if(i % 10 == 2) begin
				addr_in_c = $random & 13'h1fff;
				rden_c = interface_ready_c & ~pause_processors ? 1 : 0;
			end
			else
				rden_c = 0;

			// P_d action
			if(i % 10 == 3) begin
				addr_in_d = $random & 13'h1fff;
				rden_d = interface_ready_d & ~pause_processors ? 1 : 0;
			end
			else
				rden_d = 0;
				
			#1 clk = ~clk;
		end
		
		$finish;
	end
endmodule