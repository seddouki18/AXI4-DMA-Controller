@echo off
REM ==========================================================================
REM  run_regression.bat - XSim regression over SEED and MAX_BURST_BEATS
REM  Vivado 2018.2. Compiles once, elaborates one snapshot per configuration
REM  (generics are bound at elaboration), runs it, and reads the log.
REM  Output: reports\regression_xsim.csv and sim_reg\sim_s<seed>_b<beats>.log
REM  Duration: roughly 1 to 2 minutes per configuration.
REM ==========================================================================
setlocal EnableDelayedExpansion
call C:\Xilinx\Vivado\2018.2\settings64.bat
cd /d "%~dp0.."
if not exist reports mkdir reports
if exist sim_reg rmdir /s /q sim_reg
mkdir sim_reg
cd sim_reg

echo ===== Compile (xvhdl) =====
call xvhdl -2008 ..\rtl\dma_pkg.vhd ..\rtl\dma_burst_planner.vhd ..\rtl\dma_burst_buffer.vhd ..\rtl\dma_axi_lite_regs.vhd ..\rtl\dma_engine.vhd ..\rtl\dma_top.vhd ..\tb\tb_dma_top.vhd > compile.log 2>&1
if errorlevel 1 goto ERR

set CSV=..\reports\regression_xsim.csv
>"%CSV%" echo seed,max_beats,result
set NPASS=0
set NFAIL=0

for %%C in (1:256 2:256 3:256 4:256 5:256 6:256 1:1 1:16 1:64 2:16 3:64) do (
  for /f "tokens=1,2 delims=:" %%a in ("%%C") do (
    set SEED=%%a
    set MAXB=%%b
  )
  echo ===== seed=!SEED!  max_beats=!MAXB! =====
  call xelab tb_dma_top -s reg_!SEED!_!MAXB! -generic_top "G_SEED=!SEED!" -generic_top "G_MAX_BEATS=!MAXB!" > elab_s!SEED!_b!MAXB!.log 2>&1
  call xsim reg_!SEED!_!MAXB! -runall -log sim_s!SEED!_b!MAXB!.log > nul 2>&1
  findstr /c:"ALL TESTS PASSED" sim_s!SEED!_b!MAXB!.log > nul
  if errorlevel 1 (
    >>"%CSV%" echo !SEED!,!MAXB!,FAIL
    set /a NFAIL+=1
    echo     FAIL
  ) else (
    >>"%CSV%" echo !SEED!,!MAXB!,PASS
    set /a NPASS+=1
    echo     PASS
  )
)

echo.
echo ##########################################
echo ##### PASS=!NPASS!  FAIL=!NFAIL!
echo ##### Table: reports\regression_xsim.csv
echo ##########################################
pause
if !NFAIL! gtr 0 exit /b 1
exit /b 0

:ERR
echo ##### ERROR during compile: open sim_reg\compile.log #####
pause
exit /b 1
