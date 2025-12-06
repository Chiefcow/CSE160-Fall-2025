/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    // Command Handler
    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    // Neighbor Discovery
    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;

    // Flooding
    components FloodingC;
    Node.Flooding -> FloodingC;

    // Link State Routing
    components LinkStateC;
    Node.LinkState -> LinkStateC;

    // SimpleSend for Node to send packets
    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    // Transport Layer
    components TransportC;
    Node.Transport -> TransportC;
    
    // Timer for client data sending
    components new TimerMilliC() as ClientWriteTimerC;
    Node.ClientWriteTimer -> ClientWriteTimerC;
}
