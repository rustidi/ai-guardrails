---
name: brainstorm-first
description: "Before starting any non-trivial task (>0.5 day, new feature, new UI page, new integration, refactor spanning >5 files), it is mandatory to ask the requester 3-5 clarifying questions about scope, edge cases, and success criteria — and wait for answers BEFORE planning or coding. Trigger when the requester says \"do X\" / \"add feature Y\" and the task is non-trivial. Inspired by /brainstorm from obra/superpowers."
---
# Brainstorm-First — mandatory clarification before starting

## Why this skill exists

A recurring complaint: sometimes work gets done sloppily, without thinking through the internal logic first.

Root cause: rushing into code / a plan without checking that the task was understood correctly. Especially when a task sounds "simple" ("build page X" / "fix Y"), but behind the short description hide 5 non-obvious decisions.

This skill is a **mandatory gate** BEFORE plan/code. Without 3-5 questions and answers, work does not start.

---

## When it applies (triggers)

**Applies MANDATORILY:**
- A new feature that does not exist in the code
- A new UI page / landing page
- A new integration (external API, OAuth, billing, MCP)
- An architectural decision (new service, new DB table with >2 relations, new worker)
- Refactoring >5 files or >300 LOC
- Any touch of a high-risk native module
- Any touch of the database schema
- User-facing copy / content
- A task estimated at >0.5 working day

**Applies at discretion:**
- A bugfix where the cause is not obvious
- "Improve X" with no specifics
- "Make it nice" — always clarify what "nice" means

---

## When it does NOT apply

- An obvious bugfix (stack trace shows the cause, fix in one file)
- The requester said "no questions, just do it"
- The requester provided a ready spec (task doc with the plan already written out)
- Typo / variable rename
- A small edit <0.5 day in a well-understood module
- A deploy / operational command
- Reading/researching code
- The request contains explicit implementation parameters (file name, model, chunk size, env var name, exact numbers) — the hypothesis is unambiguous, go to code.
- A follow-up on an active task where scope is already fixed.
- The request contains an explicit plan / numbered list / "do it per this list" — the plan exists, no brainstorm needed.

---

## Calibrating the number of questions

- If the requester gave 0% scope (one sentence "do X") → 3-5 questions
- If the requester gave 50% scope (an option + context, but no exact parameters) → 1-2 questions max
- If the requester gave >80% scope (file path / model / parameters) → 0 questions, one fix-proposal sentence + go
- Anti-pattern: asking a question the requester already answered indirectly. If they wrote "chunked by 15 min" — do NOT ask "chunked vs single-pass" or "chunk size". That is offloading work.

---

## Protocol

### Step 1 — diagnose the task (1-2 minutes)

Before asking, do this **yourself**:

1. Read the project's control/focus docs
2. Look for the task in the backlog (is it there, what ID, what phase)
3. If the task concerns an existing module — read 2-3 key files of that module
4. Formulate your initial hypothesis: "I understood the task as X, I'll implement it via Y"

**If everything is already clear at this stage (small task, unambiguous hypothesis) — do NOT ask questions.** Go to plan/code.

### Step 2 — 3-5 clarifying questions

Ask **minimum 3, maximum 5** questions. No more — the requester will tire. No fewer — you will miss something.

**Questions must be:**
- Closed where possible (yes/no, option A/B/C) — open questions annoy a non-technical requester
- Concrete with examples ("do you mean case X or case Y?")
- About **scope** (in / out), **edge cases** (what if 0 / 1 / 100 / failure), **success criteria** (how do we know it's done)

**Question anti-patterns:**
- ❌ "What do you want?" — zero specificity
- ❌ "What are the performance requirements?" — technical gibberish for a non-technical requester
- ❌ "Tell me more about the use case" — offloading work onto the requester

**Good questions:**
- ✅ "The 'Share' button on the recording page — does it copy a link or open a modal with access settings? (Loom uses a modal)"
- ✅ "If the user closes the recorder mid-recording — do we lose the recording or save what was captured up to that point?"

### Step 3 — question format

Write in a single message:

```
Before I start, I have some questions.

1. <question 1 with options or example>
2. <question 2 ...>
3. <question 3 ...>
[4-5 optional]

My current hypothesis: <1-2 sentences on how I understand the task>.

Waiting for answers — then the plan.
```

### Step 4 — after the answers

1. If all questions answered → write a short recap ("OK, got it: A, B, C") + move to the planning phase.
2. If partially answered → ask **only** the missing ones, don't repeat answered ones.
3. If answered "don't sweat it, do what you think best" → take your hypothesis + explicitly record it in the task doc ("requester gave freedom, hypothesis = X"). If it turns out wrong later — that is **your** responsibility, not theirs.
4. If the requester gave contradictory requirements (X and Y) → one extra closed question "is X more important, or Y?"

---

## Interaction with other skills / agents

- **brainstorm-first comes BEFORE a decision council.** First clarify the task with the requester, then let a council defend the implementation hypothesis.
- **brainstorm-first comes BEFORE the planning phase.** The plan is written on top of clarified scope.
- **brainstorm-first does NOT duplicate a decision council.** The council defends your implementation _hypothesis_ (how); brainstorm clarifies with the requester _what_ needs to be done.
- **brainstorm-first does NOT duplicate planner/architect.** Those agents break the agreed task into steps. Brainstorm is the stage BEFORE the breakdown.

---

## Anti-patterns (do NOT do this)

- ❌ Skipping brainstorm "because it's obvious" on a non-trivial task. If unsure — better to ask.
- ❌ Writing code first, then asking questions. Too late — now you rework.
- ❌ Open questions ("tell me more") — that offloads work onto the requester.
- ❌ >5 questions in the first pass — the requester tires.
- ❌ Technical jargon aimed at a non-technical requester.
- ❌ Asking questions and writing code in parallel. Wait for the answer.
- ❌ Not recapping after the answers — the requester isn't sure you understood.

---

## Examples

### Example 1 — non-trivial feature (applies)

**Requester:** "Add sharing recordings by link."

**You (after reading the app structure):**
```
Before I start, I have some questions.

1. Is the link public (anyone with it can view) or auth-gated (only registered users)?
2. On a recording viewed via link, do we show transcript + summary, or just the video?
3. Can the owner revoke the link, or does it live forever?
4. Does the guest see a view counter / who watched, or does the owner see that in an admin panel?
5. Can free-tier share, or is this a paid feature?

My hypothesis: add a `RecordingShareLink` entity with slug + expiresAt + isRevoked, a `/share/[slug]` page without auth, owner sees a view counter in their account.

Waiting for answers — then the plan.
```

### Example 2 — obvious bugfix (does NOT apply)

**Requester:** "The 'Download' button on the recording page doesn't work, 404 in the console."

**You:** go straight to reading the button code + endpoint, fix it. No questions.

### Example 3 — requester freed you from questions

**Requester:** "Don't sweat it, do what you think is best, I trust you."

**You:** record in the task doc "requester gave freedom, my hypothesis: <X>", go to planning.

### Example 4 — requester gave explicit parameters (skip brainstorm)

**Requester:** "Make a chunked summary, chunks of 15 min, model a fast/cheap model."

**You:** do NOT ask questions. The hypothesis is unambiguous. Go straight to the task doc + code.

(This is the zero-brainstorm path — fastest delivery.)

---

## Success metric

This skill works if:
- Fewer "that's not what I asked for" moments in chat
- Task docs close as DONE without revert / rework
- Fewer changelog entries like "reworked task X because it was misunderstood"
- If the requester says "you ask too many questions" → calibration is broken, lower the question count.
- Target: on an explicit-parameter request → 0 questions in 100% of cases.

---

## References

- Inspired by `/brainstorm` from [obra/superpowers](https://github.com/obra/superpowers)
- Complements, does not replace: a decision council, `planner`, `architect`
