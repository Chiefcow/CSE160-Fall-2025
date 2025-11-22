/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/channels.h"
#include "includes/linkstate.h"
#include "includes/socket.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface CommandHandler;

   //new interfaces
   uses interface NeighborDiscovery as NeighborDiscovery;
   uses interface Flooding as Flooding;
   uses interface LinkState as LinkState;
   uses interface SimpleSend as Sender;  // Add this for sending packets
   uses interface Transport;
   uses interface Timer<TMilli> as TestTimer;
}

implementation{
   pack sendPackage;
   static uint16_t seqNo = 0; //sequence  number for packets 

   //proj 3
   socket_t mySocket = NULL;
   bool isServer = FALSE;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();
      call NeighborDiscovery.start();
      call Flooding.start();   // start flooding module
      call LinkState.start();
    dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if (len == sizeof(pack)) {
        pack* myMsg = (pack*) payload;

        // Handle neighbor discovery packets
        if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
            call NeighborDiscovery.handleNeighbor(myMsg);
            return msg;
        }

         //proj 3
        if (myMsg->protocol == PROTOCOL_TCP) {
            call Transport.receive(myMsg);
            return msg;
         }

        // Handle link state packets
         if (myMsg->protocol == PROTOCOL_LINKEDLIST) {
            call LinkState.handleLSP(myMsg);
            return msg;
         }
         
         // Handle regular packets with routing
         if (myMsg->dest == TOS_NODE_ID) {
            dbg(GENERAL_CHANNEL, "Packet reached destination\n");
         } else {
            uint16_t nextHop = call LinkState.getNextHop(myMsg->dest);
            if (nextHop != AM_BROADCAST_ADDR) {
               dbg(ROUTING_CHANNEL, "Forwarding to %d via %d\n", 
                   myMsg->dest, nextHop);
               call Sender.send(*myMsg, nextHop);
            } else {
               call Flooding.handle_flooding(myMsg);
            }
         }
      }
      return msg;
      //   ++seqNo;
        // Handle regular packets with flooding
   //      dbg(GENERAL_CHANNEL, "Node %d received packet src=%d dest=%d seq=%d\n", 
   //          TOS_NODE_ID, myMsg->src, myMsg->dest, myMsg->seq);
   //      call Flooding.handle_flooding(myMsg);
   //  }
   //  return msg;
   //    if (len == sizeof(pack)) {
   //      pack* myMsg = (pack*) payload;
   //      dbg(GENERAL_CHANNEL, "Node %d recived packet ssrc=%d dest=%d seq=%d\n", TOS_NODE_ID, myMsg->src,myMsg->dest,myMsg->seq);
   //      call Flooding.handle_flooding(myMsg);
   //  }
   //  return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 5 /* Time to live - Elvis*/, 0, seqNo++, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Flooding.handle_flooding(&sendPackage);
   }

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
       call LinkState.printRoutingTable();
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(uint8_t port){
      socket_addr_t addr;
      
      mySocket = call Transport.socket();
      if (mySocket == NULL) return;
      
      addr.port = port;
      addr.addr = TOS_NODE_ID;
      
      call Transport.bind(mySocket, &addr);
      call Transport.listen(mySocket);
      
      isServer = TRUE;
      dbg(TRANSPORT_CHANNEL, "Node %d: Server listening on port %d\n", 
         TOS_NODE_ID, port);
      }
   // event void CommandHandler.setTestServer(){}

   // event void CommandHandler.setTestClient(){}
   event void CommandHandler.setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer){
      socket_addr_t local, remote;
      
      mySocket = call Transport.socket();
      if (mySocket == NULL) return;
      
      local.port = srcPort;
      local.addr = TOS_NODE_ID;
      call Transport.bind(mySocket, &local);
      
      remote.port = destPort;
      remote.addr = dest;
      call Transport.connect(mySocket, &remote);
      
      isServer = FALSE;
      dbg(TRANSPORT_CHANNEL, "Node %d: Client connecting to %d:%d\n", 
         TOS_NODE_ID, dest, destPort);
      
      // Send data after 3 seconds
      call TestTimer.startOneShot(3000);
      }

   event void CommandHandler.clientClose(uint16_t dest, uint8_t srcPort, uint8_t destPort){
      if (mySocket != NULL) {
         call Transport.close(mySocket);
         mySocket = NULL;
      }
   }

   event void TestTimer.fired(){
      uint8_t testData[10];
      uint8_t i;
      
      if (!isServer && mySocket != NULL) {
         for (i = 0; i < 10; i++) {
               testData[i] = i;
         }
         call Transport.write(mySocket, testData, 10);
      }
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
