#include "../../includes/channels.h"
#include "../../includes/tcp.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module TransportP {
    provides interface Transport;
    uses interface LinkState;
    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Timer<TMilli> as TransportTimer;
    uses interface List<pending_packet_t> as RetransmitQueue;
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    
    // Pending connection queue for accept()
    #define MAX_PENDING 5
    typedef struct {
        uint16_t srcAddr;
        uint8_t srcPort;
        uint16_t initialSeq;
        bool valid;
    } pending_conn_t;
    
    pending_conn_t pendingConns[MAX_NUM_OF_SOCKETS][MAX_PENDING];
    uint8_t pendingCount[MAX_NUM_OF_SOCKETS];
    
    pending_packet_t retransmitQueues[MAX_NUM_OF_SOCKETS][MAX_RETRANSMIT_QUEUE];
    uint8_t retransmitCount[MAX_NUM_OF_SOCKETS];
    uint32_t currentTime = 0;

    // ========== HELPER FUNCTIONS ==========

    /**
     * Calculate available space in receive buffer
     */
    uint8_t getAdvertisedWindow(uint8_t fd) {
        uint16_t used = sockets[fd].lastRcvd - sockets[fd].lastRead;
        if (used >= SOCKET_BUFFER_SIZE) return 0;
        return SOCKET_BUFFER_SIZE - used;
    }

    /**
     * Check if sequence number has been acknowledged (handles wrap-around)
     * Based on PDF Section: "Checking Acknowledgments"
     */
    bool isAcknowledged(uint16_t seq, uint16_t lastAck, uint16_t lastSent) {
        // Typical case: lastSent >= lastAck
        if (lastSent >= lastAck) {
            // ACKed if: seq < lastAck OR seq > lastSent
            return (seq < lastAck) || (seq > lastSent);
        }
        // Wrap-around case: lastSent < lastAck
        else {
            // ACKed if: seq is between lastAck and lastSent
            return (seq >= lastAck) && (seq <= lastSent);
        }
    }

    /**
     * Find socket by 4-tuple or listening socket
     */
    uint8_t findSocket(uint16_t srcAddr, uint8_t srcPort, uint16_t destAddr, uint8_t destPort) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == 0) continue;
            
            // Exact match (for established connections)
            if (sockets[i].src == destPort && 
                sockets[i].dest.addr == srcAddr && 
                sockets[i].dest.port == srcPort) {
                return i;
            }
            
            // Listening socket match
            if (sockets[i].state == LISTEN && sockets[i].src == destPort) {
                return i;
            }
        }
        return 0;
    }

    /**
     * Add packet to retransmission queue
     */
    void addToRetransmitQueue(socket_t fd, pack* packet, uint16_t seq, uint8_t payloadLen) {
        if (retransmitCount[fd] >= MAX_RETRANSMIT_QUEUE) {
            dbg(TRANSPORT_CHANNEL, "Retransmit queue full for socket %d\n", fd);
            return;
        }

        retransmitQueues[fd][retransmitCount[fd]].packet = *packet;
        retransmitQueues[fd][retransmitCount[fd]].sentTime = currentTime;
        retransmitQueues[fd][retransmitCount[fd]].timeout = currentTime + (2 * sockets[fd].RTT);
        retransmitQueues[fd][retransmitCount[fd]].seq = seq;
        retransmitQueues[fd][retransmitCount[fd]].payloadLen = payloadLen;
        retransmitCount[fd]++;

        dbg(TRANSPORT_CHANNEL, "Added seq %d to retransmit queue (count=%d)\n", 
            seq, retransmitCount[fd]);
    }

    /**
     * Remove acknowledged packets from retransmit queue
     */
    void cleanRetransmitQueue(socket_t fd, uint16_t ackNum) {
        uint8_t i, j;
        uint8_t newCount;
        uint16_t pktSeq;
        uint16_t pktEnd;
        
        newCount = 0;

        for (i = 0; i < retransmitCount[fd]; i++) {
            pktSeq = retransmitQueues[fd][i].seq;
            pktEnd = pktSeq + retransmitQueues[fd][i].payloadLen;

            // If this packet is fully acknowledged, don't keep it
            if (pktEnd <= ackNum) {
                dbg(TRANSPORT_CHANNEL, "Removing acked packet seq %d from queue\n", pktSeq);
                continue;
            }

            // Keep this packet - shift it down
            if (newCount != i) {
                retransmitQueues[fd][newCount] = retransmitQueues[fd][i];
            }
            newCount++;
        }

        retransmitCount[fd] = newCount;
    }

    /**
     * Route and send packet using Link State routing
     */
    void routeAndSend(pack packet, uint16_t dest) {
        uint16_t nextHop = call LinkState.getNextHop(dest);
        tcp_pack* tcp = (tcp_pack*)packet.payload;
        
        dbg(TRANSPORT_CHANNEL, "*** Node %d: SENDING TCP (flags=%d) to dest=%d via nextHop=%d ***\n",
            TOS_NODE_ID, tcp->flags, dest, nextHop);
        
        if (nextHop == AM_BROADCAST_ADDR) {
            dbg(TRANSPORT_CHANNEL, "ERROR: No route to %d, dropping TCP packet\n", dest);
            return;  // Drop packet instead of broadcasting
        }
        
        call Sender.send(packet, nextHop);
    }

    /**
     * Send ACK packet
     */
    void sendAck(socket_t fd) {
        pack packet;
        tcp_pack* tcp;

        tcp = (tcp_pack*)packet.payload;
        tcp->srcPort = sockets[fd].src;
        tcp->destPort = sockets[fd].dest.port;
        tcp->seq = 0;  // ACK doesn't have seq (or use lastSent)
        tcp->ack = sockets[fd].nextExpected;
        tcp->flags = TCP_ACK;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;

        dbg(TRANSPORT_CHANNEL, "Sending ACK with ack=%d\n", tcp->ack);
        routeAndSend(packet, sockets[fd].dest.addr);
    }

    /**
     * Send data with flow control and sliding window
     */
    void sendData(socket_t fd) {
        pack packet;
        tcp_pack* tcp;
        uint8_t payloadInd;
        uint16_t seqToSend;
        uint8_t canSend;
        uint8_t maxPayload;
        uint16_t unsentBytes;
        uint16_t inFlightBytes;

        if (sockets[fd].state != ESTABLISHED) return;

        // Check flow control - don't exceed peer's window
        if (sockets[fd].effectiveWindow == 0) {
            dbg(TRANSPORT_CHANNEL, "Peer window is 0, cannot send\n");
            return;
        }

        // Calculate how much we can send based on:
        // 1. What's been written but not sent
        // 2. Peer's advertised window
        unsentBytes = sockets[fd].lastWritten - sockets[fd].lastSent;
        inFlightBytes = sockets[fd].lastSent - sockets[fd].lastAck;
        
        canSend = sockets[fd].effectiveWindow - inFlightBytes;
        
        if (canSend == 0 || unsentBytes == 0) {
            return;  // Window full or nothing to send
        }

        // Limit to TCP_MAX_PAYLOAD_SIZE and available window
        maxPayload = TCP_MAX_PAYLOAD_SIZE;
        if (canSend < maxPayload) maxPayload = canSend;
        if (unsentBytes < maxPayload) maxPayload = unsentBytes;

        tcp = (tcp_pack*)packet.payload;
        tcp->srcPort = sockets[fd].src;
        tcp->destPort = sockets[fd].dest.port;
        tcp->flags = TCP_DATA;
        tcp->window = getAdvertisedWindow(fd);
        
        // Sequence number is in BYTES
        seqToSend = sockets[fd].lastSent;
        tcp->seq = seqToSend;
        tcp->ack = sockets[fd].nextExpected;
        tcp->payloadLen = 0;

        // Copy data from send buffer
        for (payloadInd = 0; payloadInd < maxPayload; payloadInd++) {
            uint16_t buffIdx = (sockets[fd].lastSent) % SOCKET_BUFFER_SIZE;
            tcp->payload[payloadInd] = sockets[fd].sendBuff[buffIdx];
            sockets[fd].lastSent++;
            tcp->payloadLen++;
        }

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;
        
        dbg(TRANSPORT_CHANNEL, "Sending DATA seq=%d len=%d ack=%d\n", 
            seqToSend, tcp->payloadLen, tcp->ack);
        
        // Add to retransmit queue
        addToRetransmitQueue(fd, &packet, seqToSend, tcp->payloadLen);
        
        routeAndSend(packet, sockets[fd].dest.addr);
    }

    // ========== TRANSPORT INTERFACE COMMANDS ==========

    command error_t Transport.start() {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].flag = 0;
            retransmitCount[i] = 0;
        }
        call TransportTimer.startPeriodic(100);  // 100ms timer
        dbg(TRANSPORT_CHANNEL, "Transport started\n");
        return SUCCESS;
    }

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) { 
            if (sockets[i].flag == 0) {
                sockets[i].flag = 1;
                sockets[i].state = CLOSED;
                sockets[i].RTT = 200;  // 200ms default RTT
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 0;
                sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
                retransmitCount[i] = 0;
                dbg(TRANSPORT_CHANNEL, "Created socket %d\n", i);
                return i;
            }
        }
        dbg(TRANSPORT_CHANNEL, "ERROR: No available sockets\n");
        return 0;
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].src = addr->port;
        dbg(TRANSPORT_CHANNEL, "Socket %d bound to port %d\n", fd, addr->port);
        return SUCCESS;
    }

    command error_t Transport.listen(socket_t fd) {
        uint8_t i;
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].state = LISTEN;
        
        // Initialize pending connection queue
        pendingCount[fd] = 0;
        for (i = 0; i < MAX_PENDING; i++) {
            pendingConns[fd][i].valid = FALSE;
        }
        
        dbg(TRANSPORT_CHANNEL, "Socket %d listening\n", fd);
        return SUCCESS;
    }

    /**
     * accept() - Dequeue a pending connection and create new socket
     * Returns: socket_t of new connection, or 0 if no pending connections
     */
    command socket_t Transport.accept(socket_t listenFd) {
        socket_t newFd;
        uint8_t i;
        pack packet;
        tcp_pack* tcp;
        
        if (listenFd == 0 || listenFd >= MAX_NUM_OF_SOCKETS) return 0;
        if (sockets[listenFd].state != LISTEN) return 0;
        if (pendingCount[listenFd] == 0) return 0;  // No pending connections
        
        // Find first valid pending connection
        for (i = 0; i < MAX_PENDING; i++) {
            if (pendingConns[listenFd][i].valid) {
                // Create new socket for this connection
                newFd = call Transport.socket();
                if (newFd == 0) return 0;  // No sockets available
                
                // Configure new socket
                sockets[newFd].src = sockets[listenFd].src;  // Same port as listener
                sockets[newFd].dest.addr = pendingConns[listenFd][i].srcAddr;
                sockets[newFd].dest.port = pendingConns[listenFd][i].srcPort;
                sockets[newFd].state = SYN_RCVD;
                sockets[newFd].nextExpected = pendingConns[listenFd][i].initialSeq + 1;
                sockets[newFd].lastAck = 0;
                sockets[newFd].lastSent = 0;
                
                dbg("Project3TGen", "Debug(%d): Connection accepted from Node %d on socket %d\n",
                    TOS_NODE_ID, sockets[newFd].dest.addr, newFd);
                
                // Send SYN+ACK
                tcp = (tcp_pack*)packet.payload;
                tcp->srcPort = sockets[newFd].src;
                tcp->destPort = sockets[newFd].dest.port;
                tcp->seq = sockets[newFd].lastSent;
                tcp->ack = sockets[newFd].nextExpected;
                tcp->flags = TCP_SYN | TCP_ACK;
                tcp->window = getAdvertisedWindow(newFd);
                tcp->payloadLen = 0;
                
                packet.src = TOS_NODE_ID;
                packet.dest = sockets[newFd].dest.addr;
                packet.protocol = PROTOCOL_TCP;
                packet.TTL = MAX_TTL;
                
                dbg("Project3TGen", "Debug(%d): SYN+ACK Packet Sent to Node %d for Port %d\n",
                    TOS_NODE_ID, sockets[newFd].dest.addr, sockets[newFd].dest.port);
                
                routeAndSend(packet, sockets[newFd].dest.addr);
                
                // Mark SYN consumes 1 sequence number
                sockets[newFd].lastSent++;
                
                // Remove from pending queue
                pendingConns[listenFd][i].valid = FALSE;
                pendingCount[listenFd]--;
                
                return newFd;
            }
        }
        
        return 0;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {
        pack packet;
        tcp_pack* tcp;
        
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        
        sockets[fd].dest = *addr;
        sockets[fd].state = SYN_SENT;
        
        tcp = (tcp_pack*)packet.payload;
        tcp->srcPort = sockets[fd].src;
        tcp->destPort = sockets[fd].dest.port;
        tcp->seq = 0;  // Initial sequence number
        tcp->ack = 0;
        tcp->flags = TCP_SYN;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;
        packet.seq = 0;
        
        dbg(TRANSPORT_CHANNEL, "Sending SYN to %d:%d\n", 
            sockets[fd].dest.addr, sockets[fd].dest.port);
        routeAndSend(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    command error_t Transport.send(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t i;
        uint16_t written;
        uint16_t nextIdx;
        
        written = 0;
        
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        if (sockets[fd].state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, "Cannot send - socket not established\n");
            return FAIL;
        }

        // Write to send buffer
        for (i = 0; i < bufflen; i++) {
            nextIdx = (sockets[fd].lastWritten + 1) % SOCKET_BUFFER_SIZE;
            
            // Check if buffer is full
            if (nextIdx == sockets[fd].lastAck % SOCKET_BUFFER_SIZE) {
                dbg(TRANSPORT_CHANNEL, "Send buffer full, wrote %d bytes\n", written);
                break;
            }
            
            sockets[fd].sendBuff[sockets[fd].lastWritten % SOCKET_BUFFER_SIZE] = buff[i];
            sockets[fd].lastWritten++;
            written++;
        }

        dbg(TRANSPORT_CHANNEL, "Buffered %d bytes for sending\n", written);
        
        // Try to send data
        sendData(fd);
        
        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t* buff, uint16_t bufflen) {
        uint16_t i, bytesRead;
        uint16_t idx;
        
        bytesRead = 0;
        
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return 0;
        
        // Read from receive buffer
        while (sockets[fd].lastRead < sockets[fd].lastRcvd && bytesRead < bufflen) {
            idx = (sockets[fd].lastRead) % SOCKET_BUFFER_SIZE;
            buff[bytesRead++] = sockets[fd].rcvdBuff[idx];
            sockets[fd].lastRead++;
        }
        
        dbg(TRANSPORT_CHANNEL, "Read %d bytes from socket %d\n", bytesRead, fd);
        
        // Send ACK to update window after reading
        if (bytesRead > 0 && sockets[fd].state == ESTABLISHED) {
            sendAck(fd);
        }
        
        return bytesRead;
    }

    command error_t Transport.close(socket_t fd) {
        pack packet;
        tcp_pack* tcp;

        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        dbg(TRANSPORT_CHANNEL, "Closing socket %d (state=%d)\n", fd, sockets[fd].state);

        if (sockets[fd].state == ESTABLISHED) {
            sockets[fd].state = FIN_WAIT_1;
            
            tcp = (tcp_pack*)packet.payload;
            tcp->srcPort = sockets[fd].src;
            tcp->destPort = sockets[fd].dest.port;
            tcp->seq = sockets[fd].lastSent;
            tcp->ack = sockets[fd].nextExpected;
            tcp->flags = TCP_FIN;
            tcp->window = getAdvertisedWindow(fd);
            tcp->payloadLen = 0;
            
            packet.src = TOS_NODE_ID;
            packet.dest = sockets[fd].dest.addr;
            packet.protocol = PROTOCOL_TCP;
            packet.TTL = MAX_TTL;

            routeAndSend(packet, sockets[fd].dest.addr);
        } 
        else if (sockets[fd].state == CLOSE_WAIT) {
            sockets[fd].state = LAST_ACK;
            
            tcp = (tcp_pack*)packet.payload;
            tcp->srcPort = sockets[fd].src;
            tcp->destPort = sockets[fd].dest.port;
            tcp->seq = sockets[fd].lastSent;
            tcp->ack = sockets[fd].nextExpected;
            tcp->flags = TCP_FIN;
            tcp->window = getAdvertisedWindow(fd);
            tcp->payloadLen = 0;
            
            packet.src = TOS_NODE_ID;
            packet.dest = sockets[fd].dest.addr;
            packet.protocol = PROTOCOL_TCP;
            packet.TTL = MAX_TTL;

            routeAndSend(packet, sockets[fd].dest.addr);
        }
        
        return SUCCESS;
    }

    command error_t Transport.receive(pack* msg) {
        tcp_pack* tcp;
        uint8_t fd;
        pack reply;
        tcp_pack* replyTcp;
        uint8_t i;
        uint8_t newFd;
        uint16_t idx;
        
        tcp = (tcp_pack*)msg->payload;

        dbg(TRANSPORT_CHANNEL, "Node %d received TCP from %d: flags=%d seq=%d ack=%d port %d->%d\n", 
            TOS_NODE_ID, msg->src, tcp->flags, tcp->seq, tcp->ack, tcp->srcPort, tcp->destPort);

        fd = findSocket(msg->src, tcp->srcPort, msg->dest, tcp->destPort);
        
        // Handle SYN to listening socket - QUEUE IT, don't create socket yet!
        if (fd != 0 && sockets[fd].state == LISTEN && tcp->flags == TCP_SYN) {
            // Add to pending connections queue
            if (pendingCount[fd] < MAX_PENDING) {
                for (i = 0; i < MAX_PENDING; i++) {
                    if (!pendingConns[fd][i].valid) {
                        pendingConns[fd][i].valid = TRUE;
                        pendingConns[fd][i].srcAddr = msg->src;
                        pendingConns[fd][i].srcPort = tcp->srcPort;
                        pendingConns[fd][i].initialSeq = tcp->seq;
                        pendingCount[fd]++;
                        
                        dbg("Project3TGen", "Debug(%d): SYN queued from Node %d for Port %d (pending=%d)\n",
                            TOS_NODE_ID, msg->src, tcp->destPort, pendingCount[fd]);
                        break;
                    }
                }
            } else {
                dbg(TRANSPORT_CHANNEL, "Pending queue full, dropping SYN\n");
            }
            return SUCCESS;
        }

        if (fd == 0) {
            dbg(TRANSPORT_CHANNEL, "No socket found for packet\n");
            return FAIL;
        }

        // Update peer's advertised window
        sockets[fd].effectiveWindow = tcp->window;

        // State machine
        switch (sockets[fd].state) {
            case SYN_SENT:
                if (tcp->flags == (TCP_SYN | TCP_ACK)) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = tcp->ack;
                    sockets[fd].nextExpected = tcp->seq + 1;  // SYN consumes 1
                    
                    dbg(TRANSPORT_CHANNEL, "Connection established (client)\n");
                    signal Transport.connectDone(fd);

                    // Send final ACK
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent;
                    replyTcp->ack = sockets[fd].nextExpected;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = getAdvertisedWindow(fd);
                    replyTcp->payloadLen = 0;
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;
                    
                    routeAndSend(reply, reply.dest);
                }
                break;

            case SYN_RCVD:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = ESTABLISHED;
                    dbg(TRANSPORT_CHANNEL, "Connection established (server)\n");
                }
                break;

            case ESTABLISHED:
                // Handle DATA packets
                if (tcp->flags == TCP_DATA) {
                    if (tcp->seq == sockets[fd].nextExpected) {
                        // In-order data
                        dbg(TRANSPORT_CHANNEL, "Received in-order data seq=%d len=%d\n", 
                            tcp->seq, tcp->payloadLen);
                        
                        for (i = 0; i < tcp->payloadLen; i++) {
                            idx = (sockets[fd].lastRcvd) % SOCKET_BUFFER_SIZE;
                            sockets[fd].rcvdBuff[idx] = tcp->payload[i];
                            sockets[fd].lastRcvd++;
                        }
                        sockets[fd].nextExpected += tcp->payloadLen;
                    } else {
                        // Out-of-order - drop (could implement buffering)
                        dbg(TRANSPORT_CHANNEL, "Out-of-order data seq=%d (expected=%d), dropping\n",
                            tcp->seq, sockets[fd].nextExpected);
                    }

                    // Always send ACK
                    sendAck(fd);
                }

                // Handle ACK packets (for our sent data)
                if (tcp->flags == TCP_ACK || tcp->flags == (TCP_ACK | TCP_DATA)) {
                    if (tcp->ack > sockets[fd].lastAck) {
                        dbg(TRANSPORT_CHANNEL, "Received ACK=%d (lastAck was %d)\n", 
                            tcp->ack, sockets[fd].lastAck);
                        sockets[fd].lastAck = tcp->ack;
                        
                        // Clean retransmit queue
                        cleanRetransmitQueue(fd, tcp->ack);
                        
                        // Try to send more data
                        sendData(fd);
                    }
                }

                // Handle FIN
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = CLOSE_WAIT;
                    sockets[fd].nextExpected = tcp->seq + 1;  // FIN consumes 1
                    
                    dbg(TRANSPORT_CHANNEL, "Received FIN, entering CLOSE_WAIT\n");
                    
                    // Send ACK for FIN
                    sendAck(fd);
                    
                    // Application must call close() to send our FIN
                }
                break;

            case FIN_WAIT_1:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = FIN_WAIT_2;
                    dbg(TRANSPORT_CHANNEL, "FIN_WAIT_1 -> FIN_WAIT_2\n");
                }
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = TIME_WAIT;
                    sendAck(fd);
                    // Should wait, then close
                    sockets[fd].flag = 0;  // Simplified - just close
                    dbg(TRANSPORT_CHANNEL, "Connection closed\n");
                }
                break;

            case FIN_WAIT_2:
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = TIME_WAIT;
                    sendAck(fd);
                    sockets[fd].flag = 0;  // Simplified
                    dbg(TRANSPORT_CHANNEL, "Connection closed\n");
                }
                break;

            case LAST_ACK:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = CLOSED;
                    sockets[fd].flag = 0;
                    dbg(TRANSPORT_CHANNEL, "Connection closed\n");
                }
                break;
        }

        return SUCCESS;
    }

    // ========== TIMER EVENT ==========

    event void TransportTimer.fired() {
        uint8_t i, j;
        currentTime += 100;  // 100ms per tick

        // Check for retransmissions
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) {
            if (!sockets[i].flag || sockets[i].state != ESTABLISHED) continue;

            for (j = 0; j < retransmitCount[i]; j++) {
                if (currentTime >= retransmitQueues[i][j].timeout) {
                    dbg(TRANSPORT_CHANNEL, 
                        "TIMEOUT! Retransmitting seq=%d\n", 
                        retransmitQueues[i][j].seq);
                    
                    // Retransmit the packet
                    routeAndSend(retransmitQueues[i][j].packet, sockets[i].dest.addr);
                    
                    // Update timeout (exponential backoff)
                    retransmitQueues[i][j].timeout = currentTime + (2 * sockets[i].RTT);
                }
            }
        }
    }
}
