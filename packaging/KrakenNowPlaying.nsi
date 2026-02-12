!define APPNAME "KrakenNowPlaying"
!define VERSION "1.0.0"

OutFile "dist\KrakenNowPlaying-Setup.exe"
InstallDir "$LOCALAPPDATA\${APPNAME}\installer_payload"
RequestExecutionLevel user
Unicode True

Page directory
Page instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File "..\installer.ps1"

  SetOutPath "$INSTDIR\server"
  File /r "..\server\*.*"

  SetOutPath "$INSTDIR\extension"
  File /r "..\extension\*.*"

  CreateDirectory "$LOCALAPPDATA\${APPNAME}"

  ; Run the PowerShell installer hidden
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\installer.ps1"'
SectionEnd
