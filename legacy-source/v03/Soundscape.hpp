#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>

// Immutable decoded sample banks are published off the render thread and retained
// until engine destruction. No allocation, locking, I/O or ARC in next().
class Soundscape {
    struct Sample {std::vector<float> pcm;double rate;size_t frames;};
    std::array<std::atomic<const Sample*>,16> banks{};
    std::vector<std::unique_ptr<Sample>> retained;
    std::array<double,16> position{};
    std::array<float,5> sceneMix{};
    double rate=48000, radioTime=0, voicePosition=0, sceneTime=0;
    int voiceClip=0;
    bool speaking=false;
    float ambient=0,music=1,distance=.35f,voiceLevel=.35f,fade=1,details=.45f,score=.18f;
    float filterL=0,filterR=0,cityL=0,cityR=0,voiceLP=0,voiceHP=0;
    float sceneSmooth=.00003f, controlSmooth=.001f,voiceLowCoeff=.25f,voiceHighCoeff=.03f;
    uint32_t rng=0xABC124;
    float noise(){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return float(rng)* (2.f/4294967295.f)-1;}
    static float at(const Sample &s,double pos,int channel){
        auto i=std::min(size_t(pos),s.frames-1),j=std::min(i+1,s.frames-1);float f=float(pos-i);
        return s.pcm[i*2+channel]*(1-f)+s.pcm[j*2+channel]*f;
    }
    void loop(int slot,float &l,float &r,bool musical=false){
        const Sample *sample=banks[slot].load(std::memory_order_acquire);l=r=0;
        if(!sample||sample->frames<4)return;
        auto &s=*sample;double &p=position[slot];
        double cross=std::min(s.rate*(musical?.015:2.4),double(s.frames)/8);
        if(p>=s.frames)p=cross+std::fmod(p-s.frames,s.frames-cross);
        l=at(s,p,0);r=at(s,p,1);
        if(p>=s.frames-cross){
            double head=p-(s.frames-cross);float t=float(head/cross);
            // Linear crossfade avoids a +3 dB bump for correlated ambience.
            l=l*(1-t)+at(s,head,0)*t;r=r*(1-t)+at(s,head,1)*t;
        }
        p+=s.rate/rate;
    }
public:
    struct Params{int scene;float ambient,music,distance,voice,fade,details,score;};
    std::atomic<int> targetScene{0}; // 0=none, 1=cave, 2=rain, 3=radio, 4=office, 5=twilight
    std::atomic<float> targetAmbient{.55f},targetMusic{1},targetDistance{.35f},targetVoice{.35f},targetFade{1},targetDetails{.45f},targetScore{.18f};
    bool load(int slot,const float *data,size_t frames,double sampleRate){
        if(slot<0||slot>=16||!data||frames<4||frames>48000*300||sampleRate<8000||sampleRate>192000)return false;
        auto sample=std::make_unique<Sample>();sample->frames=frames;sample->rate=sampleRate;
        sample->pcm.assign(data,data+frames*2);
        double power=0;float peak=0;
        for(float &f:sample->pcm){if(!std::isfinite(f))f=0;power+=f*f;peak=std::max(peak,std::abs(f));}
        // Match ambience perceived levels without lifting silence or flattening transients.
        double rms=std::sqrt(power/(frames*2));float target=slot>=4&&slot<=7?.2f:.13f;
        float gain=rms>1e-5 ? std::min(4.f,std::min(float(target/rms),peak>0?.85f/peak:1.f)):1.f;
        for(float &f:sample->pcm)f*=gain;
        const Sample *pointer=sample.get();retained.push_back(std::move(sample));
        banks[slot].store(pointer,std::memory_order_release);return true;
    }
    bool ready(int slot)const{return slot>=0&&slot<16&&banks[slot].load(std::memory_order_acquire)!=nullptr;}
    Params parameters()const{
        return {std::clamp(targetScene.load(),0,5),std::clamp(targetAmbient.load(),0.f,1.f),std::clamp(targetMusic.load(),0.f,1.f),std::clamp(targetDistance.load(),0.f,1.f),std::clamp(targetVoice.load(),0.f,1.f),std::clamp(targetFade.load(),0.f,1.f),std::clamp(targetDetails.load(),0.f,1.f),std::clamp(targetScore.load(),0.f,1.f)};
    }
    void prepare(double sampleRate){
        rate=sampleRate;sceneSmooth=1-std::exp(-1.f/float(rate*.55));controlSmooth=1-std::exp(-1.f/float(rate*.05));
        voiceLowCoeff=1-std::exp(-float(6.2831853*2200/rate));voiceHighCoeff=1-std::exp(-float(6.2831853*240/rate));
        position.fill(0);sceneMix.fill(0);ambient=0;music=targetMusic.load();distance=targetDistance.load();
        radioTime=0;voicePosition=0;voiceClip=0;sceneTime=0;speaking=false;filterL=filterR=cityL=cityR=voiceLP=voiceHP=0;
    }
    // Mix input music and independently spatialised location ambience.
    void next(float &l,float &r,const Params &p,float active){
        ambient+=(p.ambient-ambient)*controlSmooth;music+=(p.music-music)*controlSmooth;
        distance+=(p.distance-distance)*controlSmooth;voiceLevel+=(p.voice-voiceLevel)*controlSmooth;fade+=(p.fade-fade)*controlSmooth;
        details+=(p.details-details)*controlSmooth;score+=(p.score-score)*controlSmooth;
        sceneTime+=1/rate;
        for(int i=0;i<5;i++)sceneMix[i]+=((p.scene==i+1?1.f:0.f)-sceneMix[i])*sceneSmooth;
        float outL=0,outR=0,a,b;
        if(sceneMix[0]>.00001f){
            loop(0,a,b);outL+=a*.85f*sceneMix[0];outR+=b*.85f*sceneMix[0];
            loop(1,a,b);outL+=a*.45f*sceneMix[0];outR+=b*.45f*sceneMix[0];
        }
        float rainL=0,rainR=0;
        if(sceneMix[1]+sceneMix[2]+sceneMix[3]>.00001f)loop(2,rainL,rainR);
        outL+=rainL*sceneMix[1];outR+=rainR*sceneMix[1];
        const float broadcastMix=sceneMix[2]+sceneMix[3]*.7f;
        if(broadcastMix>.00001f){
            radioTime+=1/rate;
            if(!speaking && radioTime>3 && ready(4+voiceClip)) {speaking=true;voicePosition=0;radioTime=0;}
            float speech=0;
            if(speaking){
                const Sample *s=banks[4+voiceClip].load(std::memory_order_acquire);
                if(s&&voicePosition<s->frames){speech=(at(*s,voicePosition,0)+at(*s,voicePosition,1))*.5f;voicePosition+=s->rate/rate;}
                else{speaking=false;voiceClip=(voiceClip+1)%4;radioTime=-3;}
            }
            // Distant Japanese talk from another corner. No music bank is read here.
            voiceLP+=voiceLowCoeff*(speech-voiceLP);voiceHP+=voiceHighCoeff*(voiceLP-voiceHP);
            float radio=(std::tanh((voiceLP-voiceHP)*1.4f)*.42f*voiceLevel+noise()*.0005f)*broadcastMix;
            outL+=radio*.6f+rainL*.23f*sceneMix[2];outR+=radio+rainR*.23f*sceneMix[2];
        }else{radioTime=0;voicePosition=0;speaking=false;}
        if(sceneMix[3]>.00001f){
            float officeL=rainL*.7f,officeR=rainR*.7f;
            loop(13,a,b);cityL+=(a-cityL)*.08f;cityR+=(b-cityR)*.08f;
            officeL+=cityL*.18f;officeR+=cityR*.18f;
            // Long quiet intervals between desk activities, with soft starts and stops.
            double t=std::fmod(sceneTime,71.0);
            auto gate=[](double t,double start,double end){return float(std::clamp(std::min((t-start)/.7,(end-t)/.7),0.0,1.0));};
            float typing=gate(t,2,9)+gate(t,29,35)+gate(t,49,54);
            float writing=gate(t,15,23)+gate(t,39,45)+gate(t,61,67);
            loop(11,a,b);float keys=(a+b)*.5f*typing*details*.32f;officeL+=keys;officeR+=keys*.62f;
            loop(10,a,b);float pen=(a+b)*.5f*writing*details*.4f;officeL+=pen*.55f;officeR+=pen;
            outL+=officeL*sceneMix[3];outR+=officeR*sceneMix[3];
        }
        if(sceneMix[4]>.00001f){
            float lakeL=0,lakeR=0;
            loop(9,a,b);lakeL+=a*.65f;lakeR+=b*.65f;
            loop(8,a,b);lakeL+=a*.35f;lakeR+=b*.35f;
            loop(12,a,b);lakeL+=a*.28f;lakeR+=b*.28f;
            loop(14,a,b);lakeL+=a*details*.35f;lakeR+=b*details*.35f;
            // Sparse original piano belongs only to the lakeside scene.
            loop(3,a,b,true);lakeL+=a*score*.6f;lakeR+=b*score*.6f;
            outL+=lakeL*sceneMix[4];outR+=lakeR*sceneMix[4];
        }
        float coefficient=.72f-.65f*distance;
        filterL+=coefficient*(outL-filterL);filterR+=coefficient*(outR-filterR);
        float mid=(filterL+filterR)*.5f,width=1-.6f*distance;
        float bed=ambient*(1-.4f*distance)*fade*active;
        float musicGain=1+(music-1)*active;
        l=l*musicGain+(mid+(filterL-mid)*width)*bed;
        r=r*musicGain+(mid+(filterR-mid)*width)*bed;
    }
};
