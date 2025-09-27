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
    provides interface SimpleSend;
    uses interface SimpleSend as Sender;
}

implementation {
    components NeighborDiscoveryP;
    components new SimpleSendP();
    NeighborDiscovery = NeighborDiscoveryP;

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryP.Sender -> SimpleSendC;
    
}


