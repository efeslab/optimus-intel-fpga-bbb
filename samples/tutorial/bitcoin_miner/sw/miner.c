#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>

#include <stdio.h>
#include <string.h>

#include <vai/fpga.h>

#define RAND64 ((uint64_t)(rand()) | ((uint64_t)(rand()) << 32))

#define BITCOIN_CSR_D1 (6 << 2)
#define BITCOIN_CSR_D2 (8 << 2)
#define BITCOIN_CSR_D3 (10 << 2)
#define BITCOIN_CSR_D4 (12 << 2)
#define BITCOIN_CSR_MD1 (14 << 2)
#define BITCOIN_CSR_MD2 (16 << 2)
#define BITCOIN_CSR_MD3 (18 << 2)
#define BITCOIN_CSR_MD4 (20 << 2)
#define BITCOIN_CSR_RESULT_ADDR (22 << 2)
#define BITCOIN_CSR_CONTROL (24 << 2)
#define BITCOIN_CSR_CURR_NONCE (26 << 2)

int main(int argc, char *argv[])
{
    struct vai_afu_conn *conn = vai_afu_connect();
    volatile uint64_t *result_buf = (volatile uint64_t *) vai_afu_malloc(conn, 64);

    result_buf[0] = 0;
    result_buf[1] = 0;
    vai_afu_mmio_write(conn, BITCOIN_CSR_RESULT_ADDR, (uint64_t)result_buf >> 6);

    vai_afu_mmio_write(conn, BITCOIN_CSR_MD1, (uint64_t)(0xf106abb3af41f790));
    vai_afu_mmio_write(conn, BITCOIN_CSR_MD2, (uint64_t)(0x61a5e75ec8c582a5));
    vai_afu_mmio_write(conn, BITCOIN_CSR_MD3, (uint64_t)(0x60c009cda7252b91));
    vai_afu_mmio_write(conn, BITCOIN_CSR_MD4, (uint64_t)(0x228ea4732a3c9ba8));

    while (1) {

        vai_afu_mmio_write(conn, BITCOIN_CSR_D1, (uint64_t)(RAND64));
        vai_afu_mmio_write(conn, BITCOIN_CSR_D2, (uint64_t)(RAND64));
        vai_afu_mmio_write(conn, BITCOIN_CSR_D3, (uint64_t)(RAND64));
        vai_afu_mmio_write(conn, BITCOIN_CSR_D4, (uint64_t)(RAND64));

        vai_afu_mmio_write(conn, BITCOIN_CSR_CONTROL, 1L);

        while (1) {
            if (0 != result_buf[1]) {	

                uint64_t r = result_buf[1];
                printf("Golden nonce: 0x%x\n", r);
                result_buf[1] = 0;
                break;
            }
            else {
                uint64_t curr_nonce, state;
                //vai_afu_mmio_read(conn, BITCOIN_CSR_CURR_NONCE, &curr_nonce);
                //vai_afu_mmio_read(conn, BITCOIN_CSR_CONTROL, &state);
                //printf("current nonce: 0x%lx, current state: 0x%lx\n", curr_nonce, state);
                usleep(10000);
            }
        }

    }


    vai_afu_disconnect(conn);
    
    return 0;
}
