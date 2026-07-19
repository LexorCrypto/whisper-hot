"use client";

import { create } from "zustand";
import { BUILD_VERSION } from "@/lib/version";

export type Theme = "dark" | "light";
export type ProviderId = "openai" | "openrouter" | "groq" | "polza" | "local";

const THEME_KEY = "wh-theme";

function applyTheme(theme: Theme) {
  if (typeof document === "undefined") return;
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem(THEME_KEY, theme);
  } catch {
    /* ignore private-mode storage errors */
  }
}

export interface AppState {
  /** Visual theme, mirrored onto <html data-theme>. */
  theme: Theme;
  setTheme: (theme: Theme) => void;
  toggleTheme: () => void;
  /** Sync store with the theme the inline boot script already applied. */
  initTheme: () => void;

  /** Drives the hero "recording" demo (waveform + live transcript). */
  isRecording: boolean;
  setRecording: (value: boolean) => void;
  toggleRecording: () => void;

  /** Selected transcription provider in the Providers explorer. */
  selectedProvider: ProviderId;
  setProvider: (provider: ProviderId) => void;

  /** Section id currently in view, used for nav scroll-spy. */
  activeSection: string;
  setActiveSection: (id: string) => void;

  /** Displayed app version; starts at build-time value, refreshed from the latest GitHub Release. */
  appVersion: string;
  setAppVersion: (v: string) => void;
}

export const useAppStore = create<AppState>((set, get) => ({
  theme: "dark",
  setTheme: (theme) => {
    applyTheme(theme);
    set({ theme });
  },
  toggleTheme: () => {
    const next: Theme = get().theme === "dark" ? "light" : "dark";
    applyTheme(next);
    set({ theme: next });
  },
  initTheme: () => {
    if (typeof document === "undefined") return;
    const current = (document.documentElement.dataset.theme as Theme) || "dark";
    set({ theme: current });
  },

  isRecording: false,
  setRecording: (value) => set({ isRecording: value }),
  toggleRecording: () => set((s) => ({ isRecording: !s.isRecording })),

  selectedProvider: "groq",
  setProvider: (provider) => set({ selectedProvider: provider }),

  activeSection: "hero",
  setActiveSection: (id) => set({ activeSection: id }),

  appVersion: BUILD_VERSION,
  setAppVersion: (v) => set({ appVersion: v }),
}));
