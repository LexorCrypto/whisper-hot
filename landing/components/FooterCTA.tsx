"use client";

import Reveal from "@/components/Reveal";
import { useAppStore } from "@/store/useAppStore";
import { REPO_URL, RELEASES_URL } from "@/lib/content";

export default function FooterCTA() {
  const appVersion = useAppStore((s) => s.appVersion);

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

          <div className="card mt-8 flex items-center gap-3 p-4 text-left">
            <span
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-free/15 text-free"
              aria-hidden="true"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </span>
            <p className="text-sm text-fg-dim">
              <span className="font-semibold text-fg">Подписано и нотаризовано Apple.</span>{" "}
              Просто перетащи в Applications и открой — без предупреждений Gatekeeper и без Терминала.
            </p>
          </div>

          <p className="mt-4 text-xs text-fg-mute">
            macOS 13+ · Apple Silicon · подпись Developer ID · нотаризовано Apple
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
