/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 */

#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/socket.h"
#include "includes/tcp.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"

module Node{
   uses interface Boot;
   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
   uses interface NeighborDiscovery;
   uses interface Flooding as Flooding;
   uses interface LinkState as LinkState;
   uses interface Transport;
   uses interface Timer<TMilli> as AcceptTimer;      // Server accept timer
   uses interface Timer<TMilli> as ClientWriteTimer; // Client write timer
}

implementation{
   pack sendPackage;
   uint16_t seqNo = 0;
   
   // Server state
   socket_t serverFd;
   socket_t acceptedSockets[10];
   uint8_t numAcceptedSockets = 0;
   bool isServerRunning = FALSE;
   
   // Client state
   socket_t clientFd;
   uint16_t transferAmount = 0;
   uint16_t transferCounter = 0;
   bool isClientRunning = FALSE;
   
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   /**
    * cmdTestServer - server implementation
    */
   void cmdTestServer(uint8_t port){
      socket_addr_t addr;
      uint8_t i;
      
      for (i = 0; i < 10; i++) {
         acceptedSockets[i] = 0;
      }
      numAcceptedSockets = 0;
      
      addr.port = port; 
      addr.addr = TOS_NODE_ID;
      
      call Transport.start(); 
      serverFd = call Transport.socket();
      call Transport.bind(serverFd, &addr);
      call Transport.listen(serverFd);
      
      isServerRunning = TRUE;
      
      dbg("Project3TGen", "Server started on node %d, port %d\n", TOS_NODE_ID, port);
      
      call AcceptTimer.startPeriodic(1000);
   }

   /**
    * cmdTestClient - client implementation
    */
   void cmdTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer){
      socket_addr_t src, dst;
      
      transferAmount = transfer;
      transferCounter = 0;
      
      call Transport.start();
      clientFd = call Transport.socket();

      src.port = srcPort;
      src.addr = TOS_NODE_ID;
      call Transport.bind(clientFd, &src);

      dst.port = destPort;
      dst.addr = dest;
      
      isClientRunning = TRUE;
      
      dbg("Project3TGen", "Client connecting to node %d, port %d\n", dest, destPort);
      call Transport.connect(clientFd, &dst);
   }

   /**
    * CommandHandler events - MUST MATCH INTERFACE EXACTLY
    */
   event void CommandHandler.setTestServer() {
      cmdTestServer(80);  
   }

event void CommandHandler.setTestClient() {
   cmdTestClient(1, 41, 80, 100); 
}

   // event void CommandHandler.setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer) {
   //    cmdTestClient(dest, srcPort, destPort, transfer);
   // }

   event void CommandHandler.setAppServer(){}
   event void CommandHandler.setAppClient(){}

   /**
    * Connection established - start writing data
    */
   event void Transport.connectDone(socket_t fd){
      dbg("Project3TGen", "Debug(%d): Connection established to server\n", TOS_NODE_ID);
      call ClientWriteTimer.startPeriodic(500);
   }

   /**
    * Server timer - periodically accept and read
    */
   event void AcceptTimer.fired() {
      uint8_t i;
      uint8_t buffer[256];
      uint16_t bytesRead;
      uint16_t j;
      uint16_t* dataPtr;
      socket_t newFd;
      
      if (!isServerRunning) return;
      
      // Try to accept new connections
      newFd = call Transport.accept(serverFd);
      if (newFd != 0) {
         dbg("Project3TGen", "Debug(%d): Connection accepted on socket %d\n", TOS_NODE_ID, newFd);
         if (numAcceptedSockets < 10) {
            acceptedSockets[numAcceptedSockets] = newFd;
            numAcceptedSockets++;
         }
      }
      
      // Read from all accepted sockets
      for (i = 0; i < numAcceptedSockets; i++) {
         if (acceptedSockets[i] != 0) {
            bytesRead = call Transport.read(acceptedSockets[i], buffer, 256);
            
            if (bytesRead > 0) {
               dbg("Project3TGen", "Debug(%d): Data received: ", TOS_NODE_ID);
               
               dataPtr = (uint16_t*)buffer;
               
               for (j = 0; j < bytesRead / 2; j++) {
                  dbg_clear("Project3TGen", "%u", dataPtr[j]);
                  if (j < (bytesRead / 2) - 1) {
                     dbg_clear("Project3TGen", ",");
                  }
               }
               dbg_clear("Project3TGen", "\n");
            }
         }
      }
   }

   /**
    * Client timer - periodically write data
    */
   event void ClientWriteTimer.fired() {
      uint16_t buffer[64];
      uint8_t i;
      uint8_t count;
      uint16_t bytesWritten;
      
      if (!isClientRunning) return;
      
      count = 0;
      
      if (transferCounter >= transferAmount) {
         call ClientWriteTimer.stop();
         dbg("Project3TGen", "Debug(%d): Transfer complete, closing connection\n", TOS_NODE_ID);
         call Transport.close(clientFd);
         isClientRunning = FALSE;
         return;
      }
      
      for (i = 0; i < 64 && transferCounter < transferAmount; i++) {
         buffer[i] = transferCounter;
         transferCounter++;
         count++;
      }
      
      if (count > 0) {
         bytesWritten = call Transport.send(clientFd, (uint8_t*)buffer, count * 2);
         
         if (bytesWritten > 0) {
            dbg("Project3TGen", "Debug(%d): Sent %u bytes (%u-%u)\n", 
                TOS_NODE_ID, bytesWritten, transferCounter - count, transferCounter - 1);
         }
      }
   }

   event void Boot.booted(){
      call AMControl.start();
      dbg("general", "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg("general", "Radio On\n");
         call NeighborDiscovery.start();
         call LinkState.start();
      }else{
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      pack* myMsg = (pack*) payload;
      uint16_t nextHop;
      tcp_pack* tcp;
      
      if (len != sizeof(pack)) return msg;

      if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
         call NeighborDiscovery.handleNeighbor(myMsg);
         return msg;
      }
      if (myMsg->protocol == PROTOCOL_LINKEDLIST) {
         call LinkState.handleLSP(myMsg);
         return msg;
      }

      if (myMsg->dest == TOS_NODE_ID) {
         if (myMsg->protocol == PROTOCOL_TCP){
            tcp = (tcp_pack*)myMsg->payload;
            
            if (tcp->flags == TCP_SYN) {
               dbg("Project3TGen", "Debug(%d): SYN Packet Arrived from Node %d for Port %d\n",
                   TOS_NODE_ID, myMsg->src, tcp->destPort);
            } else if (tcp->flags == (TCP_SYN | TCP_ACK)) {
               dbg("Project3TGen", "Debug(%d): SYN+ACK Packet Arrived from Node %d\n",
                   TOS_NODE_ID, myMsg->src);
            } else if (tcp->flags == TCP_FIN) {
               dbg("Project3TGen", "Debug(%d): FIN Packet Arrived from Node %d\n",
                   TOS_NODE_ID, myMsg->src);
            }
            
            call Transport.receive(myMsg);
         } else {
            dbg("general", "Packet reached destination\n");
         }
         return msg;
      } else {
         nextHop = call LinkState.getNextHop(myMsg->dest);
         
         if (nextHop != AM_BROADCAST_ADDR) {
            dbg("routing", "Forwarding packet to %d via %d\n", myMsg->dest, nextHop);
            call Sender.send(*myMsg, nextHop);
         } else {
            call Flooding.handle_flooding(myMsg);
         }
      }
      return msg;
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg("general", "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 5, 0, seqNo++, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
      // Just call dbg - the actual table is managed by LinkState
      dbg("general", "Route table requested\n");
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
