//Headers to be used by LSR
#include "../../includes/packet.h"
#include "../../includes/linkstate.h"

//Interface defines which functions our Routing procedure shall use
interface LinkState {
    command error_t start();
    command void handleLSP(pack* message);
    command void printRoutingTable();
    command unint16_t getNextHop(unint16_t dest);
    command void triggerLSPUpdate();
}
