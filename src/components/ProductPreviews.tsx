import type { ReactNode } from "react";
import { BookOpen, Check, Dumbbell, Feather, Sun, Signal, Wifi, BatteryFull, Camera, CalendarDays, Settings, Folder, Compass, MessageCircle, Phone as PhoneIcon, Search } from "lucide-react";
import wallpaper from "@/assets/widget-wallpaper.jpg";
import heatmaps from "@/assets/summa-heatmaps.jpg.asset.json";
import welcome from "@/assets/summa-welcome.jpg.asset.json";
import plan from "@/assets/summa-plan.jpg.asset.json";
import colosseum from "@/assets/summa-colosseum.jpg.asset.json";
import { Reveal } from "./Reveal";

function Phone({ children, className = "", label, screenshot }: { children?: ReactNode; className?: string; label: string; screenshot?: string }) {
  return <div className={`product-phone ${className}`} role="img" aria-label={label}><span className="phone-side-key phone-side-key-volume" aria-hidden="true" /><span className="phone-side-key phone-side-key-power" aria-hidden="true" /><div className="phone-screen">{screenshot ? <img src={screenshot} alt="" className="phone-screenshot" /> : <><div className="phone-status"><span>9:41</span><span className="flex items-center gap-1"><Signal size={10} /><Wifi size={10} /><BatteryFull size={13} /></span></div><div className="phone-island" />{children}<div className="phone-home" /></>}</div></div>;
}

function MiniGrid({ tone = "gold", count = 90, offset = 0 }: { tone?: "gold" | "sage"; count?: number; offset?: number }) {
  return <div className={`mini-grid mini-grid-${tone}`} aria-hidden="true">{Array.from({ length: count }, (_, i) => <span key={i} className={(i * 7 + offset) % 11 < 8 ? ((i + offset) % 3 === 0 ? "partial" : "kept") : ""} />)}</div>;
}

export function ThreePhones() {
  return <div className="phone-trio"><Phone className="phone-left" label="Summa Colosseum victory journal" screenshot={colosseum.url} /><Phone className="phone-center" label="Summa habit tracker with three ninety-day heatmaps" screenshot={heatmaps.url} /><Phone className="phone-right" label="Summa ninety-day plan and milestones" screenshot={plan.url} /></div>;
}

export function OnboardingSection() {
  return <section className="onboarding-section border-y border-border"><div className="mx-auto grid max-w-6xl items-center gap-16 px-6 py-24 md:grid-cols-2 md:py-32"><Reveal><p className="eyebrow mb-6">Personalized from the first conversation</p><h2 className="feature-title">Bring your story.<br />We’ll shape the plan.</h2><p className="mt-6 max-w-md font-serif text-xl text-muted-foreground">Your goals. Your routine. The habits you want to leave behind. Talk to our AI and receive a tailored 90-day plan, ready in moments.</p><div className="mt-8 flex items-center gap-3 text-sm text-gold"><Feather size={17} /><span>A conversation. Not a questionnaire.</span></div></Reveal><Reveal className="onboarding-visual"><Phone label="Summa welcome and personalized onboarding" screenshot={welcome.url} /><div className="plan-notification"><div className="notification-icon"><Check size={18} /></div><div><p className="text-sm font-medium">Your 90-day plan is ready.</p><p className="mt-1 text-xs text-muted-foreground">Built around your life. Not the other way around.</p></div></div></Reveal></div></section>;
}

function HomeApp({ kind, label, dock = false }: { kind: "calendar" | "camera" | "settings" | "files" | "safari" | "messages" | "phone"; label: string; dock?: boolean }) {
  const icons = { calendar: CalendarDays, camera: Camera, settings: Settings, files: Folder, safari: Compass, messages: MessageCircle, phone: PhoneIcon };
  const Icon = icons[kind];
  return <div className={`home-app ${dock ? "home-app-docked" : ""}`}><span className={`home-app-icon app-${kind}`}>{kind === "calendar" ? <><small>THU</small><strong>12</strong></> : <Icon size={25} strokeWidth={kind === "settings" ? 2 : 1.6} />}</span>{!dock && <span className="home-app-label">{label}</span>}</div>;
}

export function WidgetsSection() {
  return <section className="widgets-section px-6 py-24 md:py-32"><div className="mx-auto grid max-w-6xl items-center gap-16 md:grid-cols-2">
    <Reveal><p className="eyebrow mb-6">Home-screen widgets</p><h2 className="feature-title">Your habits.<br />On your home screen.</h2><p className="mt-6 max-w-md font-serif text-xl text-muted-foreground">Your daily practice, at a glance. Without opening the app.</p></Reveal>
    <Reveal className="widget-composition"><Phone className="widget-phone" label="Phone home screen with Summa reading, training, and weekly widgets">
      <img src={wallpaper} alt="" loading="lazy" width={768} height={1536} className="widget-wallpaper" />
      <div className="widget-home-screen">
        <div className="widget-home-top"><div><div className="widget-small widget-preview"><div className="widget-heading"><BookOpen size={15} className="text-sage" /><span>Read daily</span></div><MiniGrid tone="sage" count={60} /></div><p className="widget-app-label">Summa</p></div><div className="home-app-grid"><HomeApp kind="calendar" label="Calendar" /><HomeApp kind="camera" label="Camera" /><HomeApp kind="settings" label="Settings" /><HomeApp kind="files" label="Files" /></div></div>
        <div className="widget-wide widget-preview"><div className="widget-heading"><Dumbbell size={15} className="text-gold" /><div className="flex-1"><span>Train the body</span><p className="widget-caption">Twenty minutes. Fully present.</p></div><span className="widget-check"><Check size={12} /></span></div><MiniGrid count={180} /></div><p className="widget-app-label">Summa</p>
        <div className="widget-strip widget-preview"><div className="weekly-row"><span />{["M", "T", "W", "T", "F", "S", "S"].map((day, i) => <span key={i} className="text-center text-muted-foreground">{day}</span>)}</div>{[Sun, Dumbbell, Feather].map((Icon, row) => <div className={`weekly-row ${row === 1 ? "weekly-sage" : ""}`} key={row}><Icon size={12} className="text-muted-foreground" />{Array.from({ length: 7 }, (_, i) => <span key={i} className={`weekly-cell ${i < 4 && (i + row) % 3 !== 2 ? "kept" : ""}`} />)}</div>)}</div><p className="widget-app-label">Summa</p>
        <div className="home-search"><Search size={10} /><span>Search</span></div><div className="widget-home-dock"><HomeApp kind="phone" label="Phone" dock /><HomeApp kind="safari" label="Safari" dock /><HomeApp kind="messages" label="Messages" dock /><HomeApp kind="camera" label="Camera" dock /></div>
      </div>
    </Phone></Reveal>
  </div></section>;
}
