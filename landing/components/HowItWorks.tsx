import Reveal from "@/components/Reveal";
import { STEPS } from "@/lib/content";

/**
 * Thin connector segment rendered between two adjacent step cards on md+.
 * A soft dot glides along the line via the shared `animate-shimmer`
 * background-position sweep (no custom keyframes, no hooks) — purely
 * CSS-driven, so this stays a server component. Hidden below md, per spec.
 */
function Connector({ delay }: { delay: string }) {
  return (
    <div
      aria-hidden="true"
      className="relative hidden h-4 w-16 shrink-0 self-center overflow-hidden md:block"
    >
      <span className="absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-line-strong/70" />
      <span
        className="absolute inset-0 animate-shimmer bg-no-repeat"
        style={{
          backgroundImage:
            "radial-gradient(circle 4px at center, var(--accent-soft) 0%, var(--accent) 55%, transparent 100%)",
          backgroundSize: "18px 16px",
          animationDelay: delay,
        }}
      />
    </div>
  );
}

export default function HowItWorks() {
  return (
    <section id="how" className="scroll-mt-[92px] py-24 md:py-32">
      <div className="container-wh">
        <Reveal>
          <p className="eyebrow">Как это работает</p>
          <h2 className="mt-3 max-w-2xl text-4xl font-semibold tracking-tight md:text-5xl">
            Три нажатия — и готово
          </h2>
          <p className="mt-4 max-w-xl text-lg text-fg-dim">
            От нажатия хоткея до вставленного текста — один и тот же путь
            каждый раз, без мастеров настройки и лишних окон.
          </p>
        </Reveal>

        <div className="mt-12 flex flex-col gap-6 md:mt-16 md:flex-row md:gap-0">
          {STEPS.flatMap((step, i) => {
            const card = (
              <Reveal key={step.n} delay={i * 120} className="md:flex-1">
                <article className="card relative flex h-full flex-col gap-4 rounded-2xl p-6 md:p-8">
                  <span className="font-mono text-5xl font-semibold leading-none text-gradient md:text-6xl">
                    {step.n}
                  </span>
                  <h3 className="text-xl font-semibold text-fg">{step.title}</h3>
                  <p className="text-fg-dim">{step.text}</p>
                </article>
              </Reveal>
            );

            if (i === STEPS.length - 1) return [card];

            return [card, <Connector key={`connector-${step.n}`} delay={`${i * -0.9}s`} />];
          })}
        </div>
      </div>
    </section>
  );
}
