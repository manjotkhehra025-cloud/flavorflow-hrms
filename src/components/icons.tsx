export type IconName =
  | "home"
  | "users"
  | "clock"
  | "leaf"
  | "calendar"
  | "report"
  | "plus"
  | "check"
  | "x"
  | "logout"
  | "building"
  | "menu"
  | "shield"
  | "briefcase"
  | "fingerprint"
  | "badge"
  | "sliders"
  | "dots"
  | "printer"
  | "gate"
  | "bell"
  | "download"
  | "chart"
  | "link"
  | "chevron-down"
  | "target"
  | "chat"
  | "star"
  | "doc"
  | "wallet";

export function Icon({ name, className = "h-5 w-5" }: { name: IconName; className?: string }) {
  const paths: Record<IconName, React.ReactNode> = {
    home: (
      <>
        <path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
        <polyline points="9 22 9 12 15 12 15 22" />
      </>
    ),
    users: (
      <>
        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
        <circle cx="9" cy="7" r="4" />
        <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
      </>
    ),
    clock: (
      <>
        <circle cx="12" cy="12" r="10" />
        <polyline points="12 6 12 12 16 14" />
      </>
    ),
    leaf: (
      <>
        <path d="M6.5 21 21 6.5c-6.2-.8-12 .5-14.5 3S4.7 16 6.5 21z" />
        <path d="M4.5 19.5c4.5-4.5 9-6.5 12.5-8" />
      </>
    ),
    calendar: (
      <>
        <rect x="3" y="4" width="18" height="18" rx="2" />
        <line x1="16" y1="2" x2="16" y2="6" />
        <line x1="8" y1="2" x2="8" y2="6" />
        <line x1="3" y1="10" x2="21" y2="10" />
      </>
    ),
    report: (
      <>
        <path d="M3 3v18h18" />
        <path d="M7 14l4-4 3 3 5-6" />
      </>
    ),
    chart: (
      <>
        <line x1="5" y1="20" x2="5" y2="12" />
        <line x1="11" y1="20" x2="11" y2="6" />
        <line x1="17" y1="20" x2="17" y2="10" />
        <line x1="3" y1="20" x2="21" y2="20" />
      </>
    ),
    link: (
      <>
        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
      </>
    ),
    "chevron-down": (
      <>
        <polyline points="6 9 12 15 18 9" />
      </>
    ),
    target: (
      <>
        <circle cx="12" cy="12" r="10" />
        <circle cx="12" cy="12" r="6" />
        <circle cx="12" cy="12" r="2" />
      </>
    ),
    chat: (
      <>
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
        <circle cx="9" cy="10" r="0.5" fill="currentColor" />
        <circle cx="12" cy="10" r="0.5" fill="currentColor" />
        <circle cx="15" cy="10" r="0.5" fill="currentColor" />
      </>
    ),
    wallet: (
      <>
        <path d="M6 3h12a3 3 0 0 1 3 3v11a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Z" />
        <path d="M21 9h-5a3 3 0 0 0 0 6h5" />
        <circle cx="16" cy="12" r="1" fill="currentColor" stroke="none" />
      </>
    ),
    star: (
      <>
        <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
      </>
    ),
    doc: (
      <>
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
        <polyline points="14 2 14 8 20 8" />
        <line x1="16" y1="13" x2="8" y2="13" />
        <line x1="16" y1="17" x2="8" y2="17" />
      </>
    ),
    plus: (
      <>
        <line x1="12" y1="5" x2="12" y2="19" />
        <line x1="5" y1="12" x2="19" y2="12" />
      </>
    ),
    check: <polyline points="20 6 9 17 4 12" />,
    x: (
      <>
        <line x1="18" y1="6" x2="6" y2="18" />
        <line x1="6" y1="6" x2="18" y2="18" />
      </>
    ),
    logout: (
      <>
        <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
        <polyline points="16 17 21 12 16 7" />
        <line x1="21" y1="12" x2="9" y2="12" />
      </>
    ),
    building: (
      <>
        <rect x="4" y="2" width="16" height="20" rx="2" />
        <line x1="9" y1="22" x2="9" y2="18" />
        <line x1="15" y1="22" x2="15" y2="18" />
        <line x1="9" y1="6" x2="10" y2="6" />
        <line x1="14" y1="6" x2="15" y2="6" />
        <line x1="9" y1="10" x2="10" y2="10" />
        <line x1="14" y1="10" x2="15" y2="10" />
        <line x1="9" y1="14" x2="10" y2="14" />
        <line x1="14" y1="14" x2="15" y2="14" />
      </>
    ),
    menu: (
      <>
        <line x1="3" y1="6" x2="21" y2="6" />
        <line x1="3" y1="12" x2="21" y2="12" />
        <line x1="3" y1="18" x2="21" y2="18" />
      </>
    ),
    shield: (
      <>
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
        <polyline points="9 12 11 14 15 10" />
      </>
    ),
    briefcase: (
      <>
        <rect x="2" y="7" width="20" height="14" rx="2" />
        <path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16" />
      </>
    ),
    fingerprint: (
      <>
        <path d="M12 11c0 3.5-1 7-2.5 9.5" />
        <path d="M15.5 12.5c-.3 3-1 5.5-2 8" />
        <path d="M8.5 12.5c-.4 2-.9 3.6-1.5 5" />
        <path d="M7 7.5A6 6 0 0 1 18 11v1c0 2-.1 3.5-.3 5" />
        <path d="M5 13c.2-1 .3-2 .3-3a6.7 6.7 0 0 1 .7-3" />
        <path d="M2.8 5A9.6 9.6 0 0 1 11.6 2c4.1 0 7.6 2.6 9 6.3" />
      </>
    ),
    badge: (
      <>
        <rect x="5" y="2" width="14" height="20" rx="2" />
        <circle cx="12" cy="9" r="2.5" />
        <path d="M8.5 16c.8-2 6.2-2 7 0" />
      </>
    ),
    sliders: (
      <>
        <line x1="4" y1="21" x2="4" y2="14" />
        <line x1="4" y1="10" x2="4" y2="3" />
        <line x1="12" y1="21" x2="12" y2="12" />
        <line x1="12" y1="8" x2="12" y2="3" />
        <line x1="20" y1="21" x2="20" y2="16" />
        <line x1="20" y1="12" x2="20" y2="3" />
        <line x1="1" y1="14" x2="7" y2="14" />
        <line x1="9" y1="8" x2="15" y2="8" />
        <line x1="17" y1="16" x2="23" y2="16" />
      </>
    ),
    dots: (
      <>
        <circle cx="5" cy="12" r="1.8" fill="currentColor" stroke="none" />
        <circle cx="12" cy="12" r="1.8" fill="currentColor" stroke="none" />
        <circle cx="19" cy="12" r="1.8" fill="currentColor" stroke="none" />
      </>
    ),
    printer: (
      <>
        <polyline points="6 9 6 2 18 2 18 9" />
        <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2" />
        <rect x="6" y="14" width="12" height="8" />
      </>
    ),
    gate: (
      <>
        <path d="M14 3v18" />
        <path d="M14 5l7 2.5v9L14 19" />
        <path d="M3 8l8-4" />
        <path d="M3 16l8 4" />
      </>
    ),
    download: (
      <>
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
        <polyline points="7 10 12 15 17 10" />
        <line x1="12" y1="15" x2="12" y2="3" />
      </>
    ),
    bell: (
      <>
        <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" />
        <path d="M13.7 21a2 2 0 0 1-3.4 0" />
      </>
    ),
  };

  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {paths[name]}
    </svg>
  );
}
