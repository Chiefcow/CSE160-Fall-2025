#include "../../includes/socket.h"
#include "../../includes/packet.h"

interface Transport {
    command error_t start();
    command socket_t socket();
    command error_t bind(socket_t fd, socket_addr_t *addr);
    command error_t listen(socket_t fd);
    command error_t connect(socket_t fd, socket_addr_t * addr);
    command error_t close(socket_t fd);
    
    // Returns the number of bytes actually written to the buffer
    // May be less than bufflen if buffer is full
    command uint16_t send(socket_t fd, uint8_t *buff, uint16_t bufflen);
    
    // Read data from receive buffer
    // Returns number of bytes read
    command uint16_t read(socket_t fd, uint8_t *buff, uint16_t bufflen);
    
    command error_t receive(pack* msg);
    
    // Get source address for a socket (for server to know client addr)
    command uint16_t getSocketSrcAddr(socket_t fd);
    command uint8_t getSocketSrcPort(socket_t fd);
    
    // Signals to Application
    event error_t accept(socket_t fd);
    event void connectDone(socket_t fd);
    
    // Signal when data is received (for chat application)
    event void dataReceived(socket_t fd);
}