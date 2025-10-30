#include <Timer.h> //used for sending LSR packets periodically
#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration LinkStateC {
    provides interface LinkState;
}

//define which other components LSR will use
implmentation {
    component LinkStateP;
    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as LSPTimerC;
    //make use of our given hashmap ds for indexing LSR packets | 20 represents nodes in the network
    components new HashmapC(linkstate_packet, 20) as LSPCacheC;
    components new HashmapC(routing_entry, 20) as RoutingTableC;
    //Use our given list ds to account for unvisted nodes
    components new ListC(unint16_t, 20) as UnvisitedC;

    components NeighborDiscoveryC;
    components FloodingC;

    LinkState = LinkStateP;

    //Wiring
    LinkStateP.Sender -> SimpleSendC;
    LinkStateP.LSPTimer -> LSPTimerC;
    LinkStateP.LSPCache -> LSPCacheC;
    LinkStateP.RoutingTable -> RoutingTableC;
    LinkStateP.Unvisited -> UnvisitedC;
    
    //Wiring to exisiting modules from proj 1
    LinkStateP.NeighborDiscovery -> NeighborDiscoveryC;
    LinkStateP.Flooding -> FloodingC;

}