#include "../../includes/packet.h"

interface NeighborDiscovery {
   command error_t start();

   //Identify nodes
   command neighborPing(pack* pkt_info);
   //Account for dropped nodes here
   //task handleNeighbor();
}


//reminder --> events are typically call backs invoked by lower lay components
//No sense here since we are at the low level


/*
Project 1:
Right now a node can directly communicate with another 

///thoughts scratchpad

Idea:
Upon start send a neigborPing.  Idea is to use in conjunction w/ flooding to account for all nodes.
Think about using a list here to account for Nodes in the Network --> Given in DS
Also consider using a hashmap to easily select Nodes once identified.
Bigger Picture:
   When flooding is started NbD takes the packet information that is
   A) sent via flooding and used to identify nodes in the network.
   As the packet is passed through the network, the sequence number should increment
   For each UNIQUE incremented seq; it represents a new Node that has seen the packet.
      1) --> In a case where we see the same sequences number while the network is running; disregard and don't add to list.  No need for dup Nodes
   B) For each unique seq, we add it to our underlying list to keep track of and store all relevant Nodes.
   C) Then use a Timer to send periodically re-send a Flooded Neighbor Discovery Packet --> Make use of the flooding module for the flooding packet 
      2) --> Possibly consider a wrapper? Could also.... 
         .. Fix floooding so that it is modularized; once we have this we can transition to this stage
         The idea:
            With a unique Flooding packet we may wrap a NbD Ping service ontop of that packet; thus supporting Encapsulation  Less packets sent = less congestion in the network.
   D) @Consideration!
      If a Node happens to get dropped:
       This is where step C works.  However with an extra step
       ----
       @Reference: Assuming the first flooded packet accounts for all ACTIVE NODES within the network.  Each unqiue seq is added to the list
      From here we may use another flooded packet and compare the existing seq numbers in list.
      This handles a dropped Node --> If a sequence number does not exist, or is removed, we may assume that particular Node has been dropped
   E)  We may incorporate the hash map to quickly index and remove a particular Node from our current Neighbor List should it get dropped
      @Implementation:
         Key --> Node Id
         T --> Pass packet with Seq

   Another possible consideration; 
   Creating a Node Id variable to store the sequence number.


     

   Starting from the first node, we examine the sequence number.  For each unique
   sequence number, we then pass it to handle Neigbor where it is then added to our list.


When neighborPing is invoked, a packet is passed through
With the packet

Another consideration:
We can make use of the makePack Function to create unique NbD
packets.  These packets will be used to send the  Pings
void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

Design Choice:
1. Have neighborPing run indef in the background to account for dropped Nodes
2. Make use of Timer to fire neighborPing periodically while the network is up


This allows to

My approach to effectively handle dropped Nodes:
Could we use the same packet from Flooding to support NbD?
1. Flood the network | Concurrently send a NbD packet....or Ping {Design Choice here}
2. At each hop analyze the sequence number for unique nodes
   This should support cases where a Node is dropped:
      How would we achieve this?


*/

