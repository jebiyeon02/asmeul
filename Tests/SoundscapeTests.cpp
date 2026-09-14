#include "../Sources/AudioCore/Soundscape.hpp"
#include <cassert>
#include <iostream>
int main(){
 for(double rate:{44100.,48000.,96000.}){
  Soundscape a,b,both;std::vector<float>x(16000,.2f),y(16000,.1f);
  for(auto*s:{&a,&b,&both}){assert(s->load(0,x.data(),8000,8000));assert(s->load(1,y.data(),8000,8000));s->targetAmbient=1;s->prepare(rate);}
  a.targetGains[0]=.5;b.targetGains[1]=.7;both.targetGains[0]=.5;both.targetGains[1]=.7;
  auto pa=a.parameters(),pb=b.parameters(),pc=both.parameters();float al,ar,bl,br,cl,cr;
  for(int i=0;i<rate*3;i++){al=ar=bl=br=cl=cr=0;a.next(al,ar,pa,1);b.next(bl,br,pb,1);both.next(cl,cr,pc,1);assert(std::abs(cl-al-bl)<1e-5);assert(std::abs(cr-ar-br)<1e-5);}
  assert(cl>.16);both.targetGains[0]=0;pc=both.parameters();for(int i=0;i<rate;i++){cl=cr=0;both.next(cl,cr,pc,1);}assert(std::abs(cl-bl)<1e-4);
  cl=.3;cr=-.2;both.next(cl,cr,pc,0);assert(cl==.3f&&cr==-.2f);
  both.targetFade=0;pc=both.parameters();for(int i=0;i<rate;i++){cl=cr=0;both.next(cl,cr,pc,1);}assert(std::abs(cl)<1e-5);
  assert(!both.begin(-1,10,rate));assert(!both.append(3,x.data(),4));assert(!both.finish(3));assert(both.begin(3,4,rate));assert(!both.append(3,x.data(),5));assert(both.append(3,x.data(),4));assert(both.finish(3));
  Soundscape reload;
  assert(reload.load(3,x.data(),8000,rate));reload.targetGains[3]=.5f;reload.targetAmbient=1;reload.prepare(rate);
  auto rp=reload.parameters();float rl=0,rr=0;reload.next(rl,rr,rp,1);assert(std::isfinite(rl)&&std::isfinite(rr));
  reload.unload(3);rp=reload.parameters();for(int i=0;i<64;i++){rl=rr=0;reload.next(rl,rr,rp,1);assert(std::isfinite(rl)&&std::isfinite(rr));}
  reload.reclaimRetired();
 }
 std::cout<<"PASS: simultaneous additive tracks, independent deselection, looping, bypass, fade and chunk validation at 3 rates\n";
}
