import { ArrowLeftRight, History, Settings, Smartphone } from "lucide-react";
import { DEVICE_A, DEVICE_B, MODE_HINT, MODE_LABEL, formatBytes } from "@/lib/sincro/model";
import { useSincro } from "@/lib/sincro/store";
import { Logo, ModeSwitch } from "@/components/sincro/chrome";

export function HomeScreen() {
  const store = useSincro();
  const internalRoom = Math.max(0, DEVICE_A.internalFree - store.internalBufferGb * 1024 ** 3);
  const sdRoom = Math.max(0, DEVICE_A.sdFree - store.sdBufferMb * 1024 ** 2);

  return (
    <section className="min-h-dvh bg-cream pb-10">
      <header className="flex items-center justify-between px-5 pt-6">
        <div className="flex items-center gap-3">
          <Logo className="size-11" />
          <h1 className="text-2xl font-extrabold tracking-tight">SincroLocal</h1>
        </div>
        <div className="flex">
          <button
            type="button"
            aria-label="Histórico"
            onClick={() => store.setView({ id: "history" })}
            className="grid size-11 place-items-center rounded-full"
          >
            <History className="size-5" />
          </button>
          <button
            type="button"
            aria-label="Ajustes"
            onClick={() => store.setView({ id: "settings" })}
            className="grid size-11 place-items-center rounded-full"
          >
            <Settings className="size-5" />
          </button>
        </div>
      </header>

      <div className="px-5 pt-6">
        <p className="mb-2 text-xs font-bold tracking-wide text-ink/60">MODO DESTE APARELHO</p>
        <ModeSwitch value={store.modeA} onChange={store.setModeA} />
        <p className="mt-3 text-sm leading-relaxed text-ink/75">{MODE_HINT[store.modeA]}</p>
      </div>

      <dl className="mx-5 mt-4 grid grid-cols-2 gap-2">
        <div className="rounded-2xl bg-paper px-3 py-3">
          <dt className="text-xs font-semibold text-ink/60">Interna útil</dt>
          <dd className="mt-1 text-lg font-extrabold">{formatBytes(internalRoom)}</dd>
          <dd className="text-xs text-ink/60">reserva {store.internalBufferGb} GB</dd>
        </div>
        <div className="rounded-2xl bg-paper px-3 py-3">
          <dt className="text-xs font-semibold text-ink/60">SD útil</dt>
          <dd className="mt-1 text-lg font-extrabold">{formatBytes(sdRoom)}</dd>
          <dd className="text-xs text-ink/60">reserva {store.sdBufferMb} MB · FAT32</dd>
        </div>
      </dl>

      <div className="space-y-3 px-5 pt-5">
        <button
          type="button"
          onClick={() => store.setView({ id: "pick", job: "copy", ids: ["v1", "v2", "w1"] })}
          className="flex w-full items-start gap-3 rounded-3xl bg-forest px-4 py-4 text-left text-paper"
        >
          <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-paper/15">
            <Smartphone className="size-5" />
          </span>
          <span>
            <span className="block text-base font-extrabold">Copiar para o SD</span>
            <span className="mt-1 block text-sm leading-snug text-paper/85">
              Da interna para o cartão deste aparelho. Grava no modo {MODE_LABEL[store.modeA].toLowerCase()}.
            </span>
          </span>
        </button>

        <button
          type="button"
          onClick={() => store.setView({ id: "pair" })}
          className="flex w-full items-start gap-3 rounded-3xl bg-paper px-4 py-4 text-left shadow-sm"
        >
          <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-mint text-ink">
            <ArrowLeftRight className="size-5" />
          </span>
          <span>
            <span className="block text-base font-extrabold">Sincronizar com o aparelho B</span>
            <span className="mt-1 block text-sm leading-snug text-ink/70">
              Este aparelho envia. O {DEVICE_B.name} grava no modo {MODE_LABEL[store.modeB].toLowerCase()}.
            </span>
          </span>
        </button>
      </div>

      <p className="px-5 pt-5 text-sm leading-relaxed text-ink/65">
        Livre agora: interna {formatBytes(DEVICE_A.internalFree)}, SD {formatBytes(DEVICE_A.sdFree)}. A reserva é medida de novo antes de cada arquivo.
      </p>
    </section>
  );
}
