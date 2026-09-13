"""Original 32-bar slow jazz-style bed; no borrowed composition or samples. Requires numpy."""
from pathlib import Path
import numpy as np
import wave
rng = np.random.default_rng(731204)
sr=48000; beat=60/68; bars=32; duration=bars*4*beat
n=int(duration*sr); mix=np.zeros((n,2),np.float64)
def add(signal,at,pan=0):
    start=int(at*sr); idx=(np.arange(len(signal))+start)%n
    mix[idx,0]+=signal*np.sqrt((1-pan)/2)
    mix[idx,1]+=signal*np.sqrt((1+pan)/2)
def note(midi,at,length,amp,pan=0,kind='keys'):
    t=np.arange(int(length*sr))/sr; f=440*2**((midi-69)/12)
    if kind=='bass':
        y=(np.sin(2*np.pi*f*t)+.22*np.sin(4*np.pi*f*t))*np.exp(-t*2.6)
        y*=1-np.exp(-t*90)
    else:
        y=np.sin(2*np.pi*f*t+.7*np.exp(-t*3)*np.sin(2*np.pi*f*t))
        y+=.16*np.sin(2*np.pi*f*3*t)*np.exp(-t*5)
        y*=(1-np.exp(-t*130))*np.exp(-t/1.7)
        y*=1+.04*np.sin(2*np.pi*3.2*t)
    y*=np.minimum(1,(length-t)/.15)*amp
    add(y,at,pan)
# Original voicings: Dm9, G13, Cmaj9, A7(b9), with gentle substitutions.
chords=[[53,60,64,69],[53,59,64,69],[52,59,62,67],[55,61,64,70],
        [53,57,60,64],[53,59,62,69],[52,55,59,62],[55,58,61,64]]
roots=[38,43,36,33,38,43,36,33]
for bar in range(bars):
    start=bar*4*beat; chord=chords[bar%8]
    for hit,velocity in [(0,.043),(2.62,.028)]:
        for j,m in enumerate(chord): note(m,start+hit*beat+j*.012,3.5,velocity*(.9+rng.random()*.2),-.25+j*.14)
    for b,interval in [(0,0),(1.95,7),(3,12)]:note(roots[bar%8]+interval,start+b*beat,1.8,.055,0,'bass')
    if bar%2==1:
        for j,m in enumerate([chord[-1]+12,chord[-2]+12,chord[-1]+10]):
            note(m,start+(1+j*.65)*beat,2.2,.014,0.18)
    for b in [0,1,2,3]:
        t=np.arange(int(.13*sr))/sr
        noise=rng.normal(0,1,len(t));noise=np.convolve(np.diff(noise,prepend=noise[0]),np.ones(5)/5,mode='same')
        add(noise*np.exp(-t*36)*(1-np.exp(-t*120))*.007,start+b*beat+.025,-.3)
# Small room reflections, stable periodic boundary.
freq=np.fft.rfftfreq(n,1/sr)
mix=np.fft.irfft(np.fft.rfft(mix,axis=0)/(1+(freq[:,None]/5200)**4),n=n,axis=0)
for delay,level in [(.047,.1),(.081,.065),(.139,.045)]:mix+=np.roll(mix,int(delay*sr),axis=0)[:,::-1]*level
mix*=.16/max(np.sqrt(np.mean(mix**2)),.001)
mix=np.tanh(mix*1.05)/1.05
path=Path(__file__).resolve().parents[1]/'Sources/Hollow/Resources/radio-jazz.wav'
with wave.open(str(path),'wb') as file:
    file.setnchannels(2);file.setsampwidth(2);file.setframerate(sr)
    file.writeframes((np.clip(mix,-1,1)*32767).astype('<i2').tobytes())
print(f'{path}: {duration:.1f}s original stereo bed')
