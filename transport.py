from TestSim import TestSim

def main():
    # Initialize simulation
    s = TestSim()
    
    # Setup
    s.runTime(1)
    
    # Load network topology
    s.loadTopo("tuna-melt.topo")
    
    # Add noise model
    s.loadNoise("no_noise.txt")
    
    # Boot all nodes
    s.bootAll()
    
    # Add debug channels
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    
    # Let network stabilize (neighbor discovery + routing)
    print("\n=== Network Initialization ===")
    s.runTime(300)
    
    # TEST 1: Simple Connection Setup
    print("\n=== TEST 1: Connection Setup ===")
    print("Starting server on Node 1, port 80...")
    s.testServer(1, 80)
    s.runTime(60)
    
    print("Connecting client from Node 4 to Node 1...")
    s.testClient(4, 1, 90, 80, 50)
    s.runTime(500)
    
    # TEST 2: Data Transfer
    print("\n=== TEST 2: Data Transfer ===")
    print("Client should be transferring 50 bytes of data...")
    s.runTime(1000)
    
    # TEST 3: Multiple Concurrent Connections
    print("\n=== TEST 3: Multiple Concurrent Connections ===")
    s.testServer(5, 80)
    s.runTime(60)
    
    s.testClient(10, 5, 91, 80, 30)
    s.runTime(500)
    
    print("\nTests completed!")

if __name__ == '__main__':
    main()