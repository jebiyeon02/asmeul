#pragma once
#include <array>
#include <vector>
#include <atomic>
#include <cmath>
#include <algorithm>
#include "Soundscape.hpp"

// Eight-line orthogonal feedback network. Storage is prepared off the audio thread.
// This is algorithmic reverb and stereo orbit, not convolution or HRTF.
class ASMEULDSP {
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
        soundscape.prepare(sampleRate); rate=sampleRate; previousWarmth=-1; smoothing=1-std::exp(-1.f/float(rate*.02)); phase=0; toneL=toneR=0; wet=warm=motion=0; level=.7f; effect=1; feedback=.8f;
        const double lengths[]={.0473,.0531,.0617,.0719,.0793,.0893,.1013,.1139};
        for(int i=0;i<8;i++){delays[i].data.assign(size_t(rate*lengths[i]),0); delays[i].cursor=0; delays[i].low=0;}
    }
    struct Parameters {float space,warmth,orbit,gain,active,decay;Soundscape::Params ambience;};
    Parameters parameters() const {
        return {std::clamp(targetSpace.load(),0.f,1.f),std::clamp(targetWarmth.load(),0.f,1.f),std::clamp(targetOrbit.load(),0.f,1.f),std::clamp(targetGain.load(),0.f,1.f),bypass.load()?0.f:1.f,.72f + std::clamp(targetSpace.load(),0.f,1.f)*.23f,soundscape.parameters()};
    }
    void process(float left,float right,float &outL,float &outR,const Parameters &p) {
        if(!std::isfinite(left))left=0; if(!std::isfinite(right))right=0;
        const float smooth=smoothing;
        wet+=(p.space-wet)*smooth; warm+=(p.warmth-warm)*smooth; motion+=(p.orbit-motion)*smooth;
        level+=(p.gain-level)*smooth; effect+=(p.active-effect)*smooth; feedback+=(p.decay-feedback)*smooth;
        if(std::abs(warm-previousWarmth)>0.0001f){
            float cutoff=20000.f*std::pow(0.0225f,warm);
            filterAlpha=1-std::exp(-6.2831853f*cutoff/float(rate));previousWarmth=warm;
        }
        float alpha=filterAlpha;
        toneL+=alpha*(left-toneL); toneR+=alpha*(right-toneR);
        // At zero warmth the signal stays transparent. Increasing warmth adds
        // a darker low-pass tone and gently saturates peaks.
        float l=left+(toneL-left)*warm, r=right+(toneR-right)*warm;
        // At the transparent setting the saturation term is multiplied by
        // zero. Avoid its transcendental work without changing that setting.
        if(warm>0){
            float drive=1+warm*4;
            l=l+(std::tanh(l*drive)/drive*1.4f-l)*warm;
            r=r+(std::tanh(r*drive)/drive*1.4f-r)*warm;
        }
        std::array<float,8> taps{};
        float sum=0,revL=0,revR=0;
        for(int i=0;i<8;i++) {
            auto &d=delays[i]; float old=d.data[d.cursor];
            d.low+=(old-d.low)*(.72f-.35f*warm);
            if(std::abs(d.low)<1e-20f)d.low=0;
            taps[i]=d.low;sum+=d.low;
            // Different signed taps preserve stereo decorrelation.
            revL+=old*(i%2?-.35f:.35f);
            revR+=old*((i/2)%2?-.35f:.35f);
        }
        for(int i=0;i<8;i++) {
            auto &d=delays[i];
            float input=(i%2?l:r)*(i<4?.25f:-.25f);
            // Householder reflection is energy preserving; feedback stays < 1.
            d.data[d.cursor]=std::clamp(input+(taps[i]-sum*.25f)*feedback,-4.f,4.f);
            if(++d.cursor==d.data.size())d.cursor=0;
        }
        float amount=.92f*std::sqrt(std::max(0.f,wet));
        l=l*(1-amount*.85f)+revL*amount*1.5f;
        r=r*(1-amount*.85f)+revR*amount*1.5f;
        phase+=6.28318530718*(.035+motion*.145)/rate;
        if(phase>6.28318530718)phase-=6.28318530718;
        // Keep phase advancing while the effect is at its transparent default,
        // but skip the orbit math until the user actually enables it.
        if(motion>0){
            float depth=std::sqrt(motion);
            float pan=std::sin(phase)*depth*.985f;
            // Move the stereo image, including hard-panned sources, across the field.
            float mid=(l+r)*.5f, side=(l-r)*.5f*(1-depth*.85f);
            l=(mid+side)*std::sqrt(1-pan);r=(mid-side)*std::sqrt(1+pan);
        }
        // Smooth A/B at the same output gain. Peak ceiling is a final safety clamp, not a mastering limiter.
        l=left+(l-left)*effect;r=right+(r-right)*effect;
        soundscape.next(l,r,p.ambience,effect);
        outL=std::clamp(l*level,-.95f,.95f);
        outR=std::clamp(r*level,-.95f,.95f);
    }
};
