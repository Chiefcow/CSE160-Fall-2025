#include "../../includes/packet.h"

interface Flooding {
    command error_t start();
    
    command void _flood(uint8_t message, uint8_t receive);
    command void handle_flooding(pack* message);
}



