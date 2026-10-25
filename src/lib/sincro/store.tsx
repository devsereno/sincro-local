import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import type { Job, Mode, Session } from "@/lib/sincro/model";

const KEY = "sincro-local-v1";

export type View =
  | { id: "home" }
  | { id: "about" }
  | { id: "settings" }
  | { id: "history" }
  | { id: "pair" }
  | { id: "pick"; job: Job; ids: string[] }
  | { id: "plan"; job: Job; ids: string[] }
  | { id: "run"; job: Job; ids: string[] };

type Settings = {
  modeA: Mode;
  modeB: Mode;
  internalBufferGb: number;
  sdBufferMb: number;
  history: Session[];
};

type Store = Settings & {
  view: View;
  setView: (view: View) => void;
  setModeA: (mode: Mode) => void;
  setModeB: (mode: Mode) => void;
  setInternalBuffer: (gb: number) => void;
  setSdBuffer: (mb: number) => void;
  addSession: (session: Session) => void;
  markDeleted: (id: string) => void;
  modeFor: (job: Job) => Mode;
};

const DEFAULTS: Settings = {
  modeA: "hybrid",
  modeB: "hybrid",
  internalBufferGb: 5,
  sdBufferMb: 500,
  history: [],
};

const SincroContext = createContext<Store | null>(null);

function isMode(value: unknown): value is Mode {
  return value === "hybrid" || value === "sd" || value === "internal";
}

function loadSettings(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return DEFAULTS;
    const parsed = JSON.parse(raw) as Partial<Settings>;
    return {
      modeA: isMode(parsed.modeA) ? parsed.modeA : DEFAULTS.modeA,
      modeB: isMode(parsed.modeB) ? parsed.modeB : DEFAULTS.modeB,
      internalBufferGb:
        typeof parsed.internalBufferGb === "number" ? parsed.internalBufferGb : DEFAULTS.internalBufferGb,
      sdBufferMb: typeof parsed.sdBufferMb === "number" ? parsed.sdBufferMb : DEFAULTS.sdBufferMb,
      history: Array.isArray(parsed.history) ? parsed.history : [],
    };
  } catch {
    return DEFAULTS;
  }
}

export function SincroProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<Settings>(DEFAULTS);
  const [view, setView] = useState<View>({ id: "home" });
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setSettings(loadSettings());
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem(KEY, JSON.stringify(settings));
  }, [settings, ready]);

  const store = useMemo<Store>(() => {
    return {
      ...settings,
      view,
      setView,
      setModeA: (modeA) => setSettings((current) => ({ ...current, modeA })),
      setModeB: (modeB) => setSettings((current) => ({ ...current, modeB })),
      setInternalBuffer: (internalBufferGb) =>
        setSettings((current) => ({ ...current, internalBufferGb })),
      setSdBuffer: (sdBufferMb) => setSettings((current) => ({ ...current, sdBufferMb })),
      addSession: (session) =>
        setSettings((current) => ({ ...current, history: [session, ...current.history] })),
      markDeleted: (id) =>
        setSettings((current) => ({
          ...current,
          history: current.history.map((item) =>
            item.id === id ? { ...item, sourceDeleted: true } : item,
          ),
        })),
      modeFor: (job) => (job === "copy" ? settings.modeA : settings.modeB),
    };
  }, [settings, view]);

  return <SincroContext.Provider value={store}>{children}</SincroContext.Provider>;
}

export function useSincro(): Store {
  const store = useContext(SincroContext);
  if (!store) throw new Error("Sincro ausente");
  return store;
}
