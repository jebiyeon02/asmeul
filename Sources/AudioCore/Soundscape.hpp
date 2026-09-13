#pragma once
#include <algorithm>
#include "Binaural.hpp"
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>

// Independent loop players. PCM is decoded in chunks off the render thread and
// stored as 16-bit stereo to keep long recordings bounded in memory.
class Soundscape {
    static constexpr int capacity=32;
    struct Sample {std::vector<int16_t> pcm;double rate=0;size_t frames=0,written=0;};
    std::array<std::atomic<const Sample*>,capacity> banks{};
    std::array<std::unique_ptr<Sample>,capacity> pending;
    std::vector<std::unique_ptr<Sample>> retained;
    std::array<double,capacity> position{};
    std::array<float,capacity> gains{};
    std::array<Binaural,capacity> spatializers;
    double rate=48000;
    float smoothing=.001f,music=1,ambient=.65f,fade=1;
    static float at(const Sample &s,double p,int channel){
        size_t i=std::min(size_t(p),s.frames-1),j=std::min(i+1,s.frames-1);float t=float(p-i);
        return (s.pcm[i*2+channel]*(1-t)+s.pcm[j*2+channel]*t)/32768.f;
    }
public:
    struct Params {std::array<float,capacity> gains;float ambient,music,fade;bool spatial;std::array<int,capacity> directions;std::array<float,capacity> distances;};
    std::array<std::atomic<float>,capacity> targetGains{},targetDistances{};
    std::array<std::atomic<int>,capacity> targetDirections{};
    std::atomic<bool> targetSpatial{false};
    std::atomic<float> targetAmbient{.65f},targetMusic{1},targetFade{1};
    bool begin(int slot,size_t frames,double sampleRate){
        if(slot<0||slot>=capacity||frames<4||!std::isfinite(sampleRate)||sampleRate<8000||sampleRate>192000||frames>sampleRate*3600)return false;
        auto sample=std::make_unique<Sample>();sample->frames=frames;sample->rate=sampleRate;sample->pcm.resize(frames*2);
        pending[slot]=std::move(sample);return true;
    }
    bool append(int slot,const float *data,size_t frames){
        if(slot<0||slot>=capacity||!pending[slot]||!data)return false;
        auto &s=*pending[slot];if(frames>s.frames-s.written)return false;
        for(size_t i=0;i<frames*2;i++){float x=std::isfinite(data[i])?data[i]:0;s.pcm[s.written*2+i]=int16_t(std::clamp(x,-1.f,.999969f)*32768.f);}
        s.written+=frames;return true;
    }
    bool finish(int slot){
        if(slot<0||slot>=capacity||!pending[slot]||pending[slot]->written<4)return false;
        auto sample=std::move(pending[slot]);sample->frames=sample->written;sample->pcm.resize(sample->frames*2);
        const Sample *ptr=sample.get();retained.push_back(std::move(sample));banks[slot].store(ptr,std::memory_order_release);return true;
    }
    bool load(int slot,const float *data,size_t frames,double sampleRate){return data&&begin(slot,frames,sampleRate)&&append(slot,data,frames)&&finish(slot);}
    Params parameters()const{
        Params p{};for(int i=0;i<capacity;i++)p.gains[i]=std::clamp(targetGains[i].load(),0.f,1.f);
        p.spatial=targetSpatial.load();for(int i=0;i<capacity;i++){p.directions[i]=targetDirections[i].load();p.distances[i]=targetDistances[i].load();}
        p.ambient=std::clamp(targetAmbient.load(),0.f,1.f);p.music=std::clamp(targetMusic.load(),0.f,1.f);p.fade=std::clamp(targetFade.load(),0.f,1.f);return p;
    }
    void prepare(double sampleRate){rate=sampleRate;for(auto &s:spatializers)s.prepare(rate);smoothing=1-std::exp(-1.f/float(rate*.04));position.fill(0);gains.fill(0);music=targetMusic.load();ambient=targetAmbient.load();fade=targetFade.load();}
    void next(float &l,float &r,const Params &p,float active){
        music+=(p.music-music)*smoothing;ambient+=(p.ambient-ambient)*smoothing;fade+=(p.fade-fade)*smoothing;
        float bedL=0,bedR=0;
        for(int slot=0;slot<capacity;slot++){
            gains[slot]+=(p.gains[slot]-gains[slot])*smoothing;
            if(gains[slot]<.00001f&&p.gains[slot]==0)continue;
            const Sample *sample=banks[slot].load(std::memory_order_acquire);if(!sample)continue;
            auto &s=*sample;double &pos=position[slot];double cross=std::min(s.rate*.8,double(s.frames)/8);
            if(pos>=s.frames)pos=cross+std::fmod(pos-s.frames,s.frames-cross);
            float a=at(s,pos,0),b=at(s,pos,1);
            if(pos>=s.frames-cross){double head=pos-(s.frames-cross);float t=float(head/cross);a=a*(1-t)+at(s,head,0)*t;b=b*(1-t)+at(s,head,1)*t;}
            spatializers[slot].process(a,b,p.spatial,p.directions[slot],p.distances[slot]);
            bedL+=a*gains[slot];bedR+=b*gains[slot];pos+=s.rate/rate;
        }
        float inputGain=1+(music-1)*active;
        l=l*inputGain+bedL*ambient*fade*active;r=r*inputGain+bedR*ambient*fade*active;
    }
};
