#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

#define NEIGHBOR_TIMEOUT 30000
#define NEIGHBOR_PERIOD 10000


 module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as NeighborTimer;
    uses interface Hashmap<uint32_t> as NeighborMap;  // Key: nodeId, Value: lastSeen time
    uses interface List<uint16_t> as NeighborList;
 }

implementation {
    pack neighborPacket;
    uint32_t currentTime = 0;
    uint16_t neighborArray[20];  // Static array to return neighbors
    
    void sendNeighborDiscovery() {
        uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
        
        // Create neighbor discovery packet
        neighborPacket.src = TOS_NODE_ID;
        neighborPacket.dest = AM_BROADCAST_ADDR;
        neighborPacket.TTL = 1;  // Only 1 hop for neighbor discovery
        neighborPacket.seq = 0;  // Not used for neighbor discovery
        neighborPacket.protocol = PROTOCOL_NEIGHBOR_DISCOVERY;
        
        // Add node ID to payload for identification
        memcpy(payload, "NEIGHBOR_PING", 13);
        memcpy(neighborPacket.payload, payload, PACKET_MAX_PAYLOAD_SIZE);
        
        dbg(NEIGHBOR_CHANNEL, "Node %d: Broadcasting neighbor discovery packet\n", TOS_NODE_ID);
        call Sender.send(neighborPacket, AM_BROADCAST_ADDR);
    }
    
    void updateNeighborList() {
        uint32_t* keys;
        uint16_t i, size;
        
        // Clear the current neighbor list
        while (!call NeighborList.isEmpty()) {
            call NeighborList.popfront();
        }
        
        // Get all neighbors from the hashmap
        keys = call NeighborMap.getKeys();
        size = call NeighborMap.size();
        
        // Check for expired neighbors and update list
        for (i = 0; i < size; i++) {
            uint32_t nodeId = keys[i];
            uint32_t lastSeen = call NeighborMap.get(nodeId);
            
            // Check if neighbor has timed out
            if ((currentTime - lastSeen) > NEIGHBOR_TIMEOUT) {
                dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor %d timed out, removing\n", 
                    TOS_NODE_ID, nodeId);
                call NeighborMap.remove(nodeId);
            } else {
                // Add active neighbor to list
                call NeighborList.pushback((uint16_t)nodeId);
            }
        }
    }
    
    command error_t NeighborDiscovery.start() {
        dbg(NEIGHBOR_CHANNEL, "Node %d: Starting neighbor discovery\n", TOS_NODE_ID);
        
        // Start periodic timer for neighbor discovery
        call NeighborTimer.startPeriodic(NEIGHBOR_PERIOD);
        
        // Send initial neighbor discovery
        sendNeighborDiscovery();
        
        return SUCCESS;
    }
    
    command void NeighborDiscovery.handleNeighbor(pack* message) {
        // Only process neighbor discovery packets
        if (message->protocol != PROTOCOL_NEIGHBOR_DISCOVERY) {
            return;
        }
        
        // Don't process our own packets
        if (message->src == TOS_NODE_ID) {
            return;
        }
        
        // Check if this is a new neighbor or update existing
        if (!call NeighborMap.contains(message->src)) {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Discovered new neighbor %d\n", 
                TOS_NODE_ID, message->src);
            call NeighborList.pushback(message->src);
        } else {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Updated neighbor %d timestamp\n", 
                TOS_NODE_ID, message->src);
        }
        
        // Update last seen time for this neighbor
        call NeighborMap.insert(message->src, currentTime);
    }
    
    command void NeighborDiscovery.printNeighbors() {
        uint16_t i, size;
        
        updateNeighborList();
        size = call NeighborList.size();
        
        if (size == 0) {
            dbg(NEIGHBOR_CHANNEL, "Node %d: No neighbors found\n", TOS_NODE_ID);
        } else {
            dbg(NEIGHBOR_CHANNEL, "Node %d neighbors: ", TOS_NODE_ID);
            for (i = 0; i < size; i++) {
                dbg(NEIGHBOR_CHANNEL, "%d ", call NeighborList.get(i));
            }
            dbg(NEIGHBOR_CHANNEL, "\n");
        }
    }
    
    command uint16_t* NeighborDiscovery.getNeighbors() {
        uint16_t i, size;
        
        updateNeighborList();
        size = call NeighborList.size();
        
        // Copy neighbors to static array
        for (i = 0; i < size && i < 20; i++) {
            neighborArray[i] = call NeighborList.get(i);
        }
        
        return neighborArray;
    }
    
    command uint16_t NeighborDiscovery.getNeighborListSize() {
        updateNeighborList();
        return call NeighborList.size();
    }
    
    event void NeighborTimer.fired() {
        currentTime += NEIGHBOR_PERIOD;
        
        dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor discovery timer fired at time %d\n", 
            TOS_NODE_ID, currentTime);
        
        // Check for timed-out neighbors
        updateNeighborList();
        
        // Send neighbor discovery packet
        sendNeighborDiscovery();
        
        // Print current neighbors for debugging
        call NeighborDiscovery.printNeighbors();
    }
    
}
