@echo off
setlocal
set "REPO=%~dp0mobile\epic-treeinfo-dart"
if not exist "%REPO%\.git" (
  echo [ERROR] Not a Git repository: "%REPO%"
  exit /b 1
)

git -C "%REPO%" %*
exit /b %ERRORLEVEL%
