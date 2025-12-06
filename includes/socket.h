#ifndef __SOCKET_H__
#define __SOCKET_H__
#include "tcp.h"

// Socket Constants
enum {
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

// Socket States (TCP State Machine)
enum socket_state {
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
    CLOSE_WAIT,
    FIN_WAIT_1,
    FIN_WAIT_2,
    TIME_WAIT,
    LAST_ACK
};

// Port type definitions
typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// Socket address structure (for bind/connect)
typedef nx_struct socket_addr_t {
    nx_socket_port_t port;
    nx_uint16_t addr;
} socket_addr_t;

// File descriptor type
typedef uint8_t socket_t;

// Socket storage structure - maintains state for one connection
typedef struct socket_store_t {
    uint8_t flag;                   // Is this socket in use?
    enum socket_state state;        // Current TCP state
    socket_port_t src;              // Source port (our port)
    socket_addr_t dest;             // Destination address and port

    // Sender state (manages outgoing data)
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];   // Send buffer
    uint16_t lastWritten;           // Last byte written by app (byte position)
    uint16_t lastAck;               // Last byte acknowledged (byte position)
    uint16_t lastSent;              // Last byte sent (byte position)

    // Receiver state (manages incoming data)
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];   // Receive buffer
    uint16_t lastRead;              // Last byte read by app (byte position)
    uint16_t lastRcvd;              // Last byte received (byte position)
    uint16_t nextExpected;          // Next expected sequence number (byte position)

    // Connection parameters
    uint16_t RTT;                   // Round-trip time estimate (ms)
    uint8_t effectiveWindow;        // Peer's advertised window size
} socket_store_t;

#endif /* __SOCKET_H__ */