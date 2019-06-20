`include "platform_if.vh"
`include "afu_json_info.vh"

`define MPF_CONF_ENABLE_VTP 1
`define MPF_CONF_SORT_READ_RESPONSES 1

module ccip_std_afu
    (
        input           logic             pClk,
        input           logic             pClkDiv2,
        input           logic             pClkDiv4,
        input           logic             uClk_usr,
        input           logic             uClk_usrDiv2,
        input           logic             pck_cp2af_softReset,
        input           logic [1:0]       pck_cp2af_pwrState,
        input           logic             pck_cp2af_error,

        input           t_if_ccip_Rx      pck_cp2af_sRx,
        output          t_if_ccip_Tx      pck_af2cp_sTx
    );

    logic clk;
    assign clk = pClk;

    logic reset;
    assign reset = pck_cp2af_softReset;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(pck_cp2af_sRx.c0.hdr);

    // afu mmio writes
    t_ccip_clAddr buf_addr;
    t_ccip_clAddr bufcpy_addr;
    logic [16:0] size;

    // for extra purposes
    //logic [16:0] size_from_0;

    // afu state

    logic start_traversal;
    logic end_traversal;

    // rw_state
    logic rd_sent;
    logic rd_recieved;
    logic wr_sent;
    logic wr_ack;
    logic increment;

    typedef enum logic[1:0] {
        READ,
        READ_RESPONSE,
        WRITE,
        WRITE_RESPONSE
    } rw_state;

    rw_state rw;


    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            buf_addr        <= 0;
            bufcpy_addr     <= 0;
            size            <= 0;
            start_traversal <= 0;
            end_traversal   <= 0;
        end
        else
        begin
            pck_af2cp_sTx.c2.mmioRdValid <= 0;

            if (pck_cp2af_sRx.c0.mmioWrValid)
            begin
                case (mmio_req_hdr.address)
                    16'h22: buf_addr        <= t_ccip_clAddr'(pck_cp2af_sRx.c0.data);
                    16'h24: bufcpy_addr     <= t_ccip_clAddr'(pck_cp2af_sRx.c0.data);
                    16'h26: size            <= pck_cp2af_sRx.c0.data;
                endcase
            end

            // serve MMIO read requests
            if (pck_cp2af_sRx.c0.mmioRdValid)
            begin
                pck_af2cp_sTx.c2.hdr.tid <= mmio_req_hdr.tid; // copy TID

                case (mmio_req_hdr.address)
                    // AFU header
                    16'h0000: pck_af2cp_sTx.c2.data <=
                        {
                            4'b0001, // Feature type = AFU
                            8'b0,    // reserved
                            4'b0,    // afu minor revision = 0
                            7'b0,    // reserved
                            1'b1,    // end of DFH list = 1
                            24'b0,   // next DFH offset = 0
                            4'b0,    // afu major revision = 0
                            12'b0    // feature ID = 0
                        };
                    16'h0002: pck_af2cp_sTx.c2.data <= afu_id[63:0]; // afu id low
                    16'h0004: pck_af2cp_sTx.c2.data <= afu_id[127:64]; // afu id hi
                    16'h0006: pck_af2cp_sTx.c2.data <= 64'h0; // reserved
                    16'h0008: pck_af2cp_sTx.c2.data <= 64'h0; // reserved
                    default:  pck_af2cp_sTx.c2.data <= 64'h0;
                endcase
                pck_af2cp_sTx.c2.mmioRdValid <= 1;
            end

            start_traversal <= (buf_addr != 0) && (bufcpy_addr != 0);
            end_traversal   <= (size <= 0);

            if (increment && size > 0)
            begin
                size <= size - 1;
                buf_addr    <= buf_addr + 64;
                bufcpy_addr <= bufcpy_addr + 64;
            end

        end
    end

    typedef enum logic[1:0] {
        STATE_IDLE,
        STATE_RUN
    } t_state;

    t_state state;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_IDLE;
        end
        else
        begin
            case (state)
                STATE_IDLE:
                    if (start_traversal && !end_traversal)
                    begin
                        state <= STATE_RUN;
                        $display("Running afu...");
                    end
                STATE_RUN:
                    if (end_traversal)
                    begin
                        state <= STATE_IDLE;
                        $display("Copying done...");
                    end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rw <= READ;
            increment <= 0;
        end
        else
        begin
            case (rw)
                READ:
                    if (rd_sent)
                    begin
                        rw <= READ_RESPONSE;
                    end
                READ_RESPONSE:
                    if (rd_recieved)
                    begin
                        rw <= WRITE;
                    end
                WRITE:
                    if (wr_sent)
                    begin
                        rw <= WRITE_RESPONSE;
                        increment <= 1;
                    end
                WRITE_RESPONSE:
                    if (wr_ack)
                    begin
                        rw <= READ;
                    end
            endcase

            if (increment)
            begin
                increment <= 0;
            end
        end

    end

    // Read logic
    //
    t_ccip_c0_ReqMemHdr rd_hdr;

    always_comb
    begin
        rd_hdr <= t_ccip_c0_ReqMemHdr'(0);
        //rd_hdr.vc_sel = eVC_VA;
        //rd_hdr.cl_len = eCL_LEN_1;

        rd_hdr.address   <= buf_addr;
        //rd_hdr.mdata  <= size_from_0;
    end

    logic rd_needed;
    logic rd_no;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_needed <= 0;
            //size_from_0 <= 0;
            rd_sent <= 0;
            rd_no   <= 0;
            pck_af2cp_sTx.c0.valid <= 0;
            pck_af2cp_sTx.c0.hdr   <= 0;
        end
        else
        begin
            rd_needed <= (start_traversal && ! end_traversal);
            pck_af2cp_sTx.c0.valid <= (rd_needed && buf_addr != 0 && ! pck_cp2af_sRx.c0TxAlmFull && rw == READ && state == STATE_RUN && ! rd_sent);
            rd_sent <= (rd_needed && buf_addr != 0 && ! pck_cp2af_sRx.c0TxAlmFull && rw == READ && state == STATE_RUN && ! rd_sent);

            if (rd_needed && buf_addr != 0 && ! pck_cp2af_sRx.c0TxAlmFull && rw == READ && state == STATE_RUN && ! rd_sent)
            begin
                rd_no <= rd_no + 1;
            end

            if (rd_sent)
            begin
                rd_sent <= 0;
            end

            pck_af2cp_sTx.c0.hdr <= rd_hdr;
        end
    end

    // read response logic
    logic [63:0] rd_data;
    logic rd_response_no;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_data <= 0;
            rd_recieved <= 0;
            rd_response_no <= 0;
        end
        else if (pck_cp2af_sRx.c0.rspValid && rw == READ_RESPONSE && ! rd_recieved)
        begin
            rd_data <= pck_cp2af_sRx.c0.data;
            rd_recieved <= 1;
            rd_response_no <= rd_response_no + 1;
        end

        if (rd_recieved)
        begin
            rd_recieved <= 0;
        end
    end


    // write logic

    t_ccip_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_hdr <= t_ccip_c1_ReqMemHdr'(0);
        wr_hdr.vc_sel <= eVC_VA;
        wr_hdr.cl_len <= eCL_LEN_1;
        wr_hdr.sop <= 1'b1;

        wr_hdr.address <= bufcpy_addr;
    end

    // send write
    logic wr_no;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            wr_sent <= 0;
            wr_no   <= 0;
            pck_af2cp_sTx.c1.valid <= 0;
            pck_af2cp_sTx.c1.hdr <= 0;
        end
        else
        begin
            pck_af2cp_sTx.c1 <= (state == STATE_RUN  && rw == WRITE && ! wr_sent) && (! pck_cp2af_sRx.c1TxAlmFull);
            pck_af2cp_sTx.c1.data <= rd_data;
            pck_af2cp_sTx.c1.hdr <= wr_hdr;

            if (state == STATE_RUN  && rw == WRITE && ! wr_sent && ! pck_cp2af_sRx.c1TxAlmFull)
            begin
                wr_no <= wr_no + 1;
                wr_sent <= 1;
            end

            if (wr_sent)
            begin
                wr_sent <= 0;
            end

        end
    end

    // write response
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            wr_ack <= 0;
        end

        else if (pck_cp2af_sRx.c1.rspValid && rw == WRITE_RESPONSE)
        begin
            wr_ack <= 1;
        end

        if (wr_ack)
        begin
            wr_ack <= 0;
        end
    end
endmodule
