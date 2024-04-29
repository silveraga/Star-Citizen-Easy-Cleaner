@echo off
setlocal enabledelayedexpansion

::Looking for SC Shader path for deletion and make sure to not delete the GraphicsSettings folder because it contains the value indicating if dx11 or vulkan.
set "folder_search=GraphicsSettings"
set "path=%localappdata%\Star Citizen"

::Script for deleting only the folders who are not tagged as "GraphicsSettings"
for /d %%i in ("%path%\*") do (
    for /f "delims=" %%a in ('dir /b /ad "%%i"') do (
        if "%%a"=="%folder_search%" (
            set "folder_found=%%i\%%a"
        ) else (
            echo Deleting folder: %%i\%%a
            rd /s /q "%%i\%%a"
        )
    )
)

if not defined folder_found (
    echo The %folder_search% folder was not found.
)

endlocal

echo Cleanup completed. Closing in 3 seconds...
timeout /t 3 >nul

exit
