#include "../../includes/packet.h"
#include "../../includes/linkstate.h"

interface LinkState {
    command error_t start();
    //handling unique link state packet
    command void handleLSP(pack* message);
    command void printRoutingTable();
    command uint16_t getNextHop(uint16_t dest); 
    //
    command void triggerLSPUpdate();
}
