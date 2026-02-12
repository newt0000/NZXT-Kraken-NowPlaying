Kraken Now Playing — NZXT CAM Web Display
=========================================

Display your currently playing YouTube video (title, thumbnail, and circular progress bar)
directly on your NZXT Kraken Elite LCD using a local web integration.

This project uses:

• Chrome Extension → reads YouTube playback
• Local Node.js Server → exposes data via HTTP
• NZXT CAM Web Integration → renders display
• System Tray app → health + control


FEATURES
========

✓ Live YouTube title
✓ Thumbnail background
✓ Circular progress bar
✓ Auto-start on login
✓ Silent background processes (no console windows)
✓ System tray icon with:
    - Open Display
    - Open Log
    - Quit (stops server safely)
✓ Single-click Start shortcut
✓ Repair + Uninstall
✓ Defender-safe folder install


ARCHITECTURE
============

YouTube tab
   ↓
Chrome Extension (content.js)
   ↓ POST
http://127.0.0.1:27123/nowplaying
   ↓
Node Server (server.js)
   ↓
NZXT CAM → Web Integration URL
   ↓
Kraken Elite LCD


REQUIREMENTS
============

• Windows 10/11
• Node.js LTS (installer auto-installs if missing)
• Google Chrome
• NZXT CAM


INSTALLATION (RECOMMENDED)
==========================

STEP 1 — Move project to a safe folder

Windows Defender aggressively scans Downloads/Desktop.

Create:

C:\Dev\KrakenNowPlaying

Move the entire project there.


STEP 2 — Add Defender exclusion (IMPORTANT)

Open PowerShell as Administrator and run:

Add-MpPreference -ExclusionPath "C:\Dev\KrakenNowPlaying"


STEP 3 — Run installer

Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\installer.ps1

Installer automatically:

• installs Node if missing
• copies files
• installs npm deps
• creates tray
• sets startup
• creates shortcuts
• launches server


INSTALL CHROME EXTENSION (MANUAL – REQUIRED)
============================================

This is NOT automated.

1. Open Chrome
2. Visit:
   chrome://extensions
3. Enable Developer Mode
4. Click "Load unpacked"
5. Select:
   %LOCALAPPDATA%\KrakenNowPlaying\app\extension

Done.


SETUP NZXT CAM
==============

Open CAM → LCD → Web Integration

Set URL:

http://127.0.0.1:27123/


FIRST LAUNCH
============

Use:

Start Menu → KrakenNowPlaying → Start (Silent)

or reboot (auto-start enabled).


TRAY ICON
==========

Green  = server running
Red    = server offline

Right-click menu:

• Open Display
• Open Server Log
• Quit (Stop Server)


INSTALLED LOCATIONS
====================

%LOCALAPPDATA%\KrakenNowPlaying
    app\
    logs\
    Server-Run.ps1
    HealthTray.ps1
    Stop-Server.ps1
    RunAllHidden.vbs
    icon.ico


REPAIR
=======

.\installer.ps1 -mode Repair


UNINSTALL
==========

Start Menu → Uninstall

or:

%LOCALAPPDATA%\KrakenNowPlaying\Uninstall.ps1


TROUBLESHOOTING
================

Server says “Waiting for YouTube”
--------------------------------
Extension not installed. Install from chrome://extensions


Multiple tray icons
------------------
Kill all:

Get-CimInstance Win32_Process |
Where CommandLine -match "HealthTray" |
% { Stop-Process $_.ProcessId -Force }

or

run forcestop.ps1 with powershell


Server won’t stop
----------------
Run:

.\Stop-Server.ps1


Port already in use
------------------
Get-NetTCPConnection -LocalPort 27123
taskkill /PID <pid> /T /F


Defender deletes installer
--------------------------
Add exclusion:

Add-MpPreference -ExclusionPath "C:\Dev\KrakenNowPlaying"


Node not detected
----------------
Restart PowerShell or log out/in.


CAM shows blank
---------------
Visit:

http://127.0.0.1:27123/

If not loading → server isn’t running.


CUSTOM ICON
============

Place:

assets\icon.ico

Then:

.\installer.ps1 -mode Repair


DEVELOPMENT
============

Run server manually:

cd server
npm start

Run tray manually:

powershell -STA HealthTray.ps1


PACKAGING (OPTIONAL)
=====================

Use:

• Inno Setup
• NSIS

to package as single installer EXE.


SECURITY NOTES
===============

Installer writes to LOCALAPPDATA and runs hidden scripts.
This can trigger Defender heuristics.

Use exclusions or code signing for production use.


Enjoy!
If something breaks:

.\installer.ps1 -mode Repair

and you’re back to a clean state in seconds.
