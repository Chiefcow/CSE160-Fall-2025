#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/channels.h"
#include "includes/linkstate.h"
#include "includes/socket.h"
#include "includes/chat.h"

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
   uses interface Chat;
   
   // Timer for sending data in chunks
   uses interface Timer<TMilli> as ClientWriteTimer;
   uses interface Timer<TMilli> as ChatMsgTimer;
}

implementation{
   pack sendPackage;
   socket_t clientFd;
   socket_t serverFd;
   
   // Client transfer state
   uint16_t transfer_amount = 0;
   uint16_t bytes_sent = 0;
   uint8_t dataBuffer[256];
   bool transfer_in_progress = FALSE;
   
   // Chat message queue for testing
   char pendingMsg[32];
   bool hasPendingMsg = FALSE;
   
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
      uint16_t i;
      
      transfer_amount = transfer;
      bytes_sent = 0;
      transfer_in_progress = FALSE;

      for(i = 0; i < transfer_amount && i < 256; i++){
          dataBuffer[i] = (i + 1) & 0xFF;
      }

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

   event void CommandHandler.setTestServer() {
      cmdTestServer(80); 
   }

   event void CommandHandler.setTestClient() {
      cmdTestClient(1, 41, 80, 300);
   }

   // Project 4 - Chat Commands
   event void CommandHandler.setAppServer(){
      dbg("transport", "Starting Chat Server on node %d\n", TOS_NODE_ID);
      call Chat.startServer();
   }
   
   event void CommandHandler.setAppClient(){
      // Default client setup - this will be overridden by hello command
      dbg("transport", "setAppClient called - use hello command instead\n");
   }
   
   event void CommandHandler.hello(uint8_t clientPort, char* username) {
      dbg("transport", "Hello command: user=%s, port=%d\n", username, clientPort);
      call Chat.startClient(username, clientPort);
   }
   
   event void CommandHandler.broadcastMsg(char* message) {
      dbg("transport", "Broadcasting message: %s\n", message);
      call Chat.sendMessage(message);
   }
   
   event void CommandHandler.whisper(char* username, char* message) {
      dbg("transport", "Whisper to %s: %s\n", username, message);
      call Chat.sendWhisper(username, message);
   }
   
   event void CommandHandler.listUsers() {
      dbg("transport", "Requesting user list\n");
      call Chat.requestUserList();
   }

   // Chat events
   event void Chat.connected() {
      dbg("transport", "Chat: Connected to server!\n");
   }
   
   event void Chat.messageReceived(char* from, char* message) {
      dbg("transport", "Chat: [%s]: %s\n", from, message);
   }
   
   event void Chat.userListReceived(char* userList) {
      dbg("transport", "Chat: Online users: %s\n", userList);
   }

   // Called when connection is established (for test client)
   event void Transport.connectDone(socket_t fd){
      dbg("transport", "client connected. Sending %d bytes...\n", transfer_amount);
      
      transfer_in_progress = TRUE;
      bytes_sent = 0;
      
      call ClientWriteTimer.startPeriodic(100);
   }
   
   // Timer event - periodically try to send more data
   event void ClientWriteTimer.fired() {
      uint16_t bytesToSend;
      uint16_t bytesWritten;
      
      if (!transfer_in_progress) {
         call ClientWriteTimer.stop();
         return;
      }
      
      if (bytes_sent >= transfer_amount) {
         dbg("transport", "All %d bytes written to transport. Waiting for ACKs...\n", transfer_amount);
         transfer_in_progress = FALSE;
         call ClientWriteTimer.stop();
         return;
      }
      
      bytesToSend = transfer_amount - bytes_sent;
      
      bytesWritten = call Transport.send(clientFd, &dataBuffer[bytes_sent], bytesToSend);
      
      if (bytesWritten > 0) {
         bytes_sent += bytesWritten;
         dbg("transport", "Application: Wrote %d bytes (total: %d/%d)\n", 
             bytesWritten, bytes_sent, transfer_amount);
      }
      
      if (bytes_sent >= transfer_amount) {
         dbg("transport", "All %d bytes written to transport. Waiting for ACKs...\n", transfer_amount);
         transfer_in_progress = FALSE;
         call ClientWriteTimer.stop();
      }
   }
   
   event void ChatMsgTimer.fired() {
      // Not currently used
   }

   event error_t Transport.accept(socket_t fd) {
      dbg("transport", "server Accepted Connection. \n");
      return SUCCESS;
   }
   
   event void Transport.dataReceived(socket_t fd) {
      // Data handling is done in Chat module
   }

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
         // Packet is FOR ME
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
            call Flooding.handle_flooding(myMsg);
         }
      }
      return msg;
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      // ... existing ping logic ...
   }

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
       call LinkState.printRoutingTable();
   }

   event void CommandHandler.printLinkState(){}
   event void CommandHandler.printDistanceVector(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = Protocol;
      memcpy(Package->payload, payload, length);
   }
}
