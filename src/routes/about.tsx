import { createFileRoute } from "@tanstack/react-router";
import seneca from "@/assets/statue-seneca.jpg";
import { SiteShell } from "@/components/SiteShell";
import { Reveal } from "@/components/Reveal";
import { StoreButtons } from "@/components/StoreButtons";

export const Route = createFileRoute("/about")({
  head: () => ({
    meta: [
      { title: "About Stoa 90 — Stoic Habit Tracking" },
      { name: "description", content: "Why Stoa 90 exists: a minimal, noise-free habit tracker built on Stoic philosophy and a 90-day transformation." },
      { property: "og:title", content: "About Stoa 90" },
      { property: "og:description", content: "Simplicity as discipline. The story behind the 90-day stoic habit tracker." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: About,
});

const phases = [
  { d: "Days 1–21", t: "Resistance", p: "The mind bargains. You mark the square anyway." },
  { d: "Days 22–66", t: "Stabilization", p: "The grid gains rhythm. Effort turns to routine." },
  { d: "Days 67–90", t: "Automaticity", p: "The habit is no longer something you do. It is who you are." },
];

function About() {
  return (
    <SiteShell>
      <section className="relative grid min-h-screen items-center md:grid-cols-2">
        <img src={seneca} alt="Marble bust of Seneca" width={1280} height={1600} className="h-[60vh] w-full object-cover object-left md:h-screen" />
        <div className="px-6 py-20 md:px-16">
          <Reveal>
            <p className="eyebrow mb-6">About</p>
            <h1 className="title-roman text-4xl md:text-5xl">Less, but kept.</h1>
            <p className="mt-8 font-serif text-xl text-muted-foreground">
              Stoa 90 was born from frustration with habit apps that wanted to be everything — journals, social feeds, gamified reward machines. The Stoics taught that clarity comes from removing what is unnecessary.
            </p>
            <p className="mt-6 font-serif text-xl text-muted-foreground">
              So we removed it. What remains is a single heatmap, a single tap, and ninety days to prove to yourself what you are capable of.
            </p>
          </Reveal>
        </div>
      </section>
      <section className="mx-auto max-w-5xl px-6 py-32">
        <p className="eyebrow mb-12 text-center">The program</p>
        <div className="grid gap-6 md:grid-cols-3">
          {phases.map((ph) => (
            <Reveal key={ph.t} className="rounded-3xl border bg-card p-8">
              <div className="eyebrow text-gold">{ph.d}</div>
              <h3 className="title-roman mt-4 text-xl">{ph.t}</h3>
              <p className="mt-4 font-serif text-lg text-muted-foreground">{ph.p}</p>
            </Reveal>
          ))}
        </div>
        <div className="mt-20 flex justify-center"><StoreButtons /></div>
      </section>
    </SiteShell>
  );
}
