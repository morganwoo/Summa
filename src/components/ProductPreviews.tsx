import type { ReactNode } from "react";
import { ArrowUpRight, BookOpen, Check, ChevronLeft, Dumbbell, Feather, Sun, Signal, Wifi, BatteryFull, Mic, Plus } from "lucide-react";
import seneca from "@/assets/statue-seneca.jpg";
import { Reveal } from "./Reveal";

function Phone({ children, className = "", label }: { children: ReactNode; className?: string; label: string }) {
  return <div className={`product-phone ${className}`} role="img" aria-label={label}><span className="phone-side-key phone-side-key-volume" aria-hidden="true" /><span className="phone-side-key phone-side-key-power" aria-hidden="true" /><div className="phone-screen"><div className="phone-status"><span>9:41</span><span className="flex items-center gap-1"><Signal size={10} /><Wifi size={10} /><BatteryFull size={13} /></span></div><div className="phone-island" />{children}<div className="phone-home" /></div></div>;
}

function MiniGrid({ tone = "gold", count = 90, offset = 0 }: { tone?: "gold" | "sage"; count?: number; offset?: number }) {
  return <div className={`mini-grid mini-grid-${tone}`} aria-hidden="true">{Array.from({ length: count }, (_, i) => <span key={i} className={(i * 7 + offset) % 11 < 8 ? ((i + offset) % 3 === 0 ? "partial" : "kept") : ""} />)}</div>;
}

function PlanScreen() {
  return <div className="phone-content"><div className="phone-topline"><ChevronLeft size={15} /><span>YOUR 90 DAYS</span><Feather size={14} /></div><p className="phone-kicker mt-7">Made for your life</p><h3 className="phone-title mt-2">A quieter mind.<br />A stronger you.</h3><p className="phone-copy mt-3">Small beginnings. Lasting change.</p><div className="mt-7 border-t border-border">{[{ day: "01 — 21", title: "Find your footing", text: "Build a morning you can keep." }, { day: "22 — 66", title: "Settle into rhythm", text: "Make consistency feel natural." }, { day: "67 — 90", title: "Make it yours", text: "Carry your discipline forward." }].map((phase) => <div key={phase.day} className="plan-phase"><span>{phase.day}</span><h4>{phase.title}</h4><p>{phase.text}</p></div>)}</div><div className="phone-bottom-note"><Feather size={12} /> Personal by design</div></div>;
}

function HabitsScreen() {
  return <div className="phone-content"><div className="phone-topline"><span className="font-display text-gold">STOA 90</span><Sun size={15} /></div><p className="phone-kicker mt-6">Thursday, November 12</p><h3 className="phone-title mt-2">Keep your word.</h3><div className="phone-progress mt-4"><span>DAY 24 OF 90</span><span>26%</span></div><div className="mt-2 h-px bg-border"><div className="h-px w-1/4 bg-gold" /></div><div className="mt-5 space-y-3">{[{ title: "Rise with intention", sub: "A moment before the world", icon: Sun, tone: "gold" }, { title: "Train the body", sub: "Move for twenty minutes", icon: Dumbbell, tone: "sage" }, { title: "Evening reflection", sub: "Return to yourself", icon: Feather, tone: "gold" }].map((habit, i) => <div className="phone-habit" key={habit.title}><div className="mb-3 flex items-center gap-2"><habit.icon size={15} className={habit.tone === "sage" ? "text-sage" : "text-gold"} /><div className="flex-1"><h4>{habit.title}</h4><p>{habit.sub}</p></div><Check size={13} className="text-muted-foreground" /></div><MiniGrid tone={habit.tone === "sage" ? "sage" : "gold"} offset={i * 3} /></div>)}</div><p className="phone-bottom-note font-serif italic">The act is the record.</p></div>;
}

function ProgressScreen() {
  return <div className="phone-content"><div className="phone-topline"><ChevronLeft size={15} /><span>YOUR PROGRESS</span><ArrowUpRight size={15} /></div><p className="phone-kicker mt-7">Discipline, made visible</p><h3 className="phone-title mt-2">Look how far<br />you’ve come.</h3><div className="mt-6"><div className="phone-progress mb-3"><span>THE LAST 90 DAYS</span><span className="text-gold">78%</span></div><MiniGrid count={180} /></div><div className="mt-6 grid grid-cols-2 gap-4 border-y border-border py-4"><div><strong className="phone-stat">24</strong><p className="phone-copy">Day streak</p></div><div><strong className="phone-stat">70</strong><p className="phone-copy">Days kept</p></div></div><div className="progress-bars mt-6" aria-hidden="true">{[18, 24, 20, 30, 38, 34, 46, 51, 49, 63, 72, 80].map((height, i) => <span key={i} style={{ height: `${height}%` }} />)}</div><div className="phone-progress mt-2"><span>DAY 1</span><span>DAY 90</span></div></div>;
}

export function ThreePhones() {
  return <div className="phone-trio"><Phone className="phone-left" label="Example personalized ninety-day plan"><PlanScreen /></Phone><Phone className="phone-center" label="Stoa 90 habit tracker with three ninety-day heatmaps"><HabitsScreen /></Phone><Phone className="phone-right" label="Example habit progress and consistency"><ProgressScreen /></Phone></div>;
}

export function OnboardingSection() {
  return <section className="onboarding-section border-y border-border"><div className="mx-auto grid max-w-6xl items-center gap-16 px-6 py-24 md:grid-cols-2 md:py-32"><Reveal><p className="eyebrow mb-6">Personalized from the first conversation</p><h2 className="feature-title">Bring your story.<br />We’ll shape the plan.</h2><p className="mt-6 max-w-md font-serif text-xl text-muted-foreground">Your goals. Your routine. The habits you want to leave behind. Talk to our AI and receive a tailored 90-day plan, ready in moments.</p><div className="mt-8 flex items-center gap-3 text-sm text-gold"><Feather size={17} /><span>A conversation. Not a questionnaire.</span></div></Reveal><Reveal className="onboarding-visual"><Phone label="Illustration of AI onboarding creating a personalized plan"><img src={seneca} alt="" className="onboarding-statue" /><div className="phone-content relative"><div className="phone-topline"><span className="font-display">STOA 90</span><span className="flex items-center gap-2">YOUR BEGINNING<span className="voice-microphone" role="img" aria-label="Voice input microphone"><Mic size={19} strokeWidth={1.6} /></span></span></div><h3 className="phone-title mt-9">Begin with<br />who you are.</h3><p className="phone-copy mt-3 max-w-40">What would you like to change over the next ninety days?</p><div className="onboarding-dialog"><p className="phone-kicker">YOU</p><p>I want to feel more focused, move every day, and make time to reflect.</p><div className="mt-5 border-t border-border pt-4"><p className="phone-kicker text-gold">STOA</p><p className="mt-2">Let’s start small. What does a typical morning look like for you?</p></div></div></div></Phone><div className="plan-notification"><div className="notification-icon"><Check size={18} /></div><div><p className="text-sm font-medium">Your 90-day plan is ready.</p><p className="mt-1 text-xs text-muted-foreground">Built around your life. Not the other way around.</p></div></div></Reveal></div></section>;
}

export function WidgetsSection() {
  return <section className="widgets-section px-6 py-24 md:py-32"><div className="mx-auto grid max-w-6xl items-center gap-16 md:grid-cols-2">
    <Reveal><p className="eyebrow mb-6">Home-screen widgets</p><h2 className="feature-title">Your habits.<br />On your home screen.</h2><p className="mt-6 max-w-md font-serif text-xl text-muted-foreground">Your daily practice, at a glance. Without opening the app.</p></Reveal>
    <Reveal className="widget-composition"><Phone className="widget-phone" label="Phone home screen with Stoa 90 reading, training, and weekly widgets">
      <div className="widget-home-screen"><div className="widget-home-date">Thursday, November 12</div><div className="widget-home-time">9:41</div>
        <div className="widget-home-top"><div className="widget-small widget-preview"><div className="widget-heading"><BookOpen size={15} className="text-sage" /><span>Read daily</span></div><MiniGrid tone="sage" count={60} /><p className="widget-caption">Day 24 of 90</p></div><div className="widget-home-brand"><Feather size={27} strokeWidth={1} /><span>STOA 90</span></div></div>
        <div className="widget-wide widget-preview"><div className="widget-heading"><Dumbbell size={15} className="text-gold" /><span>Train the body</span><span className="widget-check"><Check size={12} /></span></div><MiniGrid count={90} /><p className="widget-caption">Twenty minutes. Fully present.</p></div>
        <div className="widget-strip widget-preview"><div className="weekly-row"><span />{["M", "T", "W", "T", "F", "S", "S"].map((day, i) => <span key={i} className="text-center text-muted-foreground">{day}</span>)}</div>{[Sun, Dumbbell, Feather].map((Icon, row) => <div className={`weekly-row ${row === 1 ? "weekly-sage" : ""}`} key={row}><Icon size={12} className="text-muted-foreground" />{Array.from({ length: 7 }, (_, i) => <span key={i} className={`weekly-cell ${i < 4 && (i + row) % 3 !== 2 ? "kept" : ""}`} />)}</div>)}</div>
        <div className="widget-page-dots" aria-hidden="true"><span /><span /><span /></div><div className="widget-home-dock" aria-hidden="true">{[Feather, BookOpen, Sun, Plus].map((Icon, i) => <span key={i}><Icon size={19} strokeWidth={1.5} /></span>)}</div>
      </div>
    </Phone></Reveal>
  </div></section>;
}
