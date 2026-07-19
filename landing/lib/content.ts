import type { ProviderId } from "@/store/useAppStore";
import { BUILD_VERSION } from "@/lib/version";

export const REPO_URL = "https://github.com/LexorCrypto/whisper-hot";
export const RELEASES_URL = `${REPO_URL}/releases/latest`;
export const VERSION = BUILD_VERSION;

/* ---------- Navigation ---------- */
export interface NavLink {
  id: string;
  label: string;
}
export const NAV_LINKS: NavLink[] = [
  { id: "how", label: "Как это работает" },
  { id: "features", label: "Возможности" },
  { id: "platforms", label: "Платформы" },
  { id: "providers", label: "Провайдеры" },
  { id: "advantages", label: "Преимущества" },
];

/* ---------- How it works (a real ordered sequence) ---------- */
export interface Step {
  n: string;
  title: string;
  text: string;
}
export const STEPS: Step[] = [
  {
    n: "01",
    title: "Нажми \u2325\u23185",
    text: "Стартовый chime звучит, когда микрофон реально готов. Появляется плавающий индикатор — можно говорить сразу.",
  },
  {
    n: "02",
    title: "Говори",
    text: "Живая RMS-волна и таймер показывают, что тебя слышно. Одно приложение, ноль вкладок, ноль отвлечения.",
  },
  {
    n: "03",
    title: "Текст у курсора",
    text: "Транскрипт попадает в буфер и автоматически вставляется через Cmd+V туда, где стоит курсор. Слышишь done-chime.",
  },
];

/* ---------- Features ---------- */
export type FeatureIcon =
  | "hotkey"
  | "paste"
  | "llm"
  | "routing"
  | "offline"
  | "privacy"
  | "waveform"
  | "dictionary";

export interface Feature {
  icon: FeatureIcon;
  title: string;
  text: string;
}
export const FEATURES: Feature[] = [
  {
    icon: "hotkey",
    title: "Хоткей под себя",
    text: "\u2325\u23185 старт/стоп, \u2325\u2318\u21E75 — сырой текст без обработки. Хоткей переназначается — можно повесить запись даже на одну клавишу Fn (🌐, экспериментально: нужен доступ Input Monitoring).",
  },
  {
    icon: "paste",
    title: "Авто-вставка",
    text: "Текст сам оказывается у курсора в любом приложении — Slack, Notes, терминал, IDE. Никогда не теряется: он всегда и в буфере.",
  },
  {
    icon: "llm",
    title: "LLM-обработка",
    text: "Опциональная чистка филлеров, пунктуация и стили: email, Slack, техдок, перевод на английский. 4 LLM-провайдера.",
  },
  {
    icon: "routing",
    title: "Контекстный роутинг",
    text: "Стиль обработки выбирается по активному приложению: Slack — казуально, Mail — формально, VS Code — техдокументация.",
  },
  {
    icon: "offline",
    title: "Офлайн-режим",
    text: "whisper.cpp ставится одной кнопкой и работает локально — без сети и без ключей. Авто-переключение при медленном соединении.",
  },
  {
    icon: "privacy",
    title: "Приватность по умолчанию",
    text: "Ключи живут в Keychain, история шифруется AES-GCM и по умолчанию выключена, аудио удаляется сразу после транскрибации.",
  },
  {
    icon: "waveform",
    title: "5 стилей индикатора",
    text: "От незаметного menubar-only до широкой Studio-панели с плотной RMS-волной в духе SuperWhisper.",
  },
  {
    icon: "dictionary",
    title: "Технический словарь",
    text: "Подсказки распознавания (commit, deploy, push) и автозамены после транскрипции: коммит → commit, деплой → deploy.",
  },
];

/* ---------- Platforms ---------- */
export interface Platform {
  key: "macos" | "windows" | "intel";
  name: string;
  status: "shipped" | "planned" | "unsupported";
  badge: string;
  detail: string;
}
export const PLATFORMS: Platform[] = [
  {
    key: "macos",
    name: "macOS",
    status: "shipped",
    badge: "Доступно сейчас",
    detail: "macOS 13.0 Ventura и новее на Apple Silicon (M1 и новее). Dock-иконка, главное окно и быстрый контроллер в menu bar.",
  },
  {
    key: "windows",
    name: "Windows",
    status: "planned",
    badge: "В дорожной карте",
    detail: "Порт принят как продуктовая цель — отдельная работа, а не флаг сборки: текущий код завязан на AppKit, AVAudioEngine и Keychain.",
  },
  {
    key: "intel",
    name: "Intel Mac",
    status: "unsupported",
    badge: "Не поддерживается",
    detail: "Поддержка Intel не входила в цели MVP. Нужен процессор Apple Silicon.",
  },
];

/* ---------- Providers ---------- */
export interface Provider {
  id: ProviderId;
  name: string;
  model: string;
  api: string;
  offline: boolean;
  free: boolean;
  recommended: boolean;
  /** Illustrative relative transcription speed, 0..100. */
  speed: number;
  note: string;
}
export const PROVIDERS: Provider[] = [
  {
    id: "groq",
    name: "Groq",
    model: "whisper-large-v3-turbo",
    api: "/openai/v1/audio/transcriptions",
    offline: false,
    free: true,
    recommended: true,
    speed: 100,
    note: "Бесплатный тариф, ~10\u00D7 быстрее и заметно дешевле. Наш выбор по умолчанию.",
  },
  {
    id: "local",
    name: "Local whisper.cpp",
    model: "любой GGML-файл",
    api: "Локальный subprocess",
    offline: true,
    free: true,
    recommended: false,
    speed: 62,
    note: "Полностью офлайн, ключ не нужен. Скорость зависит от модели и твоего Mac.",
  },
  {
    id: "openrouter",
    name: "OpenRouter",
    model: "openai/gpt-4o-audio-preview",
    api: "/v1/chat/completions (input_audio)",
    offline: false,
    free: false,
    recommended: false,
    speed: 48,
    note: "Один ключ — множество audio-моделей в чат-формате.",
  },
  {
    id: "polza",
    name: "Polza.ai",
    model: "gpt-4o-mini-transcribe",
    api: "/v1/audio/transcriptions",
    offline: false,
    free: false,
    recommended: false,
    speed: 44,
    note: "OpenAI-совместимый российский агрегатор. Оплата российскими картами.",
  },
  {
    id: "openai",
    name: "OpenAI",
    model: "gpt-4o-mini-transcribe",
    api: "/v1/audio/transcriptions",
    offline: false,
    free: false,
    recommended: false,
    speed: 42,
    note: "Максимальная точность и самый дорогой вариант.",
  },
];

export const GROQ_PITCH = {
  title: "Рекомендуем Groq",
  tagline: "Бесплатно и отлично работает",
  body: "Из всех провайдеров начни с Groq: у него есть бесплатный тариф, whisper-large-v3-turbo примерно в 10 раз быстрее и заметно дешевле остальных облачных вариантов. Вставляешь ключ, выбираешь Groq в настройках — и WhisperHot готов к работе.",
  points: [
    "Бесплатный тариф — можно начать без затрат",
    "whisper-large-v3-turbo — молниеносная транскрибация",
    "Заметно дешевле OpenAI при отличном качестве",
  ],
};

/* ---------- Advantages ---------- */
export interface Advantage {
  metric: string;
  label: string;
  text: string;
}
export const ADVANTAGES: Advantage[] = [
  {
    metric: "~10\u00D7",
    label: "Скорость",
    text: "Groq turbo быстрее облачных аналогов, а при медленной сети WhisperHot сам догоняет локальной транскрипцией.",
  },
  {
    metric: "0",
    label: "Отвлечения",
    text: "Окно прячется, фокус возвращается в предыдущее приложение, текст приходит сам. Ты не переключаешь контекст.",
  },
  {
    metric: "100%",
    label: "Приватность",
    text: "Локальный офлайн-режим, шифрование истории AES-GCM и ключи только в Keychain — твоё остаётся твоим.",
  },
  {
    metric: "5 + 4",
    label: "Гибкость",
    text: "Пять STT-провайдеров и четыре LLM для пост-обработки, пресеты, словарь и кастомный хоткей.",
  },
];
