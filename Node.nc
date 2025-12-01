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
   
   uses interface NeighborDiscovery as NeighborDiscovery;
   uses interface Flooding as Flooding;
   uses interface LinkState as LinkState;
   uses interface SimpleSend as Sender;
   uses interface Transport;
}

implementation{
   pack sendPackage;
   socket_t clientFd;
   socket_t serverFd;
   
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // CMD_TEST_SERVER
   void cmdTestServer(uint8_t port){
      socket_addr_t addr;
      addr.port = port; 
      addr.addr = TOS_NODE_ID;
      call Transport.start(); 
      serverFd = call Transport.socket();
      call Transport.bind(serverFd, &addr);
      call Transport.listen(serverFd);
      dbg("transport", "Node %d Listening on port %d\n", TOS_NODE_ID, port);
   }

   // CMD_TEST_CLIENT
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
   }

   // CMD_CLOSE
   void cmdClientClose(){
      call Transport.close(clientFd);
   }

   //event void CommandHandler.handleCommand(uint8_t *payload) {
      // Cast payload to CommandMsg to access fields if needed, 
      // but CommandHandler usually gives specific args. 
      // Use the 'payload' buffer directly based on your specific command structure.
      
      // NOTE: Your CommandHandler implementation passes a pointer to the payload bytes
      // Check CommandHandlerP.nc to see what it sends.
      // Assuming payload[0] is the first byte of data...
      
      // However, your CommandHandler interface definition has specific events:
      // setTestClient(), setTestServer(). 
      // You should implement those events instead of handleCommand if possible, 
      // OR if you modified CommandHandler to pass raw commands:

      // Since handleCommand isn't in standard CommandHandler interface provided, 
      // I will assume you meant to implement the specific events below:
   //}

   // Implement the events from CommandHandler interface:
   event void CommandHandler.setTestServer() {
      // Hardcoded test or read from a global buffer if you implemented that
      cmdTestServer(80); 
   }

   event void CommandHandler.setTestClient() {
      // Hardcoded test
      cmdTestClient(1, 41, 80, 100);
   }

   event void CommandHandler.setAppServer(){}
   event void CommandHandler.setAppClient(){}

   event void Transport.connectDone(socket_t fd){
      dbg("transport", "client connected. Sending Data...\n");
      // Add logic to send data here
   }

   event error_t Transport.accept(socket_t fd) {
      dbg("transport", "server Accepted Connection. \n");
      return SUCCESS;
   }

   // Sequence number
   static uint16_t seqNo = 0;

   event void Boot.booted(){
      call AMControl.start();
      call NeighborDiscovery.start();
      call Flooding.start();
      call LinkState.start();
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      pack* myMsg = (pack*) payload;
      
      if (len != sizeof(pack)) return msg;

      // 1. Handle Routing Control Packets
      if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
         call NeighborDiscovery.handleNeighbor(myMsg);
         return msg;
      }
      if (myMsg->protocol == PROTOCOL_LINKEDLIST) {
         call LinkState.handleLSP(myMsg);
         return msg;
      }

      // 2. Handle Data Packets (TCP, PING, etc.)
      if (myMsg->dest == TOS_NODE_ID) {
         // Packet is FOR ME -> Process it
         if (myMsg->protocol == PROTOCOL_TCP){
            call Transport.receive(myMsg);
         } else {
            dbg(GENERAL_CHANNEL, "Packet reached destination\n");
         }
         return msg;
      } else {
         // Packet is FOR SOMEONE ELSE -> Forward it
         uint16_t nextHop = call LinkState.getNextHop(myMsg->dest);
         
         if (nextHop != AM_BROADCAST_ADDR) {
            dbg(ROUTING_CHANNEL, "Forwarding packet to %d via %d\n", myMsg->dest, nextHop);
            call Sender.send(*myMsg, nextHop);
         } else {
            // No route found? Flood it.
            call Flooding.handle_flooding(myMsg);
         }
      }
      return msg;
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 5, 0, seqNo++, payload, PACKET_MAX_PAYLOAD_SIZE);
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

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}