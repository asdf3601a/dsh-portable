@echo off
setlocal EnableExtensions
call "%~dp0dsh.cmd" web %*
exit /b %ERRORLEVEL%