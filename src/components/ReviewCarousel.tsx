import { useEffect, useState } from "react";

const reviews = [
  { q: "Ninety days. One screen. I stopped chasing motivation and started keeping promises to myself.", n: "Marcus R.", h: "Day 90 complete" },
  { q: "Every other app wanted my attention. This one just shows me the truth — filled squares or empty ones.", n: "Elena V.", h: "Day 64" },
  { q: "The heatmap is brutal and beautiful. Watching the grid fill up is the most honest mirror I own.", n: "Daniel K.", h: "Day 90 complete" },
  { q: "No streak confetti, no badges. Just discipline made visible. Exactly what I needed.", n: "Sofia M.", h: "Day 41" },
  { q: "I read the Meditations years ago. This is the first tool that actually made me live it.", n: "James T.", h: "Day 90 complete" },
];

export function ReviewCarousel() {
  const [i, setI] = useState(0);
  useEffect(() => { const t = setInterval(() => setI((v) => (v + 1) % reviews.length), 6000); return () => clearInterval(t); }, []);
  const go = (d: number) => setI((v) => (v + d + reviews.length) % reviews.length);
  return (
    <div className="mx-auto max-w-3xl text-center">
      <div className="overflow-hidden">
        <div className="flex transition-transform duration-700 ease-out" style={{ transform: `translateX(-${i * 100}%)` }}>
          {reviews.map((r) => (
            <figure key={r.n} className="w-full shrink-0 px-4">
              <div className="mb-6 text-2xl tracking-[0.3em] text-gold" aria-label="5 out of 5 stars">★★★★★</div>
              <blockquote className="font-serif text-2xl italic leading-snug md:text-4xl">“{r.q}”</blockquote>
              <figcaption className="mt-8 eyebrow">{r.n} · {r.h}</figcaption>
            </figure>
          ))}
        </div>
      </div>
      <div className="mt-10 flex items-center justify-center gap-6">
        <button aria-label="Previous review" onClick={() => go(-1)} className="grid h-10 w-10 place-items-center rounded-full border hover:border-gold hover:text-gold">‹</button>
        <div className="flex gap-2">
          {reviews.map((_, k) => (
            <button key={k} aria-label={`Review ${k + 1}`} onClick={() => setI(k)} className={`h-1 rounded-full transition-all ${k === i ? "w-8 bg-gold" : "w-3 bg-foreground/30"}`} />
          ))}
        </div>
        <button aria-label="Next review" onClick={() => go(1)} className="grid h-10 w-10 place-items-center rounded-full border hover:border-gold hover:text-gold">›</button>
      </div>
    </div>
  );
}
