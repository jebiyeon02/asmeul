"""Original sparse twilight score and distant bell/wood design. No reference melody sampled."""
from pathlib import Path
import wave
import numpy as np
rng=np.random.default_rng(42179);sr=48000;n=sr*96
piano=np.zeros((n,2));details=np.zeros((n,2));root=Path(__file__).resolve().parents[1]/'Sources/Hollow/Resources'
def add(track,signal,at,pan):
 i=(np.arange(len(signal))+int(at*sr))%n
 track[i,0]+=signal*np.sqrt((1-pan)/2);track[i,1]+=signal*np.sqrt((1+pan)/2)
def note(midi,at,velocity=.045):
 t=np.arange(sr*7)/sr;f=440*2**((midi-69)/12)
 y=sum(a*np.sin(2*np.pi*f*h*t)*np.exp(-t*(.48+h*.16)) for h,a in [(1,1),(2,.25),(3,.10),(4,.035)])
 y*= (1-np.exp(-t*160))*velocity
 add(piano,y,at,float(rng.uniform(-.3,.3)))
# Spacious, original, non-melodic voicings; long gaps leave the landscape audible.
for at,notes in [(2,[50,57,64]),(14,[53,60,67]),(28,[48,55,62]),(42,[45,52,59]),(57,[50,57,65]),(72,[48,55,64]),(86,[53,60,69])]:
 for j,m in enumerate(notes):note(m,at+j*.65,.038 if j else .055)
for at,midi,pan in [(9,86,-.6),(37,81,.7),(65,88,-.45),(88,83,.5)]:
 t=np.arange(sr*6)/sr;f=440*2**((midi-69)/12)
 bell=(np.sin(2*np.pi*f*t)*np.exp(-t*1.3)+.25*np.sin(2*np.pi*f*2.756*t)*np.exp(-t*2))*(1-np.exp(-t*180))*.025
 add(details,bell,at,pan)
 for offset in [1.2,1.47,2.05]:
  t=np.arange(int(sr*.12))/sr
  wood=(np.sin(2*np.pi*730*t)+.3*np.sin(2*np.pi*1250*t))*np.exp(-t*70)*(1-np.exp(-t*800))*.02
  add(details,wood,at+offset,-pan)
for track,name in [(piano,'twilight-piano'),(details,'memory-chimes')]:
 # Many quiet, decorrelated reflections for distant, indistinct placement.
 original=track.copy()
 for delay,amp in [(.13,.23),(.241,.16),(.389,.11),(.613,.07),(.997,.04)]:track+=np.roll(original,int(delay*sr),axis=0)[:,::-1]*amp
 freq=np.fft.rfftfreq(n,1/sr);track=np.fft.irfft(np.fft.rfft(track,axis=0)/(1+(freq[:,None]/(4200 if name=='twilight-piano' else 2600))**4),n=n,axis=0)
 with wave.open(str(root/(name+'.wav')),'wb') as file:
  file.setnchannels(2);file.setsampwidth(2);file.setframerate(sr);file.writeframes((np.clip(track,-1,1)*32767).astype('<i2').tobytes())
 print(name, '96s')
