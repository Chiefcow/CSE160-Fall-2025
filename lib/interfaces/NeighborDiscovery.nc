#include "../../includes/packet.h"

interface NeighborDiscovery {
    command error_t start();
    command void handleNeighbor(pack* message);
    command void printNeighbors();
    command uint16_t* getNeighbors();
    command uint16_t getNeighborListSize();
}
   