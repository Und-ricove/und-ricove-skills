---
name: update-check
description: Проверка обновлений Claude Desktop и Claude Code CLI - где живёт правда о версиях, как читать строку хука на старте сессии, как обновляться. Вызывать по /update-check, «есть ли обновления Claude», «какая версия Claude Code», при странностях после обновления Desktop и при правке хука SessionStart.
---

# Обновления Claude Desktop и Claude Code

Хук `SessionStart` (в `%USERPROFILE%\.claude\settings.json`) запускает
`<папка скилла>\scripts\update-check.ps1` и кладёт в
контекст сессии одну строку вида:

```
⬆ ОБНОВЛЕНИЯ (12.09 16:05): Desktop 1.52386.0 → 1.52386.3 (скачана, ждёт перезапуска приложения) · CLI терминала 2.1.259 → 2.1.269 (команда: claude update) · CLI внутри Desktop 2.1.266 (...)
```

Если строка начинается с «⬆ ОБНОВЛЕНИЯ» — сказать пользователю в первом же
ответе сессии, коротко, одной строкой. «✓ Обновления» — молчать.

## Закон: только докладывать

Скрипт и скилл ничего не ставят. Обновление — решение пользователя
(правило: установки только по согласованию с пользователем). Исключение
не делать даже для «мелкого» патча.

## Три разных Claude Code на этой машине

1. **CLI терминала** — `%USERPROFILE%\.local\bin\claude.exe` (native
   installer, канал `latest`). Обновляется командой `claude update`.
2. **CLI внутри Desktop** — `%APPDATA%\Claude\claude-code\<версия>\claude.exe`.
   Именно он выполняет сессии вкладки Code (переменная
   `CLAUDE_CODE_ENTRYPOINT=claude-desktop`, процесс `CLAUDE_PID`).
   Обновляется только вместе с Desktop, отдельно не трогается.
3. **Desktop** — пакет MSIX `Claude_<версия>_x64__pzs8sxrjxfjjc` в
   `C:\Program Files\WindowsApps`, подпись Developer, id в winget
   `Anthropic.Claude`.

Следствие: новая команда из рассылки (например `/skill-doctor` с 2.1.261)
может быть доступна в Desktop-сессии и отсутствовать в терминале,
или наоборот. Смотреть обе версии.

## Где правда о доступной версии Desktop

Встроенный апдейтер ходит на `https://api.anthropic.com`, скачивает
пакет сам и пишет в журнал `%LOCALAPPDATA%\Claude\logs\main.log`
(НЕ в `%APPDATA%\Claude\logs` — тот замолчал 21.08.2026):

```
[updater] Checking for updates
[updater] Found an update, downloading
[updater] Update downloaded and ready to install { releaseName: 'Claude 1.52386.3' }
[updater] Staged version 1.52386.3 is still current (latest: 1.52386.3, lastTarget: null)
```

«Staged … still current» = обновление скачано и ждёт **перезапуска
приложения** (полного выхода через трей, не закрытия окна). Пока
Desktop не перезапущен, установленная версия остаётся старой.

Ловушки:
- `winget show Anthropic.Claude` и Store показывают версии на месяцы
  старше реальной (1.44121.2 против установленной 1.52386.0 на
  12.09.2026) — не источник.
- `Get-AppxPackage` из песочницы может вернуть пусто (ловушка CIM);
  запасной путь — `CLAUDE_CODE_DESKTOP_APP_VERSION` в окружении
  Desktop-сессии или имя папки в `WindowsApps` из `Get-Process claude`.
- Журнал 8+ МБ — читать хвостом (скрипт берёт последние 400 КБ).

## Где правда о доступной версии CLI

`https://registry.npmjs.org/@anthropic-ai/claude-code/latest` → поле
`version`. Скрипт кэширует ответ на 6 часов в
`%USERPROFILE%\.claude\cache\update-check.json`; без сети берёт старый
кэш и говорит об этом.

## Ручная проверка

```
pwsh -NoProfile -ExecutionPolicy Bypass -File "<папка скилла>\scripts\update-check.ps1"
```

Если хук не сработал: проверить `hooks.SessionStart` в settings.json,
запустить строку выше руками, посмотреть `claude --debug`.

## Что менялось

- 12.09.2026 — скилл, скрипт и хук созданы по просьбе пользователя;
  в тот же день найдено: Desktop 1.52386.3 скачан и ждёт перезапуска,
  CLI терминала 2.1.259 при доступной 2.1.269.
- 12.09.2026 (вечер) — ловушка: после перезапуска Desktop хвост журнала ещё хранит «Staged … still current», и скрипт писал «ждёт перезапуска» при уже установленной версии; теперь скачанная ≤ установленной = «установлена». Правда об установке — строка «Version changed since last launch: A → B» и папка процесса в WindowsApps.
