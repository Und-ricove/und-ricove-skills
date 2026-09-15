# Проверка обновлений Claude Desktop и Claude Code CLI при старте сессии.
# Вывод — одна-две строки в контекст сессии (SessionStart-хук).
# Ничего не устанавливает: только смотрит и докладывает.
# Источники правды:
#   Desktop установленный — пакет MSIX (Get-AppxPackage), запасной путь —
#     переменная CLAUDE_CODE_DESKTOP_APP_VERSION десктоп-сессии;
#   Desktop доступный — журнал встроенного апдейтера
#     %LOCALAPPDATA%\Claude\logs\main.log (строки «[updater] …»):
#     winget и Store отстают на месяцы, им не верить;
#   CLI терминала — «claude --version» из %USERPROFILE%\.local\bin;
#   CLI внутри Desktop — папки %APPDATA%\Claude\claude-code\<версия>;
#   CLI доступный — реестр npm (кэш 6 часов в %USERPROFILE%\.claude\cache).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'
$home_ = $env:USERPROFILE
$cacheDir = Join-Path $home_ '.claude\cache'
$cacheFile = Join-Path $cacheDir 'update-check.json'
$now = Get-Date

function Get-Tail([string]$path, [int]$bytes) {
    if (-not (Test-Path $path)) { return '' }
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $len = $fs.Length
            $take = [Math]::Min($bytes, $len)
            $fs.Seek($len - $take, 'Begin') | Out-Null
            $buf = New-Object byte[] $take
            $fs.Read($buf, 0, $take) | Out-Null
            return [System.Text.Encoding]::UTF8.GetString($buf)
        } finally { $fs.Dispose() }
    } catch { return '' }
}

function Compare-Ver([string]$a, [string]$b) {
    # >0 если a новее b; сравнение по числовым сегментам.
    $pa = ($a -split '\.') | ForEach-Object { [int]($_ -replace '\D','0') }
    $pb = ($b -split '\.') | ForEach-Object { [int]($_ -replace '\D','0') }
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -ne $y) { return $x - $y }
    }
    return 0
}

# ---------- Desktop: установленная версия ----------
$dInstalled = $null
$pkg = Get-AppxPackage -Name 'Claude' | Select-Object -First 1
if ($pkg) { $dInstalled = [string]$pkg.Version }
if (-not $dInstalled -and $env:CLAUDE_CODE_DESKTOP_APP_VERSION) {
    $dInstalled = $env:CLAUDE_CODE_DESKTOP_APP_VERSION
}
# Нормализация: 1.52386.0.0 -> 1.52386.0 (журнал пишет три сегмента)
if ($dInstalled) { $dInstalled = (($dInstalled -split '\.') | Select-Object -First 3) -join '.' }

# ---------- Desktop: что знает встроенный апдейтер ----------
$dLatest = $null; $dStaged = $null; $dState = 'журнал апдейтера не найден'
$logPath = Join-Path $env:LOCALAPPDATA 'Claude\logs\main.log'
$tail = Get-Tail $logPath 400000
if ($tail) {
    $lines = $tail -split "`n" | Where-Object { $_ -match '\[updater\]' }
    $last = $lines | Select-Object -Last 40
    $stagedLine = $last | Where-Object { $_ -match 'Staged version ([\d.]+) is still current \(latest: ([\d.]+)' } | Select-Object -Last 1
    $readyLine  = $last | Where-Object { $_ -match "ready to install .*releaseName: 'Claude ([\d.]+)'" } | Select-Object -Last 1
    $checkLine  = $last | Where-Object { $_ -match 'Checking for updates' } | Select-Object -Last 1
    $when = if ($last) { (($last | Select-Object -Last 1) -replace '^\s*(\S+ \S+) .*$', '$1') } else { '' }
    if ($stagedLine -and $stagedLine -match 'Staged version ([\d.]+) is still current \(latest: ([\d.]+)') {
        $dStaged = $Matches[1]; $dLatest = $Matches[2]
    } elseif ($readyLine -and $readyLine -match "releaseName: 'Claude ([\d.]+)'") {
        $dStaged = $Matches[1]; $dLatest = $Matches[1]
    }
    if ($dStaged -and $dInstalled -and (Compare-Ver $dStaged $dInstalled) -le 0) {
        # Скачанная версия уже стоит: перезапуск был, а строки
        # «Staged … still current» в хвосте журнала — история (ловушка 12.09).
        $dState = "установлена $dInstalled, апдейтер новых версий не находил (журнал $when)"
    } elseif ($dStaged) {
        $dState = "скачана $dStaged, ждёт перезапуска приложения (журнал $when)"
    } elseif ($checkLine) {
        $dState = "апдейтер проверял $when, новых версий не находил"
    } else {
        $dState = 'записей апдейтера в хвосте журнала нет'
    }
}

# ---------- CLI: терминал (native) ----------
$cliNative = $null
$cliExe = Join-Path $home_ '.local\bin\claude.exe'
if (Test-Path $cliExe) {
    $v = & $cliExe --version 2>$null | Select-Object -First 1
    if ($v -match '(\d+\.\d+\.\d+)') { $cliNative = $Matches[1] }
}

# ---------- CLI: внутри Desktop (bundled) ----------
$cliBundled = $null
$bdir = Join-Path $env:APPDATA 'Claude\claude-code'
if (Test-Path $bdir) {
    $cliBundled = Get-ChildItem $bdir -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1 -ExpandProperty Name
}

# ---------- CLI: доступная версия (npm, кэш 6 ч) ----------
$cliLatest = $null; $cliSource = ''
$cache = $null
if (Test-Path $cacheFile) { try { $cache = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
if ($cache -and $cache.cliLatest -and $cache.checkedAt) {
    $age = ($now - [datetime]$cache.checkedAt).TotalHours
    if ($age -lt 6) { $cliLatest = $cache.cliLatest; $cliSource = "npm, кэш $([int]$age) ч" }
}
if (-not $cliLatest) {
    try {
        $r = Invoke-RestMethod -Uri 'https://registry.npmjs.org/@anthropic-ai/claude-code/latest' -TimeoutSec 6
        if ($r.version) {
            $cliLatest = [string]$r.version; $cliSource = 'npm'
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            @{ cliLatest = $cliLatest; checkedAt = $now.ToString('o') } | ConvertTo-Json |
                Set-Content -Path $cacheFile -Encoding UTF8
        }
    } catch {
        if ($cache -and $cache.cliLatest) { $cliLatest = $cache.cliLatest; $cliSource = 'npm, старый кэш (сети нет)' }
        else { $cliSource = 'сети нет, npm недоступен' }
    }
}

# ---------- Сводка ----------
$parts = @()
$needs = 0
if ($dInstalled) {
    if ($dLatest -and (Compare-Ver $dLatest $dInstalled) -gt 0) {
        $parts += "Desktop $dInstalled → $dLatest ($dState)"; $needs++
    } else {
        $parts += "Desktop $dInstalled актуален ($dState)"
    }
} else { $parts += "Desktop: версия не определена ($dState)" }

if ($cliNative) {
    if ($cliLatest -and (Compare-Ver $cliLatest $cliNative) -gt 0) {
        $parts += "CLI терминала $cliNative → $cliLatest (команда: claude update; $cliSource)"; $needs++
    } else {
        $parts += "CLI терминала $cliNative актуален ($cliSource)"
    }
} else { $parts += 'CLI терминала не найден в ~\.local\bin' }

if ($cliBundled) {
    $tag = if ($cliLatest -and (Compare-Ver $cliLatest $cliBundled) -gt 0) { "отстаёт от $cliLatest, обновляется вместе с Desktop" } else { 'актуален' }
    $parts += "CLI внутри Desktop $cliBundled ($tag)"
}

$mark = if ($needs -gt 0) { '⬆ ОБНОВЛЕНИЯ' } else { '✓ Обновления' }
$stamp = $now.ToString('dd.MM HH:mm')
Write-Output ("{0} ({1}): {2}" -f $mark, $stamp, ($parts -join ' · '))
Write-Output 'Правило: ничего не ставить самому — доложить пользователю; Desktop обновляется перезапуском приложения, CLI терминала — «claude update».'
