@echo off
chcp 65001 >nul 2>&1

if "%DEPLOY_PROJECT_DIR%"=="" (
    set "NOW=%date% %time%"
    echo [%NOW%] ERROR DEPLOY_PROJECT_DIR NOT SET
    echo [%NOW%] ERROR DEPLOY_PROJECT_DIR NOT SET>>"%SCRIPT_DIR%deploy.log"
    exit /b 1
)

set "PROJECT_DIR=%DEPLOY_PROJECT_DIR%"
for %%I in ("%PROJECT_DIR%") do set "PROJECT_DIR=%%~fI"
if "%DEPLOY_GIT_BRANCH%"=="" (
    set "GIT_BRANCH=dev"
) else (
    set "GIT_BRANCH=%DEPLOY_GIT_BRANCH%"
)
if "%DEPLOY_PM2_APP_NAME%"=="" (
    set "PM2_APP_NAME=server"
) else (
    set "PM2_APP_NAME=%DEPLOY_PM2_APP_NAME%"
)
set "SCRIPT_DIR=%~dp0"
if "%DEPLOY_LOG_PATH%"=="" (
    set "DEPLOY_LOG=%SCRIPT_DIR%deploy.log"
) else (
    set "DEPLOY_LOG=%DEPLOY_LOG_PATH%"
)
if "%DEPLOY_REMOTE_URL%"=="" (
    set "REMOTE_URL=git@github.com:liuchen112233/yayaspeakingserver.git"
) else (
    set "REMOTE_URL=%DEPLOY_REMOTE_URL%"
)

set "NOW=%date% %time%"
echo [%NOW%] START DEPLOY
echo [%NOW%] START DEPLOY>>"%DEPLOY_LOG%"

set "PATH=%APPDATA%\npm;%ProgramFiles%\nodejs;%PATH%"
set "NOW=%date% %time%"
echo [%NOW%] STEP0 PM2 STOP %PM2_APP_NAME%
echo [%NOW%] STEP0 PM2 STOP %PM2_APP_NAME%>>"%DEPLOY_LOG%"
call pm2 stop "%PM2_APP_NAME%">>"%DEPLOY_LOG%" 2>&1

if exist "%PROJECT_DIR%" (
    set "NOW=%date% %time%"
    echo [%NOW%] STEP0 CLEAN PROJECT_DIR
    echo [%NOW%] STEP0 CLEAN PROJECT_DIR>>"%DEPLOY_LOG%"
    rmdir /s /q "%PROJECT_DIR%"
)

set "SSH_DIR=%USERPROFILE%\.ssh"
if not exist "%SSH_DIR%" (
    mkdir "%SSH_DIR%"
)
ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "%SSH_DIR%\known_hosts" 2>>"%DEPLOY_LOG%"

where git >nul 2>&1
if errorlevel 1 (
    set "NOW=%date% %time%"
    echo [%NOW%] ERROR GIT NOT FOUND
    echo [%NOW%] ERROR GIT NOT FOUND>>"%DEPLOY_LOG%"
    exit /b 1
)

set "NOW=%date% %time%"
echo [%NOW%] STEP1 GIT CLONE %GIT_BRANCH%
echo [%NOW%] STEP1 GIT CLONE %GIT_BRANCH%>>"%DEPLOY_LOG%"
cd /d "%PROJECT_DIR%\.."
git clone "%REMOTE_URL%" "%PROJECT_DIR%">>"%DEPLOY_LOG%" 2>&1
if errorlevel 1 (
    set "NOW=%date% %time%"
    echo [%NOW%] ERROR GIT CLONE FAILED
    echo [%NOW%] ERROR GIT CLONE FAILED>>"%DEPLOY_LOG%"
    exit /b 1
)

cd /d "%PROJECT_DIR%"
git checkout %GIT_BRANCH%>>"%DEPLOY_LOG%" 2>&1
if errorlevel 1 (
    set "NOW=%date% %time%"
    echo [%NOW%] ERROR GIT CHECKOUT FAILED
    echo [%NOW%] ERROR GIT CHECKOUT FAILED>>"%DEPLOY_LOG%"
    exit /b 1
)

set "NOW=%date% %time%"
echo [%NOW%] OK GIT PREPARE SUCCESS
echo [%NOW%] OK GIT PREPARE SUCCESS>>"%DEPLOY_LOG%"

set "NOW=%date% %time%"
echo [%NOW%] STEP2 NPM INSTALL
echo [%NOW%] STEP2 NPM INSTALL>>"%DEPLOY_LOG%"
if exist "%PROJECT_DIR%\package.json" (
    call :npm_install_with_retry
) else (
    set "NOW=%date% %time%"
    echo [%NOW%] INFO NO PACKAGE.JSON SKIP NPM INSTALL
    echo [%NOW%] INFO NO PACKAGE.JSON SKIP NPM INSTALL>>"%DEPLOY_LOG%"
)

set "NOW=%date% %time%"
echo [%NOW%] STEP3 NPM RUN BUILD
echo [%NOW%] STEP3 NPM RUN BUILD>>"%DEPLOY_LOG%"
set "HAS_BUILD=0"
if exist "%PROJECT_DIR%\package.json" (
    cd /d "%PROJECT_DIR%"
    node -e "try{const p=require('./package.json');const s=p.scripts&&p.scripts.build;process.exit(s?0:1);}catch(e){process.exit(1)}"
    if errorlevel 1 (
        set "NOW=%date% %time%"
        echo [%NOW%] INFO NO BUILD SCRIPT SKIP BUILD
        echo [%NOW%] INFO NO BUILD SCRIPT SKIP BUILD>>"%DEPLOY_LOG%"
    ) else (
        set "HAS_BUILD=1"
        call npm run build:dev>>"%DEPLOY_LOG%" 2>&1
        if errorlevel 1 (
            set "NOW=%date% %time%"
            echo [%NOW%] ERROR NPM RUN BUILD FAILED
            echo [%NOW%] ERROR NPM RUN BUILD FAILED>>"%DEPLOY_LOG%"
            exit /b 1
        )
        set "NOW=%date% %time%"
        echo [%NOW%] OK NPM RUN BUILD SUCCESS
        echo [%NOW%] OK NPM RUN BUILD SUCCESS>>"%DEPLOY_LOG%"
    )
)

set "NOW=%date% %time%"
if "%HAS_BUILD%"=="1" (
    echo [%NOW%] STEP4 SKIP PM2 START BECAUSE BUILD SCRIPT EXISTS
    echo [%NOW%] STEP4 SKIP PM2 START BECAUSE BUILD SCRIPT EXISTS>>"%DEPLOY_LOG%"
) else (
    echo [%NOW%] STEP4 PM2 START %PM2_APP_NAME%
    echo [%NOW%] STEP4 PM2 START %PM2_APP_NAME%>>"%DEPLOY_LOG%"
    set "PATH=%APPDATA%\npm;%ProgramFiles%\nodejs;%PATH%"
    call pm2 start "%PROJECT_DIR%\app.js" --name "%PM2_APP_NAME%" --update-env>>"%DEPLOY_LOG%" 2>&1
    if errorlevel 1 (
        set "NOW=%date% %time%"
        echo [%NOW%] ERROR PM2 START FAILED
        echo [%NOW%] ERROR PM2 START FAILED>>"%DEPLOY_LOG%"
        exit /b 1
    )
)

set "NOW=%date% %time%"
echo [%NOW%] OK DEPLOY FINISHED
echo [%NOW%] OK DEPLOY FINISHED>>"%DEPLOY_LOG%"
exit /b 0

:npm_install_with_retry
set "NPM_LOG=C:\wwwroot\webhook\npm_install.log"
if exist "%NPM_LOG%" del "%NPM_LOG%"
set "NPM_MAX_RETRY=3"
set "NPM_TRY=0"

:npm_install_retry
set /a NPM_TRY+=1
set "NOW=%date% %time%"
echo [%NOW%] STEP2 NPM INSTALL TRY %NPM_TRY%
echo [%NOW%] STEP2 NPM INSTALL TRY %NPM_TRY%>>"%DEPLOY_LOG%"
call npm install --no-fund --no-audit>>"%NPM_LOG%" 2>&1
type "%NPM_LOG%"
type "%NPM_LOG%" >>"%DEPLOY_LOG%"
if errorlevel 1 (
    if %NPM_TRY% LSS %NPM_MAX_RETRY% (
        set "NOW=%date% %time%"
        echo [%NOW%] WARN NPM INSTALL FAILED RETRY %NPM_TRY%
        echo [%NOW%] WARN NPM INSTALL FAILED RETRY %NPM_TRY%>>"%DEPLOY_LOG%"
        timeout /t 5 /nobreak >nul
        goto npm_install_retry
    ) else (
        set "NOW=%date% %time%"
        echo [%NOW%] ERROR NPM INSTALL FAILED
        echo [%NOW%] ERROR NPM INSTALL FAILED>>"%DEPLOY_LOG%"
        exit /b 1
    )
)
set "NOW=%date% %time%"
echo [%NOW%] OK NPM INSTALL SUCCESS
echo [%NOW%] OK NPM INSTALL SUCCESS>>"%DEPLOY_LOG%"
exit /b 0
