@setlocal DisableDelayedExpansion
@echo off

set WIMPATH=
set WINPE=1
set SLIM=0

set WINPEPATH=

set DEFAULTLANGUAGE=
set MOUNTDIR=

:: ##################################################################
:: # NORMALY THERE IS NO NEED TO CHANGE ANYTHING BELOW THIS COMMENT #
:: ##################################################################

set "_cmdf=%~f0"
if exist "%SystemRoot%\Sysnative\cmd.exe" (
setlocal EnableDelayedExpansion
start %SystemRoot%\Sysnative\cmd.exe /c ""!_cmdf!" "
exit /b
)
if exist "%SystemRoot%\SysArm32\cmd.exe" if /i %PROCESSOR_ARCHITECTURE%==AMD64 (
setlocal EnableDelayedExpansion
start %SystemRoot%\SysArm32\cmd.exe /c ""!_cmdf!" "
exit /b
)

title Windows NT 10.0 LangPacks Integrator
set "SysPath=%SystemRoot%\System32"
if exist "%SystemRoot%\Sysnative\reg.exe" (set "SysPath=%SystemRoot%\Sysnative")
set "Path=%SysPath%;%SystemRoot%;%SysPath%\Wbem;%SysPath%\WindowsPowerShell\v1.0\"
if /i "%PROCESSOR_ARCHITECTURE%"=="amd64" set "xOS=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="arm64" set "xOS=arm64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" if "%PROCESSOR_ARCHITEW6432%"=="" set "xOS=x86"
if /i "%PROCESSOR_ARCHITEW6432%"=="amd64" set "xOS=amd64"
if /i "%PROCESSOR_ARCHITEW6432%"=="arm64" set "xOS=arm64"
reg query HKU\S-1-5-19 1>nul 2>nul || goto :E_ADMIN
set "WORKDIR=%~dp0"
set "WORKDIR=%WORKDIR:~0,-1%"
set "TEMPDIR=%WORKDIR%\TEMP"
set "TMPDISM=%TEMPDIR%\scratch"
set "EXTRACTDIR=%TEMPDIR%\extract"
set "TMPUPDT=%TEMPDIR%\updtemp"
set _drv=%~d0
set _ntf=NTFS
if /i not "%_drv%"=="%SystemDrive%" for /f "tokens=2 delims==" %%# in ('"wmic volume where DriveLetter='%_drv%' get FileSystem /value"') do set "_ntf=%%#"
if /i not "%_ntf%"=="NTFS" set _drv=%SystemDrive%
if "%MOUNTDIR%"=="" set "MOUNTDIR=%_drv%\W10MUIMOUNT"
set "INSTALLMOUNTDIR=%MOUNTDIR%\install"
set "WINREMOUNTDIR=%MOUNTDIR%\winre"
set EAlang=(ja-jp,ko-kr,zh-cn,zh-hk,zh-tw)

:adk
SET regKeyPathFound=1
SET wowRegKeyPathFound=1
REG QUERY "HKLM\Software\Wow6432Node\Microsoft\Windows Kits\Installed Roots" /v KitsRoot10 1>NUL 2>NUL || SET wowRegKeyPathFound=0
REG QUERY "HKLM\Software\Microsoft\Windows Kits\Installed Roots" /v KitsRoot10 1>NUL 2>NUL || SET regKeyPathFound=0
if %wowRegKeyPathFound% EQU 0 (
  if %regKeyPathFound% EQU 0 (
    goto :skipadk
  ) else (
    SET regKeyPath=HKLM\Software\Microsoft\Windows Kits\Installed Roots
  )
) else (
    SET regKeyPath=HKLM\Software\Wow6432Node\Microsoft\Windows Kits\Installed Roots
)
FOR /F "skip=2 tokens=2*" %%i IN ('REG QUERY "%regKeyPath%" /v KitsRoot10') DO (SET "KitsRoot=%%j")
SET "WinPERoot=%KitsRoot%Assessment and Deployment Kit\Windows Preinstallation Environment"
set "DandIRoot=%KitsRoot%Assessment and Deployment Kit\Deployment Tools"
if exist "%DandIRoot%\%xOS%\DISM\dism.exe" (
SET "DISMRoot=%DandIRoot%\%xOS%\DISM\dism.exe"
goto :prepare
)
if /i %xOS%==arm64 if exist "%DandIRoot%\x86\DISM\dism.exe" (
SET "DISMRoot=%DandIRoot%\x86\DISM\dism.exe"
goto :prepare
)

:skipadk
set "DISMRoot=%WORKDIR%\dism\dism.exe"
if /i %xOS%==amd64 set "DISMRoot=%WORKDIR%\dism\dism64\dism.exe"
for /f "tokens=6 delims=[]. " %%G in ('ver') do set winbuild=%%G
if %winbuild% GEQ 10240 SET "DISMRoot=%SystemRoot%\system32\dism.exe"

:prepare
if not "%WINPEPATH%"=="" set "WinPERoot=%WINPEPATH%"
set "_7z=%WORKDIR%\dism\7z.exe"
setlocal EnableDelayedExpansion
pushd "!WORKDIR!"
if not exist "!_7z!" goto :E_BIN
if not exist "!DISMRoot!" goto :E_BIN
if not exist "!WinPERoot!\amd64\WinPE_OCs\*" if not exist "!WinPERoot!\x86\WinPE_OCs\*" set WINPE=0

if not "!WIMPATH!"=="" goto :begin
set _wim=0
if exist "*.wim" (for /f "delims=" %%i in ('dir /b *.wim') do (call set /a _wim+=1))
if not %_wim%==1 goto :prompt
for /f "delims=" %%i in ('dir /b *.wim') do set "WIMPATH=%%i"
goto :begin

:prompt
@cls
set WIMPATH=
echo.
echo ============================================================
echo Enter the install.wim path ^(without quotes marks ""^)
echo ============================================================
echo.
set /p WIMPATH=
if not defined WIMPATH goto :prompt
set "WIMPATH=%WIMPATH:"=%"
if "%WIMPATH:~-1%"=="\" set "WIMPATH=!WIMPATH:~0,-1!"

:begin
if not exist "!WIMPATH!" goto :E_DVD
echo.
echo ============================================================
echo Prepare work directories
echo ============================================================
echo.
if exist "!TEMPDIR!\" (rmdir /s /q "!TEMPDIR!\" 1>nul 2>nul || goto :E_DELDIR)
if exist "!MOUNTDIR!\" (rmdir /s /q "!MOUNTDIR!\" 1>nul 2>nul || goto :E_DELDIR)
mkdir "!TEMPDIR!" || goto :E_MKDIR
mkdir "!TMPDISM!" || goto :E_MKDIR
mkdir "!EXTRACTDIR!" || goto :E_MKDIR
mkdir "%MOUNTDIR%" || goto :E_MKDIR
mkdir "%INSTALLMOUNTDIR%" || goto :E_MKDIR
mkdir "%WINREMOUNTDIR%" || goto :E_MKDIR
goto :start

:setarch
set /a count+=1
for /f "tokens=2 delims=: " %%i in ('dism\dism.exe /english /get-wiminfo /wimfile:"!WIMPATH!" /index:%1 ^| find /i "Architecture"') do set "WIMARCH%count%=%%i"
goto :eof

:start
echo.
echo ============================================================
echo Detect language packs details
echo ============================================================
echo.
set count=0
set _ol=0
if exist ".\langs\*.cab" for /f %%i in ('dir /b /on ".\langs\*.cab"') do (
set /a _ol+=1
set /a count+=1
set "LPFILE!count!=%%i"
)
if exist ".\langs\*.esd" for /f %%i in ('dir /b /on ".\langs\*.esd"') do (
set /a _ol+=1
set /a count+=1
set "LPFILE!count!=%%i"
)
if %_ol% equ 0 goto :E_FILES
set LANGUAGES=%_ol%
set count=0
set _oa=0
if exist ".\ondemand\x86\*.cab" for /f %%i in ('dir /b ".\ondemand\x86\*.cab"') do (
set /a _oa+=1
set /a count+=1
set "OAFILE!count!=%%i"
)
set count=0
set _ob=0
if exist ".\ondemand\x64\*.cab" for /f %%i in ('dir /b ".\ondemand\x64\*.cab"') do (
set /a _ob+=1
set /a count+=1
set "OBFILE!count!=%%i"
)
set foundupdates=0
if exist ".\Updates\W10UI.cmd" (
if exist ".\Updates\SSU-*-*.cab" set foundupdates=1
if exist ".\Updates\SSU-*-*.msu" set foundupdates=1
if exist ".\Updates\*Windows10*KB*.cab" set foundupdates=1
if exist ".\Updates\*Windows10*KB*.msu" set foundupdates=1
)

for /L %%j in (1, 1, %LANGUAGES%) do (
"!_7z!" e ".\langs\!LPFILE%%j!" -o"!EXTRACTDIR!" langcfg.ini >nul
for /f "tokens=2 delims==" %%i in ('type "!EXTRACTDIR!\langcfg.ini" ^| findstr /i "Language"') do set "LANGUAGE%%j=%%i"
del /f /q "!EXTRACTDIR!\langcfg.ini"
"!_7z!" e ".\langs\!LPFILE%%j!" -o"!EXTRACTDIR!" Microsoft-Windows-Common-Foundation-Package*10.*.mum 1>nul 2>nul
if not exist "!EXTRACTDIR!\*.mum" set "ERRFILE=!LPFILE%%j!"&goto :E_LP
for /f "tokens=7 delims=~." %%g in ('"dir "!EXTRACTDIR!\*.mum" /b" 2^>nul') do set "LPBUILD%%j=%%g"
for /f "tokens=3 delims=~" %%V in ('"dir "!EXTRACTDIR!\*.mum" /b" 2^>nul') do set "LPARCH%%j=%%V"
del /f /q "!EXTRACTDIR!\*.mum" 1>nul 2>nul
)
for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==amd64 (echo !LANGUAGE%%j!: 64-bit {x64} - !LPBUILD%%j!) else (echo !LANGUAGE%%j!: 32-bit {x86} - !LPBUILD%%j!)
set "WinpeOC%%j=!WinPERoot!\!LPARCH%%j!\WinPE_OCs"
)
for /L %%j in (1, 1, %LANGUAGES%) do (
if not exist "!WinpeOC%%j!\!LANGUAGE%%j!\lp.cab" set WINPE=0
)
set _lpver=%LPBUILD1%

set _ODbasic86=
set _ODfont86=
set _ODhand86=
set _ODocr86=
set _ODspeech86=
set _ODtts86=
set _ODintl86=
set _ODext86=
set _ODtra86=
set _ODpaint86=
set _ODnote86=
set _ODpower86=
set _ODpmcppc86=
set _ODpwsf86=
set _ODword86=
set _ODsnip86=
set _ODnots86=
if %_oa% neq 0 for /L %%j in (1, 1, %_oa%) do (
"!_7z!" x ".\ondemand\x86\!OAFILE%%j!" -o"!TEMPDIR!\FOD86\OAFILE%%j" * -r >nul
pushd "!TEMPDIR!\FOD86\OAFILE%%j"
findstr /i /m Microsoft-Windows-LanguageFeatures-Basic update.mum 1>nul 2>nul && call set _ODbasic86=!_ODbasic86! /PackagePath:OAFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-Fonts update.mum 1>nul 2>nul && call set _ODfont86=!_ODfont86! /PackagePath:OAFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-Handwriting update.mum 1>nul 2>nul && call set _ODhand86=!_ODhand86! /PackagePath:OAFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-OCR update.mum 1>nul 2>nul && call set _ODocr86=!_ODocr86! /PackagePath:OAFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-Speech update.mum 1>nul 2>nul && call set _ODspeech86=!_ODspeech86! /PackagePath:OAFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-TextToSpeech update.mum 1>nul 2>nul && call set _ODtts86=!_ODtts86! /PackagePath:OAFILE%%j\update.mum
findstr /i /m Microsoft-Windows-InternationalFeatures update.mum 1>nul 2>nul && call set _ODintl86=!_ODintl86! /PackagePath:OAFILE%%j\update.mum
if %_lpver% GEQ 19041 (
findstr /i /m Microsoft-Windows-MSPaint-FoD update.mum 1>nul 2>nul && (set _ODext86=1&call set _ODpaint86=!_ODpaint86! /PackagePath:OAFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Notepad-FoD update.mum 1>nul 2>nul && (set _ODext86=1&call set _ODnote86=!_ODnote86! /PackagePath:OAFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-PowerShell-ISE-FOD update.mum 1>nul 2>nul && (set _ODext86=1&call set _ODpower86=!_ODpower86! /PackagePath:OAFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Printing-PMCPPC-FoD update.mum 1>nul 2>nul && (set _ODtra86=1&call set _ODpmcppc86=!_ODpmcppc86! /PackagePath:OAFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Printing-WFS-FoD update.mum 1>nul 2>nul && (set _ODtra86=1&call set _ODpwsf86=!_ODpwsf86! /PackagePath:OAFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-WordPad-FoD update.mum 1>nul 2>nul && (set _ODtra86=1&call set _ODword86=!_ODword86! /PackagePath:OAFILE%%j\update.mum)
  )
if %_lpver% GEQ 21277 (
findstr /i /m Microsoft-Windows-SnippingTool-FoD update.mum 1>nul 2>nul && (set _ODtra86=1&call set _ODsnip86=!_ODsnip86! /PackagePath:OAFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Notepad-System-FoD update.mum 1>nul 2>nul && (set _ODtra86=1&call set _ODnots86=!_ODnots86! /PackagePath:OAFILE%%j\update.mum)
  )
popd
)
set _ODbasic64=
set _ODfont64=
set _ODhand64=
set _ODocr64=
set _ODspeech64=
set _ODtts64=
set _ODintl64=
set _ODext64=
set _ODtra64=
set _ODpaint64=
set _ODnote64=
set _ODpower64=
set _ODpmcppc64=
set _ODpwsf64=
set _ODword64=
set _ODsnip64=
set _ODnots64=
if %_ob% neq 0 for /L %%j in (1, 1, %_ob%) do (
"!_7z!" x ".\ondemand\x64\!OBFILE%%j!" -o"!TEMPDIR!\FOD64\OBFILE%%j" * -r >nul
pushd "!TEMPDIR!\FOD64\OBFILE%%j"
findstr /i /m Microsoft-Windows-LanguageFeatures-Basic update.mum 1>nul 2>nul && call set _ODbasic64=!_ODbasic64! /PackagePath:OBFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-Fonts update.mum 1>nul 2>nul && call set _ODfont64=!_ODfont64! /PackagePath:OBFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-Handwriting update.mum 1>nul 2>nul && call set _ODhand64=!_ODhand64! /PackagePath:OBFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-OCR update.mum 1>nul 2>nul && call set _ODocr64=!_ODocr64! /PackagePath:OBFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-Speech update.mum 1>nul 2>nul && call set _ODspeech64=!_ODspeech64! /PackagePath:OBFILE%%j\update.mum
findstr /i /m Microsoft-Windows-LanguageFeatures-TextToSpeech update.mum 1>nul 2>nul && call set _ODtts64=!_ODtts64! /PackagePath:OBFILE%%j\update.mum
findstr /i /m Microsoft-Windows-InternationalFeatures update.mum 1>nul 2>nul && call set _ODintl64=!_ODintl64! /PackagePath:OBFILE%%j\update.mum
if %_lpver% GEQ 19041 (
findstr /i /m Microsoft-Windows-MSPaint-FoD update.mum 1>nul 2>nul && (set _ODext64=1&call set _ODpaint64=!_ODpaint64! /PackagePath:OBFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Notepad-FoD update.mum 1>nul 2>nul && (set _ODext64=1&call set _ODnote64=!_ODnote64! /PackagePath:OBFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-PowerShell-ISE-FOD update.mum 1>nul 2>nul && (set _ODext64=1&call set _ODpower64=!_ODpower64! /PackagePath:OBFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Printing-PMCPPC-FoD update.mum 1>nul 2>nul && (set _ODtra64=1&call set _ODpmcppc64=!_ODpmcppc64! /PackagePath:OBFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Printing-WFS-FoD update.mum 1>nul 2>nul && (set _ODtra64=1&call set _ODpwsf64=!_ODpwsf64! /PackagePath:OBFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-WordPad-FoD update.mum 1>nul 2>nul && (set _ODtra64=1&call set _ODword64=!_ODword64! /PackagePath:OBFILE%%j\update.mum)
  )
if %_lpver% GEQ 21277 (
findstr /i /m Microsoft-Windows-SnippingTool-FoD update.mum 1>nul 2>nul && (set _ODtra64=1&call set _ODsnip64=!_ODsnip64! /PackagePath:OBFILE%%j\update.mum)
findstr /i /m Microsoft-Windows-Notepad-System-FoD update.mum 1>nul 2>nul && (set _ODtra64=1&call set _ODnots64=!_ODnots64! /PackagePath:OBFILE%%j\update.mum)
  )
popd
)
dism\imagex.exe /info "!WIMPATH!" | findstr /c:"LZMS" >nul && goto :E_ESD
for /f "tokens=2 delims=: " %%i in ('dism\dism.exe /english /get-wiminfo /wimfile:"!WIMPATH!" ^| findstr "Index"') do set VERSIONS=%%i
for /f "tokens=4 delims=:. " %%i in ('dism\dism.exe /english /get-wiminfo /wimfile:"!WIMPATH!" /index:1 ^| find /i "Version :"') do set build=%%i
if %build% equ 18363 set build=18362
if %build% equ 19042 set build=19041
if %build% equ 19043 set build=19041
if %build% equ 19044 set build=19041
if %build% equ 19045 set build=19041
for /L %%j in (1, 1, %LANGUAGES%) do (
if not !LPBUILD%%j!==%build% set "ERRFILE=!LPFILE%%j!"&goto :E_VER
)
if %WINPE%==1 for /L %%j in (1, 1, %LANGUAGES%) do (
"!_7z!" e "!WinpeOC%%j!\!LANGUAGE%%j!\lp.cab" -o"!EXTRACTDIR!" Microsoft-Windows-Common-Foundation-Package*%build%*.mum 1>nul 2>nul
if not exist "!EXTRACTDIR!\*.mum" set WINPE=0
)
if "%DEFAULTLANGUAGE%"=="" (
for /f "tokens=1" %%i in ('dism\dism.exe /english /get-wiminfo /wimfile:"!WIMPATH!" /index:1 ^| find /i "Default"') do set "DEFAULTLANGUAGE=%%i"
)
echo.
echo ============================================================
echo Detect install.wim details
echo ============================================================
echo.
set count=0
for /L %%i in (1, 1, %VERSIONS%) do call :setarch %%i
for /L %%i in (1, 1, %VERSIONS%) do (
if /i !WIMARCH%%i!==x64 (call set WIMARCH%%i=amd64)
)
for /L %%i in (1, 1, %VERSIONS%) do (
echo !WIMARCH%%i!>>"%TEMPDIR%\WIMARCH.txt"
)
set _label86=0
findstr /i /v "amd64" "%TEMPDIR%\WIMARCH.txt" >nul
if %errorlevel%==0 (set wimbit=32&set _label86=1)

findstr /i /v "x86" "%TEMPDIR%\WIMARCH.txt" >nul
if %errorlevel%==0 (
if %_label86%==1 (set wimbit=dual) else (set wimbit=64)
)
echo Build: %build%
echo Count: %VERSIONS% Image^(s^)
if %wimbit%==dual (echo Arch : Multi) else (echo Arch : %wimbit%-bit)

if %WINPE% NEQ 1 goto :extract
set _PEM86=
set _PES86=
set _PEX86=
set _PEF86=
set _PER86=
set _PEM64=
set _PES64=
set _PEX64=
set _PEF64=
set _PER64=
echo.
echo ============================================================
echo Set WinPE language packs paths
echo ============================================================
echo.
if %wimbit%==32 for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==x86 (
echo !LANGUAGE%%j! / 32-bit
call set _PEM86=!_PEM86! /PackagePath:!LANGUAGE%%j!\lp.cab /PackagePath:!LANGUAGE%%j!\WinPE-SRT_!LANGUAGE%%j!.cab
call set _PES86=!_PES86! /PackagePath:!LANGUAGE%%j!\WinPE-Setup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Setup-Client_!LANGUAGE%%j!.cab
call set _PER86=!_PER86! /PackagePath:!LANGUAGE%%j!\WinPE-HTA_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Rejuv_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-StorageWMI_!LANGUAGE%%j!.cab
call set _PEX86=!_PEX86! /PackagePath:!LANGUAGE%%j!\WinPE-EnhancedStorage_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Scripting_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-SecureStartup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WDS-Tools_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WMI_!LANGUAGE%%j!.cab
 for %%G in %EAlang% do (
 if /i !LANGUAGE%%j!==%%G call set _PEF86=!_PEF86! /PackagePath:WinPE-FontSupport-%%G.cab
 )
)
)
if %wimbit%==64 for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==amd64 (
echo !LANGUAGE%%j! / 64-bit
call set _PEM64=!_PEM64! /PackagePath:!LANGUAGE%%j!\lp.cab /PackagePath:!LANGUAGE%%j!\WinPE-SRT_!LANGUAGE%%j!.cab
call set _PES64=!_PES64! /PackagePath:!LANGUAGE%%j!\WinPE-Setup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Setup-Client_!LANGUAGE%%j!.cab
call set _PER64=!_PER64! /PackagePath:!LANGUAGE%%j!\WinPE-HTA_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Rejuv_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-StorageWMI_!LANGUAGE%%j!.cab
call set _PEX64=!_PEX64! /PackagePath:!LANGUAGE%%j!\WinPE-EnhancedStorage_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Scripting_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-SecureStartup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WDS-Tools_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WMI_!LANGUAGE%%j!.cab
 for %%G in %EAlang% do (
 if /i !LANGUAGE%%j!==%%G call set _PEF64=!_PEF64! /PackagePath:WinPE-FontSupport-%%G.cab
 )
)
)
if %wimbit%==dual for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==x86 (
echo !LANGUAGE%%j! / 32-bit
call set _PEM86=!_PEM86! /PackagePath:!LANGUAGE%%j!\lp.cab /PackagePath:!LANGUAGE%%j!\WinPE-SRT_!LANGUAGE%%j!.cab
call set _PES86=!_PES86! /PackagePath:!LANGUAGE%%j!\WinPE-Setup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Setup-Client_!LANGUAGE%%j!.cab
call set _PER86=!_PER86! /PackagePath:!LANGUAGE%%j!\WinPE-HTA_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Rejuv_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-StorageWMI_!LANGUAGE%%j!.cab
call set _PEX86=!_PEX86! /PackagePath:!LANGUAGE%%j!\WinPE-EnhancedStorage_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Scripting_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-SecureStartup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WDS-Tools_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WMI_!LANGUAGE%%j!.cab
 for %%G in %EAlang% do (
 if /i !LANGUAGE%%j!==%%G call set _PEF86=!_PEF86! /PackagePath:WinPE-FontSupport-%%G.cab
 )
) else (
echo !LANGUAGE%%j! / 64-bit
call set _PEM64=!_PEM64! /PackagePath:!LANGUAGE%%j!\lp.cab /PackagePath:!LANGUAGE%%j!\WinPE-SRT_!LANGUAGE%%j!.cab
call set _PES64=!_PES64! /PackagePath:!LANGUAGE%%j!\WinPE-Setup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Setup-Client_!LANGUAGE%%j!.cab
call set _PER64=!_PER64! /PackagePath:!LANGUAGE%%j!\WinPE-HTA_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Rejuv_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-StorageWMI_!LANGUAGE%%j!.cab
call set _PEX64=!_PEX64! /PackagePath:!LANGUAGE%%j!\WinPE-EnhancedStorage_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-Scripting_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-SecureStartup_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WDS-Tools_!LANGUAGE%%j!.cab /PackagePath:!LANGUAGE%%j!\WinPE-WMI_!LANGUAGE%%j!.cab
 for %%G in %EAlang% do (
 if /i !LANGUAGE%%j!==%%G call set _PEF64=!_PEF64! /PackagePath:WinPE-FontSupport-%%G.cab
 )
)
)

:extract
set _PP86=
set _PP64=
echo.
echo ============================================================
echo Extract language packs
echo ============================================================
echo.
if %wimbit%==32 for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==x86 (
echo !LANGUAGE%%j! / 32-bit
"!_7z!" e ".\langs\!LPFILE%%j!" -o"!EXTRACTDIR!\!LPARCH%%j!\!LANGUAGE%%j!" vofflps.rtf -r -aos >nul
"!_7z!" x ".\langs\!LPFILE%%j!" -o"!TEMPDIR!\!LPARCH%%j!\!LANGUAGE%%j!" * -r >nul
call set _PP86=!_PP86! /PackagePath:!LANGUAGE%%j!\update.mum
)
)
if %wimbit%==64 for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==amd64 (
echo !LANGUAGE%%j! / 64-bit
"!_7z!" e ".\langs\!LPFILE%%j!" -o"!EXTRACTDIR!\!LPARCH%%j!\!LANGUAGE%%j!" vofflps.rtf -r -aos >nul
"!_7z!" x ".\langs\!LPFILE%%j!" -o"!TEMPDIR!\!LPARCH%%j!\!LANGUAGE%%j!" * -r >nul
call set _PP64=!_PP64! /PackagePath:!LANGUAGE%%j!\update.mum
)
)
if %wimbit%==dual for /L %%j in (1, 1, %LANGUAGES%) do (
if /i !LPARCH%%j!==x86 (
echo !LANGUAGE%%j! / 32-bit
"!_7z!" e ".\langs\!LPFILE%%j!" -o"!EXTRACTDIR!\!LPARCH%%j!\!LANGUAGE%%j!" vofflps.rtf -r -aos >nul
"!_7z!" x ".\langs\!LPFILE%%j!" -o"!TEMPDIR!\!LPARCH%%j!\!LANGUAGE%%j!" * -r >nul
call set _PP86=!_PP86! /PackagePath:!LANGUAGE%%j!\update.mum
) else (
echo !LANGUAGE%%j! / 64-bit
"!_7z!" e ".\langs\!LPFILE%%j!" -o"!EXTRACTDIR!\!LPARCH%%j!\!LANGUAGE%%j!" vofflps.rtf -r -aos >nul
"!_7z!" x ".\langs\!LPFILE%%j!" -o"!TEMPDIR!\!LPARCH%%j!\!LANGUAGE%%j!" * -r >nul
call set _PP64=!_PP64! /PackagePath:!LANGUAGE%%j!\update.mum
)
)
if %wimbit%==32 if not defined _PP86 goto :E_ARCH
if %wimbit%==64 if not defined _PP64 goto :E_ARCH

for /L %%i in (1, 1, %VERSIONS%) do (
echo.
echo ============================================================
echo Mount install.wim - index %%i/%VERSIONS%
echo ============================================================
"%DISMRoot%" /ScratchDir:"!TMPDISM!" /Mount-Wim /Wimfile:"!WIMPATH!" /Index:%%i /MountDir:"%INSTALLMOUNTDIR%"
if errorlevel 1 goto :E_MOUNT
echo.
echo ============================================================
echo Add LPs to install.wim - index %%i/%VERSIONS%
echo ============================================================
pushd "!TEMPDIR!\!WIMARCH%%i!"
if defined _PP64 if /i !WIMARCH%%i!==amd64 (
"%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_PP64!
)
if defined _PP86 if /i !WIMARCH%%i!==x86 (
"%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_PP86!
)
popd
if /i !WIMARCH%%i!==amd64 if exist "!TEMPDIR!\FOD64\OBFILE1\update.mum" (
pushd "!TEMPDIR!\FOD64"
if defined _ODbasic64 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODbasic64!
if defined _ODbasic64 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODfont64! !_ODtts64! !_ODhand64! !_ODocr64! !_ODspeech64! !_ODintl64!
if defined _ODext64 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODpaint64! !_ODnote64! !_ODpower64!
if defined _ODtra64 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODpmcppc64! !_ODpwsf64! !_ODword64! !_ODsnip64! !_ODnots64!
popd
)
if /i !WIMARCH%%i!==x86 if exist "!TEMPDIR!\FOD86\OAFILE1\update.mum" (
pushd "!TEMPDIR!\FOD86"
if defined _ODbasic86 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODbasic86!
if defined _ODbasic86 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODfont86! !_ODtts86! !_ODhand86! !_ODocr86! !_ODspeech86! !_ODintl86!
if defined _ODext86 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODpaint86! !_ODnote86! !_ODpower86!
if defined _ODtra86 "%DISMRoot%" /ScratchDir:"!TMPDISM!" /Image:"%INSTALLMOUNTDIR%" /Add-Package !_ODpmcppc86! !_ODpwsf86! !_ODword86! !_ODsnip86! !_ODnots86!
popd
)
echo.
echo ============================================================
echo Update language settings
echo ============================================================
echo.
"%DISMRoot%" /Quiet /Image:"%INSTALLMOUNTDIR%" /Set-AllIntl:%DEFAULTLANGUAGE%
"%DISMRoot%" /Quiet /Image:"%INSTALLMOUNTDIR%" /Set-SKUIntlDefaults:%DEFAULTLANGUAGE%
if %foundupdates%==1 call Updates\W10UI.cmd 1 "%INSTALLMOUNTDIR%" "!TMPUPDT!"
attrib -S -H -I "%INSTALLMOUNTDIR%\Windows\System32\Recovery\winre.wim" 1>nul 2>nul
if %WINPE%==1 if exist "%INSTALLMOUNTDIR%\Windows\System32\Recovery\winre.wim" if not exist "!TEMPDIR!\WR\!WIMARCH%%i!\winre.wim" (
  echo.
  echo ============================================================
  echo Update winre.wim / !WIMARCH%%i!
  echo ============================================================
  echo.
  mkdir "!TEMPDIR!\WR\!WIMARCH%%i!"
  copy "%INSTALLMOUNTDIR%\Windows\System32\Recovery\winre.wim" "!TEMPDIR!\WR\!WIMARCH%%i!"
  echo.
  echo ============================================================
  echo Mount winre.wim
  echo ============================================================
  "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Mount-Wim /Wimfile:"!TEMPDIR!\WR\!WIMARCH%%i!\winre.wim" /Index:1 /MountDir:"!WINREMOUNTDIR!"
  if errorlevel 1 goto :E_MOUNT
  echo.
  echo ============================================================
  echo Add LPs to winre.wim
  echo ============================================================
  reg load HKLM\TEMPWIM "!WINREMOUNTDIR!\Windows\System32\Config\SOFTWARE" 1>nul 2>nul
  reg add HKLM\TEMPWIM\Microsoft\Windows\CurrentVersion\SideBySide\Configuration /v DisableComponentBackups /t REG_DWORD /d 1 /f 1>nul 2>nul
  reg add HKLM\TEMPWIM\Microsoft\Windows\CurrentVersion\SideBySide\Configuration /v SupersededActions /t REG_DWORD /d 1 /f 1>nul 2>nul
  reg unload HKLM\TEMPWIM 1>nul 2>nul
  pushd "!WinPERoot!\!WIMARCH%%i!\WinPE_OCs"
  if defined _PEM64 if /i !WIMARCH%%i!==amd64 (
    "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Add-Package !_PEM64! !_PEF64!
    "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Add-Package !_PER64!
    if !SLIM! NEQ 1 "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Add-Package !_PEX64!
  )
  if defined _PEM86 if /i !WIMARCH%%i!==x86 (
    "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Add-Package !_PEM86! !_PEF86!
    "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Add-Package !_PER86!
    if !SLIM! NEQ 1 "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Add-Package !_PEX86!
  )
  popd
  echo.
  echo ============================================================
  echo Update language settings
  echo ============================================================
  echo.
  "!DISMRoot!" /Quiet /Image:"!WINREMOUNTDIR!" /Set-AllIntl:!DEFAULTLANGUAGE!
  "!DISMRoot!" /Quiet /Image:"!WINREMOUNTDIR!" /Set-SKUIntlDefaults:!DEFAULTLANGUAGE!
  "!DISMRoot!" /Quiet /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Cleanup-Image /StartComponentCleanup
  "!DISMRoot!" /Quiet /ScratchDir:"!TMPDISM!" /Image:"!WINREMOUNTDIR!" /Cleanup-Image /StartComponentCleanup /ResetBase
  if %foundupdates%==1 call Updates\W10UI.cmd 1 "!WINREMOUNTDIR!" "!TMPUPDT!"
  call :cleanup "!WINREMOUNTDIR!"
  echo.
  echo ============================================================
  echo Unmount winre.wim
  echo ============================================================
  "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Unmount-Wim /MountDir:"!WINREMOUNTDIR!" /Commit
  if errorlevel 1 goto :E_UNMOUNT
  echo.
  echo ============================================================
  echo Rebuild winre.wim
  echo ============================================================
  "!DISMRoot!" /ScratchDir:"!TMPDISM!" /Export-Image /SourceImageFile:"!TEMPDIR!\WR\!WIMARCH%%i!\winre.wim" /All /DestinationImageFile:"!EXTRACTDIR!\winre.wim"
  if exist "!EXTRACTDIR!\winre.wim" move /y "!EXTRACTDIR!\winre.wim" "!TEMPDIR!\WR\!WIMARCH%%i!" >nul
)
if %WINPE%==1 if exist "!TEMPDIR!\WR\!WIMARCH%%i!\winre.wim" (
  echo.
  echo ============================================================
  echo Add updated winre.wim to install.wim - index %%i/%VERSIONS%
  echo ============================================================
  echo.
  copy /y "!TEMPDIR!\WR\!WIMARCH%%i!\winre.wim" "%INSTALLMOUNTDIR%\Windows\System32\Recovery"
)
call :cleanup "%INSTALLMOUNTDIR%"
echo.
echo ============================================================
echo Unmount install.wim - index %%i/%VERSIONS%
echo ============================================================
"%DISMRoot%" /ScratchDir:"!TMPDISM!" /Unmount-Wim /MountDir:"%INSTALLMOUNTDIR%" /Commit
if errorlevel 1 goto :E_UNMOUNT
)
echo.
echo ============================================================
echo Rebuild install.wim
echo ============================================================
"%DISMRoot%" /ScratchDir:"!TMPDISM!" /Export-Image /SourceImageFile:"!WIMPATH!" /All /DestinationImageFile:"!TEMPDIR!\install.wim"
if exist "!TEMPDIR!\install.wim" move /y "!TEMPDIR!\install.wim" "!WIMPATH!" >nul
echo.
echo ============================================================
echo Remove temporary directories
echo ============================================================
echo.
call :remove
set MESSAGE=Finished
goto :END

:E_BIN
call :remove
set MESSAGE=ERROR: Could not find work binaries
goto :END

:E_DVD
call :remove
set MESSAGE=ERROR: Could not find the specified install.wim
goto :END

:E_ESD
call :remove
set MESSAGE=ERROR: Detected install.wim file is actually .esd file
goto :END

:E_FILES
call :remove
set MESSAGE=ERROR: Could not detect any cab/esd files in "Langs" folder
goto :END

:E_ARCH
call :remove
set MESSAGE=ERROR: None of detected LangPacks match any of WIM images architecture
goto :END

:E_LP
call :remove
set MESSAGE=ERROR: %ERRFILE% is not a valid Windows NT 10.0 LangPack
goto :END

:E_VER
call :remove
set MESSAGE=ERROR: %ERRFILE% version does not match WIM version %build%
goto :END

:E_DELDIR
set MESSAGE=ERROR: Could not delete temporary directory
goto :END

:E_MKDIR
set MESSAGE=ERROR: Could not create temporary directory
goto :END

:E_MOUNT
set MESSAGE=ERROR: Could not mount WIM image
goto :END

:E_UNMOUNT
set MESSAGE=ERROR: Could not unmount WIM image
goto :END

:E_ADMIN
set MESSAGE=ERROR: Run the script as administrator
goto :END

:remove
if exist "!TEMPDIR!" (rmdir /s /q "!TEMPDIR!" 1>nul 2>nul || goto :E_DELDIR)
if exist "!MOUNTDIR!" (rmdir /s /q "!MOUNTDIR!" 1>nul 2>nul || goto :E_DELDIR)
if exist "Updates\msucab.txt" (
  for /f %%# in (Updates\msucab.txt) do (
  if exist "Updates\*%%~#*x86*.msu" if exist "Updates\*%%~#*x86*.cab" del /f /q "Updates\*%%~#*x86*.cab" 1>nul 2>nul
  if exist "Updates\*%%~#*x64*.msu" if exist "Updates\*%%~#*x64*.cab" del /f /q "Updates\*%%~#*x64*.cab" 1>nul 2>nul
  )
  del /f /q Updates\msucab.txt
)
goto :eof

:cleanup
if exist "%~1\Windows\WinSxS\ManifestCache\*.bin" (
takeown /f "%~1\Windows\WinSxS\ManifestCache\*.bin" /A >nul 2>&1
icacls "%~1\Windows\WinSxS\ManifestCache\*.bin" /grant *S-1-5-32-544:F >nul 2>&1
del /f /q "%~1\Windows\WinSxS\ManifestCache\*.bin" >nul 2>&1
)
if exist "%~1\Windows\WinSxS\Temp\PendingDeletes\*" (
takeown /f "%~1\Windows\WinSxS\Temp\PendingDeletes\*" /A >nul 2>&1
icacls "%~1\Windows\WinSxS\Temp\PendingDeletes\*" /grant *S-1-5-32-544:F >nul 2>&1
del /f /q "%~1\Windows\WinSxS\Temp\PendingDeletes\*" >nul 2>&1
)
if exist "%~1\Windows\WinSxS\Temp\TransformerRollbackData\*" (
takeown /f "%~1\Windows\WinSxS\Temp\TransformerRollbackData\*" /R /A >nul 2>&1
icacls "%~1\Windows\WinSxS\Temp\TransformerRollbackData\*" /grant *S-1-5-32-544:F /T >nul 2>&1
del /s /f /q "%~1\Windows\WinSxS\Temp\TransformerRollbackData\*" >nul 2>&1
)
if exist "%~1\Windows\inf\*.log" (
del /f /q "%~1\Windows\inf\*.log" >nul 2>&1
)
goto :eof

:END
echo.
echo ============================================================
echo %MESSAGE%
echo ============================================================
echo.
echo Press any Key to Exit.
pause >nul
exit