# Возврат родного Segoe UI + полужирное начертание Semibold во всём интерфейсе.
# Причина: тонкие штрихи утомляют глаза; Semibold — родная гарнитура Windows,
# поэтому метрики, хинтинг и кириллица остаются штатными.
#
#   .\font-semibold-apply.ps1            — применить
#   .\font-semibold-apply.ps1 -Revert    — снять подмены, вернуть чистый Segoe UI
#
# Требует прав администратора. Применяется после перезагрузки или перевхода.

[CmdletBinding()]
param([switch]$Revert)

$ErrorActionPreference = 'Stop'

$subs   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
$backup = Join-Path $env:USERPROFILE 'Desktop\Шрифт-бэкап-откат\Fonts_backup.reg'

# Имена, которые запрашивает интерфейс Windows 11. Классические окна просят
# «Segoe UI», оболочка (Пуск, Параметры, заголовки) — семейство Variable.
$targets = @(
    'Segoe UI'
    'Segoe UI Variable'
    'Segoe UI Variable Display'
    'Segoe UI Variable Text'
    'Segoe UI Variable Small'
)

Write-Host ""

# Файловые привязки Segoe UI были погашены ради прежней подмены — возвращаем.
if (Test-Path $backup) {
    & reg.exe import $backup 2>&1 | Out-Null
    Write-Host "  Родные привязки Segoe UI восстановлены из бэкапа." -ForegroundColor Green
} else {
    Write-Host "  ВНИМАНИЕ: бэкап не найден: $backup" -ForegroundColor Yellow
}

if ($Revert) {
    foreach ($t in $targets) {
        Remove-ItemProperty -Path $subs -Name $t -ErrorAction SilentlyContinue
    }
    Write-Host "  Все подмены сняты — чистый штатный Segoe UI." -ForegroundColor Green
} else {
    foreach ($t in $targets) {
        Set-ItemProperty -Path $subs -Name $t -Value 'Segoe UI Semibold' -Type String
    }
    Write-Host "  Подмены установлены: интерфейс -> Segoe UI Semibold" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Проверка (что реально лежит в реестре):" -ForegroundColor Cyan
foreach ($t in $targets) {
    $v = (Get-ItemProperty -Path $subs -Name $t -ErrorAction SilentlyContinue).$t
    Write-Host ("    {0,-28} {1}" -f $t, $(if ($v) { $v } else { '(нет подмены)' }))
}
Write-Host ""
Write-Host "  Вступит в силу после перезагрузки или выхода и входа в систему." -ForegroundColor DarkGray
Write-Host ""
