@echo off
setlocal enabledelayedexpansion

echo.
echo ========================================
echo   TOM LANDER - BUILD SCRIPT
echo ========================================
echo.

cd /d "%~dp0"

set GAME_NAME=tom-lander
set BUILD_DIR=build
set LOVE_FILE=%BUILD_DIR%\%GAME_NAME%.love

:: Create build directory
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: Clean previous build
if exist "%LOVE_FILE%" del "%LOVE_FILE%"

echo [1/3] Creating .love package...

:: Create a temporary directory for packaging
set TEMP_DIR=%BUILD_DIR%\temp_package
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

:: Copy game files to temp directory
echo   - Copying main.lua...
copy "main.lua" "%TEMP_DIR%\" >nul
echo   - Copying conf.lua...
copy "conf.lua" "%TEMP_DIR%\" >nul
echo   - Copying src\...
xcopy "src" "%TEMP_DIR%\src\" /E /I /Q >nul
echo   - Copying assets\...
xcopy "assets" "%TEMP_DIR%\assets\" /E /I /Q >nul

:: Create .zip file first, then rename to .love
set ZIP_FILE=%BUILD_DIR%\%GAME_NAME%.zip
if exist "%ZIP_FILE%" del "%ZIP_FILE%"
if exist "%LOVE_FILE%" del "%LOVE_FILE%"

echo   - Compressing to zip...
powershell -NoProfile -Command "Compress-Archive -Path '%TEMP_DIR%\*' -DestinationPath '%ZIP_FILE%' -Force"

:: Rename .zip to .love
echo   - Renaming to .love...
ren "%ZIP_FILE%" "%GAME_NAME%.love"

:: Cleanup temp directory
rmdir /s /q "%TEMP_DIR%"

if not exist "%LOVE_FILE%" (
    echo ERROR: Failed to create .love file
    goto :error
)

echo   - Created: %LOVE_FILE%
echo.

:: Check for love.exe to create standalone exe
echo [2/3] Checking for Love2D installation...

set LOVE_DIR=
:: Check common Love2D installation paths
if exist "C:\Program Files\LOVE\love.exe" set "LOVE_DIR=C:\Program Files\LOVE"
if exist "C:\Program Files (x86)\LOVE\love.exe" set "LOVE_DIR=C:\Program Files (x86)\LOVE"
if exist "%LOCALAPPDATA%\Programs\LOVE\love.exe" set "LOVE_DIR=%LOCALAPPDATA%\Programs\LOVE"

:: Check if love is in PATH
where love.exe >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%i in ('where love.exe') do set "LOVE_DIR=%%~dpi"
)

:: Remove trailing backslash if present
if "%LOVE_DIR:~-1%"=="\" set "LOVE_DIR=%LOVE_DIR:~0,-1%"

if "%LOVE_DIR%"=="" (
    echo   - Love2D not found. Skipping .exe creation.
    echo   - To create standalone .exe, install Love2D or set LOVE_PATH environment variable
    goto :skippe
)

echo   - Found Love2D at: %LOVE_DIR%
echo.

echo [3/3] Creating standalone Windows executable...

set EXE_FILE=%BUILD_DIR%\%GAME_NAME%.exe

:: Fuse love.exe with .love file
copy /b "%LOVE_DIR%\love.exe"+"%LOVE_FILE%" "%EXE_FILE%" >nul 2>&1

if not exist "%EXE_FILE%" (
    echo   - Failed to fuse exe, trying alternate method...
    :: Try with explicit paths
    copy /b "%LOVE_DIR%\love.exe" "%EXE_FILE%" >nul 2>&1
    type "%LOVE_FILE%" >> "%EXE_FILE%" 2>nul
)

if not exist "%EXE_FILE%" (
    echo ERROR: Failed to create executable
    goto :error
)

echo   - Created: %EXE_FILE%

:: Copy required DLLs
echo   - Copying Love2D runtime DLLs...
for %%f in ("%LOVE_DIR%\*.dll") do (
    copy "%%f" "%BUILD_DIR%\" >nul 2>&1
)

:: Copy license if exists
if exist "%LOVE_DIR%\license.txt" copy "%LOVE_DIR%\license.txt" "%BUILD_DIR%\" >nul 2>&1

echo.
echo ========================================
echo   BUILD COMPLETE
echo ========================================
echo.
echo Output files in %BUILD_DIR%\:
echo   - %GAME_NAME%.love  (distributable Love2D package)
echo   - %GAME_NAME%.exe   (standalone Windows executable)
echo   - *.dll             (required runtime libraries)
echo.
echo To distribute: zip the entire %BUILD_DIR% folder
echo.
goto :end

:skippe
echo.
echo ========================================
echo   BUILD COMPLETE (Love package only)
echo ========================================
echo.
echo Output: %BUILD_DIR%\%GAME_NAME%.love
echo.
echo To run: love %GAME_NAME%.love
echo.
goto :end

:error
echo.
echo BUILD FAILED
echo.
exit /b 1

:end
endlocal
