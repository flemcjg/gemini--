@echo off
setlocal
set "PIDFILE=%~dp0data\widget.pid"
if exist "%PIDFILE%" (
  set /p WPID=<"%PIDFILE%"
  if not "%WPID%"=="" taskkill /PID %WPID% /F >nul 2>&1
  del /f /q "%PIDFILE%" >nul 2>&1
)
echo GPT-Miao widget stopped.
