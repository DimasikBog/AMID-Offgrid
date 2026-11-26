#include "Arduino.h"
#include <cassert>
#include <iostream>
uint64_t fakeUS=100000;int pins[80]={0};FakeSerial Serial;
#include "../firmware/AMID_Azimuth/AMID_Azimuth.ino"
void cmd(const char*s){Serial.inject(s);for(int i=0;i<5;i++){loop();fakeUS+=100;}}
void healthy(){pins[26]=pins[27]=pins[28]=LOW;cmd("STOP");cmd("PING");}
void tick(unsigned ms,bool ping=true){for(unsigned i=0;i<ms;i++){if(ping&&i%500==0)cmd("PING");fakeUS+=1000;loop();}}
bool off(){return !pins[22]&&!pins[23]&&!pins[24]&&!pins[25];}
int main(){
 setup();pins[26]=pins[27]=pins[28]=HIGH;cmd("ARM");assert(state==FAULT&&off());
 healthy();cmd("ARM");assert(state==HOMING);tick(100);pins[26]=HIGH;tick(20);assert(state==BACKOFF);pins[26]=LOW;tick(500);assert(state==READY&&homed&&pos==0);
 cmd("SCAN");tick(1700);assert(state==SAMPLING);uint32_t tok=token;
 char b[100];snprintf(b,sizeof(b),"S %lu 123 -900 50",(unsigned long)(tok+1));cmd(b);assert(quality.n==0);
 snprintf(b,sizeof(b),"S %lu 123 -900 50",(unsigned long)tok);cmd(b);cmd(b);assert(quality.n==1);
 snprintf(b,sizeof(b),"S %lu 124 -950 40",(unsigned long)tok);cmd(b);assert(quality.n==2);
 cmd("STOP");assert(state==DISARMED&&off()&&!homed);
 healthy();cmd("JOG 32");tick(200);assert(state==DISARMED&&off());
 healthy();homed=true;state=READY;go(2000);tick(100);tick(3200,false);assert(state==FAULT&&off());
 healthy();homed=true;state=READY;go(10);pins[27]=HIGH;loop();assert(state==FAULT&&off());
 healthy();homed=true;state=READY;go(Planner::MAX_POS+1);loop();assert(state==FAULT&&off());
 healthy();cmd("ARM");tick(24000);assert(state==FAULT&&off());
 healthy();std::string huge(120,'x');huge+="ARM";Serial.inject(huge);tick(50);assert(state==DISARMED);
 healthy();fakeUS=(uint64_t(1)<<32)*1000-1500000;cmd("PING");pos=0;homed=true;state=READY;go(1000);tick(2000);assert(state!=FAULT);cmd("STOP");
 // Planner selects a measured optimum then refines, always within its software sector.
 Planner p;p.begin();Quality q;
 for(int i=0;i<10;i++){assert(p.target()>=0&&p.target()<=3072);q.clear();q.add(1,-1000+100*(i==4),20);q.add(2,-1010+100*(i==4),30);p.finish(q,p.target());}
 assert(p.phase==Planner::FINE);
 for(int i=0;i<3;i++){int32_t where=p.target();q.clear();q.add(1,i==1?-800:-950,30);q.add(2,i==1?-810:-960,20);p.finish(q,where);}
 assert(p.phase==Planner::LOCKED&&p.bestPos==1365);
 p.begin();q.clear();for(int i=0;i<10;i++)p.finish(q,p.target());assert(p.phase==Planner::NO_SIGNAL);
 q.clear();assert(!q.add(0,-800,20));assert(!q.add(1,0,20));assert(!q.add(1,-800,400));
 // v0.2 timing and telemetry: two ACKs cannot end a scan before 30 seconds.
 healthy();pos=0;homed=true;tracking=false;planner.begin();openWindow();
 tok=token;quality.add(101,-900,20);quality.add(102,-920,30);Serial.output.clear();
 tick(29900);assert(state==SAMPLING);tick(200);assert(state==MOVING);
 assert(Serial.output.find("RESULT ")!=std::string::npos);
 assert(Serial.output.find(" 2 1 -910 25 ENOUGH")!=std::string::npos);
 size_t first=Serial.output.find("CLOSE ");assert(first!=std::string::npos&&Serial.output.find("CLOSE ",first+1)==std::string::npos);
 // A missing signal expires after 80 s with explicit NA, never synthetic zero RSSI.
 healthy();pos=0;homed=true;tracking=false;planner.begin();openWindow();Serial.output.clear();
 tick(79900);assert(state==SAMPLING);tick(200);assert(state==MOVING);
 assert(Serial.output.find(" 0 0 NA NA TIMEOUT")!=std::string::npos);
 // Tracking retains a complete 80 s observation window.
 healthy();pos=0;homed=true;tracking=true;planner.bestR=-900;openWindow();quality.add(201,-900,20);quality.add(202,-910,20);
 tick(31000);assert(state==SAMPLING);tick(49010);assert(state==HOLDING);
 // Idle positions de-energize after 5 min, even with a healthy host heartbeat.
 healthy();homed=true;state=READY;stateAt=millis();pins[22]=HIGH;
 tick(299000);assert(state==READY);tick(1200);assert(state==DISARMED&&off()&&!homed);
 healthy();homed=true;state=NO_SIGNAL;stateAt=millis();pins[22]=HIGH;tick(300100);assert(state==DISARMED&&off());
 Serial.output.clear();cmd("STATUS");assert(Serial.output.find("INFO 2 4096 3072")!=std::string::npos);
 Serial.output.clear();pins[26]=LOW;pins[27]=HIGH;pins[28]=LOW;cmd("STATUS");assert(Serial.output.find("INPUTS 1 0 1 0")!=std::string::npos);
 std::cout<<"PASS: firmware startup, NC interlocks, homing/backoff, stale/duplicate samples, stop, jog, watchdog, limits, overflow, millis wrap, scan/refine/no-signal\n";
}
