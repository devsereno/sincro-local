import { useCallback, useEffect, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AboutScreen } from "@/components/sincro/about-screen";
import { Frame } from "@/components/sincro/chrome";
import { PairScreen, PickScreen, PlanScreen, RunScreen } from "@/components/sincro/flow-screens";
import { HomeScreen } from "@/components/sincro/home-screen";
import { HistoryScreen, SettingsScreen } from "@/components/sincro/meta-screens";
import { SplashScreen } from "@/components/sincro/splash-screen";
import { SincroProvider, useSincro } from "@/lib/sincro/store";

export const Route = createFileRoute("/")({ component: Home });

function Home() {
  return (
    <SincroProvider>
      <Gate />
    </SincroProvider>
  );
}

function Gate() {
  const store = useSincro();
  const [phase, setPhase] = useState<"splash" | "app">("splash");
  const [about, setAbout] = useState(false);
  const [progress, setProgress] = useState(0);
  const [finished, setFinished] = useState(false);

  useEffect(() => {
    if (phase !== "splash" || finished) return;
    let raf = 0;
    const start = performance.now();
    const duration = 3800;
    const tick = (now: number) => {
      const next = Math.min(1, (now - start) / duration);
      setProgress(next);
      if (next < 1) raf = requestAnimationFrame(tick);
      else setFinished(true);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [finished, phase]);

  useEffect(() => {
    if (finished && !about && phase === "splash") setPhase("app");
  }, [about, finished, phase]);

  const replay = useCallback(() => {
    store.setView({ id: "home" });
    setProgress(0);
    setFinished(false);
    setAbout(false);
    setPhase("splash");
  }, [store]);

  return (
    <Frame>
      {phase === "splash" ? (
        <>
          <SplashScreen progress={progress} onAbout={() => setAbout(true)} />
          {about ? <AboutOverlay onBack={() => setAbout(false)} /> : null}
        </>
      ) : (
        <App replay={replay} />
      )}
    </Frame>
  );
}

function AboutOverlay({ onBack }: { onBack: () => void }) {
  return (
    <div className="absolute inset-0 z-20 overflow-y-auto bg-cream">
      <AboutScreen onBack={onBack} />
    </div>
  );
}

function App({ replay }: { replay: () => void }) {
  const store = useSincro();
  const view = store.view;

  if (view.id === "about") return <AboutScreen onBack={() => store.setView({ id: "settings" })} />;
  if (view.id === "settings") return <SettingsScreen onSplash={replay} />;
  if (view.id === "history") return <HistoryScreen />;
  if (view.id === "pair") return <PairScreen />;
  if (view.id === "pick") return <PickScreen job={view.job} ids={view.ids} />;
  if (view.id === "plan") return <PlanScreen job={view.job} ids={view.ids} />;
  if (view.id === "run") return <RunScreen job={view.job} ids={view.ids} />;
  return <HomeScreen />;
}
