#include "../../includes/socket.h"
#include "../../includes/chat.h"

interface Chat {
    // Server commands
    command error_t startServer();
    
    // Client commands
    command error_t startClient(char* username, uint8_t clientPort);
    command error_t sendMessage(char* message);
    command error_t sendWhisper(char* username, char* message);
    command error_t requestUserList();
    
    // Events
    event void connected();
    event void messageReceived(char* from, char* message);
    event void userListReceived(char* userList);
}