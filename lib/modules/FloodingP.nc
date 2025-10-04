#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module FloodingP {
    provides interface Flooding;
    uses interface SimpleSend as Sender;
    uses interface NeighborDiscovery;   // <-- we’ll signal this when we see any new flooded pkt
}
implementation {
    static uint16_t lastSeq[256];

    static inline void initSeqTable() {
        for (uint16_t i = 0; i < 256; i++) {
            lastSeq[i] = 0xFFFF;   // “no packet yet from that src”
        }
    }

    command error_t Flooding.start() {
        initSeqTable();
        dbg(FLOODING_CHANNEL, "Flooding module started\n");
        return SUCCESS;
    }

    command void Flooding._flood(uint8_t message, uint8_t receive) {
        // optional manual flood hook (unused)
        dbg(FLOODING_CHANNEL, "Manual flood requested\n");
    }

    command void Flooding.handle_flooding(pack* msg) {
        // Duplicate check
        if (lastSeq[msg->src] != 0xFFFF && lastSeq[msg->src] == msg->seq) {
            dbg(FLOODING_CHANNEL, "Duplicate packet from %d seq=%d, dropping\n", msg->src, msg->seq);
            return;
        }
        lastSeq[msg->src] = msg->seq;

        // Notify Neighbor Discovery about every NEW flooded packet
        signal NeighborDiscovery.handleNeighbor(msg);

        // Deliver or rebroadcast
        if (msg->dest == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL, "Flooded packet reached destination %d with payload=%s\n",
                TOS_NODE_ID, msg->payload);
        } else {
            dbg(FLOODING_CHANNEL, "Rebroadcasting packet from %d seq=%d (node %d)\n",
                msg->src, msg->seq, TOS_NODE_ID);
            call Sender.send(*msg, AM_BROADCAST_ADDR);
        }
    }
}
