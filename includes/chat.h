#ifndef CHAT_H
#define CHAT_H

// Chat protocol constants
#define CHAT_SERVER_PORT 41
#define CHAT_SERVER_NODE 1
#define MAX_USERNAME_LEN 12
#define MAX_MESSAGE_LEN 64
#define MAX_CLIENTS 10

// Buffer size constants
#define CHAT_RECV_BUFFER_SIZE 64
#define CHAT_SEND_BUFFER_SIZE 64
#define MAX_BROADCAST_PREFIX 10  // "msg : \r\n" overhead
#define MAX_WHISPER_PREFIX 16    // "whisper : \r\n" overhead
#define MAX_LISTUSR_PREFIX 13    // "listUsrRply " + "\r\n"

// Timeout constants
#define CLIENT_TIMEOUT 30000     // 30 seconds of inactivity
#define CLIENT_CHECK_INTERVAL 5000  // Check every 5 seconds

// Chat message types (sent within TCP payload)
enum {
    CHAT_HELLO = 0,
    CHAT_MSG = 1,
    CHAT_WHISPER = 2,
    CHAT_LISTUSR = 3,
    CHAT_LISTUSR_REPLY = 4,
    CHAT_BROADCAST = 5,
    CHAT_ERROR = 6
};

// Error codes
enum {
    CHAT_ERR_USERNAME_EXISTS = 1,
    CHAT_ERR_USERNAME_INVALID = 2,
    CHAT_ERR_USER_NOT_FOUND = 3,
    CHAT_ERR_SERVER_FULL = 4,
    CHAT_ERR_NOT_CONNECTED = 5,
    CHAT_ERR_MESSAGE_TOO_LONG = 6
};

// Client information structure for server to track
typedef struct chat_client {
    uint8_t active;
    uint16_t addr;
    uint8_t port;
    char username[MAX_USERNAME_LEN + 1];
    socket_t socketFd;
    uint32_t lastActivity;  // For timeout detection
} chat_client_t;

// Chat message structure (sent over TCP)
typedef nx_struct chat_msg {
    nx_uint8_t type;           // CHAT_HELLO, CHAT_MSG, etc.
    nx_uint8_t len;            // Length of data
    nx_uint8_t data[18];       // Message content (fits in TCP payload)
} chat_msg_t;

#endif /* CHAT_H */