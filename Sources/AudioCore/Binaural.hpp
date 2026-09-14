#pragma once
#include "HRTFData.hpp"
#include <Accelerate/Accelerate.h>
#include <array>
#include <cmath>
#include <algorithm>
#include <memory>
// Measured HRIR convolution, no allocation in render. Seven fixed directions.
class Binaural {
public:
 // All voices at one output rate use the same immutable coefficients. Build
 // these only during preparation; each voice keeps its own playback history.
 struct KernelBank {
  std::array<std::array<std::array<float,768>,2>,7> values{};
  int taps;
  float smooth;
  explicit KernelBank(double rate):taps(std::min(768,int(std::ceil(128*rate/44100)))),smooth(1-std::exp(-1.f/float(rate*.04))){
   for(int d=0;d<7;d++)for(int c=0;c<2;c++)for(int i=0;i<taps;i++){
    double pos=i*44100/rate;int a=int(pos);float t=float(pos-a);
    values[d][c][i]=(a<128?((1-t)*hrir[d][c][a]+(a+1<128?t*hrir[d][c][a+1]:0)):0)/32768.f*float(44100/rate);
   }
  }
 };
private:
 static constexpr int historySize=1024;
 static constexpr int historyMask=historySize-1;
 // Mirrored history makes newest-to-oldest samples contiguous at every cursor,
 // allowing Accelerate to vectorize the FIR without per-tap ring indexing.
 std::array<float,2048> history{};
 std::shared_ptr<const KernelBank> kernels;
 std::array<float,7> weights{};
 int cursor=0,taps=128;float smooth=.001f,wet=0,dist=0;
public:
 void prepare(double rate){
  prepare(std::make_shared<const KernelBank>(rate));
 }
 void prepare(std::shared_ptr<const KernelBank> bank){
  kernels=std::move(bank);
  history.fill(0);weights.fill(0);weights[0]=1;cursor=0;wet=dist=0;
  smooth=kernels->smooth;taps=kernels->taps;
 }
 void process(float &l,float &r,bool enabled,int direction,float distance){
  direction=std::clamp(direction,0,6);wet+=((enabled?1.f:0.f)-wet)*smooth;dist+=(distance-dist)*smooth;
  for(int d=0;d<7;d++)weights[d]+=((d==direction?1.f:0.f)-weights[d])*smooth;
  history[cursor]=history[cursor+historySize]=(l+r)*.5f;
  // Keep the history and control smoothing warm while spatial audio is off,
  // but avoid the convolution work once the wet path has faded out.
  if(wet>.00001f){
   float a=0,b=0;
   for(int d=0;d<7;d++)if(weights[d]>.00001f){
    float x=0,y=0;
    vDSP_dotpr(history.data()+cursor,1,kernels->values[d][0].data(),1,&x,vDSP_Length(taps));
    vDSP_dotpr(history.data()+cursor,1,kernels->values[d][1].data(),1,&y,vDSP_Length(taps));
    a+=x*weights[d];b+=y*weights[d];
   }
   // Low-level cross reflections provide an external room cue; distance sets
   // direct/reflected ratio and attenuation, not a calibrated metre estimate.
   float echo=history[(cursor+std::min(1000,taps*2))&historyMask];
   float attenuation=1/(1+dist*1.7f);
   a=(a+echo*(.04f+dist*.12f))*attenuation;
   b=(b+history[(cursor+std::min(1000,taps*3))&historyMask]*(.04f+dist*.12f))*attenuation;
   l+=(a-l)*wet;r+=(b-r)*wet;
  }
  cursor=(cursor-1+historySize)&historyMask;
 }
};
