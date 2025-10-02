#include "../../includes/packet.h"

// module NeighborDiscovery{
//     uses interface SimpleSend as Sender;
// }

interface NeighborDiscovery {
   command error_t start();
   command void handleNeighbor(pack* message);
}


// #include "../../includes/packet.h"


// interface NeighborDiscovery {
//     command void NeighborDiscovery();
// }


// // Header NeighborDiscovery


