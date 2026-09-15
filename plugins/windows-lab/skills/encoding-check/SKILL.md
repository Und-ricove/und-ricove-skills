---
name: encoding-check
description: Смоук-тест UTF-8 всех трактов (pwsh 7, PS 5.1, Git Bash, Python/uv, файлы, git). Вызывать по /encoding-check, «проверь кодировки», после Canary-билда, при кракозябрах или «вопросиках».
---

# Смоук-матрица кодировок

Эталонная строка: `Тест-Кириллица_★_2026` (кириллица + символ вне cp1251 — двойную перекодировку не спрячешь).

Правила прогона:
- Временные файлы — только в scratchpad сессии (не Desktop/Documents: там Controlled Folder Access).
- Системный слой — через `reg query`, НЕ через CIM/WMI (в песочнице CIM тихо возвращает пусто).
- Всё автоматически, без ручного ввода от пользователя.

Прогони ШЕСТЬ трактов, каждый сравни с эталоном:

1. **pwsh 7** (инструмент PowerShell): `[Console]::OutputEncoding.CodePage; 'Тест-Кириллица_★_2026'` — CodePage 65001, строка без искажений.
2. **PowerShell 5.1**: `powershell.exe -NoProfile -Command "[Console]::OutputEncoding.CodePage; 'Тест-Кириллица_★_2026'"` — тоже 65001. `-NoProfile` намеренно: проверяем базовый системный слой, а не заплатку из профиля. Если без профиля ✗, а с профилем (`powershell.exe -Command ...`) ✓ — так и скажи: «UTF-8 держится только на профиле», это жёлтый флаг, не зелёный.
3. **Git Bash** (инструмент Bash): `echo 'Тест-Кириллица_★_2026'; locale charmap 2>/dev/null || echo нет-locale` — ожидаем UTF-8.
4. **Python/uv** (из pwsh): `python3.12 -c "import sys; print('Тест-Кириллица_★_2026', sys.stdout.encoding)"` — encoding должен быть utf-8 (PYTHONUTF8=1). Если `python3.12` не найден — uv-шим в `%USERPROFILE%\.local\bin` слетел: запусти fallback `uv run --python 3.12 python -c "..."` и отметь пропажу шима как отдельную находку.
5. **Файловый круг + BOM**: из pwsh записать эталон в файл в scratchpad (`Set-Content -Encoding utf8`) → прочитать инструментом Read → сравнить. Затем байтовый чек: `[System.IO.File]::ReadAllBytes('<путь>')[0..2]` — если `239 187 191` (EF BB BF), в файле BOM → ✗ (стандарт: UTF-8 БЕЗ BOM).
6. **git-конфиг**: `git config --global core.quotepath` → `false`; `git config --global i18n.commitencoding` → `utf-8`. Пустой вывод (exit 1) = ключ не задан = ✗, а не «по умолчанию сойдёт».

## Ловушка инструмента Write (найдена 03.09.2026)

Инструмент Write в Claude Code на Windows пишет новые файлы с **CRLF** (BOM не ставит). Стандарт — LF. После создания файлов Write/Edit проверять и конвертировать:

```powershell
$enc = New-Object System.Text.UTF8Encoding($false)
foreach ($p in $files) { $t = [IO.File]::ReadAllText($p, $enc) -replace "`r`n","`n" -replace "`r","`n"; [IO.File]::WriteAllText($p, $t, $enc) }
# проверка: ([IO.File]::ReadAllBytes($p) | Where-Object { $_ -eq 13 }).Count → 0
```

`sed -i 's/\r$//'` из Git Bash в этой песочнице CR **не убирает** (проверено: счётчик CR не изменился). Конвертировать только через .NET.

Системный слой (reg query):
- `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v ACP` → 65001
- `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v OEMCP` → 65001 (кодировка консольных приложений — отдельный шов)
- `reg query HKCU\Environment /v PYTHONUTF8` → 1

## Вывод

Таблица «тракт → ✓/✗» крупно, по-русски, без мелких простыней. Для любого ✗:
- покажи, ЧТО именно вернулось (побайтово, если надо);
- назови слой поломки по сигнатуре: «РўРµСЃС‚» = двойная перекодировка UTF-8→cp1251; «???» = вывод в не-Unicode консоль; «пїЅ» или � = замещающие символы при чтении не тем декодером;
- предложи точечный фикс (какой профиль/ключ реестра/конфиг чинить); правки — поэтапные и обратимые, elevated-шаги только с предупреждением.

Все ✓ — одной строкой: **«Швов нет, все тракты UTF-8 ✅»**.