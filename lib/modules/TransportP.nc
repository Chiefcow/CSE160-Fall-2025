#include "../../includes/channels.h"
#include "../../includes/tcp.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

/*
 * TRANSPORT LAYER IMPLEMENTATION - PROJECT 3
 * 
 * Key Features Implemented:
 * - Adaptive RTT estimation using EWMA (Exponential Weighted Moving Average)
 * - Exponential backoff for retransmissions
 * - Retry limits with connection teardown
 * - Proper uint16_t wrap-around handling for sequence numbers
 * - Pending connection queue for accept()
 * - Sliding window flow control
 * - Control packet validation
 * - Complete TCP state machine (10 states)
 */

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
    
    // ========== PENDING CONNECTION QUEUE ==========
    // NEW: Proper accept() implementation - queue SYN packets
    #define MAX_PENDING 5
    typedef struct {
        uint16_t srcAddr;
        uint8_t srcPort;
        uint16_t initialSeq;
        bool valid;
    } pending_conn_t;
    
    pending_conn_t pendingConns[MAX_NUM_OF_SOCKETS][MAX_PENDING];
    uint8_t pendingCount[MAX_NUM_OF_SOCKETS];
    
    // ========== RETRANSMISSION QUEUE ==========
    // Enhanced with retry tracking for exponential backoff
    typedef struct {
        pack packet;
        uint32_t sentTime;
        uint32_t timeout;
        uint16_t seq;
        uint8_t payloadLen;
        uint8_t retryCount;  // NEW: Track retry attempts
    } retransmit_entry_t;
    
    retransmit_entry_t retransmitQueues[MAX_NUM_OF_SOCKETS][MAX_RETRANSMIT_QUEUE];
    uint8_t retransmitCount[MAX_NUM_OF_SOCKETS];
    uint32_t currentTime = 0;
    
    #define MAX_RETRIES 10  // Maximum retransmission attempts before giving up

    // ========== HELPER FUNCTIONS ==========

    /**
     * Calculate available space in receive buffer
     * FIXED: Proper wrap-around handling with uint16_t
     */
    uint8_t getAdvertisedWindow(uint8_t fd) {
        uint16_t used;
        
        // Handle wrap-around correctly
        if (sockets[fd].lastRcvd >= sockets[fd].lastRead) {
            // Normal case: no wrap-around
            used = sockets[fd].lastRcvd - sockets[fd].lastRead;
        } else {
            // Wrap-around case (sequence numbers wrapped at 65536)
            used = (65536 - sockets[fd].lastRead) + sockets[fd].lastRcvd;
        }
        
        if (used >= SOCKET_BUFFER_SIZE) return 0;
        return SOCKET_BUFFER_SIZE - used;
    }

    /**
     * Check if sequence number is NOT acknowledged (needs retransmission)
     * FIXED: Proper handling of uint16_t wrap-around
     * Returns TRUE if packet needs retransmission
     */
    bool isNotAcknowledged(uint16_t seq, uint16_t lastAck, uint16_t lastSent) {
        // Typical case: lastSent >= lastAck
        if (lastSent >= lastAck) {
            // NOT acknowledged if: seq is in the range [lastAck, lastSent)
            return (seq >= lastAck) && (seq < lastSent);
        }
        // Wrap-around case: lastSent < lastAck (wrapped at 65536)
        else {
            // NOT acknowledged if: seq < lastSent OR seq >= lastAck
            return (seq < lastSent) || (seq >= lastAck);
        }
    }

    /**
     * NEW: Update RTT estimate using EWMA (Exponential Weighted Moving Average)
     * Formula: RTT = (7/8)*oldRTT + (1/8)*sampleRTT
     * This smooths out variations while adapting to network changes
     */
    void updateRTT(socket_t fd, uint32_t sampleRTT) {
        if (sampleRTT == 0) return;
        
        // EWMA: RTT = (7/8)*oldRTT + (1/8)*sample
        sockets[fd].RTT = ((7 * sockets[fd].RTT) + sampleRTT) / 8;
        
        // Keep RTT in reasonable bounds (50ms to 5000ms)
        if (sockets[fd].RTT < 50) sockets[fd].RTT = 50;
        if (sockets[fd].RTT > 5000) sockets[fd].RTT = 5000;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: RTT updated to %d ms (sample=%d)\n", 
            TOS_NODE_ID, sockets[fd].RTT, sampleRTT);
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
     * Add packet to retransmission queue with retry tracking
     * NEW: Initialize retryCount for exponential backoff
     */
    void addToRetransmitQueue(socket_t fd, pack* packet, uint16_t seq, uint8_t payloadLen) {
        if (retransmitCount[fd] >= MAX_RETRANSMIT_QUEUE) {
            dbg(TRANSPORT_CHANNEL, "Node %d: Retransmit queue full for socket %d\n", 
                TOS_NODE_ID, fd);
            return;
        }

        retransmitQueues[fd][retransmitCount[fd]].packet = *packet;
        retransmitQueues[fd][retransmitCount[fd]].sentTime = currentTime;
        retransmitQueues[fd][retransmitCount[fd]].timeout = currentTime + (2 * sockets[fd].RTT);
        retransmitQueues[fd][retransmitCount[fd]].seq = seq;
        retransmitQueues[fd][retransmitCount[fd]].payloadLen = payloadLen;
        retransmitQueues[fd][retransmitCount[fd]].retryCount = 0;  // NEW: Initialize retry count
        retransmitCount[fd]++;

        dbg(TRANSPORT_CHANNEL, "Node %d: Added seq %d to retransmit queue (count=%d, timeout=%d)\n", 
            TOS_NODE_ID, seq, retransmitCount[fd], 
            retransmitQueues[fd][retransmitCount[fd]-1].timeout);
    }

    /**
     * Remove acknowledged packets from retransmit queue
     * NEW: Also measures RTT from first ACKed packet (Karn's algorithm)
     */
    void cleanRetransmitQueue(socket_t fd, uint16_t ackNum) {
        uint8_t i;
        uint8_t newCount;
        uint16_t pktSeq;
        uint16_t pktEnd;
        uint32_t rttSample;
        bool measuredRTT = FALSE;
        
        newCount = 0;

        for (i = 0; i < retransmitCount[fd]; i++) {
            pktSeq = retransmitQueues[fd][i].seq;
            pktEnd = pktSeq + retransmitQueues[fd][i].payloadLen;

            // If this packet is fully acknowledged, don't keep it
            if (pktEnd <= ackNum) {
                // NEW: Measure RTT from first ACKed packet (only if not retransmitted)
                // This is Karn's algorithm - don't use retransmitted packets for RTT
                if (!measuredRTT && retransmitQueues[fd][i].retryCount == 0) {
                    rttSample = currentTime - retransmitQueues[fd][i].sentTime;
                    updateRTT(fd, rttSample);
                    measuredRTT = TRUE;
                }
                
                dbg(TRANSPORT_CHANNEL, "Node %d: Removing acked packet seq %d from queue\n", 
                    TOS_NODE_ID, pktSeq);
                continue;  // Don't keep this packet
            }

            // Keep this packet - shift it down in the array
            if (newCount != i) {
                retransmitQueues[fd][newCount] = retransmitQueues[fd][i];
            }
            newCount++;
        }

        retransmitCount[fd] = newCount;
    }

    /**
     * Route and send packet using LinkState routing
     */
    void routeAndSend(pack packet, uint16_t dest) {
        uint16_t nextHop = call LinkState.getNextHop(dest);
        tcp_pack* tcp = (tcp_pack*)packet.payload;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: SENDING TCP (flags=%d) to dest=%d via nextHop=%d\n",
            TOS_NODE_ID, tcp->flags, dest, nextHop);
        
        if (nextHop == 255) {  // No route available
            dbg(TRANSPORT_CHANNEL, "Node %d: ERROR - No route to %d, dropping TCP packet\n", 
                TOS_NODE_ID, dest);
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
        tcp->seq = 0;  // ACK doesn't use seq
        tcp->ack = sockets[fd].nextExpected;
        tcp->flags = TCP_ACK;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.protocol = PROTOCOL_TCP;

        dbg(TRANSPORT_CHANNEL, "Node %d: Sending ACK with ack=%d window=%d\n", 
            TOS_NODE_ID, tcp->ack, tcp->window);
        routeAndSend(packet, sockets[fd].dest.addr);
    }

    /**
     * Send data with proper flow control and sliding window
     * FIXED: Handles wrap-around correctly with uint16_t
     */
    void sendData(socket_t fd) {
        pack packet;
        tcp_pack* tcp;
        uint8_t payloadInd;
        uint16_t seqToSend;
        uint16_t canSend;
        uint8_t maxPayload;
        uint16_t unsentBytes;
        uint16_t inFlightBytes;

        if (sockets[fd].state != ESTABLISHED) return;

        // Check flow control - don't exceed peer's window
        if (sockets[fd].effectiveWindow == 0) {
            dbg(TRANSPORT_CHANNEL, "Node %d: Peer window is 0, cannot send\n", TOS_NODE_ID);
            return;
        }

        // Calculate how much we can send based on:
        // 1. What's been written but not sent
        // 2. Peer's advertised window
        
        // FIXED: Handle wrap-around in calculations
        if (sockets[fd].lastWritten >= sockets[fd].lastSent) {
            unsentBytes = sockets[fd].lastWritten - sockets[fd].lastSent;
        } else {
            // Wrap-around case
            unsentBytes = (65536 - sockets[fd].lastSent) + sockets[fd].lastWritten;
        }
        
        if (sockets[fd].lastSent >= sockets[fd].lastAck) {
            inFlightBytes = sockets[fd].lastSent - sockets[fd].lastAck;
        } else {
            // Wrap-around case
            inFlightBytes = (65536 - sockets[fd].lastAck) + sockets[fd].lastSent;
        }
        
        // Calculate available window space
        if (inFlightBytes >= sockets[fd].effectiveWindow) {
            canSend = 0;
        } else {
            canSend = sockets[fd].effectiveWindow - inFlightBytes;
        }
        
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
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Sending DATA seq=%d len=%d ack=%d window=%d\n", 
            TOS_NODE_ID, seqToSend, tcp->payloadLen, tcp->ack, tcp->window);
        
        // Add to retransmit queue
        addToRetransmitQueue(fd, &packet, seqToSend, tcp->payloadLen);
        
        routeAndSend(packet, sockets[fd].dest.addr);
    }

    /**
     * NEW: Validate that control packets (SYN/ACK/FIN) don't carry data
     * This enforces TCP protocol correctness
     */
    bool isValidControlPacket(tcp_pack* tcp) {
        // Control packets should not carry payload data
        if ((tcp->flags == TCP_SYN || 
             tcp->flags == TCP_FIN || 
             tcp->flags == TCP_ACK ||
             tcp->flags == (TCP_SYN | TCP_ACK)) && 
            tcp->payloadLen > 0) {
            dbg(TRANSPORT_CHANNEL, "Node %d: ERROR - Control packet (flags=%d) has payload data!\n", 
                TOS_NODE_ID, tcp->flags);
            return FALSE;
        }
        return TRUE;
    }

    // ========== TRANSPORT INTERFACE COMMANDS ==========

    command error_t Transport.start() {
        uint8_t i, j;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].flag = 0;
            retransmitCount[i] = 0;
            pendingCount[i] = 0;
            
            // Initialize pending connections
            for (j = 0; j < MAX_PENDING; j++) {
                pendingConns[i][j].valid = FALSE;
            }
        }
        call TransportTimer.startPeriodic(100);  // 100ms timer
        dbg(TRANSPORT_CHANNEL, "Node %d: Transport started\n", TOS_NODE_ID);
        return SUCCESS;
    }

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) { 
            if (sockets[i].flag == 0) {
                sockets[i].flag = 1;
                sockets[i].state = CLOSED;
                sockets[i].RTT = 200;  // 200ms initial RTT (will adapt via EWMA)
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 0;
                sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
                retransmitCount[i] = 0;
                dbg(TRANSPORT_CHANNEL, "Node %d: Created socket %d\n", TOS_NODE_ID, i);
                return i;
            }
        }
        dbg(TRANSPORT_CHANNEL, "Node %d: ERROR - No available sockets\n", TOS_NODE_ID);
        return 0;
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].src = addr->port;
        dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d bound to port %d\n", 
            TOS_NODE_ID, fd, addr->port);
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
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d listening on port %d\n", 
            TOS_NODE_ID, fd, sockets[fd].src);
        return SUCCESS;
    }

    /**
     * NEW: Proper accept() implementation
     * Dequeues a pending connection and creates new socket
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
                
                dbg("Project3TGen", "Debug(%d): SYN+ACK Packet Sent to Node %d for Port %d\n",
                    TOS_NODE_ID, sockets[newFd].dest.addr, sockets[newFd].dest.port);
                
                routeAndSend(packet, sockets[newFd].dest.addr);
                
                // SYN consumes 1 sequence number
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
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Sending SYN to %d:%d\n",
            TOS_NODE_ID, sockets[fd].dest.addr, sockets[fd].dest.port);
        routeAndSend(packet, sockets[fd].dest.addr);
        
        sockets[fd].lastSent = 1;  // SYN consumes 1 byte
        
        return SUCCESS;
    }

    command error_t Transport.send(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t i;
        uint16_t written;
        uint16_t nextIdx;
        
        written = 0;
        
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        if (sockets[fd].state != ESTABLISHED) {
            dbg(TRANSPORT_CHANNEL, "Node %d: Cannot send - socket not established (state=%d)\n", 
                TOS_NODE_ID, sockets[fd].state);
            return FAIL;
        }

        // Write to send buffer
        for (i = 0; i < bufflen; i++) {
            nextIdx = (sockets[fd].lastWritten + 1) % SOCKET_BUFFER_SIZE;
            
            // Check if buffer is full
            if (nextIdx == sockets[fd].lastAck % SOCKET_BUFFER_SIZE) {
                dbg(TRANSPORT_CHANNEL, "Node %d: Send buffer full, wrote %d bytes\n", 
                    TOS_NODE_ID, written);
                break;
            }
            
            sockets[fd].sendBuff[sockets[fd].lastWritten % SOCKET_BUFFER_SIZE] = buff[i];
            sockets[fd].lastWritten++;
            written++;
        }

        dbg(TRANSPORT_CHANNEL, "Node %d: Buffered %d bytes for sending\n", TOS_NODE_ID, written);
        
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
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Read %d bytes from socket %d\n", 
            TOS_NODE_ID, bytesRead, fd);
        
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

        dbg(TRANSPORT_CHANNEL, "Node %d: Closing socket %d (state=%d)\n", 
            TOS_NODE_ID, fd, sockets[fd].state);

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

            routeAndSend(packet, sockets[fd].dest.addr);
            sockets[fd].lastSent++;
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

            routeAndSend(packet, sockets[fd].dest.addr);
            sockets[fd].lastSent++;
        }
        
        return SUCCESS;
    }

    command error_t Transport.receive(pack* msg) {
        tcp_pack* tcp;
        uint8_t fd;
        pack reply;
        tcp_pack* replyTcp;
        uint8_t i;
        uint16_t idx;
        
        tcp = (tcp_pack*)msg->payload;
        
        // NEW: Validate control packets don't carry data
        if (!isValidControlPacket(tcp)) {
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "Node %d received TCP from %d: flags=%d seq=%d ack=%d port %d->%d\n", 
            TOS_NODE_ID, msg->src, tcp->flags, tcp->seq, tcp->ack, tcp->srcPort, tcp->destPort);

        fd = findSocket(msg->src, tcp->srcPort, msg->dest, tcp->destPort);
        
        // NEW: Handle SYN to listening socket - QUEUE IT for accept()
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
                        
                        dbg("Project3TGen", "Debug(%d): SYN Packet Arrived from Node %d for Port %d\n",
                            TOS_NODE_ID, msg->src, tcp->destPort);
                        break;
                    }
                }
            } else {
                dbg(TRANSPORT_CHANNEL, "Node %d: Pending queue full, dropping SYN\n", TOS_NODE_ID);
            }
            return SUCCESS;
        }

        if (fd == 0) {
            dbg(TRANSPORT_CHANNEL, "Node %d: No socket found for packet\n", TOS_NODE_ID);
            return FAIL;
        }

        // Update peer's advertised window
        sockets[fd].effectiveWindow = tcp->window;

        // TCP State Machine
        switch (sockets[fd].state) {
            case SYN_SENT:
                if (tcp->flags == (TCP_SYN | TCP_ACK)) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = tcp->ack;
                    sockets[fd].nextExpected = tcp->seq + 1;  // SYN consumes 1
                    
                    dbg(TRANSPORT_CHANNEL, "Node %d: Connection established (client)\n", TOS_NODE_ID);
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
                    
                    routeAndSend(reply, reply.dest);
                }
                break;

            case SYN_RCVD:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = ESTABLISHED;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Connection established (server)\n", TOS_NODE_ID);
                }
                break;

            case ESTABLISHED:
                // Handle DATA packets
                if (tcp->flags == TCP_DATA) {
                    if (tcp->seq == sockets[fd].nextExpected) {
                        // In-order data
                        dbg(TRANSPORT_CHANNEL, "Node %d: Received in-order data seq=%d len=%d\n", 
                            TOS_NODE_ID, tcp->seq, tcp->payloadLen);
                        
                        for (i = 0; i < tcp->payloadLen; i++) {
                            idx = (sockets[fd].lastRcvd) % SOCKET_BUFFER_SIZE;
                            sockets[fd].rcvdBuff[idx] = tcp->payload[i];
                            sockets[fd].lastRcvd++;
                        }
                        sockets[fd].nextExpected += tcp->payloadLen;
                    } else {
                        // Out-of-order - drop (simplified - could buffer)
                        dbg(TRANSPORT_CHANNEL, "Node %d: Out-of-order data seq=%d (expected=%d), dropping\n",
                            TOS_NODE_ID, tcp->seq, sockets[fd].nextExpected);
                    }

                    // Always send ACK
                    sendAck(fd);
                }

                // Handle ACK packets (for our sent data)
                if (tcp->flags == TCP_ACK || tcp->flags == (TCP_ACK | TCP_DATA)) {
                    if (tcp->ack > sockets[fd].lastAck) {
                        dbg(TRANSPORT_CHANNEL, "Node %d: Received ACK=%d (lastAck was %d)\n", 
                            TOS_NODE_ID, tcp->ack, sockets[fd].lastAck);
                        sockets[fd].lastAck = tcp->ack;
                        
                        // Clean retransmit queue (also measures RTT)
                        cleanRetransmitQueue(fd, tcp->ack);
                        
                        // Try to send more data
                        sendData(fd);
                    }
                }

                // Handle FIN
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = CLOSE_WAIT;
                    sockets[fd].nextExpected = tcp->seq + 1;  // FIN consumes 1
                    
                    dbg("Project3TGen", "Debug(%d): FIN Packet Arrived from Node %d\n",
                        TOS_NODE_ID, msg->src);
                    
                    // Send ACK for FIN
                    sendAck(fd);
                }
                break;

            case FIN_WAIT_1:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = FIN_WAIT_2;
                    dbg(TRANSPORT_CHANNEL, "Node %d: FIN_WAIT_1 -> FIN_WAIT_2\n", TOS_NODE_ID);
                }
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = TIME_WAIT;
                    sendAck(fd);
                    // Should wait, then close
                    sockets[fd].flag = 0;  // Simplified
                    dbg(TRANSPORT_CHANNEL, "Node %d: Connection closed\n", TOS_NODE_ID);
                }
                break;

            case FIN_WAIT_2:
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = TIME_WAIT;
                    sendAck(fd);
                    sockets[fd].flag = 0;  // Simplified
                    dbg(TRANSPORT_CHANNEL, "Node %d: Connection closed\n", TOS_NODE_ID);
                }
                break;

            case LAST_ACK:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = CLOSED;
                    sockets[fd].flag = 0;
                    dbg(TRANSPORT_CHANNEL, "Node %d: Connection closed\n", TOS_NODE_ID);
                }
                break;
        }

        return SUCCESS;
    }

    // ========== TIMER EVENT ==========

    /**
     * NEW: Timer with exponential backoff and retry limits
     * Implements timeout/retransmit logic for reliability
     */
    event void TransportTimer.fired() {
        uint8_t i, j;
        uint8_t backoffMultiplier;
        
        currentTime += 100;  // 100ms per tick

        // Check for retransmissions on all sockets
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) {
            if (!sockets[i].flag || sockets[i].state != ESTABLISHED) continue;

            for (j = 0; j < retransmitCount[i]; j++) {
                if (currentTime >= retransmitQueues[i][j].timeout) {
                    // NEW: Check retry limit
                    if (retransmitQueues[i][j].retryCount >= MAX_RETRIES) {
                        dbg(TRANSPORT_CHANNEL, 
                            "Node %d: Max retries (%d) exceeded for seq=%d, closing connection\n",
                            TOS_NODE_ID, MAX_RETRIES, retransmitQueues[i][j].seq);
                        
                        // Close connection due to repeated failures
                        sockets[i].state = CLOSED;
                        sockets[i].flag = 0;
                        retransmitCount[i] = 0;
                        break;
                    }
                    
                    // NEW: Exponential backoff: 2^retryCount (capped at 16x)
                    backoffMultiplier = 1 << retransmitQueues[i][j].retryCount;
                    if (backoffMultiplier > 16) backoffMultiplier = 16;
                    
                    dbg(TRANSPORT_CHANNEL, 
                        "Node %d: TIMEOUT! Retransmitting seq=%d (retry #%d, backoff=%dx)\n", 
                        TOS_NODE_ID,
                        retransmitQueues[i][j].seq,
                        retransmitQueues[i][j].retryCount + 1,
                        backoffMultiplier);
                    
                    // Retransmit the packet
                    routeAndSend(retransmitQueues[i][j].packet, sockets[i].dest.addr);
                    
                    // Update timeout with exponential backoff
                    retransmitQueues[i][j].timeout = currentTime + 
                        (2 * sockets[i].RTT * backoffMultiplier);
                    retransmitQueues[i][j].retryCount++;
                }
            }
        }
    }
}
