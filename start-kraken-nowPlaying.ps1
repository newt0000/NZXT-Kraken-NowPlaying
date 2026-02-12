# Start-KrakenNowPlaying.ps1
# Startup-safe launcher:
# - Finds server folder (package.json + server.js)
# - Ensures Node.js + npm exist (downloads & launches installer if missing)
# - Ensures deps installed
# - Starts server
# - Logs to %LOCALAPPDATA%\KrakenNowPlaying\launcher.log
Start-Sleep -Seconds 5

$ErrorActionPreference = "Stop"

# -------------------------
# Settings
# -------------------------
$Port = 27123
$Root = $PSScriptRoot
$LogDir = Join-Path $env:LOCALAPPDATA "KrakenNowPlaying"
$LogPath = Join-Path $LogDir "launcher.log"
$NodeInstallerUrl = "https://nodejs.org/dist/v20.18.1/node-v20.18.1-x64.msi"  # Node 20 LTS (stable line)
$NodeInstallerPath = Join-Path $LogDir "node-lts-x64.msi"
$WaitForNodeSeconds = 300  # 5 minutes

# -------------------------
# Helpers
# -------------------------
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log($msg) {
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "$stamp  $msg"
  Add-Content -Path $LogPath -Value $line
}

function Fail($msg) {
  Log "FAIL: $msg"
  Write-Host "❌ $msg" -ForegroundColor Red
  exit 1
}

function Warn($msg) {
  Log "WARN: $msg"
  Write-Host "⚠️  $msg" -ForegroundColor Yellow
}

function Ok($msg) {
  Log "OK: $msg"
  Write-Host "✅ $msg" -ForegroundColor Green
}

function Has-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# Finds a directory containing BOTH package.json and server.js
function Find-ServerDir($rootPath) {
  if ((Test-Path (Join-Path $rootPath "package.json")) -and (Test-Path (Join-Path $rootPath "server.js"))) {
    return $rootPath
  }

  $match = Get-ChildItem -Path $rootPath -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
      (Test-Path (Join-Path $_.FullName "package.json")) -and (Test-Path (Join-Path $_.FullName "server.js"))
    } |
    Select-Object -First 1

  if ($match) { return $match.FullName }
  return $null
}

function Port-InUse($port) {
  try {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    return [bool]$conn
  } catch {
    return $false
  }
}
function Get-NodeInstallCandidates {
  $candidates = @()

  # System-wide install (most common)
  $candidates += Join-Path ${env:ProgramFiles} "nodejs\node.exe"
  $candidates += Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe"

  # Some setups / older per-user installs (less common)
  $candidates += Join-Path $env:LOCALAPPDATA "Programs\nodejs\node.exe"
  $candidates += Join-Path $env:APPDATA "npm\node.exe" # rare, but harmless

  return $candidates
}

function Find-NodeExe {
  foreach ($p in Get-NodeInstallCandidates) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

function Ensure-NodeBinOnPath($nodeExePath) {
  $nodeDir = Split-Path -Parent $nodeExePath

  # Add Node dir to PATH for THIS process so the script can keep going immediately
  if ($env:Path -notlike "*$nodeDir*") {
    $env:Path = "$nodeDir;$env:Path"
  }

  # npm is typically a .cmd in these locations:
  $npmCmdCandidates = @(
    (Join-Path $nodeDir "npm.cmd"),
    (Join-Path $env:APPDATA "npm\npm.cmd")
  )

  foreach ($c in $npmCmdCandidates) {
    if (Test-Path $c) {
      $npmDir = Split-Path -Parent $c
      if ($env:Path -notlike "*$npmDir*") {
        $env:Path = "$npmDir;$env:Path"
      }
      break
    }
  }
}

function Ensure-Node {
  # First try: already in PATH
  if (Has-Command "node" -and Has-Command "npm") {
    Ok "Node.js already installed: $(node -v) | npm: $(npm -v)"
    return
  }

  # Second try: installed but not on PATH yet
  $nodeExe = Find-NodeExe
  if ($nodeExe) {
    Ensure-NodeBinOnPath $nodeExe
    if (Has-Command "node" -and Has-Command "npm") {
      Ok "Node.js found (PATH refreshed for this run): $(node -v) | npm: $(npm -v)"
      return
    } else {
      Warn "Node.exe exists at $nodeExe, but npm not found yet. Continuing anyway; npm usually comes with Node."
      return
    }
  }

  # Not installed: download installer if needed
  if (!(Test-Path $NodeInstallerPath)) {
    Warn "Node.js and/or npm not found. Downloading Node LTS installer..."
    try {
      Invoke-WebRequest -Uri $NodeInstallerUrl -OutFile $NodeInstallerPath -UseBasicParsing
      Ok "Downloaded Node installer to: $NodeInstallerPath"
    } catch {
      Fail "Failed to download Node installer. Error: $($_.Exception.Message)"
    }
  } else {
    Warn "Installer already present: $NodeInstallerPath"
  }

  # Launch installer AND WAIT for it to finish
  Warn "Launching Node installer (complete the install). Waiting for it to finish..."
  try {
    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$NodeInstallerPath`"" -PassThru -Verb RunAs
    $p.WaitForExit()
  } catch {
    Warn "Could not launch with elevation. Trying without elevation..."
    try {
      $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$NodeInstallerPath`"" -PassThru
      $p.WaitForExit()
    } catch {
      Fail "Could not launch Node installer. Error: $($_.Exception.Message)"
    }
  }

  # After installer completes, detect by file path and patch PATH
  $nodeExe = Find-NodeExe
  if (-not $nodeExe) {
    Fail "Installer finished but node.exe was not found in expected locations. Try installing Node LTS manually, then rerun."
  }

  Ensure-NodeBinOnPath $nodeExe

  if (Has-Command "node" -and Has-Command "npm") {
    Ok "Node installed and detected: $(node -v) | npm: $(npm -v)"
    return
  }

  # Fallback: call node.exe directly at least
  Warn "node.exe detected at $nodeExe but npm still not detected via PATH in this session."
  Warn "Log off/on may be required for PATH to update globally. The script will attempt to proceed."
}


# -------------------------
# Main
# -------------------------
Log "----- Launcher start -----"
Ok "Launcher starting from: $Root"

# Find server dir
$ServerDir = Find-ServerDir $Root
if (-not $ServerDir) {
  Fail "Could not find server folder containing package.json + server.js under: $Root"
}
Ok "Server directory: $ServerDir"

# Ensure Node/npm exists (install if missing)
Ensure-Node

# Move to server folder
Set-Location $ServerDir

# Ensure deps
if (!(Test-Path (Join-Path $ServerDir "node_modules"))) {
  Warn "node_modules not found -> running npm install"
  & npm install
  Ok "Dependencies installed."
} else {
  Ok "Dependencies already present."
}

# Port check
if (Port-InUse $Port) {
  Warn "Port $Port is in use. Server may already be running."
  Warn "If you see issues, stop the existing process using this port."
}

# Start server
Ok "Starting server via npm start"
try {
  Start-Process "http://127.0.0.1:$Port/" | Out-Null
} catch {
  Warn "Could not open browser automatically."
}

# Keep running in foreground for logging clarity (startup task can run hidden)
& npm start

Log "----- Launcher end -----"
