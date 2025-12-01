def testServer(self, address):
    """
    Starts a test server on the given node address.
    Server will bind to port 80 by default.
    """
    port = 80  # Default port
    payloadStr = "{0}{1}".format(chr(address), chr(port))
    self.sendCMD(self.CMD_TEST_SERVER, address, payloadStr)
    print "Test Server started on node", address

def testClient(self, clientAddress, serverAddress, srcPort, destPort, transfer):
    """
    Starts a test client that connects to a server.
    
    Parameters:
    - clientAddress: Node ID where client runs
    - serverAddress: Node ID where server is running
    - srcPort: Client's source port
    - destPort: Server's destination port
    - transfer: Number of bytes to transfer
    """
    payloadStr = "{0}{1}{2}{3}{4}".format(
        chr(serverAddress), 
        chr(srcPort), 
        chr(destPort),
        chr(transfer & 0xFF),
        chr((transfer >> 8) & 0xFF)
    )
    self.sendCMD(self.CMD_TEST_CLIENT, clientAddress, payloadStr)
    print "Test Client started on node", clientAddress, "connecting to", serverAddress

def clientClose(self, clientAddress, serverAddress, srcPort, destPort):
    """
    Closes a client connection.
    """
    payloadStr = "{0}{1}{2}{3}".format(
        chr(serverAddress),
        chr(srcPort),
        chr(destPort),
        chr(0)
    )
    print "Close command for node", clientAddress