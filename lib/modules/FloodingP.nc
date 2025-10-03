#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"



module FloodingP {
    provides interface Flooding;
    uses interface SimpleSend as Sender;
}
implementation {
    static uint16_t lastSeq[256];

    // Initialize table
    void initSeqTable() {
        int i;
        for (i = 0; i < 256; i++) {
            lastSeq[i] = 0xFFFF;   // invalid starting value
        }
    }

    command error_t Flooding.start() {
        initSeqTable();
        dbg(FLOODING_CHANNEL, "Flooding module started\n");
        return SUCCESS;
    }

    command void Flooding._flood(uint8_t message, uint8_t receive) {
        dbg(FLOODING_CHANNEL, "Manual flood requested (not implemented yet)\n");
    }

    command void Flooding.handle_flooding(pack* msg) {
        // Duplicate check
        if (lastSeq[msg->src] == msg->seq) {
            dbg(FLOODING_CHANNEL,
                "Duplicate packet from %d seq=%d, dropping\n",
                msg->src, msg->seq);
            return;
        }

        // Update last seen
        lastSeq[msg->src] = msg->seq;

        // Deliver locally or rebroadcast
        if (msg->dest == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL,
                "Flooded packet reached destination %d with payload=%s\n",
                TOS_NODE_ID, msg->payload);
        } else {
            dbg(FLOODING_CHANNEL,
                "Rebroadcasting packet from %d seq=%d\n",
                msg->src, msg->seq);
                call Sender.send(*msg, AM_BROADCAST_ADDR);
        }
    }
}