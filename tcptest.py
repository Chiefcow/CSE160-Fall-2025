# Use testA.py
from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("tuna-melt.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()
    s.addChannel(s.TRANSPORT_CHANNEL)
    
    s.runTime(300)      # Let routing stabilize
    s.testServer(1)     # Node 1 is server
    s.runTime(60)
    s.testClient(4)     # Node 4 is client  
    s.runTime(1000)     # Watch transfer

if __name__ == '__main__':
    main()