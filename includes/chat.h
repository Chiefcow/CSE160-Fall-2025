#ifndef CHAT_H
#define CHAT_H

// Chat protocol constants
#define CHAT_SERVER_PORT 41
#define CHAT_SERVER_NODE 1
#define MAX_USERNAME_LEN 12
#define MAX_MESSAGE_LEN 64
#define MAX_CLIENTS 10

// Chat message types (sent within TCP payload)
enum {
    CHAT_HELLO = 0,
    CHAT_MSG = 1,
    CHAT_WHISPER = 2,
    CHAT_LISTUSR = 3,
    CHAT_LISTUSR_REPLY = 4,
    CHAT_BROADCAST = 5
};

// Client information structure for server to track
typedef struct chat_client {
    uint8_t active;
    uint16_t addr;
    uint8_t port;
    char username[MAX_USERNAME_LEN + 1];
    socket_t socketFd;
} chat_client_t;

// Chat message structure (sent over TCP)
typedef nx_struct chat_msg {
    nx_uint8_t type;           // CHAT_HELLO, CHAT_MSG, etc.
    nx_uint8_t len;            // Length of data
    nx_uint8_t data[18];       // Message content (fits in TCP payload)
} chat_msg_t;

#endif /* CHAT_H */