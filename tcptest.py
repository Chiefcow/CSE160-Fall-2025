from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    s.loadTopo("long_line.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels.
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);
    s.addChannel(s.ROUTING_CHANNEL);

    # Wait for network to stabilize
    print "==============================================="
    print "TCP Transport Protocol Test (Simple Version)"
    print "==============================================="
    s.runTime(10);

    # Test 1: Start server on node 1, port 80
    # Using direct sendCMD instead of cmdTestServer
    print "\n--- Test 1: Starting Server ---"
    payloadStr = "{0}{1}".format(chr(1), chr(80))  # address=1, port=80
    s.sendCMD(5, 1, payloadStr)  # CMD_TEST_SERVER=5, destination=1
    print "Server command sent to node 1, port 80"
    s.runTime(5);

    # Test 2: Start client on node 2, connect to server
    print "\n--- Test 2: Starting Client ---"
    # Pack: dest(1), srcPort(41), destPort(80), transfer(20)
    payloadStr = "{0}{1}{2}{3}{4}".format(
        chr(1),      # dest = 1
        chr(41),     # srcPort = 41
        chr(80),     # destPort = 80
        chr(20),     # transfer low byte = 20
        chr(0)       # transfer high byte = 0
    )
    s.sendCMD(4, 2, payloadStr)  # CMD_TEST_CLIENT=4, source=2
    print "Client command sent from node 2 to node 1"
    s.runTime(20);

    # Check for accepted connections
    print "\n--- Test 3: Checking for Accepted Connections ---"
    payloadStr = "{0}{1}".format(chr(1), chr(80))
    s.sendCMD(5, 1, payloadStr)  # Server check
    s.runTime(20);

    # Let data transfer complete
    print "\n--- Test 4: Data Transfer ---"
    s.runTime(30);

    # Read data on server
    print "\n--- Test 5: Reading Data on Server ---"
    payloadStr = "{0}{1}".format(chr(1), chr(80))
    s.sendCMD(5, 1, payloadStr)  # Server check
    s.runTime(5);

    print "\n==============================================="
    print "Test Complete"
    print "==============================================="

if __name__ == '__main__':
    main()