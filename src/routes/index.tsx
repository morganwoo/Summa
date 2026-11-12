import { createFileRoute } from "@tanstack/react-router";
import seneca from "@/assets/statue-seneca.jpg";
import { SiteShell } from "@/components/SiteShell";
import { Reveal } from "@/components/Reveal";
import { Heatmap } from "@/components/Heatmap";
import { ProgramPhone } from "@/components/ProgramPhone";
import { HabitCurve } from "@/components/HabitCurve";
import { ReviewCarousel } from "@/components/ReviewCarousel";
import { StoreButtons } from "@/components/StoreButtons";
import { ThreePhones, OnboardingSection, WidgetsSection } from "@/components/ProductPreviews";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Summa — The 90-Day Stoic Habit Tracker" },
      { name: "description", content: "Build your discipline with Summa. Personalized AI onboarding, a tailored ninety-day plan, simple habit heatmaps, and quiet home-screen widgets." },
      { property: "og:title", content: "Summa — The 90-Day Stoic Habit Tracker" },
      { property: "og:description", content: "Your story. Your ninety-day plan. Stoic habit tracking, personalized AI onboarding, and quiet home-screen widgets." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

function Index() {
  return (
    <SiteShell>
      {/* Hero */}
      <section className="product-opening px-6 text-center">
        <p className="eyebrow mb-4">Ninety days. One discipline.</p>
        <h1 className="font-display text-4xl md:text-5xl">Summa</h1>
        <p className="mx-auto mt-4 max-w-lg font-serif text-xl text-muted-foreground">A considered approach to becoming who you want to be.</p>
        <ThreePhones />
        <div className="mt-8"><StoreButtons /></div>
        <p className="mt-5 text-xs text-muted-foreground">Rooted in Stoicism. Built around you.</p>
      </section>

      <OnboardingSection />

      <WidgetsSection />

      {/* Heatmap */}
      <section aria-label="Daily practice and ninety-day heatmaps" className="mx-auto grid max-w-6xl items-start gap-16 px-6 py-24 md:grid-cols-2 md:py-32">
        <Reveal><ProgramPhone /></Reveal>
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
