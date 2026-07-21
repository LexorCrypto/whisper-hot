# Audit record — commit 910332f (indicator always-on-top при записи)

- **External Codex audit: NOT COMPLETED** (та же деградация, что в
  ef7650f-codex-audit.md: модель недоступна / 300s timeout).
- **Gate closed via direct verification** (не Codex): прямой ревью кода + сборка.
  Ретроспективно — v0.9.0 уже опубликован.
- Date: 2026-07-21
- Scope: `git show 910332f` — IndicatorController (installKeepOnTopObserver /
  removeKeepOnTopObserver, вызовы в show()/hide(), свойство activationObserver).

## Verification: PASS (нет P1); одно [P2]-ограничение вынесено в follow-up

- Сборка чистая; `MainActor.assumeIsolated` внутри блока
  `NSWorkspace.didActivateApplicationNotification` (`queue: .main`) — тот же паттерн,
  что в существующем `IndicatorViewModel` Timer-блоке (main-thread доставка → assume
  валиден). Компилятор Swift принял без ошибок concurrency.
- Lifecycle наблюдателя: `installKeepOnTopObserver()` защищён
  `guard activationObserver == nil` (нет двойной подписки при повторном `show()`);
  `removeKeepOnTopObserver()` вызывается первым в `hide()` и обнуляет токен — утечки
  нет. `[weak self]` в блоке.

## [P2] Открытое ограничение — deferred → issue #11 (audit)

- Ре-ассерт `orderFrontRegardless()` срабатывает на **активацию приложения**, не на
  появление нового окна внутри уже активного приложения; `.statusBar` по дизайну ниже
  системных popup/menu-уровней. Реализация РАССЧИТАНА на переключение приложений,
  Spaces и fullscreen другого приложения (`.canJoinAllSpaces` + `.fullScreenAuxiliary`),
  но проверена только на уровне кода/сборки — GUI-прогон (fullscreen / app-switch / popup)
  НЕ выполнялся. Пользователь требовал «всегда поверх всех окон» — это НЕ формальная
  абсолютная гарантия против всех оконных уровней. Не блокирует релиз; поднимать до
  `.screenSaver` намеренно не стали (перекрыл бы системный UI). Deferred для
  доработки/GUI-проверки → **issue #11** (label `audit`).
- Секретов/PII нет.
