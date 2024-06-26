`include "cache.v"
`include "snooper.v"

/*	INTENT OF DESIGN
1. Relays signals from both caches to each other.
2. Buffers/arbitrates between read/write requests of both L1s bound for L2.
*/

// magic memory. Can accept reads at any time. Releases random valid outputs after a fixed clock cycles of rden.
// consume writes to oblivion. Release fake results after a few cycles.
module memory(
	output reg  [127:0] data_out,
	output wire data_out_valid,
	input  wire [127:0] data_in,
	input  wire [031:0] addr_in,
	input  wire rden, wren,
	// misc. signals
	input  wire client_id_in,
	output wire client_id_out,
	input  wire en,
	input  wire clk, reset
);
	integer i;
	parameter DELAY = 5;
	
	reg [127:0] gbg_data = 128'hFB63DA9647CC13DC9913FA22DEADBEEF;
	
	reg [1:0] delay_line [0:DELAY];
	
	// alias the input 
	always @(*) delay_line[0] = {client_id_in, rden};
	
	always @(posedge clk) begin
		for(i=DELAY; i>0; i -= 1) begin
			if(reset)
				delay_line[i] <= 0;
			else if(en)
				delay_line[i] <= delay_line[i-1];
		end
	end
	
	assign data_out_valid = delay_line[DELAY][0];
	assign client_id_out  = delay_line[DELAY][1];
	
	always @(posedge clk) begin
		if(reset)
			data_out <= 128'd0;
		else if(en) begin
			if(delay_line[DELAY-1][0])
				data_out <= gbg_data ^ {data_out[126:0], data_out[127]};
		end
	end
endmodule

// Wraps two L1s and a snooper. Provides interface to a memory.
module L1_complex(
	// cpu-cache interface
	output wire interface_ready_a, interface_ready_b,
	output wire [31:0] data_out_a, data_out_b,
	output wire data_out_valid_a, data_out_valid_b,
	input  wire [31:0] data_in_a, data_in_b,
	input  wire [31:0] addr_in_a, addr_in_b,			// 2 LSbits are essentially useless.
	input  wire rden_a, rden_b, wren_a, wren_b,
	// snooper-downstream interface
	output wire [031:0] mem_addr_StoD,		// StoD is snooper to Downstream
	output wire [127:0] cacheline_StoD,
	input  wire [127:0] cacheline_DtoS,
	output wire wren_StoD, rden_StoD,
	input  wire valid_DtoS,
	output wire downstream_enable,
	input  wire client_id_DtoS,
	output wire client_id_StoD,
	// misc. signals
	output wire pause_processors,
	input  wire clk, reset
);
	// cache-snooper interface
	wire [031:0] mem_addr_a, mem_addr_b;
	wire [127:0] evictable_cacheline_a, evictable_cacheline_b;
	wire eviction_wren_a, mem_read_valid_a;
	wire eviction_wren_b, mem_read_valid_b;
	wire [127:0] updated_cacheline_a, updated_cacheline_b;
	wire cacheline_update_valid_a, cacheline_update_valid_b;
	
	// hotlink wireup
	wire [31:0] hotlink_addr_AtoB, hotlink_addr_BtoA;
	wire hotlink_invl_AtoB, hotlink_read_AtoB;
	wire hotlink_invl_BtoA, hotlink_read_BtoA;
	wire hotlink_wren_AtoB, hotlink_wren_BtoA;

	wire valid_interrupt_received_a, valid_interrupt_received_b;
	wire hotlink_interrupt_a, hotlink_interrupt_b;

	interrupt_arbiter interrupt_arbiter_inst(
		.hotlink_interrupt_L1a(hotlink_interrupt_a),
		.hotlink_interrupt_L1b(hotlink_interrupt_b),
		.irq_L1a(valid_interrupt_received_a),
		.irq_L1b(valid_interrupt_received_b)
	);

	L1_cache L1a(
		.interface_ready(interface_ready_a),
		.data_out(data_out_a),
		.data_out_valid(data_out_valid_a),
		.data_in(data_in_a),
		.addr_in(addr_in_a),			// 2 LSbits are essentially useless.
		.rden(rden_a), .wren(wren_a),
		// cache-snooper interface
		.snooper_addr(mem_addr_a),
		.evictable_cacheline(evictable_cacheline_a),
		.eviction_wren(eviction_wren_a),
		.snooper_read_valid(mem_read_valid_a),
		.updated_cacheline(updated_cacheline_a),
		.cacheline_update_valid(cacheline_update_valid_a),		// also serves as an address override.
		// hotlink input port
		.hotlink_addr_in(hotlink_addr_BtoA),		// used only for invalidation and read.
		.hotlink_invl_in(hotlink_invl_BtoA),
		.hotlink_read_in(hotlink_read_BtoA),
		.hotlink_wren_out(hotlink_wren_AtoB),				// responds with data on 'evictable cacheline' if read request matches.
		// hotlink output port
		.hotlink_addr_out(hotlink_addr_AtoB),		// used only for invalidation and read.
		.hotlink_invl_out(hotlink_invl_AtoB),
		.hotlink_read_out(hotlink_read_AtoB),
		.hotlink_wren_in(hotlink_wren_BtoA),				// tells if there was a horizontal hit, and the neighbor returned data
		// misc. signals
		.valid_interrupt_received(valid_interrupt_received_a),
		.hotlink_interrupt(hotlink_interrupt_a),
		.clk(clk), .reset(reset)
	);

	L1_cache L1b(
		.interface_ready(interface_ready_b),
		.data_out(data_out_b),
		.data_out_valid(data_out_valid_b),
		.data_in(data_in_b),
		.addr_in(addr_in_b),			// 2 LSbits are essentially useless.
		.rden(rden_b), .wren(wren_b),
		// cache-snooper interface
		.snooper_addr(mem_addr_b),
		.evictable_cacheline(evictable_cacheline_b),
		.eviction_wren(eviction_wren_b),
		.snooper_read_valid(mem_read_valid_b),
		.updated_cacheline(updated_cacheline_b),
		.cacheline_update_valid(cacheline_update_valid_b),		// also serves as an address override.
		// hotlink input port
		.hotlink_addr_in(hotlink_addr_AtoB),		// used only for invalidation and read.
		.hotlink_invl_in(hotlink_invl_AtoB),
		.hotlink_read_in(hotlink_read_AtoB),
		.hotlink_wren_out(hotlink_wren_BtoA),				// responds with data on 'evictable cacheline' if read request matches.
		// hotlink output port
		.hotlink_addr_out(hotlink_addr_BtoA),		// used only for invalidation and read.
		.hotlink_invl_out(hotlink_invl_BtoA),
		.hotlink_read_out(hotlink_read_BtoA),
		.hotlink_wren_in(hotlink_wren_AtoB),				// tells if there was a horizontal hit, and the neighbor returned data
		// misc. signals
		.valid_interrupt_received(valid_interrupt_received_b),
		.hotlink_interrupt(hotlink_interrupt_b),
		.clk(clk), .reset(reset)
	);

	arbiter arbiter_L1(
		// LXa interface
		.mem_addr_a(mem_addr_a),
		.cacheline_wr_a(evictable_cacheline_a),
		.rden_a(mem_read_valid_a),
		.wren_a(eviction_wren_a),
		.cacheline_rd_a(updated_cacheline_a),
		.cacheline_rd_valid_a(cacheline_update_valid_a),
		.LXa_responding(hotlink_wren_AtoB),
		// LXb interface
		.mem_addr_b(mem_addr_b),
		.cacheline_wr_b(evictable_cacheline_b),
		.rden_b(mem_read_valid_b),
		.wren_b(eviction_wren_b),
		.cacheline_rd_b(updated_cacheline_b),
		.cacheline_rd_valid_b(cacheline_update_valid_b),
		.LXb_responding(hotlink_wren_BtoA),
		// memory interface
		.client_id(client_id_DtoS),						// used for returning read requests. Tells about who the issuing client was. 1 for B, 0 for A.
		.client_id_downstream(client_id_StoD),
		.downstream_enable(downstream_enable),
		.mem_addr_out(mem_addr_StoD),
		.downstream_cacheline(cacheline_StoD),
		.rden_out(rden_StoD),
		.wren_out(wren_StoD),
		.upstream_cacheline(cacheline_DtoS),
		.incoming_cacheline_valid(valid_DtoS),
		// misc. signals
		.downstream_buffer_filled(pause_processors),			// is an output signal to the processors
		.clk(clk), .reset(reset)
	);

endmodule

module testbench;
	integer i = 0;
	integer instr_count = 0;
	reg clk, reset;
	
	// cpu-cache interface
	wire interface_ready_a, interface_ready_b;
	wire [31:0] data_out_a, data_out_b;
	wire data_out_valid_a, data_out_valid_b;
	reg  [31:0] data_in_a, data_in_b;
	reg  [31:0] addr_in_a, addr_in_b;			// 2 LSbits are essentially useless.
	reg  rden_a, rden_b, wren_a, wren_b;

	// Snooper-memory bindings
	wire [031:0] mem_addr_StoD;		// StoD is snooper to Downstream
	wire [127:0] cacheline_StoD, cacheline_DtoS; 
	wire wren_StoD, rden_StoD, valid_DtoS;
	wire downstream_enable;
	wire client_id_StoD, client_id_DtoS;

	wire pause_processors;

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
		.mem_addr_StoD(mem_addr_StoD),		// StoD is snooper to Downstream
		.cacheline_StoD(cacheline_StoD),
		.cacheline_DtoS(cacheline_DtoS),
		.wren_StoD(wren_StoD),
		.rden_StoD(rden_StoD),
		.valid_DtoS(valid_DtoS),
		.downstream_enable(downstream_enable),
		.client_id_DtoS(client_id_DtoS),
		.client_id_StoD(client_id_StoD),
		// misc. signals
		.pause_processors(pause_processors),
		.clk(clk), .reset(reset)
	);

	memory memory_inst(
		.data_out(cacheline_DtoS),
		.data_out_valid(valid_DtoS),
		.data_in(cacheline_StoD),
		.addr_in(mem_addr_StoD),
		.rden(rden_StoD),
		.wren(wren_StoD),
		.en(downstream_enable),
		// misc. signals
		.client_id_in(client_id_StoD),
		.client_id_out(client_id_DtoS),
		.clk(clk),
		.reset(reset)
	);

	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(0, testbench);

		
		addr_in_a = 0;
		rden_a = 0; wren_a = 0;
		data_in_a = $random;

		addr_in_b = 0;
		rden_b = 0; wren_b = 0;
		data_in_b = $random;

		#0 clk = 0; reset = 0;
		#1 reset = 1;
		#1 clk = 1;
		#1 clk = 0;
		#1 reset = 0;

		repeat(2000) begin
			#1 clk = ~clk;
			#0.1 i = i+1;
			#0.1 instr_count = i/10;

			if(i % 10 == 0) begin
				// every case match is an instruction number.
				case(instr_count)
					
					1: begin
						// A: read 0x10
						addr_in_a = {13'h10, 4'b0000};
						rden_a = 1; wren_a = 0;
						data_in_a = 32'h0;

						addr_in_b = 0;
						rden_b = 0; wren_b = 0;
						data_in_b = 0;
					end

					2: begin
						// A: write 0x10
						addr_in_a = {13'h10, 4'b0000};
						rden_a = 0; wren_a = 1;
						data_in_a = 32'hDEADBEEF;

						addr_in_b = 0;
						rden_b = 0; wren_b = 0;
						data_in_b = 0;
					end

					3: begin
						// B: read 0x10
						addr_in_a = 0;
						rden_a = 0; wren_a = 0;
						data_in_a = 32'hDEADBEEF;

						addr_in_b = {13'h10, 4'b0000};
						rden_b = 1; wren_b = 0;
						data_in_b = 0;
					end

					4: begin
						// B: write 0x10
						addr_in_a = 0;
						rden_a = 0; wren_a = 0;
						data_in_a = 32'hDEADBEEF;

						addr_in_b = {13'h10, 4'b0000};
						rden_b = 0; wren_b = 1;
						data_in_b = 32'hBAADBEEF;;
					end
					// extender
					default: begin
						addr_in_a = 0;
						rden_a = 0; wren_a = 0;
						data_in_a = $random;

						addr_in_b = 0;
						rden_b = 0; wren_b = 0;
						data_in_b = $random;
					end
				endcase
			end

			else begin
				addr_in_a = addr_in_a;
				rden_a = 0; wren_a = 0;
				data_in_a = data_in_a;

				addr_in_b = addr_in_b;
				rden_b = 0; wren_b = 0;
				data_in_b = data_in_b;
			end


			#1 clk = ~clk;
		end


	end
endmodule

