@echo off
setlocal
set APP_HOME=%~dp0
set GRADLE_VERSION=8.4
set DISTRIBUTION=gradle-%GRADLE_VERSION%-all
set CACHE_ROOT=%USERPROFILE%\.gradle\wrapper\dists\%DISTRIBUTION%\flavorflow
set GRADLE_HOME=%CACHE_ROOT%\%DISTRIBUTION%

if exist "%APP_HOME%gradle\wrapper\gradle-wrapper.jar" (
  java -classpath "%APP_HOME%gradle\wrapper\gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain %*
  exit /b %ERRORLEVEL%
)
if not exist "%GRADLE_HOME%\bin\gradle.bat" (
  if not exist "%CACHE_ROOT%" mkdir "%CACHE_ROOT%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $zip=Join-Path '%CACHE_ROOT%' '%DISTRIBUTION%.zip'; Invoke-WebRequest -Uri 'https://services.gradle.org/distributions/%DISTRIBUTION%.zip' -OutFile $zip; Expand-Archive -Path $zip -DestinationPath '%CACHE_ROOT%' -Force; Remove-Item $zip -Force"
  if errorlevel 1 exit /b 1
)
cd /d "%APP_HOME%"
call "%GRADLE_HOME%\bin\gradle.bat" %*
exit /b %ERRORLEVEL%
