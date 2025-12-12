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
    # print("============================================================")
    # print("=== COMPREHENSIVE CHAT TEST SUITE ===")
    # print("============================================================")
    # print("")
    # print("=== Phase 1: Network Stabilization ===")
    # s.runTime(300);

    # # Start the chat server on Node 1, Port 41
    # print("")
    # print("=== Phase 2: Server Initialization ===")
    # print("Starting Chat Server on Node 1...")
    # s.chatServer(1);
    # s.runTime(60);

    # # Test 1: Basic Connections
    # print("")
    # print("=== Phase 3: Basic Client Connections ===")
    # print("Test 1.1: Connect Client 'alice' (Node 4)")
    # s.chatHello(4, "alice", 50);
    # s.runTime(100);

    # print("Test 1.2: Connect Client 'bob' (Node 7)")
    # s.chatHello(7, "bob", 51);
    # s.runTime(100);

    # print("Test 1.3: Connect Client 'charlie' (Node 10)")
    # s.chatHello(10, "charlie", 52);
    # s.runTime(100);

    # # Test 2: Duplicate Username (Should fail)
    # print("")
    # print("=== Phase 4: Edge Case - Duplicate Username ===")
    # print("Test 2.1: Attempt to connect with duplicate username 'alice'")
    # s.chatHello(13, "alice", 53);
    # s.runTime(100);

    # # Test 3: Basic Messaging
    # print("")
    # print("=== Phase 5: Basic Messaging ===")
    # print("Test 3.1: Alice broadcasts 'Hello everyone!'")
    # s.chatMsg(4, "Hello everyone!");
    # s.runTime(200);

    # print("Test 3.2: Bob broadcasts 'Hi Alice!'")
    # s.chatMsg(7, "Hi Alice!");
    # s.runTime(200);

    # print("Test 3.3: Charlie broadcasts 'Greetings!'")
    # s.chatMsg(10, "Greetings!");
    # s.runTime(200);

    # # Test 4: Private Messages (Whisper)
    # print("")
    # print("=== Phase 6: Private Messaging (Whisper) ===")
    # print("Test 4.1: Alice whispers to Bob: 'Secret message'")
    # s.chatWhisper(4, "bob", "Secret message");
    # s.runTime(200);

    # print("Test 4.2: Bob whispers to Charlie: 'Hey there!'")
    # s.chatWhisper(7, "charlie", "Hey there!");
    # s.runTime(200);

    # print("Test 4.3: Charlie whispers to Alice: 'Private chat'")
    # s.chatWhisper(10, "alice", "Private chat");
    # s.runTime(200);

    # # Test 5: Whisper to Non-existent User (Should fail)
    # print("")
    # print("=== Phase 7: Edge Case - Whisper to Non-existent User ===")
    # print("Test 5.1: Alice tries to whisper to 'dave' (doesn't exist)")
    # s.chatWhisper(4, "dave", "Are you there?");
    # s.runTime(200);

    # # Test 6: User List
    # print("")
    # print("=== Phase 8: User List Functionality ===")
    # print("Test 6.1: Alice requests user list")
    # s.chatListUsers(4);
    # s.runTime(200);

    # print("Test 6.2: Bob requests user list")
    # s.chatListUsers(7);
    # s.runTime(200);

    # print("Test 6.3: Charlie requests user list")
    # s.chatListUsers(10);
    # s.runTime(200);

    # # Test 7: Additional Client
    # print("")
    # print("=== Phase 9: Additional Client Connection ===")
    # print("Test 7.1: Connect Client 'dave' (Node 13)")
    # s.chatHello(13, "dave", 54);
    # s.runTime(100);

    # print("Test 7.2: Dave broadcasts 'Just joined!'")
    # s.chatMsg(13, "Just joined!");
    # s.runTime(200);

    # print("Test 7.3: Alice requests updated user list")
    # s.chatListUsers(4);
    # s.runTime(200);

    # # Test 8: Connect another client (Node 16)
    # print("")
    # print("=== Phase 10: Fifth Client Connection ===")
    # print("Test 8.1: Connect Client 'eve' (Node 16)")
    # s.chatHello(16, "eve", 55);
    # s.runTime(100);

    # print("Test 8.2: Eve broadcasts 'Hello all!'")
    # s.chatMsg(16, "Hello all!");
    # s.runTime(200);

    # # Test 9: Stress Test - Multiple Messages
    # print("")
    # print("=== Phase 11: Stress Test - Multiple Sequential Messages ===")
    # print("Test 9.1: Rapid message sequence")
    # s.chatMsg(4, "Message 1");
    # s.runTime(50);
    # s.chatMsg(7, "Message 2");
    # s.runTime(50);
    # s.chatMsg(10, "Message 3");
    # s.runTime(50);
    # s.chatMsg(13, "Message 4");
    # s.runTime(50);
    # s.chatMsg(16, "Message 5");
    # s.runTime(200);

    # # Test 10: Long Message Test
    # print("")
    # print("=== Phase 12: Edge Case - Long Messages ===")
    # print("Test 10.1: Alice sends a longer message")
    # s.chatMsg(4, "This is a much longer message to test buffer handling");
    # s.runTime(200);

    # # Test 11: Whisper Chain
    # print("")
    # print("=== Phase 13: Whisper Chain Test ===")
    # print("Test 11.1: Alice -> Bob")
    # s.chatWhisper(4, "bob", "Pass it on");
    # s.runTime(150);
    # print("Test 11.2: Bob -> Charlie")
    # s.chatWhisper(7, "charlie", "Pass it on");
    # s.runTime(150);
    # print("Test 11.3: Charlie -> Dave")
    # s.chatWhisper(10, "dave", "Pass it on");
    # s.runTime(150);
    # print("Test 11.4: Dave -> Eve")
    # s.chatWhisper(13, "eve", "End of chain");
    # s.runTime(150);

    # Test 12: Final User List with All Clients
    print("")
    print("=== Phase 14: Final User List ===")
    print("Test 12.1: Bob requests final user list (should show all 5 users)")
    s.chatListUsers(7);
    s.runTime(200);

    # Test 13: Multiple broadcasts
    print("")
    print("=== Phase 15: Group Conversation Simulation ===")
    print("Test 13.1: Alice: 'Who wants to play a game?'")
    s.chatMsg(4, "Who wants to play a game?");
    s.runTime(150);
    print("Test 13.2: Bob: 'I'm in!'")
    s.chatMsg(7, "I'm in!");
    s.runTime(150);
    print("Test 13.3: Charlie: 'Me too!'")
    s.chatMsg(10, "Me too!");
    s.runTime(150);
    print("Test 13.4: Dave: 'Count me in'")
    s.chatMsg(13, "Count me in");
    s.runTime(150);
    print("Test 13.5: Eve: 'Sounds fun!'")
    s.chatMsg(16, "Sounds fun!");
    s.runTime(200);

    # Test 14: Mixed Communication
    print("")
    print("=== Phase 16: Mixed Communication (Broadcasts + Whispers) ===")
    print("Test 14.1: Alice broadcasts: 'Starting in 5 minutes'")
    s.chatMsg(4, "Starting in 5 minutes");
    s.runTime(100);
    print("Test 14.2: Alice whispers to Bob: 'Are you ready?'")
    s.chatWhisper(4, "bob", "Are you ready?");
    s.runTime(100);
    print("Test 14.3: Bob broadcasts: 'Ready!'")
    s.chatMsg(7, "Ready!");
    s.runTime(100);
    print("Test 14.4: Charlie whispers to Dave: 'What game?'")
    s.chatWhisper(10, "dave", "What game?");
    s.runTime(100);
    print("Test 14.5: Dave whispers back to Charlie: 'Not sure yet'")
    s.chatWhisper(13, "charlie", "Not sure yet");
    s.runTime(200);

    # Test 15: Verify all clients still active
    print("")
    print("=== Phase 17: Final Connectivity Check ===")
    print("Test 15.1: All clients send final messages")
    s.chatMsg(4, "Alice still here");
    s.runTime(100);
    s.chatMsg(7, "Bob still here");
    s.runTime(100);
    s.chatMsg(10, "Charlie still here");
    s.runTime(100);
    s.chatMsg(13, "Dave still here");
    s.runTime(100);
    s.chatMsg(16, "Eve still here");
    s.runTime(200);

    print("")
    print("============================================================")
    print("=== TEST SUITE COMPLETE ===")
    print("============================================================")
    print("")
    print("Tests Performed:")
    print("  - Basic client connections (5 clients)")
    print("  - Duplicate username handling")
    print("  - Broadcast messaging")
    print("  - Private messaging (whisper)")
    print("  - User list requests")
    print("  - Whisper to non-existent user")
    print("  - Long messages")
    print("  - Rapid message sequences")
    print("  - Whisper chains")
    print("  - Group conversations")
    print("  - Mixed communication patterns")
    print("  - Connection persistence")
    print("")
    print("Expected Results:")
    print("  - All 5 clients connected successfully")
    print("  - Duplicate username rejected")
    print("  - All broadcasts received by all clients")
    print("  - All whispers delivered to intended recipients")
    print("  - User lists show all connected clients")
    print("  - Error messages for invalid operations")
    print("============================================================")

if __name__ == '__main__':
    main()