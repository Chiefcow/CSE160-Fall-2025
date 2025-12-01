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
#include "includes/tcp.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface CommandHandler;

   //new interfaces
   uses interface NeighborDiscovery as NeighborDiscovery;
   uses interface Flooding as Flooding;
   uses interface LinkState as LinkState;
   uses interface SimpleSend as Sender;  
   uses interface Transport;
   uses interface Timer<TMilli> as ClientWriteTimer;
}

implementation{
   pack sendPackage;
   static uint16_t seqNo = 0; //sequence  number for packets 

   // Test server/client state
   socket_t serverSocket = NULL_SOCKET;
   socket_t clientSocket = NULL_SOCKET;
   socket_t acceptedSockets[10];
   uint8_t numAcceptedSockets = 0;
   uint16_t transferAmount = 0;
   uint16_t transferredData = 0;
   uint16_t nextDataToSend = 0;
   uint8_t i;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();
      call NeighborDiscovery.start();
      call Flooding.start();   // start flooding module
      call LinkState.start();
      // Initialize accepted sockets array
      for (i = 0; i < 10; i++) {
          acceptedSockets[i] = NULL_SOCKET;
      }
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
         
         // Handle neighbor discovery packets (broadcast)
         if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
               call NeighborDiscovery.handleNeighbor(myMsg);
               return msg;
         }
         
         // Handle link state packets (broadcast)
         if (myMsg->protocol == PROTOCOL_LINKEDLIST) {
               call LinkState.handleLSP(myMsg);
               return msg;
         }

         // Check if packet is for THIS node
         if (myMsg->dest == TOS_NODE_ID) {
               // Packet reached destination - now check protocol
               
               // Handle TCP packets at destination
               if (myMsg->protocol == PROTOCOL_TCP) {
                  call Transport.receive(myMsg);
                  return msg;
               }
               
               // Handle other protocols
               dbg(GENERAL_CHANNEL, "Packet reached destination\n");
               
         } else {
               // Packet needs forwarding - route it
               uint16_t nextHop = call LinkState.getNextHop(myMsg->dest);
               
               if (nextHop != AM_BROADCAST_ADDR) {
                  dbg(ROUTING_CHANNEL, "Forwarding packet to %d via %d (protocol=%d)\n", 
                     myMsg->dest, nextHop, myMsg->protocol);
                  call Sender.send(*myMsg, nextHop);
               } else {
                  dbg(ROUTING_CHANNEL, "No route to %d, using flooding\n", myMsg->dest);
                  call Flooding.handle_flooding(myMsg);
               }
         }
      }
      return msg;
      // if (len == sizeof(pack)) {
      //   pack* myMsg = (pack*) payload;
        
      //   // Handle neighbor discovery packets
      //   if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
      //       call NeighborDiscovery.handleNeighbor(myMsg);
      //       return msg;
      //   }
      //   // Handle link state packets
      //    if (myMsg->protocol == PROTOCOL_LINKEDLIST) {
      //       call LinkState.handleLSP(myMsg);
      //       return msg;
      //    }

      //    // Handle TCP packets
      //   if (myMsg->protocol == PROTOCOL_TCP) {
      //       call Transport.receive(myMsg);
      //       return msg;
      //   }
         
      //    // Handle regular packets with routing
      //    if (myMsg->dest == TOS_NODE_ID) {
      //       dbg(GENERAL_CHANNEL, "Packet reached destination\n");
      //    } else {
      //       uint16_t nextHop = call LinkState.getNextHop(myMsg->dest);
      //       if (nextHop != AM_BROADCAST_ADDR) {
      //          dbg(ROUTING_CHANNEL, "Forwarding to %d via %d\n", 
      //              myMsg->dest, nextHop);
      //          call Sender.send(*myMsg, nextHop);
      //       } else {
      //          call Flooding.handle_flooding(myMsg);
      //       }
      //    }
      // }
      // return msg;
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

   event void CommandHandler.setTestServer(){
      socket_addr_t addr;
      socket_t newSocket;
      uint8_t i;
      uint8_t buffer[128];
      uint16_t bytesRead;
      uint16_t j;
      
      // Only handle this event on the correct node
      // The parameters are passed via the command system
      // For now, we'll set up a server on port 80
      
      if (serverSocket == NULL_SOCKET) {
          // Create socket
          serverSocket = call Transport.socket();
          
          if (serverSocket != NULL_SOCKET) {
              // Bind to port 80
              addr.port = 80;
              addr.addr = TOS_NODE_ID;
              
              if (call Transport.bind(serverSocket, &addr) == SUCCESS) {
                  // Start listening
                  if (call Transport.listen(serverSocket) == SUCCESS) {
                      dbg(TRANSPORT_CHANNEL, 
                          "Debug(1): Server started on node %d, port 80\n", 
                          TOS_NODE_ID);
                  }
              }
          }
      }
      
      // Try to accept new connections
      newSocket = call Transport.accept(serverSocket);
      if (newSocket != NULL_SOCKET && numAcceptedSockets < 10) {
          acceptedSockets[numAcceptedSockets++] = newSocket;
          dbg(TRANSPORT_CHANNEL, 
              "Debug(1): Accepted new connection (socket %d)\n", 
              newSocket);
      }
      
      // Read data from all accepted sockets and print
      for (i = 0; i < numAcceptedSockets; i++) {
          if (acceptedSockets[i] != NULL_SOCKET) {
              bytesRead = call Transport.read(acceptedSockets[i], buffer, 128);
              
              if (bytesRead > 0) {
                  // Print received data
                  dbg(TRANSPORT_CHANNEL, "Received data: ");
                  for (j = 0; j < bytesRead; j += 2) {
                      uint16_t value = buffer[j] | (buffer[j+1] << 8);
                      dbg_clear(TRANSPORT_CHANNEL, "%d ", value);
                  }
                  dbg_clear(TRANSPORT_CHANNEL, "\n");
              }
          }
      }

   }

   event void CommandHandler.setTestClient(){
      socket_addr_t localAddr, serverAddr;
      
      // This is called to initiate the client
      // Parameters would normally come from the command parser
      // For demonstration, we'll use: dest=1, srcPort=41, destPort=80, transfer=20
      
      if (clientSocket == NULL_SOCKET) {
          // Create socket
          clientSocket = call Transport.socket();
          
          if (clientSocket != NULL_SOCKET) {
              // Bind to local port
              localAddr.port = 41;
              localAddr.addr = TOS_NODE_ID;
              
              if (call Transport.bind(clientSocket, &localAddr) == SUCCESS) {
                  // Connect to server
                  serverAddr.port = 80;
                  serverAddr.addr = 1;  // Server node
                  
                  if (call Transport.connect(clientSocket, &serverAddr) == SUCCESS) {
                      // Set transfer parameters
                      transferAmount = 20;  // Send 20 bytes (10 uint16_t values)
                      transferredData = 0;
                      nextDataToSend = 0;
                      
                      // Start write timer
                      call ClientWriteTimer.startPeriodic(CLIENT_WRITE_TIMER);
                      
                      dbg(TRANSPORT_CHANNEL, 
                          "Debug(1): Client connecting to node 1, port 80\n");
                  }
              }
          }
      }

   }

   event void ClientWriteTimer.fired() {
      uint8_t buffer[20];
      uint16_t bytesToWrite;
      uint16_t written;
      uint16_t i;
      
      if (clientSocket != NULL_SOCKET && transferredData < transferAmount) {
          // Prepare data: 16-bit unsigned integers from 0 to transfer amount
          bytesToWrite = (transferAmount - transferredData > 10) ? 10 : (transferAmount - transferredData);
          
          // Pack data as uint16_t values
          for (i = 0; i < bytesToWrite; i += 2) {
              buffer[i] = nextDataToSend & 0xFF;
              buffer[i+1] = (nextDataToSend >> 8) & 0xFF;
              nextDataToSend++;
          }
          
          // Write to socket
          written = call Transport.write(clientSocket, buffer, bytesToWrite);
          transferredData += written;
          
          dbg(TRANSPORT_CHANNEL, 
              "Debug(1): Client wrote %d bytes (total: %d/%d)\n",
              written, transferredData, transferAmount);
          
          // Stop timer when done
          if (transferredData >= transferAmount) {
              call ClientWriteTimer.stop();
              dbg(TRANSPORT_CHANNEL, 
                  "Debug(1): Client finished sending all data\n");
          }
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
