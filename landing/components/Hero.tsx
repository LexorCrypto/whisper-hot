"use client";

import { useEffect, useRef, useState } from "react";
import { useAppStore } from "@/store/useAppStore";
import Reveal from "@/components/Reveal";
import { REPO_URL, RELEASES_URL } from "@/lib/content";

/** Phrase "typed" into the Studio mock while the demo recording runs. */
const DEMO_PHRASE = "Собери релиз, запушь ветку и напиши в Slack, что деплой готов.";

/** Canvas palette — literal hex, canvas 2D context can't read CSS custom properties. */
const WAVE_ACCENT = "#0a84ff";
const WAVE_ACCENT_SOFT = "#64d2ff";
const WAVE_VIOLET = "#bf5af2";

const BAR_COUNT = 48;
const BAR_GAP = 3;
const TYPE_INTERVAL_MS = 42;
const TIMER_TICK_MS = 250;

function formatClock(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, "0");
  const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, "0");
  return `${minutes}:${seconds}`;
}

/** Tracks prefers-reduced-motion for the JS-driven bits CSS alone can't neutralize. */
function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    if (typeof window === "undefined" || !window.matchMedia) return;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(query.matches);
    const onChange = (e: MediaQueryListEvent) => setReduced(e.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);
  return reduced;
}

function MicIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-6 w-6"
      aria-hidden="true"
    >
      <rect x="9" y="2.5" width="6" height="12" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0" />
      <line x1="12" y1="18" x2="12" y2="21.5" />
      <line x1="8.5" y1="21.5" x2="15.5" y2="21.5" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className="h-5 w-5" aria-hidden="true">
      <rect x="6" y="6" width="12" height="12" rx="2.5" />
    </svg>
  );
}

/**
 * Flagship above-the-fold screen: pitch on the left, a live "Studio" panel
 * mock on the right — canvas waveform, mm:ss timer and typed transcript,
 * all driven by the shared `isRecording` store flag.
 */
export default function Hero() {
  const isRecording = useAppStore((s) => s.isRecording);
  const toggleRecording = useAppStore((s) => s.toggleRecording);
  const reducedMotion = useReducedMotion();

  const [elapsedSec, setElapsedSec] = useState(0);
  const [transcript, setTranscript] = useState("");

  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const isRecordingRef = useRef(isRecording);
  isRecordingRef.current = isRecording;

  // Timer: counts up from 00:00 while recording, freezes the moment it stops.
  useEffect(() => {
    if (!isRecording) return;
    setElapsedSec(0);
    const start = Date.now();
    const id = window.setInterval(() => {
      setElapsedSec(Math.floor((Date.now() - start) / 1000));
    }, TIMER_TICK_MS);
    return () => window.clearInterval(id);
  }, [isRecording]);

  // Live transcript: types the demo phrase in while recording, keeps whatever
  // landed on screen once it stops. Reduced motion skips the typing entirely.
  useEffect(() => {
    if (!isRecording) return;
    if (reducedMotion) {
      setTranscript(DEMO_PHRASE);
      return;
    }
    setTranscript("");
    let charIndex = 0;
    const id = window.setInterval(() => {
      charIndex += 1;
      setTranscript(DEMO_PHRASE.slice(0, charIndex));
      if (charIndex >= DEMO_PHRASE.length) window.clearInterval(id);
    }, TYPE_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [isRecording, reducedMotion]);

  // Waveform: symmetric bars growing from the vertical center, redrawn every
  // frame from the container's real pixel size. Idle = quiet drift, recording
  // = sines + noise. Reduced motion draws one static frame and skips rAF.
  useEffect(() => {
    const canvas = canvasRef.current;
    const wrap = wrapRef.current;
    if (!canvas || !wrap) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let width = 0;
    let height = 0;
    const dpr = Math.max(1, window.devicePixelRatio || 1);

    const draw = (t: number) => {
      if (!width || !height) return;
      ctx.clearRect(0, 0, width, height);

      const gradient = ctx.createLinearGradient(0, 0, width, 0);
      gradient.addColorStop(0, WAVE_ACCENT);
      gradient.addColorStop(0.55, WAVE_ACCENT_SOFT);
      gradient.addColorStop(1, WAVE_VIOLET);
      ctx.fillStyle = gradient;

      const barWidth = Math.max(2, width / BAR_COUNT - BAR_GAP);
      const centerY = height / 2;
      const recording = isRecordingRef.current;
      const ceiling = recording ? height * 0.42 : height * 0.1;

      for (let i = 0; i < BAR_COUNT; i += 1) {
        const x = i * (barWidth + BAR_GAP);
        const phase = i * 0.5;
        let amp: number;
        if (recording) {
          amp = Math.abs(
            Math.sin(t * 0.0055 + phase) * 0.55 +
              Math.sin(t * 0.012 + phase * 1.8) * 0.3 +
              (Math.random() - 0.5) * 0.4,
          );
        } else {
          amp = Math.abs(Math.sin(t * 0.0012 + phase) * 0.5 + 0.5) * 0.55;
        }
        const barHeight = Math.max(1.5, amp * ceiling);
        ctx.fillRect(x, centerY - barHeight, barWidth, barHeight * 2);
      }
    };

    const resize = () => {
      const rect = wrap.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      draw(reducedMotion ? 0 : performance.now());
    };
    resize();

    const ro = new ResizeObserver(resize);
    ro.observe(wrap);

    let raf = 0;
    if (!reducedMotion) {
      const loop = (t: number) => {
        draw(t);
        raf = window.requestAnimationFrame(loop);
      };
      raf = window.requestAnimationFrame(loop);
    }

    return () => {
      ro.disconnect();
      if (raf) window.cancelAnimationFrame(raf);
    };
  }, [reducedMotion]);

  return (
    <section
      id="hero"
      className="scroll-mt-[92px] relative min-h-[92vh] flex items-center pt-28 pb-20"
    >
      <div className="container-wh">
        <div className="grid items-center gap-16 lg:grid-cols-2 lg:gap-12">
          <Reveal>
            <div>
              <p className="eyebrow">macOS · speech-to-text</p>
              <h1 className="mt-4 text-5xl md:text-7xl font-semibold tracking-tight leading-[1.05]">
                <span className="text-gradient">Говори. Текст появляется сам.</span>
              </h1>
              <p className="mt-6 max-w-xl text-lg text-fg-dim">
                WhisperHot — локальное macOS-приложение для speech-to-text: живёт прямо на
                твоём Mac и не требует ничего лишнего для запуска. Нажми ⌥⌘5, говори — и
                транскрипт сам вставится в любое поле там, где стоит курсор.
              </p>

              <div className="mt-8 flex flex-wrap items-center gap-2">
                <kbd className="kbd">⌥</kbd>
                <span aria-hidden="true" className="text-fg-mute">
                  +
                </span>
                <kbd className="kbd">⌘</kbd>
                <span aria-hidden="true" className="text-fg-mute">
                  +
                </span>
                <kbd className="kbd">5</kbd>
                <span className="ml-2 text-sm text-fg-mute">старт/стоп</span>
              </div>

              <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
                <span className="text-fg-mute">или всего одной клавишей</span>
                <kbd className="kbd gap-1.5" aria-label="клавиша Fn">
                  <span aria-hidden="true">🌐</span> Fn
                </kbd>
                <span
                  className="rounded-full border border-line bg-surface px-2 py-0.5 text-[11px] font-medium text-accent"
                  title="macOS резервирует Fn под Dictation и Show Emoji — включается тумблером в настройках при выданном доступе Input Monitoring"
                >
                  экспериментально
                </span>
              </div>

              <div className="mt-8 flex flex-wrap items-center gap-3">
                <a href={RELEASES_URL} className="btn btn-primary">
                  Скачать для macOS
                </a>
                <a
                  href={REPO_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn btn-ghost"
                >
                  Смотреть на GitHub
                </a>
              </div>

              <p className="mt-5 text-xs text-fg-mute">
                macOS 13+ · Apple Silicon · рекомендуем Groq — бесплатно
              </p>
            </div>
          </Reveal>

          <Reveal delay={120}>
            <div className="relative">
              <div
                aria-hidden="true"
                className="pointer-events-none absolute -inset-10 -z-10 rounded-[48px] blur-2xl"
                style={{
                  background:
                    "radial-gradient(closest-side, color-mix(in oklab, var(--accent) 28%, transparent), transparent 70%)",
                }}
              />

              <div className="card overflow-hidden rounded-2xl shadow-[var(--shadow)]">
                <div className="flex items-center gap-2 border-b border-line px-5 py-4">
                  <span className="h-3 w-3 rounded-full" style={{ background: "#ff5f57" }} />
                  <span className="h-3 w-3 rounded-full" style={{ background: "#febc2e" }} />
                  <span className="h-3 w-3 rounded-full" style={{ background: "#28c840" }} />
                  <p className="ml-2 text-sm font-medium text-fg-dim">WhisperHot — Studio</p>
                </div>

                <div className="space-y-5 p-5 md:p-6">
                  <div
                    ref={wrapRef}
                    className="h-28 w-full overflow-hidden rounded-xl border border-line bg-bg-elev/60 md:h-32"
                  >
                    <canvas ref={canvasRef} className="block h-full w-full" aria-hidden="true" />
                  </div>

                  <div className="flex items-center justify-between">
                    <span className="font-mono text-3xl tabular-nums text-fg">
                      {formatClock(elapsedSec)}
                    </span>
                    <span
                      className={`inline-flex items-center gap-1.5 text-xs font-medium ${
                        isRecording ? "text-rec" : "text-fg-mute"
                      }`}
                    >
                      <span
                        className={`h-1.5 w-1.5 rounded-full ${
                          isRecording ? "bg-rec animate-blink" : "bg-fg-mute"
                        }`}
                        aria-hidden="true"
                      />
                      {isRecording ? "Идёт запись" : "Готово"}
                    </span>
                  </div>

                  <div className="min-h-[76px] rounded-xl border border-line bg-bg-elev/40 p-4 text-sm leading-relaxed text-fg">
                    {transcript ? (
                      <>
                        {transcript}
                        {isRecording && (
                          <span className="animate-blink" aria-hidden="true">
                            ▌
                          </span>
                        )}
                      </>
                    ) : (
                      <span className="text-fg-mute">Транскрипт появится здесь…</span>
                    )}
                  </div>

                  <div className="flex justify-center pt-1">
                    <button
                      type="button"
                      onClick={toggleRecording}
                      aria-label={isRecording ? "Остановить запись" : "Начать запись"}
                      className="relative grid h-16 w-16 place-items-center rounded-full bg-rec text-white shadow-lg transition-transform active:scale-95"
                    >
                      {isRecording && (
                        <>
                          <span
                            className="absolute inset-0 rounded-full bg-rec animate-pulse-ring"
                            aria-hidden="true"
                          />
                          <span
                            className="absolute inset-0 rounded-full bg-rec animate-pulse-ring"
                            style={{ animationDelay: "0.7s" }}
                            aria-hidden="true"
                          />
                        </>
                      )}
                      {isRecording ? <StopIcon /> : <MicIcon />}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
