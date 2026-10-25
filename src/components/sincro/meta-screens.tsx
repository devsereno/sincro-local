import { useState } from "react";
import { DEVICE_A, GB, MB, MODE_LABEL, formatBytes } from "@/lib/sincro/model";
import { useSincro } from "@/lib/sincro/store";
import { BackHeader, ModeSwitch } from "@/components/sincro/chrome";

const INTERNAL = [3, 5, 8];
const SD = [300, 500, 1000];

export function SettingsScreen({ onSplash }: { onSplash: () => void }) {
  const store = useSincro();

  return (
    <section className="min-h-dvh bg-cream pb-10">
      <BackHeader title="Ajustes" onBack={() => store.setView({ id: "home" })} />
      <div className="space-y-6 px-5 pt-4">
        <div>
          <p className="mb-2 text-xs font-bold tracking-wide text-ink/60">MODO DESTE APARELHO</p>
          <ModeSwitch value={store.modeA} onChange={store.setModeA} />
          <p className="mt-3 text-sm leading-relaxed text-ink/70">
            Vale na cópia para o SD daqui. Na sincronização, o aparelho B escolhe o modo dele na hora.
          </p>
        </div>
        <div>
          <p className="mb-2 text-xs font-bold tracking-wide text-ink/60">RESERVA DA INTERNA</p>
          <div className="grid grid-cols-3 gap-2">
            {INTERNAL.map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => store.setInternalBuffer(value)}
                className={
                  store.internalBufferGb === value
                    ? "min-h-12 rounded-2xl bg-mint font-bold"
                    : "min-h-12 rounded-2xl bg-paper font-semibold"
                }
              >
                {value} GB
              </button>
            ))}
          </div>
          <p className="mt-2 text-sm text-ink/65">
            Útil agora: {formatBytes(Math.max(0, DEVICE_A.internalFree - store.internalBufferGb * GB))}
          </p>
        </div>
        <div>
          <p className="mb-2 text-xs font-bold tracking-wide text-ink/60">RESERVA DO CARTÃO</p>
          <div className="grid grid-cols-3 gap-2">
            {SD.map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => store.setSdBuffer(value)}
                className={
                  store.sdBufferMb === value
                    ? "min-h-12 rounded-2xl bg-mint font-bold"
                    : "min-h-12 rounded-2xl bg-paper font-semibold"
                }
              >
                {value} MB
              </button>
            ))}
          </div>
          <p className="mt-2 text-sm text-ink/65">
            Útil agora: {formatBytes(Math.max(0, DEVICE_A.sdFree - store.sdBufferMb * MB))}. Cartão deste aparelho em FAT32, limite de 4 GB por arquivo.
          </p>
        </div>
        <button
          type="button"
          onClick={() => store.setView({ id: "about" })}
          className="min-h-12 w-full rounded-full bg-paper text-sm font-bold"
        >
          Saber mais & portfólio Ricardo Works
        </button>
        <button
          type="button"
          onClick={onSplash}
          className="min-h-12 w-full rounded-full bg-forest text-sm font-bold text-paper"
        >
          Ver tela de início
        </button>
      </div>
    </section>
  );
}

export function HistoryScreen() {
  const store = useSincro();
  const [pending, setPending] = useState<string | null>(null);

  return (
    <section className="min-h-dvh bg-cream pb-8">
      <BackHeader title="Histórico" onBack={() => store.setView({ id: "home" })} />
      {store.history.length === 0 ? (
        <p className="px-5 pt-6 text-sm leading-relaxed text-ink/70">
          Nenhuma cópia ainda. Quando uma terminar verificada, ela fica aqui para você apagar os originais no seu ritmo.
        </p>
      ) : (
        <ul className="space-y-3 px-5 pt-4">
          {store.history.map((session) => (
            <li key={session.id} className="rounded-3xl bg-paper p-4">
              <p className="text-sm font-extrabold">
                {session.job === "copy" ? "Cópia neste aparelho" : "Sincronização"} · {MODE_LABEL[session.mode]}
              </p>
              <p className="mt-1 text-xs text-ink/60">
                {session.writer} · {session.files.length} arquivos ·{" "}
                {new Date(session.at).toLocaleString("pt-BR", {
                  day: "2-digit",
                  month: "2-digit",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </p>
              <ul className="mt-2 space-y-1">
                {session.files.map((file) => (
                  <li key={file.name} className="flex justify-between gap-3 text-sm">
                    <span className="truncate">{file.name}</span>
                    <span className="shrink-0 text-ink/60">
                      {file.dest === "sd" ? "SD" : "Interna"}
                    </span>
                  </li>
                ))}
              </ul>
              <button
                type="button"
                disabled={session.sourceDeleted}
                onClick={() => setPending(session.id)}
                className="mt-3 min-h-11 w-full rounded-full bg-cream text-sm font-bold disabled:opacity-50"
              >
                {session.sourceDeleted ? "Originais apagados" : "Apagar originais"}
              </button>
            </li>
          ))}
        </ul>
      )}
      {pending ? (
        <div className="fixed inset-0 z-20 grid place-items-end bg-forest-deep/50">
          <div className="mx-auto w-full max-w-md rounded-t-3xl bg-cream p-5">
            <h2 className="text-lg font-extrabold">Apagar de vez?</h2>
            <p className="mt-2 text-sm leading-relaxed text-ink/75">
              A exclusão passa direto, sem lixeira. Confirme só se a cópia já foi verificada — e ela foi.
            </p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setPending(null)}
                className="min-h-12 rounded-full bg-paper font-bold"
              >
                Manter
              </button>
              <button
                type="button"
                onClick={() => {
                  store.markDeleted(pending);
                  setPending(null);
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
