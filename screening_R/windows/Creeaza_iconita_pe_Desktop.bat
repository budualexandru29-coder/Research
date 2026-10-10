@echo off
REM ==================================================================
REM  Creeaza pe Desktop iconita "Porneste Screening".
REM  Se ruleaza O SINGURA DATA (dublu-click pe acest fisier).
REM ==================================================================
set "TINTA=%~dp0Porneste_Screening.bat"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d=[Environment]::GetFolderPath('Desktop'); $s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $d 'Porneste Screening.lnk')); $s.TargetPath=$env:TINTA; $s.WorkingDirectory=(Split-Path $env:TINTA); $s.Description='Aplicatia de screening titlu si abstract'; $s.Save()"
if errorlevel 1 (
  echo.
  echo  Nu am reusit sa creez iconita.
  pause
  exit /b 1
)
echo.
echo  Gata! Pe Desktop a aparut iconita "Porneste Screening".
echo.
pause
