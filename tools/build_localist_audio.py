"""Compile Localist's WaveRT capture driver without installing or test-signing it."""
from pathlib import Path
import subprocess,os,sys,json,re
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'build/localist-virtual-audio'
WDK=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'.runlogs/localist-microphone/wdk/c'
subprocess.run([sys.executable,str(ROOT/'tools/generate_virtual_audio.py'),str(OUT/'generated')],check=True)
source=OUT/'generated/Source';objects=OUT/'objects';objects.mkdir(parents=True,exist_ok=True)
package=OUT/'unsigned';package.mkdir(exist_ok=True)
vswhere=Path(os.environ['ProgramFiles(x86)'])/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=Path(subprocess.check_output([str(vswhere),'-latest','-property','installationPath'],text=True).strip())
vc=sorted((vs/'VC/Tools/MSVC').iterdir())[-1]
cl=vc/'bin/Hostx64/x64/cl.exe';link=vc/'bin/Hostx64/x64/link.exe'
sdk=Path(os.environ['ProgramFiles(x86)'])/'Windows Kits/10'
version='10.0.26100.0';framework='1.15'
incs=[vc/'include',WDK/f'Include/{version}/km',WDK/f'Include/{version}/shared',
 sdk/f'Include/{version}/shared',sdk/f'Include/{version}/ucrt',WDK/f'Include/wdf/kmdf/{framework}',
 source/'Main',source/'Filters',source/'Inc',source/'Utilities']
flags=['/nologo','/c','/kernel','/GS','/Zl','/Z7','/GR-','/EHs-c-','/std:c++17','/W3','/O2','/Oi',
 '/D_AMD64_','/DAMD64','/D_WIN64','/D_WIN32','/DUNICODE','/D_UNICODE',
 '/DWINVER=0x0A00','/D_WIN32_WINNT=0x0A00','/DNTDDI_VERSION=0x0A000008',
 '/D_USE_WAVERT_','/D_USE_IPortClsRuntimePower','/D_NEW_DELETE_OPERATORS_','/DPC_IMPLEMENTATION']
flags += ['/I'+str(p) for p in incs]
compiled=[]
for file in sorted(source.rglob('*.cpp')):
 obj=objects/(file.stem+'.obj');compiled.append(obj)
 result=subprocess.run([str(cl),*flags,'/Fo'+str(obj),str(file)],cwd=objects,capture_output=True,text=True)
 print(result.stdout+result.stderr,end='',flush=True)
 if result.returncode: raise SystemExit(result.returncode)
libs=[WDK/f'Lib/{version}/km/x64',WDK/f'Lib/wdf/kmdf/x64/{framework}',vc/'lib/x64']
command=[str(link),'/nologo','/DRIVER','/SUBSYSTEM:NATIVE,10.00','/MACHINE:X64','/ENTRY:FxDriverEntry',
 '/NODEFAULTLIB','/INTEGRITYCHECK','/DYNAMICBASE','/NXCOMPAT','/MANIFEST:NO','/OPT:REF','/OPT:ICF',
 '/DEBUG:FULL','/PDB:'+str(package/'LocalistAudio.pdb'),'/PDBALTPATH:%_PDB%',
 '/OUT:'+str(package/'LocalistAudio.sys'),*map(str,compiled)]
command+=['/LIBPATH:'+str(p) for p in libs]
command+=['ntoskrnl.lib','hal.lib','wmilib.lib','portcls.lib','stdunk.lib','libcntpr.lib','wdmsec.lib',
 'ksguid.lib','wdfdriverentry.lib','wdfldr.lib','BufferOverflowFastFailK.lib']
subprocess.run(command,cwd=objects,check=True)
import shutil
shutil.copyfile(ROOT/'windows/virtual_audio/LocalistAudio.inf',package/'LocalistAudio.inf')
print('LOCALIST_AUDIO_UNSIGNED_DRIVER_BUILT',package/'LocalistAudio.sys')
