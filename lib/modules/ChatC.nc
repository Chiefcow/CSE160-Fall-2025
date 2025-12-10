#include "../../includes/socket.h"
#include "../../includes/chat.h"

configuration ChatC {
    provides interface Chat;
}

implementation {
    components ChatP;
    components TransportC;
    components new TimerMilliC() as ChatTimerC;
    
    Chat = ChatP;
    
    ChatP.Transport -> TransportC;
    ChatP.ChatTimer -> ChatTimerC;
}