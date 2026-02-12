#define AppName "KrakenNowPlaying"
#define AppVersion "1.0.0"

[Setup]
AppId={{A8AAB1AA-2C2E-4DA9-9C8A-9C2B18E4C0D2}}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={userappdata}\{#AppName}\installer_payload
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=KrakenNowPlaying-Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest

[Files]
Source: "..\installer.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\server\*";      DestDir: "{app}\server"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\extension\*";   DestDir: "{app}\extension"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer.ps1"""; Flags: waituntilterminated runhidden
