#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

#define PROJECT3_CHANNEL "Project3TGen"

// Simplified socket structure
typedef struct simple_socket {
    bool in_use;
    enum socket_state state;
    uint8_t local_port;
    uint16_t remote_addr;
    uint8_t remote_port;
} simple_socket;

module TransportSimpleP {
    provides interface Transport;
    
    uses interface SimpleSend as Sender;
    uses interface LinkState;
}

implementation {
    // Simple socket storage - max 5 sockets
    simple_socket sockets[5];
    
    // Helper to find free socket
    socket_t getFreeSocket() {
        uint8_t i;
        for (i = 0; i < 5; i++) {
            if (!sockets[i].in_use) {
                return i;
            }
        }
        return NULL;  // No free sockets
    }
    
    // Helper to find socket by port
    socket_t findSocketByPort(uint8_t port) {
        uint8_t i;
        for (i = 0; i < 5; i++) {
            if (sockets[i].in_use && sockets[i].local_port == port) {
                return i;
            }
        }
        return NULL;
    }
    
    // Send TCP packet
    void sendTCPPacket(socket_t fd, uint8_t flags, uint8_t* data, uint8_t dataLen) {
        pack tcpPacket;
        tcp_packet tcpHdr;
        uint16_t nextHop;
        
        // Build TCP header
        tcpHdr.src_port = sockets[fd].local_port;
        tcpHdr.dest_port = sockets[fd].remote_port;
        tcpHdr.flags = flags;
        tcpHdr.data_len = dataLen;
        
        // Copy data if present
        if (dataLen > 0 && data != NULL) {
            memcpy(tcpHdr.payload, data, dataLen);
        }
        
        // Build packet
        tcpPacket.src = TOS_NODE_ID;
        tcpPacket.dest = sockets[fd].remote_addr;
        tcpPacket.TTL = MAX_TTL;
        tcpPacket.protocol = PROTOCOL_TCP;
        tcpPacket.seq = 0;
        memcpy(tcpPacket.payload, &tcpHdr, sizeof(tcp_packet));
        
        // Route and send
        nextHop = call LinkState.getNextHop(sockets[fd].remote_addr);
        if (nextHop != AM_BROADCAST_ADDR) {
            call Sender.send(tcpPacket, nextHop);
        }
        
        // Debug output
        if (flags & TCP_FLAG_SYN && flags & TCP_FLAG_ACK) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Syn Ack Packet Sent to Node %d for Port %d\n",
                TOS_NODE_ID, sockets[fd].remote_addr, sockets[fd].remote_port);
        } else if (flags & TCP_FLAG_SYN) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Syn Packet Sent to Node %d for Port %d\n",
                TOS_NODE_ID, sockets[fd].remote_addr, sockets[fd].remote_port);
        } else if (flags & TCP_FLAG_FIN) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Fin Packet Sent to Node %d for Port %d\n",
                TOS_NODE_ID, sockets[fd].remote_addr, sockets[fd].remote_port);
        } else if (flags & TCP_FLAG_DATA) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Data Packet Sent to Node %d (len=%d)\n",
                TOS_NODE_ID, sockets[fd].remote_addr, dataLen);
        }
    }
    
    //=================================================================
    // TRANSPORT INTERFACE IMPLEMENTATION
    //=================================================================
    
    command socket_t Transport.socket() {
        socket_t fd = getFreeSocket();
        if (fd != NULL) {
            sockets[fd].in_use = TRUE;
            sockets[fd].state = CLOSED;
            sockets[fd].local_port = 0;
            sockets[fd].remote_addr = 0;
            sockets[fd].remote_port = 0;
            
            dbg(TRANSPORT_CHANNEL, "Node %d: Created socket %d\n", TOS_NODE_ID, fd);
        }
        return fd;
    }
    
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (fd >= 5 || !sockets[fd].in_use) {
            return FAIL;
        }
        
        sockets[fd].local_port = addr->port;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Bound socket %d to port %d\n", 
            TOS_NODE_ID, fd, addr->port);
        
        return SUCCESS;
    }
    
    command error_t Transport.listen(socket_t fd) {
        if (fd >= 5 || !sockets[fd].in_use) {
            return FAIL;
        }
        
        sockets[fd].state = LISTEN;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Socket %d listening on port %d\n",
            TOS_NODE_ID, fd, sockets[fd].local_port);
        
        return SUCCESS;
    }
    
    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        if (fd >= 5 || !sockets[fd].in_use) {
            return FAIL;
        }
        
        sockets[fd].remote_addr = addr->addr;
        sockets[fd].remote_port = addr->port;
        sockets[fd].state = SYN_SENT;
        
        // Send SYN
        sendTCPPacket(fd, TCP_FLAG_SYN, NULL, 0);
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Connecting socket %d to %d:%d\n",
            TOS_NODE_ID, fd, addr->addr, addr->port);
        
        return SUCCESS;
    }
    
    command socket_t Transport.accept(socket_t fd) {
        // Simplified: just check if we got a SYN and moved to SYN_RCVD
        if (fd >= 5 || !sockets[fd].in_use) {
            return NULL;
        }
        
        // In real implementation, we'd create new socket here
        // For simplicity, we'll handle this in receive()
        return NULL;
    }
    
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        if (fd >= 5 || !sockets[fd].in_use || sockets[fd].state != ESTABLISHED) {
            return 0;
        }
        
        // Simple: just send ONE packet with the data
        if (bufflen > 16) bufflen = 16;  // Max 16 bytes
        
        sendTCPPacket(fd, TCP_FLAG_DATA, buff, bufflen);
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Sent %d bytes on socket %d\n",
            TOS_NODE_ID, bufflen, fd);
        
        return bufflen;
    }
    
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        // Not implemented in this simplified version
        return 0;
    }
    
    command error_t Transport.close(socket_t fd) {
        if (fd >= 5 || !sockets[fd].in_use) {
            return FAIL;
        }
        
        // Send FIN
        sendTCPPacket(fd, TCP_FLAG_FIN, NULL, 0);
        
        // Close socket
        sockets[fd].state = CLOSED;
        sockets[fd].in_use = FALSE;
        
        dbg(TRANSPORT_CHANNEL, "Node %d: Closed socket %d\n", TOS_NODE_ID, fd);
        
        return SUCCESS;
    }
    
    command error_t Transport.release(socket_t fd) {
        if (fd >= 5) {
            return FAIL;
        }
        
        sockets[fd].in_use = FALSE;
        sockets[fd].state = CLOSED;
        return SUCCESS;
    }
    
    //=================================================================
    // RECEIVE HANDLER - This is where the magic happens
    //=================================================================
    
    command error_t Transport.receive(pack* package) {
        tcp_packet* tcpHdr = (tcp_packet*) package->payload;
        socket_t fd;
        
        //---------------------------------------------------
        // HANDLE SYN (Server side - connection request)
        //---------------------------------------------------
        if (tcpHdr->flags == TCP_FLAG_SYN) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Syn Packet Arrived from Node %d for Port %d\n",
                TOS_NODE_ID, package->src, tcpHdr->dest_port);
            
            // Find listening socket
            fd = findSocketByPort(tcpHdr->dest_port);
            
            if (fd != NULL && sockets[fd].state == LISTEN) {
                // Store connection info
                sockets[fd].remote_addr = package->src;
                sockets[fd].remote_port = tcpHdr->src_port;
                sockets[fd].state = SYN_RCVD;
                
                // Send SYN-ACK
                sendTCPPacket(fd, TCP_FLAG_SYN | TCP_FLAG_ACK, NULL, 0);
            }
            return SUCCESS;
        }
        
        //---------------------------------------------------
        // HANDLE SYN-ACK (Client side - connection accepted)
        //---------------------------------------------------
        if (tcpHdr->flags == (TCP_FLAG_SYN | TCP_FLAG_ACK)) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Syn Ack Packet Arrived from Node %d for Port %d\n",
                TOS_NODE_ID, package->src, tcpHdr->src_port);
            
            // Find our socket
            fd = findSocketByPort(tcpHdr->dest_port);
            
            if (fd != NULL && sockets[fd].state == SYN_SENT) {
                sockets[fd].state = ESTABLISHED;
                
                // Send final ACK
                sendTCPPacket(fd, TCP_FLAG_ACK, NULL, 0);
                
                dbg(TRANSPORT_CHANNEL, "Node %d: Connection ESTABLISHED on socket %d\n",
                    TOS_NODE_ID, fd);
            }
            return SUCCESS;
        }
        
        //---------------------------------------------------
        // HANDLE ACK (Server side - final handshake)
        //---------------------------------------------------
        if (tcpHdr->flags == TCP_FLAG_ACK) {
            fd = findSocketByPort(tcpHdr->dest_port);
            
            if (fd != NULL && sockets[fd].state == SYN_RCVD) {
                sockets[fd].state = ESTABLISHED;
                
                dbg(TRANSPORT_CHANNEL, "Node %d: Connection ESTABLISHED on socket %d\n",
                    TOS_NODE_ID, fd);
            }
            return SUCCESS;
        }
        
        //---------------------------------------------------
        // HANDLE DATA (Receive data packet)
        //---------------------------------------------------
        if (tcpHdr->flags == TCP_FLAG_DATA) {
            uint8_t i;
            
            fd = findSocketByPort(tcpHdr->dest_port);
            
            if (fd != NULL && sockets[fd].state == ESTABLISHED) {
                dbg(PROJECT3_CHANNEL, "Debug(%d): Received %d bytes from Node %d:\n",
                    TOS_NODE_ID, tcpHdr->data_len, package->src);
                
                // Print the data
                dbg_clear(PROJECT3_CHANNEL, "Data: ");
                for (i = 0; i < tcpHdr->data_len; i++) {
                    dbg_clear(PROJECT3_CHANNEL, "%d ", tcpHdr->payload[i]);
                }
                dbg_clear(PROJECT3_CHANNEL, "\n");
                
                // Send ACK back
                sendTCPPacket(fd, TCP_FLAG_ACK, NULL, 0);
            }
            return SUCCESS;
        }
        
        //---------------------------------------------------
        // HANDLE FIN (Connection close request)
        //---------------------------------------------------
        if (tcpHdr->flags == TCP_FLAG_FIN) {
            dbg(PROJECT3_CHANNEL, "Debug(%d): Fin Packet Arrived from Node %d for Port %d\n",
                TOS_NODE_ID, package->src, tcpHdr->src_port);
            
            fd = findSocketByPort(tcpHdr->dest_port);
            
            if (fd != NULL) {
                // Send FIN-ACK
                sendTCPPacket(fd, TCP_FLAG_FIN | TCP_FLAG_ACK, NULL, 0);
                
                // Close socket
                sockets[fd].state = CLOSED;
                sockets[fd].in_use = FALSE;
                
                dbg(TRANSPORT_CHANNEL, "Node %d: Connection closed on socket %d\n",
                    TOS_NODE_ID, fd);
            }
            return SUCCESS;
        }
        
        return FAIL;
    }
}
