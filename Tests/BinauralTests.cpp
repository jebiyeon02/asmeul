#include "../Sources/AudioCore/Binaural.hpp"
#include <cassert>
#include <iostream>
#include <vector>
std::vector<float> impulse(int direction,double rate){Binaural b;b.prepare(rate);float l=0,r=0;for(int i=0;i<rate;i++)b.process(l,r,true,direction,0);std::vector<float> out;for(int i=0;i<2048;i++){l=r=i==0?.5f:0;b.process(l,r,true,direction,0);assert(std::isfinite(l)&&std::isfinite(r));out.push_back(l);out.push_back(r);}return out;}
int main(){for(double rate:{44100.,48000.,96000.}){
 auto left=impulse(1,rate),right=impulse(2,rate),front=impulse(0,rate),back=impulse(5,rate),up=impulse(6,rate);
 double el=0,er=0,fb=0,fu=0;for(int i=0;i<300;i++){el+=left[i*2]*left[i*2];er+=left[i*2+1]*left[i*2+1];fb+=std::abs(front[i*2]-back[i*2]);fu+=std::abs(front[i*2]-up[i*2]);}
 assert(el>er*1.5&&fb>.01&&fu>.01);
 Binaural b;b.prepare(rate);float l=.3,r=-.1;b.process(l,r,false,0,0);assert(l==.3f&&r==-.1f);
 for(int i=0;i<rate;i++){l=r=.1;b.process(l,r,true,(i/2000)%7,.5);assert(std::isfinite(l)&&std::isfinite(r));}
 for(int i=0;i<rate;i++){l=.3;r=-.1;b.process(l,r,false,0,0);}assert(std::abs(l-.3)<1e-4&&std::abs(r+.1)<1e-4);
 std::cout<<"PASS HRTF "<<rate<<": left/right energy "<<el/er<<", distinct front/back/elevation, transition and off transparency\n";
}}
