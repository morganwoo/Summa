function Apple() {
  return <svg viewBox="0 0 24 24" className="h-5 w-5 fill-current"><path d="M16.37 12.6c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.82-.81-3-.79-1.54.02-2.96.9-3.76 2.28-1.6 2.78-.41 6.9 1.15 9.16.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.77.74 2.98.72 1.23-.02 2.01-1.12 2.76-2.23.87-1.28 1.23-2.52 1.25-2.58-.03-.01-2.4-.92-2.42-3.66zM14.1 5.84c.63-.77 1.06-1.83.94-2.89-.91.04-2.02.61-2.67 1.37-.58.67-1.1 1.76-.96 2.8 1.02.08 2.06-.52 2.69-1.28z"/></svg>;
}
function Play() {
  return <svg viewBox="0 0 24 24" className="h-5 w-5 fill-current"><path d="M3.6 2.2 13.3 12l-9.7 9.8c-.36-.2-.6-.6-.6-1.1V3.3c0-.5.24-.9.6-1.1zm10.8 10.9 2.5 2.5-11.6 6.6 9.1-9.1zm3.7-3.6 2.9 1.7c.8.5.8 1.6 0 2.1l-2.9 1.7-2.7-2.8 2.7-2.7zM5.3 1.8l11.6 6.6-2.5 2.5-9.1-9.1z"/></svg>;
}

export function StoreButtons({ compact = false }: { compact?: boolean }) {
  const base = "inline-flex items-center gap-2 rounded-full border border-foreground/30 transition-colors hover:border-gold hover:text-gold";
  const size = compact ? "px-4 py-2 text-xs" : "px-6 py-3 text-sm";
  return (
    <div className="flex flex-wrap items-center justify-center gap-3">
      <a href="https://apps.apple.com" target="_blank" rel="noreferrer" className={`${base} ${size}`}>
        <Apple /><span className="leading-tight">{!compact && <span className="block text-[10px] opacity-60">Download on the</span>}App Store</span>
      </a>
      <a href="https://play.google.com" target="_blank" rel="noreferrer" className={`${base} ${size}`}>
        <Play /><span className="leading-tight">{!compact && <span className="block text-[10px] opacity-60">Get it on</span>}Google Play</span>
      </a>
    </div>
  );
}
