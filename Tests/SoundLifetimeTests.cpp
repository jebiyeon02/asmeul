#include "../Sources/AudioCore/Soundscape.hpp"
#include <cassert>
#include <iostream>
#include <thread>

int main(){
    Soundscape live,decoder;
    std::vector<float> pcm(96000,.2f);
    assert(decoder.load(1,pcm.data(),48000,48000));
    assert(decoder.residentSampleBytes()==192000);
    live.prepare(48000);live.targetGains[1]=1;live.targetAmbient=1;
    // Waiting for a long decoder must not pre-advance the fade-in.
    auto p=live.parameters();float l=0,r=0;
    for(int i=0;i<48000;i++){l=r=0;live.next(l,r,p,1);assert(l==0&&r==0);}
    assert(live.takeSound(decoder,1));
    assert(decoder.residentSampleBytes()==0&&live.residentSampleBytes()==192000);
    assert(!live.takeSound(decoder,1));
    live.next(l,r,p,1);assert(l>0&&l<.001f);
    live.unload(1);
    live.collectRetired();assert(live.residentSampleBytes()==192000);
    live.renderCompleted();live.collectRetired();assert(live.residentSampleBytes()==192000);
    live.renderCompleted();live.collectRetired();assert(live.residentSampleBytes()==0);

    // Repeated publication/unload/reclamation while a serial render thread
    // holds old pointers. Run under address/undefined/thread sanitizers.
    std::atomic<bool> done{false};
    std::thread audio([&]{
        while(!done.load()){
            auto params=live.parameters();
            for(int i=0;i<256;i++){float a=0,b=0;live.next(a,b,params,1);assert(std::isfinite(a)&&std::isfinite(b));}
            live.renderCompleted();
        }
    });
    for(int i=0;i<1000;i++){
        assert(decoder.load(1,pcm.data(),48000,48000));
        assert(live.takeSound(decoder,1));
        live.collectRetired();
        if(i%2==0)live.unload(1);
    }
    done=true;audio.join();
    live.unload(1);live.reclaimRetired();
    assert(live.residentSampleBytes()==0);
    std::cout<<"PASS: zero-copy ownership, late-load fade-in, two-quantum retirement, concurrent reload/unload and complete PCM reclamation\n";
}
