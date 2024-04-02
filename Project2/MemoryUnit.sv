
// mem_unit is effectively a reservation station which takes every request if it can.
// Assuming all writes to be safe. Does not have a real input interface for CDB
module MemoryUnit(
	input  wire [31:0] data_in,
	input  wire [31:0] addr_in,
	input  wire rden, wren,
	// CDB output interface
	output reg  data_out_valid,
	output reg  [31:0] data_out,
	output reg  [07:0] reg_tag_out,
	// dispatcher interface
	output wire ready_for_instr,
	output wire [07:0] acceptor_tag,			// {tag_valid, mem_type, add_type, mul_type, div_type, 3'dID}
	// misc. signals
	input  wire en, clk, reset
);
	integer i;

	reg  [07:0] CDB_offload;

	// record keeping memory
	reg  [00:0] load_buffer_busy [0:7];
	reg  [15:0] load_buffer_addr [0:7];
	reg  [02:0] load_buffer_cntr [0:7];

	// *** *** *** *** *** *** TAG HANDLING *** *** *** *** *** *** //
	reg [03:0] acceptor_id;

	// priority encoder. Semi-clever.
	always @(*) begin
		acceptor_id = 8;			// no one is free. Tag is invalid.

		for(i=7; i>=0; i-=1)
			if(~load_buffer_busy[i])
				acceptor_id = i;
	end

	assign ready_for_instr = (acceptor_id != 4'd8);
	assign acceptor_tag = {ready_for_instr, 4'b1000, acceptor_id[2:0]};			// {tag_valid, mem_type, add_type, mul_type, div_type, 3'dID}

	// *** *** *** *** *** *** READ HANDLING *** *** *** *** *** *** //
	// writes are consumed to oblivion. Reads will emit a delayed random number.
	always @(posedge clk) begin
		for(i=0; i<8; i+=1) begin
			if(reset)
				{load_buffer_busy[i], load_buffer_addr[i], load_buffer_cntr[i]} <= {1'b0, 16'd0, 3'd0};
			else if(en) begin
				if(rden && (acceptor_id == i)) begin		// invalid acceptor id is automatically discarded.
					load_buffer_busy[i] <= 1'b1;
					load_buffer_addr[i] <= addr_in;
				end
				else if(load_buffer_busy[i]) begin									// Expect this to be mutually exclusive from the above if block.
					if(load_buffer_cntr[i] < 7)
						load_buffer_cntr[i] <= load_buffer_cntr[i] + 1;
					else if(CDB_offload[i]) begin
						load_buffer_busy[i] <= 1'b0;
						load_buffer_addr[i] <= 16'd0;
						load_buffer_cntr[i] <= 3'd0;
					end
				end
			end
		end
	end

	// *** *** *** *** *** *** CDB OFFLOADING *** *** *** *** *** *** //
	// priority decoder. Semi-clever.
	always @(*) begin
		// default value
		data_out = 32'd0;
		reg_tag_out = {1'b0, 3'b000, 1'b0, 3'b000};
		data_out_valid = 1'b0;

		for(i=0; i<8; i+=1) begin
			// if this unit is done working, and the sister unit is already free: raise the offload flag.
			CDB_offload[i] = !data_out_valid && load_buffer_busy[i] && (load_buffer_cntr[i] == 3'd7);

			// for corresponding offload flag, display data outside.
			if(CDB_offload[i]) begin
				data_out = load_buffer_addr[i];
				reg_tag_out = {1'b1, 4'b1000, i[2:0]};		// {tag_valid, mem_type, add_type, mul_type, div_type, 3'dID}
				data_out_valid = 1'b1;
			end
		end
	end
endmodule
