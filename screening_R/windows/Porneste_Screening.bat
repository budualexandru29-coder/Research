@echo off
REM ==================================================================
REM  Porneste aplicatia de screening (dublu-click pe acest fisier
REM  sau pe iconita de pe Desktop creata de Creeaza_iconita_pe_Desktop.bat)
REM ==================================================================
title Screening titlu si abstract
cd /d "%~dp0.."

REM --- caut programul Rscript.exe (R instalat) ---
set "RSCRIPT="
for /f "delims=" %%R in ('where Rscript 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%R"
if not defined RSCRIPT for /d %%D in ("%ProgramFiles%\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
if not defined RSCRIPT for /d %%D in ("%LOCALAPPDATA%\Programs\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"

if not defined RSCRIPT goto :fara_r

echo.
echo  Pornesc aplicatia de screening...
echo  (prima data poate dura cateva minute: se instaleaza pachetul shiny)
echo.
echo  NU inchide aceasta fereastra cat timp lucrezi.
echo  Cand termini, inchide fereastra ca sa opresti aplicatia.
echo.
"%RSCRIPT%" "porneste.R"
echo.
echo  Aplicatia s-a oprit.
pause
exit /b 0

:fara_r
echo.
echo  R nu este instalat pe acest calculator.
echo  Se deschide pagina de descarcare: apasa "install R for the first time",
echo  descarca si instaleaza R (Next, Next, Finish), apoi porneste din nou.
echo.
start "" "https://cran.r-project.org/bin/windows/base/"
pause
exit /b 1
