#include <Timer.h>
#include "../../includes/packet.h"

configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as TransportTimerC;
    components new TimerMilliC() as ClientWriteTimerC;
    
    // Add LinkState for routing
    components LinkStateC;
    
    Transport = TransportP;
    
    TransportP.Sender -> SimpleSendC;
    TransportP.TransportTimer -> TransportTimerC;
    TransportP.ClientWriteTimer -> ClientWriteTimerC;
    TransportP.LinkState -> LinkStateC;  // Wire up LinkState
}