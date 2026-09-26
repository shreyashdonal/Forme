# LevelUp — Notes Generation Prompt

Paste this (once, or whenever you want notes for a session) instead of re-uploading a
previous notes file as a format reference. It fully describes the format on its own.

---

Generate beginner-friendly notes for this session, covering everything we just built and
discussed. Follow this exact format:

## Chapter Numbering — Two Separate Tracks

- Backend and frontend sessions are numbered **independently**. Check PROGRESS.md's
  "Notes chapter tracking" section for the current count of each before naming the file.
- Backend notes: `LevelUp-chapterN-notes.md` (lowercase "chapter")
- Frontend notes: `LevelUp-ChapterN-Frontend.md` (capital "Chapter", "-Frontend" suffix)
- A session that touches both in one sitting gets two separate files, one per track, each
  incrementing its own track's counter.
- After generating notes, update PROGRESS.md's "Notes chapter tracking" line for whichever
  track was used, so the next session knows the current count without guessing.

## Structure

- Number top-level sections for each major topic covered this session: `## 1) Topic Name`,
  `## 2) Topic Name`, etc.
- Under each, use `###` subsections as needed — most topics follow this pattern:
  - `### X.1 The Problem` — why this exists / what issue it solves, in plain terms
  - `### X.2 The Code` (or a descriptive name like "The Recipe" / "Breaking It Down") —
    the actual code/SQL/command, then an explanation of each meaningful part
  - A **Rule:** callout for any hard-and-fast rule worth remembering, in bold, as its own line
  - A **Why?** callout (bold, own line) followed by 1-3 sentences explaining the reasoning —
    not just *what* the code does, but *why* it's built that way instead of some simpler or
    more obvious alternative
- Separate each numbered section with a horizontal rule (`---`).

## Tone and depth

- Written for a beginner — explain concepts as if this is new, don't assume prior
  knowledge beyond what earlier sessions' notes already covered (within the same track —
  backend notes assume backend history, frontend notes assume frontend history).
- Every code snippet gets a plain-English walkthrough of what each meaningful line does —
  not just "this connects to the database" but *how* and *why* that line specifically.
- Prefer short, direct sentences over dense paragraphs.
- Include short "wrong vs. right" contrast blocks (❌ / ✅) when a concept is commonly
  misunderstood or confused with something similar.

## Content scope

- Cover only what was actually built, decided, or debugged in the session just finished —
  new code, new concepts explained, decisions made, and any real troubleshooting that
  happened (with what the symptom was, what the actual cause turned out to be, and the
  general lesson — not just "it works now").
- Don't re-explain concepts already covered in a previous session's notes on the same
  track — reference them briefly instead (e.g. "see Chapter 1, Section 7.3") rather than
  repeating the explanation.

## Output

- Save as a new file, named per the "Chapter Numbering" rules above.
- Title each numbered section clearly enough that someone could scan just the headers and
  know what the session covered.
- At the very end of the file, after all sections, add a final section titled
  `## Topics Covered in This Chapter` — a flat list of every numbered section and its
  subsections from this chapter, e.g.:
  ```
  ## Topics Covered in This Chapter

  1) Topic Name
     - 1.1 The Problem
     - 1.2 The Code
  2) Topic Name
     - 2.1 The Problem
     - 2.2 The Fix
     - 2.3 Some Other Subsection
  ```
  This acts as a quick index/summary of the chapter — generate it last, once all sections
  above it are finalized, so it accurately reflects everything actually included.

## Example of the expected style (from Chapter 1)

```
## 6) Password Hashing (bcrypt)

### 6.1 The Problem

- You must **never** store a user's actual password in the database. If your database ever
  leaked, every user's real password would be exposed.

### 6.2 The Fix — Hashing

​```js
const passwordHash = await bcrypt.hash(password, 10);
​```

- **Hashing** turns "password123" into a long scrambled string. This process is **one-way**
  — there is no function that turns the hash back into the original password.
- The `10` is the "cost factor" — roughly, how many times the algorithm scrambles the data.

**Rule:** you can hash a password; you can never un-hash one. Login always works by
comparing, never by reversing.
```

Match that density and tone — not shorter, not more casual.
