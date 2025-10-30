#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration LinkStateC {
    provides interface LinkState;
}

implementation {  // Fixed typo: was "implmentation"
    components LinkStateP;
    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as LSPTimerC;
    components new HashmapC(linkstate_packet, 20) as LSPCacheC;
    components new HashmapC(routing_entry, 20) as RoutingTableC;
    components new ListC(uint16_t, 20) as UnvisitedC;
    
    components NeighborDiscoveryC;
    components FloodingC;
    
    LinkState = LinkStateP;
    
    LinkStateP.Sender -> SimpleSendC;
    LinkStateP.LSPTimer -> LSPTimerC;
    LinkStateP.LSPCache -> LSPCacheC;
    LinkStateP.RoutingTable -> RoutingTableC;
    LinkStateP.Unvisited -> UnvisitedC;
    
    LinkStateP.NeighborDiscovery -> NeighborDiscoveryC;
    LinkStateP.Flooding -> FloodingC;
}