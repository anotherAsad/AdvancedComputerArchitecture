module arbiter(
	// LXa interface
	input  wire [031:0] mem_addr_a,
	input  wire [127:0] cacheline_wr_a,
	input  wire rden_a, wren_a,
	output wire [127:0] cacheline_rd_a,
	output wire cacheline_rd_valid_a,
	input  wire LXa_responding,
	// LXb interface
	input  wire [031:0] mem_addr_b,
	input  wire [127:0] cacheline_wr_b,
	input  wire rden_b, wren_b,
	output wire [127:0] cacheline_rd_b,
	output wire cacheline_rd_valid_b,
	input  wire LXb_responding,
	// memory interface
	input  wire client_id,						// used for returning read requests. Tells about who the issuing client was. 1 for B, 0 for A.
	output reg  client_id_downstream,
	output wire downstream_enable,
	output reg  [031:0] mem_addr_out,
	output reg  [127:0] downstream_cacheline,
	output reg  rden_out, wren_out,
	input  wire [127:0] upstream_cacheline,
	input  wire incoming_cacheline_valid,
	// misc. signals
	output reg  downstream_buffer_filled,
	input  wire clk, reset
);
	// Snooper based data-routing || hotlink datapath.
	assign cacheline_rd_a = LXb_responding ? cacheline_wr_b : upstream_cacheline;
	assign cacheline_rd_b = LXa_responding ? cacheline_wr_a : upstream_cacheline;

	// disable downstream if upstream is in a private conflict resolution
	assign downstream_enable = ~(LXb_responding | LXb_responding);

	// *** *** *** Downstream Arbitration *** *** *** //
	reg  [128+32+2-1:0] downstream_buffer;

	// MAIN IDEA: If two requests arrive together, one of them goes to the waiting buffer. downstream_buffer_filled goes high.
	// WARN: utilized if two requests arrive at once. In this case back pressure MUST be asserted to let upstream know that further requests are absolute no-no.
	always @(posedge clk) begin
		if(reset)
			{downstream_buffer_filled, downstream_buffer} <= 163'd0;
		else if((wren_a | rden_a) & (wren_b | rden_b)) begin
			downstream_buffer_filled <= 1'b1;
			downstream_buffer <= {rden_b, wren_b, mem_addr_b, cacheline_wr_b};
		end
		else begin
			downstream_buffer_filled <= 1'b0;
			downstream_buffer <= 160'd0;
		end
	end

	always @(*) begin
		if(downstream_buffer_filled) begin						// if downstream buffer filled -> Prioritise buffer
			client_id_downstream = 1'd1;									// because downstream buffer only saves requests from B
			{rden_out, wren_out, mem_addr_out, downstream_cacheline} <= downstream_buffer;
		end
		else if(~(wren_a | rden_a) & (wren_b | rden_b)) begin		// if request is only from B   -> issue B
			client_id_downstream = 1'd1;
			{rden_out, wren_out, mem_addr_out, downstream_cacheline} <= {rden_b, wren_b, mem_addr_b, cacheline_wr_b};
		end
		else begin												// if request is only from A, or if it is from both A and B (or from neither) ->  Prioritise A
			client_id_downstream = 1'd0;
			{rden_out, wren_out, mem_addr_out, downstream_cacheline} <= {rden_a, wren_a, mem_addr_a, cacheline_wr_a};
		end
	end
	
	// *** *** *** Upstream Arbitration *** *** *** //
	assign cacheline_rd_a = upstream_cacheline;
	assign cacheline_rd_b = upstream_cacheline;

	// Simply assert the valid signal for the L1 cache with the correct ID.
	assign cacheline_rd_valid_a = incoming_cacheline_valid & (client_id == 1'd0);
	assign cacheline_rd_valid_b = incoming_cacheline_valid & (client_id == 1'd1);
endmodule
