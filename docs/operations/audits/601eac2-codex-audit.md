# Codex audit — commit 601eac2 (bump to v0.9.0, build 22)

- Auditor: `codex exec` (дефолтная модель, read-only) — ревью release-prep диффа
  этой сессии дал **GREEN**. (Отдельный повтор per-commit деградировал по timeout;
  release-prep GREEN покрывает ровно этот bump-дифф.)
- Date: 2026-07-21
- Scope: `git show 601eac2` — VERSION, Resources/Info.plist, CHANGELOG.md.

## VERDICT: SHIP

- [P0] Нет. [P1] Нет. [P2] Нет.
- Codex GREEN: `VERSION == Info.plist CFBundleShortVersionString == 0.9.0`;
  `CFBundleVersion` поднят ровно 21 → 22; секция CHANGELOG `[0.9.0]` соответствует
  изменениям; посторонних правок нет.
- Тег `v0.9.0` запушен атомарно; DMG нотаризован (Apple: Accepted), staple + `spctl`
  accepted; GitHub Release опубликован с DMG + `.sha256`.
- Секретов/PII нет.
