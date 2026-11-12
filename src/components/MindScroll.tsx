import { useEffect, useRef } from "react";
import marbleHead from "@/assets/aurelius-mind.jpg";

const clamp = (value: number) => Math.min(1, Math.max(0, value));
const smooth = (value: number) => value * value * (3 - 2 * value);

export function MindScroll() {
  const section = useRef<HTMLElement>(null);
  useEffect(() => {
    const element = section.current;
    if (!element) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    let frame = 0;
    const update = () => {
      const rect = element.getBoundingClientRect();
      const progress = clamp(-rect.top / (rect.height - window.innerHeight));
      const opening = smooth(clamp((progress - 0.06) / 0.62));
      const quote = smooth(clamp((progress - 0.22) / 0.28));
      const exit = smooth(clamp((progress - 0.82) / 0.18));
      element.style.setProperty("--split", `${opening * 85}%`);
      element.style.setProperty("--zoom", `${1 + opening * 1.65}`);
      element.style.setProperty("--head-opacity", `${1 - smooth(clamp((progress - 0.55) / 0.2))}`);
      element.style.setProperty("--quote-opacity", `${quote * (1 - exit)}`);
      element.style.setProperty("--quote-scale", `${0.76 + quote * 0.24}`);
      element.style.setProperty("--quote-shift", `${(1 - quote) * 28}px`);
      element.style.setProperty("--cue-opacity", `${1 - clamp(progress * 9)}`);
      element.dataset.reducedMotion = String(reduced.matches);
      frame = 0;
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
    update();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    return () => {
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <section ref={section} className="mind-scroll" aria-label="Into the mind of Marcus Aurelius">
      <div className="mind-stage">
        <h1 className="sr-only">Stoa 90 — A ninety-day Stoic practice</h1>
        <div className="mind-head" role="img" aria-label="Marble head of Marcus Aurelius opening as you scroll">
          <div className="mind-half mind-half-left"><img src={marbleHead} alt="" width={1536} height={1536} fetchPriority="high" /></div>
          <div className="mind-half mind-half-right"><img src={marbleHead} alt="" width={1536} height={1536} /></div>
        </div>
        <div className="mind-quote">
          <blockquote className="font-serif text-3xl leading-tight md:text-5xl">“You have power over your mind — not outside events. Realize this, and you will find strength.”</blockquote>
          <p className="eyebrow mt-8">Marcus Aurelius · Meditations</p>
        </div>
        <div className="mind-cue" aria-hidden="true"><span className="h-12 w-px bg-foreground/40" /></div>
      </div>
    </section>
  );
}