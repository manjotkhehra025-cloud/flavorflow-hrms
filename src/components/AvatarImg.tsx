import { initials } from "@/lib/utils";

/** Photo-aware avatar: shows employee photo when available, initials otherwise. */
export function AvatarImg({
  name,
  photoUrl,
  size = "h-9 w-9",
  textSize = "text-xs",
}: {
  name: string;
  photoUrl?: string | null;
  size?: string;
  textSize?: string;
}) {
  const cls = `${size} rounded-full`;
  if (photoUrl) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={photoUrl} alt={name} className={`${cls} object-cover ring-2 ring-emerald-400/40`} />;
  }
  return (
    <div className={`${cls} flex items-center justify-center bg-[#0a1628] font-bold text-emerald-400 ${textSize}`}>
      {initials(name)}
    </div>
  );
}
