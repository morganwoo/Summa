import { useState } from "react";
import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { HEATMAP_DAYS, toggleLatestDay } from "@/lib/heatmap-state";

function seeded(n: number) { const x = Math.sin(n * 9301 + 49297) * 233280; return x - Math.floor(x); }

const habits = [
  { name: "Wake before dawn", rate: 0.82 },
  { name: "Train the body", rate: 0.7 },
  { name: "Journal — evening review", rate: 0.9 },
];

export function HabitCard({ name, rate, idx, completed, onComplete }: { name: string; rate: number; idx: number; completed: boolean; onComplete: () => void }) {
  const cols = 30, rows = 3;
  return (
    <div className="habit-card rounded-lg border p-5 md:p-8">
      <div className="mb-5 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <span className="font-serif text-xl md:text-3xl">{name}</span>
        </div>
        <Button size="icon" aria-label={`Mark today's habits — ${name}`} aria-pressed={completed} title={completed ? "Clear today in all three habits" : "Complete today in all three habits"} onClick={onComplete} className={`habit-check h-11 w-11 rounded-full ${completed ? "is-complete" : ""}`}><Check /></Button>
      </div>
      <div className="heatmap-grid">
        {Array.from({ length: HEATMAP_DAYS }).map((_, i) => {
          const day = (i % cols) * rows + Math.floor(i / cols);
          const r = seeded(day + idx * 100);
          const latest = day === HEATMAP_DAYS - 1;
          const done = latest ? completed : r < rate;
          const lvl = !done ? "bg-cell" : r < rate * 0.4 ? "bg-cell-3" : r < rate * 0.75 ? "bg-cell-2" : "bg-cell-1";
          return (
            <div key={i} role="img" aria-label={`${name}, day ${day + 1}: ${done ? "completed" : "not completed"}`} className={`heatmap-cell ${latest ? `latest-cell ${completed ? "is-complete" : ""}` : lvl}`} />
          );
        })}
      </div>
      <div className="mt-3 flex justify-between eyebrow"><span>Day 1</span><span>Day 90</span></div>
    </div>
  );
}

export function Heatmap() {
  const [completed, setCompleted] = useState([false, false, false]);
  const [theme, setTheme] = useState<"gold" | "marble">("gold");
  return (
    <div className="heatmap-tool" data-theme={theme}>
      <div className="mb-6 flex items-center justify-between">
        <p className="eyebrow">90 days · Your practice</p>
        <div className="flex gap-3" role="group" aria-label="Heatmap theme">
          <Button variant="ghost" size="icon" aria-label="Gold theme" aria-pressed={theme === "gold"} title="Gold" onClick={() => setTheme("gold")} className={`theme-choice ${theme === "gold" ? "is-selected" : ""}`}><span className="theme-swatch theme-swatch-gold" /></Button>
          <Button variant="ghost" size="icon" aria-label="Marble theme" aria-pressed={theme === "marble"} title="Marble" onClick={() => setTheme("marble")} className={`theme-choice ${theme === "marble" ? "is-selected" : ""}`}><span className="theme-swatch theme-swatch-marble" /></Button>
        </div>
      </div>
      <div className="flex flex-col gap-5">{habits.map((h, i) => <HabitCard key={h.name} {...h} idx={i} completed={completed[i] ?? false} onComplete={() => setCompleted(toggleLatestDay)} />)}</div>
    </div>
  );
}
