param(
  [ValidateSet("Install","Repair")]
  [string]$Mode = "Install"
)

$ErrorActionPreference = "Stop"

# -------------------------
# Config
# -------------------------
$AppName  = "KrakenNowPlaying"
$BaseDir  = Join-Path $env:LOCALAPPDATA $AppName
$AppDir   = Join-Path $BaseDir "app"
$ServerDir= Join-Path $AppDir  "server"
$ExtDir   = Join-Path $AppDir  "extension"
$LogDir   = Join-Path $BaseDir "logs"
$LogPath  = Join-Path $LogDir  "server.log"

$Port     = 27123
$Url      = "http://127.0.0.1:$Port/"

$TaskServer = "$AppName (Server AutoStart)"
$TaskTray   = "$AppName (Health Tray)"

$NodeInstallerUrl  = "https://nodejs.org/dist/v20.18.1/node-v20.18.1-x64.msi"
$NodeInstallerPath = Join-Path $BaseDir "node-lts-x64.msi"

# Start Menu folder
$StartMenuFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName"
$DesktopDir = [Environment]::GetFolderPath("Desktop")

# Source folders relative to installer.ps1
$SrcRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcServer = Join-Path $SrcRoot "server"
$SrcExt    = Join-Path $SrcRoot "extension"

# -------------------------
# Helpers
# -------------------------
function I($m){ Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function OK($m){ Write-Host "✅ $m" -ForegroundColor Green }
function W($m){ Write-Host "⚠️  $m" -ForegroundColor Yellow }
function F($m){ Write-Host "❌ $m" -ForegroundColor Red; exit 1 }

function EnsureDir($p){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
function HasCmd($n){ return [bool](Get-Command $n -ErrorAction SilentlyContinue) }

function Find-NodeExe {
  $candidates = @(
    (Join-Path ${env:ProgramFiles} "nodejs\node.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\nodejs\node.exe")
  )
  foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
  return $null
}

function Ensure-NodeBinOnPath($nodeExePath) {
  $nodeDir = Split-Path -Parent $nodeExePath
  if ($env:Path -notlike "*$nodeDir*") { $env:Path = "$nodeDir;$env:Path" }

  $npmCmdCandidates = @(
    (Join-Path $nodeDir "npm.cmd"),
    (Join-Path $env:APPDATA "npm\npm.cmd")
  )
  foreach ($c in $npmCmdCandidates) {
    if (Test-Path $c) {
      $npmDir = Split-Path -Parent $c
      if ($env:Path -notlike "*$npmDir*") { $env:Path = "$npmDir;$env:Path" }
      break
    }
  }
}

function Ensure-NodeInstalled {
  if (HasCmd "node" -and HasCmd "npm") {
    OK "Node present: $(node -v) | npm: $(npm -v)"
    return
  }

  $nodeExe = Find-NodeExe
  if ($nodeExe) {
    Ensure-NodeBinOnPath $nodeExe
    if (HasCmd "node" -and HasCmd "npm") {
      OK "Node found (PATH refreshed): $(node -v) | npm: $(npm -v)"
      return
    }
  }

  W "Node.js not found. This installer can download and run the official Node LTS installer."
  $resp = Read-Host "Install Node LTS now? (Y/N)"
  if ($resp -notin @("Y","y")) { F "Node is required. Install Node LTS then rerun." }

  EnsureDir $BaseDir
  try {
    I "Downloading Node installer..."
    Invoke-WebRequest -Uri $NodeInstallerUrl -OutFile $NodeInstallerPath -UseBasicParsing
    OK "Downloaded: $NodeInstallerPath"
  } catch { F "Node download failed: $($_.Exception.Message)" }

  I "Launching installer (complete install). Waiting..."
  try {
    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$NodeInstallerPath`"" -PassThru -Verb RunAs
    $p.WaitForExit()
  } catch {
    W "Could not elevate; trying without elevation..."
    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$NodeInstallerPath`"" -PassThru
    $p.WaitForExit()
  }

  $nodeExe = Find-NodeExe
  if (-not $nodeExe) { F "Installer finished but node.exe not found. Install Node manually then rerun." }

  Ensure-NodeBinOnPath $nodeExe
  if (!(HasCmd "node") -or !(HasCmd "npm")) { F "Node installed but not available in this session. Log off/on then rerun." }

  OK "Node installed: $(node -v) | npm: $(npm -v)"
}

function CopyProjectFiles {
  if (!(Test-Path $SrcServer)) { F "Missing source folder: $SrcServer" }
  if (!(Test-Path $SrcExt))    { F "Missing source folder: $SrcExt" }
  if (!(Test-Path (Join-Path $SrcServer "package.json"))) { F "Missing server\package.json" }
  if (!(Test-Path (Join-Path $SrcServer "server.js")))    { F "Missing server\server.js" }
  if (!(Test-Path (Join-Path $SrcExt "manifest.json")))   { F "Missing extension\manifest.json" }

  EnsureDir $AppDir; EnsureDir $ServerDir; EnsureDir $ExtDir; EnsureDir $LogDir

  I "Copying server..."
  Copy-Item -Path (Join-Path $SrcServer "*") -Destination $ServerDir -Recurse -Force
  I "Copying extension..."
  Copy-Item -Path (Join-Path $SrcExt "*")    -Destination $ExtDir   -Recurse -Force

  OK "Files installed to: $AppDir"
}

function InstallServerDeps([switch]$Force) {
  Push-Location $ServerDir
  try {
    if ($Force) {
      I "Repair: reinstalling dependencies (npm install)..."
      npm install | Out-Null
      OK "Dependencies repaired."
      return
    }

    if (!(Test-Path (Join-Path $ServerDir "node_modules"))) {
      I "Installing dependencies (npm install)..."
      npm install | Out-Null
      OK "Dependencies installed."
    } else {
      OK "Dependencies already present."
    }
  } finally { Pop-Location }
}

# -------------------------
# Runtime scripts
# -------------------------
function WriteRuntimeScripts {
  # Hidden runner VBS (no console)
  $vbsPath = Join-Path $BaseDir "RunServerHidden.vbs"
  @"
Dim shell : Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$BaseDir\Server-Run.ps1""", 0, False
"@ | Set-Content -Path $vbsPath -Encoding ASCII

  # Server-Run.ps1 (logs only)
  $runPs1 = Join-Path $BaseDir "Server-Run.ps1"
  @"
`$ErrorActionPreference = "Stop"
`$serverDir = "$ServerDir"
`$logDir = "$LogDir"
`$log = "$LogPath"

New-Item -ItemType Directory -Force -Path `$logDir | Out-Null

function Find-NodeExe {
  `$c = @(
    (Join-Path `${env:ProgramFiles} "nodejs\node.exe"),
    (Join-Path `${env:ProgramFiles(x86)} "nodejs\node.exe"),
    (Join-Path `${env:LOCALAPPDATA} "Programs\nodejs\node.exe")
  )
  foreach (`$p in `$c) { if (`$p -and (Test-Path `$p)) { return `$p } }
  return `$null
}

`$nodeExe = Find-NodeExe
if (`$nodeExe) {
  `$nodeDir = Split-Path -Parent `$nodeExe
  if (`$env:Path -notlike "*`$nodeDir*") { `$env:Path = "`$nodeDir;`$env:Path" }
  `$npmDir = Join-Path `${env:APPDATA} "npm"
  if (Test-Path `$npmDir -and `$env:Path -notlike "*`$npmDir*") { `$env:Path = "`$npmDir;`$env:Path" }
}

Set-Location `$serverDir

"`$(Get-Date -Format o) Starting server..." | Add-Content `$log
try {
  # If already running, don't start another
  try {
    `$conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if (`$conn) {
      "`$(Get-Date -Format o) Port $Port already in use; assuming server running." | Add-Content `$log
      exit 0
    }
  } catch {}

  npm start 2>&1 | Tee-Object -FilePath `$log -Append | Out-Null
} catch {
  "`$(Get-Date -Format o) Server crashed: `$($_.Exception.Message)" | Add-Content `$log
  exit 1
}
"@ | Set-Content -Path $runPs1 -Encoding UTF8

  # Stop-Server.ps1
  $stopPs1 = Join-Path $BaseDir "Stop-Server.ps1"
  @"
`$ErrorActionPreference = "SilentlyContinue"
`$port = $Port
`$conns = Get-NetTCPConnection -LocalPort `$port -ErrorAction SilentlyContinue
if (`$conns) {
  `$pids = `$conns | Select-Object -ExpandProperty OwningProcess -Unique
  foreach (`$pid in `$pids) { Stop-Process -Id `$pid -Force -ErrorAction SilentlyContinue }
  Write-Host "Stopped process(es) on port `$port"
} else {
  Write-Host "No process found listening on port `$port"
}
"@ | Set-Content -Path $stopPs1 -Encoding UTF8

  # Open-CAM-URL.ps1
  $openCamPs1 = Join-Path $BaseDir "Open-CAM-URL.ps1"
  @"
`$ErrorActionPreference = "SilentlyContinue"
`$url = "$Url"

Set-Clipboard -Value `$url
Write-Host "Copied URL to clipboard: `$url"

`$candidates = @(
  (Join-Path `${env:ProgramFiles} "NZXT CAM\CAM.exe"),
  (Join-Path `${env:ProgramFiles(x86)} "NZXT CAM\CAM.exe")
)
foreach (`$p in `$candidates) {
  if (Test-Path `$p) { Start-Process `$p | Out-Null; break }
}

Start-Process `$url | Out-Null
"@ | Set-Content -Path $openCamPs1 -Encoding UTF8

  # Repair.ps1 entrypoint
  $repairPs1 = Join-Path $BaseDir "Repair.ps1"
  @"
Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$SrcRoot\installer.ps1`" -Mode Repair" -Verb RunAs
"@ | Set-Content -Path $repairPs1 -Encoding UTF8

  # Extension instructions
  $howTxt = Join-Path $BaseDir "INSTALL-EXTENSION.txt"
  @"
Chrome extension install (one-time):
1) Open Chrome: chrome://extensions
2) Enable Developer mode (top right)
3) Click "Load unpacked"
4) Select:
   $ExtDir

Test:
- Play a YouTube video
- Open: http://127.0.0.1:$Port/nowplaying

NZXT CAM:
- Web Integration URL: $Url
"@ | Set-Content -Path $howTxt -Encoding UTF8

  OK "Runtime scripts written to: $BaseDir"
}

# -------------------------
# Health tray (NotifyIcon + alerts)
# -------------------------
function WriteHealthTray {
  $trayPs1 = Join-Path $BaseDir "HealthTray.ps1"
  @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$url = "$Url"
`$checkUrl = "http://127.0.0.1:$Port/nowplaying"

function MakeIcon([System.Drawing.Color]`$color) {
  `$bmp = New-Object System.Drawing.Bitmap 16,16
  `$g = [System.Drawing.Graphics]::FromImage(`$bmp)
  `$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  `$g.Clear([System.Drawing.Color]::Transparent)
  `$brush = New-Object System.Drawing.SolidBrush `$color
  `$g.FillEllipse(`$brush, 1,1,14,14)
  `$g.Dispose()
  return [System.Drawing.Icon]::FromHandle(`$bmp.GetHicon())
}

`$iconUp = MakeIcon ([System.Drawing.Color]::LimeGreen)
`$iconDown = MakeIcon ([System.Drawing.Color]::Red)

`$ni = New-Object System.Windows.Forms.NotifyIcon
`$ni.Text = "Kraken Now Playing"
`$ni.Visible = `$true
`$ni.Icon = `$iconDown

`$menu = New-Object System.Windows.Forms.ContextMenuStrip
`$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem "Open Display URL"
`$miOpen.add_Click({ Start-Process `$url | Out-Null })
`$miLogs = New-Object System.Windows.Forms.ToolStripMenuItem "Open Log"
`$miLogs.add_Click({ Start-Process "notepad.exe" -ArgumentList "$LogPath" | Out-Null })
`$miQuit = New-Object System.Windows.Forms.ToolStripMenuItem "Quit"
`$miQuit.add_Click({ `$ni.Visible = `$false; [System.Windows.Forms.Application]::Exit() })
`$menu.Items.AddRange(@(`$miOpen, `$miLogs, `$miQuit))
`$ni.ContextMenuStrip = `$menu

`$wasUp = `$false
`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 5000
`$timer.add_Tick({
  try {
    `$resp = Invoke-WebRequest -Uri `$checkUrl -UseBasicParsing -TimeoutSec 2
    `$isUp = (`$resp.StatusCode -eq 200)
  } catch { `$isUp = `$false }

  if (`$isUp) {
    `$ni.Icon = `$iconUp
    `$ni.Text = "Kraken Now Playing - OK"
  } else {
    `$ni.Icon = `$iconDown
    `$ni.Text = "Kraken Now Playing - DOWN"
    if (`$wasUp) {
      `$ni.ShowBalloonTip(5000, "Kraken Now Playing", "Server appears down. Check log / scheduled tasks.", [System.Windows.Forms.ToolTipIcon]::Error)
    }
  }
  `$wasUp = `$isUp
})

`$timer.Start()
[System.Windows.Forms.Application]::Run()
"@ | Set-Content -Path $trayPs1 -Encoding UTF8

  OK "Health tray created: $trayPs1"
}

# -------------------------
# Scheduled tasks
# -------------------------
function RegisterTasks {
  try { Unregister-ScheduledTask -TaskName $TaskServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
  try { Unregister-ScheduledTask -TaskName $TaskTray   -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

  $vbs = Join-Path $BaseDir "RunServerHidden.vbs"
  if (!(Test-Path $vbs)) { F "Missing hidden runner: $vbs" }

  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

  # Silent server via wscript
  $actionServer = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbs`""
  Register-ScheduledTask -TaskName $TaskServer -Action $actionServer -Trigger $trigger -Settings $settings -Description "Auto-start $AppName server silently at logon" | Out-Null
  OK "Scheduled task installed: $TaskServer"

  # Tray
  $trayPs1 = Join-Path $BaseDir "HealthTray.ps1"
  if (Test-Path $trayPs1) {
    $actionTray = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$trayPs1`""
    Register-ScheduledTask -TaskName $TaskTray -Action $actionTray -Trigger $trigger -Settings $settings -Description "Tray health monitor for $AppName" | Out-Null
    OK "Scheduled task installed: $TaskTray"
  }
}

# -------------------------
# Shortcuts
# -------------------------
function New-Shortcut($ShortcutPath, $TargetPath, $Arguments, $WorkingDir, $Description) {
  $wsh = New-Object -ComObject WScript.Shell
  $sc = $wsh.CreateShortcut($ShortcutPath)
  $sc.TargetPath = $TargetPath
  if ($Arguments)  { $sc.Arguments = $Arguments }
  if ($WorkingDir) { $sc.WorkingDirectory = $WorkingDir }
  if ($Description){ $sc.Description = $Description }
  $sc.IconLocation = "$env:SystemRoot\System32\shell32.dll, 220"
  $sc.Save()
}

function CreateShortcuts {
  EnsureDir $StartMenuFolder

  $ps = (Get-Command powershell.exe).Source

  $open = Join-Path $BaseDir "Open-CAM-URL.ps1"
  $stop = Join-Path $BaseDir "Stop-Server.ps1"
  $uninst = Join-Path $BaseDir "Uninstall.ps1"
  $tray = Join-Path $BaseDir "HealthTray.ps1"

  # Start = kick the scheduled task (silent server)
  $startCmdArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"Start-ScheduledTask -TaskName '$TaskServer'`""
  # Stop = run Stop-Server.ps1
  $stopArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$stop`""
  # Open = Open-CAM-URL.ps1
  $openArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$open`""
  # Uninstall = Uninstall.ps1
  $unArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$uninst`""
  # Repair = rerun installer in Repair mode (from installed copy not guaranteed; point to installed installer if you package it with EXE)
  $repairArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$SrcRoot\installer.ps1`" -Mode Repair"

  # Desktop shortcut (Open CAM URL)
  $desktopLink = Join-Path $DesktopDir "Open CAM URL.lnk"
  New-Shortcut $desktopLink $ps $openArgs $BaseDir "Copy and open the Kraken Web Integration URL."
  OK "Desktop shortcut created: $desktopLink"

  # Start Menu shortcuts
  New-Shortcut (Join-Path $StartMenuFolder "Start Server (Silent).lnk") $ps $startCmdArgs $BaseDir "Start server via scheduled task (silent)."
  New-Shortcut (Join-Path $StartMenuFolder "Stop Server.lnk")          $ps $stopArgs     $BaseDir "Stop server listening on port $Port."
  New-Shortcut (Join-Path $StartMenuFolder "Open CAM URL.lnk")         $ps $openArgs     $BaseDir "Copy/open the Kraken Web Integration URL."
  New-Shortcut (Join-Path $StartMenuFolder "Open Log.lnk")             "notepad.exe" "`"$LogPath`"" $BaseDir "Open server log."
  New-Shortcut (Join-Path $StartMenuFolder "Repair.lnk")               $ps $repairArgs   $BaseDir "Repair install: recopy, reinstall deps, re-register tasks."
  New-Shortcut (Join-Path $StartMenuFolder "Uninstall.lnk")            $ps $unArgs       $BaseDir "Uninstall KrakenNowPlaying."

  OK "Start Menu folder created: $StartMenuFolder"
}

# -------------------------
# Uninstaller
# -------------------------
function WriteUninstaller {
  $uninstall = Join-Path $BaseDir "Uninstall.ps1"
  @"
`$ErrorActionPreference = "SilentlyContinue"
try { & (Join-Path "$BaseDir" "Stop-Server.ps1") } catch {}

try { Unregister-ScheduledTask -TaskName "$TaskServer" -Confirm:`$false | Out-Null } catch {}
try { Unregister-ScheduledTask -TaskName "$TaskTray" -Confirm:`$false | Out-Null } catch {}

# Remove shortcuts
try { Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path "$DesktopDir" "Open CAM URL.lnk") } catch {}
try { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$StartMenuFolder" } catch {}

try { Remove-Item -Recurse -Force -Path "$BaseDir" } catch {}
Write-Host "Uninstalled."
"@ | Set-Content -Path $uninstall -Encoding UTF8
  OK "Uninstaller created: $uninstall"
}

# -------------------------
# MAIN
# -------------------------
I "$Mode: $AppName -> $BaseDir"
EnsureDir $BaseDir

Ensure-NodeInstalled

if ($Mode -eq "Install") {
  CopyProjectFiles
  InstallServerDeps
  WriteRuntimeScripts
  WriteHealthTray
  RegisterTasks
  WriteUninstaller
  CreateShortcuts

  OK "Install complete."
} else {
  # Repair mode: recopy + reinstall deps + rewrite scripts + re-register tasks + recreate shortcuts
  CopyProjectFiles
  InstallServerDeps -Force
  WriteRuntimeScripts
  WriteHealthTray
  RegisterTasks
  WriteUninstaller
  CreateShortcuts

  OK "Repair complete."
}

I "Chrome extension folder: $ExtDir"
I "Extension instructions: $BaseDir\INSTALL-EXTENSION.txt"
I "NZXT CAM Web Integration URL: $Url"
I "Logs: $LogPath"

# Show extension instructions on fresh install only
if ($Mode -eq "Install") {
  try { Start-Process "notepad.exe" -ArgumentList (Join-Path $BaseDir "INSTALL-EXTENSION.txt") | Out-Null } catch {}
  try { Start-Process "chrome.exe" -ArgumentList "chrome://extensions" | Out-Null } catch {}
}
