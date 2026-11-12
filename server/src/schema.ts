import { z } from "zod";

/** Version 1 of the plan contract. Mirrors `PlanSchema` in ios/SummaCore. */
export const SCHEMA_VERSION = 1;

const QUESTION_IDS = [
  "name", "username", "motivation", "focus", "objective", "obstacles", "arc", "minutes", "days",
  "timeOfDay", "startSize", "body", "future", "extra",
] as const;

const answer = z.array(z.string().max(2000)).max(12);

export const planRequestSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    answers: z.record(z.enum(QUESTION_IDS), answer),
    weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7),
    minutesPerDay: z.number().int().min(1).max(240),
  })
  .strict();

export type PlanRequest = z.infer<typeof planRequestSchema>;

const text = (max: number) => z.string().trim().min(1).max(max);

const habitSchema = z
  .object({
    title: text(60),
    action: text(200),
    minimumVersion: text(200),
    /** Measurable amount for one occurrence, e.g. "10 pages". */
    target: text(60),
    /** Why this habit fits this person, in terms of their answers. */
    reason: text(300),
    weekdays: z
      .array(z.number().int().min(1).max(7))
      .min(1)
      .max(7)
      .transform((days) => [...new Set(days)].sort((a, b) => a - b)),
    reminder: z
      .object({ hour: z.number().int().min(0).max(23), minute: z.number().int().min(0).max(59) })
      .strict()
      .optional(),
    symbol: z.string().regex(/^[a-z0-9.]{1,40}$/).optional(),
  })
  .strict();

const phaseSchema = z
  .object({ title: text(60), startDay: z.number().int(), endDay: z.number().int(), focus: text(240) })
  .strict();

export const planSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    objective: text(280),
    habits: z.array(habitSchema).length(3),
    phases: z.array(phaseSchema).length(3),
  })
  .strict()
  .superRefine((plan, ctx) => {
    const expected = [[1, 21], [22, 66], [67, 90]] as const;
    plan.phases.forEach((phase, index) => {
      const range = expected[index];
      if (!range || phase.startDay !== range[0] || phase.endDay !== range[1]) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["phases", index], message: "phases must cover days 1-21, 22-66, 67-90" });
      }
    });
    const titles = new Set(plan.habits.map((habit) => habit.title.toLowerCase()));
    if (titles.size !== plan.habits.length) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["habits"], message: "habit titles must be distinct" });
    }
  });

export type Plan = z.infer<typeof planSchema>;

export const PHASE_TITLES = ["Find your footing", "Settle into rhythm", "Make it yours"] as const;
