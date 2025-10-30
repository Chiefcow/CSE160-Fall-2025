//Headers to be used by LSR
#include "../../includes/packet.h"
#include "../../includes/linkstate.h"

//Interface defines which functions our Routing procedure shall use
interface LinkState {
    command error_t start();
    //handle the link state packet and its content
    command void handleLSP(pack* message);
    command void printRoutingTable();
    //Get the next hop using the dest; again memory constraints allows us to specify an uint16
    command unint16_t getNextHop(unint16_t dest);
    //Handling updated cost
    command void triggerLSPUpdate();
}
