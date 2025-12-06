#include "../../includes/socket.h"
#include "../../includes/packet.h"

interface Transport {
    command error_t start();
    command socket_t socket();
    command error_t bind(socket_t fd, socket_addr_t *addr);
    command socket_t accept(socket_t fd);  // FIXED: command returning socket_t
    command error_t listen(socket_t fd);
    command error_t connect(socket_t fd, socket_addr_t * addr);
    command error_t close(socket_t fd);
    command error_t send(socket_t fd, uint8_t *buff, uint16_t bufflen);
    command uint16_t read(socket_t fd, uint8_t* buff, uint16_t bufflen);
    command error_t receive(pack* msg);
    
    // Signals to Application
    event void connectDone(socket_t fd);
}