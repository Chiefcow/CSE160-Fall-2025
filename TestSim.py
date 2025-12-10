#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    moteids=[]
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP=3

    #project 3 
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5

    #Project 4 -chat commands 

    CMD_HELLO = 10
    CMD_MSG = 11
    CMD_WHISPER = 12
    CMD_LISTUSR = 13

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())
    
    def cmdTestServer(self, address, port):
        # Create Payload
        # We need to serialize this to match how CommandHandler parses it
        # Assuming payload format: [port]
        self.sendCMD(self.CMD_TEST_SERVER, address, chr(port))

    def cmdTestClient(self, address, dest, srcPort, destPort, transfer):
        # Payload: dest(2 bytes), srcPort(1), destPort(1), transfer(2 bytes)
        payload = ""
        payload += chr(dest & 0xFF) + chr((dest >> 8) & 0xFF)
        payload += chr(srcPort)
        payload += chr(destPort)
        payload += chr(transfer & 0xFF) + chr((transfer >> 8) & 0xFF)
        
        self.sendCMD(self.CMD_TEST_CLIENT, address, payload)

    def cmdClientClose(self, address, dest, srcPort, destPort):
         # Similar payload construction
         pass
    # Wrapper for the Server test
    # Usage: s.testServer(node_id, port=80)
    def testServer(self, address, port=80):
        print "Node " + str(address) + " acting as server on port " + str(port)
        self.cmdTestServer(address, port)

    # Wrapper for the Client test
    # Usage: s.testClient(client_id, dest_id=1, src_port=90, dest_port=80, transfer=100)
    # Added dest=1 default to support legacy calls like s.testClient(4)
    def testClient(self, address, dest=1, srcPort=90, destPort=80, transfer=100):
        print "Node " + str(address) + " connecting to Node " + str(dest) + \
              " : " + str(destPort) + " transferring " + str(transfer)
        # Arguments: (ClientNodeID, DestNodeID, SrcPort, DestPort, TransferAmount)
        self.cmdTestClient(address, dest, srcPort, destPort, transfer)

    # ==================== Project 4 - Chat Commands ====================
    
    def chatServer(self, address):
        """Start the chat server on the specified node (should be node 1, port 41)"""
        print "Starting Chat Server on Node " + str(address)
        # Use CMD_TEST_SERVER with port 41 for chat
        self.sendCMD(self.CMD_TEST_SERVER, address, chr(41))
    
    def chatHello(self, address, username, clientPort):
        """Connect a client to the chat server
        Format: hello [username] [clientport]
        """
        print "Node " + str(address) + " connecting as '" + username + "' on port " + str(clientPort)
        # Payload format: [clientPort][username...]
        payload = chr(clientPort) + username
        self.sendCMD(self.CMD_HELLO, address, payload)
    
    def chatMsg(self, address, message):
        """Send a broadcast message from a client
        Format: msg [message]
        """
        print "Node " + str(address) + " broadcasting: " + message
        self.sendCMD(self.CMD_MSG, address, message)
    
    def chatWhisper(self, address, toUsername, message):
        """Send a private message to a specific user
        Format: whisper [username] [message]
        """
        print "Node " + str(address) + " whispering to " + toUsername + ": " + message
        # Payload format: [usernameLen][username][message]
        payload = chr(len(toUsername)) + toUsername + message
        self.sendCMD(self.CMD_WHISPER, address, payload)
    
    def chatListUsers(self, address):
        """Request list of connected users
        Format: listusr
        """
        print "Node " + str(address) + " requesting user list"
        self.sendCMD(self.CMD_LISTUSR, address, "")
    
    # ==================== End Project 4 Commands ====================
    
    



    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))
                if not int(s[0]) in self.moteids:
                    self.moteids=self.moteids+[int(s[0])]
                if not int(s[1]) in self.moteids:
                    self.moteids=self.moteids+[int(s[1])]

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in self.moteids:
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in self.moteids:
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in self.moteids:
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("long_line.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);

    s.runTime(20);
    s.ping(1, 2, "Hello, World");
    s.runTime(10);
    s.ping(1, 3, "Hi!");
    s.runTime(20);

    s.cmdTestServer(1, 80)
    s.runTime(10)
    s.cmdTestClient(2, 1, 90, 80, 150)
if __name__ == '__main__':
    main()
