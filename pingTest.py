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

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.FLOODING_CHANNEL);
    #s.addChannel(s.NEIGHBOR_CHANNEL);

    # After sending a ping, simulate a little to prevent collision.
    #s.runTime(1);
    # s.ping(2, 3, "Hello, World");
    # s.runTime(1);
    s.runTime(1);

    s.ping(1, 10, "Hi!");
    s.runTime(1);

    s.runTime(5)

    s.ping(1, 5, "Hello seq 1")
    s.runTime(10)
    # Print neighbors for each node
    # for i in range(1, 2):
    #     s.neighborDMP(i)
    #     s.runTime(1)
    
    # Let it run for a while to see periodic updates
    #s.runTime(5)
    
    # Test with a ping to see flooding still works
    # s.ping(1, 9, "Test message")
    # s.runTime(10)

if __name__ == '__main__':
    main()
