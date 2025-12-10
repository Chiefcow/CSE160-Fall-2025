from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    s.loadTopo("tuna-melt.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    # Wait for network to stabilize (neighbor discovery, link state)
    print "=== Waiting for network to stabilize ==="
    s.runTime(300);

    # Start the chat server on Node 1, Port 41
    print "\n=== Starting Chat Server on Node 1 ==="
    s.chatServer(1);
    s.runTime(60);

    # Connect Client 1 (Node 4) as "alice" on port 50
    print "\n=== Connecting Client 'alice' (Node 4) ==="
    s.chatHello(4, "alice", 50);
    s.runTime(100);

    # Connect Client 2 (Node 7) as "bob" on port 51
    print "\n=== Connecting Client 'bob' (Node 7) ==="
    s.chatHello(7, "bob", 51);
    s.runTime(100);

    # Connect Client 3 (Node 10) as "charlie" on port 52
    print "\n=== Connecting Client 'charlie' (Node 10) ==="
    s.chatHello(10, "charlie", 52);
    s.runTime(100);

    # Alice sends a broadcast message
    print "\n=== Alice broadcasts 'Hello everyone!' ==="
    s.chatMsg(4, "Hello everyone!");
    s.runTime(200);

    # Bob sends a broadcast message
    print "\n=== Bob broadcasts 'Hi Alice!' ==="
    s.chatMsg(7, "Hi Alice!");
    s.runTime(200);

    # Alice whispers to Bob
    print "\n=== Alice whispers to Bob: 'Secret message' ==="
    s.chatWhisper(4, "bob", "Secret message");
    s.runTime(200);

    # Charlie requests user list
    print "\n=== Charlie requests user list ==="
    s.chatListUsers(10);
    s.runTime(200);

    # Charlie sends a message
    print "\n=== Charlie broadcasts 'Greetings!' ==="
    s.chatMsg(10, "Greetings!");
    s.runTime(200);

    # Bob whispers to Charlie
    print "\n=== Bob whispers to Charlie: 'Hey there!' ==="
    s.chatWhisper(7, "charlie", "Hey there!");
    s.runTime(200);

    print "\n=== Chat Test Complete ==="

if __name__ == '__main__':
    main()
