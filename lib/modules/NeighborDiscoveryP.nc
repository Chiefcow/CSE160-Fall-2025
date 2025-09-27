#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"



 module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    provides interface SimpleSend;
    uses interface SimpleSend as Sender;
 }

implementation {
    command error_t NeighborDiscovery.start() {};

    command void NeighborDiscovery.handleNeighbor(pack* myMsg) {};


}
