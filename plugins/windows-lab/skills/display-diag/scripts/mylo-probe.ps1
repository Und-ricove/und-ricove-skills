# Объективный замер «мыла»: снимает экран в НАТИВНОМ разрешении и считает,
# насколько резкие края у текста. Запускать В МОМЕНТ, когда мыло видно.
#
#   .\mylo-probe.ps1                     — снять весь экран и замерить
#   .\mylo-probe.ps1 -Keep               — ещё и сохранить PNG для разбора
#
# Метрика: доля полутоновых пикселей на границе глифа. Резкая отрисовка даёт
# переход в 1 пиксель (отношение < 0.6). Растянутый растр размазывает переход
# на 2-3 пикселя, и отношение уходит за 1.2 — это и есть мыло В ФАЙЛЕ.
#
# Если мыло видно глазами, а замер говорит «резко» — значит картинка до панели
# чистая, и виновата уже сама панель или тракт вывода, а не отрисовка.

[CmdletBinding()]
param([switch]$Keep)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class DpiAware { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
'@
[DpiAware]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$w = $screen.Width
$h = $screen.Height

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $w, $h))
$g.Dispose()

Write-Host ""
Write-Host "  снимок: $w x $h" -ForegroundColor Cyan

# Ищем строки с наибольшим числом резких перепадов — там текст.
$rows = @()
for ($y = 0; $y -lt $h; $y += 7) {
    $c = 0
    for ($x = 8; $x -lt $w - 1; $x += 2) {
        if ([math]::Abs($bmp.GetPixel($x, $y).R - $bmp.GetPixel($x + 1, $y).R) -gt 25) { $c++ }
    }
    if ($c -gt 12) { $rows += [pscustomobject]@{ Y = $y; Edges = $c } }
}

if (-not $rows) {
    Write-Host "  Текста на экране не нашёл — открой окно с текстом и повтори." -ForegroundColor Yellow
    $bmp.Dispose(); return
}

$sample = $rows | Sort-Object Edges -Descending | Select-Object -First 12
$mid = 0; $solid = 0

foreach ($r in $sample) {
    $line = for ($x = 8; $x -lt $w; $x++) { $bmp.GetPixel($x, $r.Y).R }
    $sorted = $line | Sort-Object
    $bg = $sorted[[int]($sorted.Count * 0.10)]
    $fg = $sorted[[int]($sorted.Count * 0.98)]
    if (($fg - $bg) -lt 40) { continue }
    $lo = $bg + [int](($fg - $bg) * 0.20)
    $hi = $bg + [int](($fg - $bg) * 0.80)
    $mid   += ($line | Where-Object { $_ -gt $lo -and $_ -lt $hi }).Count
    $solid += ($line | Where-Object { $_ -ge $hi }).Count
}

$ratio = [math]::Round($mid / [math]::Max(1, $solid), 2)

Write-Host "  строк с текстом замерено: $($sample.Count)"
Write-Host "  полутоновых пикселей: $mid    ярких: $solid"
Write-Host ""
Write-Host ("  ОТНОШЕНИЕ = {0}" -f $ratio) -ForegroundColor White
Write-Host ""

# Абсолютного порога у этой метрики нет: она зависит от того, что сейчас на
# экране. Значение имеет только СРАВНЕНИЕ замеров одной и той же картинки
# в чистый момент и в мыльный — поэтому ведём журнал.
$log = Join-Path $PSScriptRoot 'mylo-log.csv'
$note = if ($Keep) { 'снимок сохранён' } else { '' }
if (-not (Test-Path $log)) {
    Set-Content -Path $log -Value 'время;отношение;полутон;яркие;строк;примечание' -Encoding utf8
}
Add-Content -Path $log -Encoding utf8 -Value ("{0};{1};{2};{3};{4};{5}" -f `
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $ratio, $mid, $solid, $sample.Count, $note)

$hist = @(Import-Csv $log -Delimiter ';')
if ($hist.Count -gt 1) {
    $prev = $hist[0..($hist.Count - 2)] | ForEach-Object { [double]($_.'отношение' -replace ',', '.') }
    $min = [math]::Round(($prev | Measure-Object -Minimum).Minimum, 2)
    $max = [math]::Round(($prev | Measure-Object -Maximum).Maximum, 2)
    Write-Host "  прошлые замеры: от $min до $max  (всего $($prev.Count))" -ForegroundColor DarkGray
    $r = [double]($ratio.ToString() -replace ',', '.')
    if ($r -gt $max * 1.25) {
        Write-Host "  СЕЙЧАС ЗАМЕТНО ХУЖЕ обычного — мыло попало В ФАЙЛ." -ForegroundColor Red
        Write-Host "  Значит растр растянут до панели: масштабирование текста," -ForegroundColor DarkGray
        Write-Host "  DPI-виртуализация окна или апскейл композитора." -ForegroundColor DarkGray
    } elseif ($r -lt $min * 0.8) {
        Write-Host "  СЕЙЧАС ЗАМЕТНО ЧЁТЧЕ обычного." -ForegroundColor Green
    } else {
        Write-Host "  В пределах обычного разброса." -ForegroundColor Green
        Write-Host "  Если мыло видно глазами именно сейчас — картинка до панели" -ForegroundColor DarkGray
        Write-Host "  чистая, и копать надо тракт вывода, а не отрисовку." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Это первый замер — он стал точкой отсчёта." -ForegroundColor DarkGray
    Write-Host "  Запусти ещё раз В МОМЕНТ мыла: смысл имеет разница, не само число." -ForegroundColor DarkGray
}
Write-Host ""

if ($Keep) {
    $dir = Join-Path $env:USERPROFILE 'Desktop'
    $path = Join-Path $dir ("mylo-probe-{0}.png" -f (Get-Date -Format 'HHmmss'))
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "  снимок сохранён: $path" -ForegroundColor Cyan
    Write-Host ""
}

$bmp.Dispose()
