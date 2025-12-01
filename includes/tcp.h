#ifndef TCP_H
#define TCP_H

#include "socket.h"

// TCP Flags
#define TCP_FLAG_SYN  0x01
#define TCP_FLAG_ACK  0x02
#define TCP_FLAG_FIN  0x04
#define TCP_FLAG_DATA 0x08

// TCP Timer Configuration
#define TCP_TIMER_INTERVAL 100  // milliseconds
#define TCP_TIMEOUT 1000         // milliseconds for retransmission

// NULL socket constant
#define NULL_SOCKET 255

// TCP Header Structure (fits in packet payload)
typedef struct tcp_header {
    nx_uint8_t src_port;
    nx_uint8_t dest_port;
    nx_uint16_t seq_num;           // Sequence number for this packet
    nx_uint16_t ack_num;           // Acknowledgment number
    nx_uint8_t flags;              // SYN, ACK, FIN, DATA flags
    nx_uint8_t advertised_window;  // Flow control window
    nx_uint8_t data[];             // Variable length data (rest of payload)
} tcp_header;

#endif // TCP_H