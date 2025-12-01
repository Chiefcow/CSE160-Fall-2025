#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

/**
 * TransportP - Simplified TCP Implementation
 * 
 * Features:
 * - Connection setup/teardown (3-way handshake, FIN)
 * - Stop-and-wait data transfer
 * - Flow control with advertised window
 * - Multiple concurrent connections
 * - Timeout and retransmission
 */

module TransportP {
    provides interface Transport;
    
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as TransportTimer;
    uses interface LinkState;
}

implementation {
    // Socket storage - array of sockets for multiple concurrent connections
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    
    // Retransmission tracking
    uint16_t retransmitCounter[MAX_NUM_OF_SOCKETS];

    // static bool initialized = FALSE;
    
    // ==================== HELPER FUNCTIONS ====================
    
    /**
     * Initialize all sockets to CLOSED state
     */
    void initSockets() {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].state = CLOSED;
            sockets[i].flag = 0;
            sockets[i].src = 0;
            sockets[i].dest.port = 0;
            sockets[i].dest.addr = 0;
            sockets[i].lastWritten = 0;
            sockets[i].lastAck = 0;
            sockets[i].lastSent = 0;
            sockets[i].lastRead = 0;
            sockets[i].lastRcvd = 0;
            sockets[i].nextExpected = 0;
            sockets[i].RTT = TCP_TIMEOUT;
            sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
            retransmitCounter[i] = 0;
        }
        
        // Start the transport timer for periodic checks
        call TransportTimer.startPeriodic(TCP_TIMER_INTERVAL);
        
        dbg(TRANSPORT_CHANNEL, "Transport: Sockets initialized\n");
    }

    command error_t Transport.start() {
        static bool initialized = FALSE;
        // static bool initialized = FALSE;
        if (!initialized) {
            initSockets();
            initialized = TRUE;
            dbg(TRANSPORT_CHANNEL, "Transport: Module started\n");
        }
        return SUCCESS;
    }
    

    // command error_t Transport.start() {
    //     initSockets();
    //     dbg(TRANSPORT_CHANNEL, "Transport: Started\n");
    //     return SUCCESS;
    // }
    
    /**
     * Send a TCP packet through the network
     */
    void sendTCPPacket(uint16_t dest_addr, uint8_t src_port, uint8_t dest_port, 
                       uint16_t seq, uint16_t ack, uint8_t flags, 
                       uint8_t window, uint8_t* data, uint8_t dataLen) {
        pack tcpPacket;
        tcp_header* tcpHdr;
        uint16_t nextHop;
        uint8_t i;
        
        // Build the network packet
        tcpPacket.src = TOS_NODE_ID;
        tcpPacket.dest = dest_addr;
        tcpPacket.TTL = MAX_TTL;
        tcpPacket.seq = 0;  // Network-level sequence (not used for TCP)
        tcpPacket.protocol = PROTOCOL_TCP;
        
        // Build TCP header in payload
        tcpHdr = (tcp_header*)tcpPacket.payload;
        tcpHdr->src_port = src_port;
        tcpHdr->dest_port = dest_port;
        tcpHdr->seq_num = seq;
        tcpHdr->ack_num = ack;
        tcpHdr->flags = flags;
        tcpHdr->advertised_window = window;
        
        // Copy data if present (only for DATA packets)
        if (data != NULL && dataLen > 0 && (flags & TCP_FLAG_DATA)) {
            for (i = 0; i < dataLen && i < (PACKET_MAX_PAYLOAD_SIZE - sizeof(tcp_header)); i++) {
                tcpHdr->data[i] = data[i];
            }
        }
        
        // Get next hop from routing table
        nextHop = call LinkState.getNextHop(dest_addr);
        
        if (nextHop == AM_BROADCAST_ADDR) {
            dbg(TRANSPORT_CHANNEL, 
                "Transport: ERROR - No route to destination %d\n", dest_addr);
            return;
        }
        
        // Send the packet to next hop
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Sending TCP [flags=0x%02x seq=%d ack=%d] to dest=%d via nextHop=%d\n",
            flags, seq, ack, dest_addr, nextHop);
        
        call Sender.send(tcpPacket, nextHop);
    }

    // command error_t Transport.start() {
    //     // static bool initialized = FALSE;
    //     if (!initialized) {
    //         initSockets();
    //         initialized = TRUE;
    //         dbg(TRANSPORT_CHANNEL, "Transport: Module started\n");
    //     }
    //     return SUCCESS;
    // }
    
    /**
     * Get socket by file descriptor
     */
    socket_store_t* getSocket(socket_t fd) {
        if (fd >= MAX_NUM_OF_SOCKETS) {
            return NULL;
        }
        return &sockets[fd];
    }
    
    /**
     * Find socket by connection tuple (for incoming packets)
     */
    socket_t findSocket(uint16_t src_addr, uint8_t src_port, uint8_t dest_port) {
        uint8_t i;
        
        // First, try to find an exact match (established connection)
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state != CLOSED && sockets[i].state != LISTEN) {
                if (sockets[i].src == dest_port && 
                    sockets[i].dest.addr == src_addr && 
                    sockets[i].dest.port == src_port) {
                    return i;
                }
            }
        }
        
        // If no exact match, check for listening socket
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == LISTEN && sockets[i].src == dest_port) {
                return i;
            }
        }
        
        return NULL_SOCKET;
    }
    
    /**
     * Calculate available space in receive buffer
     */
    uint8_t getAvailableWindow(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        uint16_t used;
        
        if (sock == NULL) {
            return 0;
        }
        
        used = sock->lastRcvd - sock->lastRead;
        if (used >= SOCKET_BUFFER_SIZE) {
            return 0;
        }
        
        return (uint8_t)(SOCKET_BUFFER_SIZE - used);
    }
    
    // ==================== TRANSPORT INTERFACE COMMANDS ====================
    
    /**
     * Allocate a new socket
     */
    command socket_t Transport.socket() {
        uint8_t i;
        
        // Initialize sockets on first call
        static bool initialized = FALSE;
        if (!initialized) {
            initSockets();
            initialized = TRUE;
        }
        
        // Find an available socket
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED && sockets[i].flag == 0) {
                sockets[i].flag = 1;  // Mark as allocated
                dbg(TRANSPORT_CHANNEL, "Transport: Allocated socket fd=%d\n", i);
                return i;
            }
        }
        
        dbg(TRANSPORT_CHANNEL, "Transport: ERROR - No sockets available\n");
        return NULL_SOCKET;
    }
    
    /**
     * Bind a socket to a local port
     */
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL || sock->flag == 0) {
            dbg(TRANSPORT_CHANNEL, "Transport: ERROR - Invalid socket fd=%d\n", fd);
            return FAIL;
        }
        
        sock->src = addr->port;
        
        dbg(TRANSPORT_CHANNEL, "Transport: Socket fd=%d bound to port %d\n", 
            fd, addr->port);
        
        return SUCCESS;
    }
    
    /**
     * Put socket in listening state
     */
    command error_t Transport.listen(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL || sock->flag == 0) {
            dbg(TRANSPORT_CHANNEL, "Transport: ERROR - Invalid socket fd=%d\n", fd);
            return FAIL;
        }
        
        sock->state = LISTEN;
        
        dbg(TRANSPORT_CHANNEL, "Transport: Socket fd=%d listening on port %d\n", 
            fd, sock->src);
        
        return SUCCESS;
    }
    
    /**
     * Accept an incoming connection (returns established socket)
     */
    command socket_t Transport.accept(socket_t fd) {
        uint8_t i;
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL || sock->state != LISTEN) {
            dbg(TRANSPORT_CHANNEL, "Transport: ERROR - Socket fd=%d not listening\n", fd);
            return NULL_SOCKET;
        }
        
        // Find a socket that was recently established from this listening socket
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == ESTABLISHED && 
                sockets[i].src == sock->src && 
                sockets[i].flag == 2) {  // flag=2 indicates newly accepted
                
                sockets[i].flag = 1;  // Clear the "newly accepted" flag
                
                dbg(TRANSPORT_CHANNEL, 
                    "Transport: Accepted connection on socket fd=%d\n", i);
                
                return i;
            }
        }
        
        return NULL_SOCKET;
    }
    
    /**
     * Connect to a remote server
     */
    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL || sock->flag == 0) {
            dbg(TRANSPORT_CHANNEL, "Transport: ERROR - Invalid socket fd=%d\n", fd);
            return FAIL;
        }
        
        // Set destination
        sock->dest = *addr;
        sock->state = SYN_SENT;
        sock->lastSent = 0;
        sock->lastAck = 0;
        sock->nextExpected = 0;
        
        // Send SYN packet
        sendTCPPacket(addr->addr, sock->src, addr->port,
                     0, 0, TCP_FLAG_SYN, 
                     SOCKET_BUFFER_SIZE, NULL, 0);
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Socket fd=%d connecting to %d:%d\n",
            fd, addr->addr, addr->port);
        
        return SUCCESS;
    }
    
    /**
     * Write data to socket (client sends data)
     */
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t* sock = getSocket(fd);
        uint16_t written = 0;
        uint16_t i;
        
        if (sock == NULL || sock->state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, 
                "Transport: ERROR - Socket fd=%d not established\n", fd);
            return 0;
        }
        
        // Write data to send buffer
        for (i = 0; i < bufflen; i++) {
            if ((sock->lastWritten - sock->lastAck) >= SOCKET_BUFFER_SIZE) {
                // Buffer full
                break;
            }
            
            sock->sendBuff[sock->lastWritten % SOCKET_BUFFER_SIZE] = buff[i];
            sock->lastWritten++;
            written++;
        }
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Socket fd=%d wrote %d bytes to buffer\n", fd, written);
        
        return written;
    }
    
    /**
     * Read data from socket (server reads received data)
     */
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t* sock = getSocket(fd);
        uint16_t available;
        uint16_t toRead;
        uint16_t i;
        
        if (sock == NULL) {
            return 0;
        }
        
        available = sock->lastRcvd - sock->lastRead;
        toRead = (available < bufflen) ? available : bufflen;
        
        // Copy data from receive buffer
        for (i = 0; i < toRead; i++) {
            buff[i] = sock->rcvdBuff[sock->lastRead % SOCKET_BUFFER_SIZE];
            sock->lastRead++;
        }
        
        // Update advertised window
        sock->effectiveWindow = getAvailableWindow(fd);
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Socket fd=%d read %d bytes\n", fd, toRead);
        
        return toRead;
    }
    
    /**
     * Close connection (send FIN)
     */
    command error_t Transport.close(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL || sock->state == CLOSED) {
            return FAIL;
        }
        
        if (sock->state == ESTABLISHED) {
            // Send FIN packet
            sendTCPPacket(sock->dest.addr, sock->src, sock->dest.port,
                         sock->lastSent, sock->nextExpected,
                         TCP_FLAG_FIN, sock->effectiveWindow, NULL, 0);
            
            sock->state = FIN_WAIT_1;
            
            dbg(TRANSPORT_CHANNEL, 
                "Transport: Socket fd=%d closing connection\n", fd);
        } else {
            // Just close it
            sock->state = CLOSED;
            sock->flag = 0;
        }
        
        return SUCCESS;
    }
    
    /**
     * Force close socket (hard close)
     */
    command error_t Transport.release(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL) {
            return FAIL;
        }
        
        sock->state = CLOSED;
        sock->flag = 0;
        
        dbg(TRANSPORT_CHANNEL, "Transport: Socket fd=%d released\n", fd);
        
        return SUCCESS;
    }
    
    /**
     * Process incoming TCP packet
     */
    command error_t Transport.receive(pack* package) {
        tcp_header* tcpHdr;
        socket_t sockFd;
        socket_store_t* sock;
        uint8_t dataLen;
        uint8_t i;
        socket_t newFd;
        socket_store_t* newSock;
        
        if (package->protocol != PROTOCOL_TCP) {
            return FAIL;
        }
        
        tcpHdr = (tcp_header*)package->payload;
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Received TCP [flags=0x%02x seq=%d ack=%d] from %d:%d to port %d\n",
            tcpHdr->flags, tcpHdr->seq_num, tcpHdr->ack_num, 
            package->src, tcpHdr->src_port, tcpHdr->dest_port);
        
        // Find the socket for this packet
        sockFd = findSocket(package->src, tcpHdr->src_port, tcpHdr->dest_port);
        
        // ==================== HANDLE SYN ====================
        if (tcpHdr->flags & TCP_FLAG_SYN && !(tcpHdr->flags & TCP_FLAG_ACK)) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                if (sock->state == LISTEN) {
                    // Allocate new socket for this connection
                    newFd = call Transport.socket();
                    if (newFd == NULL_SOCKET) {
                        dbg(TRANSPORT_CHANNEL, 
                            "Transport: ERROR - Cannot accept connection, no sockets\n");
                        return FAIL;
                    }
                    
                    newSock = getSocket(newFd);
                    
                    // Configure new socket
                    newSock->src = tcpHdr->dest_port;
                    newSock->dest.addr = package->src;
                    newSock->dest.port = tcpHdr->src_port;
                    newSock->state = SYN_RCVD;
                    newSock->nextExpected = tcpHdr->seq_num + 1;
                    newSock->lastAck = 0;
                    newSock->lastSent = 0;
                    newSock->lastWritten = 0;
                    newSock->flag = 1;
                    
                    // Send SYN-ACK
                    sendTCPPacket(package->src, tcpHdr->dest_port, tcpHdr->src_port,
                                 0, newSock->nextExpected,
                                 TCP_FLAG_SYN | TCP_FLAG_ACK,
                                 SOCKET_BUFFER_SIZE, NULL, 0);
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Received SYN on listening socket, sent SYN-ACK\n");
                }
            }
            return SUCCESS;
        }
        
        // ==================== HANDLE SYN-ACK ====================
        if ((tcpHdr->flags & (TCP_FLAG_SYN | TCP_FLAG_ACK)) == (TCP_FLAG_SYN | TCP_FLAG_ACK)) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                if (sock->state == SYN_SENT) {
                    sock->nextExpected = tcpHdr->seq_num + 1;
                    sock->lastAck = tcpHdr->ack_num;
                    sock->state = ESTABLISHED;
                    
                    // Send ACK to complete handshake
                    sendTCPPacket(package->src, sock->src, sock->dest.port,
                                 sock->lastSent, sock->nextExpected,
                                 TCP_FLAG_ACK, sock->effectiveWindow, NULL, 0);
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Connection ESTABLISHED (client) on socket fd=%d\n", sockFd);


                    signal Transport.connectDone(sockFd);
                }
            }
            return SUCCESS;
        }
        
        // ==================== HANDLE ACK ====================
        if (tcpHdr->flags & TCP_FLAG_ACK) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                // Complete 3-way handshake (server side)
                if (sock->state == SYN_RCVD && !(tcpHdr->flags & TCP_FLAG_DATA)) {
                    sock->state = ESTABLISHED;
                    sock->flag = 2;  // Mark as newly accepted
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Connection ESTABLISHED (server) on socket fd=%d\n", sockFd);
                }
                
                // Update acknowledgment
                if (tcpHdr->ack_num > sock->lastAck) {
                    sock->lastAck = tcpHdr->ack_num;
                    retransmitCounter[sockFd] = 0;  // Reset retransmission counter
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: ACK received for seq=%d\n", tcpHdr->ack_num);
                }
                
                // Handle FIN_WAIT_1 -> FIN_WAIT_2 transition
                if (sock->state == FIN_WAIT_1) {
                    sock->state = FIN_WAIT_2;
                }
            }
            
            // If pure ACK, we're done
            if (tcpHdr->flags == TCP_FLAG_ACK) {
                return SUCCESS;
            }
        }
        
        // ==================== HANDLE DATA ====================
        if (tcpHdr->flags & TCP_FLAG_DATA) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                if (sock->state == ESTABLISHED) {
                    // Check if this is the expected sequence
                    if (tcpHdr->seq_num == sock->nextExpected) {
                        // Calculate data length
                        dataLen = PACKET_MAX_PAYLOAD_SIZE - sizeof(tcp_header);
                        
                        // Copy data to receive buffer
                        for (i = 0; i < dataLen; i++) {
                            if ((sock->lastRcvd - sock->lastRead) >= SOCKET_BUFFER_SIZE) {
                                break;  // Buffer full
                            }
                            sock->rcvdBuff[sock->lastRcvd % SOCKET_BUFFER_SIZE] = tcpHdr->data[i];
                            sock->lastRcvd++;
                        }
                        
                        sock->nextExpected += i;  // Update expected sequence
                        sock->effectiveWindow = getAvailableWindow(sockFd);
                        
                        // Send ACK
                        sendTCPPacket(package->src, sock->src, sock->dest.port,
                                     sock->lastSent, sock->nextExpected,
                                     TCP_FLAG_ACK, sock->effectiveWindow, NULL, 0);
                        
                        dbg(TRANSPORT_CHANNEL, 
                            "Transport: Received %d bytes, sent ACK\n", i);
                    } else {
                        dbg(TRANSPORT_CHANNEL, 
                            "Transport: Out-of-order packet (expected %d, got %d)\n",
                            sock->nextExpected, tcpHdr->seq_num);
                    }
                }
            }
            return SUCCESS;
        }
        
        // ==================== HANDLE FIN ====================
        if (tcpHdr->flags & TCP_FLAG_FIN) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                // Send ACK for FIN
                sendTCPPacket(package->src, sock->src, sock->dest.port,
                             sock->lastSent, tcpHdr->seq_num + 1,
                             TCP_FLAG_ACK, sock->effectiveWindow, NULL, 0);
                
                if (sock->state == FIN_WAIT_2) {
                    sock->state = CLOSED;
                    sock->flag = 0;
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Connection fully closed on socket fd=%d\n", sockFd);
                } else {
                    sock->state = CLOSE_WAIT;
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Received FIN, entering CLOSE_WAIT\n");
                }
            }
            return SUCCESS;
        }
        
        return SUCCESS;
    }
    
    /**
     * Timer event for data transmission and retransmission (Stop-and-Wait)
     */
    event void TransportTimer.fired() {
        uint8_t i;
        socket_store_t* sock;
        uint16_t bytesToSend;
        uint8_t dataLen;
        uint8_t data[PACKET_MAX_PAYLOAD_SIZE - sizeof(tcp_header)];
        uint16_t j;
        
        // Check each socket for pending data
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sock = &sockets[i];
            
            if (sock->state == ESTABLISHED) {
                bytesToSend = sock->lastWritten - sock->lastSent;
                
                // Stop-and-wait: only send if previous packet was acknowledged
                if (bytesToSend > 0 && sock->lastSent == sock->lastAck) {
                    // Calculate data length to send
                    dataLen = (bytesToSend > (PACKET_MAX_PAYLOAD_SIZE - sizeof(tcp_header))) ? 
                              (PACKET_MAX_PAYLOAD_SIZE - sizeof(tcp_header)) : (uint8_t)bytesToSend;
                    
                    // Copy data from send buffer
                    for (j = 0; j < dataLen; j++) {
                        data[j] = sock->sendBuff[(sock->lastSent + j) % SOCKET_BUFFER_SIZE];
                    }
                    
                    // Send DATA packet
                    sendTCPPacket(sock->dest.addr, sock->src, sock->dest.port,
                                 sock->lastSent, sock->nextExpected,
                                 TCP_FLAG_DATA | TCP_FLAG_ACK,
                                 sock->effectiveWindow, data, dataLen);
                    
                    sock->lastSent += dataLen;
                    retransmitCounter[i] = 0;
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Sent %d bytes on socket fd=%d (seq=%d)\n",
                        dataLen, i, sock->lastSent - dataLen);
                }
                // Check for timeout and retransmit
                else if (sock->lastSent > sock->lastAck) {
                    retransmitCounter[i]++;
                    
                    if (retransmitCounter[i] >= (sock->RTT / TCP_TIMER_INTERVAL)) {
                        // Timeout! Retransmit
                        sock->lastSent = sock->lastAck;  // Reset to last ACKed position
                        retransmitCounter[i] = 0;
                        
                        dbg(TRANSPORT_CHANNEL, 
                            "Transport: Timeout on socket fd=%d, retransmitting from seq=%d\n",
                            i, sock->lastAck);
                    }
                }
            }
        }
    }
}
