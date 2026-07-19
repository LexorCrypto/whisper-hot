"use client";

import { useEffect, useId, useState } from "react";
import { useAppStore } from "@/store/useAppStore";
import { NAV_LINKS, RELEASES_URL, VERSION } from "@/lib/content";

/** Five vertical waveform bars, gradient accent → violet. */
function LogoMark() {
  const gradId = useId();
  const bars: Array<{ x: number; h: number }> = [
    { x: 2, h: 10 },
    { x: 7, h: 16 },
    { x: 12, h: 22 },
    { x: 17, h: 16 },
    { x: 22, h: 10 },
  ];
  return (
    <svg width="24" height="24" viewBox="0 0 28 28" fill="none" aria-hidden="true" className="shrink-0">
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="1" y2="0.4">
          <stop offset="0%" stopColor="var(--accent)" />
          <stop offset="100%" stopColor="var(--violet)" />
        </linearGradient>
      </defs>
      {bars.map((bar) => (
        <rect
          key={bar.x}
          x={bar.x}
          y={(28 - bar.h) / 2}
          width="3"
          height={bar.h}
          rx="1.5"
          fill={`url(#${gradId})`}
        />
      ))}
    </svg>
  );
}

function SunIcon() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="4.5" stroke="currentColor" strokeWidth="1.8" />
      <path
        d="M12 2.5v2.4M12 19.1v2.4M21.5 12h-2.4M4.9 12H2.5M18.4 5.6l-1.7 1.7M7.3 16.7l-1.7 1.7M18.4 18.4l-1.7-1.7M7.3 7.3 5.6 5.6"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M20.2 14.5A8.7 8.7 0 1 1 9.5 3.8a7 7 0 0 0 10.7 10.7Z"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function MenuIcon({ open }: { open: boolean }) {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <line
        x1="3.5"
        y1={open ? "6" : "6.5"}
        x2={open ? "20.5" : "20.5"}
        y2={open ? "20.5" : "6.5"}
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        style={{ transformOrigin: "12px 12px", transition: "all 0.2s ease" }}
        transform={open ? "rotate(45 12 12)" : undefined}
      />
      <line
        x1="3.5"
        y1="12"
        x2="20.5"
        y2="12"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        style={{ transition: "opacity 0.15s ease" }}
        opacity={open ? 0 : 1}
      />
      <line
        x1="3.5"
        y1={open ? "20.5" : "17.5"}
        x2={open ? "20.5" : "20.5"}
        y2={open ? "6" : "17.5"}
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        style={{ transformOrigin: "12px 12px", transition: "all 0.2s ease" }}
        transform={open ? "rotate(-45 12 12)" : undefined}
      />
    </svg>
  );
}

export default function SiteNav() {
  const theme = useAppStore((s) => s.theme);
  const toggleTheme = useAppStore((s) => s.toggleTheme);
  const activeSection = useAppStore((s) => s.activeSection);
  const setActiveSection = useAppStore((s) => s.setActiveSection);
  const [menuOpen, setMenuOpen] = useState(false);

  // Scroll-spy: highlight the nav link for the section currently crossing
  // a thin band near the vertical center of the viewport.
  useEffect(() => {
    const sections = NAV_LINKS.map((link) => document.getElementById(link.id)).filter(
      (el): el is HTMLElement => el !== null,
    );
    if (sections.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActiveSection(entry.target.id);
          }
        }
      },
      { rootMargin: "-45% 0px -50% 0px", threshold: 0 },
    );
    for (const section of sections) observer.observe(section);
    return () => observer.disconnect();
  }, [setActiveSection]);

  // Lock body scroll while the mobile menu is open.
  useEffect(() => {
    if (!menuOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [menuOpen]);

  const closeMenu = () => setMenuOpen(false);

  return (
    <header className="sticky top-0 z-50 glass border-b border-line">
      <div className="container-wh flex h-16 items-center justify-between gap-2 sm:gap-4">
        <a href="#" className="flex shrink-0 items-center gap-2.5" aria-label="WhisperHot — наверх">
          <LogoMark />
          <span className="text-[15px] font-semibold tracking-tight text-fg">WhisperHot</span>
          <span className="hidden font-mono text-[11px] text-fg-mute sm:inline">v{VERSION}</span>
        </a>

        <nav className="hidden items-center gap-1 lg:flex" aria-label="Секции страницы">
          {NAV_LINKS.map((link) => {
            const active = activeSection === link.id;
            return (
              <a
                key={link.id}
                href={`#${link.id}`}
                aria-current={active ? "true" : undefined}
                className={`rounded-lg px-3 py-2 text-[13px] font-medium transition-colors ${
                  active ? "text-fg" : "text-fg-dim hover:text-fg"
                }`}
              >
                {link.label}
              </a>
            );
          })}
        </nav>

        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            onClick={toggleTheme}
            aria-label={theme === "dark" ? "Включить светлую тему" : "Включить тёмную тему"}
            className="flex h-9 w-9 items-center justify-center rounded-lg border border-line text-fg-dim transition-colors hover:border-line-strong hover:text-fg"
          >
            {theme === "dark" ? <SunIcon /> : <MoonIcon />}
          </button>

          <a
            href={RELEASES_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-primary h-9 rounded-lg px-4 text-[13px]"
          >
            Скачать
          </a>

          <button
            type="button"
            onClick={() => setMenuOpen((v) => !v)}
            aria-label={menuOpen ? "Закрыть меню" : "Открыть меню"}
            aria-expanded={menuOpen}
            className="flex h-9 w-9 items-center justify-center rounded-lg border border-line text-fg-dim transition-colors hover:border-line-strong hover:text-fg lg:hidden"
          >
            <MenuIcon open={menuOpen} />
          </button>
        </div>
      </div>

      {menuOpen && (
        <div className="glass border-t border-line lg:hidden">
          <nav className="container-wh flex flex-col py-2" aria-label="Мобильная навигация">
            {NAV_LINKS.map((link) => {
              const active = activeSection === link.id;
              return (
                <a
                  key={link.id}
                  href={`#${link.id}`}
                  onClick={closeMenu}
                  aria-current={active ? "true" : undefined}
                  className={`rounded-lg px-3 py-3 text-[15px] font-medium transition-colors ${
                    active ? "text-fg" : "text-fg-dim hover:text-fg"
                  }`}
                >
                  {link.label}
                </a>
              );
            })}
          </nav>
        </div>
      )}
    </header>
  );
}
