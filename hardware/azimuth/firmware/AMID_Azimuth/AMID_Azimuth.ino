#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Planner.h"
// Stand prototype only. Motor: 5V 28BYJ-48 + ULN2003. No radio is driven by this sketch.
const uint8_t MP[4]={22,23,24,25}, LEFT_PIN=26,RIGHT_PIN=27,STOP_PIN=28;
const uint32_t STEP_US=4000,HEARTBEAT_MS=3000,SETTLE_MS=1500,DWELL_MS=80000,MIN_SAMPLE_MS=30000,IDLE_MS=300000;
const int32_t HOME_BACKOFF=Planner::FINE_STEPS,HOME_LIMIT=5000;
const bool MOTOR_REVERSED=false; // Set true only if the unloaded direction test requires it.
const uint8_t PHASE[8]={1,3,2,6,4,12,8,9};
enum State{DISARMED,HOMING,BACKOFF,READY,MOVING,SETTLING,SAMPLING,HOLDING,NO_SIGNAL,FAULT,JOGGING};
State state=DISARMED;Planner planner;Quality quality;
int32_t pos=0,target=0,homeSteps=0,backSteps=0;uint8_t phase=0,badWindows=0;bool homed=false,tracking=false;
uint32_t heartbeat=0,lastStep=0,stateAt=0,token=0;char line[96];uint8_t lineLen=0;bool overflow=false;
bool leftHit(){return digitalRead(LEFT_PIN)==HIGH;}bool rightHit(){return digitalRead(RIGHT_PIN)==HIGH;}bool stopped(){return digitalRead(STOP_PIN)==HIGH;}
void coilsOff(){for(uint8_t i=0;i<4;i++)digitalWrite(MP[i],LOW);}
void closeWindow(){if(state==SAMPLING){Serial.print(F("CLOSE "));Serial.println(token);state=READY;}}
void fail(const __FlashStringHelper *reason){closeWindow();coilsOff();homed=false;tracking=false;state=FAULT;Serial.print(F("FAULT "));Serial.println(reason);}
void stopNow(){closeWindow();coilsOff();homed=false;tracking=false;state=DISARMED;Serial.println(F("DISARMED"));}
void stepMotor(int8_t dir){int8_t electrical=MOTOR_REVERSED?-dir:dir;phase=(phase+(electrical>0?1:7))&7;for(uint8_t i=0;i<4;i++)digitalWrite(MP[i],(PHASE[phase]>>i)&1);pos+=dir;}
void status(){Serial.print(F("INFO 2 "));Serial.print(Planner::STEPS_REV);Serial.print(' ');Serial.println(Planner::MAX_POS);Serial.print(F("STATE "));Serial.print(int(state));Serial.print(F(" POS "));Serial.print(pos);Serial.print(F(" HOMED "));Serial.println(homed?1:0);Serial.print(F("INPUTS 1 "));Serial.print(leftHit()?1:0);Serial.print(' ');Serial.print(rightHit()?1:0);Serial.print(' ');Serial.println(stopped()?1:0);}
void go(int32_t p){closeWindow();target=p;state=MOVING;stateAt=millis();}
void scan(){planner.begin();tracking=false;badWindows=0;go(planner.target());Serial.println(F("SCAN COARSE"));}
void openWindow(){quality.clear();token++;if(!token)token++;state=SAMPLING;stateAt=millis();Serial.print(F("WINDOW "));Serial.print(token);Serial.print(' ');Serial.println(pos);}
void handle(char *s){
 if(!strcmp(s,"PING")){heartbeat=millis();return;}
 if(!strcmp(s,"STOP")){stopNow();return;}
 if(!strcmp(s,"STATUS")){status();return;}
 if(!strcmp(s,"ARM")){
  if(stopped()||rightHit()){fail(F("CHECK_NC_SWITCHES"));return;}
  if(state!=DISARMED&&state!=FAULT){Serial.println(F("ERR STOP_FIRST"));return;}
  heartbeat=millis();homed=false;tracking=false;homeSteps=backSteps=0;stateAt=millis();state=leftHit()?BACKOFF:HOMING;Serial.println(F("HOMING"));return;
 }
 if(!strcmp(s,"SCAN")){if(!homed||!(state==READY||state==HOLDING||state==NO_SIGNAL)){Serial.println(F("ERR HOME_FIRST_OR_BUSY"));return;}scan();return;}
 long jog;char extra;
 if(sscanf(s,"JOG %ld %c",&jog,&extra)==1){
  if(state!=DISARMED||stopped()||!jog||jog<-32||jog>32){Serial.println(F("ERR JOG"));return;}
  pos=0;target=jog;homed=false;heartbeat=millis();state=JOGGING;return;
 }
 // Integer tenths of dBm/dB avoid AVR scanf float limitations.
 unsigned long t,id;long r,n;
 if(sscanf(s,"S %lu %lu %ld %ld %c",&t,&id,&r,&n,&extra)==4){
  if(state==SAMPLING&&uint32_t(t)==token&&r>=-1500&&r<0&&n>=-300&&n<=300&&quality.add(uint32_t(id),int16_t(r),int16_t(n))){Serial.print(F("ACCEPT "));Serial.print(token);Serial.print(' ');Serial.println(quality.n);}return;
 }
 Serial.println(F("ERR COMMAND"));
}
void setup(){
 Serial.begin(115200);for(uint8_t i=0;i<4;i++)pinMode(MP[i],OUTPUT);coilsOff();
 pinMode(LEFT_PIN,INPUT_PULLUP);pinMode(RIGHT_PIN,INPUT_PULLUP);pinMode(STOP_PIN,INPUT_PULLUP);Serial.println(F("HELLO AMID_AZIMUTH_0.3"));
}
void loop(){
 uint8_t consumed=0;
 while(Serial.available()&&consumed++<48){char c=Serial.read();if(c=='\n'){if(!overflow){line[lineLen]=0;handle(line);}else Serial.println(F("ERR LINE_TOO_LONG"));lineLen=0;overflow=false;}else if(c!='\r'){if(lineLen<sizeof(line)-1&&!overflow)line[lineLen++]=c;else overflow=true;}}
 uint32_t now=millis();
 if(stopped()&&state!=FAULT){fail(F("ESTOP_OR_BROKEN_WIRE"));return;}
 if(state==DISARMED||state==FAULT)return;
 if(uint32_t(now-heartbeat)>HEARTBEAT_MS){fail(F("HOST_TIMEOUT"));return;}
 if(leftHit()&&rightHit()){fail(F("BOTH_LIMITS"));return;}
 if(state==HOMING||state==BACKOFF){
  if(uint32_t(now-stateAt)>25000){fail(F("HOME_TIMEOUT"));return;}
  if(state==HOMING&&leftHit()){state=BACKOFF;backSteps=0;}
  if(rightHit()){fail(F("RIGHT_LIMIT_DURING_HOME"));return;}
  if(uint32_t(micros()-lastStep)<STEP_US)return;
  lastStep=micros();
  if(state==HOMING){if(++homeSteps>HOME_LIMIT){fail(F("HOME_TRAVEL"));return;}stepMotor(-1);}
  else {stepMotor(1);if(++backSteps>=HOME_BACKOFF){if(leftHit()){fail(F("LEFT_NOT_RELEASED"));return;}pos=target=0;homed=true;state=READY;stateAt=now;Serial.println(F("HOMED"));}}
  return;
 }
 if(leftHit()||rightHit()){fail(F("TRAVEL_LIMIT"));return;}
 if(state==MOVING||state==JOGGING){
  if(pos==target){if(state==JOGGING){stopNow();return;}state=SETTLING;stateAt=now;return;}
  if(state==MOVING&&(pos<0||pos>Planner::MAX_POS||target<0||target>Planner::MAX_POS)){fail(F("SOFT_LIMIT"));return;}
  if(uint32_t(micros()-lastStep)>=STEP_US){lastStep=micros();stepMotor(target>pos?1:-1);}return;
 }
 if(state==SETTLING&&uint32_t(now-stateAt)>=SETTLE_MS){openWindow();return;}
 if((state==READY||state==NO_SIGNAL)&&uint32_t(now-stateAt)>=IDLE_MS){Serial.println(F("NOTICE IDLE_TIMEOUT"));stopNow();return;}
 bool enough=state==SAMPLING&&!tracking&&quality.valid()&&uint32_t(now-stateAt)>=MIN_SAMPLE_MS;
 if(state==SAMPLING&&(enough||uint32_t(now-stateAt)>=DWELL_MS)){
  Serial.print(F("RESULT "));Serial.print(token);Serial.print(' ');Serial.print(pos);Serial.print(' ');Serial.print(tracking?2:int(planner.phase));Serial.print(' ');Serial.print(quality.n);Serial.print(' ');Serial.print(quality.valid()?1:0);Serial.print(' ');
  if(quality.valid()){Serial.print(quality.r());Serial.print(' ');Serial.print(quality.s());}else Serial.print(F("NA NA"));
  Serial.print(' ');Serial.println(enough?F("ENOUGH"):F("TIMEOUT"));
  closeWindow();
  if(tracking){
   if(!quality.valid()||quality.r()<planner.bestR-60)badWindows++;else badWindows=0;
   if(badWindows>=2){Serial.println(F("REACQUIRE"));scan();return;}
   state=HOLDING;stateAt=now;return;
  }
  planner.finish(quality,pos);
  if(planner.phase==Planner::NO_SIGNAL){state=NO_SIGNAL;stateAt=now;Serial.println(F("NO_SIGNAL SEND_SCAN_TO_RETRY"));return;}
  if(planner.phase==Planner::LOCKED){tracking=true;go(planner.bestPos);Serial.print(F("LOCK_TARGET "));Serial.print(planner.bestPos);Serial.print(F(" RSSI10 "));Serial.println(planner.bestR);return;}
  go(planner.target());return;
 }
 if(state==HOLDING&&uint32_t(now-stateAt)>=1000)openWindow();
}
