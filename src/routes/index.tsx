import { createFileRoute } from "@tanstack/react-router";
import hero from "@/assets/statue-hero.jpg";
import seneca from "@/assets/statue-seneca.jpg";
import { SiteShell } from "@/components/SiteShell";
import { Reveal } from "@/components/Reveal";
import { Heatmap } from "@/components/Heatmap";
import { HabitCurve } from "@/components/HabitCurve";
import { ReviewCarousel } from "@/components/ReviewCarousel";
import { StoreButtons } from "@/components/StoreButtons";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Stoa 90 — The 90-Day Stoic Habit Tracker" },
      { name: "description", content: "A minimal stoic habit tracker. One heatmap, ninety days, no noise. Transform your life with discipline made visible." },
      { property: "og:title", content: "Stoa 90 — The 90-Day Stoic Habit Tracker" },
      { property: "og:description", content: "One heatmap. Ninety days. No noise." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

const principles = [
  { n: "I", t: "Habit tracking", d: "Mark the day. Nothing more. The act is the record." },
  { n: "II", t: "Seen, minimally", d: "A single heatmap shows the truth of your discipline at a glance." },
  { n: "III", t: "No noise", d: "No feeds, badges, or confetti. Silence is the feature." },
  { n: "IV", t: "One exact solution", d: "Not a bundle of features. One tool, built to do one thing perfectly." },
];

function Index() {
  return (
    <SiteShell>
      {/* Hero */}
      <section className="relative flex min-h-screen items-center overflow-hidden">
        <img src={hero} alt="Marble bust of Marcus Aurelius" width={1920} height={1088} className="absolute inset-0 h-full w-full object-cover object-right opacity-80" />
        <div className="absolute inset-0 fade-x" />
        <div className="absolute inset-0 fade-b" />
        <div className="relative z-10 px-6 md:px-16">
          <p className="eyebrow mb-6">A 90-day stoic program</p>
          <h1 className="title-roman max-w-3xl text-4xl md:text-6xl">
            Ninety days.<br />One discipline.<br />A different life.
          </h1>
          <p className="mt-6 max-w-md font-serif text-xl text-muted-foreground italic">
            “We suffer more often in imagination than in reality.” — Seneca
          </p>
          <div className="mt-10 flex justify-start"><StoreButtons /></div>
        </div>
        <div className="absolute bottom-8 left-1/2 z-10 flex -translate-x-1/2 flex-col items-center gap-3">
          <div className="flex h-10 w-6 justify-center rounded-full border border-foreground/60 pt-2"><span className="h-2 w-px bg-foreground scroll-cue" /></div>
          <span className="eyebrow">Scroll down</span>
        </div>
      </section>

      {/* Manifesto */}
      <section className="flex min-h-[80vh] items-center justify-center px-6 py-32 text-center">
        <Reveal>
          <p className="eyebrow mb-8">The philosophy</p>
          <h2 className="title-roman mx-auto max-w-4xl text-3xl md:text-5xl">
            Track the habit.<br />See it plainly.<br />Ignore the noise.
          </h2>
          <p className="mx-auto mt-8 max-w-xl font-serif text-xl text-muted-foreground">
            Most habit apps become another distraction. Stoa 90 is the exact solution — simple by design, so the only thing left is the work.
          </p>
        </Reveal>
      </section>

      {/* Principles */}
      <section className="mx-auto grid max-w-6xl gap-px overflow-hidden rounded-3xl border bg-border px-0 md:grid-cols-4">
        {principles.map((p) => (
          <Reveal key={p.n} className="bg-background p-8">
            <div className="title-roman text-3xl text-gold">{p.n}</div>
            <h3 className="title-roman mt-6 text-sm">{p.t}</h3>
            <p className="mt-3 text-sm text-muted-foreground">{p.d}</p>
          </Reveal>
        ))}
      </section>

      {/* Heatmap */}
      <section className="mx-auto grid max-w-6xl items-center gap-16 px-6 py-40 md:grid-cols-2">
        <Reveal>
          <p className="eyebrow mb-6">The one feature</p>
          <h2 className="title-roman text-3xl md:text-4xl">The heatmap does not lie.</h2>
          <p className="mt-6 font-serif text-xl text-muted-foreground">
            Every square is a day. Ninety of them. Tap once to mark it kept. Over weeks, the grid becomes a portrait of who you are becoming — written in gold, or left in shadow.
          </p>
        </Reveal>
        <Reveal><Heatmap /></Reveal>
      </section>

      {/* Curve */}
      <section className="relative overflow-hidden py-32">
        <img src={seneca} alt="" loading="lazy" width={1280} height={1600} className="absolute -left-40 top-0 h-full w-auto object-cover opacity-25" />
        <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-6 md:grid-cols-2">
          <Reveal className="md:order-2">
            <p className="eyebrow mb-6">The 90-day arc</p>
            <h2 className="title-roman text-3xl md:text-4xl">Resistance. Then rhythm. Then you.</h2>
            <p className="mt-6 font-serif text-xl text-muted-foreground">
              Research suggests habits take around 66 days to become automatic. We give you ninety — enough to pass through resistance, stabilize, and arrive at a self that no longer needs persuading.
            </p>
          </Reveal>
          <Reveal className="md:order-1"><HabitCurve /></Reveal>
        </div>
      </section>

      {/* Quote */}
      <section className="flex min-h-[70vh] items-center justify-center px-6 text-center">
        <Reveal>
          <blockquote className="mx-auto max-w-4xl font-serif text-3xl italic leading-tight md:text-5xl">
            “You have power over your mind — not outside events. Realize this, and you will find strength.”
          </blockquote>
          <p className="eyebrow mt-8">Marcus Aurelius · Meditations</p>
        </Reveal>
      </section>

      {/* Reviews */}
      <section className="px-6 py-32">
        <p className="eyebrow mb-12 text-center">Testimonia</p>
        <ReviewCarousel />
      </section>

      {/* CTA */}
      <section className="flex min-h-[70vh] flex-col items-center justify-center px-6 text-center">
        <Reveal>
          <h2 className="title-roman text-4xl md:text-6xl">Day one is today.</h2>
          <p className="mx-auto mt-6 max-w-md font-serif text-xl text-muted-foreground">Begin the 90-day transformation.</p>
          <div className="mt-10"><StoreButtons /></div>
        </Reveal>
      </section>
    </SiteShell>
  );
}
