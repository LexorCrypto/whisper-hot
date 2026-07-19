"use client";

import { useEffect } from "react";
import { useAppStore } from "@/store/useAppStore";
import { BUILD_VERSION } from "@/lib/version";

const LATEST_RELEASE_URL =
  "https://api.github.com/repos/LexorCrypto/whisper-hot/releases/latest";

/**
 * Refreshes the displayed version from the latest GitHub Release once on
 * mount, falling back to the build-time BUILD_VERSION on any failure so the
 * initial render (and hydration) never depends on the network.
 */
export default function VersionSync() {
  useEffect(() => {
    let cancelled = false;

    async function syncVersion() {
      try {
        const res = await fetch(LATEST_RELEASE_URL, {
          headers: { Accept: "application/vnd.github+json" },
        });
        if (!res.ok) return;

        const json = await res.json();
        const version = String(json.tag_name ?? "").replace(/^v/, "").trim();

        if (!cancelled && version) {
          useAppStore.getState().setAppVersion(version);
        }
      } catch {
        if (!cancelled) {
          useAppStore.getState().setAppVersion(BUILD_VERSION);
        }
      }
    }

    syncVersion();
    return () => {
      cancelled = true;
    };
  }, []);

  return null;
}
