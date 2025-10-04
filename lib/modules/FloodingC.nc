#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"

configuration FloodingC {
    provides interface Flooding;
    uses interface NeighborDiscovery;  // <-- so NodeC can connect this to NeighborDiscoveryC
}
implementation {
    components FloodingP;
    components new SimpleSendC(AM_PACK);

    Flooding = FloodingP;
    FloodingP.Sender -> SimpleSendC;

    // pass-through of NeighborDiscovery to FloodingP
    FloodingP.NeighborDiscovery -> NeighborDiscovery;
}
