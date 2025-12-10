/**
 * @author UCM ANDES Lab
 * $Author: abeltran2 $
 * $LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
 *
 */


#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

module CommandHandlerP{
   provides interface CommandHandler;
   uses interface Receive;
   uses interface Pool<message_t>;
   uses interface Queue<message_t*>;
   uses interface Packet;
}

implementation{
    task void processCommand(){
        if(! call Queue.empty()){
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;

            // Pop message out of queue.
            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            // Check to see if the packet is valid.
            if(!payload){
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }
            // Change it to our type.
            msg = (CommandMsg*) payload;

            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;

            //Find out which command was called and call related command
            switch(commandID){
            // A ping will have the destination of the packet as the first
            // value and the string in the remainder of the payload
            case CMD_PING:
                dbg(COMMAND_CHANNEL, "Command Type: Ping\n");
                signal CommandHandler.ping(buff[0], &buff[1]);
                break;

            case CMD_NEIGHBOR_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
                signal CommandHandler.printNeighbors();
                break;

            case CMD_LINKSTATE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
                signal CommandHandler.printLinkState();
                break;

            case CMD_ROUTETABLE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
                signal CommandHandler.printRouteTable();
                break;

            case CMD_TEST_CLIENT:
                dbg(COMMAND_CHANNEL, "Command Type: Test Client\n");
                signal CommandHandler.setTestClient();
                break;

            case CMD_TEST_SERVER:
                dbg(COMMAND_CHANNEL, "Command Type: Test Server\n");
                signal CommandHandler.setTestServer();
                break;
            
            // Project 4 - Chat Commands
            case CMD_HELLO:
                {
                    // Payload format: [clientPort][username...]
                    uint8_t clientPort = buff[0];
                    char username[16];
                    uint8_t i;
                    for(i = 0; i < 15 && buff[i+1] != '\0'; i++) {
                        username[i] = buff[i+1];
                    }
                    username[i] = '\0';
                    dbg(COMMAND_CHANNEL, "Command Type: Hello - User: %s, Port: %d\n", username, clientPort);
                    signal CommandHandler.hello(clientPort, username);
                }
                break;
                
            case CMD_MSG:
                {
                    // Payload format: [message...]
                    char message[24];
                    uint8_t i;
                    for(i = 0; i < 23 && buff[i] != '\0'; i++) {
                        message[i] = buff[i];
                    }
                    message[i] = '\0';
                    dbg(COMMAND_CHANNEL, "Command Type: Broadcast Message: %s\n", message);
                    signal CommandHandler.broadcastMsg(message);
                }
                break;
                
            case CMD_WHISPER:
                {
                    // Payload format: [usernameLen][username][message...]
                    char username[16];
                    char message[24];
                    uint8_t usernameLen = buff[0];
                    uint8_t i;
                    
                    for(i = 0; i < usernameLen && i < 15; i++) {
                        username[i] = buff[i+1];
                    }
                    username[i] = '\0';
                    
                    for(i = 0; i < 23 && buff[usernameLen+1+i] != '\0'; i++) {
                        message[i] = buff[usernameLen+1+i];
                    }
                    message[i] = '\0';
                    
                    dbg(COMMAND_CHANNEL, "Command Type: Whisper to %s: %s\n", username, message);
                    signal CommandHandler.whisper(username, message);
                }
                break;
                
            case CMD_LISTUSR:
                dbg(COMMAND_CHANNEL, "Command Type: List Users\n");
                signal CommandHandler.listUsers();
                break;

            default:
                dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                break;
            }
            call Pool.put(raw_msg);
        }

        if(! call Queue.empty()){
            post processCommand();
        }
    }
    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len){
        if (! call Pool.empty()){
            call Queue.enqueue(raw_msg);
            post processCommand();
            return call Pool.get();
        }
        return raw_msg;
    }
}
