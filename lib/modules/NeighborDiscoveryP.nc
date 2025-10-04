#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface Timer<TMilli> as Timer0;
    uses interface Flooding;  // to disseminate periodic NbD probes through flooding
}
implementation {
    // very simple neighbor book-keeping
    bool seen[256];
    uint8_t neighborCount = 0;
    static uint16_t nbdSeq = 0;   // NbD’s own sequence space

    command error_t NeighborDiscovery.start() {
        // init seen table
        for (uint16_t i = 0; i < 256; i++) seen[i] = FALSE;
        neighborCount = 0;
        dbg(NEIGHBOR_CHANNEL, "NeighborDiscovery started\n");

        // send a probe every 10 seconds
        call Timer0.startPeriodic(10000);
        return SUCCESS;
    }

    event void Timer0.fired() {
        // Build a Neighbor Discovery probe and inject it into flooding
        pack pkt;

        pkt.src      = TOS_NODE_ID;
        pkt.dest     = AM_BROADCAST_ADDR;  // flood
        pkt.TTL      = 5;
        pkt.protocol = PROTOCOL_NBD;
        pkt.seq      = nbdSeq++;

        // small payload (optional)
        const char *txt = "NbDPing";
        uint8_t i = 0;
        while (txt[i] && i < PACKET_MAX_PAYLOAD_SIZE) {
            pkt.payload[i] = (uint8_t)txt[i];
            i++;
        }

        dbg(NEIGHBOR_CHANNEL, "Node %d sending NbD probe seq=%d\n", TOS_NODE_ID, pkt.seq);
        call Flooding.handle_flooding(&pkt);
    }

    // This is the event FloodingP signals for every *new* flooded packet
    event void NeighborDiscovery.handleNeighbor(pack* msg) {
        // don’t count self
        if (msg->src == TOS_NODE_ID) return;

        if (!seen[msg->src]) {
            seen[msg->src] = TRUE;
            neighborCount++;
            dbg(NEIGHBOR_CHANNEL, "Node %d discovered neighbor %d (total=%d) via proto=%d seq=%d\n",
                TOS_NODE_ID, msg->src, neighborCount, msg->protocol, msg->seq);
        }
        // (You can add aging with timestamps to remove stale neighbors later)
    }
}
