#include "../../includes/socket.h"

configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    components new SimpleSendC(AM_PACK);
    components RandomC;
    components new TimerMilliC() as TransportTimer;
    components new ListC(pending_packet_t, MAX_RETRANSMIT_QUEUE) as RetransmitQueueC;
    components LinkStateC;

    Transport = TransportP;
    
    TransportP.Sender -> SimpleSendC;
    TransportP.Random -> RandomC;
    TransportP.TransportTimer -> TransportTimer;
    TransportP.RetransmitQueue -> RetransmitQueueC;
    TransportP.LinkState -> LinkStateC;
}
