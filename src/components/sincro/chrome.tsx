import type { ReactNode } from "react";
import { ChevronLeft, Repeat } from "lucide-react";

export function Frame({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-dvh bg-forest-deep">
      <div className="relative mx-auto min-h-dvh w-full max-w-md overflow-x-hidden bg-cream text-ink">
        {children}
      </div>
    </div>
  );
}

export function Logo({ className = "size-12" }: { className?: string }) {
  return (
    <span
      className={`grid shrink-0 place-items-center rounded-xl bg-forest text-paper ${className}`}
      aria-hidden="true"
    >
      <Repeat className="size-6" strokeWidth={2.5} />
    </span>
  );
}

export function BackHeader({
  title,
  onBack,
  aside,
}: {
  title: string;
  onBack: () => void;
  aside?: ReactNode;
}) {
  return (
    <header className="flex items-center gap-2 px-3 pt-4">
      <button
        type="button"
        onClick={onBack}
        className="grid size-11 place-items-center rounded-full text-ink"
        aria-label="Voltar"
      >
        <ChevronLeft className="size-6" />
      </button>
      <h1 className="min-w-0 flex-1 truncate text-lg font-bold">{title}</h1>
      {aside}
    </header>
  );
}

export function ModeSwitch({
  value,
  onChange,
}: {
  value: "hybrid" | "sd" | "internal";
  onChange: (mode: "hybrid" | "sd" | "internal") => void;
}) {
  const options = [
    ["hybrid", "Híbrido"],
    ["sd", "Só SD"],
    ["internal", "Só interna"],
  ] as const;

  return (
    <div className="grid grid-cols-3 gap-1 rounded-full bg-line p-1">
      {options.map(([id, label]) => {
        const active = value === id;
        return (
          <button
            key={id}
            type="button"
            onClick={() => onChange(id)}
            className={
              active
                ? "min-h-11 rounded-full bg-mint text-sm font-bold text-ink"
                : "min-h-11 rounded-full text-sm font-semibold text-ink/70"
            }
          >
            {label}
          </button>
        );
      })}
    </div>
  );
}
