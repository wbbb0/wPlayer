@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hdc-agent.ps1" %*
