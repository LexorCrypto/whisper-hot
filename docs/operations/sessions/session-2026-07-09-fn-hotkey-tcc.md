# Session 2026-07-09 — FN hotkey stopped working (TCC / re-sign)

## Симптом

Пользователь: FN-хоткей перестал срабатывать вне приложения (внутри — работал).
Сломалось сразу после того, как в этой сессии `/Applications/WhisperHot.app` заменили
самоподписанной сборки (`whisper-hot-local`) на Developer ID (TeamID `3Z9833DUR3`).

## Root cause (подтверждён базой TCC, не догадкой)

FN ловится системным `CGEvent.tapCreate(.cgSessionEventTap, .flagsChanged)` в
`Sources/WhisperHot/Hotkey/FnKeyMonitor.swift` → требует разрешения **Input Monitoring**
(`kTCCServiceListenEvent`). macOS привязывает TCC-гранты к code-signing identity приложения.
Смена подписи обнулила грант. Прямое чтение `TCC.db`: у WhisperHot отсутствовала строка
`kTCCServiceListenEvent` (при живой у Discord) → tap не создаётся → FN снаружи молчит.
Внутри приложения FN работал, т.к. окно активно и системный tap не нужен. Дефолтный ⌥⌘5
(Carbon `RegisterEventHotKey`, `HotkeyManager.swift`) от TCC не зависит и не ломался.

## Fix (операционный, без правок кода)

```
tccutil reset ListenEvent com.aleksejsupilin.WhisperHot
tccutil reset Accessibility com.aleksejsupilin.WhisperHot
# перезапуск /Applications/WhisperHot.app; в System Settings → Privacy & Security →
# Input Monitoring и Accessibility включить WhisperHot; ещё раз перезапустить.
```

Итог (проверено чтением `TCC.db`): `kTCCServiceListenEvent = 2`, `kTCCServiceAccessibility = 2`
(оба granted). Пользователь подтвердил: FN и вставка работают.

Accessibility нужен для вставки распознанного текста (`PasteService`) и тоже слетал от смены
подписи — переразрешён.

## На будущее

Developer ID-подпись стабильна между версиями, поэтому будущие обновления эти гранты сохранят
(самоподпись меняла подпись на каждой пересборке → разрешения слетали при каждом обновлении).
Записано в память проекта: `project_whisperhot_tcc_resign.md` + gstack-learnings.

## Изменённые файлы

- Кода репозитория не менялось (диагностика + операционный fix через `tccutil`).
- `docs/operations/sessions/session-2026-07-09-fn-hotkey-tcc.md` — этот отчёт.
- `docs/operations/audits/ee0cbc7-codex-audit.md` — аудит serena-config коммита.
