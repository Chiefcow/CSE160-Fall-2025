#include "../../includes/channels.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module TransportP {
    provides interface Transport;
    
    uses interface LinkState; 
    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Timer<TMilli> as TransportTimer;
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    
    // Track transfer progress for each socket
    uint16_t totalToSend[MAX_NUM_OF_SOCKETS];    // Total bytes application wants to send
    uint16_t totalWritten[MAX_NUM_OF_SOCKETS];   // Total bytes written to buffer so far
    bool transferComplete[MAX_NUM_OF_SOCKETS];

    // Calculate available space in send buffer
    uint8_t getSendBufferSpace(uint8_t fd) {
        uint16_t inFlight;
        
        // Data in flight = lastWritten - lastAck
        if (sockets[fd].lastWritten >= sockets[fd].lastAck) {
            inFlight = sockets[fd].lastWritten - sockets[fd].lastAck;
        } else {
            inFlight = 0;
        }
        
        // Leave 1 slot to distinguish full from empty
        if (inFlight >= SOCKET_BUFFER_SIZE - 1) {
            return 0;
        }
        return SOCKET_BUFFER_SIZE - 1 - inFlight;
    }

    uint8_t getAdvertisedWindow(uint8_t fd) {
        uint16_t used;
        if (sockets[fd].lastRcvd >= sockets[fd].lastRead) {
            used = sockets[fd].lastRcvd - sockets[fd].lastRead;
        } else {
            used = 0;
        }
        if (used >= SOCKET_BUFFER_SIZE) return 0;
        return SOCKET_BUFFER_SIZE - used;
    }

    uint8_t findSocket(uint16_t srcAddr, uint8_t srcPort, uint16_t destAddr, uint8_t destPort) {
        uint8_t i;
        uint8_t listenFd = 0;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == 0) continue;
            if (sockets[i].state != LISTEN &&
                sockets[i].src == destPort &&
                sockets[i].dest.addr == srcAddr &&
                sockets[i].dest.port == srcPort) {
                return i;
            }
            if (listenFd == 0 && sockets[i].state == LISTEN && sockets[i].src == destPort) {
                listenFd = i;
            }
        }
        return listenFd; 
    }

    void routeAndSend(pack packet, uint16_t dest) {
        uint16_t nextHop = call LinkState.getNextHop(dest);
        if (nextHop == AM_BROADCAST_ADDR) {
            nextHop = AM_BROADCAST_ADDR;
        }
        call Sender.send(packet, nextHop);
    }

    void handleInboundData(socket_t fd, tcp_pack* tcp) {
        pack reply;
        tcp_pack* replyTcp;
        uint8_t i;

        if (tcp->seq == sockets[fd].nextExpected) {
            dbg("transport", "Data Received Seq: %d Len: %d\n", tcp->seq, tcp->payloadLen);
            
            for(i=0; i<tcp->payloadLen; i++) {
                uint16_t idx = (sockets[fd].lastRcvd + 1) % SOCKET_BUFFER_SIZE;
                sockets[fd].rcvdBuff[idx] = tcp->payload[i];
                sockets[fd].lastRcvd++;
            }
            sockets[fd].nextExpected = tcp->seq + tcp->payloadLen; 

            dbg("transport", "Reading Data: ");
            for(i=0; i<tcp->payloadLen; i++) {
                dbg_clear("transport", "%d, ", tcp->payload[i]); 
            }
            dbg_clear("transport", "\n");
        } else {
            dbg("transport", "Out-of-order DATA Seq: %d Expected: %d\n", tcp->seq, sockets[fd].nextExpected);
        }

        // Always send ACK
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
        reply.seq = 0; 

        routeAndSend(reply, reply.dest);
    }

    command error_t Transport.start() {
        uint8_t i;
        for(i=0; i<MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].flag = 0;
            totalToSend[i] = 0;
            totalWritten[i] = 0;
            transferComplete[i] = FALSE;
        }
        call TransportTimer.startPeriodic(500); 
        return SUCCESS;
    }

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) { 
            if (sockets[i].flag == 0) {
                sockets[i].flag = 1;
                sockets[i].state = CLOSED;
                sockets[i].RTT = 100;
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 1; 
                totalToSend[i] = 0;
                totalWritten[i] = 0;
                transferComplete[i] = FALSE;
                return i;
            }
        }
        return 0; 
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].src = addr->port;
        return SUCCESS;
    }

    command error_t Transport.listen(socket_t fd) {
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        sockets[fd].state = LISTEN;
        return SUCCESS;
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
        
        sockets[fd].lastSent = 0; 
        sockets[fd].lastWritten = 0;
        
        tcp->seq = sockets[fd].lastSent + 1;
        tcp->flags = TCP_SYN;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.TTL = MAX_TTL;
        packet.seq = 0;
        packet.protocol = PROTOCOL_TCP;

        dbg("transport", "Sending SYN to %d port %d\n", sockets[fd].dest.addr, sockets[fd].dest.port);
        
        // SYN consumes sequence 1
        sockets[fd].lastSent++;
        sockets[fd].lastWritten++;
        
        routeAndSend(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    void sendData(socket_t fd) {
        pack packet;
        tcp_pack* tcp;
        uint8_t payloadInd;
        uint16_t seqToSend;

        if(sockets[fd].state != ESTABLISHED) return;

        // Send data if we have unsent data in the buffer
        while(sockets[fd].lastWritten > sockets[fd].lastSent) {
            uint8_t maxPayload = TCP_MAX_PAYLOAD_SIZE; 
            
            tcp = (tcp_pack*)packet.payload;
            tcp->srcPort = sockets[fd].src;
            tcp->destPort = sockets[fd].dest.port;
            tcp->flags = TCP_DATA;
            tcp->window = getAdvertisedWindow(fd);
            
            seqToSend = sockets[fd].lastSent + 1;
            tcp->seq = seqToSend;
            tcp->ack = sockets[fd].nextExpected;

            tcp->payloadLen = 0;
            for(payloadInd = 0; payloadInd < maxPayload && (sockets[fd].lastSent < sockets[fd].lastWritten); payloadInd++) {
                uint16_t buffInd = (sockets[fd].lastSent + 1) % SOCKET_BUFFER_SIZE;
                tcp->payload[payloadInd] = sockets[fd].sendBuff[buffInd];
                sockets[fd].lastSent++;
                tcp->payloadLen++;
            }

            packet.src = TOS_NODE_ID;
            packet.dest = sockets[fd].dest.addr;
            packet.TTL = MAX_TTL;
            packet.seq = 0; 
            packet.protocol = PROTOCOL_TCP;
            
            dbg("transport", "Sending DATA Seq: %d Len: %d\n", seqToSend, tcp->payloadLen);
            
            routeAndSend(packet, sockets[fd].dest.addr);
        }
    }

    // Returns number of bytes actually written to buffer
    command uint16_t Transport.send(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t i;
        uint16_t bytesWritten = 0;
        uint8_t availableSpace;
        
        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return 0;
        if (sockets[fd].state != ESTABLISHED) return 0;

        // Set the total if this is a new transfer
        if (totalToSend[fd] == 0) {
            totalToSend[fd] = bufflen;
            totalWritten[fd] = 0;
            transferComplete[fd] = FALSE;
            dbg("transport", "Starting transfer of %d bytes\n", bufflen);
        }

        availableSpace = getSendBufferSpace(fd);

        for(i = 0; i < bufflen && bytesWritten < availableSpace; i++) {
            sockets[fd].lastWritten++;
            sockets[fd].sendBuff[sockets[fd].lastWritten % SOCKET_BUFFER_SIZE] = buff[i];
            bytesWritten++;
        }
        
        totalWritten[fd] += bytesWritten;
        
        dbg("transport", "Wrote %d bytes to buffer (total: %d/%d)\n", 
            bytesWritten, totalWritten[fd], totalToSend[fd]);

        sendData(fd);
        return bytesWritten;
    }

    command error_t Transport.close(socket_t fd) {
        pack packet;
        tcp_pack* tcp;

        if (fd == 0 || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        sockets[fd].state = FIN_WAIT_1;
        
        tcp = (tcp_pack*)packet.payload;
        tcp->srcPort = sockets[fd].src;
        tcp->destPort = sockets[fd].dest.port;
        tcp->seq = sockets[fd].lastSent + 1;
        tcp->flags = TCP_FIN;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;
        packet.seq = 0; 

        dbg("transport", "Sending FIN to close connection\n");
        routeAndSend(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    command error_t Transport.receive(pack* msg) {
        tcp_pack* tcp = (tcp_pack*)msg->payload;
        uint8_t fd;
        pack reply;
        tcp_pack* replyTcp;

        fd = findSocket(msg->src, tcp->srcPort, msg->dest, tcp->destPort);
        
        // Handle New Connection (Listen State)
        if (fd != 0 && sockets[fd].state == LISTEN && tcp->flags == TCP_SYN) {
            uint8_t checkFd = 0;
            uint8_t k;
            for(k=1; k<MAX_NUM_OF_SOCKETS; k++) {
                if(sockets[k].flag && sockets[k].dest.addr == msg->src && 
                   sockets[k].dest.port == tcp->srcPort && sockets[k].src == tcp->destPort) {
                    checkFd = k;
                    break;
                }
            }

            if(checkFd == 0) {
                uint8_t newFd = call Transport.socket();
                if (newFd != 0) {
                    sockets[newFd].state = SYN_RCVD;
                    sockets[newFd].dest.addr = msg->src;
                    sockets[newFd].dest.port = tcp->srcPort;
                    sockets[newFd].src = tcp->destPort;
                    sockets[newFd].nextExpected = tcp->seq + 1;
                    
                    signal Transport.accept(newFd);
                    
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[newFd].src;
                    replyTcp->destPort = sockets[newFd].dest.port;
                    replyTcp->seq = sockets[newFd].lastSent + 1; 
                    replyTcp->ack = sockets[newFd].nextExpected;
                    replyTcp->flags = TCP_SYN + TCP_ACK;
                    replyTcp->window = getAdvertisedWindow(newFd);
                    replyTcp->payloadLen = 0;

                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[newFd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;
                    reply.seq = 0; 

                    dbg("transport", "Received SYN, sending SYN+ACK\n");
                    routeAndSend(reply, reply.dest);

                    sockets[newFd].lastSent++;
                    sockets[newFd].lastWritten++;
                }
            } else {
                dbg("transport", "Duplicate SYN. Resending SYN+ACK.\n");
                
                replyTcp = (tcp_pack*)reply.payload;
                replyTcp->srcPort = sockets[checkFd].src;
                replyTcp->destPort = sockets[checkFd].dest.port;
                replyTcp->seq = sockets[checkFd].lastSent; 
                replyTcp->ack = sockets[checkFd].nextExpected;
                replyTcp->flags = TCP_SYN + TCP_ACK;
                replyTcp->window = getAdvertisedWindow(checkFd);
                replyTcp->payloadLen = 0;

                reply.src = TOS_NODE_ID;
                reply.dest = sockets[checkFd].dest.addr;
                reply.protocol = PROTOCOL_TCP;
                reply.TTL = MAX_TTL;
                reply.seq = 0;
                
                routeAndSend(reply, reply.dest);
            }
            return SUCCESS;
        }

        if (fd == 0) return FAIL; 

        switch(sockets[fd].state) {
            case SYN_SENT:
                if (tcp->flags == (TCP_SYN + TCP_ACK)) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = (tcp->ack > 0) ? tcp->ack - 1 : 0;
                    sockets[fd].nextExpected = tcp->seq + 1;
                    
                    signal Transport.connectDone(fd);

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
                    reply.seq = 0; 
                    
                    dbg("transport", "Conn Established. Sending ACK.\n");
                    routeAndSend(reply, reply.dest);
                }
                break;

            case SYN_RCVD:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = (tcp->ack > 0) ? tcp->ack - 1 : 0;
                    dbg("transport", "Server Established.\n");
                } else if (tcp->flags == TCP_DATA) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = (sockets[fd].nextExpected > 0) ? sockets[fd].nextExpected - 1 : 0;
                    dbg("transport", "Server Established via DATA.\n");
                    handleInboundData(fd, tcp);
                }
                break;

            case ESTABLISHED:
                if (tcp->flags == TCP_DATA) {
                    handleInboundData(fd, tcp);
                }

                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = CLOSE_WAIT;
                    
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent;
                    replyTcp->ack = tcp->seq + 1;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = getAdvertisedWindow(fd);
                    replyTcp->payloadLen = 0;
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;
                    reply.seq = 0;
                    
                    dbg("transport", "Received FIN, sending ACK. Connection closing.\n");
                    routeAndSend(reply, reply.dest);
                    
                    call Transport.close(fd);
                }
                
                if (tcp->flags == TCP_ACK) {
                    if(tcp->ack > sockets[fd].lastAck) {
                        sockets[fd].lastAck = (tcp->ack > 0) ? tcp->ack - 1 : 0;
                        
                        dbg("transport", "ACK received: %d (lastAck now %d, lastWritten %d)\n", 
                            tcp->ack, sockets[fd].lastAck, sockets[fd].lastWritten);
                        
                        // Check if ALL data has been acknowledged
                        if(totalToSend[fd] > 0 && 
                           totalWritten[fd] >= totalToSend[fd] &&
                           sockets[fd].lastAck >= sockets[fd].lastWritten && 
                           !transferComplete[fd]) {
                            transferComplete[fd] = TRUE;
                            dbg("transport", "Transfer Complete! All %d bytes acknowledged.\n", totalToSend[fd]);
                            call Transport.close(fd);
                        } else {
                            // Try to send more data
                            sendData(fd);
                        }
                    }
                }
                break;

            case FIN_WAIT_1:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = FIN_WAIT_2;
                    dbg("transport", "FIN_WAIT_1 -> FIN_WAIT_2\n");
                }
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = TIME_WAIT;
                    
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent;
                    replyTcp->ack = tcp->seq + 1;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = 0;
                    replyTcp->payloadLen = 0;
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;
                    reply.seq = 0;
                    
                    routeAndSend(reply, reply.dest);
                    dbg("transport", "Received FIN in FIN_WAIT_1, sent ACK. TIME_WAIT\n");
                }
                break;
                
            case FIN_WAIT_2:
                if (tcp->flags == TCP_FIN) {
                    sockets[fd].state = TIME_WAIT;
                    
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent;
                    replyTcp->ack = tcp->seq + 1;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = 0;
                    replyTcp->payloadLen = 0;
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;
                    reply.seq = 0;
                    
                    routeAndSend(reply, reply.dest);
                    dbg("transport", "Received FIN in FIN_WAIT_2, sent ACK. Connection CLOSED.\n");
                    
                    sockets[fd].flag = 0;
                    sockets[fd].state = CLOSED;
                }
                break;
                
            case CLOSE_WAIT:
                break;
                
            case LAST_ACK:
                if (tcp->flags == TCP_ACK) {
                    dbg("transport", "Received final ACK. Connection CLOSED.\n");
                    sockets[fd].flag = 0;
                    sockets[fd].state = CLOSED;
                }
                break;
                
            case TIME_WAIT:
                if (tcp->flags == TCP_FIN) {
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent;
                    replyTcp->ack = tcp->seq + 1;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = 0;
                    replyTcp->payloadLen = 0;
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;
                    reply.seq = 0;
                    
                    routeAndSend(reply, reply.dest);
                }
                break;

            default:
                break;
        }
        return SUCCESS;
    }

    event void TransportTimer.fired() {
        uint8_t i;
        for(i=1; i<MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].flag) {
                // Retransmit unacked data
                if (sockets[i].state == ESTABLISHED && 
                    sockets[i].lastSent > sockets[i].lastAck &&
                    !transferComplete[i]) {
                    dbg("transport", "Timeout! Retransmitting from %d\n", sockets[i].lastAck);
                    sockets[i].lastSent = sockets[i].lastAck;
                    sendData(i);
                }
                
                // Retransmit SYN
                if (sockets[i].state == SYN_SENT) {
                    pack packet;
                    tcp_pack* tcp = (tcp_pack*)packet.payload;
                    
                    dbg("transport", "Handshake Timeout! Retrying SYN...\n");
                    
                    tcp->srcPort = sockets[i].src;
                    tcp->destPort = sockets[i].dest.port;
                    tcp->seq = 1;
                    tcp->flags = TCP_SYN;
                    tcp->window = getAdvertisedWindow(i);
                    tcp->payloadLen = 0;

                    packet.src = TOS_NODE_ID;
                    packet.dest = sockets[i].dest.addr;
                    packet.TTL = MAX_TTL;
                    packet.seq = 0;
                    packet.protocol = PROTOCOL_TCP;
                    
                    routeAndSend(packet, sockets[i].dest.addr);
                }
                
                // Clean up TIME_WAIT sockets
                if (sockets[i].state == TIME_WAIT) {
                    dbg("transport", "TIME_WAIT expired, closing socket.\n");
                    sockets[i].flag = 0;
                    sockets[i].state = CLOSED;
                }
            }
        }
    }
}
