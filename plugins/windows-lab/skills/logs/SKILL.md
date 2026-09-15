---
name: logs
description: Свежие ошибки журналов Windows (System + Application) со сводкой по-русски. Вызывать по /logs, «что в журналах», «посмотри логи». Подозрение на железо/разгон — это /hw-health.
---

# Свежие ошибки журналов

Аргумент — часы назад (по умолчанию 24): `/logs 48`.

## Сбор — одним вызовом PowerShell

Каждый `Get-WinEvent` — только в `try/catch` с `-ErrorAction Stop`: «No events found» у него — non-terminating error, и `-ErrorAction SilentlyContinue` НЕ спасает от exit 1 в этой обвязке. Пустой журнал — это ЧИСТО, а не сбой.

Группируй внутри PowerShell — сырые события в вывод не выгружать.

```powershell
$hours = 24   # ← подставь аргумент скилла, если задан
$since = (Get-Date).AddHours(-$hours)
$events = foreach ($log in 'System','Application') {
  try { Get-WinEvent -FilterHashtable @{LogName=$log;Level=1,2;StartTime=$since} -ErrorAction Stop } catch {}
}
$events | Group-Object ProviderName, Id | Sort-Object Count -Descending |
  ForEach-Object { [pscustomobject]@{
    Раз       = $_.Count
    Последний = ($_.Group | Sort-Object TimeCreated -Descending)[0].TimeCreated.ToString('dd.MM HH:mm')
    Провайдер = $_.Group[0].ProviderName
    Id        = $_.Group[0].Id
    Текст     = (($_.Group[0].Message) -split '\r?\n')[0]
  } } | Format-Table -AutoSize | Out-String -Width 220
```

(Level 1 = Critical, 2 = Error.)

## Защита от «тихой пустоты» песочницы

Если событий 0 — ПЕРЕД вердиктом «чисто» убедись, что журнал вообще читается (песочница умеет тихо возвращать пусто; проверяем независимым каналом, как netsh/reg query для CIM):

```powershell
wevtutil qe System /c:1 /rd:true /f:text
```

Вернулся хоть один ивент любого уровня → доступ есть, «чисто» честное. Пусто и здесь → чтение журналов заблокировано: скажи об этом пользователю прямо и вердикт НЕ выноси.

## Вывод по-русски, крупно

- **Итог первой строкой**: «Чисто ✅» или «N ошибок, из них важных M».
- Таблица групп — короткая и разреженная (бережно к глазам): последний раз, провайдер, Id, сколько раз, одна строка смысла по-русски. Не больше ~10 строк; остальное — одной строкой «и ещё K групп по 1 разу».
- Известный шум на многих машинах (тревогу НЕ поднимать): DCOM 10016 (косметика), SCM 7043 при выключении (косметика), Camera_FrameServer watchdog (штатное). Если встретились — одна строка в конце, не в основной таблице. У пользователя может быть свой список повторяющегося шума — уточни.
- **Страшное — крупно и ПЕРВЫМ**: диск/NTFS/storahci, Kernel-Power 41, WHEA, Display 4101 (TDR), nvlddmkm. Для WHEA / TDR / Kernel-Power следующий шаг — запусти скилл **hw-health**: там датчики LibreHardwareMonitor и вердикт по разгону.
