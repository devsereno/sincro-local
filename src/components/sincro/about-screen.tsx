import { BackHeader } from "@/components/sincro/chrome";

export function AboutScreen({ onBack }: { onBack: () => void }) {
  return (
    <section className="min-h-dvh bg-cream text-ink">
      <BackHeader title="Ricardo Works" onBack={onBack} />
      <div className="space-y-4 px-5 pt-4 pb-10">
        <p className="text-sm font-bold tracking-wide text-forest">SINCROLOCAL</p>
        <h2 className="text-2xl font-extrabold leading-tight">
          Sistemas parrudos para problemas reais.
        </h2>
        <p className="text-base leading-relaxed">
          O SincroLocal não usa nuvem. Ele faz duas coisas, e nas duas quem grava escolhe o destino.
        </p>
        <article className="rounded-3xl bg-paper p-4 shadow-sm">
          <h3 className="font-bold">1. Copiar para o SD deste aparelho</h3>
          <p className="mt-1 text-sm leading-relaxed text-ink/75">
            Sai da memória interna e entra no cartão daqui. O modo deste aparelho decide o transbordo.
          </p>
        </article>
        <article className="rounded-3xl bg-paper p-4 shadow-sm">
          <h3 className="font-bold">2. Sincronizar com o aparelho B</h3>
          <p className="mt-1 text-sm leading-relaxed text-ink/75">
            Este aparelho envia. O B grava no modo dele: híbrido, só SD ou só interna. O modo daqui não manda no disco de lá.
          </p>
        </article>
        <p className="text-sm leading-relaxed text-ink/75">
          A interna guarda uma reserva para o sistema não travar. O cartão fica com uma folga menor. Um arquivo nunca se parte entre os dois.
        </p>
        <p className="text-sm font-semibold">Inovação para um futuro digital e verde.</p>
      </div>
    </section>
  );
}
