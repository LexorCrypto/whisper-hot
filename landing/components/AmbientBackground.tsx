interface Orb {
  /** Position + size + color + opacity (light, dark) + drift animation. */
  readonly className: string;
  /** Negative delay desyncs the shared keyframes so orbs never breathe in lockstep. */
  readonly animationDelay: string;
}

const ORBS: readonly Orb[] = [
  {
    className:
      "-top-56 -left-48 h-[560px] w-[560px] bg-accent opacity-20 dark:opacity-35 animate-drift",
    animationDelay: "0s",
  },
  {
    className:
      "-top-44 -right-56 h-[620px] w-[620px] bg-violet opacity-[0.16] dark:opacity-30 animate-float-slow",
    animationDelay: "-5s",
  },
  {
    className:
      "-bottom-52 -left-40 h-[520px] w-[520px] bg-rec opacity-[0.14] dark:opacity-25 animate-float-slow",
    animationDelay: "-10.5s",
  },
  {
    className:
      "-bottom-48 -right-44 h-[540px] w-[540px] bg-accent-soft opacity-20 dark:opacity-35 animate-drift",
    animationDelay: "-16s",
  },
];

/**
 * Fixed, full-viewport decorative backdrop that sits under all page content:
 * four slowly drifting blurred color orbs, a faint horizontal "waveform" line
 * grid, and a top/bottom vignette so the glow never crowds the edges.
 *
 * Purely CSS-driven (colors + opacity respond to [data-theme] via the `dark:`
 * variant, motion is neutralized by the global prefers-reduced-motion rule in
 * globals.css) — no hooks/effects needed, so this stays a server component.
 */
export default function AmbientBackground() {
  return (
    <div
      aria-hidden
      className="fixed inset-0 -z-10 overflow-hidden pointer-events-none"
    >
      {ORBS.map((orb, i) => (
        <div
          key={i}
          className={`absolute rounded-full blur-3xl will-change-transform ${orb.className}`}
          style={{ animationDelay: orb.animationDelay }}
        />
      ))}

      <svg className="absolute inset-0 h-full w-full text-fg opacity-[0.04]">
        <defs>
          <pattern
            id="ambient-grid"
            width="40"
            height="34"
            patternUnits="userSpaceOnUse"
          >
            <line x1="0" y1="0.5" x2="40" y2="0.5" stroke="currentColor" strokeWidth="1" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#ambient-grid)" />
      </svg>

      <div className="absolute inset-x-0 top-0 h-56 bg-gradient-to-b from-bg to-transparent" />
      <div className="absolute inset-x-0 bottom-0 h-56 bg-gradient-to-t from-bg to-transparent" />
    </div>
  );
}
