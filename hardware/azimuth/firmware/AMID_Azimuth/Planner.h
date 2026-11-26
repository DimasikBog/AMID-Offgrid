#pragma once
#include <stdint.h>
struct Quality {
  int16_t rss[5],snr[5]; uint32_t ids[5]; uint8_t n=0;
  void clear(){n=0;}
  bool add(uint32_t id,int16_t r,int16_t s){
    if(!id || n>=5 || r<-1500 || r>=0 || s<-300 || s>300)return false;
    for(uint8_t i=0;i<n;i++)if(ids[i]==id)return false;
    ids[n]=id;rss[n]=r;snr[n]=s;n++;return true;
  }
  static int16_t median(const int16_t *v,uint8_t count){int16_t a[5];for(uint8_t i=0;i<count;i++)a[i]=v[i];for(uint8_t i=1;i<count;i++){int16_t x=a[i];int8_t j=i-1;while(j>=0&&a[j]>x){a[j+1]=a[j];j--;}a[j+1]=x;}return count%2?a[count/2]:(a[count/2-1]+a[count/2])/2;}
  bool valid()const{return n>=2;}
  int16_t r()const{return median(rss,n);}
  int16_t s()const{return median(snr,n);}
};
struct Planner {
  enum Phase{COARSE,FINE,LOCKED,NO_SIGNAL};
  static const int32_t STEPS_REV=4096;
  static const int32_t MAX_POS=STEPS_REV*3/4;
  static const int32_t FINE_STEPS=(STEPS_REV*10+180)/360; // Nominal 4096 half-steps/rev * 270/360; calibrate actual gearbox.
  Phase phase=COARSE;uint8_t index=0;int32_t bestPos=0,coarsePos=0;int16_t bestR=-32768,bestS=-32768;
  void begin(){phase=COARSE;index=0;resetBest();}
  void resetBest(){bestR=-32768;bestS=-32768;}
  static int32_t clamp(int32_t p){return p<0?0:p>MAX_POS?MAX_POS:p;}
  int32_t target()const {return phase==COARSE?MAX_POS*index/9:phase==FINE?clamp(coarsePos+(int32_t(index)-1)*FINE_STEPS):bestPos;}
  void finish(const Quality&q,int32_t pos){
    if(q.valid()&&(q.r()>bestR+10||(q.r()>=bestR-10&&q.s()>bestS))){bestPos=pos;bestR=q.r();bestS=q.s();}
    if(phase==COARSE){if(++index<10)return;if(bestR==-32768){phase=NO_SIGNAL;return;}coarsePos=bestPos;phase=FINE;index=0;resetBest();}
    else if(phase==FINE){if(++index<3)return;phase=bestR==-32768?NO_SIGNAL:LOCKED;}
  }
};
