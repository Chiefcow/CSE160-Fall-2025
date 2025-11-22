#include "../../includes/socket.h"

configuration TransportSimpleC {
    provides interface Transport;
}

implementation {
    components TransportSimpleP;
    components new SimpleSendC(AM_PACK);
    components LinkStateC;
    
    Transport = TransportSimpleP;
    TransportSimpleP.Sender -> SimpleSendC;
    TransportSimpleP.LinkState -> LinkStateC;
}