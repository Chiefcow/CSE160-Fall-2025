//File created for project 3 
//Transport Layer
//Check debugger notes and code
#include "../../includes/channels.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module TransportP {
    provides interface Transport;
    
    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Timer<TMilli> as TransportTimer; // For retransmissions
    uses interface List<pack> as PacketQueue; // Optional: For queuing if needed
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    //Calculate window availability
    uint8_t getAdvertisedWindow(uint8_t fd) {
        // Simple circular buffer math: How much space is left in Recv Buffer?
        // (Size - (LastRcvd - LastRead))
        uint16_t used = sockets[fd].lastRcvd - sockets[fd].lastRead;
        if (used >= SOCKET_BUFFER_SIZE) return 0;
        return SOCKET_BUFFER_SIZE - used;
    }

    // Find a socket by address/port
    uint8_t findSocket(uint16_t srcAddr, uint8_t srcPort, uint16_t destAddr, uint8_t destPort) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == 0) continue; // Skip unused causes errors without a check :p
            
            // Check for explicit match
            if (sockets[i].src == destPort && sockets[i].dest.addr == srcAddr && sockets[i].dest.port == srcPort) {
                return i;
            }
            // Check for Listen socket (Server waiting for connection)
            if (sockets[i].state == LISTEN && sockets[i].src == destPort) {
                return i;
            }
        }
        return 0; // 0 is invalid/null fd in this context usually, or handle error
    }

    command error_t Transport.start() {
        uint8_t i;
        for(i=0; i<MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].flag = 0; // Mark all as empty
        }
        // Start a periodic timer to check for retransmissions/timeouts
        call TransportTimer.startPeriodic(100); 
        return SUCCESS;
    }

    // --- Socket Management ---

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) { // Start at 1, keep 0 as error/null
            if (sockets[i].flag == 0) {
                sockets[i].flag = 1;
                sockets[i].state = CLOSED;
                sockets[i].RTT = 20; // Default RTT estimate
                
                // Initialize pointers
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 1; // Start Seq at 1
                return i;
            }
        }
        return 0; // No sockets available
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
        
        // Create SYN packet
        tcp = (tcp_pack*)packet.payload;
        tcp->srcPort = sockets[fd].src;
        tcp->destPort = sockets[fd].dest.port;
        tcp->seq = sockets[fd].lastSent + 1;
        tcp->flags = TCP_SYN;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.ttl = MAX_TTL;
        packet.seq = 0; // Transport seq is inside TCP header
        packet.protocol = PROTOCOL_TCP;

        dbg("transport", "Sending SYN to %d port %d\n", sockets[fd].dest.addr, sockets[fd].dest.port);
        call Sender.send(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    // --- Sending Data Helper ---
    void sendData(socket_t fd) {
        pack packet;
        tcp_pack* tcp;
        uint16_t bytesToSend;
        uint8_t payloadInd;
        uint16_t seqToSend;

        if(sockets[fd].state != ESTABLISHED) return;

        // Check window: min(AdvertisedWindow, CongestionWindow)
        // Here we just use flow control (Advertised Window)
        // Check if we have data to send (LastWritten > LastSent)
        if(sockets[fd].lastWritten > sockets[fd].lastSent) {
            
            // Limit by packet size (max 10 bytes payload for safety in sim)
            uint8_t maxPayload = 10; 
            
            tcp = (tcp_pack*)packet.payload;
            tcp->srcPort = sockets[fd].src;
            tcp->destPort = sockets[fd].dest.port;
            tcp->flags = TCP_DATA;
            tcp->window = getAdvertisedWindow(fd);
            
            seqToSend = sockets[fd].lastSent + 1;
            tcp->seq = seqToSend;
            tcp->ack = sockets[fd].nextExpected;

            // Copy data from circular buffer
            tcp->payloadLen = 0;
            for(payloadInd = 0; payloadInd < maxPayload && (sockets[fd].lastSent < sockets[fd].lastWritten); payloadInd++) {
                uint16_t buffInd = (sockets[fd].lastSent + 1) % SOCKET_BUFFER_SIZE;
                tcp->payload[payloadInd] = sockets[fd].sendBuff[buffInd];
                sockets[fd].lastSent++;
                tcp->payloadLen++;
            }

            packet.src = TOS_NODE_ID;
            packet.dest = sockets[fd].dest.addr;
            packet.ttl = MAX_TTL;
            packet.protocol = PROTOCOL_TCP;
            
            dbg("transport", "Sending DATA Seq: %d Len: %d\n", seqToSend, tcp->payloadLen);
            call Sender.send(packet, sockets[fd].dest.addr);
        }
    }

    command error_t Transport.send(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t i;
        if (sockets[fd].state != ESTABLISHED) return FAIL;

        // Write to buffer
        for(i=0; i<bufflen; i++) {
             // Calculate next index
             uint16_t nextIdx = (sockets[fd].lastWritten + 1) % SOCKET_BUFFER_SIZE;
             
             // Check if buffer full (Prevent Overwrite)
             if(nextIdx == sockets[fd].lastAck % SOCKET_BUFFER_SIZE) {
                 // Buffer full
                 break; 
             }
             
             sockets[fd].lastWritten++;
             sockets[fd].sendBuff[sockets[fd].lastWritten % SOCKET_BUFFER_SIZE] = buff[i];
        }

        // Trigger send logic
        sendData(fd);
        return SUCCESS;
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

        call Sender.send(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    // --- Receive Logic ---

    // Should receive pointer to payload pack
    command error_t Transport.receive(pack* msg) {
        tcp_pack* tcp = (tcp_pack*)msg->payload;
        uint8_t fd;
        pack reply;
        tcp_pack* replyTcp;
        uint8_t i;

        // Find associated socket
        fd = findSocket(msg->src, tcp->srcPort, msg->dest, tcp->destPort);
        
        // Handle Server Accept (Listen state)
        if (fd != 0 && sockets[fd].state == LISTEN && tcp->flags == TCP_SYN) {
            // Fork new socket
            uint8_t newFd = call Transport.socket();
            if (newFd != 0) {
                sockets[newFd].state = SYN_RCVD;
                sockets[newFd].dest.addr = msg->src;
                sockets[newFd].dest.port = tcp->srcPort;
                sockets[newFd].src = tcp->destPort;
                sockets[newFd].nextExpected = tcp->seq + 1;
                
                // Signal Connection Accepted to App
                signal Transport.accept(newFd);

                // Send SYN+ACK
                replyTcp = (tcp_pack*)reply.payload;
                replyTcp->srcPort = sockets[newFd].src;
                replyTcp->destPort = sockets[newFd].dest.port;
                replyTcp->seq = sockets[newFd].lastSent + 1; // ISN
                replyTcp->ack = sockets[newFd].nextExpected;
                replyTcp->flags = TCP_SYN + TCP_ACK;
                replyTcp->window = getAdvertisedWindow(newFd);
                replyTcp->payloadLen = 0;

                reply.src = TOS_NODE_ID;
                reply.dest = sockets[newFd].dest.addr;
                reply.protocol = PROTOCOL_TCP;
                
                dbg("transport", "Received SYN, sending SYN+ACK\n");
                call Sender.send(reply, reply.dest);
            }
            return SUCCESS;
        }

        if (fd == 0) return FAIL; // No socket found

        // Handle State Transitions
        switch(sockets[fd].state) {
            case SYN_SENT:
                if (tcp->flags == (TCP_SYN + TCP_ACK)) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = tcp->ack;
                    sockets[fd].nextExpected = tcp->seq + 1;
                    
                    signal Transport.connectDone(fd);

                    // Send ACK
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent + 1; 
                    replyTcp->ack = sockets[fd].nextExpected;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = getAdvertisedWindow(fd);
                    replyTcp->payloadLen = 0;
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    
                    dbg("transport", "Conn Established. Sending ACK.\n");
                    call Sender.send(reply, reply.dest);
                }
                break;

            case SYN_RCVD:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = ESTABLISHED;
                    dbg("transport", "Server Established.\n");
                }
                break;

            case ESTABLISHED:
                // Handle Data
                if (tcp->flags == TCP_DATA) {
                    if (tcp->seq == sockets[fd].nextExpected) {
                        dbg("transport", "Data Received Seq: %d Len: %d\n", tcp->seq, tcp->payloadLen);
                        
                        // Write to Recv Buffer
                        for(i=0; i<tcp->payloadLen; i++) {
                            uint16_t idx = (sockets[fd].lastRcvd + 1) % SOCKET_BUFFER_SIZE;
                            sockets[fd].rcvdBuff[idx] = tcp->payload[i];
                            sockets[fd].lastRcvd++;
                        }
                        sockets[fd].nextExpected = tcp->seq + tcp->payloadLen; // Or +1 if simplified

                        // IMPORTANT: Print Data immediately as per "Tips"
                        // This emulates the application reading immediately
                        // Construct string for debug
                        dbg("transport", "Reading Data: ");
                        for(i=0; i<tcp->payloadLen; i++) {
                             // Assuming payload is uint16_t split into bytes? 
                             // Instructions say send 0 to [transfer].
                             // If sender sends uint16, we receive 2 bytes.
                             // For simplicity of printing logic here:
                             // (In a real app, signal Transport.receive would let App handle this)
                        }
                        // For Project 3 output format requirement, print contents
                        // Note: formatting implies CSV style.
                    }

                    // Send ACK (Cumulative)
                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent; // ACKs don't consume seq
                    replyTcp->ack = sockets[fd].nextExpected;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = getAdvertisedWindow(fd);
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    call Sender.send(reply, reply.dest);
                }

                // Handle FIN
                if (tcp->flags == TCP_FIN) {
                     sockets[fd].state = CLOSE_WAIT;
                     // Send ACK
                     // Logic to close...
                     sockets[fd].flag = 0; // Release socket for now (simplified)
                     dbg("transport", "Connection Closed by peer.\n");
                }
                
                // Handle ACK for sent data
                if (tcp->flags == TCP_ACK) {
                    if(tcp->ack > sockets[fd].lastAck) {
                        sockets[fd].lastAck = tcp->ack;
                        // Slide window, send more data if available
                        sendData(fd);
                    }
                }
                break;
        }
        return SUCCESS;
    }

    event void TransportTimer.fired() {
        // Retransmission Logic
        // Iterate sockets, if Established and LastSent > LastAck, check timeout
        // For simplified Stop-and-Wait or Go-Back-N:
        // If (Now - TimePacketSent > RTT*2) Resend.
        // Since we don't have per-packet timestamps in this simple struct,
        // we can just blindly re-send unacked data periodically.
        
        uint8_t i;
        for(i=1; i<MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].flag && sockets[i].state == ESTABLISHED) {
                if(sockets[i].lastSent > sockets[i].lastAck) {
                    // Primitive Retransmission: Move LastSent back to LastAck and resend
                    // This is Go-Back-N behavior
                    dbg("transport", "Timeout! Retransmitting from %d\n", sockets[i].lastAck);
                    sockets[i].lastSent = sockets[i].lastAck;
                    sendData(i);
                }
            }
        }
    }
}