#pragma once
#include "HRTFData.hpp"
#include <array>
#include <cmath>
#include <algorithm>
// Measured HRIR convolution, no allocation in render. Seven fixed directions.
class Binaural {
 std::array<float,1024> history{};
 std::array<std::array<std::array<float,768>,2>,7> kernels{};
 std::array<float,7> weights{};
 int cursor=0,taps=128;float smooth=.001f,wet=0,dist=0;
public:
 void prepare(double rate){
  history.fill(0);weights.fill(0);weights[0]=1;cursor=0;wet=dist=0;
  smooth=1-std::exp(-1.f/float(rate*.04));taps=std::min(768,int(std::ceil(128*rate/44100)));
  for(int d=0;d<7;d++)for(int c=0;c<2;c++)for(int i=0;i<taps;i++){
   double pos=i*44100/rate;int a=int(pos);float t=float(pos-a);
   kernels[d][c][i]=(a<128?((1-t)*hrir[d][c][a]+(a+1<128?t*hrir[d][c][a+1]:0)):0)/32768.f*float(44100/rate);
  }
 }
 void process(float &l,float &r,bool enabled,int direction,float distance){
  direction=std::clamp(direction,0,6);wet+=((enabled?1.f:0.f)-wet)*smooth;dist+=(distance-dist)*smooth;
  for(int d=0;d<7;d++)weights[d]+=((d==direction?1.f:0.f)-weights[d])*smooth;
  history[cursor]=(l+r)*.5f;
  if(wet>.00001f){
   float a=0,b=0;
   for(int d=0;d<7;d++)if(weights[d]>.00001f){
    float x=0,y=0;for(int j=0;j<taps;j++){float h=history[(cursor-j+1024)%1024];x+=h*kernels[d][0][j];y+=h*kernels[d][1][j];}
    a+=x*weights[d];b+=y*weights[d];
   }
   // Low-level cross reflections provide an external room cue; distance sets
   // direct/reflected ratio and attenuation, not a calibrated metre estimate.
   float echo=history[(cursor-std::min(1000,taps*2)+1024)%1024];
   float attenuation=1/(1+dist*1.7f);
   a=(a+echo*(.04f+dist*.12f))*attenuation;
   b=(b+history[(cursor-std::min(1000,taps*3)+1024)%1024]*(.04f+dist*.12f))*attenuation;
   l+=(a-l)*wet;r+=(b-r)*wet;
  }
  cursor=(cursor+1)%1024;
 }
};
