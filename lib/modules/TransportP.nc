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
    uses interface List<pack> as PacketQueue;
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    uint8_t getAdvertisedWindow(uint8_t fd) {
        uint16_t used = sockets[fd].lastRcvd - sockets[fd].lastRead;
        if (used >= SOCKET_BUFFER_SIZE) return 0;
        return SOCKET_BUFFER_SIZE - used;
    }

    uint8_t findSocket(uint16_t srcAddr, uint8_t srcPort, uint16_t destAddr, uint8_t destPort) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].flag == 0) continue;
            
            if (sockets[i].src == destPort && sockets[i].dest.addr == srcAddr && sockets[i].dest.port == srcPort) {
                return i;
            }
            if (sockets[i].state == LISTEN && sockets[i].src == destPort) {
                return i;
            }
        }
        return 0;
    }

    command error_t Transport.start() {
        uint8_t i;
        for(i=0; i<MAX_NUM_OF_SOCKETS; i++) {
            sockets[i].flag = 0;
        }
        call TransportTimer.startPeriodic(100);
        return SUCCESS;
    }

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) { 
            if (sockets[i].flag == 0) {
                sockets[i].flag = 1;
                sockets[i].state = CLOSED;
                sockets[i].RTT = 20; 
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 1;
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

    void routeAndSend(pack packet, uint16_t dest) {
        uint16_t nextHop = call LinkState.getNextHop(dest);
        if (nextHop == AM_BROADCAST_ADDR) {
            // If routing fails, we can't send unicast. 
            // In a real TCP, we might drop, but here we can try broadcasting/flooding 
            // or just drop. For robustness in this project, use broadcast:
            nextHop = AM_BROADCAST_ADDR;
        }
        call Sender.send(packet, nextHop);
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
        tcp->seq = sockets[fd].lastSent + 1;
        tcp->flags = TCP_SYN;
        tcp->window = getAdvertisedWindow(fd);
        tcp->payloadLen = 0;

        packet.src = TOS_NODE_ID;
        packet.dest = sockets[fd].dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;
        packet.seq = 0; 
        
        dbg("transport", "Sending SYN to %d port %d\n", sockets[fd].dest.addr, sockets[fd].dest.port);
        routeAndSend(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    void sendData(socket_t fd) {
        pack packet;
        tcp_pack* tcp;
        uint8_t payloadInd;
        uint16_t seqToSend;

        if(sockets[fd].state != ESTABLISHED) return;

        if(sockets[fd].lastWritten > sockets[fd].lastSent) {
            uint8_t maxPayload = 10; 
            
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
            packet.protocol = PROTOCOL_TCP;
            packet.TTL = MAX_TTL;
            
            dbg("transport", "Sending DATA Seq: %d Len: %d\n", seqToSend, tcp->payloadLen);
            routeAndSend(packet, sockets[fd].dest.addr);
        }
    }

    command error_t Transport.send(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t i;
        if (sockets[fd].state != ESTABLISHED) return FAIL;

        for(i=0; i<bufflen; i++) {
             uint16_t nextIdx = (sockets[fd].lastWritten + 1) % SOCKET_BUFFER_SIZE;
             if(nextIdx == sockets[fd].lastAck % SOCKET_BUFFER_SIZE) {
                 break;
             }
             sockets[fd].lastWritten++;
             sockets[fd].sendBuff[sockets[fd].lastWritten % SOCKET_BUFFER_SIZE] = buff[i];
        }

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
        packet.TTL = MAX_TTL;

        routeAndSend(packet, sockets[fd].dest.addr);
        return SUCCESS;
    }

    command error_t Transport.receive(pack* msg) {
        tcp_pack* tcp = (tcp_pack*)msg->payload;
        uint8_t fd;
        pack reply;
        tcp_pack* replyTcp;
        uint8_t i;

        fd = findSocket(msg->src, tcp->srcPort, msg->dest, tcp->destPort);
        
        if (fd != 0 && sockets[fd].state == LISTEN && tcp->flags == TCP_SYN) {
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

                dbg("transport", "Received SYN, sending SYN+ACK\n");
                routeAndSend(reply, reply.dest);
            }
            return SUCCESS;
        }

        if (fd == 0) return FAIL;

        switch(sockets[fd].state) {
            case SYN_SENT:
                if (tcp->flags == (TCP_SYN + TCP_ACK)) {
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastAck = tcp->ack;
                    sockets[fd].nextExpected = tcp->seq + 1;
                    
                    signal Transport.connectDone(fd);

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
                    reply.TTL = MAX_TTL;
                    
                    dbg("transport", "Conn Established. Sending ACK.\n");
                    routeAndSend(reply, reply.dest);
                }
                break;
            case SYN_RCVD:
                if (tcp->flags == TCP_ACK) {
                    sockets[fd].state = ESTABLISHED;
                    dbg("transport", "Server Established.\n");
                }
                break;
            case ESTABLISHED:
                if (tcp->flags == TCP_DATA) {
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
                            // Print logic
                        }
                    }

                    replyTcp = (tcp_pack*)reply.payload;
                    replyTcp->srcPort = sockets[fd].src;
                    replyTcp->destPort = sockets[fd].dest.port;
                    replyTcp->seq = sockets[fd].lastSent; 
                    replyTcp->ack = sockets[fd].nextExpected;
                    replyTcp->flags = TCP_ACK;
                    replyTcp->window = getAdvertisedWindow(fd);
                    
                    reply.src = TOS_NODE_ID;
                    reply.dest = sockets[fd].dest.addr;
                    reply.protocol = PROTOCOL_TCP;
                    reply.TTL = MAX_TTL;

                    routeAndSend(reply, reply.dest);
                }

                if (tcp->flags == TCP_FIN) {
                     sockets[fd].state = CLOSE_WAIT;
                     sockets[fd].flag = 0;
                     dbg("transport", "Connection Closed by peer.\n");
                }
                
                if (tcp->flags == TCP_ACK) {
                    if(tcp->ack > sockets[fd].lastAck) {
                        sockets[fd].lastAck = tcp->ack;
                        sendData(fd);
                    }
                }
                break;
        }
        return SUCCESS;
    }

    event void TransportTimer.fired() {
        uint8_t i;
        for(i=1; i<MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].flag && sockets[i].state == ESTABLISHED) {
                if(sockets[i].lastSent > sockets[i].lastAck) {
                    dbg("transport", "Timeout! Retransmitting from %d\n", sockets[i].lastAck);
                    sockets[i].lastSent = sockets[i].lastAck;
                    sendData(i);
                }
            }
        }
    }
}