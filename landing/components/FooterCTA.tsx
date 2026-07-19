"use client";

import { useState } from "react";
import Reveal from "@/components/Reveal";
import { useAppStore } from "@/store/useAppStore";
import { REPO_URL, RELEASES_URL } from "@/lib/content";

const INSTALL_COMMAND = "xattr -cr /Applications/WhisperHot.app";
const COPY_RESET_DELAY_MS = 2000;

export default function FooterCTA() {
  const [copied, setCopied] = useState(false);
  const appVersion = useAppStore((s) => s.appVersion);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(INSTALL_COMMAND);
      setCopied(true);
      setTimeout(() => setCopied(false), COPY_RESET_DELAY_MS);
    } catch {
      // Clipboard API unavailable or denied — nothing sensible to fall back to.
    }
  }

  return (
    <section id="download" className="scroll-mt-[92px] py-24 md:py-32">
      <div className="container-wh">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="eyebrow">Скачать</p>
          <h2 className="mt-3 text-4xl font-semibold tracking-tight md:text-5xl">
            Поставь WhisperHot на свой Mac
          </h2>
          <p className="mt-4 text-lg text-fg-dim">
            Один хоткей — и голос становится текстом в любом окне macOS.
            Установка за минуту, без подписки и без аккаунта.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
            <a
              href={RELEASES_URL}
              target="_blank"
              rel="noreferrer"
              className="btn btn-primary"
            >
              Скачать {appVersion}
            </a>
            <a
              href={REPO_URL}
              target="_blank"
              rel="noreferrer"
              className="btn btn-ghost"
            >
              GitHub
            </a>
          </div>

          <div className="card mt-8 flex items-center justify-between gap-4 p-4 text-left">
            <code className="overflow-x-auto whitespace-nowrap font-mono text-sm text-fg">
              {INSTALL_COMMAND}
            </code>
            <button
              type="button"
              onClick={handleCopy}
              aria-label="Скопировать команду установки в буфер обмена"
              className="btn btn-ghost h-9 shrink-0 px-4 text-xs"
            >
              {copied ? "Скопировано!" : "Копировать"}
            </button>
          </div>

          <p className="mt-4 text-xs text-fg-mute">
            macOS 13+ · Apple Silicon · подпись Developer ID (без нотаризации)
          </p>
          <p className="mt-2 text-sm text-fg-dim">
            Совет напоследок: начни с{" "}
            <span className="font-semibold text-free">Groq</span> — платформа
            бесплатная и отлично работает.
          </p>
        </Reveal>

        <div className="mt-16 flex flex-col items-center justify-between gap-3 border-t border-line py-8 text-sm text-fg-mute sm:flex-row">
          <p>
            WhisperHot v{appVersion} · Apache-2.0
          </p>
          <div className="flex items-center gap-5">
            <a
              href={REPO_URL}
              target="_blank"
              rel="noreferrer"
              className="transition hover:text-fg"
            >
              GitHub
            </a>
            <a
              href={RELEASES_URL}
              target="_blank"
              rel="noreferrer"
              className="transition hover:text-fg"
            >
              Releases
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
