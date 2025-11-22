#ifndef TCP_SIMPLE_H
#define TCP_SIMPLE_H

// TCP Flags - just what we need for basic setup/teardown
#define TCP_FLAG_SYN 0x01
#define TCP_FLAG_ACK 0x02
#define TCP_FLAG_FIN 0x04
#define TCP_FLAG_DATA 0x08

// Simplified TCP packet structure (fits in 20-byte packet payload)
typedef nx_struct tcp_packet {
    nx_uint8_t src_port;
    nx_uint8_t dest_port;
    nx_uint8_t flags;           // SYN, ACK, FIN, DATA
    nx_uint8_t data_len;        // How many bytes of actual data
    nx_uint8_t payload[16];     // Simple data payload
} tcp_packet;

#endif