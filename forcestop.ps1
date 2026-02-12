$serverPid = (Get-NetTCPConnection -LocalPort 27123 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess)
if ($serverPid) {
Stop-Process -Id $serverPid -Force
}

# Kill any wscript/powershell that is running HealthTray.ps1
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='wscript.exe'" |
  Where-Object { $_.CommandLine -match 'HealthTray\.ps1|RunTrayHidden\.vbs|RunAllHidden\.vbs' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# Kill any leftover node servers started by this project (safe filter by path/name)
Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='nodemon.exe'" |
  Where-Object { $_.CommandLine -match 'KrakenNowPlaying|server\.js|now-playing' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "KrakenNowPlaying-All" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name "KrakenNowPlaying-Server" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name "KrakenNowPlaying-Tray" -ErrorAction SilentlyContinue

Get-ScheduledTask | Where-Object { $_.TaskName -like "KrakenNowPlaying*" } |
  ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue }
