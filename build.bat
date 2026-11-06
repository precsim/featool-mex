cls
rem MATLAB MEX file build script (gcc/mingw)
@echo off

setlocal enableextensions enabledelayedexpansion
set SRC=%~n1

set GCC=C:\TDM-GCC-10p3
set ML=C:\Program Files\MATLAB\R2011a
set MLOLD=t

set OPT=-O2 -std=c99 -DNDEBUG
set OPT=%OPT% -fexceptions -fno-omit-frame-pointer -fwrapv -fPIC

set INC=-I"%GCC%\x86_64-w64-mingw32\include" -I"%ML%\extern\include"

set LD=-L"%ML%\extern\lib\win64\mingw64" -L"%ML%\bin\win64"

set OMP=-fopenmp
if defined OMP (
   set LD=%LD% -lgomp -lgomp.dll
) else (
   set LD=%LD% -s
)

if not defined MLOLD (
  goto mlnew
) else (
  goto mlold
)

:mlnew
@echo on

"%GCC%\bin\gcc.exe" -m64 -c -DMATLAB_DEFAULT_RELEASE=R2017b -DUSE_MEX_CMD -DMATLAB_MEX_FILE %INC% ^
%OPT% %OMP% %SRC%.c -o %SRC%.obj

"%GCC%\bin\gcc.exe" -m64 -c -DMATLAB_DEFAULT_RELEASE=R2017b -DUSE_MEX_CMD -DMATLAB_MEX_FILE %INC% ^
%OPT% %OMP% "%ML%\extern\version\c_mexapi_version.c" -o c_mexapi_version.obj

"%GCC%\bin\gcc.exe" -m64 %OMP% -shared -static -Wl,--no-undefined ^
-Wl,"%ML%\extern\lib\win64\mingw64\exportsmexfileversion.def" ^
%SRC%.obj c_mexapi_version.obj %LD% ^
-llibmx -llibmex -llibmat -lm -llibmwlapack -llibmwblas ^
-o %SRC%.mexw64
@echo off
goto exit

:mlold
@echo on

"%GCC%\bin\gcc.exe" -m64 -c -largeArrayDims -DMATLAB_MEX_FILE %INC% ^
%OPT% %OMP% %SRC%.c -o %SRC%.obj

rem "%GCC%\bin\gcc.exe" %OMP% -m64 -shared -static-libgcc -Wl,--no-undefined ^
rem %SRC%.obj %LD% -lmex -lmx -leng -lmat -lmwlapack -lmwblas -o %SRC%.mexw64
rem @echo off

rem Use fully static build with OpenMP
set LD=-L"%ML%\extern\lib\win64\microsoft" -L"%ML%\bin\win64"
"%GCC%\bin\gcc.exe" %OMP% -m64 -shared -static -static-libgcc -Wl,--no-undefined ^
%SRC%.obj %LD% -llibmex -llibmx -llibeng -llibmat -llibmwlapack -llibmwblas -o %SRC%.mexw64

@echo off
goto exit


:exit
del /Q /F *.obj > nul
