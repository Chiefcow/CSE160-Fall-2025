#ifndef __TCP_H__
#define __TCP_H__

#include "protocol.h"

// TCP Protocol Constants
enum {
    TCP_MAX_PAYLOAD_SIZE = 10,
    MAX_RETRANSMIT_QUEUE = 20,
};

// TCP Flags
enum tcp_flags {
    TCP_SYN = 0,
    TCP_ACK = 1,
    TCP_FIN = 2,
    TCP_DATA = 3,
};

// TCP Packet Header Structure
typedef nx_struct tcp_pack {
    nx_uint8_t srcPort;
    nx_uint8_t destPort;
    nx_uint16_t seq;        // Sequence number in BYTES
    nx_uint16_t ack;        // Acknowledgment number in BYTES
    nx_uint8_t flags;       // TCP flags (SYN, ACK, FIN, DATA)
    nx_uint8_t window;      // Advertised window size
    nx_uint8_t payloadLen;  // Actual payload length
    nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE]; 
} tcp_pack;

// Retransmission Queue Entry
typedef struct pending_packet_t {
    pack packet;            // The full packet to retransmit
    uint32_t sentTime;      // When was it sent
    uint32_t timeout;       // When should we retransmit
    uint16_t seq;           // Sequence number for this packet
    uint8_t payloadLen;     // Length of payload
} pending_packet_t;

#endif /* __TCP_H__ */