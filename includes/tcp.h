#ifndef __TCP_H__
#define __TCP_H__

#include "protocol.h"

// TCP Protocol Constants
enum {
    TCP_MAX_PAYLOAD_SIZE = 10,      // Max data per TCP packet
    MAX_RETRANSMIT_QUEUE = 20,      // Max packets in retransmit queue
};

// TCP Flags - Used in tcp_pack.flags field (bit flags)
enum tcp_flags {
    TCP_SYN = 0x01,   // 0001 - Synchronize
    TCP_ACK = 0x02,   // 0010 - Acknowledge
    TCP_FIN = 0x04,   // 0100 - Finish
    TCP_DATA = 0x08,  // 1000 - Data transfer
};

// Convenience definition for combined SYN+ACK
#define TCP_SYN_ACK (TCP_SYN | TCP_ACK)  // 0x03

// TCP Packet Header Structure
// This structure goes into the payload of a 'pack' when protocol = PROTOCOL_TCP
typedef nx_struct tcp_pack {
    nx_uint8_t srcPort;             // Source port
    nx_uint8_t destPort;            // Destination port
    nx_uint16_t seq;                // Sequence number in BYTES
    nx_uint16_t ack;                // Acknowledgment number in BYTES
    nx_uint8_t flags;               // TCP flags (SYN, ACK, FIN, DATA)
    nx_uint8_t window;              // Advertised window size
    nx_uint8_t payloadLen;          // Actual payload length (0 for control packets)
    nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE];  // Data payload
} tcp_pack;

// Retransmission Queue Entry
// Tracks packets that need to be retransmitted if not acknowledged
typedef struct pending_packet_t {
    pack packet;            // The full packet to retransmit
    uint32_t sentTime;      // When was it sent (for RTT calculation)
    uint32_t timeout;       // When should we retransmit
    uint16_t seq;           // Sequence number for this packet
    uint8_t payloadLen;     // Length of payload
    uint8_t retryCount;     // Number of retransmission attempts
} pending_packet_t;

#endif /* __TCP_H__ */