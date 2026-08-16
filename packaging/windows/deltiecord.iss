#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #error SourceDir must point to the complete Flutter Windows Release directory
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{2E5E8DB4-F62B-4E91-B4C4-2CA41EDCC91F}
AppName=Deltiecord
AppVersion={#MyAppVersion}
AppPublisher=Deltiecord contributors
AppPublisherURL=https://deltie.net/cord
AppSupportURL=https://github.com/vosjecleo/deltiecord/issues
AppUpdatesURL=https://deltie.net/cord
DefaultDirName={localappdata}\Programs\Deltiecord
DefaultGroupName=Deltiecord
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=Deltiecord-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\deltiecord.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany=Deltiecord contributors
VersionInfoDescription=Deltiecord Matrix client installer
VersionInfoCopyright=AGPL-3.0-or-later

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Deltiecord"; Filename: "{app}\deltiecord.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Deltiecord"; Filename: "{app}\deltiecord.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\deltiecord.exe"; Description: "Launch Deltiecord"; Flags: nowait postinstall skipifsilent

; User sessions and Matrix data live outside {app}. Deliberately do not add
; [UninstallDelete] entries for AppData so upgrades/uninstall preserve them.
