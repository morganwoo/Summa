import { useState } from "react";
import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { HEATMAP_DAYS, toggleLatestDay } from "@/lib/heatmap-state";
import { useInView } from "./Reveal";

function seeded(n: number) { const x = Math.sin(n * 9301 + 49297) * 233280; return x - Math.floor(x); }

const habits = [
  { name: "Wake before dawn", rate: 0.82 },
  { name: "Train the body", rate: 0.7 },
  { name: "Journal — evening review", rate: 0.9 },
];

export function HabitCard({ name, rate, idx, completed, onComplete }: { name: string; rate: number; idx: number; completed: boolean; onComplete: () => void }) {
  const { ref, inView } = useInView<HTMLDivElement>();
  const cols = 30, rows = 3;
  return (
    <div ref={ref} className="rounded-3xl border bg-card p-5 md:p-6">
      <div className="mb-5 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className="grid h-11 w-11 place-items-center rounded-xl bg-cell-1 font-display text-gold">{["I", "II", "III"][idx]}</div>
          <span className="font-serif text-xl md:text-2xl">{name}</span>
        </div>
        <Button size="icon" aria-label={`Mark today — ${name}`} aria-pressed={completed} title={completed ? `Clear today — ${name}` : `Complete today — ${name}`} onClick={onComplete} className="h-11 w-11 rounded-xl bg-gold text-primary-foreground glow"><Check /></Button>
      </div>
      <div className="grid gap-[5px]" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0,1fr))` }}>
        {Array.from({ length: HEATMAP_DAYS }).map((_, i) => {
          const day = (i % cols) * rows + Math.floor(i / cols);
          const r = seeded(day + idx * 100);
          const latest = day === HEATMAP_DAYS - 1;
          const done = latest ? completed : r < rate;
          const lvl = !done ? "bg-cell" : r < rate * 0.4 ? "bg-cell-3" : r < rate * 0.75 ? "bg-cell-2" : "bg-cell-1";
          return (
            <div key={i} role="img" aria-label={`${name}, day ${day + 1}: ${done ? "completed" : "not completed"}`} className={`aspect-square rounded-[4px] transition-all duration-500 ${latest ? (completed ? "bg-cell-3 glow" : "bg-cell") : (inView ? lvl : "bg-cell")}`} style={{ transitionDelay: latest ? "0ms" : `${day * 15}ms` }} />
          );
        })}
      </div>
      <div className="mt-3 flex justify-between eyebrow"><span>Day 1</span><span>Day 90</span></div>
    </div>
  );
}

export function Heatmap() {
  const [completed, setCompleted] = useState([false, false, false]);
  return <div className="flex flex-col gap-5">{habits.map((h, i) => <HabitCard key={h.name} {...h} idx={i} completed={completed[i] ?? false} onComplete={() => setCompleted((current) => toggleLatestDay(current, i))} />)}</div>;
}
