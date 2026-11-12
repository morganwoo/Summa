import { useInView } from "./Reveal";

function seeded(n: number) { const x = Math.sin(n * 9301 + 49297) * 233280; return x - Math.floor(x); }

const habits = [
  { name: "Wake before dawn", rate: 0.82 },
  { name: "Train the body", rate: 0.7 },
  { name: "Journal — evening review", rate: 0.9 },
];

export function HabitCard({ name, rate, idx }: { name: string; rate: number; idx: number }) {
  const { ref, inView } = useInView<HTMLDivElement>();
  const cols = 30, rows = 3; // 90 days
  return (
    <div ref={ref} className="rounded-3xl border bg-card p-5 md:p-6">
      <div className="mb-5 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className="grid h-11 w-11 place-items-center rounded-xl bg-cell-1 font-display text-gold">{["I", "II", "III"][idx]}</div>
          <span className="font-serif text-xl md:text-2xl">{name}</span>
        </div>
        <div className="grid h-11 w-11 place-items-center rounded-xl bg-gold text-primary-foreground glow">✓</div>
      </div>
      <div className="grid gap-[5px]" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0,1fr))` }}>
        {Array.from({ length: cols * rows }).map((_, i) => {
          const day = (i % cols) * rows + Math.floor(i / cols);
          const r = seeded(day + idx * 100);
          const done = r < rate;
          const lvl = !done ? "bg-cell" : r < rate * 0.4 ? "bg-cell-3" : r < rate * 0.75 ? "bg-cell-2" : "bg-cell-1";
          return (
            <div key={i} className={`aspect-square rounded-[4px] transition-all duration-500 ${inView ? lvl : "bg-cell"}`} style={{ transitionDelay: `${day * 15}ms` }} />
          );
        })}
      </div>
      <div className="mt-3 flex justify-between eyebrow"><span>Day 1</span><span>Day 90</span></div>
    </div>
  );
}

export function Heatmap() {
  return <div className="flex flex-col gap-5">{habits.map((h, i) => <HabitCard key={h.name} {...h} idx={i} />)}</div>;
}
