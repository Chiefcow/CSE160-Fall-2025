/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"
//#include "../../lib/interfaces/SimpleSend.nc"

configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as NeighborTimerC;
    components new HashmapC(uint32_t, 20) as NeighborMapC;
    components new ListC(uint16_t, 20) as NeighborListC;
    
    NeighborDiscovery = NeighborDiscoveryP;
    
    NeighborDiscoveryP.Sender -> SimpleSendC;
    NeighborDiscoveryP.NeighborTimer -> NeighborTimerC;
    NeighborDiscoveryP.NeighborMap -> NeighborMapC;
    NeighborDiscoveryP.NeighborList -> NeighborListC;
    // components NeighborDiscoveryP;
    // NeighborDiscovery = NeighborDiscoveryP;

    // //components new SimpleSendP();
    // // components new SimpleSendC(AM_PACK);
    // // NeighborDiscoveryP.Sender -> SimpleSendC;
    
}


