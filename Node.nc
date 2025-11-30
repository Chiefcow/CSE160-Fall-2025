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
   //Project 3
   uses interface Transport;
}

implementation{
   pack sendPackage;
   //Logic for project 3
   //*********************************************************************************
   socket_t clientFd;
   socket_t serverFd;

   //CMD_TEST_SERVER
   void cmdTestServer(uint8_t port){
      socket_addr_t addr;
      addr.port = port; 
      addr.addr = TOS_NODE_ID;

      call Transport.start(); //make sure the timer starts
      serverFd = call Transport.socket();
      call Transport.bind(serverFd, &addr);
      call Transport.listen(serverFd);
      dbg("transport", "Node %d Listening on port %d\n", TOS_NODE_ID, port);

   }

   //CDM_TEST_CLIENT
   void cmdTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer){
      socket_addr_t src, dst;

      call Transport.start();
      clientFd = call Transport.socket();

      src.port = srcPort;
      src.addr = TOS_NODE_ID;
      call Transport.bind(clientFd, &src);

      dst.port = destPort;
      dst.addr = dest;
      call Transport.connect(clientFd, &dst);

      //Store our transfer quantity on a global variable 

   }

   //CDM_CLOSE
   void cmdClientClose(){
      call Transport.close(clientFd)
   }

   event void CommandHandler.handleCommand(unit8_t *payload) {
      if (msg->id == CDM_TEST_CLIENT){
         uint16_t dest = payload[0] | (payload[1] <<8);
      }

      if (msg ->id == CMD_TEST_SERVER){
         //call cmdTestserver
      }

   }

   event void Transport.connectDone(socket_t fd){
      dbg("transport", "client connected. Sending Data...\n");

   }

   event error_t Transport.accept(socket_t fd) {
      dbg("transport", "server Accepted Connection. \n");
      return SUCCESS;
   }

   //IMPORTANT: Hook Transport.recive into the main recive loop
   //check below for logic


   //**********************************************************************************
   static uint16_t seqNo = 0; //sequence  number for packets 
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
      //Project 3 Project Hook Transportation

      pack* myMsg = (pack*) payload;

      if (myMsg ->protocol == PROTOCOL_TCP){
         call Transport.recive(myMsg);
         return msg;
      }

      //********************************************************
      if (len == sizeof(pack)) {
        pack* myMsg = (pack*) payload;
        
        // Handle neighbor discovery packets
        if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
            call NeighborDiscovery.handleNeighbor(myMsg);
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

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

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
