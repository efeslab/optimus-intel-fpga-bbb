/* usage
logic [31:0] init_state[0:4] = {32'h1,32'h2,32'h3,32'h4,32'h5};
logic [31:0] state [0:4];
logic [31:0] random_out;
logic valid_out;
    xorwow #(.WIDTH(32)) xw(
        .clk(clk),
        .reset(reset),
        .init_state(init_state),
        .random(random_out),
        .valid(valid_out)
    );
*/
module xorwow
#(parameter WIDTH=32, parameter N_STATES=5)
(
    input logic clk,
    input logic reset,
    input logic [WIDTH-1:0] init_state[0:N_STATES-1],
    output logic [WIDTH-1:0] random,
    output logic valid
);
localparam DUP_NUM=6;
logic [3:0] select_cnt;
logic resetQ [0:DUP_NUM-1];
logic [WIDTH-1:0] randomQ [0:DUP_NUM-1];
logic [WIDTH-1:0] init_stateQ [0:DUP_NUM-1] [0:N_STATES-1];
logic validQ [0:DUP_NUM-1];

assign resetQ[0] = reset;
integer i;
always_ff @(posedge clk) begin
    for (i=1; i < DUP_NUM; i++) begin
        resetQ[i] <= resetQ[i-1];
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        select_cnt <= 0;
        random <= 0;
        valid <= 0;
    end
    else begin
        if (select_cnt == DUP_NUM - 1)
            select_cnt <= 0;
        else
            select_cnt <= select_cnt + 1;
        random <= randomQ[select_cnt];
        valid <= validQ[select_cnt];
    end
end

genvar n, m;
generate
    for (n=0; n < DUP_NUM; ++n) begin
        for (m=0; m < N_STATES; ++m) begin
            assign init_stateQ[n][m] = init_state[m] ^ n ^ m;
    end
    end
endgenerate
generate
    for (n=0; n < 6; n++)
    begin: gen_xorwow
        xorwow_C6 #(
            .WIDTH(WIDTH),
            .N_STATES(N_STATES)
        ) xw (
            .clk(clk),
            .reset(resetQ[n]),
            .init_state(init_stateQ[n]),
            .random(randomQ[n]),
            .valid(validQ[n])
        );
    end
endgenerate

endmodule

module xorwow_C6
#(parameter WIDTH=32, parameter N_STATES=5)
(
    input logic clk,
    input logic reset,
    input logic [WIDTH-1:0] init_state[0:N_STATES-1],
    output logic [WIDTH-1:0] random,
    output logic valid
);
logic [WIDTH-1:0] state [0:N_STATES-1];
logic [WIDTH-1:0] s;
logic [WIDTH-1:0] t;
integer i;
typedef enum logic [2:0] {
    T0, T1, T2, T3, T4, T5
} state_t;
state_t sm;
always_ff @(posedge clk) begin
    if (reset)
    begin
        state <= init_state;
        sm <= T0;
        valid <= 0;
    end
    else
    begin
        case (sm)
            T0: begin
                s <= state[0];
                t <= state[3];
                sm <= T1;
                valid <= 0;
            end
            T1: begin
                t <= t ^ (t >> 2);
                sm <= T2;
                valid <= 0;
            end
            T2: begin
                t <= t ^ (t << 1);
                sm <= T3;
                valid <= 0;
            end
            T3: begin
                t <= t ^ s;
                state[3] <= state[2];
                state[2] <= state[1];
                state[1] <= s;
                sm <= T4;
                valid <= 0;
            end
            T4: begin
                t <= t ^ (s << 4);
                state[4] <= state[4] + 362437;
                sm <= T5;
                valid <= 0;
            end
            T5: begin
                random <= t + state[4];
                state[0] <= t;
                sm <= T0;
                valid <= 1;
            end
        endcase
    end
end
endmodule
