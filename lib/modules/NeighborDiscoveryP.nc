#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

//result_r --> Returns success or failure

 module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
 }

implementation {
    command error_t NeighborDiscovery.start() {};

    command void NeighborDiscovery.neighborPing(pack* pkt_info) {};
    /*
    Currenlty empty as I am...At the moment, in the process of re-manifacturing my partners code base
    As it stands my partner was set with keeping his FLooding implementation in NodeC.nc...
    The reason I was skeptical about merging both code bases was because I maintain a desire to keep
    the code base clean and support best practice philosophies.  I also consider network efficiency
    as a top design choice.  The single point of failure issue, which I addressed
    in the discussion document explains why I am steering towards this direction; which I why I am not fully on board with 
    Flooding implementation being bound to Node.
    */
    
}
