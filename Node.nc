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
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   //new interface
   uses interface NeighborDiscovery as NeighborDiscovery;
   //uses interface NeighborDiscovery;
}

implementation{
   pack sendPackage;
   static uint16_t lastSeq[256]; // tracks last sequence seen per source - Elvis 
   static uint16_t seqNo = 0; //sequence  number for packets 
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();
      //starting the neighborDiscovery module on start
      call NeighborDiscovery.start();

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
      dbg(GENERAL_CHANNEL, "Packet Received\n"); //This function was changed by me - Elvis 
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(FLOODING_CHANNEL, "Flooding: recived seq=%d from src=%d destined for %d\n", myMsg->seq, myMsg->src, myMsg->dest); // Debug messaging 
         //static uint16_t lastseq[256]; // per-source sequence memory 
         //IF this method fails best try a hashmap never can go wrong with that - Elvis
         if(myMsg->seq == lastseq[myMsg->src]){
            dbg(FLOODING_CHANNEL, "Duplicate packet, dropping.\n");
            return msg; // This should be fowarded? - ELvis
         }
         lastSeq[myMsg->src] = myMsg->seq;

         //Check if the packet is to be Delivered-Elvis
         if(myMsg->dest == TOS_NODE_ID){
            dbg(FLOODING_CHANNEL, "Packet reached destination %d with a paylod of %s/n", TOS_NODE_ID, myMsg->payload);
   
         }
         else{
            //This is a statement to incase there is a need to rebroadcast
            dbg(FLOODING_CHANNEL, "Rebrcasting to packet from %d with seq=%d\n", myMsg->src,myMsg->seq);
            call Sender.send(*myMsg, AM_BROADCAST_ADDR);
         }
         return msg;
         
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 5 /* Time to live - Elvis*/, 0, seqNo++, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destination);
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

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
