#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

module TransportP {
    provides interface Transport;
    
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as TransportTimer;
    uses interface Timer<TMilli> as ClientWriteTimer;
}

implementation {
    // Socket storage - array of sockets for multiple concurrent connections
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    
    // Initialize all sockets to CLOSED state
    void initSockets() {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].state = CLOSED;
            sockets[i].src = 0;
            sockets[i].dest.port = 0;
            sockets[i].dest.addr = 0;
            sockets[i].flag = 0;
            sockets[i].lastWritten = 0;
            sockets[i].lastAck = 0;
            sockets[i].lastSent = 0;
            sockets[i].lastRead = 0;
            sockets[i].lastRcvd = 0;
            sockets[i].nextExpected = 0;
            sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
        }
        
        // Start the transport timer for periodic checks
        call TransportTimer.startPeriodic(TCP_TIMER_INTERVAL);
        
        dbg(TRANSPORT_CHANNEL, "Transport: Sockets initialized\n");
    }
    
    // Helper function to send TCP packet
    void sendTCPPacket(uint16_t dest_addr, uint8_t src_port, uint8_t dest_port, 
                       uint16_t seq, uint16_t ack, uint8_t flags, 
                       uint8_t window, uint8_t* data, uint8_t dataLen) {
        pack tcpPacket;
        tcp_header tcpHdr;
        
        // Build TCP header
        tcpHdr.src_port = src_port;
        tcpHdr.dest_port = dest_port;
        tcpHdr.seq_num = seq;
        tcpHdr.ack_num = ack;
        tcpHdr.flags = flags;
        tcpHdr.advertised_window = window;
        
        // Copy data if present (only for DATA packets, not SYN/ACK/FIN)
        if (data != NULL && dataLen > 0 && (flags & TCP_FLAG_DATA)) {
            memcpy(tcpHdr.data, data, dataLen);
        }
        
        // Build the network packet
        tcpPacket.src = TOS_NODE_ID;
        tcpPacket.dest = dest_addr;
        tcpPacket.TTL = MAX_TTL;
        tcpPacket.seq = 0; // Network-level sequence (not used for TCP)
        tcpPacket.protocol = PROTOCOL_TCP;
        
        // Copy TCP header into packet payload
        memcpy(tcpPacket.payload, &tcpHdr, sizeof(tcp_header));
        
        // Send the packet
        call Sender.send(tcpPacket, dest_addr);
    }
    
    // Find a socket by file descriptor
    socket_store_t* getSocket(socket_t fd) {
        if (fd >= MAX_NUM_OF_SOCKETS) {
            return NULL;
        }
        return &sockets[fd];
    }
    
    // Find socket by connection tuple (used for matching incoming packets)
    socket_t findSocket(uint16_t src_addr, uint8_t src_port, uint8_t dest_port) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state != CLOSED) {
                // Match on local port and (if connected) remote address/port
                if (sockets[i].src == dest_port) {
                    if (sockets[i].state == LISTEN) {
                        // Listening socket matches any source
                        return i;
                    } else if (sockets[i].dest.addr == src_addr && 
                               sockets[i].dest.port == src_port) {
                        // Established connection must match both
                        return i;
                    }
                }
            }
        }
        return NULL_SOCKET;
    }
    
    /**
     * Get a socket if there is one available.
     * Returns a socket file descriptor or NULL_SOCKET if none available.
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
            if (sockets[i].state == CLOSED) {
                sockets[i].state = CLOSED; // Mark as allocated but closed
                sockets[i].flag = 0;
                dbg(TRANSPORT_CHANNEL, "Transport: Allocated socket %d\n", i);
                return i;
            }
        }
        
        dbg(TRANSPORT_CHANNEL, "Transport: No sockets available\n");
        return NULL_SOCKET;
    }
    
    /**
     * Bind a socket with an address (source port and address).
     */
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL) {
            dbg(TRANSPORT_CHANNEL, "Transport: Invalid socket fd %d\n", fd);
            return FAIL;
        }
        
        // Bind the socket to the local port
        sock->src = addr->port;
        
        dbg(TRANSPORT_CHANNEL, "Transport: Socket %d bound to port %d\n", 
            fd, addr->port);
        
        return SUCCESS;
    }
    
    /**
     * Listen for incoming connections on this socket.
     */
    command error_t Transport.listen(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL) {
            return FAIL;
        }
        
        // Change state to LISTEN
        sock->state = LISTEN;
        
        dbg(TRANSPORT_CHANNEL, "Transport: Socket %d now listening on port %d\n", 
            fd, sock->src);
        
        return SUCCESS;
    }
    
    /**
     * Accept a connection - check if there's a pending connection.
     * Returns a new socket fd for the connection, or NULL_SOCKET if none.
     */
    command socket_t Transport.accept(socket_t fd) {
        socket_store_t* listenSock = getSocket(fd);
        socket_t newFd;
        uint8_t i;
        
        if (listenSock == NULL || listenSock->state != LISTEN) {
            return NULL_SOCKET;
        }
        
        // Look for a socket in SYN_RCVD state that was created from this listener
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == ESTABLISHED && 
                sockets[i].src == listenSock->src &&
                sockets[i].flag == 1) { // Flag marks newly established connection
                
                sockets[i].flag = 0; // Clear the flag
                
                dbg(TRANSPORT_CHANNEL, 
                    "Transport: Accepted connection on socket %d (new fd %d) from %d:%d\n",
                    fd, i, sockets[i].dest.addr, sockets[i].dest.port);
                
                return i;
            }
        }
        
        return NULL_SOCKET;
    }
    
    /**
     * Connect to a remote address (client-side connection establishment).
     */
    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL) {
            return FAIL;
        }
        
        // Set destination
        sock->dest.addr = addr->addr;
        sock->dest.port = addr->port;
        sock->state = SYN_SENT;
        
        // Initialize sequence numbers
        sock->lastSent = 0;
        sock->lastAck = 0;
        sock->nextExpected = 0;
        
        // Send SYN packet
        sendTCPPacket(sock->dest.addr, sock->src, sock->dest.port,
                     0, 0, TCP_FLAG_SYN, SOCKET_BUFFER_SIZE, NULL, 0);
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Socket %d connecting to %d:%d (SYN sent)\n",
            fd, addr->addr, addr->port);
        
        return SUCCESS;
    }
    
    /**
     * Write data to the socket buffer.
     * Returns the number of bytes actually written.
     */
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t* sock = getSocket(fd);
        uint16_t i;
        uint16_t written = 0;
        uint16_t available;
        
        if (sock == NULL || sock->state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, "Transport: Cannot write - socket not established\n");
            return 0;
        }
        
        // Calculate available space in send buffer
        // Available = BUFFER_SIZE - (lastWritten - lastAck)
        available = SOCKET_BUFFER_SIZE - (sock->lastWritten - sock->lastAck);
        
        // Write as much as we can
        for (i = 0; i < bufflen && i < available; i++) {
            sock->sendBuff[(sock->lastWritten + i) % SOCKET_BUFFER_SIZE] = buff[i];
            written++;
        }
        
        sock->lastWritten += written;
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Socket %d wrote %d bytes (lastWritten=%d, lastAck=%d)\n",
            fd, written, sock->lastWritten, sock->lastAck);
        
        return written;
    }
    
    /**
     * Read data from the socket receive buffer.
     * Returns the number of bytes actually read.
     */
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t* sock = getSocket(fd);
        uint16_t i;
        uint16_t bytesRead = 0;
        uint16_t available;
        
        if (sock == NULL) {
            return 0;
        }
        
        // Calculate available data in receive buffer
        available = sock->lastRcvd - sock->lastRead;
        
        // Read as much as requested or available
        for (i = 0; i < bufflen && i < available; i++) {
            buff[i] = sock->rcvdBuff[(sock->lastRead + i) % SOCKET_BUFFER_SIZE];
            bytesRead++;
        }
        
        sock->lastRead += bytesRead;
        
        // Update advertised window
        sock->effectiveWindow = SOCKET_BUFFER_SIZE - (sock->lastRcvd - sock->lastRead);
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Socket %d read %d bytes (lastRead=%d, lastRcvd=%d)\n",
            fd, bytesRead, sock->lastRead, sock->lastRcvd);
        
        return bytesRead;
    }
    
    /**
     * Close the socket gracefully (send FIN).
     */
    command error_t Transport.close(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL) {
            return FAIL;
        }
        
        if (sock->state == ESTABLISHED) {
            // Send FIN packet
            sendTCPPacket(sock->dest.addr, sock->src, sock->dest.port,
                         sock->lastWritten, sock->nextExpected, 
                         TCP_FLAG_FIN, sock->effectiveWindow, NULL, 0);
            
            dbg(TRANSPORT_CHANNEL, 
                "Transport: Socket %d closing connection (FIN sent)\n", fd);
        }
        
        // Reset socket to CLOSED state
        sock->state = CLOSED;
        sock->src = 0;
        sock->dest.addr = 0;
        sock->dest.port = 0;
        
        return SUCCESS;
    }
    
    /**
     * Hard close without graceful shutdown.
     */
    command error_t Transport.release(socket_t fd) {
        socket_store_t* sock = getSocket(fd);
        
        if (sock == NULL) {
            return FAIL;
        }
        
        sock->state = CLOSED;
        dbg(TRANSPORT_CHANNEL, "Transport: Socket %d released\n", fd);
        
        return SUCCESS;
    }
    
    /**
     * Handle incoming TCP packets.
     */
    command error_t Transport.receive(pack* package) {
        tcp_header* tcpHdr;
        socket_t sockFd;
        socket_store_t* sock;
        socket_t newFd;
        uint8_t dataLen;
        uint8_t i;
        
        if (package->protocol != PROTOCOL_TCP) {
            return FAIL;
        }
        
        tcpHdr = (tcp_header*)package->payload;
        
        dbg(TRANSPORT_CHANNEL, 
            "Transport: Received TCP packet from %d:%d to port %d, flags=0x%x, seq=%d, ack=%d\n",
            package->src, tcpHdr->src_port, tcpHdr->dest_port, 
            tcpHdr->flags, tcpHdr->seq_num, tcpHdr->ack_num);
        
        // Find the socket for this connection
        sockFd = findSocket(package->src, tcpHdr->src_port, tcpHdr->dest_port);
        
        // Handle SYN (connection request)
        if (tcpHdr->flags & TCP_FLAG_SYN) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                if (sock->state == LISTEN) {
                    // Create new socket for this connection
                    newFd = call Transport.socket();
                    if (newFd != NULL_SOCKET) {
                        socket_store_t* newSock = getSocket(newFd);
                        
                        // Set up the new socket
                        newSock->src = tcpHdr->dest_port;
                        newSock->dest.addr = package->src;
                        newSock->dest.port = tcpHdr->src_port;
                        newSock->state = SYN_RCVD;
                        newSock->nextExpected = tcpHdr->seq_num + 1;
                        newSock->lastAck = 0;
                        newSock->lastWritten = 0;
                        newSock->flag = 0; // Will be set to 1 when ESTABLISHED
                        
                        // Send SYN-ACK
                        sendTCPPacket(package->src, tcpHdr->dest_port, tcpHdr->src_port,
                                     0, newSock->nextExpected, 
                                     TCP_FLAG_SYN | TCP_FLAG_ACK, 
                                     SOCKET_BUFFER_SIZE, NULL, 0);
                        
                        dbg(TRANSPORT_CHANNEL, 
                            "Debug(1): Syn Packet Arrived from Node %d for Port %d\n",
                            package->src, tcpHdr->dest_port);
                        dbg(TRANSPORT_CHANNEL, 
                            "Debug(1): Syn Ack Packet Sent to Node %d for Port %d\n",
                            package->src, tcpHdr->src_port);
                    }
                } else if (sock->state == SYN_SENT) {
                    // Simultaneous open (not required but handle gracefully)
                    sock->nextExpected = tcpHdr->seq_num + 1;
                    sock->state = SYN_RCVD;
                    
                    // Send SYN-ACK
                    sendTCPPacket(package->src, sock->src, sock->dest.port,
                                 sock->lastSent, sock->nextExpected,
                                 TCP_FLAG_SYN | TCP_FLAG_ACK,
                                 sock->effectiveWindow, NULL, 0);
                }
            }
            return SUCCESS;
        }
        
        // Handle SYN-ACK (response to connection request)
        if ((tcpHdr->flags & (TCP_FLAG_SYN | TCP_FLAG_ACK)) == (TCP_FLAG_SYN | TCP_FLAG_ACK)) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                if (sock->state == SYN_SENT) {
                    sock->nextExpected = tcpHdr->seq_num + 1;
                    sock->state = ESTABLISHED;
                    
                    // Send ACK to complete 3-way handshake
                    sendTCPPacket(package->src, sock->src, sock->dest.port,
                                 sock->lastSent, sock->nextExpected,
                                 TCP_FLAG_ACK, sock->effectiveWindow, NULL, 0);
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Socket %d connection ESTABLISHED\n", sockFd);
                }
            }
            return SUCCESS;
        }
        
        // Handle ACK
        if (tcpHdr->flags & TCP_FLAG_ACK) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                // If in SYN_RCVD, this completes the 3-way handshake
                if (sock->state == SYN_RCVD) {
                    sock->state = ESTABLISHED;
                    sock->flag = 1; // Mark as newly established for accept()
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Socket %d connection ESTABLISHED (server side)\n", 
                        sockFd);
                }
                
                // Update lastAck based on acknowledgment number
                if (tcpHdr->ack_num > sock->lastAck) {
                    sock->lastAck = tcpHdr->ack_num;
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Socket %d received ACK for seq %d\n",
                        sockFd, tcpHdr->ack_num);
                }
            }
            
            // If only ACK flag, we're done
            if (tcpHdr->flags == TCP_FLAG_ACK) {
                return SUCCESS;
            }
        }
        
        // Handle DATA
        if (tcpHdr->flags & TCP_FLAG_DATA) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                if (sock->state == ESTABLISHED) {
                    // Check if this is the expected sequence number
                    if (tcpHdr->seq_num == sock->nextExpected) {
                        // Calculate data length (total payload - TCP header size)
                        dataLen = PACKET_MAX_PAYLOAD_SIZE - 8;
                        
                        // Copy data into receive buffer
                        for (i = 0; i < dataLen; i++) {
                            if ((sock->lastRcvd - sock->lastRead) >= SOCKET_BUFFER_SIZE) {
                                break; // Buffer full
                            }
                            sock->rcvdBuff[sock->lastRcvd % SOCKET_BUFFER_SIZE] = tcpHdr->data[i];
                            sock->lastRcvd++;
                        }
                        
                        sock->nextExpected = tcpHdr->seq_num + dataLen;
                        sock->effectiveWindow = SOCKET_BUFFER_SIZE - (sock->lastRcvd - sock->lastRead);
                        
                        // Send ACK
                        sendTCPPacket(package->src, sock->src, sock->dest.port,
                                     sock->lastSent, sock->nextExpected,
                                     TCP_FLAG_ACK, sock->effectiveWindow, NULL, 0);
                        
                        dbg(TRANSPORT_CHANNEL, 
                            "Transport: Socket %d received %d bytes of data (seq=%d)\n",
                            sockFd, dataLen, tcpHdr->seq_num);
                    } else {
                        dbg(TRANSPORT_CHANNEL, 
                            "Transport: Out-of-order packet (expected %d, got %d)\n",
                            sock->nextExpected, tcpHdr->seq_num);
                    }
                }
            }
            return SUCCESS;
        }
        
        // Handle FIN (connection termination)
        if (tcpHdr->flags & TCP_FLAG_FIN) {
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                
                // Send ACK for FIN
                sendTCPPacket(package->src, sock->src, sock->dest.port,
                             sock->lastSent, tcpHdr->seq_num + 1,
                             TCP_FLAG_ACK, sock->effectiveWindow, NULL, 0);
                
                dbg(TRANSPORT_CHANNEL, 
                    "Transport: Socket %d received FIN, connection closing\n", sockFd);
                
                // Close the socket
                sock->state = CLOSED;
            }
            return SUCCESS;
        }
        
        return SUCCESS;
    }
    
    /**
     * Timer event for sending data and handling retransmissions.
     */
    event void TransportTimer.fired() {
        uint8_t i;
        socket_store_t* sock;
        uint16_t bytesToSend;
        uint8_t dataLen;
        uint8_t data[PACKET_MAX_PAYLOAD_SIZE - 8];
        uint16_t j;
        
        // Check each socket for pending data to send
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sock = &sockets[i];
            
            if (sock->state == ESTABLISHED) {
                // Check if we have data to send (stop-and-wait)
                bytesToSend = sock->lastWritten - sock->lastSent;
                
                if (bytesToSend > 0 && sock->lastSent == sock->lastAck) {
                    // We can send (previous data was acknowledged)
                    dataLen = (bytesToSend > (PACKET_MAX_PAYLOAD_SIZE - 8)) ? 
                              (PACKET_MAX_PAYLOAD_SIZE - 8) : bytesToSend;
                    
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
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Transport: Socket %d sent %d bytes (seq=%d)\n",
                        i, dataLen, sock->lastSent - dataLen);
                }
            }
        }
    }
    
    event void ClientWriteTimer.fired() {
        // This timer is managed externally by the test commands
    }
}
