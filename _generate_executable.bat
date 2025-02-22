@echo off
REM Copy the run.bat file into the ./build/web/ folder
copy /Y ".\assets\setup_config\run.bat" ".\build\web\"

REM Zip the entire ./build/web/ folder into build\web.zip using PowerShell
powershell -command "Compress-Archive -Path '.\build\web\*' -DestinationPath '.\web.zip' -Force"

echo Operation complete.
pause
