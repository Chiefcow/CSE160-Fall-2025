#include "../../includes/channels.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/Chat.h"

module ChatP {
    provides interface Chat;
    
    uses interface Transport;
    uses interface Timer<TMilli> as ChatTimer;
}

implementation {
    // Server state
    bool isServer = FALSE;
    socket_t serverFd = 0;
    chat_client_t clients[MAX_CLIENTS];
    uint8_t numClients = 0;
    
    // Client state
    bool isClient = FALSE;
    socket_t clientFd = 0;
    char myUsername[MAX_USERNAME_LEN + 1];
    uint8_t myPort = 0;
    bool connected = FALSE;
    
    // Buffer for receiving data - per socket for server
    uint8_t recvBuffer[MAX_CLIENTS][64];
    uint8_t recvLen[MAX_CLIENTS];
    
    // Client receive buffer
    uint8_t clientRecvBuf[64];
    uint8_t clientRecvLen = 0;
    
    // Pending message to send after connection
    bool pendingHello = FALSE;
    
    // Initialize client array
    void initClients() {
        uint8_t i;
        for(i = 0; i < MAX_CLIENTS; i++) {
            clients[i].active = 0;
            clients[i].socketFd = 0;
            recvLen[i] = 0;
        }
        numClients = 0;
    }
    
    // Copy string with length limit
    void strcopy(char* dest, char* src, uint8_t maxLen) {
        uint8_t i;
        for(i = 0; i < maxLen && src[i] != '\0'; i++) {
            dest[i] = src[i];
        }
        dest[i] = '\0';
    }
    
    // Get string length
    uint8_t strlen_local(char* str) {
        uint8_t len = 0;
        while(str[len] != '\0' && len < 128) len++;
        return len;
    }
    
    // Compare strings
    bool streq(char* a, char* b) {
        uint8_t i = 0;
        while(a[i] != '\0' && b[i] != '\0') {
            if(a[i] != b[i]) return FALSE;
            i++;
        }
        return a[i] == b[i];
    }
    
    // Find client by username
    int findClientByUsername(char* username) {
        uint8_t i;
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active && streq(clients[i].username, username)) {
                return i;
            }
        }
        return -1;
    }
    
    // Find client by socket fd
    int findClientBySocket(socket_t fd) {
        uint8_t i;
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active && clients[i].socketFd == fd) {
                return i;
            }
        }
        return -1;
    }
    
    // ==================== SERVER FUNCTIONS ====================
    
    // Broadcast message to all connected clients
    void broadcastToClients(char* sender, char* message) {
        uint8_t i;
        uint8_t buffer[64];
        uint8_t len = 0;
        uint8_t j;
        
        // Format: "msg sender: message\r\n"
        buffer[len++] = 'm';
        buffer[len++] = 's';
        buffer[len++] = 'g';
        buffer[len++] = ' ';
        
        for(j = 0; sender[j] != '\0' && len < 50; j++) {
            buffer[len++] = sender[j];
        }
        buffer[len++] = ':';
        buffer[len++] = ' ';
        
        for(j = 0; message[j] != '\0' && len < 60; j++) {
            buffer[len++] = message[j];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Broadcasting from %s: %s\n", sender, message);
        
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active && clients[i].socketFd != 0) {
                call Transport.send(clients[i].socketFd, buffer, len);
            }
        }
    }
    
    // Send user list to requesting client
    void sendUserList(uint8_t clientIdx) {
        uint8_t buffer[64];
        uint8_t len = 0;
        uint8_t i, j;
        bool first = TRUE;
        char* prefix = "listUsrRply ";
        
        for(j = 0; prefix[j] != '\0'; j++) {
            buffer[len++] = prefix[j];
        }
        
        for(i = 0; i < MAX_CLIENTS && len < 55; i++) {
            if(clients[i].active) {
                if(!first) {
                    buffer[len++] = ',';
                    buffer[len++] = ' ';
                }
                first = FALSE;
                for(j = 0; clients[i].username[j] != '\0' && len < 55; j++) {
                    buffer[len++] = clients[i].username[j];
                }
            }
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending user list to client %d\n", clientIdx);
        
        if(clients[clientIdx].active && clients[clientIdx].socketFd != 0) {
            call Transport.send(clients[clientIdx].socketFd, buffer, len);
        }
    }
    
    // Send whisper to specific user
    void sendWhisperTo(char* fromUser, char* toUser, char* message) {
        int idx = findClientByUsername(toUser);
        uint8_t buffer[64];
        uint8_t len = 0;
        uint8_t j;
        char* prefix = "whisper ";
        
        if(idx < 0) {
            dbg("transport", "Chat: Whisper target %s not found\n", toUser);
            return;
        }
        
        for(j = 0; prefix[j] != '\0'; j++) {
            buffer[len++] = prefix[j];
        }
        for(j = 0; fromUser[j] != '\0' && len < 45; j++) {
            buffer[len++] = fromUser[j];
        }
        buffer[len++] = ':';
        buffer[len++] = ' ';
        for(j = 0; message[j] != '\0' && len < 60; j++) {
            buffer[len++] = message[j];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Whisper from %s to %s: %s\n", fromUser, toUser, message);
        
        if(clients[idx].active && clients[idx].socketFd != 0) {
            call Transport.send(clients[idx].socketFd, buffer, len);
        }
    }
    
    // Process a complete message from client (server side)
    void processServerMessage(socket_t fd, uint8_t* data, uint8_t len) {
        int clientIdx = findClientBySocket(fd);
        char cmd[16];
        char arg1[MAX_USERNAME_LEN + 1];
        char arg2[MAX_MESSAGE_LEN];
        uint8_t i = 0, j = 0;
        
        // Parse command
        while(i < len && data[i] != ' ' && data[i] != '\r' && j < 15) {
            cmd[j++] = data[i++];
        }
        cmd[j] = '\0';
        
        if(i < len && data[i] == ' ') i++;
        
        // Parse first argument
        j = 0;
        while(i < len && data[i] != ' ' && data[i] != '\r' && j < MAX_USERNAME_LEN) {
            arg1[j++] = data[i++];
        }
        arg1[j] = '\0';
        
        if(i < len && data[i] == ' ') i++;
        
        // Parse second argument (rest of message)
        j = 0;
        while(i < len && data[i] != '\r' && j < MAX_MESSAGE_LEN - 1) {
            arg2[j++] = data[i++];
        }
        arg2[j] = '\0';
        
        dbg("transport", "Chat Server: cmd='%s' arg1='%s' arg2='%s' from fd=%d\n", cmd, arg1, arg2, fd);
        
        // Handle hello command
        if(streq(cmd, "hello")) {
            if(clientIdx < 0) {
                // New client - find empty slot
                for(i = 0; i < MAX_CLIENTS; i++) {
                    if(!clients[i].active) {
                        clientIdx = i;
                        break;
                    }
                }
            }
            
            if(clientIdx >= 0) {
                clients[clientIdx].active = 1;
                clients[clientIdx].socketFd = fd;
                clients[clientIdx].addr = call Transport.getSocketSrcAddr(fd);
                strcopy(clients[clientIdx].username, arg1, MAX_USERNAME_LEN);
                numClients++;
                dbg("transport", "Chat: User '%s' connected (slot %d, addr %d)\n", 
                    arg1, clientIdx, clients[clientIdx].addr);
            }
        }
        // Handle msg command
        else if(streq(cmd, "msg")) {
            if(clientIdx >= 0 && clients[clientIdx].active) {
                if(arg2[0] != '\0') {
                    char fullMsg[MAX_MESSAGE_LEN];
                    uint8_t k = 0, m = 0;
                    while(arg1[k] != '\0' && m < MAX_MESSAGE_LEN - 2) {
                        fullMsg[m++] = arg1[k++];
                    }
                    fullMsg[m++] = ' ';
                    k = 0;
                    while(arg2[k] != '\0' && m < MAX_MESSAGE_LEN - 1) {
                        fullMsg[m++] = arg2[k++];
                    }
                    fullMsg[m] = '\0';
                    broadcastToClients(clients[clientIdx].username, fullMsg);
                } else {
                    broadcastToClients(clients[clientIdx].username, arg1);
                }
            }
        }
        // Handle whisper command
        else if(streq(cmd, "whisper")) {
            if(clientIdx >= 0 && clients[clientIdx].active) {
                sendWhisperTo(clients[clientIdx].username, arg1, arg2);
            }
        }
        // Handle listusr command
        else if(streq(cmd, "listusr")) {
            if(clientIdx >= 0) {
                sendUserList(clientIdx);
            }
        }
    }
    
    command error_t Chat.startServer() {
        socket_addr_t addr;
        
        dbg("transport", "Chat: Starting server on node %d, port %d\n", TOS_NODE_ID, CHAT_SERVER_PORT);
        
        isServer = TRUE;
        initClients();
        
        call Transport.start();
        serverFd = call Transport.socket();
        
        if(serverFd == 0) {
            dbg("transport", "Chat: Failed to create server socket\n");
            return FAIL;
        }
        
        addr.port = CHAT_SERVER_PORT;
        addr.addr = TOS_NODE_ID;
        
        call Transport.bind(serverFd, &addr);
        call Transport.listen(serverFd);
        
        call ChatTimer.startPeriodic(200);
        
        dbg("transport", "Chat: Server listening on port %d\n", CHAT_SERVER_PORT);
        return SUCCESS;
    }
    
    // ==================== CLIENT FUNCTIONS ====================
    
    command error_t Chat.startClient(char* username, uint8_t clientPort) {
        socket_addr_t src, dest;
        
        dbg("transport", "Chat: Starting client '%s' on port %d\n", username, clientPort);
        
        isClient = TRUE;
        strcopy(myUsername, username, MAX_USERNAME_LEN);
        myPort = clientPort;
        clientRecvLen = 0;
        
        call Transport.start();
        clientFd = call Transport.socket();
        
        if(clientFd == 0) {
            dbg("transport", "Chat: Failed to create client socket\n");
            return FAIL;
        }
        
        src.port = clientPort;
        src.addr = TOS_NODE_ID;
        call Transport.bind(clientFd, &src);
        
        dest.port = CHAT_SERVER_PORT;
        dest.addr = CHAT_SERVER_NODE;
        
        pendingHello = TRUE;
        
        call Transport.connect(clientFd, &dest);
        
        call ChatTimer.startPeriodic(200);
        
        return SUCCESS;
    }
    
    command error_t Chat.sendMessage(char* message) {
        uint8_t buffer[64];
        uint8_t len = 0;
        uint8_t i;
        
        if(!connected || clientFd == 0) {
            dbg("transport", "Chat: Cannot send - not connected\n");
            return FAIL;
        }
        
        buffer[len++] = 'm';
        buffer[len++] = 's';
        buffer[len++] = 'g';
        buffer[len++] = ' ';
        
        for(i = 0; message[i] != '\0' && len < 60; i++) {
            buffer[len++] = message[i];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending message: %s\n", message);
        call Transport.send(clientFd, buffer, len);
        
        return SUCCESS;
    }
    
    command error_t Chat.sendWhisper(char* username, char* message) {
        uint8_t buffer[64];
        uint8_t len = 0;
        uint8_t i;
        char* prefix = "whisper ";
        
        if(!connected || clientFd == 0) {
            return FAIL;
        }
        
        for(i = 0; prefix[i] != '\0'; i++) {
            buffer[len++] = prefix[i];
        }
        for(i = 0; username[i] != '\0' && len < 25; i++) {
            buffer[len++] = username[i];
        }
        buffer[len++] = ' ';
        for(i = 0; message[i] != '\0' && len < 60; i++) {
            buffer[len++] = message[i];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending whisper to %s: %s\n", username, message);
        call Transport.send(clientFd, buffer, len);
        
        return SUCCESS;
    }
    
    command error_t Chat.requestUserList() {
        uint8_t buffer[16];
        
        if(!connected || clientFd == 0) {
            return FAIL;
        }
        
        buffer[0] = 'l';
        buffer[1] = 'i';
        buffer[2] = 's';
        buffer[3] = 't';
        buffer[4] = 'u';
        buffer[5] = 's';
        buffer[6] = 'r';
        buffer[7] = '\r';
        buffer[8] = '\n';
        
        dbg("transport", "Chat: Requesting user list\n");
        call Transport.send(clientFd, buffer, 9);
        
        return SUCCESS;
    }
    
    // Process message received by client
    void processClientMessage(uint8_t* data, uint8_t len) {
        char cmd[16];
        char from[MAX_USERNAME_LEN + 1];
        char message[MAX_MESSAGE_LEN];
        uint8_t i = 0, j = 0;
        
        while(i < len && data[i] != ' ' && data[i] != '\r' && j < 15) {
            cmd[j++] = data[i++];
        }
        cmd[j] = '\0';
        
        if(i < len && data[i] == ' ') i++;
        
        j = 0;
        while(i < len && data[i] != '\r' && j < MAX_MESSAGE_LEN - 1) {
            message[j++] = data[i++];
        }
        message[j] = '\0';
        
        dbg("transport", "Chat Client: cmd='%s' content='%s'\n", cmd, message);
        
        if(streq(cmd, "msg") || streq(cmd, "whisper")) {
            j = 0;
            i = 0;
            while(message[i] != ':' && message[i] != '\0' && j < MAX_USERNAME_LEN) {
                from[j++] = message[i++];
            }
            from[j] = '\0';
            
            if(message[i] == ':') i++;
            if(message[i] == ' ') i++;
            
            j = 0;
            while(message[i] != '\0' && j < MAX_MESSAGE_LEN - 1) {
                message[j++] = message[i++];
            }
            message[j] = '\0';
            
            dbg("transport", "Chat: Message from %s: %s\n", from, message);
            signal Chat.messageReceived(from, message);
        }
        else if(streq(cmd, "listUsrRply")) {
            dbg("transport", "Chat: User list: %s\n", message);
            signal Chat.userListReceived(message);
        }
    }
    
    // ==================== TRANSPORT EVENTS ====================
    
    event void Transport.connectDone(socket_t fd) {
        uint8_t buffer[32];
        uint8_t len = 0;
        uint8_t i;
        
        if(isClient && fd == clientFd) {
            connected = TRUE;
            dbg("transport", "Chat: Client connected to server\n");
            
            buffer[len++] = 'h';
            buffer[len++] = 'e';
            buffer[len++] = 'l';
            buffer[len++] = 'l';
            buffer[len++] = 'o';
            buffer[len++] = ' ';
            
            for(i = 0; myUsername[i] != '\0' && len < 28; i++) {
                buffer[len++] = myUsername[i];
            }
            buffer[len++] = '\r';
            buffer[len++] = '\n';
            
            call Transport.send(clientFd, buffer, len);
            
            pendingHello = FALSE;
            signal Chat.connected();
        }
    }
    
    event error_t Transport.accept(socket_t fd) {
        dbg("transport", "Chat: Server accepted connection on socket %d\n", fd);
        return SUCCESS;
    }
    
    // Handle data received on a socket
    event void Transport.dataReceived(socket_t fd) {
        uint8_t tempBuf[32];
        uint16_t bytesRead;
        uint8_t i;
        int clientIdx;
        
        dbg("transport", "Chat: Data received on socket %d\n", fd);
        
        if(isServer) {
            // Server: find which client this is or create entry
            clientIdx = findClientBySocket(fd);
            if(clientIdx < 0) {
                // New connection, find empty slot
                for(i = 0; i < MAX_CLIENTS; i++) {
                    if(!clients[i].active) {
                        clients[i].active = 1;
                        clients[i].socketFd = fd;
                        clients[i].addr = call Transport.getSocketSrcAddr(fd);
                        clients[i].username[0] = '\0';
                        recvLen[i] = 0;
                        clientIdx = i;
                        break;
                    }
                }
            }
            
            if(clientIdx >= 0) {
                // Read available data
                bytesRead = call Transport.read(fd, tempBuf, 32);
                
                // Append to buffer and look for \r\n
                for(i = 0; i < bytesRead && recvLen[clientIdx] < 62; i++) {
                    recvBuffer[clientIdx][recvLen[clientIdx]++] = tempBuf[i];
                    
                    // Check for message terminator \r\n
                    if(recvLen[clientIdx] >= 2 && 
                       recvBuffer[clientIdx][recvLen[clientIdx]-2] == '\r' &&
                       recvBuffer[clientIdx][recvLen[clientIdx]-1] == '\n') {
                        // Complete message received
                        processServerMessage(fd, recvBuffer[clientIdx], recvLen[clientIdx]);
                        recvLen[clientIdx] = 0;
                    }
                }
            }
        }
        else if(isClient && fd == clientFd) {
            // Client: read and process
            bytesRead = call Transport.read(fd, tempBuf, 32);
            
            for(i = 0; i < bytesRead && clientRecvLen < 62; i++) {
                clientRecvBuf[clientRecvLen++] = tempBuf[i];
                
                if(clientRecvLen >= 2 && 
                   clientRecvBuf[clientRecvLen-2] == '\r' &&
                   clientRecvBuf[clientRecvLen-1] == '\n') {
                    processClientMessage(clientRecvBuf, clientRecvLen);
                    clientRecvLen = 0;
                }
            }
        }
    }
    
    // Timer for periodic maintenance
    event void ChatTimer.fired() {
        // Can be used for timeout handling if needed
    }
    
    // Default event handlers
    default event void Chat.connected() {}
    default event void Chat.messageReceived(char* from, char* message) {}
    default event void Chat.userListReceived(char* userList) {}
}