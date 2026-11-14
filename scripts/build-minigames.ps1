param(
    [string]$Godot = 'C:\Games\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$build = Join-Path $repo 'builds/minigames-windows'
$stage = Join-Path $build ('source-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $build 'ZumaMinigames-Windows-x64'
New-Item -ItemType Directory -Force -Path "$stage/addons", $package | Out-Null
Copy-Item -LiteralPath "$repo/addons/zuma_minigames" -Destination "$stage/addons" -Recurse
@'
config_version=5
[application]
config/name="Zuma Minigames"
config/version="1.0.0"
run/main_scene="res://addons/zuma_minigames/demo.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="ZumaMinigames"
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/min_width=960
window/size/min_height=540
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@ | Set-Content -LiteralPath "$stage/project.godot" -Encoding utf8
@'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="addons/zuma_minigames/tests/*,addons/zuma_minigames/README.md"
export_path=""
script_export_mode=2
[preset.0.options]
binary_format/architecture="x86_64"
binary_format/embed_pck=true
debug/export_console_wrapper=0
codesign/enable=false
application/modify_resources=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
'@ | Set-Content -LiteralPath "$stage/export_presets.cfg" -Encoding utf8
& $Godot --headless --editor --path $stage --import 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
& $Godot --headless --path $stage --export-release 'Windows Desktop' "$package/ZumaMinigames.exe" 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Godot export failed: $LASTEXITCODE" }
@'
Zuma Minigames — Windows 64-bit

Запустите ZumaMinigames.exe. Установка Godot, сервера и модели не требуется.
Выберите игру и сложность, прочитайте инструкцию и нажмите «Начать».
Доступны пятнашки, найди пару, математика на скорость и запоминание чисел.
Для офлайн-игры оставьте «Без серверного профиля»; серверные кнопки необязательны.
При потере фокуса окна попытка прерывается. Для новой попытки нажмите «Заново».
Локальные результаты: %APPDATA%\ZumaMinigames.
Для записи видео сначала включите рекордер, затем вернитесь в окно игры.

Сборка не подписана цифровым сертификатом. Это локальная демонстрационная версия.
Движок Godot распространяется по лицензии MIT; см. GODOT-LICENSE.txt.
'@ | Set-Content -LiteralPath "$package/READ-ME.txt" -Encoding utf8
$godotLicense = Join-Path (Split-Path $Godot -Parent) 'LICENSE.txt'
if (!(Test-Path -LiteralPath $godotLicense)) { throw 'Godot LICENSE.txt is required next to the editor.' }
Copy-Item -LiteralPath $godotLicense -Destination "$package/GODOT-LICENSE.txt" -Force
$godotCopyright = Join-Path (Split-Path $Godot -Parent) 'COPYRIGHT.txt'
if (Test-Path -LiteralPath $godotCopyright) {
    Copy-Item -LiteralPath $godotCopyright -Destination "$package/GODOT-COPYRIGHT.txt" -Force
}
$zip = Join-Path $build 'ZumaMinigames-Windows-x64.zip'
Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
Get-Item -LiteralPath "$package/ZumaMinigames.exe", $zip | Select-Object FullName, Length
