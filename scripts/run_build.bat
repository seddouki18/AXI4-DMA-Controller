@echo off
REM ==========================================================================
REM  run_build.bat - OOC synthesis + place + route of dma_top, with reports
REM  Vivado 2018.2, part xc7z020clg400-1, 100 MHz. Duration: about 3 to 6 min.
REM  Writes reports\*.rpt, reports\tool_version.txt, reports\vivado_build.log
REM  and build\dma_routed.dcp. Does not touch the GUI project in vivado\.
REM ==========================================================================
call C:\Xilinx\Vivado\2018.2\settings64.bat
cd /d "%~dp0.."
if not exist reports mkdir reports
if not exist build mkdir build

call vivado -mode batch -source scripts/build_ooc.tcl -log reports/vivado_build.log -journal build/vivado_build.jou
if errorlevel 1 goto ERR

findstr /c:"BUILD DONE" reports\vivado_build.log >nul
if errorlevel 1 goto ERR

echo.
echo ##########################################
echo ##### BUILD DONE                     #####
echo ##### Reports are in the reports\ folder
echo ##########################################
pause
exit /b 0

:ERR
echo.
echo ##########################################
echo ##### BUILD FAILED                   #####
echo ##### Open reports\vivado_build.log  #####
echo ##########################################
pause
exit /b 1
