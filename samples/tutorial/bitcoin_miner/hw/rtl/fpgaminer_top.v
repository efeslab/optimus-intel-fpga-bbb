/*
*
* Copyright (c) 2011 fpgaminer@bitcoin-mining.com
*
*
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
* 
*/


`timescale 1ns/1ps

module fpgaminer_top (osc_clk, reset, d, md, n, gn, gn_v);

	// The LOOP_LOG2 parameter determines how unrolled the SHA-256
	// calculations are. For example, a setting of 0 will completely
	// unroll the calculations, resulting in 128 rounds and a large, but
	// fast design.
	//
	// A setting of 1 will result in 64 rounds, with half the size and
	// half the speed. 2 will be 32 rounds, with 1/4th the size and speed.
	// And so on.
	//
	// Valid range: [0, 5]
`ifdef CONFIG_LOOP_LOG2
	parameter LOOP_LOG2 = `CONFIG_LOOP_LOG2;
`else
	parameter LOOP_LOG2 = 3;
`endif

	// No need to adjust these parameters
	localparam [5:0] LOOP = (6'd1 << LOOP_LOG2);
	// The nonce will always be larger at the time we discover a valid
	// hash. This is its offset from the nonce that gave rise to the valid
	// hash (except when LOOP_LOG2 == 0 or 1, where the offset is 131 or
	// 66 respectively).
	localparam [31:0] GOLDEN_NONCE_OFFSET = (32'd1 << (7 - LOOP_LOG2)) + 32'd1;

	input osc_clk;
    input reset;
	input [255:0] d;
	input [255:0] md;
	output [31:0] n;
	output [31:0] gn;
    output gn_v;

	//// 
	reg [255:0] state;
	reg [511:0] data;
	reg [31:0] nonce;
	assign n = nonce;

	//// PLL
	wire hash_clk;
    assign hash_clk = osc_clk;


	//// Hashers
	wire [255:0] hash, hash2;
	reg [5:0] cnt;
	reg feedback;

	sha256_transform #(.LOOP(LOOP)) uut (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input(data),
		.tx_hash(hash)
	);
	sha256_transform #(.LOOP(LOOP)) uut2 (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash}),
		.tx_hash(hash2)
	);


	//// Virtual Wire Control
	reg [255:0] midstate_buf, data_buf;
	//wire [255:0] midstate_vw, data2_vw;


	//// Virtual Wire Output
	reg [31:0] golden_nonce;
	assign gn = golden_nonce;
	

	//// Control Unit
	reg is_golden_ticket;
	reg feedback_d1;
	wire [5:0] cnt_next;
	wire [31:0] nonce_next;
	wire feedback_next;

    assign gn_v = is_golden_ticket;
	assign cnt_next =  reset ? 6'd0 : (LOOP == 1) ? 6'd0 : (cnt + 6'd1) & (LOOP-1);
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (LOOP == 1) ? 1'b0 : (cnt_next != {(LOOP_LOG2){1'b0}});
	assign nonce_next =
		reset ? 32'd0 :
		feedback_next ? nonce : (nonce + 32'd1);

	
	always @ (posedge hash_clk)
	begin
        if (reset) begin
            golden_nonce <= 0;
            midstate_buf <= 0;
            data_buf <= 0;
            is_golden_ticket <= 0;
            feedback_d1 <= 1;
            feedback <= 0;
            cnt <= 0;
            state <= 0;
            data <= 0;
            nonce <= 0;
        end
        else begin
            midstate_buf <= md; //midstate_vw;
            data_buf <= d; //data2_vw;

            cnt <= cnt_next;
            feedback <= feedback_next;
            feedback_d1 <= feedback;

            // Give new data to the hasher
            state <= midstate_buf;
            data <= {384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, nonce_next, data_buf[95:0]};
            nonce <= nonce_next;
            //nonce <= 32'h0e33337a;


            // Check to see if the last hash generated is valid.
            is_golden_ticket <= (hash2[255:244] == 32'h00000000) && !feedback_d1;
            if(is_golden_ticket)
            begin
                // TODO: Find a more compact calculation for this
                if (LOOP == 1)
                    golden_nonce <= nonce - 32'd131;
                else if (LOOP == 2)
                    golden_nonce <= nonce - 32'd66;
                else
                    golden_nonce <= nonce - GOLDEN_NONCE_OFFSET;
                //$display ("nonce: %8x\ngolden_nonce: %8x\nhash2: %64x\n", nonce,golden_nonce,hash2);
                //$finish();
            end

            //if (!feedback_d1) begin
                //$display ("nonce: %8x\ngolden_nonce: %8x\nhash2: %64x\n", nonce,golden_nonce,hash2);
                //$display ("data: %128x\n", data);
            //end

        end
	end

endmodule

