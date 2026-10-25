import { Logo } from "@/components/sincro/chrome";

const SHEETS = [0, 45, 90, 135, 180, 225, 270, 315];

export function SplashScreen({
  progress,
  onAbout,
}: {
  progress: number;
  onAbout: () => void;
}) {
  const percent = Math.round(progress * 100);

  return (
    <section className="relative flex min-h-dvh flex-col text-paper" aria-busy={progress < 1}>
      <img
        src="/media/splash.jpg"
        alt=""
        className="absolute inset-0 h-full w-full object-cover"
      />
      <div className="absolute inset-0 bg-forest-deep/45" />
      <div className="absolute inset-0 bg-gradient-to-b from-forest-deep/80 via-forest-deep/15 to-forest-deep/85" />

      <div className="relative z-10 flex flex-1 flex-col items-center px-6 pt-14 pb-8">
        <div className="flex items-center gap-3">
          <h1 className="text-3xl font-extrabold tracking-tight">SincroLocal</h1>
          <Logo />
        </div>

        <p className="mt-4 text-center text-sm font-bold">Desenvolvedor: RICARDO WORKS</p>
        <p className="mt-1 text-center text-sm">Sistemas parrudos para problemas reais.</p>

        <div className="flex flex-1 items-center justify-center py-8">
          <div className="sincro-spin relative size-44" aria-hidden="true">
            {SHEETS.map((deg) => (
              <span
                key={deg}
                className="absolute left-1/2 top-1/2 h-14 w-10 rounded-md bg-paper shadow-md"
                style={{
                  transform: `translate(-50%, -50%) rotate(${deg}deg) translateY(-52px) rotate(${deg % 90 === 0 ? -14 : 10}deg)`,
                }}
              />
            ))}
          </div>
        </div>

        <p className="text-sm font-medium">Carregando...</p>
        <div
          className="mt-3 h-px w-full max-w-xs bg-paper/35"
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-label="Carregando"
        >
          <div className="h-px bg-paper" style={{ width: `${percent}%` }} />
        </div>

        <button
          type="button"
          onClick={onAbout}
          className="mt-8 w-full max-w-sm rounded-full bg-mint px-6 py-3 text-center text-base font-extrabold leading-tight text-ink"
        >
          Saber Mais & Portfólio Ricardo
          <br />
          Works
        </button>
        <p className="mt-4 text-center text-xs font-medium">
          Inovação para um futuro digital e verde.
        </p>
      </div>
    </section>
  );
}
