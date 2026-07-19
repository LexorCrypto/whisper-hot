import type { Metadata, Viewport } from "next";
import "./globals.css";
import ThemeSync from "@/components/ThemeSync";

export const metadata: Metadata = {
  title: "WhisperHot — голос в текст под курсором для macOS",
  description:
    "Локальное macOS-приложение для speech-to-text. Нажми \u2325\u23185, говори — транскрипт сам появляется у курсора. Мульти-провайдер, офлайн whisper.cpp, LLM-обработка. Рекомендуем Groq — бесплатно и отлично работает.",
  keywords: [
    "WhisperHot",
    "speech to text",
    "macOS",
    "транскрибация",
    "Groq",
    "whisper.cpp",
    "диктовка",
  ],
  authors: [{ name: "LexorCrypto" }],
  openGraph: {
    title: "WhisperHot — голос в текст под курсором для macOS",
    description:
      "Нажми \u2325\u23185, говори — текст сам появляется у курсора. Рекомендуем Groq: бесплатно и отлично работает.",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#09090c",
  width: "device-width",
  initialScale: 1,
};

const themeBoot = `(function(){try{var t=localStorage.getItem('wh-theme');if(t!=='light'&&t!=='dark'){t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';}document.documentElement.dataset.theme=t;}catch(e){document.documentElement.dataset.theme='dark';}})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ru" data-theme="dark" suppressHydrationWarning>
      <body className="min-h-screen antialiased">
        <script dangerouslySetInnerHTML={{ __html: themeBoot }} />
        <ThemeSync />
        {children}
      </body>
    </html>
  );
}
