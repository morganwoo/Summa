import { useInView } from "./Reveal";

const pts = [
  { x: 150, y: 330, label: "Day 7", sub: "Resistance" },
  { x: 290, y: 255, label: "Day 21", sub: "Stabilization" },
  { x: 430, y: 160, label: "Day 66", sub: "Automaticity" },
  { x: 520, y: 40, label: "Day 90", sub: "" },
];

export function HabitCurve() {
  const { ref, inView } = useInView<HTMLDivElement>();
  return (
    <div ref={ref} className="w-full">
      <svg viewBox="0 0 560 420" className="w-full text-foreground" role="img" aria-label="Ninety-day habit curve through day 7, day 21, day 66, and day 90">
        {[330, 255, 160, 50].map((y, i) => (
          <g key={y}>
            <line x1="60" x2="530" y1={y} y2={y} stroke="currentColor" strokeOpacity="0.15" strokeDasharray="6 8" />
            <text x="10" y={y + 4} fontSize="12" fill="currentColor" opacity="0.5">{["5%", "15%", "34%", "58%"][i]}</text>
          </g>
        ))}
        <line x1="60" y1="380" x2="540" y2="380" stroke="currentColor" strokeOpacity="0.6" />
        <line x1="60" y1="380" x2="60" y2="20" stroke="currentColor" strokeOpacity="0.6" />
        <path
          d="M60 380 C 100 345, 120 340, 150 330 S 240 310, 290 255 S 380 190, 430 160 S 500 110, 520 40"
          fill="none" stroke="var(--gold)" strokeWidth="3"
          pathLength="1"
          className={`draw-line ${inView ? "drawn" : ""}`}
        />
        {pts.map((p, i) => (
          <g key={p.label} className={`curve-milestone ${inView ? "visible" : ""}`} style={{ transitionDelay: `${[500, 1100, 1900, 2800][i]}ms` }}>
            <circle cx={p.x} cy={p.y} r="9" fill="var(--background)" stroke="var(--gold)" strokeWidth="3" />
            <text x={p.x - (i === 3 ? 48 : 24)} y={p.y - 20} fontSize="15" fill="currentColor" fontFamily="Cinzel">{p.label}</text>
            <text x={p.x - 34} y="402" fontSize="12" fill="currentColor" opacity="0.6">{p.sub}</text>
          </g>
        ))}
        <text x="70" y="15" fontSize="11" fill="currentColor" opacity="0.6" letterSpacing="3">WELL-BEING</text>
      </svg>
    </div>
  );
}
