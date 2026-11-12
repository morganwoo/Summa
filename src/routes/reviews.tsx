import { createFileRoute } from "@tanstack/react-router";
import { SiteShell } from "@/components/SiteShell";
import { ReviewCarousel } from "@/components/ReviewCarousel";
import { StoreButtons } from "@/components/StoreButtons";

export const Route = createFileRoute("/reviews")({
  head: () => ({
    meta: [
      { title: "Reviews — Stoa 90 Habit Tracker" },
      { name: "description", content: "Five-star reviews from people who completed the Stoa 90 stoic habit program." },
      { property: "og:title", content: "Stoa 90 Reviews" },
      { property: "og:description", content: "What people say after ninety days of discipline." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Reviews,
});

function Reviews() {
  return (
    <SiteShell>
      <section className="flex min-h-screen flex-col items-center justify-center gap-16 px-6 py-32">
        <div className="text-center">
          <p className="eyebrow mb-6">Testimonia</p>
          <h1 className="title-roman text-4xl md:text-5xl">Words of the disciplined</h1>
        </div>
        <ReviewCarousel />
        <StoreButtons />
      </section>
    </SiteShell>
  );
}
