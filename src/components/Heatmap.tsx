import { useState } from "react";
import { Check, Moon, Focus, Footprints } from "lucide-react";
import { Button } from "@/components/ui/button";
import { HEATMAP_DAYS, toggleLatestDay } from "@/lib/heatmap-state";
import { useInView } from "./Reveal";

function seeded(n: number) { const x = Math.sin(n * 9301 + 49297) * 233280; return x - Math.floor(x); }

const habits = [
  { name: "Evening", caption: "A quiet moment to close the day.", rate: 0.82 },
  { name: "One focused block", caption: "One thing. Your full attention.", rate: 0.7 },
  { name: "Train the body", caption: "Move with intention.", rate: 0.9 },
];

export function HabitCard({ name, caption, rate, idx, completed, onComplete }: { name: string; caption: string; rate: number; idx: number; completed: boolean; onComplete: () => void }) {
  const { ref, inView } = useInView<HTMLDivElement>();
  const cols = 13, rows = 7;
  const Icon = [Moon, Focus, Footprints][idx] ?? Moon;
  return (
    <div ref={ref} className={`actual-habit-card habit-tone-${idx}`}>
      <div className="mb-5 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className="actual-habit-icon"><Icon size={23} /></div>
          <div><span className="font-serif text-xl md:text-2xl">{name}</span><p className="mt-1 text-xs text-muted-foreground">{caption}</p></div>
        </div>
        <Button size="icon" aria-label={`Mark today — ${name}`} aria-pressed={completed} title={completed ? `Clear today — ${name}` : `Complete today — ${name}`} onClick={onComplete} className="actual-habit-check"><Check /></Button>
      </div>
      <div className="actual-habit-grid">
        {Array.from({ length: HEATMAP_DAYS }).map((_, i) => {
          const day = (i % cols) * rows + Math.floor(i / cols);
          const r = seeded(day + idx * 100);
          const latest = day === HEATMAP_DAYS - 1;
          const done = latest ? completed : r < rate;
          const lvl = !done ? "" : r < rate * 0.4 ? "cell-full" : r < rate * 0.75 ? "cell-medium" : "cell-light";
          return (
            <div key={i} role="img" aria-label={`${name}, day ${day + 1}: ${done ? "completed" : "not completed"}`} className={`actual-habit-cell ${latest ? (completed ? "cell-full cell-today" : "cell-today") : (inView ? lvl : "")}`} style={{ transitionDelay: latest ? "0ms" : `${day * 6}ms` }} />
          );
        })}
      </div>
    </div>
  );
}

export function Heatmap() {
  const [completed, setCompleted] = useState([false, false, false]);
  return <div className="flex flex-col gap-5">{habits.map((h, i) => <HabitCard key={h.name} {...h} idx={i} completed={completed[i] ?? false} onComplete={() => setCompleted((current) => toggleLatestDay(current, i))} />)}</div>;
}
