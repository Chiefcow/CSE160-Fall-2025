from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network - using simple topology
    s.loadTopo("simple.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    # Wait for network to stabilize
    print "=== Waiting for network to stabilize ==="
    s.runTime(200);

    # Start the chat server on Node 1, Port 41
    print "\n=== Starting Chat Server on Node 1 ==="
    s.chatServer(1);
    s.runTime(50);

    # Connect Client 1 (Node 3) as "alice" on port 50
    print "\n=== Connecting Client 'alice' (Node 3) ==="
    s.chatHello(3, "alice", 50);
    s.runTime(100);

    # Connect Client 2 (Node 5) as "bob" on port 51
    print "\n=== Connecting Client 'bob' (Node 5) ==="
    s.chatHello(5, "bob", 51);
    s.runTime(100);

    # Alice sends a broadcast message
    print "\n=== Alice broadcasts 'Hello!' ==="
    s.chatMsg(3, "Hello!");
    s.runTime(150);

    # Bob sends a broadcast message
    print "\n=== Bob broadcasts 'Hi Alice!' ==="
    s.chatMsg(5, "Hi Alice!");
    s.runTime(150);

    # Alice requests user list
    print "\n=== Alice requests user list ==="
    s.chatListUsers(3);
    s.runTime(150);

    # Alice whispers to Bob
    print "\n=== Alice whispers to Bob ==="
    s.chatWhisper(3, "bob", "Secret!");
    s.runTime(150);

    print "\n=== Chat Test Complete ==="

if __name__ == '__main__':
    main()
