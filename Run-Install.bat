@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ^
  "try { Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0Install-EssentialApps.ps1\"' -Verb RunAs -ErrorAction Stop } catch { Write-Host ''; Write-Host ' Administrator access was denied.' -ForegroundColor Red; Write-Host ' Please re-run Run-Install.bat and accept the UAC prompt.' -ForegroundColor Yellow; Write-Host ''; Read-Host 'Press Enter to close' }"
