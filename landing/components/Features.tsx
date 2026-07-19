import type { JSX } from "react";
import Reveal from "@/components/Reveal";
import { FEATURES, type FeatureIcon } from "@/lib/content";

const ICON_PROPS = {
  width: 24,
  height: 24,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

function icon(key: FeatureIcon): JSX.Element {
  switch (key) {
    case "hotkey":
      return (
        <svg {...ICON_PROPS}>
          <rect x="3" y="7" width="18" height="11" rx="2.5" />
          <path d="M7.5 11.5h.01M11.5 11.5h.01M15.5 11.5h.01" />
          <path d="M8 15h8" />
        </svg>
      );
    case "paste":
      return (
        <svg {...ICON_PROPS}>
          <rect x="7" y="4" width="10" height="4" rx="1.2" />
          <path d="M7 6H6a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-1" />
          <path d="M8.5 13h7M8.5 16.5h5" />
        </svg>
      );
    case "llm":
      return (
        <svg {...ICON_PROPS}>
          <path d="M12 3l1.6 4.2L18 9l-4.4 1.8L12 15l-1.6-4.2L6 9l4.4-1.8L12 3z" />
          <path d="M18.5 15l.8 2.1 2.1.8-2.1.8-.8 2.1-.8-2.1-2.1-.8 2.1-.8.8-2.1z" />
        </svg>
      );
    case "routing":
      return (
        <svg {...ICON_PROPS}>
          <circle cx="6" cy="6" r="2.2" />
          <circle cx="6" cy="18" r="2.2" />
          <circle cx="18" cy="12" r="2.2" />
          <path d="M8 6.6C11.5 7.4 14.5 9.4 15.9 11M8 17.4C11.5 16.6 14.5 14.6 15.9 13" />
        </svg>
      );
    case "offline":
      return (
        <svg {...ICON_PROPS}>
          <path d="M3 3l18 18" />
          <path d="M5 8.5a15.6 15.6 0 0 1 4.4-2.6M13 5.1c2.4.3 4.7 1.4 6.6 3.2M8.3 12.2a9.6 9.6 0 0 1 4.9-2M16.9 11.6c.9.6 1.7 1.3 2.4 2.1" />
          <path d="M9 16.2a5.4 5.4 0 0 1 4.6-1.6" />
          <circle cx="12" cy="19.2" r="1.15" fill="currentColor" stroke="none" />
        </svg>
      );
    case "privacy":
      return (
        <svg {...ICON_PROPS}>
          <path d="M12 3.5l6.5 2.4v5.3c0 4.2-2.7 7.5-6.5 9.3-3.8-1.8-6.5-5.1-6.5-9.3V5.9L12 3.5z" />
          <path d="M9.3 12.1l1.9 1.9 3.5-3.9" />
        </svg>
      );
    case "waveform":
      return (
        <svg {...ICON_PROPS}>
          <path d="M3 12h2.2l1.4-5.5 2.3 11 2.2-8.4 1.8 5.7 1.9-8.3 1.6 5.5H21" />
        </svg>
      );
    case "dictionary":
      return (
        <svg {...ICON_PROPS}>
          <path d="M5 4.5h9.5A2.5 2.5 0 0 1 17 7v12.5H7A2.5 2.5 0 0 1 4.5 17V5A.5.5 0 0 1 5 4.5z" />
          <path d="M4.5 17.2A2.3 2.3 0 0 1 6.8 15H17" />
          <path d="M8 8.3h5.5M8 11.3h5.5" />
        </svg>
      );
  }
}

export default function Features() {
  return (
    <section id="features" className="scroll-mt-[92px] py-24 md:py-32">
      <div className="container-wh">
        <Reveal>
          <p className="eyebrow">Возможности</p>
          <h2 className="mt-3 max-w-2xl text-4xl font-semibold tracking-tight md:text-5xl">
            Всё, что нужно для диктовки
          </h2>
          <p className="mt-4 max-w-xl text-lg text-fg-dim">
            От нажатия хоткея до готового текста в буфере — каждый шаг продуман
            под скорость и приватность.
          </p>
        </Reveal>

        <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map((feature, i) => (
            <Reveal key={feature.title} delay={(i % 4) * 90}>
              <article className="card h-full rounded-2xl p-6 transition hover:-translate-y-1">
                <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-surface-strong text-accent">
                  {icon(feature.icon)}
                </div>
                <h3 className="mt-4 font-semibold text-fg">{feature.title}</h3>
                <p className="mt-2 text-sm text-fg-dim">{feature.text}</p>
              </article>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
