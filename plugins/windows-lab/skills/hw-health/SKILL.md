---
name: hw-health
description: Здоровье железа: WHEA, BSOD, TDR/nvlddmkm, Kernel-Power 41, краши, температуры. Вызывать по /hw-health, «проверь разгон/железо», «синий экран», «вылетел драйвер видео», «фризы», «артефакты».
---

# Проверка здоровья железа

Аргумент — глубина в днях (по умолчанию 3): `/hw-health 7`.

```powershell
$days  = 3                              # или из аргумента
$since = (Get-Date).AddDays(-$days)
```

## 0. Сначала — проба, что журнал вообще читается

Песочница умеет ТИХО возвращать пусто (см. CLAUDE.md). Нулям можно верить только после этой пробы:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$since} -MaxEvents 1
```

Информационные события в System есть всегда. Если проба пуста или упала — журнал недоступен: так и скажи, вердикт «Чисто» НЕ выноси, обход — `wevtutil qe System /c:5 /rd:true /f:text`.

## 1. Маркеры в журналах

За период посчитай (каждый блок в try/catch; «No events found» после шага 0 — это ХОРОШО, выводи 0):

- **WHEA** (ошибки CPU/кэша/шины — маркер перебора разгона CPU): `Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$since}`
- **BugCheck / BSOD**: LogName System, провайдер `Microsoft-Windows-WER-SystemErrorReporting`, Id 1001 — вытащи из текста bugcheck-код
- **Kernel-Power 41** (жёсткий провал питания / зависание намертво): провайдер `Microsoft-Windows-Kernel-Power`, Id 41
- **TDR** (перезапуск драйвера GPU — перебор разгона GPU): LogName System, провайдер `Display`, Id 4101
- **nvlddmkm** (любые события драйвера NVIDIA): провайдер `nvlddmkm`
- **Краши приложений**: LogName Application, провайдер `Application Error`, Id 1000 — имена приложений и падающие модули

## 2. Датчики

`Invoke-RestMethod http://localhost:8085/data.json -TimeoutSec 3` (LibreHardwareMonitor). Пройди дерево Children рекурсивно: температуры CPU (пакет и максимум ядер), GPU (core/hotspot если есть), NVMe — текущие и Max. Порт молчит → LHM не запущен: скажи об этом и продолжи; температуру GPU возьми из `nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader`. За полной живой картиной карты — скилл /gpu, здесь её не дублируй.

## 3. Вердикт по-русски

Крупно: **«Чисто ✅»** (все нули И шаг 0 прошёл) или список находок с расшифровкой, что каждая значит для разгона:

- WHEA >0 → CPU-разгон на грани: откатить последнюю ступень PL1/PL2
- BugCheck 1001 → синий экран, назови код: 0x124 WHEA_UNCORRECTABLE_ERROR — почти всегда CPU/кэш; 0x116 VIDEO_TDR_FAILURE — GPU
- TDR/nvlddmkm >0 → GPU-разгон: снять +МГц с ядра или VRAM
- Kernel-Power 41 → жёсткий сбой; если рядом BugCheck — это BSOD с перезагрузкой, если без него — провал питания или зависание намертво. Разбираться ДО продолжения разгона
- Краши LegionSpace ntdll 0xc0000374 — известный баг LS, НЕ маркер разгона

## Разделение труда с соседями

- **/logs** — общий разбор всех ошибок журналов; здесь — только маркеры стабильности железа.
- **/gpu** — живое состояние карты (VRAM, клоки, процессы); здесь — история сбоев + температуры.

Контекст железа: модель машины, профиль разгона и уже поднятые ступени возьми из своего CLAUDE.md или памяти проекта, без них маркеры не читаются. Пример записи: «ноутбук X, профиль Y: GPU +200/+400, CPU PL1 55/PL2 65, сток 156/201».
