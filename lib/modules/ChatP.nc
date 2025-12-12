#include "../../includes/channels.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/chat.h"

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
    uint32_t serverTime = 0;  // For timeout tracking
    
    // Client state
    bool isClient = FALSE;
    socket_t clientFd = 0;
    char myUsername[MAX_USERNAME_LEN + 1];
    uint8_t myPort = 0;
    bool connected = FALSE;
    
    // Buffer for receiving data - per socket for server
    uint8_t recvBuffer[MAX_CLIENTS][CHAT_RECV_BUFFER_SIZE];
    uint8_t recvLen[MAX_CLIENTS];
    
    // Client receive buffer
    uint8_t clientRecvBuf[CHAT_RECV_BUFFER_SIZE];
    uint8_t clientRecvLen = 0;
    
    // Function prototypes
    void initClients();
    void safeCopy(char* dest, char* src, uint8_t maxLen);
    uint8_t getStringLen(char* str);
    bool stringEquals(char* a, char* b);
    bool isValidUsername(char* username);
    int findClientByUsername(char* username);
    int findClientBySocket(socket_t fd);
    int findFreeClientSlot();
    void cleanupClient(uint8_t clientIdx);
    void checkClientTimeouts();
    void sendError(socket_t fd, uint8_t errorCode, char* errorMsg);
    void broadcastToClients(char* sender, char* message);
    void sendUserList(uint8_t clientIdx);
    void sendWhisperTo(char* fromUser, char* toUser, char* message);
    void processServerMessage(socket_t fd, uint8_t* data, uint8_t len);
    void processClientMessage(uint8_t* data, uint8_t len);
    
    // Initialize client array
    void initClients() {
        uint8_t i;
        for(i = 0; i < MAX_CLIENTS; i++) {
            clients[i].active = 0;
            clients[i].socketFd = 0;
            clients[i].lastActivity = 0;
            recvLen[i] = 0;
        }
        numClients = 0;
        serverTime = 0;
    }
    
    // Safe string copy with bounds checking
    void safeCopy(char* dest, char* src, uint8_t maxLen) {
        uint8_t i;
        for(i = 0; i < maxLen - 1 && src[i] != '\0'; i++) {
            dest[i] = src[i];
        }
        dest[i] = '\0';
    }
    
    // Get string length safely
    uint8_t getStringLen(char* str) {
        uint8_t len = 0;
        while(str[len] != '\0' && len < 128) len++;
        return len;
    }
    
    // Compare strings
    bool stringEquals(char* a, char* b) {
        uint8_t i = 0;
        while(a[i] != '\0' && b[i] != '\0') {
            if(a[i] != b[i]) return FALSE;
            i++;
        }
        return a[i] == b[i];
    }
    
    // Validate username (not empty, not duplicate, within length)
    bool isValidUsername(char* username) {
        uint8_t i, len;
        
        // Check for NULL or empty
        if(username == NULL || username[0] == '\0') {
            return FALSE;
        }
        
        // Check length
        len = getStringLen(username);
        if(len > MAX_USERNAME_LEN) {
            return FALSE;
        }
        
        // Check for duplicates
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active && stringEquals(clients[i].username, username)) {
                return FALSE;
            }
        }
        
        return TRUE;
    }
    
    // Find client by username
    int findClientByUsername(char* username) {
        uint8_t i;
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active && stringEquals(clients[i].username, username)) {
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
    
    // Find free client slot
    int findFreeClientSlot() {
        uint8_t i;
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(!clients[i].active) {
                return i;
            }
        }
        return -1;
    }
    
    // Cleanup client slot
    void cleanupClient(uint8_t clientIdx) {
        if(clientIdx >= MAX_CLIENTS) return;
        
        dbg("transport", "Chat: Cleaning up client slot %d (%s)\n", 
            clientIdx, clients[clientIdx].username);
        
        // Close socket if still open
        if(clients[clientIdx].socketFd != 0) {
            call Transport.close(clients[clientIdx].socketFd);
        }
        
        // Clear client data
        clients[clientIdx].active = 0;
        clients[clientIdx].socketFd = 0;
        clients[clientIdx].username[0] = '\0';
        clients[clientIdx].lastActivity = 0;
        recvLen[clientIdx] = 0;
        
        if(numClients > 0) numClients--;
    }
    
    // Check for inactive clients and timeout
    void checkClientTimeouts() {
        uint8_t i;
        if(!isServer) return;
        
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active) {
                if((serverTime - clients[i].lastActivity) > CLIENT_TIMEOUT) {
                    dbg("transport", "Chat: Client %s timed out\n", clients[i].username);
                    cleanupClient(i);
                }
            }
        }
    }
    
    // Send error message to client
    void sendError(socket_t fd, uint8_t errorCode, char* errorMsg) {
        uint8_t buffer[CHAT_SEND_BUFFER_SIZE];
        uint8_t len = 0;
        uint8_t i;
        
        // Format: "error [code] [message]\r\n"
        buffer[len++] = 'e';
        buffer[len++] = 'r';
        buffer[len++] = 'r';
        buffer[len++] = 'o';
        buffer[len++] = 'r';
        buffer[len++] = ' ';
        buffer[len++] = '0' + errorCode;
        buffer[len++] = ' ';
        
        for(i = 0; errorMsg[i] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 3; i++) {
            buffer[len++] = errorMsg[i];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending error %d: %s\n", errorCode, errorMsg);
        call Transport.send(fd, buffer, len);
    }
    
    // ==================== SERVER FUNCTIONS ====================
    
    // Broadcast message to all connected clients
    void broadcastToClients(char* sender, char* message) {
        uint8_t i;
        uint8_t buffer[CHAT_SEND_BUFFER_SIZE];
        uint8_t len = 0;
        uint8_t j;
        
        // Check message length
        if(getStringLen(sender) + getStringLen(message) + MAX_BROADCAST_PREFIX > CHAT_SEND_BUFFER_SIZE) {
            dbg("transport", "Chat: Broadcast message too long\n");
            return;
        }
        
        // Format: "msg sender: message\r\n"
        buffer[len++] = 'm';
        buffer[len++] = 's';
        buffer[len++] = 'g';
        buffer[len++] = ' ';
        
        for(j = 0; sender[j] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 4; j++) {
            buffer[len++] = sender[j];
        }
        buffer[len++] = ':';
        buffer[len++] = ' ';
        
        for(j = 0; message[j] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 2; j++) {
            buffer[len++] = message[j];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Broadcasting from %s: %s\n", sender, message);
        
        for(i = 0; i < MAX_CLIENTS; i++) {
            if(clients[i].active && clients[i].socketFd != 0) {
                if(call Transport.send(clients[i].socketFd, buffer, len) == 0) {
                    dbg("transport", "Chat: Failed to send to client %d\n", i);
                }
            }
        }
    }
    
    // Send user list to requesting client
    void sendUserList(uint8_t clientIdx) {
        uint8_t buffer[CHAT_SEND_BUFFER_SIZE];
        uint8_t len = 0;
        uint8_t i, j;
        bool first = TRUE;
        char* prefix = "listUsrRply ";
        
        for(j = 0; prefix[j] != '\0'; j++) {
            buffer[len++] = prefix[j];
        }
        
        for(i = 0; i < MAX_CLIENTS && len < CHAT_SEND_BUFFER_SIZE - 3; i++) {
            if(clients[i].active) {
                if(!first && len < CHAT_SEND_BUFFER_SIZE - 3) {
                    buffer[len++] = ',';
                    buffer[len++] = ' ';
                }
                first = FALSE;
                for(j = 0; clients[i].username[j] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 3; j++) {
                    buffer[len++] = clients[i].username[j];
                }
            }
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending user list to client %d\n", clientIdx);
        
        if(clients[clientIdx].active && clients[clientIdx].socketFd != 0) {
            if(call Transport.send(clients[clientIdx].socketFd, buffer, len) == 0) {
                dbg("transport", "Chat: Failed to send user list\n");
            }
        }
    }
    
    // Send whisper to specific user
    void sendWhisperTo(char* fromUser, char* toUser, char* message) {
        int idx = findClientByUsername(toUser);
        int fromIdx = findClientByUsername(fromUser);
        uint8_t buffer[CHAT_SEND_BUFFER_SIZE];
        uint8_t len = 0;
        uint8_t j;
        char* prefix = "whisper ";
        
        if(idx < 0) {
            dbg("transport", "Chat: Whisper target %s not found\n", toUser);
            // Send error back to sender
            if(fromIdx >= 0) {
                sendError(clients[fromIdx].socketFd, CHAT_ERR_USER_NOT_FOUND, "User not found");
            }
            return;
        }
        
        // Check message length
        if(getStringLen(fromUser) + getStringLen(message) + MAX_WHISPER_PREFIX > CHAT_SEND_BUFFER_SIZE) {
            dbg("transport", "Chat: Whisper message too long\n");
            if(fromIdx >= 0) {
                sendError(clients[fromIdx].socketFd, CHAT_ERR_MESSAGE_TOO_LONG, "Message too long");
            }
            return;
        }
        
        for(j = 0; prefix[j] != '\0'; j++) {
            buffer[len++] = prefix[j];
        }
        for(j = 0; fromUser[j] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 4; j++) {
            buffer[len++] = fromUser[j];
        }
        buffer[len++] = ':';
        buffer[len++] = ' ';
        for(j = 0; message[j] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 2; j++) {
            buffer[len++] = message[j];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Whisper from %s to %s: %s\n", fromUser, toUser, message);
        
        if(clients[idx].active && clients[idx].socketFd != 0) {
            if(call Transport.send(clients[idx].socketFd, buffer, len) == 0) {
                dbg("transport", "Chat: Failed to send whisper\n");
            }
        }
    }
    
    // Process a complete message from client (server side)
    void processServerMessage(socket_t fd, uint8_t* data, uint8_t len) {
        int clientIdx = findClientBySocket(fd);
        char cmd[17];  // 16 + null terminator
        char arg1[MAX_USERNAME_LEN + 2];
        char arg2[MAX_MESSAGE_LEN + 1];
        uint8_t i = 0, j = 0;
        
        // Update activity timestamp
        if(clientIdx >= 0) {
            clients[clientIdx].lastActivity = serverTime;
        }
        
        // Command - with bounds checking
        while(i < len && data[i] != ' ' && data[i] != '\r' && j < 16) {
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
        if(stringEquals(cmd, "hello")) {
            // Validate username
            if(!isValidUsername(arg1)) {
                if(findClientByUsername(arg1) >= 0) {
                    sendError(fd, CHAT_ERR_USERNAME_EXISTS, "Username taken");
                } else {
                    sendError(fd, CHAT_ERR_USERNAME_INVALID, "Invalid username");
                }
                // Don't accept the client
                return;
            }
            
            if(clientIdx < 0) {
                // New client - find empty slot
                clientIdx = findFreeClientSlot();
                if(clientIdx < 0) {
                    sendError(fd, CHAT_ERR_SERVER_FULL, "Server full");
                    call Transport.close(fd);
                    return;
                }
            }
            
            clients[clientIdx].active = 1;
            clients[clientIdx].socketFd = fd;
            clients[clientIdx].addr = call Transport.getSocketSrcAddr(fd);
            clients[clientIdx].lastActivity = serverTime;
            safeCopy(clients[clientIdx].username, arg1, MAX_USERNAME_LEN + 1);
            numClients++;
            dbg("transport", "Chat: User '%s' connected (slot %d, addr %d)\n", 
                arg1, clientIdx, clients[clientIdx].addr);
        }
        // Handle msg command
        else if(stringEquals(cmd, "msg")) {
            if(clientIdx >= 0 && clients[clientIdx].active) {
                // Combine arg1 and arg2 if needed (full message after "msg ")
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
            } else {
                sendError(fd, CHAT_ERR_NOT_CONNECTED, "Not connected");
            }
        }
        // Handle whisper command
        else if(stringEquals(cmd, "whisper")) {
            if(clientIdx >= 0 && clients[clientIdx].active) {
                sendWhisperTo(clients[clientIdx].username, arg1, arg2);
            } else {
                sendError(fd, CHAT_ERR_NOT_CONNECTED, "Not connected");
            }
        }
        // Handle listusr command
        else if(stringEquals(cmd, "listusr")) {
            if(clientIdx >= 0) {
                sendUserList(clientIdx);
            } else {
                sendError(fd, CHAT_ERR_NOT_CONNECTED, "Not connected");
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
        
        // Start timer for client timeout checking
        call ChatTimer.startPeriodic(CLIENT_CHECK_INTERVAL);
        
        dbg("transport", "Chat: Server listening on port %d\n", CHAT_SERVER_PORT);
        return SUCCESS;
    }
    

    command error_t Chat.startClient(char* username, uint8_t clientPort) {
        socket_addr_t src, dest;
        
        // Validate inputs
        if(username == NULL || username[0] == '\0') {
            dbg("transport", "Chat: Invalid username\n");
            return FAIL;
        }
        
        if(clientPort == 0 || clientPort == 255) {
            dbg("transport", "Chat: Invalid client port\n");
            return FAIL;
        }
        
        dbg("transport", "Chat: Starting client '%s' on port %d\n", username, clientPort);
        
        isClient = TRUE;
        safeCopy(myUsername, username, MAX_USERNAME_LEN + 1);
        myPort = clientPort;
        clientRecvLen = 0;
        connected = FALSE;
        
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
        
        call Transport.connect(clientFd, &dest);
        
        
        // call ChatTimer.startPeriodic(CLIENT_CHECK_INTERVAL);
        
        return SUCCESS;
    }
    
    command error_t Chat.sendMessage(char* message) {
        uint8_t buffer[CHAT_SEND_BUFFER_SIZE];
        uint8_t len = 0;
        uint8_t i;
        uint16_t sent;
        
        if(!connected || clientFd == 0) {
            dbg("transport", "Chat: Cannot send - not connected\n");
            return FAIL;
        }
        
        if(getStringLen(message) > MAX_MESSAGE_LEN - 8) {
            dbg("transport", "Chat: Message too long\n");
            return FAIL;
        }
        
        buffer[len++] = 'm';
        buffer[len++] = 's';
        buffer[len++] = 'g';
        buffer[len++] = ' ';
        
        for(i = 0; message[i] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 2; i++) {
            buffer[len++] = message[i];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending message: %s\n", message);
        sent = call Transport.send(clientFd, buffer, len);
        
        if(sent == 0) {
            dbg("transport", "Chat: Failed to send message\n");
            return FAIL;
        }
        
        return SUCCESS;
    }
    
    command error_t Chat.sendWhisper(char* username, char* message) {
        uint8_t buffer[CHAT_SEND_BUFFER_SIZE];
        uint8_t len = 0;
        uint8_t i;
        uint16_t sent;
        char* prefix = "whisper ";
        
        if(!connected || clientFd == 0) {
            dbg("transport", "Chat: Cannot send - not connected\n");
            return FAIL;
        }
        
        if(getStringLen(username) + getStringLen(message) + 12 > CHAT_SEND_BUFFER_SIZE) {
            dbg("transport", "Chat: Whisper too long\n");
            return FAIL;
        }
        
        for(i = 0; prefix[i] != '\0'; i++) {
            buffer[len++] = prefix[i];
        }
        for(i = 0; username[i] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 3; i++) {
            buffer[len++] = username[i];
        }
        buffer[len++] = ' ';
        for(i = 0; message[i] != '\0' && len < CHAT_SEND_BUFFER_SIZE - 2; i++) {
            buffer[len++] = message[i];
        }
        buffer[len++] = '\r';
        buffer[len++] = '\n';
        
        dbg("transport", "Chat: Sending whisper to %s: %s\n", username, message);
        sent = call Transport.send(clientFd, buffer, len);
        
        if(sent == 0) {
            dbg("transport", "Chat: Failed to send whisper\n");
            return FAIL;
        }
        
        return SUCCESS;
    }
    
    command error_t Chat.requestUserList() {
        uint8_t buffer[16];
        uint16_t sent;
        
        if(!connected || clientFd == 0) {
            dbg("transport", "Chat: Cannot send - not connected\n");
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
        sent = call Transport.send(clientFd, buffer, 9);
        
        if(sent == 0) {
            dbg("transport", "Chat: Failed to send user list request\n");
            return FAIL;
        }
        
        return SUCCESS;
    }
    
    // Process message received by client
    void processClientMessage(uint8_t* data, uint8_t len) {
        char cmd[17];
        char from[MAX_USERNAME_LEN + 2];
        char message[MAX_MESSAGE_LEN + 1];
        uint8_t i = 0, j = 0;
        
        // Parse command
        while(i < len && data[i] != ' ' && data[i] != '\r' && j < 16) {
            cmd[j++] = data[i++];
        }
        cmd[j] = '\0';
        
        if(i < len && data[i] == ' ') i++;
        
        // Parse rest of message
        j = 0;
        while(i < len && data[i] != '\r' && j < MAX_MESSAGE_LEN - 1) {
            message[j++] = data[i++];
        }
        message[j] = '\0';
        
        dbg("transport", "Chat Client: cmd='%s' content='%s'\n", cmd, message);
        
        // Handle error messages
        if(stringEquals(cmd, "error")) {
            dbg("transport", "Chat: Error received: %s\n", message);
            // Could signal error event if needed
            return;
        }
        
        // Handle broadcast or whisper
        if(stringEquals(cmd, "msg") || stringEquals(cmd, "whisper")) {
            // Extract sender name (before colon)
            j = 0;
            i = 0;
            while(message[i] != ':' && message[i] != '\0' && j < MAX_USERNAME_LEN) {
                from[j++] = message[i++];
            }
            from[j] = '\0';
            
            if(message[i] == ':') i++;
            if(message[i] == ' ') i++;
            
            // Extract actual message
            j = 0;
            while(message[i] != '\0' && j < MAX_MESSAGE_LEN - 1) {
                message[j++] = message[i++];
            }
            message[j] = '\0';
            
            dbg("transport", "Chat: Message from %s: %s\n", from, message);
            signal Chat.messageReceived(from, message);
        }
        // Handle user list reply
        else if(stringEquals(cmd, "listUsrRply")) {
            dbg("transport", "Chat: User list: %s\n", message);
            signal Chat.userListReceived(message);
        }
    }
    
   

    //transpot events
    event void Transport.connectDone(socket_t fd) {
        uint8_t buffer[32];
        uint8_t len = 0;
        uint8_t i;
        uint16_t sent;
        
        if(isClient && fd == clientFd && myUsername[0] != '\0') {
            connected = TRUE;
            dbg("transport", "Chat: Client connected to server\n");
            
            // Send hello message
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
            
            sent = call Transport.send(clientFd, buffer, len);
            
            if(sent > 0) {
                signal Chat.connected();
            } else {
                dbg("transport", "Chat: Failed to send hello message\n");
                connected = FALSE;
            }
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
            // Server: find which client this is
            clientIdx = findClientBySocket(fd);
            if(clientIdx < 0) {
                // New connection, find empty slot
                clientIdx = findFreeClientSlot();
                if(clientIdx < 0) {
                    dbg("transport", "Chat: No free client slots\n");
                    sendError(fd, CHAT_ERR_SERVER_FULL, "Server full");
                    call Transport.close(fd);
                    return;
                }
                clients[clientIdx].active = 1;
                clients[clientIdx].socketFd = fd;
                clients[clientIdx].addr = call Transport.getSocketSrcAddr(fd);
                clients[clientIdx].username[0] = '\0';
                clients[clientIdx].lastActivity = serverTime;
                recvLen[clientIdx] = 0;
            }
            
            // Read available data
            bytesRead = call Transport.read(fd, tempBuf, 32);
            
            // Append to buffer and look for \r\n
            for(i = 0; i < bytesRead && recvLen[clientIdx] < CHAT_RECV_BUFFER_SIZE - 1; i++) {
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
        else if(isClient && fd == clientFd) {
            // Client: read and process
            bytesRead = call Transport.read(fd, tempBuf, 32);
            
            for(i = 0; i < bytesRead && clientRecvLen < CHAT_RECV_BUFFER_SIZE - 1; i++) {
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
        if(isServer) {
            serverTime += CLIENT_CHECK_INTERVAL;
            checkClientTimeouts();
        }
        // Could be used for client keepalive if needed
    }
    
    // Default event handlers
    default event void Chat.connected() {}
    default event void Chat.messageReceived(char* from, char* message) {}
    default event void Chat.userListReceived(char* userList) {}
}
