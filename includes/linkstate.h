#ifndef LINKSTATE_H
#define LINKSTATE_H

#define MAX_NODES 20
#define MAX_NEIGHBORS 10
#define LSP_TIMEOUT 50000
#define LSP_PERIOD 30000
#define MAX_COST 999  // Changed from INFINITY to avoid conflict

typedef nx_struct linkstate_packet {
    nx_uint16_t node_id;
    nx_uint16_t seq_num;
    nx_uint8_t neighbor_count;
    nx_uint16_t neighbors[MAX_NEIGHBORS];
} linkstate_packet;

typedef struct routing_entry {
    uint16_t destination;
    uint16_t next_hop;
    uint16_t cost;
} routing_entry;

#endif