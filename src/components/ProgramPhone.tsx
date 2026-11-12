import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import program from "@/assets/summa-program.jpg.asset.json";
import detail from "@/assets/summa-day-detail.jpg.asset.json";
import capture from "@/assets/summa-capture-moment.jpg.asset.json";
import { Phone } from "./ProductPreviews";

export function ProgramPhone() {
  const [activePreview, setActivePreview] = useState<"day" | "book" | null>(null);
  const open = activePreview !== null;
  const dayButton = useRef<HTMLButtonElement>(null);
  const bookButton = useRef<HTMLButtonElement>(null);
  const lastTrigger = useRef<"day" | "book">("day");
  const doneButton = useRef<HTMLButtonElement>(null);
  const bookPreview = activePreview === "book" || (!open && lastTrigger.current === "book");
  const previewImage = bookPreview ? capture.url : detail.url;

  useEffect(() => {
    if (open) doneButton.current?.focus({ preventScroll: true });
  }, [open]);

  function close() {
    setActivePreview(null);
    const trigger = lastTrigger.current === "book" ? bookButton : dayButton;
    trigger.current?.focus({ preventScroll: true });
  }

  function show(preview: "day" | "book") {
    lastTrigger.current = preview;
    setActivePreview(preview);
  }

  return <div className="program-preview">
    <div className="program-interaction">
    <Phone className="program-phone" label="Interactive Summa ninety-day heatmap" screenshot={program.url} interactive>
      <Button ref={dayButton} variant="ghost" className="program-day-hit" aria-label="Open Foundation day 1" aria-expanded={activePreview === "day"} aria-controls="program-day-sheet" onClick={() => show("day")} tabIndex={open ? -1 : 0} />
      <Button ref={bookButton} variant="ghost" className="program-book-hit" aria-label="Open yellow book reflection" aria-expanded={activePreview === "book"} aria-controls="program-day-sheet" onClick={() => show("book")} tabIndex={open ? -1 : 0} />
      <div className={`program-upper-dim ${bookPreview ? "program-book-dim" : ""} ${open ? "is-open" : ""}`} aria-hidden="true"><img src={previewImage} alt="" className="phone-screenshot" /></div>
      <div id="program-day-sheet" role="dialog" aria-label={bookPreview ? "Yellow book reflection details" : "Foundation day 1 details"} aria-hidden={!open} className={`program-day-sheet ${bookPreview ? "program-book-sheet" : ""} ${open ? "is-open" : ""}`} onKeyDown={(event) => { if (event.key === "Escape") close(); }}>
        <img src={previewImage} alt="" className="phone-screenshot" />
        <div className="sr-only">{bookPreview ? <><h3>Capture this moment</h3><p>Write a reflection. Talk to Summa. Your Colosseum.</p></> : <><h3>Day 1 — Foundation</h3><p>3 of 3 done: Train the body, Pre-Home Movement, Class Arrival. All completed.</p></>}</div>
        <Button ref={doneButton} variant="ghost" className={bookPreview ? "program-close-book-hit" : "program-done-hit"} aria-label={bookPreview ? "Close reflection preview" : "Done, close day details"} onClick={close} tabIndex={open ? 0 : -1} />
      </div>
    </Phone>
    <svg className={`program-cue-arrows ${open ? "is-hidden" : ""}`} viewBox="-50 0 380 710" fill="none" aria-hidden="true">
      <defs><marker id="program-cue-tip" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto"><path d="M1 1 L6 3.5 L1 6" /></marker></defs>
      <path d="M125 694 C-8 699 -29 577 29 556" markerEnd="url(#program-cue-tip)" />
      <path d="M140 694 C-60 680 -60 245 31 245" markerEnd="url(#program-cue-tip)" />
    </svg>
    </div>
    <p className="program-try text-xs text-muted-foreground">Try me, click here.</p>
    <div className="program-phase-legend" aria-label="90-day transformation phases"><span><i className="phase-foundation" />Foundation</span><span><i className="phase-momentum" />Momentum</span><span><i className="phase-transformation" />Transformation</span></div>
  </div>;
}