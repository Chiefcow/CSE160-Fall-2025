#include "../../includes/socket.h"

configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    components new SimpleSendC(PROTOCOL_TCP); // Uses Project 2 routing/flooding
    components RandomC;
    components new TimerMilliC() as TransportTimer;

    components LinkStateC;

    Transport = TransportP;
    
    TransportP.Sender -> SimpleSendC;
    TransportP.Random -> RandomC;
    TransportP.TransportTimer -> TransportTimer;

    TransportP.LinkState -> LinkStateC;
}