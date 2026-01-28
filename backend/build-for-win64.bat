@echo off
REM Build script for POS Labs Backend - Windows 64-bit executable
REM Output: pos-labs-backend.exe

echo Building POS Labs Backend for Windows 64-bit...
echo.

REM Set build environment for Windows 64-bit
set GOOS=windows
set GOARCH=amd64

REM Create bin directory if it doesn't exist
if not exist "bin" mkdir bin

REM Build the executable
echo Building executable...
go build -ldflags="-s -w" -o bin\pos-labs-backend.exe cmd\server\main.go

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful!
    echo Executable: bin\pos-labs-backend.exe
    echo.
    echo To run the server:
    echo   bin\pos-labs-backend.exe
) else (
    echo.
    echo Build failed!
    exit /b %ERRORLEVEL%
)
