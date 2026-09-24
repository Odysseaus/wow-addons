@echo off
cd /d "%~dp0"
start "WoW Grok bridge" cmd /k node supervisor.js
