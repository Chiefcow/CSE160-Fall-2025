#ifndef __SOCKET_H__
#define __SOCKET_H__
//Editing and making notes this time to not forget - Elvis

#include "protocol.h"
enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,

    //setting Flags - Elvis
    TCP_SYN = 0,
    TCP_ACK = 1,
    TCP_Fin = 2,
    TCP_DATA = 3,
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
    //Adding socket states for our flags
    CLOSE_WAIT,
    FIN_WAIT_1,
    FIN_WAIT_2,
    TIME_WAIT,
    LAST_ACK

};


typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
//This will be edited to support our TCP I will explain it so you dont get lost - Elvis
typedef nx_struct tcp_pack {
    nx_socket_port_t srcPort;
    nx_socket_port_t destPort;
    nx_uint16_t seq; //sequence number
    nx_uint16_t ack; //acknowledgment number
    nx_uint16_t flags; // SYN, ACK, FIN, DATA stated above
    nx_uint16_t window; // our advertised window
    nx_uint16_t payload[SOCKET_BUFFER_SIZE]; // Max Payload 
    nx_uint16_t payloadLen; // Our data length in Payload
}tcp_pack;


// File descripter id. Each id is associated with a socket_store_t
//typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag; //Is our Socket active
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest; //where our destination, address and destination port into goes

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten; //Last byte written by app
    uint8_t lastAck; //Last byte acknowledged by our reciver
    uint8_t lastSent; //Last byte the network was sent

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead; //Last Byte written by app
    uint8_t lastRcvd; //Last Byte recived from network
    uint8_t nextExpected; //Next sequence number expected

    uint16_t RTT;
    uint8_t effectiveWindow;
}socket_store_t;

#endif
