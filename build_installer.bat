@echo off
echo Building Alnaser Installer...

REM Try different possible Inno Setup paths
set "INNO_PATH1=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
set "INNO_PATH2=C:\Program Files\Inno Setup 6\ISCC.exe"

if exist "%INNO_PATH1%" (
    echo Found Inno Setup at: %INNO_PATH1%
    "%INNO_PATH1%" "AlnaserSetup.iss"
    goto :end
)

if exist "%INNO_PATH2%" (
    echo Found Inno Setup at: %INNO_PATH2%
    "%INNO_PATH2%" "AlnaserSetup.iss"
    goto :end
)

echo Inno Setup not found. Please install Inno Setup 6 from:
echo https://jrsoftware.org/isinfo.php
echo.
echo After installation, run this script again.
pause

:end
if exist "installer_output\AlnaserSetup.exe" (
    echo.
    echo Success! Installer created: installer_output\AlnaserSetup.exe
    echo You can now distribute this file to other computers.
) else (
    echo.
    echo Failed to create installer. Please check the error messages above.
)
pause 