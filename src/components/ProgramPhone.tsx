import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import program from "@/assets/summa-program.jpg.asset.json";
import detail from "@/assets/summa-day-detail.jpg.asset.json";
import { Phone } from "./ProductPreviews";

export function ProgramPhone() {
  const [open, setOpen] = useState(false);
  const dayButton = useRef<HTMLButtonElement>(null);
  const doneButton = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (open) doneButton.current?.focus({ preventScroll: true });
  }, [open]);

  function close() {
    setOpen(false);
    dayButton.current?.focus({ preventScroll: true });
  }

  return <div className="program-preview">
    <Phone className="program-phone" label="Interactive Summa ninety-day heatmap" screenshot={program.url} interactive>
      <Button ref={dayButton} variant="ghost" className="program-day-hit" aria-label="Open Foundation day 1" aria-expanded={open} aria-controls="program-day-sheet" onClick={() => setOpen(true)} tabIndex={open ? -1 : 0} />
      <div className={`program-upper-dim ${open ? "is-open" : ""}`} aria-hidden="true"><img src={detail.url} alt="" className="phone-screenshot" /></div>
      <div id="program-day-sheet" role="dialog" aria-label="Foundation day 1 details" aria-hidden={!open} className={`program-day-sheet ${open ? "is-open" : ""}`} onKeyDown={(event) => { if (event.key === "Escape") close(); }}>
        <img src={detail.url} alt="" className="phone-screenshot" />
        <div className="sr-only"><h3>Day 1 — Foundation</h3><p>3 of 3 done: Train the body, Pre-Home Movement, Class Arrival. All completed.</p></div>
        <Button ref={doneButton} variant="ghost" className="program-done-hit" aria-label="Done, close day details" onClick={close} tabIndex={open ? 0 : -1} />
      </div>
    </Phone>
    <p className="program-try text-xs text-muted-foreground">Try me, click here.<span aria-hidden="true"> ↗</span></p>
    <div className="program-phase-legend" aria-label="90-day transformation phases"><span><i className="phase-foundation" />Foundation</span><span><i className="phase-momentum" />Momentum</span><span><i className="phase-transformation" />Transformation</span></div>
  </div>;
}