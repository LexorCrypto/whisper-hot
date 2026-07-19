"use client";

import { useEffect } from "react";
import { useAppStore } from "@/store/useAppStore";

/**
 * Syncs the Zustand theme with the value the inline boot script applied
 * to <html data-theme> before hydration, avoiding a mismatch/flash.
 */
export default function ThemeSync() {
  const initTheme = useAppStore((s) => s.initTheme);
  useEffect(() => {
    initTheme();
  }, [initTheme]);
  return null;
}
