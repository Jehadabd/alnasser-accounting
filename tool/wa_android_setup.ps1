# tool/wa_android_setup.ps1
#
# 📱 تجهيز «خادم واتساب على الهاتف» قبل بناء نسخة أندرويد (مرة واحدة، ثم بعد تحديث مكتبات الخادم):
#   1) ينزّل Node.js لأندرويد (nodejs-mobile) من إصداره الرسمي على GitHub، ويطابق بصمته SHA-256،
#      ويفكه في android\app\libnode (خارج git).
#   2) يأخذ مكتبات الخادم المثبّتة على هذه الحاسبة (من «تشغيل على هذه الحاسبة بضغطة» في البرنامج)،
#      بلا sharp (مكتبة صور أصلية لويندوز لا تعمل على أندرويد ولا يحتاجها إرسال النص وPDF)،
#      ويضغطها في android\app\src\main\assets\wa_node\modules.zip (خارج git).
# بعدها: flutter build apk --split-per-abi --release
# بدون هذا السكربت تُبنى نسخة أندرويد كما كانت (بلا خادم الهاتف — خادم الحاسبة فقط).

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repo 'android\app'
$ver = 'v18.20.4'
$sha = 'bd7321eaa1a7602fbe0bb87302df2d79d87835cf4363fbdd17c350dbb485c2af'
$url = "https://github.com/nodejs-mobile/nodejs-mobile/releases/download/$ver/nodejs-mobile-$ver-android.zip"
$libnode = Join-Path $appDir 'libnode'
$stamp = Join-Path $libnode 'VERSION'

function Say($m) { Write-Host $m }

# ───────────── 1) Node.js لأندرويد ─────────────
$have = (Test-Path (Join-Path $libnode 'bin\arm64-v8a\libnode.so')) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $ver)
if ($have) {
  Say "[1/2] Node.js $ver لأندرويد موجود ✓"
} else {
  Say "[1/2] تنزيل Node.js $ver لأندرويد (≈57 ميغابايت)…"
  $zip = Join-Path $env:TEMP "nodejs-mobile-$ver-android.zip"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  $got = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
  if ($got -ne $sha) {
    Remove-Item $zip -Force
    throw "بصمة الملف لا تطابق ($got) — حُذف ولم يُستعمل"
  }
  if (Test-Path $libnode) { Remove-Item $libnode -Recurse -Force }
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $libnode)
  Set-Content -Path $stamp -Value $ver -Encoding ASCII
  Remove-Item $zip -Force
  Say "      فُك في android\app\libnode ✓ (البصمة مطابقة)"
}

# ───────────── 2) مكتبات الخادم ─────────────
$candidates = @(
  (Join-Path $env:APPDATA 'Alnaser\AlnaserAccounting\wa_local\app')
)
$found = Get-ChildItem -Path $env:APPDATA -Directory -ErrorAction SilentlyContinue |
  ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue } |
  ForEach-Object { Join-Path $_.FullName 'wa_local\app' }
$candidates += $found
$src = $candidates | Where-Object { Test-Path (Join-Path $_ 'node_modules\baileys\package.json') } | Select-Object -First 1
if (-not $src) {
  throw "لم أجد مكتبات الخادم على هذه الحاسبة. افتح البرنامج على ويندوز ← خادم واتساب ← «تشغيل على هذه الحاسبة بضغطة»، ثم أعد تشغيل هذا السكربت."
}
$assetPkg = Get-Content (Join-Path $repo 'assets\wa_server\package.json') -Raw
$srcPkg = Get-Content (Join-Path $src 'package.json') -Raw
if (($assetPkg -replace "`r", "").Trim() -ne ($srcPkg -replace "`r", "").Trim()) {
  throw "مكتبات الخادم على هذه الحاسبة أقدم من البرنامج. افتح البرنامج ← خادم واتساب ← «إعادة التشغيل» (يحدّثها)، ثم أعد تشغيل السكربت."
}
Say "[2/2] ضغط مكتبات الخادم من: $src"
$stage = Join-Path $env:TEMP 'alnaser_wa_modules'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
$null = robocopy (Join-Path $src 'node_modules') (Join-Path $stage 'node_modules') /E /NFL /NDL /NJH /NJS /NP /XD sharp '@img' '.bin'
if ($LASTEXITCODE -ge 8) { throw "فشل نسخ المكتبات (robocopy $LASTEXITCODE)" }
$outDir = Join-Path $appDir 'src\main\assets\wa_node'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$out = Join-Path $outDir 'modules.zip'
if (Test-Path $out) { Remove-Item $out -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $out, [IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $stage -Recurse -Force
$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Say "      android\app\src\main\assets\wa_node\modules.zip ($mb ميغابايت) ✓"
Say ""
Say "جاهز. ابنِ نسخة أندرويد:  flutter build apk --split-per-abi --release"
