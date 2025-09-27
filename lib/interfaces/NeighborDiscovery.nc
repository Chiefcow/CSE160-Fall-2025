#include "../../includes/packet.h"

interface NeighborDiscovery {
   command error_t start();
   command void handleNeighbor(pack* myMsg);
}


// #include "../../includes/packet.h"


// interface NeighborDiscovery {
//     command void NeighborDiscovery();
// }


// // Header NeighborDiscovery


