#define MyAppName "Alnaser Accounting"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "Alnaser Company"
#define MyAppURL "https://www.alnaser.com/"
#define MyAppExeName "debt_book.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
; هوية خاصة بـ«الناصر للحسابات» (كانت مشتركة مع شوب مانجر ودفتر الديون فيحلّ أحدهما محل الآخر)
AppId={{C61570EE-B926-4B43-9236-775B4BFD201D}
AppName={#MyAppName}
AppVersion=1.0.1
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\AlnaserAccounting
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\debt_book.exe
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=installer_output
OutputBaseFilename=AlnaserAccountingSetup
SetupIconFile=assets\icon\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; إغلاق التطبيق تلقائياً قبل التثبيت
CloseApplications=force
CloseApplicationsFilter=*.exe
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Visual C++ Redistributable - يتم تثبيته تلقائياً إذا لم يكن موجوداً
Source: "installer\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

; ملف الإعدادات البيئية (.env) - مهم لإعدادات Telegram
Source: ".env"; DestDir: "{app}"; Flags: ignoreversion

; ملفات التطبيق
Source: "build\windows\x64\runner\Release\debt_book.exe"; DestDir: "{app}"; Flags: ignoreversion
; استثناء نماذج الذكاء الاصطناعي ومحرك OCR لتقليل حجم التطبيق (~500MB → ~50MB)
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "onnxruntime.dll,tesseract\*,data\flutter_assets\assets\models\*,data\flutter_assets\assets\tessdata\*"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\debt_book.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\debt_book.exe"; Tasks: desktopicon

[Code]
// إغلاق التطبيق قبل التثبيت بالقوة
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // لا taskkill باسم debt_book.exe: كان يُغلق شوب مانجر ودفتر الديون أيضاً (نفس اسم الملف).
  // CloseApplications=force في [Setup] يُغلق فقط البرامج التي تستعمل ملفات مجلد التثبيت.
  ResultCode := 0;
  Result := True;
end;

// إغلاق التطبيق قبل إلغاء التثبيت
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  // إغلاق نسخة هذا المجلد فقط (لا كل برنامج اسمه debt_book.exe)
  Exec('powershell.exe', '-NoProfile -Command "Get-Process debt_book -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ''' + ExpandConstant('{app}') + '\debt_book.exe'' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  Result := True;
end;

[Run]
; تثبيت Visual C++ Runtime أولاً (بصمت - لن يظهر للمستخدم إلا إذا احتاج)
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "جاري تثبيت المتطلبات الأساسية..."; Flags: waituntilterminated

; 🖧 النسخة المحاسبية: السماح لخادم الشبكة المحلية (حاسبة السيرفر) والاكتشاف التلقائي
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Alnaser LAN Server"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Alnaser LAN Server"" dir=in action=allow protocol=TCP localport=47800 profile=any"; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Alnaser LAN Discovery"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Alnaser LAN Discovery"" dir=in action=allow protocol=UDP localport=47801 profile=any"; Flags: runhidden waituntilterminated

; تشغيل التطبيق بعد التثبيت
Filename: "{app}\debt_book.exe"; Description: "{cm:LaunchProgram,Alnaser}"; Flags: nowait postinstall skipifsilent
