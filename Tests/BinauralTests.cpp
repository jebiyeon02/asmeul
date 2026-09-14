#include "../Sources/AudioCore/Binaural.hpp"
#include <cassert>
#include <iostream>
#include <vector>
void verifySharedKernels(){
 for(double rate:{44100.,48000.,96000.,192000.}){
  std::array<Binaural,3> shared,independent;
  auto bank=std::make_shared<const Binaural::KernelBank>(rate);
  for(int voice=0;voice<3;voice++){shared[voice].prepare(bank);independent[voice].prepare(rate);}
  // Voices own the coefficients even after the preparation scope exits.
  bank.reset();
  for(int frame=0;frame<16384;frame++){
   // Re-preparing one voice must not change other voices sharing its old bank.
   if(frame==8192){shared[0].prepare(44100.);independent[0].prepare(44100.);}
   for(int voice=0;voice<3;voice++){
    float l=.2f*std::sin(float(frame+voice)*.071f),r=.1f*std::cos(float(frame-voice)*.093f),a=l,b=r;
    bool enabled=(frame/2048+voice)%3!=2;
    int direction=(frame/997+voice)%7;
    float distance=float((frame/701+voice)%11)/10;
    shared[voice].process(l,r,enabled,direction,distance);
    independent[voice].process(a,b,enabled,direction,distance);
    assert(std::isfinite(l)&&std::isfinite(r)&&l==a&&r==b);
   }
  }
 }
 std::cout<<"PASS: shared coefficients preserve independent voice histories, transitions, lifetime and sample-rate resets at 4 rates\n";
}
std::vector<float> impulse(int direction,double rate){Binaural b;b.prepare(rate);float l=0,r=0;for(int i=0;i<rate;i++)b.process(l,r,true,direction,0);std::vector<float> out;for(int i=0;i<2048;i++){l=r=i==0?.5f:0;b.process(l,r,true,direction,0);assert(std::isfinite(l)&&std::isfinite(r));out.push_back(l);out.push_back(r);}return out;}
int main(){verifySharedKernels();for(double rate:{44100.,48000.,96000.}){
 auto left=impulse(1,rate),right=impulse(2,rate),front=impulse(0,rate),back=impulse(5,rate),up=impulse(6,rate);
 double el=0,er=0,fb=0,fu=0;for(int i=0;i<300;i++){el+=left[i*2]*left[i*2];er+=left[i*2+1]*left[i*2+1];fb+=std::abs(front[i*2]-back[i*2]);fu+=std::abs(front[i*2]-up[i*2]);}
 assert(el>er*1.5&&fb>.01&&fu>.01);
 Binaural b;b.prepare(rate);float l=.3,r=-.1;b.process(l,r,false,0,0);assert(l==.3f&&r==-.1f);
 for(int i=0;i<rate;i++){l=r=.1;b.process(l,r,true,(i/2000)%7,.5);assert(std::isfinite(l)&&std::isfinite(r));}
 for(int i=0;i<rate;i++){l=.3;r=-.1;b.process(l,r,false,0,0);}assert(std::abs(l-.3)<1e-4&&std::abs(r+.1)<1e-4);
 std::cout<<"PASS HRTF "<<rate<<": left/right energy "<<el/er<<", distinct front/back/elevation, transition and off transparency\n";
}}
