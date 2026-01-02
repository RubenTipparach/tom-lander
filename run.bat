@echo off
echo.
echo ========================================
echo   CHIEFTAN ENGINE - SOFTWARE RENDERER
echo ========================================
echo.
echo Starting...
echo.
cd /d "%~dp0"
love . main.lua
if errorlevel 1 (
    echo.
    echo Error: LOVE2D not found or failed to launch
    echo Please ensure LOVE2D is installed and in your PATH
    echo Download from: https://love2d.org/
    echo.
)
