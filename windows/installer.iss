#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{A8B76B8C-0924-4C2B-9428-5C0D9C980751}
AppName=柒伍壹壹音乐
AppVersion={#MyAppVersion}
AppPublisher=DuckMusic
DefaultDirName={autopf}\DuckMusic
DefaultGroupName=柒伍壹壹音乐
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=DuckMusic-Flutter-v{#MyAppVersion}-Windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\duck_music.exe
SetupIconFile=runner\resources\app_icon.ico

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\柒伍壹壹音乐"; Filename: "{app}\duck_music.exe"
Name: "{autodesktop}\柒伍壹壹音乐"; Filename: "{app}\duck_music.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："

[Run]
Filename: "{app}\duck_music.exe"; Description: "启动柒伍壹壹音乐"; Flags: nowait postinstall skipifsilent
