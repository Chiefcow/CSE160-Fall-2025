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

    //look here
    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;

    components FloodingC;
    Node.Flooding -> FloodingC;

    components LinkStateC;
    Node.LinkState -> LinkStateC;

    // Add SimpleSend for Node to send packets
    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    // Add Transport module
    components TransportC;
    Node.Transport -> TransportC;
    
    // Add client write timer
    components new TimerMilliC() as ClientWriteTimerC;
    Node.ClientWriteTimer -> ClientWriteTimerC;
    // components NeighborDiscoveryC;
    // Node.NeighborDiscovery -> SimpleSendC;
}
