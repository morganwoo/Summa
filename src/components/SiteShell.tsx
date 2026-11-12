import { Link } from "@tanstack/react-router";
import { useState, type ReactNode } from "react";
import { StoreButtons } from "./StoreButtons";

const links = [
  { to: "/", label: "Home" },
  { to: "/about", label: "About" },
  { to: "/reviews", label: "Reviews" },
] as const;

export function SiteShell({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="min-h-screen bg-background text-foreground">
      <header className="fixed inset-x-0 top-0 z-50 flex items-center justify-between px-6 py-5 md:px-10">
        <nav className="hidden gap-8 md:flex">
          {links.map((l) => (
            <Link key={l.to} to={l.to} activeOptions={{ exact: true }} activeProps={{ className: "text-gold" }} className="eyebrow transition-colors hover:text-foreground">
              {l.label}
            </Link>
          ))}
        </nav>
        <Link to="/" className="title-roman absolute left-1/2 -translate-x-1/2 rounded-full border border-foreground/40 px-6 py-1 text-sm tracking-[0.5em]">
          Stoa 90
        </Link>
        <div className="hidden md:block"><StoreButtons compact /></div>
        <button aria-label="Menu" onClick={() => setOpen(!open)} className="ml-auto flex flex-col gap-1.5 md:hidden">
          <span className="h-px w-7 bg-foreground" /><span className="h-px w-7 bg-foreground" /><span className="h-px w-7 bg-foreground" />
        </button>
      </header>
      {open && (
        <div className="fixed inset-0 z-40 flex flex-col items-center justify-center gap-8 bg-background">
          {links.map((l) => (
            <Link key={l.to} to={l.to} onClick={() => setOpen(false)} className="title-roman text-2xl">{l.label}</Link>
          ))}
          <StoreButtons />
        </div>
      )}
      <main>{children}</main>
      <footer className="flex flex-col items-center justify-between gap-4 border-t px-6 py-8 text-xs text-muted-foreground md:flex-row md:px-10">
        <span>© 2026 Stoa 90 — Memento mori. Memento vivere.</span>
        <StoreButtons compact />
      </footer>
    </div>
  );
}
