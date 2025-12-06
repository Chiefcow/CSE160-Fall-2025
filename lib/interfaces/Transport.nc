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
    
    command error_t receive(pack* msg);
    
    // Signals to Application
    event error_t accept(socket_t fd);
    event void connectDone(socket_t fd);
}