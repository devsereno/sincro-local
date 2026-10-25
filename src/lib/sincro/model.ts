export const GB = 1024 ** 3;
export const MB = 1024 ** 2;
export const FAT32_LIMIT = 4 * GB;

export type Mode = "hybrid" | "sd" | "internal";
export type Job = "copy" | "sync";
export type Dest = "sd" | "internal";
export type Category = "Fotos" | "Vídeos" | "Documentos" | "Downloads";

export type LibraryFile = {
  id: string;
  name: string;
  category: Category;
  bytes: number;
};

export type Disk = {
  name: string;
  internalFree: number;
  sdFree: number;
  fat32: boolean;
};

export type Reason = "ok" | "fat32" | "full";

export type Placement = {
  file: LibraryFile;
  dest: Dest | null;
  reason: Reason;
};

export type SessionFile = {
  name: string;
  bytes: number;
  dest: Dest;
};

export type Session = {
  id: string;
  job: Job;
  mode: Mode;
  writer: string;
  at: number;
  files: SessionFile[];
  sourceDeleted: boolean;
};

export const MODE_LABEL: Record<Mode, string> = {
  hybrid: "Híbrido",
  sd: "Só SD",
  internal: "Só interna",
};

export const MODE_HINT: Record<Mode, string> = {
  hybrid: "Enche o cartão até a reserva. O que não cabe vai para a interna.",
  sd: "Tudo no cartão. Se encher, pausa. Não cai na interna.",
  internal: "Tudo na interna, respeitando a reserva. O cartão não entra.",
};

export const CATEGORIES: Category[] = ["Fotos", "Vídeos", "Documentos", "Downloads"];

const gb = (n: number) => Math.round(n * GB);
const mb = (n: number) => Math.round(n * MB);

export const LIBRARY: LibraryFile[] = [
  { id: "f1", name: "IMG_20261012_0912.jpg", category: "Fotos", bytes: mb(4.2) },
  { id: "f2", name: "IMG_20261018_1430.jpg", category: "Fotos", bytes: mb(3.6) },
  { id: "f3", name: "WhatsApp Image 2026-10-20.jpg", category: "Fotos", bytes: mb(1.8) },
  { id: "f4", name: "IMG_familia_001.jpg", category: "Fotos", bytes: mb(5.1) },
  { id: "v1", name: "VID_praia.mp4", category: "Vídeos", bytes: gb(2.4) },
  { id: "v2", name: "VID_aniversario.mp4", category: "Vídeos", bytes: gb(1.7) },
  { id: "v3", name: "VID_viagem_4k.mp4", category: "Vídeos", bytes: gb(4.6) },
  { id: "d1", name: "contrato-aluguel.pdf", category: "Documentos", bytes: mb(0.84) },
  { id: "d2", name: "extrato-outubro.pdf", category: "Documentos", bytes: 240 * 1024 },
  { id: "w1", name: "backup-conversas.zip", category: "Downloads", bytes: mb(640) },
  { id: "w2", name: "aula-01.apk", category: "Downloads", bytes: mb(48) },
];

export const DEFAULT_SELECTION = ["v1", "v2", "w1"];

export const DEVICE_A: Disk = {
  name: "Este aparelho",
  internalFree: gb(18),
  sdFree: gb(4),
  fat32: true,
};

export const DEVICE_B: Disk = {
  name: "Aparelho B",
  internalFree: gb(12),
  sdFree: gb(1.2),
  fat32: false,
};

export const PAIR_CODE = "K7M";
export const PAIR_OPTIONS = ["Q2P", "K7M", "8HN"];

export function diskFor(job: Job): Disk {
  return job === "copy" ? DEVICE_A : DEVICE_B;
}

export function formatBytes(bytes: number): string {
  const num = (n: number, digits: number) => n.toFixed(digits).replace(".", ",");
  if (bytes >= GB) {
    const value = bytes / GB;
    return `${num(value, value >= 10 ? 0 : 1)} GB`;
  }
  if (bytes >= MB) return `${num(bytes / MB, bytes >= 10 * MB ? 0 : 1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

export function formatEta(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 1) return "menos de 1 s";
  const total = Math.ceil(seconds);
  const m = Math.floor(total / 60);
  const s = total % 60;
  if (m <= 0) return `${s} s`;
  if (m < 60) return s ? `${m} min ${s} s` : `${m} min`;
  const h = Math.floor(m / 60);
  return `${h} h ${m % 60} min`;
}

export function placeFiles(
  files: LibraryFile[],
  mode: Mode,
  disk: Disk,
  internalBufferGb: number,
  sdBufferMb: number,
): Placement[] {
  let sdRoom = Math.max(0, disk.sdFree - sdBufferMb * MB);
  let internalRoom = Math.max(0, disk.internalFree - internalBufferGb * GB);

  return files.map((file) => {
    const fits = (dest: Dest) => {
      if (dest === "sd" && disk.fat32 && file.bytes > FAT32_LIMIT) return false;
      const room = dest === "sd" ? sdRoom : internalRoom;
      return file.bytes <= room;
    };
    const consume = (dest: Dest) => {
      if (dest === "sd") sdRoom -= file.bytes;
      else internalRoom -= file.bytes;
    };
    const order: Dest[] =
      mode === "sd" ? ["sd"] : mode === "internal" ? ["internal"] : ["sd", "internal"];

    for (const dest of order) {
      if (!fits(dest)) continue;
      consume(dest);
      return { file, dest, reason: "ok" };
    }

    if (disk.fat32 && file.bytes > FAT32_LIMIT && mode === "sd") {
      return { file, dest: null, reason: "fat32" };
    }
    return { file, dest: null, reason: "full" };
  });
}

export function placementLabel(item: Placement): string {
  if (item.dest === "sd") return "Cartão SD";
  if (item.dest === "internal") return "Interna";
  if (item.reason === "fat32") return "FAT32 recusa";
  return "Não cabe";
}
