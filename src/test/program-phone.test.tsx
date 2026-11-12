import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { ProgramPhone } from "@/components/ProgramPhone";

afterEach(cleanup);

describe("program day preview", () => {
  it("opens day 1 only when the highlighted green day is activated", () => {
    render(<ProgramPhone />);
    const day = screen.getByRole("button", { name: "Open Foundation day 1" });
    const phone = screen.getByRole("group", { name: "Interactive Summa ninety-day heatmap" });
    fireEvent.click(phone);
    expect(day).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("dialog")).toBeNull();
    fireEvent.click(day);
    expect(day).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("dialog", { name: "Foundation day 1 details" })).toBeInTheDocument();
  });

  it("returns to the full heatmap when Done is activated", () => {
    render(<ProgramPhone />);
    const day = screen.getByRole("button", { name: "Open Foundation day 1" });
    fireEvent.click(day);
    fireEvent.click(screen.getByRole("button", { name: "Done, close day details" }));
    expect(day).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("opens the book preview only when the yellow book is activated", () => {
    render(<ProgramPhone />);
    const book = screen.getByRole("button", { name: "Open yellow book reflection" });
    fireEvent.click(screen.getByRole("group", { name: "Interactive Summa ninety-day heatmap" }));
    expect(book).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(book);
    expect(book).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("button", { name: "Open Foundation day 1" })).toHaveAttribute("aria-expanded", "false");
    expect(screen.getByRole("dialog", { name: "Yellow book reflection details" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Done, close day details" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(book).toHaveFocus();
  });
});