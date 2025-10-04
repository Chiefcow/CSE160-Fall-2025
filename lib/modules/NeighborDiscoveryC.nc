configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
    uses interface Flooding;     // NodeC will wire this to FloodingC
}
implementation {
    components NeighborDiscoveryP;
    components new TimerMilliC();

    NeighborDiscovery = NeighborDiscoveryP;

    NeighborDiscoveryP.Timer0  -> TimerMilliC;
    NeighborDiscoveryP.Flooding -> Flooding;   // receive Flooding.handle_flooding calls
}
