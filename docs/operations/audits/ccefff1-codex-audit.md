# Codex audit — session range 41b914d..ccefff1 (v0.8.0 + v0.8.1)

- Auditor: `codex exec` (gpt-5.6-sol, reasoning=high, read-only)
- Date: 2026-07-19
- Scope: 9 session commits `41b914d..ccefff1` — landing (Next.js + Zustand + Tailwind),
  Swift recording-indicator refactor (5→3 стиля), иконка, бампы версии 0.8.0/0.8.1,
  автоверсия сайта, нотаризация DMG.

## VERDICT: ITERATE → устранено

P0/P1 не обнаружены (audit-гейт не блокирует). TypeScript проходит; `git diff --check`
чист; gitleaks утечек не нашёл. Swift build/test не запускались (read-only sandbox).

### Находки [P2] и устранение (commit c3ed519)

- **[P2] README.md:9,94** — документация описывала v0.7.2 (self-signed, `xattr -cr`),
  хотя v0.8.1 нотаризована. → **Исправлено**: статус 0.8.1, Developer ID + нотаризовано,
  три стиля индикатора (было «пять»/Studio), установка без `xattr -cr`.
- **[P2] landing/package.json:11** — `start: next start` несовместим с `output: "export"`.
  → **Исправлено**: неприменимый `start` удалён (static-export деплоится файлами в
  gh-pages; отдельный сервер не нужен).
- **[P2] landing/lib/version.ts:1** — HEAD-blob `0.8.0` при `VERSION` `0.8.1`.
  → **Исправлено**: синхронизирован с `VERSION` (0.8.1).

Re-audit ремедиэйшн-коммита `c3ed519` (reasoning=medium): **VERDICT: SHIP**, нет
P0/P1/P2 — см. `c3ed519-codex-audit.md`.
