#include "../../includes/socket.h"
#include "../../includes/packet.h"

interface Transport {
    /**
     * Initialize transport layer
     */
    command error_t start();
    
    /**
     * Create a new socket
     * Returns: socket file descriptor (1-9), or 0 on failure
     */
    command socket_t socket();
    
    /**
     * Bind socket to local address/port
     */
    command error_t bind(socket_t fd, socket_addr_t *addr);
    
    /**
     * Accept a pending connection (for servers)
     * Returns: new socket for the accepted connection, or 0 if no pending connections
     */
    command socket_t accept(socket_t fd);
    
    /**
     * Mark socket as listening for incoming connections
     */
    command error_t listen(socket_t fd);
    
    /**
     * Connect to remote server (for clients)
     */
    command error_t connect(socket_t fd, socket_addr_t * addr);
    
    /**
     * Close a connection gracefully
     */
    command error_t close(socket_t fd);
    
    /**
     * Send data on a socket
     * Returns: SUCCESS if buffered, FAIL if socket not established or buffer full
     */
    command error_t send(socket_t fd, uint8_t *buff, uint16_t bufflen);
    
    /**
     * Read data from a socket
     * Returns: number of bytes read
     */
    command uint16_t read(socket_t fd, uint8_t* buff, uint16_t bufflen);
    
    /**
     * Receive and process incoming TCP packet
     */
    command error_t receive(pack* msg);
    
    /**
     * Signal when connection is established (for clients)
     */
    event void connectDone(socket_t fd);
}
