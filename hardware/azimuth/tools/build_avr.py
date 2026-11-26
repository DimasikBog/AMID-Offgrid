from pathlib import Path
import subprocess,json
P=Path(__file__).parent;R=P.parent;C=next((P/'build-tools/core').glob('*/cores/arduino'));V=C.parents[1]/'variants/mega';G=next((P/'build-tools/compiler').glob('*/bin/avr-g++')).parent;O=P/'avr-objects';O.mkdir(exist_ok=True);D=R/'firmware/build';D.mkdir(exist_ok=True)
flags=['-mmcu=atmega2560','-DF_CPU=16000000L','-DARDUINO=10819','-DARDUINO_AVR_MEGA2560','-DARDUINO_ARCH_AVR','-Os','-ffunction-sections','-fdata-sections','-I'+str(C),'-I'+str(V),'-I'+str(R/'firmware/AMID_Azimuth')]
objects=[]
for i,f in enumerate(list(C.glob('*.c'))+list(C.glob('*.cpp'))+list(C.glob('*.S'))+[R/'firmware/AMID_Azimuth/AMID_Azimuth.ino']):
 obj=O/f'{i}.o';cpp=f.suffix in ('.cpp','.ino');tool=G/('avr-g++' if cpp else 'avr-gcc');extra=['-std=gnu++11','-fno-exceptions','-fno-threadsafe-statics'] if cpp else []
 if f.suffix=='.ino':extra+=['-x','c++']
 subprocess.run([str(tool),*flags,*extra,'-c',str(f),'-o',str(obj)],check=True,capture_output=True);objects.append(str(obj))
elf=D/'AMID_Azimuth_Mega2560.elf';subprocess.run([str(G/'avr-g++'),'-mmcu=atmega2560','-Wl,--gc-sections',*objects,'-lm','-o',str(elf)],check=True)
subprocess.run([str(G/'avr-objcopy'),'-O','ihex','-R','.eeprom',str(elf),str(D/'AMID_Azimuth_Mega2560.hex')],check=True)
s=subprocess.check_output([str(G/'avr-size'),str(elf)],text=True);(D/'avr_size.txt').write_text(s);(D/'toolchain.json').write_bytes((P/'build-tools/versions.json').read_bytes());print(s)
