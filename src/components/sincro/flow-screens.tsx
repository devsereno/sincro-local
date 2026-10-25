import { useEffect, useMemo, useRef, useState } from "react";
import {
  BatteryLow,
  Check,
  Clapperboard,
  Download,
  FileText,
  Image as ImageIcon,
} from "lucide-react";
import type { Category, Job } from "@/lib/sincro/model";
import {
  CATEGORIES,
  LIBRARY,
  MB,
  MODE_HINT,
  MODE_LABEL,
  PAIR_CODE,
  PAIR_OPTIONS,
  diskFor,
  formatBytes,
  formatEta,
  placeFiles,
  placementLabel,
} from "@/lib/sincro/model";
import { useSincro } from "@/lib/sincro/store";
import { BackHeader, ModeSwitch } from "@/components/sincro/chrome";

const ICONS = {
  Fotos: ImageIcon,
  Vídeos: Clapperboard,
  Documentos: FileText,
  Downloads: Download,
} as const;

function BatteryNote() {
  return (
    <p className="flex gap-2 rounded-2xl bg-forest/10 px-4 py-3 text-sm leading-snug text-ink">
      <BatteryLow className="mt-0.5 size-4 shrink-0 text-forest" aria-hidden="true" />
      <span>Bateria em 18%. Para uma cópia longa, ligue ao carregador.</span>
    </p>
  );
}

export function PairScreen() {
  const store = useSincro();
  const [error, setError] = useState(false);

  return (
    <section className="min-h-dvh bg-cream pb-8">
      <BackHeader title="Aparelho B" onBack={() => store.setView({ id: "home" })} />
      <div className="space-y-4 px-5 pt-3">
        <p className="text-sm leading-relaxed text-ink/75">
          Moto G84 na mesma Wi-Fi. Quem grava é ele. O modo deste aparelho não entra.
        </p>
        <ModeSwitch value={store.modeB} onChange={store.setModeB} />
        <p className="text-sm leading-relaxed text-ink/70">{MODE_HINT[store.modeB]}</p>

        <div className="rounded-3xl bg-forest px-4 py-4 text-paper">
          <p className="text-xs font-bold tracking-wide text-paper/70">NO OUTRO APARELHO</p>
          <p className="mt-2 text-3xl font-extrabold tracking-widest">{PAIR_CODE}</p>
        </div>

        <p className="text-sm font-semibold">Toque no mesmo código.</p>
        <div className="grid grid-cols-3 gap-2">
          {PAIR_OPTIONS.map((code) => (
            <button
              key={code}
              type="button"
              onClick={() => {
                if (code !== PAIR_CODE) {
                  setError(true);
                  return;
                }
                store.setView({ id: "pick", job: "sync", ids: ["v1", "v2", "w1"] });
              }}
              className="min-h-14 rounded-2xl bg-paper text-lg font-extrabold tracking-widest shadow-sm"
            >
              {code}
            </button>
          ))}
        </div>
        {error ? (
          <p className="text-sm font-semibold text-forest" role="alert">
            Os códigos não batem. A ligação não abre.
          </p>
        ) : null}
      </div>
    </section>
  );
}

export function PickScreen({ job, ids }: { job: Job; ids: string[] }) {
  const store = useSincro();
  const [selected, setSelected] = useState<string[]>(ids);
  const [category, setCategory] = useState<Category | "Tudo">("Tudo");
  const selectedSet = useMemo(() => new Set(selected), [selected]);
  const visible = LIBRARY.filter((file) => category === "Tudo" || file.category === category);
  const bytes = LIBRARY.filter((file) => selectedSet.has(file.id)).reduce((sum, file) => sum + file.bytes, 0);
  const back = () =>
    store.setView(job === "copy" ? { id: "home" } : { id: "pair" });

  return (
    <section className="min-h-dvh bg-cream pb-28">
      <BackHeader
        title={job === "copy" ? "Copiar para o SD" : "Enviar ao aparelho B"}
        onBack={back}
      />
      <p className="px-5 pt-2 text-sm text-ink/70">Toque para marcar. O destino aparece no passo seguinte.</p>
      <div className="flex gap-2 overflow-x-auto px-5 pt-4">
        {(["Tudo", ...CATEGORIES] as const).map((item) => {
          const active = category === item;
          return (
            <button
              key={item}
              type="button"
              onClick={() => setCategory(item)}
              className={
                active
                  ? "shrink-0 rounded-full bg-mint px-4 py-2 text-sm font-bold"
                  : "shrink-0 rounded-full bg-paper px-4 py-2 text-sm font-semibold text-ink/70"
              }
            >
              {item}
            </button>
          );
        })}
      </div>
      <ul className="px-3 pt-3">
        {visible.map((file) => {
          const Icon = ICONS[file.category];
          const on = selectedSet.has(file.id);
          return (
            <li key={file.id}>
              <button
                type="button"
                onClick={() =>
                  setSelected((current) =>
                    current.includes(file.id)
                      ? current.filter((id) => id !== file.id)
                      : [...current, file.id],
                  )
                }
                className="flex w-full items-center gap-3 rounded-2xl px-2 py-2 text-left"
              >
                <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-paper">
                  <Icon className="size-5 text-forest" aria-hidden="true" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-semibold">{file.name}</span>
                  <span className="block text-xs text-ink/60">
                    {file.category} · {formatBytes(file.bytes)}
                  </span>
                </span>
                <span
                  className={
                    on
                      ? "grid size-6 place-items-center rounded-md bg-forest text-paper"
                      : "size-6 rounded-md border border-line"
                  }
                  aria-hidden="true"
                >
                  {on ? <Check className="size-4" strokeWidth={3} /> : null}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
      <div className="fixed inset-x-0 bottom-0 z-10">
        <div className="mx-auto flex w-full max-w-md items-center gap-3 bg-cream/95 px-5 py-4 backdrop-blur">
          <p className="min-w-0 flex-1 text-sm font-semibold">
            {selected.length} arquivos
            <span className="block font-medium text-ink/60">{formatBytes(bytes)}</span>
          </p>
          <button
            type="button"
            disabled={selected.length === 0}
            onClick={() => store.setView({ id: "plan", job, ids: selected })}
            className="min-h-12 rounded-full bg-forest px-5 font-bold text-paper disabled:opacity-40"
          >
            Ver destino
          </button>
        </div>
      </div>
    </section>
  );
}

export function PlanScreen({ job, ids }: { job: Job; ids: string[] }) {
  const store = useSincro();
  const disk = diskFor(job);
  const mode = store.modeFor(job);
  const files = LIBRARY.filter((file) => ids.includes(file.id));
  const plan = placeFiles(files, mode, disk, store.internalBufferGb, store.sdBufferMb);
  const placed = plan.filter((item) => item.dest);
  const sdBytes = plan.filter((item) => item.dest === "sd").reduce((sum, item) => sum + item.file.bytes, 0);
  const internalBytes = plan
    .filter((item) => item.dest === "internal")
    .reduce((sum, item) => sum + item.file.bytes, 0);
  const blocked = plan.length - placed.length;

  return (
    <section className="min-h-dvh bg-cream pb-28">
      <BackHeader
        title="Destino previsto"
        onBack={() => store.setView({ id: "pick", job, ids })}
      />
      <div className="space-y-4 px-5 pt-3">
        <p className="text-sm leading-relaxed">
          Quem grava: <span className="font-bold">{disk.name}</span> · {MODE_LABEL[mode]}
          {disk.fat32 ? " · cartão FAT32" : " · cartão exFAT"}
        </p>
        <BatteryNote />
        <ul className="divide-y divide-line overflow-hidden rounded-3xl bg-paper">
          {plan.map((item) => (
            <li key={item.file.id} className="flex items-center gap-3 px-4 py-3">
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold">{item.file.name}</span>
                <span className="text-xs text-ink/60">{formatBytes(item.file.bytes)}</span>
              </span>
              <span className={item.dest ? "text-sm font-bold text-forest" : "text-sm font-bold"}>
                {placementLabel(item)}
              </span>
            </li>
          ))}
        </ul>
        <p className="text-sm leading-relaxed text-ink/75">
          SD {formatBytes(sdBytes)} · interna {formatBytes(internalBytes)}
          {blocked ? ` · ${blocked} de fora` : ""}. Um arquivo não se parte.
        </p>
        {blocked ? (
          <p className="text-sm leading-relaxed">
            O que não cabe fica parado. Nada é empurrado para o outro disco se o modo não permite.
          </p>
        ) : null}
      </div>
      <div className="fixed inset-x-0 bottom-0 z-10">
        <div className="mx-auto w-full max-w-md bg-cream/95 px-5 py-4 backdrop-blur">
          <button
            type="button"
            disabled={placed.length === 0}
            onClick={() => store.setView({ id: "run", job, ids })}
            className="min-h-12 w-full rounded-full bg-forest font-bold text-paper disabled:opacity-40"
          >
            {job === "copy" ? "Iniciar cópia" : "Iniciar sincronização"}
          </button>
        </div>
      </div>
    </section>
  );
}

export function RunScreen({ job, ids }: { job: Job; ids: string[] }) {
  const store = useSincro();
  const disk = diskFor(job);
  const mode = store.modeFor(job);
  const plan = useMemo(() => {
    const files = LIBRARY.filter((file) => ids.includes(file.id));
    return placeFiles(files, mode, disk, store.internalBufferGb, store.sdBufferMb).filter(
      (item) => item.dest,
    );
  }, [disk, ids, mode, store.internalBufferGb, store.sdBufferMb]);
  const total = plan.reduce((sum, item) => sum + item.file.bytes, 0);
  const [status, setStatus] = useState<"running" | "paused" | "done">("running");
  const [moved, setMoved] = useState(0);
  const [speed, setSpeed] = useState(36 * MB);
  const [askDelete, setAskDelete] = useState(false);
  const saved = useRef(false);
  const sessionId = useRef(`s-${Date.now()}`);

  useEffect(() => {
    if (status !== "running") return;
    let raf = 0;
    let last = performance.now();
    let cursor = moved;
    const tick = (now: number) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const nextSpeed = (36 + Math.sin(now / 420) * 8) * MB;
      cursor = Math.min(total, cursor + nextSpeed * dt * 24);
      setSpeed(nextSpeed);
      setMoved(cursor);
      if (cursor >= total) {
        setStatus("done");
        return;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // Resume should continue from the latest byte count captured when status flips.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, total]);

  useEffect(() => {
    if (status !== "done" || saved.current) return;
    saved.current = true;
    store.addSession({
      id: sessionId.current,
      job,
      mode,
      writer: disk.name,
      at: Date.now(),
      files: plan.map((item) => ({
        name: item.file.name,
        bytes: item.file.bytes,
        dest: item.dest!,
      })),
      sourceDeleted: false,
    });
  }, [disk.name, job, mode, plan, status, store]);

  const current = plan.find((_, index) => {
    const before = plan.slice(0, index).reduce((sum, item) => sum + item.file.bytes, 0);
    return moved < before + plan[index].file.bytes || index === plan.length - 1;
  });
  const ratio = total === 0 ? 1 : moved / total;
  const remaining = Math.max(0, total - moved);
  const session = store.history.find((item) => item.id === sessionId.current);
  const deleted = session?.sourceDeleted ?? false;

  return (
    <section className="min-h-dvh bg-cream pb-10">
      <BackHeader
        title={status === "done" ? "Verificado" : job === "copy" ? "Copiando" : "Sincronizando"}
        onBack={() => store.setView({ id: "home" })}
      />
      <div className="space-y-4 px-5 pt-4">
        <p className="text-5xl font-extrabold tracking-tight">{Math.round(ratio * 100)}%</p>
        <p className="truncate text-sm font-semibold">{current?.file.name ?? "Concluído"}</p>
        <div className="h-2 overflow-hidden rounded-full bg-line">
          <div className="h-2 rounded-full bg-forest" style={{ width: `${ratio * 100}%` }} />
        </div>
        <div className="flex items-end justify-between text-sm">
          <p>
            <span className="text-2xl font-extrabold">{(speed / MB).toFixed(0)}</span> MB/s
          </p>
          <p className="text-ink/70">
            {status === "done" ? "checado" : formatEta(remaining / Math.max(speed * 24, 1))}
          </p>
        </div>
        <p className="text-xs font-semibold tracking-wide text-ink/50">TERMÔMETRO</p>
        <div className="h-1.5 overflow-hidden rounded-full bg-line">
          <div
            className="h-1.5 rounded-full bg-mint"
            style={{ width: `${Math.min(100, (speed / (60 * MB)) * 100)}%` }}
          />
        </div>
        {status !== "done" ? <BatteryNote /> : null}
        {status !== "done" ? (
          <p className="text-sm text-ink/70">A cópia segue mesmo com a tela apagada.</p>
        ) : (
          <p className="text-sm leading-relaxed">
            Tamanho e checksum conferem. Os originais continuam neste aparelho até você apagar.
          </p>
        )}
        {status === "done" ? (
          <ul className="divide-y divide-line rounded-3xl bg-paper">
            {plan.map((item) => (
              <li key={item.file.id} className="flex justify-between gap-3 px-4 py-3 text-sm">
                <span className="truncate">{item.file.name}</span>
                <span className="shrink-0 font-bold text-forest">{placementLabel(item)}</span>
              </li>
            ))}
          </ul>
        ) : null}
        {status !== "done" ? (
          <button
            type="button"
            onClick={() => setStatus((value) => (value === "paused" ? "running" : "paused"))}
            className="min-h-12 w-full rounded-full bg-paper font-bold"
          >
            {status === "paused" ? "Continuar" : "Pausar"}
          </button>
        ) : (
          <button
            type="button"
            disabled={deleted}
            onClick={() => setAskDelete(true)}
            className="min-h-12 w-full rounded-full bg-ink font-bold text-paper disabled:opacity-40"
          >
            {deleted ? "Originais apagados" : "Apagar originais"}
          </button>
        )}
      </div>
      {askDelete ? (
        <div className="fixed inset-0 z-20 grid place-items-end bg-forest-deep/50">
          <div className="mx-auto w-full max-w-md rounded-t-3xl bg-cream p-5">
            <h2 className="text-lg font-extrabold">Apagar de vez?</h2>
            <p className="mt-2 text-sm leading-relaxed text-ink/75">
              Não vai para a lixeira. O espaço só volta depois desta confirmação. Não dá para desfazer.
            </p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setAskDelete(false)}
                className="min-h-12 rounded-full bg-paper font-bold"
              >
                Manter
              </button>
              <button
                type="button"
                onClick={() => {
                  store.markDeleted(sessionId.current);
                  setAskDelete(false);
                }}
                className="min-h-12 rounded-full bg-forest font-bold text-paper"
              >
                Apagar
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
}
