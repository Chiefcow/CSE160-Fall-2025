/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
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
    components new TimerMilliC() as AcceptTimerC;
    components new TimerMilliC() as ClientWriteTimerC;

    Node -> MainC.Boot;
    Node.Receive -> GeneralReceive;
    Node.AcceptTimer -> AcceptTimerC;
    Node.ClientWriteTimer -> ClientWriteTimerC;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;

    components FloodingC;
    Node.Flooding -> FloodingC;

    components LinkStateC;
    Node.LinkState -> LinkStateC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components TransportC;
    Node.Transport -> TransportC;
}
