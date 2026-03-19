@rem Gradle startup script for Windows

@if "%DEBUG%" == "" @echo off
@rem Set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%" == "" set DIRNAME=.
set APP_BASE_NAME=%~n0
set APP_HOME=%DIRNAME%

@rem Resolve any "." and ".." in APP_HOME to make it shorter.
for %%i in ("%APP_HOME%") do set APP_HOME=%%~fi

set CLASSPATH=%APP_HOME%\gradle\wrapper\gradle-wrapper.jar

@rem Keep Android/AGP user config inside the repo sandbox (avoids writing to %USERPROFILE%).
set "ANDROID_USER_HOME=%APP_HOME%\.android-home"
set "ANDROID_SDK_HOME="
set "ANDROID_PREFS_ROOT="

@rem ---------------------------------------------------------------------------
@rem This project uses Android Gradle Plugin 8.x, which requires running Gradle
@rem on JDK 17+. If JAVA_HOME points to an older JDK (common on CI/dev boxes),
@rem fall back to the JBR bundled with Android Studio if present.
@rem You can override by setting MUSICPLAYER_JAVA_HOME explicitly.
@rem ---------------------------------------------------------------------------
set "DEFAULT_JBR=C:\Program Files\Android\Android Studio\jbr"

if not "%MUSICPLAYER_JAVA_HOME%"=="" (
    set "JAVA_HOME=%MUSICPLAYER_JAVA_HOME%"
)

if "%MUSICPLAYER_JAVA_HOME%"=="" (
    if exist "%DEFAULT_JBR%\bin\java.exe" (
        set "JAVA_HOME=%DEFAULT_JBR%"
    )
)

if not exist "%JAVA_HOME%\bin\java.exe" (
    echo ERROR: JAVA_HOME is not set to a valid JDK 17+.
    echo Set MUSICPLAYER_JAVA_HOME or JAVA_HOME to a JDK 17+ install.
    echo Current JAVA_HOME: "%JAVA_HOME%"
    exit /b 1
)

@rem Execute Gradle
"%JAVA_HOME%\bin\java.exe" -classpath "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %*

:end
@rem End local scope for the variables with windows NT shell
if "%ERRORLEVEL%"=="0" goto mainEnd

:fail
rem Set variable GRADLE_EXIT_CONSOLE if you need the _script_ return code instead of
rem the _cmd.exe /c_ return code!
if  not "" == "%GRADLE_EXIT_CONSOLE%" exit 1
exit /b 1

:mainEnd
if "%OS%"=="Windows_NT" endlocal

:omega
