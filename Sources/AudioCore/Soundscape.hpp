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
    static constexpr int capacity=36;
    struct Sample {std::vector<int16_t> pcm;double rate=0,crossfade=0;size_t frames=0,written=0;};
    std::array<std::atomic<const Sample*>,capacity> banks{};
    std::array<std::unique_ptr<Sample>,capacity> pending;
    std::vector<std::unique_ptr<Sample>> retained;
    // A published sample may still be read by the current render quantum when
    // a control-thread operation unpublishes it. Retire it first and reclaim
    // after the device has stopped or the old render quantum has completed.
    struct Retired { std::unique_ptr<Sample> sample; uint64_t after; };
    std::vector<Retired> retired;
    std::atomic<uint64_t> completedQuanta{0};
    std::array<double,capacity> position{};
    std::array<float,capacity> gains{};
    std::array<Binaural,capacity> spatializers;
    double rate=48000;
    float smoothing=.001f,music=1,ambient=.65f,fade=1;
    static float at(const Sample &s,double p,int channel){
        size_t i=std::min(size_t(p),s.frames-1),j=std::min(i+1,s.frames-1);float t=float(p-i);
        return (s.pcm[i*2+channel]*(1-t)+s.pcm[j*2+channel]*t)/32768.f;
    }
    void retirePublished(int slot){
        const Sample *published=banks[slot].exchange(nullptr,std::memory_order_acq_rel);
        if(!published)return;
        for(auto it=retained.begin();it!=retained.end();++it)if(it->get()==published){retired.push_back({std::move(*it),completedQuanta.load(std::memory_order_acquire)+2});retained.erase(it);return;}
    }
public:
    struct Params {std::array<float,capacity> gains;float ambient,music,fade;bool spatial;std::array<int,capacity> directions;std::array<float,capacity> distances;std::array<int,capacity> activeSlots{};int activeCount=0;};
    std::array<std::atomic<float>,capacity> targetGains{},targetDistances{};
    std::array<std::atomic<int>,capacity> targetDirections{};
    std::atomic<bool> targetSpatial{false};
    std::atomic<float> targetAmbient{.65f},targetMusic{1},targetFade{1};
    bool begin(int slot,size_t frames,double sampleRate){
        if(slot<0||slot>=capacity||frames<4||!std::isfinite(sampleRate)||sampleRate<8000||sampleRate>192000||frames>sampleRate*3600)return false;
        auto sample=std::make_unique<Sample>();sample->frames=frames;sample->rate=sampleRate;sample->pcm.resize(frames*2);
        sample->crossfade=std::min(sampleRate*.8,double(frames)/8);
        retirePublished(slot);
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
        sample->crossfade=std::min(sample->rate*.8,double(sample->frames)/8);
        const Sample *ptr=sample.get();retained.push_back(std::move(sample));banks[slot].store(ptr,std::memory_order_release);return true;
    }
    bool load(int slot,const float *data,size_t frames,double sampleRate){return data&&begin(slot,frames,sampleRate)&&append(slot,data,frames)&&finish(slot);}
    void unload(int slot){
        if(slot<0||slot>=capacity)return;
        pending[slot].reset();
        retirePublished(slot);
    }
    void reclaimRetired(){retired.clear();}
    // One serial device render thread reports completed quanta. Free memory
    // only on the control thread, after any reader of the old bank has left.
    void renderCompleted(){completedQuanta.fetch_add(1,std::memory_order_release);}
    void collectRetired(){
        auto completed=completedQuanta.load(std::memory_order_acquire);
        retired.erase(std::remove_if(retired.begin(),retired.end(),[&](const Retired &r){return completed>=r.after;}),retired.end());
    }
    // Source is a stopped, privately owned decoder; transfer without a PCM copy.
    bool takeSound(Soundscape &source,int slot){
        if(&source==this||slot<0||slot>=capacity)return false;
        const Sample *ptr=source.banks[slot].exchange(nullptr);
        if(!ptr)return false;
        for(auto it=source.retained.begin();it!=source.retained.end();++it)if(it->get()==ptr){
            retirePublished(slot);
            retained.push_back(std::move(*it));source.retained.erase(it);
            banks[slot].store(ptr,std::memory_order_release);return true;
        }
        return false;
    }
    size_t residentSampleBytes()const{
        size_t bytes=0;
        for(const auto &s:retained)bytes+=s->pcm.size()*sizeof(int16_t);
        for(const auto &s:pending)if(s)bytes+=s->pcm.size()*sizeof(int16_t);
        for(const auto &r:retired)bytes+=r.sample->pcm.size()*sizeof(int16_t);
        return bytes;
    }
    Params parameters()const{
        Params p{};for(int i=0;i<capacity;i++){
            p.gains[i]=std::clamp(targetGains[i].load(),0.f,1.f);
            if(p.gains[i]>0||gains[i]>=.00001f)p.activeSlots[p.activeCount++]=i;
        }
        p.spatial=targetSpatial.load();for(int i=0;i<capacity;i++){p.directions[i]=targetDirections[i].load();p.distances[i]=targetDistances[i].load();}
        p.ambient=std::clamp(targetAmbient.load(),0.f,1.f);p.music=std::clamp(targetMusic.load(),0.f,1.f);p.fade=std::clamp(targetFade.load(),0.f,1.f);return p;
    }
    void prepare(double sampleRate){
        rate=sampleRate;
        auto kernels=std::make_shared<const Binaural::KernelBank>(rate);
        for(auto &s:spatializers)s.prepare(kernels);
        smoothing=1-std::exp(-1.f/float(rate*.04));position.fill(0);gains.fill(0);music=targetMusic.load();ambient=targetAmbient.load();fade=targetFade.load();
    }
    void next(float &l,float &r,const Params &p,float active){
        music+=(p.music-music)*smoothing;ambient+=(p.ambient-ambient)*smoothing;fade+=(p.fade-fade)*smoothing;
        float bedL=0,bedR=0;
        for(int activeSlot=0;activeSlot<p.activeCount;activeSlot++){
            int slot=p.activeSlots[activeSlot];
            const Sample *sample=banks[slot].load(std::memory_order_acquire);
            // A lazy-loaded voice must begin its fade when PCM arrives, not
            // while the decoder is still working (which would cause a click).
            if(!sample){gains[slot]=0;continue;}
            gains[slot]+=(p.gains[slot]-gains[slot])*smoothing;
            if(gains[slot]<.00001f&&p.gains[slot]==0)continue;
            auto &s=*sample;double &pos=position[slot];double cross=s.crossfade;
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
