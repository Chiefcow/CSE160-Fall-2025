#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"



 module FloodingP {
    provides interface Flooding;
    // provides interface SimpleSend;
    // uses interface SimpleSend as Sender;
 }

implementation { 
    command error_t Flooding.start() {};

    command void Flooding._flood(uint8_t message, uint8_t receive) {};

    command void Flooding.handle_flooding(pack* message) {};


}
