@echo off
REM ==========================================================================
REM  run_sim.bat - full self-checking simulation of the AXI4 DMA (V1)
REM  Vivado 2018.2 XSim, VHDL-2008, seed 1, MAX_BURST_BEATS = 256.
REM  Double-click it, or run it from any folder. Work files go to sim_cmd\.
REM  PASS only if the log contains "ALL TESTS PASSED".
REM ==========================================================================
call C:\Xilinx\Vivado\2018.2\settings64.bat
cd /d "%~dp0.."
if exist sim_cmd rmdir /s /q sim_cmd
mkdir sim_cmd
cd sim_cmd

echo.
echo ===== 1/3 Compile (xvhdl) =====
call xvhdl -2008 ..\rtl\dma_pkg.vhd ..\rtl\dma_burst_planner.vhd ..\rtl\dma_burst_buffer.vhd ..\rtl\dma_axi_lite_regs.vhd ..\rtl\dma_engine.vhd ..\rtl\dma_top.vhd ..\tb\tb_dma_top.vhd
if errorlevel 1 goto ERR

echo.
echo ===== 2/3 Elaborate (xelab) =====
call xelab -debug typical tb_dma_top -s tbsim
if errorlevel 1 goto ERR

echo.
echo ===== 3/3 Simulate (xsim, about 1 to 2 minutes) =====
call xsim tbsim -runall -log sim.log

findstr /c:"ALL TESTS PASSED" sim.log >nul
if errorlevel 1 goto FAIL

echo.
findstr /c:"ALL TESTS PASSED" sim.log
echo ##########################################
echo ##### RESULT: ALL TESTS PASSED       #####
echo ##### Log: sim_cmd\sim.log           #####
echo ##########################################
pause
exit /b 0

:FAIL
echo.
echo ##########################################
echo ##### RESULT: FAILED                 #####
echo ##### Open sim_cmd\sim.log           #####
echo ##########################################
pause
exit /b 1

:ERR
echo.
echo ##########################################
echo ##### ERROR in compile or elaborate  #####
echo ##### Read the messages above        #####
echo ##########################################
pause
exit /b 1
