interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer();
   event void setTestClient();
   event void setAppServer();
   event void setAppClient();
   // event void setClientClose(uint16_t dest, uint8_t srcPort, uint8_t destPort);
   // event void clientClose(uint16_t clientAddr, uint16_t dest, uint8_t srcPort, uint8_t destPort);
}
