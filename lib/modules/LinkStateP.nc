#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/linkstate.h"

module LinkStateP {
    provides interface LinkState;
    
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as LSPTimer;
    uses interface Hashmap<linkstate_packet> as LSPCache;
    uses interface Hashmap<routing_entry> as RoutingTable;
    uses interface List<uint16_t> as Unvisited;
    
    uses interface NeighborDiscovery;
    uses interface Flooding;
}

implementation {
    uint16_t lsp_sequence = 0;
    uint16_t distance[MAX_NODES];
    uint16_t previous[MAX_NODES];
    bool visited[MAX_NODES];

    //Skeleton
    void calculateRoutingTable();
    void broadcastLSP();
    
    // Initialize link state module
    command error_t LinkState.start() {
        dbg(ROUTING_CHANNEL, "Node %d: Starting Link State module\n", TOS_NODE_ID);
        
        // Start periodic LSP broadcasts
        call LSPTimer.startPeriodic(LSP_PERIOD);
        
        // Send initial LSP
        call LinkState.triggerLSPUpdate();
        
        return SUCCESS;
    }
    
    // Create and broadcast Link State Packet
    void broadcastLSP() {
        pack lsp_packet;
        //
        linkstate_packet lsp_data;
        // Contents defined in our header file of which we would make use of
        uint16_t* neighbors;
        uint16_t neighbor_count;

        uint16_t i;
        
        // Get current neighbors
        neighbors = call NeighborDiscovery.getNeighbors();
        neighbor_count = call NeighborDiscovery.getNeighborListSize();
        
        // Use the information provided by neighbor discovery for our lsp packet
        lsp_data.node_id = TOS_NODE_ID;
        lsp_data.seq_num = ++lsp_sequence;
        lsp_data.neighbor_count = neighbor_count;
        
        // Copy neighbors provided by Neighbor discovery into our list provided by the header struct
        for (i = 0; i < neighbor_count && i < MAX_NEIGHBORS; i++) {
            lsp_data.neighbors[i] = neighbors[i];
        }
        
        // Create packet
        lsp_packet.src = TOS_NODE_ID;
        lsp_packet.dest = AM_BROADCAST_ADDR;
        lsp_packet.TTL = MAX_TTL;
        lsp_packet.seq = lsp_data.seq_num;
        lsp_packet.protocol = PROTOCOL_LINKEDLIST;
        //Copying the contents of the packet
        memcpy(lsp_packet.payload, &lsp_data, sizeof(linkstate_packet));
        
        dbg(ROUTING_CHANNEL, "Node %d: Broadcasting LSP with %d neighbors\n", 
            TOS_NODE_ID, neighbor_count);
        
        // Start inserting items into our hash | Store own LSP
        call LSPCache.insert(TOS_NODE_ID, lsp_data);
        
        // Use flooding to distribute the Link state packet 
        call Flooding.handle_flooding(&lsp_packet);
    }
    
    // Handle incoming LSP | updates tables
    command void LinkState.handleLSP(pack* message) {
        linkstate_packet* lsp_data;
        linkstate_packet cached_lsp;
        
        if (message->protocol != PROTOCOL_LINKEDLIST) {
            return;
        }
        
        lsp_data = (linkstate_packet*) message->payload;
        
        // Check if we have this LSP already
        if (call LSPCache.contains(lsp_data->node_id)) {
            cached_lsp = call LSPCache.get(lsp_data->node_id);
            
            // Only process if newer sequence number
            if (cached_lsp.seq_num >= lsp_data->seq_num) {
                dbg(ROUTING_CHANNEL, "Node %d: Ignoring old LSP from %d\n", 
                    TOS_NODE_ID, lsp_data->node_id);
                return;
            }
        }
        
        dbg(ROUTING_CHANNEL, "Node %d: Received new LSP from %d with %d neighbors\n", 
            TOS_NODE_ID, lsp_data->node_id, lsp_data->neighbor_count);
        
        // Store the LSP
        call LSPCache.insert(lsp_data->node_id, *lsp_data);
        
        // Recalculate routing table
        calculateRoutingTable();
        
        // Use flooding to dirstribute the LSP packet
        call Flooding.handle_flooding(message);
    }
    
    // Dijkstra's algorithm implementation
    void calculateRoutingTable() {
        uint16_t i, j, u, v;
        uint16_t min_distance;
        uint16_t min_node;
        uint32_t* lsp_keys;
        uint16_t lsp_count;
        linkstate_packet current_lsp;
        routing_entry route;
        
        dbg(ROUTING_CHANNEL, "Node %d: ==================Calculating routing table=================\n", TOS_NODE_ID);
        
        // initialize our distances and previous node with i - Max_Nodes ; which is 20-> Max nodes in network
        for (i = 0; i < MAX_NODES; i++) {
            distance[i] = MAX_COST;
            previous[i] = MAX_COST;
            //Currently set everything to false as nothing as been visted yet
            visited[i] = FALSE;
        }
        
        // cost or distances from init node is 0
        distance[TOS_NODE_ID] = 0;
        //Previous node
        previous[TOS_NODE_ID] = TOS_NODE_ID;  
        
        // Get all nodes we know about --> LSPCache refers to a hash with neigbors popullated by our neighbor discovery module
        lsp_keys = call LSPCache.getKeys();

        // Defined eariler as 16bit unsigned int; set its value to the size our current neigbor list size; means how many neighbors we have
        lsp_count = call LSPCache.size();
        
        // Run Dijkstra's algorithm
        for (i = 0; i < lsp_count; i++) {
            // place holder variables set to Max_Cost --> Being 20, which represents 20 hops
            min_distance = MAX_COST;
            min_node = MAX_COST;
            
            // Loop to go through nodes and thier given cost
            for (j = 0; j < lsp_count; j++) {
                // Set u equal to a particular index of our hashed neibor map; continue updwards until we hit the size of the neighbor list
                u = lsp_keys[j];
                // Updated if the node hase been vistied with a better cost
                if (!visited[u] && distance[u] < min_distance) {
                    min_distance = distance[u];
                    min_node = u;
                }
            }
            
            if (min_node == MAX_COST) break;
            
            u = min_node;
            // Set u to True as we have just completed the logic to vist
            visited[u] = TRUE;
            
            // Get LSP for this node
            if (!call LSPCache.contains(u)) continue;
            current_lsp = call LSPCache.get(u);
            
            // Update distances to neighbors
            for (j = 0; j < current_lsp.neighbor_count; j++) {
                v = current_lsp.neighbors[j];
                
                // Check if shorter path exists
                if (distance[u] + 1 < distance[v]) {
                    distance[v] = distance[u] + 1;
                    previous[v] = u;
                }
            }
        }
        
        // Build routing table from results
        for (i = 0; i < lsp_count; i++) {
            u = lsp_keys[i];
            if (u == TOS_NODE_ID) continue;
            
            // Find next hop by tracing back to source
            v = u;
            while (previous[v] != TOS_NODE_ID && previous[v] != MAX_COST) {
                v = previous[v];
            }
            
            if (previous[v] == TOS_NODE_ID) {
                // v is the next hop to reach u
                route.destination = u;
                route.next_hop = v;
                route.cost = distance[u];
                
                call RoutingTable.insert(u, route);
                
                dbg(ROUTING_CHANNEL, "Node %d: Route to %d via %d (cost %d)\n", 
                    TOS_NODE_ID, u, v, distance[u]);
            }
        } //end of dijstra
    }
    
    // Get next hop for destination
    command uint16_t LinkState.getNextHop(uint16_t dest) {
        routing_entry route;
        
        if (dest == TOS_NODE_ID) {
            return TOS_NODE_ID;
        }
        
        if (call RoutingTable.contains(dest)) {
            route = call RoutingTable.get(dest);
            return route.next_hop;
        }
        
        return AM_BROADCAST_ADDR; // Fallback to flooding
    }
    
    // Print routing table
    command void LinkState.printRoutingTable() {
        uint32_t* keys;
        uint16_t size, i;
        routing_entry route;
        
        dbg(ROUTING_CHANNEL, "Node %d Routing Table:\n", TOS_NODE_ID);
        dbg(ROUTING_CHANNEL, "Dest\tNext\tCost\n");
        
        keys = call RoutingTable.getKeys();
        size = call RoutingTable.size();
        
        for (i = 0; i < size; i++) {
            route = call RoutingTable.get(keys[i]);
            dbg(ROUTING_CHANNEL, "%d\t%d\t%d\n", 
                route.destination, route.next_hop, route.cost);
        }
    }
    
    // Manually trigger LSP update
    command void LinkState.triggerLSPUpdate() {
        broadcastLSP();
    }
    
    // Timer event for periodic LSP broadcasts
    event void LSPTimer.fired() {
        dbg(ROUTING_CHANNEL, "Node %d: LSP Timer fired\n", TOS_NODE_ID);
        broadcastLSP();
    }
}