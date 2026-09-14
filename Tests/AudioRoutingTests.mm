#include "../Sources/AudioCore/Engine.mm"
#include <cassert>
#include <iostream>
#include <thread>

int main(){
    AudioRing ring;
    float l=1,r=1;ring.pop(l,r);assert(l==0 && r==0);
    for(int i=0;i<16384;i++)assert(ring.push(float(i),-float(i)));
    assert(!ring.push(1,1));
    for(int i=0;i<16384;i++){ring.pop(l,r);assert(l==i && r==-i);}
    std::thread producer([&]{for(int i=1;i<=100000;i++)while(!ring.push(float(i),-float(i)))std::this_thread::yield();});
    for(int i=1;i<=100000;){ring.pop(l,r);if(l!=0){assert(l==i && r==-i);i++;}}
    producer.join();
    Engine e;
    std::vector<float> sound(8192,0.2f),out(8192);
    assert(asmeul_load_sound(&e,0,sound.data(),4096,48000));
    asmeul_configure(&e,0,0,0,1,0);asmeul_spatial(&e,0);
    asmeul_mix(&e,1,1,1);asmeul_track_gain(&e,0,1);
    e.dsp.prepare(48000);
    AudioBufferList output={1,{{2,UInt32(out.size()*sizeof(float)),out.data()}}};
    // An inactive selected app never calls capture. Output must still render ASMR.
    for(int i=0;i<20;i++)render(0,nullptr,nullptr,nullptr,&output,nullptr,&e);
    assert(e.callbacks==20 && e.dsp.peak>0.01f);
    asmeul_track_gain(&e,0,0);
    for(int i=0;i<30;i++)render(0,nullptr,nullptr,nullptr,&output,nullptr,&e);
    assert(e.dsp.peak<0.001f);
    // Permission denial can deliver valid, zero-filled callbacks. Neither
    // those nor invalid samples may arm the tap and silence the source.
    std::vector<float> silence(8192,0),invalid(8192,NAN);
    AudioBufferList denied={1,{{2,UInt32(silence.size()*sizeof(float)),silence.data()}}};
    AudioBufferList bad={1,{{2,UInt32(invalid.size()*sizeof(float)),invalid.data()}}};
    capture(0,nullptr,nullptr,nullptr,nullptr,nullptr,&e);
    capture(0,nullptr,&denied,nullptr,nullptr,nullptr,&e);
    capture(0,nullptr,&bad,nullptr,nullptr,nullptr,&e);
    assert(!e.inputSignal && !e.routingInput);
    AudioBufferList input={1,{{2,UInt32(sound.size()*sizeof(float)),sound.data()}}};
    capture(0,nullptr,&input,nullptr,nullptr,nullptr,&e);
    assert(e.inputSignal && !e.routingInput);
    render(0,nullptr,nullptr,nullptr,&output,nullptr,&e);
    assert(e.dsp.peak<0.001f); // No duplicate playback while original is audible.
    e.routingInput=true; // Simulate a successful control-thread mute handoff.
    capture(0,nullptr,&input,nullptr,nullptr,nullptr,&e);
    render(0,nullptr,nullptr,nullptr,&output,nullptr,&e);
    assert(e.dsp.peak>0.1f);
    render(0,nullptr,nullptr,nullptr,&output,nullptr,&e);
    assert(e.dsp.peak<0.001f);
    asmeul_track_gain(&e,0,1);
    for(int i=0;i<20;i++){
        capture(0,nullptr,&input,nullptr,nullptr,nullptr,&e);
        render(0,nullptr,nullptr,nullptr,&output,nullptr,&e);
    }
    assert(out.back()>0.39f && out.back()<0.41f); // Music + ASMR, independently audible.
    asmeul_stop(&e);
    assert(!e.inputSignal && !e.routingInput);
    std::cout<<"PASS: concurrent queue, ASMR without capture, denied capture preserves original, no duplicate playback, music + ASMR and restart reset\n";
}
