#pragma once
#include <array>
#include <atomic>
#include <cstdint>

// One tap producer and one independently clocked output consumer. Neither
// callback waits for the other; an idle music app simply supplies silence.
class AudioRing {
    static constexpr uint32_t capacity=16384;
    std::array<std::array<float,2>,capacity> samples{};
    std::atomic<uint32_t> written{0},consumed{0};
public:
    void reset(){written=0;consumed=0;}
    bool push(float l,float r){
        auto w=written.load(std::memory_order_relaxed);
        if(w-consumed.load(std::memory_order_acquire)>=capacity)return false;
        samples[w%capacity]={l,r};written.store(w+1,std::memory_order_release);return true;
    }
    void pop(float &l,float &r){
        auto c=consumed.load(std::memory_order_relaxed);
        if(c==written.load(std::memory_order_acquire)){l=r=0;return;}
        l=samples[c%capacity][0];r=samples[c%capacity][1];
        consumed.store(c+1,std::memory_order_release);
    }
};
