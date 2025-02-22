@echo off
rem ------------------------------------------------------------
rem 1. Check if "conda" is available in PATH
rem ------------------------------------------------------------
where conda >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Conda found in PATH.
    call conda activate base
) else (
    echo Conda command not found in PATH. Searching for Anaconda installation...
    
    rem ------------------------------------------------------------
    rem 2. Search common installation locations:
    rem    (a) %USERPROFILE%\Anaconda3\Scripts\activate.bat
    rem    (b) C:\ProgramData\Anaconda3\Scripts\activate.bat
    rem ------------------------------------------------------------
    if exist "%USERPROFILE%\Anaconda3\Scripts\activate.bat" (
        echo Found Anaconda at %USERPROFILE%\Anaconda3
        call "%USERPROFILE%\Anaconda3\Scripts\activate.bat"
        call conda activate base
    ) else if exist "C:\ProgramData\Anaconda3\Scripts\activate.bat" (
        echo Found Anaconda at C:\ProgramData\Anaconda3
        call "C:\ProgramData\Anaconda3\Scripts\activate.bat"
        call conda activate base
    ) else (
        echo Could not find an Anaconda installation.
        pause
        exit /b 1
    )
)

rem ------------------------------------------------------------
rem 3. Start the Python HTTP server in a new window.
rem    "start" launches a new Command Prompt window.
rem ------------------------------------------------------------
start "" conda run python -m http.server 8000

rem ------------------------------------------------------------
rem 4. Open the default web browser to http://localhost:8000.
rem ------------------------------------------------------------
start http://localhost:8000

pause
