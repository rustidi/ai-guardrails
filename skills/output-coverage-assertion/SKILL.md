---
name: output-coverage-assertion
description: "BEFORE claiming \"full coverage\" / \"covers all N minutes\" / \"X highlights across the whole recording\", assert the min/max timeSec of the real output against the source durationSec. Never use bullet count as proof of coverage. Applies to any time-indexed output — highlights, milestones, attention moments, transcript segments, minute summaries, briefs."
---
# Output Coverage Assertion — verify coverage before saying "done"

## Why this skill exists

**The incident:** a report went out as "16 highlights, full coverage of a 49:45 recording". It was believed and the work was closed. 24 hours later the recording was opened — the last highlight was at 31:29, exactly the midpoint. A `BRIEF_MAX_CHARS` cap had truncated the LLM prompt; the last 18 minutes never reached the model. The follow-up fix plus a retroactive re-run across every recording in the regression window cost a whole extra cycle.

**Root cause:** trusting array length (`items.length`) as a proxy for coverage. This is categorically wrong: 16 items in the first half is still 16 items, and `.length === 16` is not lying. **The lie is calling it "covers the full 49:45".**

This skill is a mandatory assertion before any coverage claim. Without checking `max(timeSec) / durationSec` you may not write "full coverage" into a status message, a task file, or a changelog.

Bug class: silent truncation in an LLM pipeline (token limit, char limit, chunk-cut) that does not throw, but returns a schema-valid yet timeline-incomplete output.

---

## When it applies (triggers)

**MANDATORY on any time-indexed output:**

- `highlights[]` (field `timeSec`)
- `milestones[]` (fields `startSec`/`endSec`)
- `attentionMoments[]` (field `timestampSec`)
- `transcript.segments[]` (fields `start`/`end`)
- minute-summary arrays (field `minuteIndex` or `startSec`)
- `brief` (as an object with `keyMoments[]` or `chapters[]`)
- any LLM-generated structured output that has a time field and a known source duration
- any output you are about to describe as "X% coverage" / "covers full N minutes" / "the whole recording is analyzed"

**MANDATORY on text outputs:**
- `transcript.fullText` — check `length / durationSec` against a historical baseline (e.g. ~8-15 chars/sec for continuous speech). If the ratio drops below 4 — truncation.
- `brief.summary` — check that the summary mentions events from the last quarter of the recording (at least one timestamp > 0.75 * durationSec).

**Does NOT apply:**
- Output with no time axis (theme classification, language detection, single-number metrics)
- A single-event output (at 1:30 the user said X) — coverage is not measurable
- The stakeholder explicitly said "this is the first half / partial processing / preview"

---

## Protocol

### Step 1 — before generation, capture the source durationSec

Before the LLM / pipeline call:

```ts
const durationSec = recording.durationSec; // or audioFile.durationSec, or video.metadata.duration
console.log(`[coverage:input] ${recording.id}: source duration ${durationSec}s (${Math.round(durationSec/60)}min)`);
```

If `durationSec === null` / undefined — **that is already a red flag**. Without a known duration you cannot assert coverage; log `console.warn` and continue with an explicit "coverage unverifiable".

### Step 2 — after output returns, compute min/max timeSec

```ts
const min = Math.min(...items.map(x => x.timeSec));
const max = Math.max(...items.map(x => x.timeSec));
```

For multi-field structures (milestones with startSec/endSec) — take `min` of `startSec` and `max` of `endSec`.

### Step 3 — log coverage_ratio

```ts
const ratio = (max - min) / durationSec;
console.log(`[coverage] ${label}: ${items.length} items, range ${Math.round(min)}-${Math.round(max)}s / ${Math.round(durationSec)}s (${(ratio*100).toFixed(0)}%)`);
```

This log should land in a structured log / breadcrumb, so that during an incident you can grep for `[coverage]` and find every recording with a suspicious ratio.

### Step 4 — emit a warning on suspicious coverage

Condition:
- `coverage_ratio < 0.8` (output covered less than 80% of the timeline)
- AND `durationSec > 10*60` (recording longer than 10 minutes — on short recordings the LLM may legitimately give 1 highlight)

→ `console.warn` with full context (recordingId, durationSec, min, max, items.length, label). This goes to an alert.

Additional heuristic for very short outputs:
- `items.length < Math.ceil(durationSec / 600)` (fewer than 1 item per 10 minutes) → also warn.

### Step 5 — before reporting to a stakeholder, quote the real range

**Never:**
> "16 highlights, full coverage of 49:45"

**Always:**
> "16 highlights, range 00:14 – 31:29 (63% of 49:45). Suspicious — the last 18 minutes are not covered. Investigating."

If ratio > 0.95 — you may say "coverage is complete". If 0.8-0.95 — "coverage is nearly complete, last highlight at M:SS of N:NN". If <0.8 — do NOT claim done; go find the cause.

The numbers come from the DB or a log — not a bullet count and not a "subjective sense that it's fine".

---

## Anti-patterns (do NOT do this)

- ❌ **Reporting "N highlights" as evidence of coverage.** `items.length` says nothing about distribution across the timeline. 16 highlights can all sit in the first minute.
- ❌ **Trusting an LLM `responseSchema` array length without a timeSec range check.** Models honor `minItems`/`maxItems` but do not guarantee time distribution. They fill items from whatever part of the prompt they reached.
- ❌ **Assuming truncation caps won't silently trigger.** `BRIEF_MAX_CHARS`, `MAX_PROMPT_TOKENS`, `MAX_CHUNK_SIZE`, batch slicing — all these constants exist and fire silently. If a cap exists, assume it fired; prove otherwise.
- ❌ **Asserting coverage based on `status=DONE` alone.** `status=DONE` means "the pipeline ran without an exception", not "the output is correct". Different things.
- ❌ **"Smoke test on a 5-minute recording" → claim ready for prod.** Truncation caps trigger on long recordings (30+ min); a short smoke test won't reproduce them. Test on a >30 min recording before "done".
- ❌ **Grep "coverage" in logs, find nothing → say "all good".** If the skill isn't integrated and the `[coverage]` log is absent, that means the assertion was never written — not "verified ok".

---

## Examples

### Example A — Brief generation via chunked LLM calls

**Before (broken):**
```ts
const transcriptText = transcript.fullText.slice(0, BRIEF_MAX_CHARS); // 200_000
const result = await llm.generateContent({
  contents: [{ role: 'user', parts: [{ text: brief_prompt(transcriptText) }] }],
  generationConfig: { responseSchema: HIGHLIGHTS_SCHEMA, responseMimeType: 'application/json' }
});
const highlights = JSON.parse(result.response.text()).highlights;
// silently: on a 49-min recording fullText.length = 380_000, the slice cut at 31:29
console.log(`Generated ${highlights.length} highlights`); // 16
return { highlights }; // stakeholder sees 16, you say "full coverage"
```

**After (fixed):**
```ts
console.log(`[coverage:input] ${recording.id}: durationSec=${durationSec}, fullText.length=${transcript.fullText.length}`);

const highlights = await generateHighlightsChunked(transcript, durationSec);
// chunked: split transcript into overlapping chunks of 60_000 chars, one LLM call each,
// then merge + dedupe + sort by timeSec

assertCoverage(highlights, durationSec, 'highlights');
// emits [coverage] highlights: 16 items, range 14-2989s / 2985s (100%)
// if there were truncation: [coverage] highlights: SUSPICIOUS — coverage 63% < 80% on 49min input

return { highlights };
```

### Example B — Transcript fullText coverage check

```ts
function assertTranscriptCoverage(transcript: { fullText: string; segments: { end: number }[] }, durationSec: number) {
  const lastSegmentEnd = transcript.segments.length
    ? Math.max(...transcript.segments.map(s => s.end))
    : 0;
  const segmentRatio = lastSegmentEnd / durationSec;
  const charsPerSec = transcript.fullText.length / durationSec;

  console.log(`[coverage:transcript] last segment ${Math.round(lastSegmentEnd)}s / ${Math.round(durationSec)}s (${(segmentRatio*100).toFixed(0)}%), density ${charsPerSec.toFixed(1)} chars/sec`);

  if (segmentRatio < 0.95 && durationSec > 60) {
    console.warn(`[coverage:transcript] SUSPICIOUS — segments cover only ${(segmentRatio*100).toFixed(0)}% of recording. Possible transcription truncation or early-stop.`);
  }
  if (charsPerSec < 4 && durationSec > 300) {
    console.warn(`[coverage:transcript] SUSPICIOUS — density ${charsPerSec.toFixed(1)} chars/sec is low for continuous speech (expected 8-15). Possible silent gap or transcription failure.`);
  }
}
```

---

## Ready-to-use inline assertion (TypeScript)

Drop into a shared utils module and import into every pipeline step that returns time-indexed output:

```ts
export function assertCoverage(
  items: { timeSec: number }[],
  durationSec: number,
  label: string,
): void {
  if (items.length === 0) {
    console.warn(`[coverage] ${label}: empty output for ${durationSec}s input`);
    return;
  }
  const min = Math.min(...items.map(x => x.timeSec));
  const max = Math.max(...items.map(x => x.timeSec));
  const ratio = (max - min) / durationSec;
  console.log(
    `[coverage] ${label}: ${items.length} items, range ${Math.round(min)}-${Math.round(max)}s / ${Math.round(durationSec)}s (${(ratio * 100).toFixed(0)}%)`,
  );
  if (ratio < 0.8 && durationSec > 600) {
    console.warn(
      `[coverage] ${label}: SUSPICIOUS — coverage ${(ratio * 100).toFixed(0)}% < 80% on ${Math.round(durationSec / 60)}min input. Possible truncation.`,
    );
  }
}
```

For milestones (startSec/endSec) — a separate helper:

```ts
export function assertRangeCoverage(
  items: { startSec: number; endSec: number }[],
  durationSec: number,
  label: string,
): void {
  if (items.length === 0) {
    console.warn(`[coverage] ${label}: empty output for ${durationSec}s input`);
    return;
  }
  const min = Math.min(...items.map(x => x.startSec));
  const max = Math.max(...items.map(x => x.endSec));
  const ratio = (max - min) / durationSec;
  console.log(
    `[coverage] ${label}: ${items.length} items, range ${Math.round(min)}-${Math.round(max)}s / ${Math.round(durationSec)}s (${(ratio * 100).toFixed(0)}%)`,
  );
  if (ratio < 0.8 && durationSec > 600) {
    console.warn(
      `[coverage] ${label}: SUSPICIOUS — coverage ${(ratio * 100).toFixed(0)}% < 80% on ${Math.round(durationSec / 60)}min input. Possible truncation.`,
    );
  }
}
```

---

## Success metric

This skill works if:

1. **Zero false coverage claims for the next several cycles.** Every coverage statement quotes a real numeric range from the DB or a log, not a bullet count.
2. **`console.warn [coverage]` fires on truncation and is visible in alerting.** If there's no warn in 30 days — either the assertion isn't integrated (bad) or there really is no truncation (good). Re-verify with a targeted test (a recording >40 minutes).
3. **On a regression, the fix takes under 2 hours** — because the log shows recordingId + ratio directly; no reverse-engineering "why does it feel short".

---

**Success criterion in one line:** before any "full coverage" statement, the log must contain a fresh line `[coverage] <label>: N items, range X-Y s / Z s (P%)` with P >= 95.
