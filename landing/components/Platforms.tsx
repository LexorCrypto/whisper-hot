import type { ReactNode } from "react";
import Reveal from "@/components/Reveal";
import { PLATFORMS, type Platform } from "@/lib/content";

/* ---------- Platform icons ---------- */

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-9 w-9" fill="currentColor" aria-hidden="true">
      <path d="M16.365 1.43c0 1.14-.493 2.27-1.177 3.08-.744.9-1.99 1.57-2.987 1.57-.12 0-.23-.02-.3-.03-.01-.06-.04-.22-.04-.39 0-1.15.572-2.27 1.206-2.98.804-.94 2.142-1.64 3.248-1.68.03.13.05.28.05.43zm4.565 15.71c-.03.07-.463 1.58-1.518 3.12-.945 1.34-1.94 2.71-3.43 2.71-1.517 0-1.9-.88-3.63-.88-1.698 0-2.302.91-3.67.91-1.365 0-2.324-1.267-3.428-2.85-1.3-1.98-2.353-5.02-2.353-7.9 0-4.65 3.02-7.11 5.996-7.11 1.35 0 2.481.87 3.334.87.813 0 2.16-.921 3.66-.921.6 0 2.762.05 4.185 2.088-.11.07-2.5 1.454-2.5 4.43 0 3.556 3.12 4.8 3.155 4.83z" />
    </svg>
  );
}

function WindowsIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-9 w-9" fill="currentColor" aria-hidden="true">
      <rect x="2" y="2" width="9" height="9" rx="1.4" />
      <rect x="13" y="2" width="9" height="9" rx="1.4" />
      <rect x="2" y="13" width="9" height="9" rx="1.4" />
      <rect x="13" y="13" width="9" height="9" rx="1.4" />
    </svg>
  );
}

function ChipIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      className="h-9 w-9"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.5}
      strokeLinecap="round"
      aria-hidden="true"
    >
      <rect x="6" y="6" width="12" height="12" rx="1.5" />
      <rect x="9.5" y="9.5" width="5" height="5" rx="0.75" />
      <path d="M9 2v3.2M12 2v3.2M15 2v3.2M9 18.8V22M12 18.8V22M15 18.8V22M2 9h3.2M2 12h3.2M2 15h3.2M18.8 9H22M18.8 12H22M18.8 15H22" />
    </svg>
  );
}

const PLATFORM_ICONS: Record<Platform["key"], ReactNode> = {
  macos: <AppleIcon />,
  windows: <WindowsIcon />,
  intel: <ChipIcon />,
};

/* ---------- Status badge ---------- */

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 12.5l5 5L20 6" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 7.5v4.7l3.2 2.3" />
    </svg>
  );
}

function DashIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" aria-hidden="true">
      <path d="M5 12h14" />
    </svg>
  );
}

const STATUS_STYLE: Record<Platform["status"], { badge: string; icon: ReactNode }> = {
  shipped: {
    badge: "border-free/30 bg-free/10 text-free",
    icon: <CheckIcon />,
  },
  planned: {
    badge: "border-rec-soft/30 bg-rec-soft/10 text-rec-soft",
    icon: <ClockIcon />,
  },
  unsupported: {
    badge: "border-line bg-surface text-fg-mute",
    icon: <DashIcon />,
  },
};

/* ---------- Section ---------- */

export default function Platforms() {
  return (
    <section id="platforms" className="scroll-mt-[92px] py-24 md:py-32">
      <div className="container-wh">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="eyebrow">Платформы</p>
          <h2 className="mt-3 text-4xl font-semibold tracking-tight md:text-5xl">
            Где работает WhisperHot
          </h2>
          <p className="mt-4 text-lg text-fg-dim">
            Нативное приложение для macOS уже доступно. Остальные платформы —
            открытая дорожная карта, а не пустое обещание в README.
          </p>
        </Reveal>

        <div className="mt-14 grid gap-5 md:grid-cols-3">
          {PLATFORMS.map((platform, i) => {
            const isMac = platform.key === "macos";
            const status = STATUS_STYLE[platform.status];
            return (
              <Reveal key={platform.key} delay={i * 100} className="h-full">
                <article
                  className={`card relative flex h-full flex-col gap-6 p-8 transition-transform duration-300 hover:-translate-y-1 ${
                    isMac
                      ? "border-accent/40 shadow-[0_0_60px_-18px_var(--accent)] ring-1 ring-accent/15"
                      : ""
                  }`}
                >
                  {isMac ? (
                    <span className="absolute right-6 top-6 rounded-full border border-accent/30 bg-accent/10 px-2.5 py-1 text-[11px] font-medium tracking-wide text-accent">
                      Рекомендуется
                    </span>
                  ) : null}

                  <div
                    className={`flex h-16 w-16 items-center justify-center rounded-2xl border ${
                      isMac
                        ? "border-accent/30 bg-accent/10 text-accent"
                        : "border-line bg-surface-strong text-fg-dim"
                    }`}
                  >
                    {PLATFORM_ICONS[platform.key]}
                  </div>

                  <div className="flex flex-col gap-3">
                    <h3 className="text-2xl font-semibold">{platform.name}</h3>
                    <span
                      className={`inline-flex w-fit items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium ${status.badge}`}
                    >
                      {status.icon}
                      {platform.badge}
                    </span>
                  </div>

                  <p className="text-sm leading-relaxed text-fg-dim">{platform.detail}</p>
                </article>
              </Reveal>
            );
          })}
        </div>
      </div>
    </section>
  );
}
