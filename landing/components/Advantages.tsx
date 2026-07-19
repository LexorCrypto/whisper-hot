import Reveal from "@/components/Reveal";
import { ADVANTAGES } from "@/lib/content";

/** Tiny decorative waveform squiggle tucked into the card corner. */
function MiniWave({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 64 28"
      fill="none"
      className={className}
    >
      <path
        d="M1 14h3l2.5-9 3.5 18 3-14 2.5 7 3-16 3.5 20 2.5-9h3l2-5 3 11 2.5-7h9"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export default function Advantages() {
  return (
    <section id="advantages" className="scroll-mt-[92px] py-24 md:py-32">
      <div className="container-wh">
        <Reveal>
          <p className="eyebrow">Преимущества</p>
          <h2 className="mt-3 max-w-2xl text-4xl font-semibold tracking-tight md:text-5xl">
            Почему WhisperHot
          </h2>
        </Reveal>

        <div className="mt-12 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {ADVANTAGES.map((item, i) => (
            <Reveal key={item.label} delay={i * 90}>
              <article className="card relative h-full overflow-hidden rounded-2xl p-6">
                <span
                  aria-hidden="true"
                  className="absolute inset-y-0 left-0 w-[3px] bg-gradient-to-b from-accent via-accent-soft to-violet"
                />
                <MiniWave className="absolute right-4 top-5 h-6 w-16 text-accent/25" />
                <p className="font-mono text-4xl font-semibold text-gradient">
                  {item.metric}
                </p>
                <p className="eyebrow mt-4">{item.label}</p>
                <p className="mt-2 text-sm leading-relaxed text-fg-dim">
                  {item.text}
                </p>
              </article>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
