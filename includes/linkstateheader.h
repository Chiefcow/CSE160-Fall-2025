//Header guards
#ifndef LINKSTATEHEADER_H
#define LINKSTATEHEADER_H

//Defined constants usded for link state
#define MAX_NODES 20 //nodes in network
#define MAX_NEIGHBORS 5 //max neighbor count for a lsr packet
#define LSP_TIMEOUT 50000
#define LSP_PERIOD 30000
#define INFINITY 999

//Defining structs used for LS Routing

//nx_struct is used in TinyOS to define an object being sent over the network
typedef nx_struct linkstate_packet {
    //For memory constraints we use an unsigned int of 16bits for portablility
    nx_uint16_t node_id;
    nx_unint16_t seq_num;
    //We dont expect a large neighbor count thus specify an 8bit int
    nx_unint8_t neighbor_count;
    nx_uint16_t neighbors[MAX_NEIGHBORS] //define our neighbor array
} linkstate_packet; //the link-state packet is unique as it is specifically used later in our implmentation of the routing procedure

//Use another struct for a general container of information needed for our Routing procedure
typedef struct routing_entry {
    unint16_t destination;
    unint16_t next_hop;
    unint16_t cost;
} routing_entry;


#endif