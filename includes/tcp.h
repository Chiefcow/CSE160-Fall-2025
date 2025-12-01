#ifndef __TCP_H__
#define __TCP_H__

#include "socket.h"

// TCP Flags
enum {
    TCP_FLAG_SYN = 0x01,    // Synchronize - establish connection
    TCP_FLAG_ACK = 0x02,    // Acknowledgment
    TCP_FLAG_FIN = 0x04,    // Finish - close connection
    TCP_FLAG_DATA = 0x08,   // Data packet
};

// TCP Header Structure
// This goes in the payload of the regular packet
typedef nx_struct tcp_header {
    nx_uint8_t src_port;           // Source port
    nx_uint8_t dest_port;          // Destination port
    nx_uint16_t seq_num;           // Sequence number (byte-based)
    nx_uint16_t ack_num;           // Acknowledgment number
    nx_uint8_t flags;              // TCP flags (SYN, ACK, FIN, DATA)
    nx_uint8_t advertised_window;  // Flow control window size
    nx_uint8_t data[PACKET_MAX_PAYLOAD_SIZE - 8]; // Remaining space for data
} tcp_header;

// Timer intervals
enum {
    TCP_TIMER_INTERVAL = 1000,      // 1 second periodic timer
    TCP_RETRANSMIT_TIMEOUT = 3000,  // 3 seconds for retransmission
    CLIENT_WRITE_TIMER = 500,       // 500ms for client writes
};

#endif