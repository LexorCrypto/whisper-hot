"use client";

import { useEffect, useRef, useState } from "react";
import { PROVIDERS, GROQ_PITCH } from "@/lib/content";
import { useAppStore } from "@/store/useAppStore";
import Reveal from "@/components/Reveal";

type Provider = (typeof PROVIDERS)[number];

function CheckIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" className="mt-0.5 size-4 shrink-0">
      <circle cx="10" cy="10" r="9" className="fill-free/15" />
      <path
        d="M6.4 10.3l2.4 2.4 4.6-5.4"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="text-free"
      />
    </svg>
  );
}

/**
 * Horizontal bar that animates from 0 to the provider's illustrative speed
 * score the first time it scrolls into view.
 */
function SpeedBar({ provider }: { provider: Provider }) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (typeof IntersectionObserver === "undefined") {
      setWidth(provider.speed);
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setWidth(provider.speed);
            io.disconnect();
            break;
          }
        }
      },
      { threshold: 0.35 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [provider.speed]);

  return (
    <div ref={ref} className="flex items-center gap-4">
      <span
        className={`w-36 shrink-0 text-sm md:w-40 ${
          provider.recommended ? "font-semibold text-fg" : "font-medium text-fg-dim"
        }`}
      >
        {provider.name}
      </span>
      <div className="relative h-3 flex-1 overflow-hidden rounded-full border border-line bg-surface">
        <div
          className={`h-full rounded-full transition-[width] duration-1000 ease-out ${
            provider.recommended ? "bg-linear-to-r from-accent to-violet" : "bg-fg-mute/50"
          }`}
          style={{ width: `${width}%` }}
        />
      </div>
      {provider.recommended && (
        <span className="shrink-0 rounded-full bg-free/15 px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-free">
          рекомендуем
        </span>
      )}
    </div>
  );
}

export default function Providers() {
  const selectedProvider = useAppStore((s) => s.selectedProvider);
  const setProvider = useAppStore((s) => s.setProvider);

  const activeProvider =
    PROVIDERS.find((p) => p.id === selectedProvider) ?? PROVIDERS[0];

  return (
    <section id="providers" className="scroll-mt-[92px] py-24 md:py-32">
      <div className="container-wh">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="eyebrow">Провайдеры</p>
          <h2 className="mt-3 text-4xl font-semibold tracking-tight text-fg md:text-5xl">
            Пять сервисов на выбор
          </h2>
          <p className="mt-4 text-lg text-fg-dim">
            Провайдер меняется в настройках в любой момент — у каждого свой слот
            ключа в Keychain.
          </p>
        </Reveal>

        {/* Groq hero recommendation — deliberately dominant */}
        <Reveal delay={80} className="mt-14">
          <div className="relative">
            <div
              aria-hidden="true"
              className="absolute -inset-6 rounded-[2.5rem] bg-linear-to-br from-accent/40 via-violet/30 to-accent-soft/20 blur-3xl"
            />
            <div className="relative rounded-2xl bg-linear-to-br from-accent via-violet to-accent-soft p-[1.5px] shadow-[0_24px_70px_-24px_rgba(10,132,255,0.45)]">
              <div className="relative overflow-hidden rounded-2xl bg-bg-elev p-8 md:p-12">
                <div
                  aria-hidden="true"
                  className="absolute right-8 top-8 size-2.5 rounded-full bg-accent animate-pulse-ring"
                />
                <div className="flex flex-col gap-10 md:flex-row md:items-start md:justify-between">
                  <div className="max-w-xl">
                    <span className="inline-flex items-center rounded-full bg-free px-3 py-1 text-xs font-semibold uppercase tracking-wide text-bg">
                      Бесплатно
                    </span>
                    <h3 className="mt-4 text-3xl font-semibold tracking-tight text-fg md:text-4xl">
                      {GROQ_PITCH.title}
                    </h3>
                    <p className="mt-2 text-lg font-medium text-accent-soft">
                      {GROQ_PITCH.tagline}
                    </p>
                    <p className="mt-4 leading-relaxed text-fg-dim">{GROQ_PITCH.body}</p>
                    <ul className="mt-6 space-y-3">
                      {GROQ_PITCH.points.map((point) => (
                        <li key={point} className="flex items-start gap-3 text-sm text-fg">
                          <CheckIcon />
                          <span>{point}</span>
                        </li>
                      ))}
                    </ul>
                  </div>

                  <div className="flex shrink-0 flex-row items-center gap-4 md:flex-col md:items-end md:gap-3">
                    <span className="text-gradient text-5xl font-bold tracking-tight md:text-6xl">
                      Groq
                    </span>
                    <span className="rounded-full border border-line-strong bg-surface px-3 py-1 font-mono text-xs text-accent-soft">
                      ~10×{"\u00A0"}быстрее
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </Reveal>

        {/* Interactive provider explorer */}
        <Reveal delay={140} className="mt-16">
          <div className="flex flex-wrap gap-3" role="group" aria-label="Выбор провайдера">
            {PROVIDERS.map((provider) => {
              const isSelected = provider.id === selectedProvider;
              return (
                <button
                  key={provider.id}
                  type="button"
                  aria-pressed={isSelected}
                  onClick={() => setProvider(provider.id)}
                  className={`flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-medium transition-colors ${
                    isSelected
                      ? "border-accent bg-accent/15 text-accent-soft"
                      : "border-line text-fg-dim hover:border-line-strong hover:text-fg"
                  }`}
                >
                  {provider.name}
                  {provider.recommended && (
                    <span className="rounded-full bg-free/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-free">
                      рекомендуем
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          <div className="card mt-6 p-6 md:p-8">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div>
                <div className="text-lg font-semibold text-fg">{activeProvider.name}</div>
                <div className="mt-1 font-mono text-sm text-fg">{activeProvider.model}</div>
              </div>
              <div className="flex flex-wrap gap-2">
                {activeProvider.offline && (
                  <span className="rounded-full border border-line-strong bg-surface px-2.5 py-1 text-xs font-medium text-fg-dim">
                    офлайн
                  </span>
                )}
                {activeProvider.free && (
                  <span className="rounded-full bg-free/15 px-2.5 py-1 text-xs font-medium text-free">
                    бесплатно
                  </span>
                )}
              </div>
            </div>
            <div className="mt-3 font-mono text-xs text-fg-mute">{activeProvider.api}</div>
            <p className="mt-4 text-sm leading-relaxed text-fg-dim">{activeProvider.note}</p>
          </div>
        </Reveal>

        {/* Speed race */}
        <Reveal delay={200} className="mt-16">
          <p className="text-sm text-fg-mute">Относительная скорость (наглядно)</p>
          <div className="mt-5 space-y-4">
            {PROVIDERS.map((provider) => (
              <SpeedBar key={provider.id} provider={provider} />
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
