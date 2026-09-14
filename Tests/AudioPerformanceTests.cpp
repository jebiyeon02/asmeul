#include "../Sources/AudioCore/Binaural.hpp"
#include "Fixtures/BinauralReference.hpp"
#include <cassert>
#include <chrono>
#include <iostream>
#include <random>
#include <vector>

volatile float benchmarkSink=0;
template<class Spatializer> double benchmark(double rate,int tracks){
    std::vector<Spatializer> voices(tracks);
    for(auto &voice:voices)voice.prepare(rate);
    auto start=std::chrono::steady_clock::now();
    float sum=0;
    for(int frame=0;frame<int(rate*2);frame++)for(int slot=0;slot<tracks;slot++){
        float l=.1f*std::sin(float(frame)*.071f),r=l*.7f;
        voices[slot].process(l,r,true,slot%7,.3f);sum+=l+r;
    }
    benchmarkSink=sum;
    return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
int main(){
    float worst=0;
    for(double rate:{44100.,48000.,96000.,192000.}){
        Binaural optimized;BinauralReference reference;
        optimized.prepare(rate);reference.prepare(rate);
        std::mt19937 rng(1234);std::uniform_real_distribution<float> noise(-.5f,.5f);
        for(int frame=0;frame<int(rate*2);frame++){
            float l=noise(rng),r=noise(rng),a=l,b=r;
            bool on=(frame/11003)%3!=2;int direction=(frame/2017)%7;
            float distance=float((frame/3701)%11)/10;
            optimized.process(l,r,on,direction,distance);
            reference.process(a,b,on,direction,distance);
            worst=std::max(worst,std::max(std::abs(l-a),std::abs(r-b)));
            assert(std::isfinite(l)&&std::isfinite(r));
            assert(std::abs(l-a)<2e-6f&&std::abs(r-b)<2e-6f);
        }
    }
    std::cout<<"PASS: accelerated FIR matches scalar reference across wraparound, 7 directions, distance and wet transitions at 4 sample rates; max error "<<worst<<"\n";
    for(int tracks:{1,8,24}){
        // Warm up the vector library before measuring the same workload.
        benchmark<Binaural>(48000,1);
        double before=benchmark<BinauralReference>(48000,tracks);
        double after=benchmark<Binaural>(48000,tracks);
        std::cout<<tracks<<" tracks / 2s at 48kHz: scalar "<<before<<"ms, Accelerate "<<after<<"ms ("<<before/after<<"x)\n";
    }
}
