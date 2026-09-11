@echo off
REM Run this file via right-click -> Run as administrator
msiexec /i "C:\Temp\mssql-setup\SqlLocalDB.msi" IACCEPTSQLLOCALDBLICENSETERMS=YES /qb /norestart
if errorlevel 1 (
  echo Install failed. Code=%ERRORLEVEL%
  pause
  exit /b %ERRORLEVEL%
)
echo LocalDB installed. Starting instance...
"%ProgramFiles%\Microsoft SQL Server\160\Tools\Binn\SqlLocalDB.exe" create MSSQLLocalDB 16.0 -s
"%ProgramFiles%\Microsoft SQL Server\160\Tools\Binn\SqlLocalDB.exe" info MSSQLLocalDB
echo.
echo In SSMS connect to:  (localdb)\MSSQLLocalDB
echo Authentication: Windows Authentication
pause
