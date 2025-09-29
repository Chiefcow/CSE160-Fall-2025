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

configuration FloodingC {
    provides interface Flooding;
    //provides interface SimpleSend;
    //uses interface SimpleSend as Sender;
}

implementation {
    components FloodingP;
    Flooding = FloodingP;
    
    //components new SimpleSendP();

    // components new SimpleSendC(AM_PACK);
    // NeighborDiscoveryP.Sender -> SimpleSendC;
    
}


