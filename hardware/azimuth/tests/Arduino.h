#pragma once
#include <stdint.h>
#include <string>
#include <sstream>
#include <deque>
#define HIGH 1
#define LOW 0
#define INPUT_PULLUP 2
#define OUTPUT 1
struct __FlashStringHelper{};
#define F(x) (reinterpret_cast<const __FlashStringHelper*>(x))
extern uint64_t fakeUS;
extern int pins[80];
inline uint32_t millis(){return uint32_t(fakeUS/1000);}
inline uint32_t micros(){return uint32_t(fakeUS);}
inline void pinMode(int,int){}
inline int digitalRead(int n){return pins[n];}
inline void digitalWrite(int n,int v){pins[n]=v;}
struct FakeSerial {
 std::deque<char> incoming;std::string output;
 void begin(int){} int available(){return incoming.size();}int read(){char c=incoming.front();incoming.pop_front();return c;}
 void print(const __FlashStringHelper *s){output+=reinterpret_cast<const char*>(s);}
 void print(char c){output+=c;}
 void print(unsigned char c){print(unsigned(c));}
 template<class T>void print(T x){std::ostringstream ss;ss<<x;output+=ss.str();}
 template<class T>void println(T x){print(x);output+='\n';}
 void inject(std::string s){for(char c:s+"\n")incoming.push_back(c);}
};
extern FakeSerial Serial;
