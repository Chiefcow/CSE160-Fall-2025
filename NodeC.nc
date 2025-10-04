#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC { }
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components ActiveMessageC;
    components new SimpleSendC(AM_PACK);
    components CommandHandlerC;

    // Flooding + Neighbor Discovery
    components FloodingC;
    components NeighborDiscoveryC;

    // Boot & Receive
    Node -> MainC.Boot;
    Node.Receive -> GeneralReceive;

    // Radio
    Node.AMControl -> ActiveMessageC;

    // SimpleSend for Node
    Node.Sender -> SimpleSendC;

    // Commands
    Node.CommandHandler -> CommandHandlerC;

    // Flooding to Node
    Node.Flooding -> FloodingC;

    // Neighbor Discovery to Node
    Node.NeighborDiscovery -> NeighborDiscoveryC;

    // Cross wiring:
    //  - Let Flooding notify NbD (events)
    //  - Let NbD send its probes through Flooding (commands)
    FloodingC.NeighborDiscovery   -> NeighborDiscoveryC;
    NeighborDiscoveryC.Flooding   -> FloodingC;
}
