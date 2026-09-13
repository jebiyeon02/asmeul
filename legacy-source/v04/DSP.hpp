#pragma once
#include <array>
#include <vector>
#include <atomic>
#include <cmath>
#include <algorithm>
#include "Soundscape.hpp"

// Eight parallel damped feedback delays. All storage is prepared off the audio thread.
// This is algorithmic reverb and stereo orbit, not convolution or HRTF.
class HollowDSP {
    struct Delay { std::vector<float> data; size_t cursor=0; float low=0; };
    std::array<Delay,8> delays;
    double rate=48000, phase=0;
    float smoothing=0.001f, previousWarmth=-1, filterAlpha=1;
    float toneL=0, toneR=0, wet=0, warm=0, motion=0, level=.7f, effect=1, feedback=.8f;
public:
    Soundscape soundscape;
    std::atomic<float> targetSpace{.28f}, targetWarmth{.2f}, targetOrbit{0}, targetGain{.7f};
    std::atomic<int> bypass{0};
    std::atomic<float> peak{0};
    void prepare(double sampleRate) {
        soundscape.prepare(sampleRate); rate=sampleRate; previousWarmth=-1; smoothing=1-std::exp(-1.f/float(rate*.02)); phase=0; toneL=toneR=0; wet=0;
        const double lengths[]={.0297,.0371,.0411,.0437,.0307,.0323,.0393,.0451};
        for(int i=0;i<8;i++){delays[i].data.assign(size_t(rate*lengths[i]),0); delays[i].cursor=0; delays[i].low=0;}
    }
    struct Parameters {float space,warmth,orbit,gain,active,decay;Soundscape::Params ambience;};
    Parameters parameters() const {
        return {std::clamp(targetSpace.load(),0.f,.65f),std::clamp(targetWarmth.load(),0.f,1.f),std::clamp(targetOrbit.load(),0.f,1.f),std::clamp(targetGain.load(),0.f,1.f),bypass.load()?0.f:1.f,.78f + std::clamp(targetSpace.load(),0.f,.65f)*.18f,soundscape.parameters()};
    }
    void process(float left,float right,float &outL,float &outR,const Parameters &p) {
        if(!std::isfinite(left))left=0; if(!std::isfinite(right))right=0;
        const float smooth=smoothing;
        wet+=(p.space-wet)*smooth; warm+=(p.warmth-warm)*smooth; motion+=(p.orbit-motion)*smooth;
        level+=(p.gain-level)*smooth; effect+=(p.active-effect)*smooth; feedback+=(p.decay-feedback)*smooth;
        if(std::abs(warm-previousWarmth)>0.0001f){
            float cutoff=18000.f*std::pow(0.045f,warm);
            filterAlpha=1-std::exp(-6.2831853f*cutoff/float(rate));previousWarmth=warm;
        }
        float alpha=filterAlpha;
        toneL+=alpha*(left-toneL); toneR+=alpha*(right-toneR);
        float l=toneL, r=toneR, revL=0, revR=0;
        for(int i=0;i<8;i++) {
            auto &d=delays[i]; float old=d.data[d.cursor];
            d.low+=(old-d.low)*(.5f-.35f*warm);
            if(std::abs(d.low)<1e-20f)d.low=0;
            d.data[d.cursor]=std::clamp((i<4?l:r)*.18f+d.low*feedback,-4.f,4.f);
            if(++d.cursor==d.data.size())d.cursor=0;
            if(i<4)revL+=old;else revR+=old;
        }
        l=l*(1-wet)+revL*wet; r=r*(1-wet)+revR*wet;
        phase+=6.28318530718*(.025+motion*.22)/rate; if(phase>6.28318530718)phase-=6.28318530718;
        float pan=std::sin(phase)*motion*.75f;
        l*=std::sqrt(1-pan);r*=std::sqrt(1+pan);
        // Smooth A/B at the same output gain. Peak ceiling is a final safety clamp, not a mastering limiter.
        l=left+(l-left)*effect;r=right+(r-right)*effect;
        soundscape.next(l,r,p.ambience,effect);
        outL=std::clamp(l*level,-.95f,.95f);
        outR=std::clamp(r*level,-.95f,.95f);
    }
};
