import type { ReactNode } from "react";
import { Check, Feather, Signal, Wifi, BatteryFull } from "lucide-react";
import widgets from "@/assets/summa-widgets.jpg.asset.json";
import heatmaps from "@/assets/summa-heatmaps.jpg.asset.json";
import welcome from "@/assets/summa-welcome.jpg.asset.json";
import plan from "@/assets/summa-plan.jpg.asset.json";
import colosseum from "@/assets/summa-colosseum.jpg.asset.json";
import { Reveal } from "./Reveal";

export function Phone({ children, className = "", label, screenshot, interactive = false }: { children?: ReactNode; className?: string; label: string; screenshot?: string; interactive?: boolean }) {
  return <div className={`product-phone ${className}`} role={interactive ? "group" : "img"} aria-label={label}><span className="phone-side-key phone-side-key-volume" aria-hidden="true" /><span className="phone-side-key phone-side-key-power" aria-hidden="true" /><div className="phone-screen">{screenshot ? <><img src={screenshot} alt="" className="phone-screenshot" />{children}</> : <><div className="phone-status"><span>9:41</span><span className="flex items-center gap-1"><Signal size={10} /><Wifi size={10} /><BatteryFull size={13} /></span></div><div className="phone-island" />{children}<div className="phone-home" /></>}</div></div>;
}

export function ThreePhones() {
  return <div className="phone-trio"><Phone className="phone-left" label="Summa Colosseum victory journal" screenshot={colosseum.url} /><Phone className="phone-center" label="Summa habit tracker with three ninety-day heatmaps" screenshot={heatmaps.url} /><Phone className="phone-right" label="Summa ninety-day plan and milestones" screenshot={plan.url} /></div>;
}

export function OnboardingSection() {
  return <section className="onboarding-section border-y border-border"><div className="mx-auto grid max-w-6xl items-center gap-16 px-6 py-24 md:grid-cols-2 md:py-32"><Reveal><p className="eyebrow mb-6">Personalized from the first conversation</p><h2 className="feature-title">Bring your story.<br />We’ll shape the plan.</h2><p className="mt-6 max-w-md font-serif text-xl text-muted-foreground">Your goals. Your routine. The habits you want to leave behind. Talk to our AI and receive a tailored 90-day plan, ready in moments.</p><div className="mt-8 flex items-center gap-3 text-sm text-gold"><Feather size={17} /><span>A conversation. Not a questionnaire.</span></div></Reveal><Reveal className="onboarding-visual"><Phone label="Summa welcome and personalized onboarding" screenshot={welcome.url} /><div className="plan-notification"><div className="notification-icon"><Check size={18} /></div><div><p className="text-sm font-medium">Your 90-day plan is ready.</p><p className="mt-1 text-xs text-muted-foreground">Built around your life. Not the other way around.</p></div></div></Reveal></div></section>;
}

export function WidgetsSection() {
  return <section className="widgets-section px-6 py-24 md:py-32"><div className="mx-auto grid max-w-6xl items-center gap-16 md:grid-cols-2">
    <Reveal><p className="eyebrow mb-6">Home-screen widgets</p><h2 className="feature-title">Your habits.<br />On your home screen.</h2><p className="mt-6 max-w-md font-serif text-xl text-muted-foreground">Your daily practice, at a glance. Without opening the app.</p></Reveal>
    <Reveal className="widget-composition"><Phone className="widget-phone" label="Apple home screen with Summa victory, habit heatmap, and weekly widgets" screenshot={widgets.url} /></Reveal>
  </div></section>;
}
