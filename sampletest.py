from TestSim import TestSim

def main():
    print("\n" + "="*70)
    print("TCP SIMPLE TEST - Single Connection, 1000 bytes")
    print("="*70)
    
    s = TestSim()
    s.runTime(1)
    
    # Load topology and noise
    s.loadTopo("tuna-melt.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    
    # Enable required channel for grading
    s.addChannel("Project3TGen")
    s.addChannel("general")
    # Uncomment for debugging:
    # s.addChannel("transport")
    
    # Wait for routing to stabilize
    print("\nWaiting for routing to stabilize...")
    s.runTime(500)
    print("Routing ready\n")
    
    # Start server on Node 1, Port 80
    print("Starting server on Node 1, Port 80...")
    s.testServer(1)
    s.runTime(100)
    
    # Start client on Node 4 -> Node 1
    print("Starting client on Node 4...")
    print("  Destination: Node 1")
    print("  Transfer: 1000 bytes (numbers 0-999)")
    s.testClient(4, dest=1, srcPort=41, destPort=80, transfer=1000)
    
    # Run simulation
    print("\nRunning transfer (this takes ~6 seconds simulated time)...\n")
    s.runTime(6000)
    
    print("\n" + "="*70)
    print("TEST COMPLETE")

if __name__ == '__main__':
    main()