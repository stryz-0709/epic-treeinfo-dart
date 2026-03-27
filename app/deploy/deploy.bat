@echo off
echo =========================================
echo   Deploying to DigitalOcean Droplet...
echo =========================================

set SERVER=root@152.42.252.46
set REMOTE=/opt/earthranger

echo [1/6] Uploading source code...
scp -r ..\src\*.py %SERVER%:%REMOTE%/src/
scp -r ..\src\__init__.py %SERVER%:%REMOTE%/src/

echo [2/6] Uploading templates...
scp -r ..\templates\* %SERVER%:%REMOTE%/templates/

echo [3/6] Uploading static files...
ssh %SERVER% "mkdir -p %REMOTE%/static"
scp -r ..\static\* %SERVER%:%REMOTE%/static/

echo [4/6] Uploading requirements and config...
scp ..\requirements.txt %SERVER%:%REMOTE%/requirements.txt

echo [5/6] Installing dependencies and setting up service...
ssh %SERVER% "cd %REMOTE% && source venv/bin/activate && pip install -r requirements.txt --quiet 2>&1 | tail -5"

echo [6/6] Setting up and restarting service...
scp earthranger.service %SERVER%:/etc/systemd/system/earthranger.service
ssh %SERVER% "systemctl daemon-reload && systemctl stop dashboard er-monitor 2>/dev/null; systemctl enable earthranger && systemctl restart earthranger && echo 'V2 service started!' && sleep 2 && systemctl is-active earthranger && curl -sf http://localhost:8000/health && echo ' Health OK'"

echo.
echo =========================================
echo   Deploy complete!
echo   Dashboard: http://152.42.252.46/
echo =========================================
pause
