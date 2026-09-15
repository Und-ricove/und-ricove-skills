# Переключатель сглаживания текста Windows (ClearType / серое) + порядок субпикселей.
# Меняет ЖИВОЕ состояние сессии через SystemParametersInfo и пишет его в реестр.
# Применяется мгновенно, перезагрузка не нужна. Полностью обратимо.
#
#   .\cleartype-toggle.ps1                    — показать текущее состояние
#   .\cleartype-toggle.ps1 -Mode cleartype    — включить ClearType
#   .\cleartype-toggle.ps1 -Mode gray         — вернуть серое сглаживание
#   .\cleartype-toggle.ps1 -Mode cleartype -Orientation rgb
#
# На OLED-панели «правильного» ответа нет: субпиксельная геометрия там часто
# не совпадает с RGB-полоской, под которую считается ClearType. Решают глаза.

[CmdletBinding()]
param(
    [ValidateSet('status', 'cleartype', 'gray')]
    [string]$Mode = 'status',

    [ValidateSet('keep', 'rgb', 'bgr')]
    [string]$Orientation = 'keep'
)

$ErrorActionPreference = 'Stop'

$sig = @'
[DllImport("user32.dll", SetLastError=true)]
public static extern bool SystemParametersInfo(uint a, uint b, ref uint c, uint d);

[DllImport("user32.dll", SetLastError=true, EntryPoint="SystemParametersInfoW")]
public static extern bool SystemParametersInfoSet(uint a, uint b, System.UIntPtr c, uint d);
'@
$spi = Add-Type -MemberDefinition $sig -Name Spi -Namespace ClearTypeTool -PassThru

$GET_TYPE = 0x200A
$SET_TYPE = 0x200B
$GET_ORNT = 0x2012
$SET_ORNT = 0x2013
$UPDATE_AND_BROADCAST = 0x03   # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE

function Get-State {
    $t = 0; $o = 0
    $spi::SystemParametersInfo($GET_TYPE, 0, [ref]$t, 0) | Out-Null
    $spi::SystemParametersInfo($GET_ORNT, 0, [ref]$o, 0) | Out-Null
    [pscustomobject]@{
        Type            = $t
        TypeName        = if ($t -eq 2) { 'ClearType (субпиксельное)' } else { 'серое (grayscale)' }
        Orientation     = $o
        OrientationName = if ($o -eq 1) { 'RGB' } else { 'BGR' }
    }
}

function Show-State([string]$label) {
    $s = Get-State
    Write-Host ""
    Write-Host "  $label" -ForegroundColor Cyan
    Write-Host ("  тип сглаживания   : {0}  (значение {1})" -f $s.TypeName, $s.Type)
    Write-Host ("  порядок субпикселей: {0}  (значение {1})" -f $s.OrientationName, $s.Orientation)
    Write-Host ""
}

Show-State 'ТЕКУЩЕЕ СОСТОЯНИЕ'

if ($Mode -eq 'status' -and $Orientation -eq 'keep') {
    Write-Host "  Ничего не менял. Подсказка: -Mode cleartype | gray" -ForegroundColor DarkGray
    Write-Host ""
    return
}

# Порядок субпикселей выставляем ПЕРВЫМ: если он неверный, ClearType
# сразу покажет грязную бахрому и будет отвергнут незаслуженно.
if ($Orientation -ne 'keep') {
    $val = if ($Orientation -eq 'rgb') { 1 } else { 0 }
    if (-not $spi::SystemParametersInfoSet($SET_ORNT, 0, [System.UIntPtr]::new($val), $UPDATE_AND_BROADCAST)) {
        throw "Не удалось задать порядок субпикселей (код $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
}

if ($Mode -ne 'status') {
    $val = if ($Mode -eq 'cleartype') { 2 } else { 1 }
    if (-not $spi::SystemParametersInfoSet($SET_TYPE, 0, [System.UIntPtr]::new($val), $UPDATE_AND_BROADCAST)) {
        throw "Не удалось задать тип сглаживания (код $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
}

Show-State 'СТАЛО'
Write-Host "  Часть уже запущенных окон перерисуется не сразу — они читают" -ForegroundColor DarkGray
Write-Host "  настройку при старте. Проводник: Win+E заново. Полная картина —" -ForegroundColor DarkGray
Write-Host "  после выхода и входа в систему." -ForegroundColor DarkGray
Write-Host ""
