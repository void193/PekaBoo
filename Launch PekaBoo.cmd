@echo off
cd /d "%~dp0"
start "" "%~dp0tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0game" --resolution 1280x720
