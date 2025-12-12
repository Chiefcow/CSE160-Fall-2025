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

    #Wait for network to stabilize (neighbor discovery, link state)
    print("=== Phase 1: Network Stabilization ===")
    s.runTime(300);

    #Starting the chat server on Node 1, Port 41
    print("")
    print("=== Phase 2: Server Initialization ===")
    print("Starting Chat Server on Node 1...")
    s.chatServer(1);
    s.runTime(60);

    # Basic connection
    print("")
    print("=== Phase 3: Basic Client Connections ===")
    print("Test 1.1: Connect Client 'alice' (Node 4)")
    s.chatHello(4, "alice", 50);
    s.runTime(100);

    print("Test 1.2: Connect Client 'bob' (Node 7)")
    s.chatHello(7, "bob", 51);
    s.runTime(100);

    print("Test 1.3: Connect Client 'charlie' (Node 10)")
    s.chatHello(10, "charlie", 52);
    s.runTime(100);

    # Duplicate username case
    print("")
    print("=== Phase 4: Edge Case - Duplicate Username ===")
    print("Test 2.1: Attempt to connect with duplicate username 'alice'")
    s.chatHello(13, "alice", 53);
    s.runTime(100);

    # Basic Message
    print("")
    print("=== Phase 5: Basic Messaging ===")
    print("Test 3.1: Alice broadcasts 'Hello everyone!'")
    s.chatMsg(4, "Hello everyone!");
    s.runTime(200);

    print("Test 3.2: Bob broadcasts 'Hi Alice!'")
    s.chatMsg(7, "Hi Alice!");
    s.runTime(200);

    print("Test 3.3: Charlie broadcasts 'Greetings!'")
    s.chatMsg(10, "Greetings!");
    s.runTime(200);

    # Whisper
    print("")
    print("=== Phase 6: Private Messaging (Whisper) ===")
    print("Test 4.1: Alice whispers to Bob: 'Secret message'")
    s.chatWhisper(4, "bob", "Secret message");
    s.runTime(200);

    print("Test 4.2: Bob whispers to Charlie: 'Hey there!'")
    s.chatWhisper(7, "charlie", "Hey there!");
    s.runTime(200);

    print("Test 4.3: Charlie whispers to Alice: 'Private chat'")
    s.chatWhisper(10, "alice", "Private chat");
    s.runTime(200);

    # Whisper to Non-existent User -> Should fail
    print("")
    print("=== Phase 7: Edge Case - Whisper to Non-existent User ===")
    print("Test 5.1: Alice tries to whisper to 'dave' (doesn't exist)")
    s.chatWhisper(4, "dave", "Are you there?");
    s.runTime(200);

    # User List
    print("")
    print("=== Phase 8: User List Functionality ===")
    print("Test 6.1: Alice requests user list")
    s.chatListUsers(4);
    s.runTime(200);

    print("Test 6.2: Bob requests user list")
    s.chatListUsers(7);
    s.runTime(200);

    print("Test 6.3: Charlie requests user list")
    s.chatListUsers(10);
    s.runTime(200);

    # Additional Client
    print("")
    print("=== Phase 9: Additional Client Connection ===")
    print("Test 7.1: Connect Client 'dave' (Node 13)")
    s.chatHello(13, "dave", 54);
    s.runTime(100);

    print("Test 7.2: Dave broadcasts 'Just joined!'")
    s.chatMsg(13, "Just joined!");
    s.runTime(200);

    print("Test 7.3: Alice requests updated user list")
    s.chatListUsers(4);
    s.runTime(200);

    # Connect another client (Node 16)
    print("")
    print("=== Phase 10: Fifth Client Connection ===")
    print("Test 8.1: Connect Client 'eve' (Node 16)")
    s.chatHello(16, "eve", 55);
    s.runTime(100);

    print("Test 8.2: Eve broadcasts 'Hello all!'")
    s.chatMsg(16, "Hello all!");
    s.runTime(200);

    # Test 9:Multiple Messages
    print("")
    print("=== Phase 11: Stress Test - Multiple Sequential Messages ===")
    print("Test 9.1: Rapid message sequence")
    s.chatMsg(4, "Message 1");
    s.runTime(50);
    s.chatMsg(7, "Message 2");
    s.runTime(50);
    s.chatMsg(10, "Message 3");
    s.runTime(50);
    s.chatMsg(13, "Message 4");
    s.runTime(50);
    s.chatMsg(16, "Message 5");
    s.runTime(200);


if __name__ == '__main__':
    main()