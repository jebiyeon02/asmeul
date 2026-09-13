#include "../Sources/AudioCore/DSP.hpp"
#include <cassert>
#include <iostream>
#include <limits>
double lateTail(float space){
 HollowDSP d;d.targetSpace=space;d.targetWarmth=0;d.targetGain=.7;d.prepare(48000);auto p=d.parameters();float l,r;
 for(int i=0;i<48000;i++)d.process(0,0,l,r,p);
 double energy=0;for(int i=0;i<48000*7;i++){d.process(i==0?.5f:0,i==0?.5f:0,l,r,p);if(i>48000)energy+=l*l+r*r;}return energy;
}
double toneEnergy(float warmth){
 HollowDSP d;d.targetSpace=0;d.targetWarmth=warmth;d.targetGain=.7;d.prepare(48000);auto p=d.parameters();float l,r;double energy=0;
 for(int i=0;i<96000;i++){float x=.2f*std::sin(6.2831853*6000*i/48000);d.process(x,x,l,r,p);if(i>48000)energy+=l*l+r*r;}return energy;
}
int main(){
 double shortTail=lateTail(.4f),longTail=lateTail(1);assert(longTail>shortTail*5);
 double clear=toneEnergy(0),dark=toneEnergy(1);assert(dark<clear*.05);
 HollowDSP orbit;orbit.targetSpace=0;orbit.targetWarmth=0;orbit.targetOrbit=1;orbit.prepare(48000);auto op=orbit.parameters();float ol,orr;double ratio=1;
 for(int i=0;i<48000*8;i++){orbit.process(.1f,.1f,ol,orr,op);if(i>48000)ratio=std::max(ratio,double(std::max(std::abs(ol),std::abs(orr))/(std::min(std::abs(ol),std::abs(orr))+1e-6f)));}assert(ratio>10);
 HollowDSP neutral;neutral.targetSpace=neutral.targetWarmth=neutral.targetOrbit=0;neutral.targetGain=.7;neutral.prepare(48000);auto np=neutral.parameters();
 for(int i=0;i<48000;i++)neutral.process(.2f,-.1f,ol,orr,np);assert(std::abs(ol-.14f)<1e-5&&std::abs(orr+.07f)<1e-5);
 std::cout<<"PASS: long tail ratio "<<longTail/shortTail<<", warmth HF ratio "<<dark/clear<<", orbit channel ratio "<<ratio<<", neutral transparency\n";

    for(double rate:{44100.,48000.,96000.})for(float space:{.1f,.4f,1.f}){
        HollowDSP dsp;dsp.prepare(rate);dsp.targetSpace=space;dsp.targetOrbit=.5f;
        float l=0,r=0;auto p=dsp.parameters();
        for(int i=0;i<int(rate);i++)dsp.process(0,0,l,r,p);
        double tail=0;
        for(int i=0;i<int(rate*4);i++){
            dsp.process(i==0?.8f:0,i==0?.8f:0,l,r,p);
            assert(std::isfinite(l)&&std::isfinite(r));assert(std::abs(l)<=.95f&&std::abs(r)<=.95f);
            if(i>rate*.02)tail+=l*l+r*r;
        }
        assert(tail>0.00001);
        dsp.bypass=1;dsp.targetGain=.7f;p=dsp.parameters();
        for(int i=0;i<int(rate);i++)dsp.process(.2f,-.1f,l,r,p);
        assert(std::abs(l-.14f)<.0001f&&std::abs(r+.07f)<.0001f);
        dsp.process(std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity(),l,r,p);
        assert(std::isfinite(l)&&std::isfinite(r));
        dsp.bypass=0;dsp.targetSpace=1.f;dsp.targetGain=1;p=dsp.parameters();
        for(int i=0;i<int(rate);i++){dsp.process(100,-100,l,r,p);assert(std::isfinite(l)&&std::isfinite(r)&&std::abs(l)<=.95f&&std::abs(r)<=.95f);}
    }
    std::cout<<"PASS: 3 space settings × 3 sample rates; reverb tails, finite output, bypass accuracy, peak ceiling\n";
}
