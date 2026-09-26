# NPTEL Management System — Approach Comparison

> Two ways to build this, worked out over the last few sessions. This file exists so you
> can pick one deliberately instead of half-building both. `PROJECT_PLAN.md` /
> `PROGRESS.md` currently reflect **Approach A (PERN)** — if you pick B, those get
> rewritten for the PowerShell version instead.

---

## Approach A — PERN Web App

A real hosted web application. Students and the coordinator both use it directly through
a browser.

### Stack
- **Backend:** Node.js + Express
- **Database:** PostgreSQL, raw SQL via `pg` (no ORM)
- **Auth:** JWT + bcrypt — coordinator only, students use public forms (no login)
- **File uploads:** `multer`, receipt/confirmation-email files
- **OCR:** `tesseract.js` (pure JS/WASM, runs inside the Node process)
- **Frontend:** React (Vite) + React Router + plain CSS

### Free hosting (long-term, no trial, no card)
```
Frontend  → Netlify           (free forever; free tier explicitly allows
                                institutional/commercial use, unlike Vercel Hobby)
Backend   → Render free web service   (free forever; sleeps after 15 min idle,
                                        ~30-60s cold-start on next request)
Database  → Neon                      (free forever; NOT Render's own Postgres,
                                        which now expires after 30 days)
Files     → Supabase Storage          (free forever; receipts/confirmation emails —
                                        Render's free disk is wiped on every redeploy)
```
No cost, no expiry — the only real-world cost is a cold-start delay on the first request
after idle time. For a tool checked a few times a day, this is a minor annoyance.

### What it gives you
- Students fill real forms with live validation, on any device, no Google account needed
- Coordinator dashboard reachable from anywhere, not tied to one PC
- OCR + verification run automatically the moment a student submits
- One centralized database — cumulative sheet and reports are live queries, not manual
  joins across spreadsheets
- Matches the spec's original vision most closely (sections 27, 38 of `project.md`)

### What it costs you (in effort, not money)
- A real backend to build: ~9 tables/routes worth of logic, an auth system, a file-upload
  pipeline, an OCR pipeline, a verification engine — see `PROGRESS.md`'s full checklist
- More moving parts to keep working over time (4 separate free services, each with its
  own dashboard/limits to babysit)
- Cold-start delay is permanent, not a bug you fix later — it's inherent to free-tier
  hosting unless you eventually pay

### Best fit if
- You want this to look and feel like a real deployed system, not a personal tool
- You're comfortable maintaining a small multi-service stack
- The college might eventually want this to outlive you handing it off to someone else

---

## Approach B — PowerShell + WPF + Google Forms

No backend, no database, no hosting at all. Google Forms/Sheets does the data collection;
your local WPF app does the verification.

### Pipeline
```
Coordinator creates 3 Google Forms:
  1. Elective Selection
  2. Registration (structured fields + receipt upload + confirmation-email upload)
  3. Result Submission

Students fill forms  →  Google auto-writes 3 linked Sheets
                            +
                     uploaded files land in a Drive folder per form

Coordinator runs the WPF app  →  pulls sheet data + reads local synced Drive folder  →
                                  runs OCR + verification  →  shows exceptions +
                                  sends reminder emails
```

### Stack
- **App:** PowerShell + WPF/XAML (same pattern as your other desktop tools —
  Wall-E, TV Launcher, ScreenOCR, Productivity Tracker)
- **Data source:** Google Sheets, pulled via **published-to-web CSV URLs**
  (`Invoke-WebRequest` — no OAuth, no API keys, no Google Cloud project needed)
- **Files:** Google Drive for Desktop syncs the form's upload folder locally — the app
  just reads normal files, no Drive API
- **OCR:** Tesseract OCR CLI (`tesseract.exe`), called from PowerShell — simpler to wire
  up than Windows' built-in OCR WinRT API from PowerShell
- **Email:** Outlook COM automation (`New-Object -ComObject Outlook.Application`, no
  password needed, uses the coordinator's logged-in Outlook) or SMTP via a Gmail App
  Password — either works for both targeted "pending" reminders and one-click "email
  everyone" broadcasts
- **Roster diffing:** a maintained CSV of all enrolled students, so "did not register" is
  computable (Google Forms only tells you who *did* submit, never who didn't)

### Cost
$0, permanently, with no limits to hit at all — nothing is hosted anywhere. Google Forms/
Sheets/Drive free tier is generous enough that a single class's worth of data will never
come close to any cap.

### What it gives you
- Zero deployment, zero hosting accounts, zero cold-starts, zero services to babysit
- Fits your existing build style exactly — same PowerShell + WPF pattern as every other
  tool you've built
- Task Scheduler can run the reminder-email check daily/weekly with the app closed —
  fully automated without a server
- Nothing to break from a platform changing its free-tier terms (the risk Approach A
  carries with 4 different free services)

### What it costs you
- Google Forms file-upload questions require students to be signed into a Google account
  — fine if the college uses Google Workspace for students, a real blocker if it doesn't
- Registration and results live in separate sheets, joined by roll number inside the app
  at runtime, rather than one live database — works fine, just means every run re-does
  the join instead of a database doing it once
- Single coordinator, single PC — no concurrent multi-user access to the *app* itself
  (though any number of students can fill the forms simultaneously)
- Not reachable from a phone/browser the way a hosted dashboard would be — the
  coordinator has to be at that PC to run it (or have Task Scheduler running it headless)

### Best fit if
- You want something working with the least possible infrastructure risk
- The coordinator is fine with a desktop tool rather than a hosted dashboard
- You'd rather build in the style you already know (PowerShell/WPF) than take on a full
  Node/React/Postgres stack for a first "real" backend project

---

## Side-by-Side

| | PERN Web App | PowerShell + Forms |
|---|---|---|
| Hosting cost | $0 (4 free-tier services) | $0 (nothing hosted) |
| Setup complexity | High — backend, DB, auth, OCR, frontend | Low — one app, existing skillset |
| Where students submit | Custom web forms | Google Forms |
| Where coordinator works | Web dashboard, any device | Desktop app, one PC (or headless via Task Scheduler) |
| Data storage | Postgres (Neon) | Google Sheets |
| OCR | `tesseract.js` (in-process) | Tesseract CLI (external call) |
| Reminder emails | Would need a mail step added to the backend | Outlook COM / SMTP, already scoped (see chat above) |
| Long-term risk | 4 free tiers to monitor, terms can change | Google Forms/Sheets availability only |
| Feels like | A real deployed system | A personal automation tool |

---

## Decision

*(fill this in once you've picked — whichever one, `PROGRESS.md` should be rewritten to
match it before the next build session, so there's only one active plan.)*

**Chosen approach:** ⬜ A (PERN)  ⬜ B (PowerShell + Forms)

**Why:**
