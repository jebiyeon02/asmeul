#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include "include/AudioCore.h"
#include "DSP.hpp"
#include <unistd.h>
#include <string>
#include <cstring>

static AudioObjectPropertyAddress address(AudioObjectPropertySelector s, AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) {return {s,scope,kAudioObjectPropertyElementMain};}
template<class T> static OSStatus read(AudioObjectID object,AudioObjectPropertySelector selector,T &value,AudioObjectPropertyScope scope=kAudioObjectPropertyScopeGlobal) {
    auto a=address(selector,scope); UInt32 size=sizeof(T); return AudioObjectGetPropertyData(object,&a,0,nullptr,&size,&value);
}
struct Engine {
    AudioObjectID tap=0,device=0,output=0; AudioDeviceIOProcID proc=nullptr;
    HollowDSP dsp; std::atomic<uint64_t> callbacks{0}; double sampleRate=0; std::string error;
    void stop(){
        if(device && proc){AudioDeviceStop(device,proc);AudioDeviceDestroyIOProcID(device,proc);proc=nullptr;}
        if(device){AudioHardwareDestroyAggregateDevice(device);device=0;}
        if(tap){AudioHardwareDestroyProcessTap(tap);tap=0;}
        output=0; callbacks=0; dsp.peak=0;
    }
    ~Engine(){stop();}
    bool check(OSStatus s,const char *operation){if(s==noErr)return true;error=std::string(operation)+" ("+std::to_string(s)+")";return false;}
};
static OSStatus render(AudioObjectID,const AudioTimeStamp*,const AudioBufferList *input,const AudioTimeStamp*,AudioBufferList *output,const AudioTimeStamp*,void *context) {
    auto &e=*static_cast<Engine*>(context);
    for(UInt32 b=0;b<output->mNumberBuffers;b++)if(output->mBuffers[b].mData)std::memset(output->mBuffers[b].mData,0,output->mBuffers[b].mDataByteSize);
    // Tap channels are appended after the physical device's input channels.
    UInt32 inputChannels=0;for(UInt32 b=0;b<input->mNumberBuffers;b++)inputChannels+=input->mBuffers[b].mNumberChannels;

    const float *src[2]={}; UInt32 srcStride[2]={}; UInt32 inputFrames=UINT32_MAX,frames=UINT32_MAX,channel=0;
    for(UInt32 b=0;b<input->mNumberBuffers;b++) {
        auto &buffer=input->mBuffers[b];
        for(UInt32 c=0;c<buffer.mNumberChannels;c++,channel++)if(inputChannels>=2 && channel>=inputChannels-2 && buffer.mData){
            UInt32 n=channel-(inputChannels-2);src[n]=static_cast<const float*>(buffer.mData)+c;srcStride[n]=buffer.mNumberChannels;
            inputFrames=std::min(inputFrames,buffer.mDataByteSize/(UInt32(sizeof(float))*buffer.mNumberChannels));
        }
    }
    float *dst[2]={};UInt32 dstStride[2]={};channel=0;
    for(UInt32 b=0;b<output->mNumberBuffers;b++){
        auto &buffer=output->mBuffers[b];
        for(UInt32 c=0;c<buffer.mNumberChannels;c++,channel++)if(channel<2&&buffer.mData){dst[channel]=static_cast<float*>(buffer.mData)+c;dstStride[channel]=buffer.mNumberChannels;frames=std::min(frames,buffer.mDataByteSize/(UInt32(sizeof(float))*buffer.mNumberChannels));}
    }
    if(!dst[0]||!dst[1]||frames==UINT32_MAX)return noErr;
    auto parameters=e.dsp.parameters();float peak=0;
    for(UInt32 f=0;f<frames;f++){
        float l,r;e.dsp.process(src[0]&&f<inputFrames?src[0][f*srcStride[0]]:0,src[1]&&f<inputFrames?src[1][f*srcStride[1]]:0,l,r,parameters);
        dst[0][f*dstStride[0]]=l;dst[1][f*dstStride[1]]=r;peak=std::max(peak,std::max(std::abs(l),std::abs(r)));
    }
    e.dsp.peak.store(peak,std::memory_order_relaxed);e.callbacks.fetch_add(1,std::memory_order_relaxed);return noErr;
}
static bool validateStreams(Engine &e,AudioObjectPropertyScope scope) {
    auto a=address(kAudioDevicePropertyStreams,scope);UInt32 size=0;
    if(!e.check(AudioObjectGetPropertyDataSize(e.device,&a,0,nullptr,&size),"Read streams"))return false;
    std::vector<AudioStreamID> streams(size/sizeof(AudioStreamID));
    if(!e.check(AudioObjectGetPropertyData(e.device,&a,0,nullptr,&size,streams.data()),"Read streams"))return false;
    UInt32 channels=0;
    for(auto stream:streams){AudioStreamBasicDescription f={};if(!e.check(read(stream,kAudioStreamPropertyVirtualFormat,f),"Read format"))return false;
        if(f.mFormatID!=kAudioFormatLinearPCM || !(f.mFormatFlags&kAudioFormatFlagIsFloat) || f.mBitsPerChannel!=32 || f.mSampleRate!=e.sampleRate){e.error="Unsupported audio format. Use a stereo output at 44.1, 48 or 96 kHz.";return false;}channels+=f.mChannelsPerFrame;}
    if(channels<2){e.error="A stereo output device is required.";return false;}return true;
}
extern "C" {
HollowEngine hollow_create(){return new Engine;}
void hollow_destroy(HollowEngine e){delete static_cast<Engine*>(e);}
void hollow_stop(HollowEngine e){static_cast<Engine*>(e)->stop();}
int32_t hollow_start(HollowEngine raw,uint32_t process) {
    auto &e=*static_cast<Engine*>(raw);e.stop();e.error.clear();
    auto fail=[&](){e.stop();return int32_t(-1);};
    if(!e.check(read(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,e.output),"Default output")||!e.output)return fail();
    CFStringRef uid=nullptr;
    if(!e.check(read(e.output,kAudioDevicePropertyDeviceUID,uid),"Output UID"))return fail();
    NSString *outputUID=CFBridgingRelease(uid);
    if(!e.check(read(e.output,kAudioDevicePropertyNominalSampleRate,e.sampleRate),"Sample rate"))return fail();
    pid_t pid=getpid();AudioObjectID own=0;UInt32 size=sizeof(own);auto a=address(kAudioHardwarePropertyTranslatePIDToProcessObject);
    if(!e.check(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,sizeof(pid),&pid,&size,&own),"Exclude ASMEUL")||!own){e.error="Cannot identify ASMEUL's audio process safely.";return fail();}
    CATapDescription *description=process?[[CATapDescription alloc] initStereoMixdownOfProcesses:@[@(process)]]:[[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[@(own)]];
    description.name=@"ASMEUL Live Audio";description.privateTap=YES;description.muteBehavior=CATapMutedWhenTapped;
    if(!e.check(AudioHardwareCreateProcessTap(description,&e.tap),"Create audio tap"))return fail();
    NSDictionary *config=@{@kAudioAggregateDeviceNameKey:@"ASMEUL Private Output",@kAudioAggregateDeviceUIDKey:NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey:@YES,@kAudioAggregateDeviceMainSubDeviceKey:outputUID,
        @kAudioAggregateDeviceSubDeviceListKey:@[@{@kAudioSubDeviceUIDKey:outputUID}],
        @kAudioAggregateDeviceTapListKey:@[@{@kAudioSubTapUIDKey:description.UUID.UUIDString,@kAudioSubTapDriftCompensationKey:@YES}],
        @kAudioAggregateDeviceTapAutoStartKey:@YES};
    if(!e.check(AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)config,&e.device),"Create aggregate"))return fail();
    if(!validateStreams(e,kAudioObjectPropertyScopeInput)||!validateStreams(e,kAudioObjectPropertyScopeOutput))return fail();
    e.dsp.prepare(e.sampleRate);
    if(!e.check(AudioDeviceCreateIOProcID(e.device,render,&e,&e.proc),"Create audio callback"))return fail();
    if(!e.check(AudioDeviceStart(e.device,e.proc),"Start audio"))return fail();return 0;
}
void hollow_configure(HollowEngine raw,float space,float warmth,float orbit,float gain,int bypass){auto &d=static_cast<Engine*>(raw)->dsp;d.targetSpace=space;d.targetWarmth=warmth;d.targetOrbit=orbit;d.targetGain=gain;d.bypass=bypass;}
void hollow_render_offline(HollowEngine raw,float *output,uint32_t frames,double rate){auto &e=*static_cast<Engine*>(raw);if(e.proc||!output||rate<8000||rate>192000)return;e.dsp.prepare(rate);auto p=e.dsp.parameters();for(uint32_t i=0;i<frames;i++)e.dsp.process(0,0,output[i*2],output[i*2+1],p);}
int hollow_load_sound(HollowEngine e,int slot,const float *stereo,uint32_t frames,double rate){return static_cast<Engine*>(e)->dsp.soundscape.load(slot,stereo,frames,rate)?1:0;}
int hollow_begin_sound(HollowEngine e,int slot,uint32_t frames,double rate){return static_cast<Engine*>(e)->dsp.soundscape.begin(slot,frames,rate);}
int hollow_append_sound(HollowEngine e,int slot,const float *data,uint32_t frames){return static_cast<Engine*>(e)->dsp.soundscape.append(slot,data,frames);}
int hollow_finish_sound(HollowEngine e,int slot){return static_cast<Engine*>(e)->dsp.soundscape.finish(slot);}
void hollow_track_gain(HollowEngine e,int slot,float gain){if(slot>=0&&slot<32)static_cast<Engine*>(e)->dsp.soundscape.targetGains[slot]=std::isfinite(gain)?std::clamp(gain,0.f,1.f):0;}
void hollow_mix(HollowEngine e,float ambience,float music,float fade){auto &s=static_cast<Engine*>(e)->dsp.soundscape;s.targetAmbient=ambience;s.targetMusic=music;s.targetFade=fade;}
float hollow_peak(HollowEngine e){return static_cast<Engine*>(e)->dsp.peak.load();}
uint64_t hollow_callbacks(HollowEngine e){return static_cast<Engine*>(e)->callbacks.load();}
uint32_t hollow_output_device(HollowEngine e){return static_cast<Engine*>(e)->output;}
double hollow_sample_rate(HollowEngine e){return static_cast<Engine*>(e)->sampleRate;}
const char *hollow_error(HollowEngine e){return static_cast<Engine*>(e)->error.c_str();}
}

void hollow_spatial(HollowEngine raw,int enabled){static_cast<Engine*>(raw)->dsp.soundscape.targetSpatial=enabled!=0;}
void hollow_position(HollowEngine raw,int slot,int direction,float distance){if(slot<0||slot>=32)return;auto &s=static_cast<Engine*>(raw)->dsp.soundscape;s.targetDirections[slot]=std::clamp(direction,0,6);s.targetDistances[slot]=std::isfinite(distance)?std::clamp(distance,0.f,1.f):0;}
