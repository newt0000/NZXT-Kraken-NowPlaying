param(
  [ValidateSet("Install","Repair")]
  [string]$Mode = "Install"
)

$ErrorActionPreference = "Stop"

# -------------------------
# Config
# -------------------------
$AppName   = "KrakenNowPlaying"
$BaseDir   = Join-Path $env:LOCALAPPDATA $AppName
$AppDir    = Join-Path $BaseDir "app"
$ServerDir = Join-Path $AppDir "server"
$ExtDir    = Join-Path $AppDir "extension"

$LogDir     = Join-Path $BaseDir "logs"
$InstallLog = Join-Path $LogDir "install.log"
$ServerLog  = Join-Path $LogDir "server.log"

$Port = 27123
$Url  = "http://127.0.0.1:$Port/"

$TaskAll = "$AppName (AutoStart)"

$StartMenuFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName"
$DesktopDir = [Environment]::GetFolderPath("Desktop")

$NodeInstallerUrl  = "https://nodejs.org/dist/v20.18.1/node-v20.18.1-x64.msi"
$NodeInstallerPath = Join-Path $BaseDir "node-lts-x64.msi"

# Source folders relative to this installer script
$SrcRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcServer  = Join-Path $SrcRoot "server"
$SrcExt     = Join-Path $SrcRoot "extension"
$SrcAssets  = Join-Path $SrcRoot "assets"
$SrcIcon    = Join-Path $SrcAssets "icon.ico"

# Installed icon path
$IconPath   = Join-Path $BaseDir "icon.ico"

# -------------------------
# Helpers / logging
# -------------------------
function EnsureDir([string]$p) { New-Item -ItemType Directory -Force -Path $p | Out-Null }

EnsureDir $LogDir

function LogLine([string]$msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
  Add-Content -Path $InstallLog -Value $line
}

function Info([string]$m) { Write-Host "[INFO] $m"; LogLine "INFO: $m" }
function Ok([string]$m)   { Write-Host "[ OK ] $m"; LogLine "OK: $m" }
function Warn([string]$m) { Write-Host "[WARN] $m"; LogLine "WARN: $m" }
function Fail([string]$m) { Write-Host "[FAIL] $m"; LogLine "FAIL: $m"; throw $m }

function HasCmd([string]$n) { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }

# -------------------------
# Node checks
# -------------------------
function Find-NodeExe {
  $candidates = @(
    (Join-Path $env:ProgramFiles "nodejs\node.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\nodejs\node.exe")
  )
  foreach ($p in $candidates) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

function Ensure-NodeOnPathForThisProcess([string]$nodeExe) {
  if (-not $nodeExe) { return }
  $nodeDir = Split-Path -Parent $nodeExe
  if ($env:Path -notlike "*$nodeDir*") { $env:Path = "$nodeDir;$env:Path" }

  $npmDir = Join-Path $env:APPDATA "npm"
  if ((Test-Path $npmDir) -and ($env:Path -notlike "*$npmDir*")) {
    $env:Path = "$npmDir;$env:Path"
  }
}

function Ensure-NodeInstalled {
  if (HasCmd "node" -and HasCmd "npm") {
    Ok "Node present: $(node -v) | npm: $(npm -v)"
    return
  }

  $nodeExe = Find-NodeExe
  if ($nodeExe) {
    Ensure-NodeOnPathForThisProcess $nodeExe
    if (HasCmd "node" -and HasCmd "npm") {
      Ok "Node found (PATH refreshed): $(node -v) | npm: $(npm -v)"
      return
    }
  }

  Warn "Node.js not found. This installer can download and run the official Node LTS installer."
  $resp = Read-Host "Install Node LTS now? (Y/N)"
  if ($resp -notin @("Y","y")) { Fail "Node is required. Install Node LTS then rerun." }

  EnsureDir $BaseDir

  Info "Downloading Node installer..."
  Invoke-WebRequest -Uri $NodeInstallerUrl -OutFile $NodeInstallerPath -UseBasicParsing
  Ok "Downloaded: $NodeInstallerPath"

  Info "Launching Node installer. Waiting..."
  try {
    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$NodeInstallerPath`"" -PassThru -Verb RunAs
    $p.WaitForExit()
  } catch {
    Warn "Could not elevate; trying without elevation..."
    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$NodeInstallerPath`"" -PassThru
    $p.WaitForExit()
  }

  $nodeExe = Find-NodeExe
  if (-not $nodeExe) { Fail "Node installer finished but node.exe not found." }

  Ensure-NodeOnPathForThisProcess $nodeExe
  if (!(HasCmd "node") -or !(HasCmd "npm")) {
    Fail "Node installed but not available in this PowerShell session. Log off/on then rerun."
  }

  Ok "Node installed: $(node -v) | npm: $(npm -v)"
}

# -------------------------
# Install files
# -------------------------
function CopyProjectFiles {
  if (!(Test-Path $SrcServer)) { Fail "Missing source folder: $SrcServer" }
  if (!(Test-Path $SrcExt))    { Fail "Missing source folder: $SrcExt" }

  if (!(Test-Path (Join-Path $SrcServer "package.json"))) { Fail "Missing server\package.json" }
  if (!(Test-Path (Join-Path $SrcServer "server.js")))    { Fail "Missing server\server.js" }
  if (!(Test-Path (Join-Path $SrcExt "manifest.json")))   { Fail "Missing extension\manifest.json" }

  EnsureDir $AppDir
  EnsureDir $ServerDir
  EnsureDir $ExtDir

  Info "Copying server..."
  Copy-Item -Path (Join-Path $SrcServer "*") -Destination $ServerDir -Recurse -Force

  Info "Copying extension..."
  Copy-Item -Path (Join-Path $SrcExt "*") -Destination $ExtDir -Recurse -Force

  # Optional icon
  if (Test-Path $SrcIcon) {
    Copy-Item -Path $SrcIcon -Destination $IconPath -Force
    Ok "Icon installed: $IconPath"
  } else {
    Warn "No icon found at $SrcIcon (shortcuts will use default Windows icon)."
  }

  Ok "Files copied to $AppDir"
}

function InstallServerDeps([switch]$Force) {
  Push-Location $ServerDir
  try {
    if ($Force) {
      Info "Repair: npm install"
      npm install | Out-Null
      Ok "Dependencies repaired."
      return
    }

    if (!(Test-Path (Join-Path $ServerDir "node_modules"))) {
      Info "npm install"
      npm install | Out-Null
      Ok "Dependencies installed."
    } else {
      Ok "Dependencies already present."
    }
  } finally {
    Pop-Location
  }
}

# -------------------------
# Runtime scripts (hidden launches)
# -------------------------
function WriteRuntimeScripts {
  EnsureDir $BaseDir
  EnsureDir $LogDir

  # ---- Stop-Server.ps1 (kills process tree owning port; avoids $PID reserved var) ----
  $stopPs1 = Join-Path $BaseDir "Stop-Server.ps1"
@"
`$ErrorActionPreference = "SilentlyContinue"
`$port = $Port

function Kill-Tree([int]`$p) {
  if (-not `$p) { return }
  & taskkill.exe /PID `$p /T /F | Out-Null
}

# Kill anything listening on the port (covers respawners like nodemon via /T)
`$conns = Get-NetTCPConnection -LocalPort `$port -ErrorAction SilentlyContinue
if (`$conns) {
  `$pids = `$conns | Select-Object -ExpandProperty OwningProcess -Unique
  foreach (`$p in `$pids) { Kill-Tree ([int]`$p) }
}

# Extra safety: kill node/nodemon whose command line mentions server.js or this app path
try {
  `$procs = Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='nodemon.exe'" -ErrorAction SilentlyContinue
  foreach (`$proc in `$procs) {
    `$cmd = `$proc.CommandLine
    if (`$cmd -and (`$cmd -match "server\.js" -or `$cmd -match "KrakenNowPlaying" -or `$cmd -match "now-playing")) {
      Kill-Tree ([int]`$proc.ProcessId)
    }
  }
} catch {}

Write-Host "Stop complete."
"@ | Set-Content -Path $stopPs1 -Encoding UTF8

  # ---- Server runner (no window) ----
  $serverRunPs1 = Join-Path $BaseDir "Server-Run.ps1"
@"
`$ErrorActionPreference = "Stop"
`$serverDir = "$ServerDir"
`$log = "$ServerLog"

New-Item -ItemType Directory -Force -Path "$(Split-Path -Parent $ServerLog)" | Out-Null
Set-Location `$serverDir

"`$(Get-Date -Format o) Server-Run start" | Add-Content `$log

# Avoid duplicates by port
try {
  `$conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
  if (`$conn) {
    "`$(Get-Date -Format o) Port $Port already in use; assume running." | Add-Content `$log
    exit 0
  }
} catch {}

try {
  npm start 2>&1 | Tee-Object -FilePath `$log -Append | Out-Null
} catch {
  "`$(Get-Date -Format o) Server crashed: `$($_.Exception.Message)" | Add-Content `$log
  exit 1
}
"@ | Set-Content -Path $serverRunPs1 -Encoding UTF8

  # ---- Tray script: Quit runs Stop-Server IN THIS PROCESS, verifies port, then exits tray ----
  $trayPs1 = Join-Path $BaseDir "HealthTray.ps1"
@"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$port       = $Port
`$checkUrl   = "http://127.0.0.1:$Port/nowplaying"
`$displayUrl = "$Url"
`$baseDir    = Join-Path `$env:LOCALAPPDATA "$AppName"
`$stopPs1    = Join-Path `$baseDir "Stop-Server.ps1"
`$serverLog  = Join-Path `$baseDir "logs\server.log"

function MakeIcon([System.Drawing.Color]`$color) {
  `$bmp = New-Object System.Drawing.Bitmap 16,16
  `$g = [System.Drawing.Graphics]::FromImage(`$bmp)
  `$g.Clear([System.Drawing.Color]::Transparent)
  `$brush = New-Object System.Drawing.SolidBrush `$color
  `$g.FillEllipse(`$brush, 1,1,14,14)
  `$g.Dispose()
  return [System.Drawing.Icon]::FromHandle(`$bmp.GetHicon())
}

`$iconUp = MakeIcon ([System.Drawing.Color]::LimeGreen)
`$iconDown = MakeIcon ([System.Drawing.Color]::Red)

`$ni = New-Object System.Windows.Forms.NotifyIcon
`$ni.Text = "$AppName"
`$ni.Visible = `$true
`$ni.Icon = `$iconDown

`$menu = New-Object System.Windows.Forms.ContextMenuStrip

`$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem "Open Display URL"
`$miOpen.add_Click({ Start-Process `$displayUrl | Out-Null })

`$miLog = New-Object System.Windows.Forms.ToolStripMenuItem "Open Server Log"
`$miLog.add_Click({ Start-Process "notepad.exe" -ArgumentList `$serverLog | Out-Null })

`$miQuit = New-Object System.Windows.Forms.ToolStripMenuItem "Quit (Stop Server)"
`$miQuit.add_Click({
  try {
    if (Test-Path `$stopPs1) {
      # Run stop script reliably
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`$stopPs1" | Out-Null

      Start-Sleep -Milliseconds 500

      # If still listening, last-resort kill tree by port
      `$conns = Get-NetTCPConnection -LocalPort `$port -ErrorAction SilentlyContinue
      if (`$conns) {
        `$pids = `$conns | Select-Object -ExpandProperty OwningProcess -Unique
        foreach (`$p in `$pids) { & taskkill.exe /PID `$p /T /F | Out-Null }
      }
    } else {
      `$ni.ShowBalloonTip(4000, "$AppName", "Stop-Server.ps1 missing.", [System.Windows.Forms.ToolTipIcon]::Error)
      Start-Sleep -Milliseconds 1200
    }
  } catch {
    `$ni.ShowBalloonTip(4000, "$AppName", "Failed to stop server. Try Stop Server shortcut.", [System.Windows.Forms.ToolTipIcon]::Error)
    Start-Sleep -Milliseconds 1200
  }

  # Exit tray last (ensures stop happens first)
  `$ni.Visible = `$false
  [System.Windows.Forms.Application]::Exit()
})

`$menu.Items.AddRange(@(`$miOpen, `$miLog, `$miQuit))
`$ni.ContextMenuStrip = `$menu

`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 2000
`$timer.add_Tick({
  `$isUp = `$false
  try {
    `$resp = Invoke-WebRequest -Uri `$checkUrl -UseBasicParsing -TimeoutSec 2
    `$isUp = (`$resp.StatusCode -eq 200)
  } catch { `$isUp = `$false }

  if (`$isUp) {
    `$ni.Icon = `$iconUp
    `$ni.Text = "$AppName - OK"
  } else {
    `$ni.Icon = `$iconDown
    `$ni.Text = "$AppName - DOWN"
  }
})
`$timer.Start()

[System.Windows.Forms.Application]::Run()
"@ | Set-Content -Path $trayPs1 -Encoding UTF8

  # ---- Hidden launchers (no windows) ----
  $runServerVbs = Join-Path $BaseDir "RunServerHidden.vbs"
@"
Dim shell : Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$BaseDir\Server-Run.ps1""", 0, False
"@ | Set-Content -Path $runServerVbs -Encoding ASCII

  $runTrayVbs = Join-Path $BaseDir "RunTrayHidden.vbs"
@"
Dim shell : Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File ""$BaseDir\HealthTray.ps1""", 0, False
"@ | Set-Content -Path $runTrayVbs -Encoding ASCII

  # One launcher to start BOTH with one shortcut
  $runAllVbs = Join-Path $BaseDir "RunAllHidden.vbs"
@"
Dim shell : Set shell = CreateObject("WScript.Shell")
shell.Run "wscript.exe ""$BaseDir\RunServerHidden.vbs""", 0, False
shell.Run "wscript.exe ""$BaseDir\RunTrayHidden.vbs""", 0, False
"@ | Set-Content -Path $runAllVbs -Encoding ASCII

  # ---- Open CAM URL helper ----
  $openPs1 = Join-Path $BaseDir "Open-CAM-URL.ps1"
@"
`$ErrorActionPreference = "SilentlyContinue"
`$url = "$Url"
Set-Clipboard -Value `$url
Start-Process `$url | Out-Null
"@ | Set-Content -Path $openPs1 -Encoding UTF8

  Ok "Runtime scripts written."
}

# -------------------------
# Auto-start (Task Scheduler or HKCU fallback)
# -------------------------
function TaskExists([string]$name) {
  try { return [bool](Get-ScheduledTask -TaskName $name -ErrorAction Stop) } catch { return $false }
}

function StartAllNow {
  $runAllVbs = Join-Path $BaseDir "RunAllHidden.vbs"
  try { Start-Process "wscript.exe" -ArgumentList "`"$runAllVbs`"" | Out-Null } catch { Warn "Could not start (silent): $($_.Exception.Message)" }
}

function RegisterAutoStart {
  $runAllVbs = Join-Path $BaseDir "RunAllHidden.vbs"
  if (!(Test-Path $runAllVbs)) { Fail "Missing: $runAllVbs" }

  $taskSetupOk = $false

  # Try Task Scheduler (often blocked on your machine)
  try {
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    try { Unregister-ScheduledTask -TaskName $TaskAll -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

    $actionAll = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$runAllVbs`""
    $taskObj = New-ScheduledTask -Action $actionAll -Trigger $trigger -Settings $settings

    Register-ScheduledTask -TaskName $TaskAll -InputObject $taskObj -Force -ErrorAction Stop | Out-Null

    if (TaskExists $TaskAll) {
      $taskSetupOk = $true
      Ok "Auto-start configured via Task Scheduler."
    }
  } catch {
    Warn "Task Scheduler setup failed; will fallback. Error: $($_.Exception.Message)"
    $taskSetupOk = $false
  }

  if ($taskSetupOk) {
    try { Start-ScheduledTask -TaskName $TaskAll | Out-Null } catch { Warn "Could not start task now: $($_.Exception.Message)" }
    return
  }

  # HKCU Run fallback (no admin required)
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  $allCmd = "wscript.exe `"$runAllVbs`""

  try {
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name "$AppName-All" -Value $allCmd -PropertyType String -Force | Out-Null
    Ok "Auto-start configured via HKCU Run key."
  } catch {
    Fail "Failed to configure HKCU Run startup: $($_.Exception.Message)"
  }

  StartAllNow
}

# -------------------------
# Shortcuts (with icon fallback)
# -------------------------
function Get-ShortcutIconLocation {
  if (Test-Path $IconPath) { return "$IconPath,0" }
  return "$env:SystemRoot\System32\shell32.dll,220"
}

function New-Shortcut([string]$ShortcutPath, [string]$TargetPath, [string]$Arguments, [string]$WorkingDir, [string]$Description) {
  $wsh = New-Object -ComObject WScript.Shell
  $sc = $wsh.CreateShortcut($ShortcutPath)
  $sc.TargetPath = $TargetPath
  if ($Arguments)  { $sc.Arguments = $Arguments }
  if ($WorkingDir) { $sc.WorkingDirectory = $WorkingDir }
  if ($Description){ $sc.Description = $Description }
  $sc.IconLocation = (Get-ShortcutIconLocation)
  $sc.Save()
}

function CreateShortcuts {
  EnsureDir $StartMenuFolder

  $ps = (Get-Command powershell.exe).Source
  $open = Join-Path $BaseDir "Open-CAM-URL.ps1"
  $stop = Join-Path $BaseDir "Stop-Server.ps1"
  $uninst = Join-Path $BaseDir "Uninstall.ps1"
  $runAllVbs = Join-Path $BaseDir "RunAllHidden.vbs"
  $repairArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$SrcRoot\installer.ps1`" -Mode Repair"

  # Desktop: Open CAM URL
  New-Shortcut (Join-Path $DesktopDir "Open CAM URL.lnk") $ps "-NoProfile -ExecutionPolicy Bypass -File `"$open`"" $BaseDir "Open/copy CAM URL"
  Ok "Desktop shortcut created."

  # Start Menu: ONE Start shortcut starts server + tray (silent, no windows)
  New-Shortcut (Join-Path $StartMenuFolder "Start (Silent).lnk") "wscript.exe" "`"$runAllVbs`"" $BaseDir "Start server + tray (silent)"

  # Stop server
  New-Shortcut (Join-Path $StartMenuFolder "Stop Server.lnk") $ps "-NoProfile -ExecutionPolicy Bypass -File `"$stop`"" $BaseDir "Stop server"

  # Open display URL
  New-Shortcut (Join-Path $StartMenuFolder "Open CAM URL.lnk") $ps "-NoProfile -ExecutionPolicy Bypass -File `"$open`"" $BaseDir "Open/copy CAM URL"

  # Logs
  New-Shortcut (Join-Path $StartMenuFolder "Open Server Log.lnk") "notepad.exe" "`"$ServerLog`"" $BaseDir "Open server log"

  # Repair
  New-Shortcut (Join-Path $StartMenuFolder "Repair.lnk") $ps $repairArgs $BaseDir "Repair install"

  # Uninstall
  New-Shortcut (Join-Path $StartMenuFolder "Uninstall.lnk") $ps "-NoProfile -ExecutionPolicy Bypass -File `"$uninst`"" $BaseDir "Uninstall"

  Ok "Start Menu shortcuts created at $StartMenuFolder"
}

# -------------------------
# Uninstaller
# -------------------------
function WriteUninstaller {
  $uninstall = Join-Path $BaseDir "Uninstall.ps1"
@"
`$ErrorActionPreference = "SilentlyContinue"

# Stop server first
try { & (Join-Path "$BaseDir" "Stop-Server.ps1") } catch {}

# Remove scheduled task
try { Unregister-ScheduledTask -TaskName "$TaskAll" -Confirm:`$false | Out-Null } catch {}

# Remove HKCU startup
try {
  `$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  Remove-ItemProperty -Path `$runKey -Name "$AppName-All" -ErrorAction SilentlyContinue
} catch {}

# Remove shortcuts
try { Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path "$DesktopDir" "Open CAM URL.lnk") } catch {}
try { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$StartMenuFolder" } catch {}

# Remove files
try { Remove-Item -Recurse -Force -Path "$BaseDir" } catch {}

Write-Host "Uninstalled."
"@ | Set-Content -Path $uninstall -Encoding UTF8

  Ok "Uninstaller written."
}

# -------------------------
# MAIN
# -------------------------
try {
  LogLine "----- $Mode begin -----"
  Info "Install log: $InstallLog"

  Ensure-NodeInstalled
  CopyProjectFiles
  if ($Mode -eq "Repair") { InstallServerDeps -Force } else { InstallServerDeps }

  WriteRuntimeScripts
  RegisterAutoStart
  WriteUninstaller
  CreateShortcuts

  Ok "$Mode complete."
  Info "CAM URL: $Url"
  Info "Extension folder: $ExtDir"
  Info "Server log: $ServerLog"
  Info "Install log: $InstallLog"
} catch {
  Warn "Installer failed. Check: $InstallLog"
  throw
}
