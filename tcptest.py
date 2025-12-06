# Use testA.py
from TestSim import TestSim

def main():
     # Create simulator
    s = TestSim()
    
    # Boot simulator with 1 time unit
    s.runTime(1)
    
    # Load network topology
    s.loadTopo("tuna-melt.topo")  # or "long_line.topo"
    
    # Load noise model
    s.loadNoise("no_noise.txt")   # or "meyer-heavy.txt"
    
    # Boot all nodes in topology
    s.bootAll()
    
    # Add debug channels - USE "Project3TGen" for grading!
    s.addChannel("Project3TGen")   # REQUIRED for your project
    s.addChannel("general")
    #s.addChannel("routing")
    
    # CRITICAL: Wait for routing to stabilize
    print("\n=== Waiting for routing to stabilize ===")
    s.runTime(500)
    
    # Verify routes exist
    # print("\n=== Routing Tables ===")
    # s.routeDMP(1)
    # s.runTime(10)
    # s.routeDMP(4)
    # s.runTime(10)
    
    # Start server on Node 1, Port 80
    print("\n=== Starting Server ===")
    s.testServer(1)  # Node 1 becomes server on port 80
    s.runTime(100)
    
    # Start client on Node 4 connecting to Node 1
    print("\n=== Starting Client ===")
    s.testClient(4)  # Node 4 connects to Node 1, transfers 100 bytes
    
    # Run simulation long enough for transfer
    s.runTime(3000)
    
    print("\n=== Test Complete ===")
if __name__ == '__main__':
    main()