# Typee Design System & UI Specification

A complete guide to the visual language, color palette, typography, and component patterns of **Typee**. Use this specification as the single source of truth when designing and building new pages, features, and UI components to preserve the warm, low-fatigue, terminal-inspired aesthetic.

---

## 1. Design Philosophy

- **Warm Dark Minimalism**: Rather than cold, sterile obsidian blues (`#0d1117`), Typee uses an earthy, warm charcoal (`#151513`) with subtle olive/sand undertones. This dramatically reduces eye fatigue during extended typing sessions.
- **Coder & Terminal Heritage**: Clean typography pairing high-legibility geometric sans-serif (`Inter`) for prose with a warm, technical monospace (`IBM Plex Mono`) for keycaps, code, metrics, and commands.
- **Tactile Hardware Metaphors**: Keycaps feature subtle 3D inner bevels (`inset 0 -3px 0 rgba(0,0,0,0.18)`) and tactile home-row bumps mimicking physical mechanical keyboards.
- **Zero Layout Shift (CLS)**: Critical dynamic feedback elements (such as mistake hints) occupy fixed min-heights even when idle so the typing interface never bounces or shifts beneath the user's gaze.
- **High-Contrast Semantic Color Mapping**: Every accent or finger color is paired with a carefully calibrated dark text tone so that every label maintains AA/AAA legibility standards.

---

## 2. Color Palette & Design Tokens

### 2.1 Core Base Tokens

```css
:root {
  /* Surfaces & Backgrounds */
  --bg: #151513;        /* Base canvas background (warm obsidian) */
  --panel: #1E1E1B;     /* Primary container/card surface */
  --panel-2: #202019;   /* Secondary surface (picker buttons, inputs) */
  --panel-mod: #26261F; /* Keyboard modifier keys, progress tracks */

  /* Text & Foreground */
  --text: #EAE6DD;      /* Primary text (warm bone white) */
  --muted: #8A8578;     /* Secondary text, inactive states, labels */
  --muted-2: #5F5E5A;   /* Lowest-emphasis text, footers, hints */

  /* Borders & Dividers */
  --border: #2A2A24;    /* Default borders, card outlines, grid dividers */
  --border-hover: #3A3A32; /* Hovered border, focus rings, palm SVG fill */

  /* Accent & Status */
  --accent: #E8B04B;    /* Signature warm amber / marigold gold */
  --sage: #5B8C7B;      /* Soft sage green (accuracy, success) */
  --danger: #E24B4A;    /* Soft crimson red (typos, errors) */
}
```

| Token | Hex Code | Role & Usage |
| :--- | :--- | :--- |
| `--bg` | `#151513` | Full viewport background, primary button text color |
| `--panel` | `#1E1E1B` | Card backgrounds, typing container, insight panels |
| `--panel-mod` | `#26261F` | Non-typable modifier keys (Shift, Enter, Ctrl), progress tracks |
| `--text` | `#EAE6DD` | Primary headings, active tab text, correct typed letters |
| `--muted` | `#8A8578` | Subtitles, pending untyped letters, metric labels, inactive icons |
| `--muted-2` | `#5F5E5A` | Microcopy, footer notice, tertiary hints |
| `--border` | `#2A2A24` | 1px dividers, button borders, stat card grid gutters |
| `--border-hover` | `#3A3A32` | Secondary button hover, active focus outline, SVG palm base |
| `--accent` | `#E8B04B` | Primary CTAs, active nav indicators, cursor bar, center compass cell |
| `--sage` | `#5B8C7B` | Accuracy percentages, success states, correct target character in hint |
| `--danger` | `#E24B4A` | Mistake red letters, wrong key border, shake animation triggers |

---

### 2.2 Semantic Tint & Transparency Tokens

Used for overlays, badges, cursors, and error highlights:

| State | CSS Definition | Usage |
| :--- | :--- | :--- |
| **Error Flash / Typo** | `rgba(226, 75, 74, 0.15)` | Background on erroneous typed letters |
| **Error Cell Active** | `rgba(226, 75, 74, 0.25)` | Background on the mistake key in hint bar |
| **Error Border** | `rgba(226, 75, 74, 0.50)` | Border around wrong compass cell |
| **Hint Box Active** | `rgba(232, 176, 75, 0.08)` | Background of mistake hint when typo active |
| **Hint Border Active** | `rgba(232, 176, 75, 0.30)` | 1px border around active mistake banner |
| **Hint Box Idle** | `rgba(232, 176, 75, 0.04)` | Subtle background when idle / no typo |
| **Keycap Depth Shadow** | `inset 0 -3px 0 rgba(0,0,0,0.18)` | Bottom tactile edge on all full keyboard keys |
| **Keycap Hover Glow** | `0 0 0 2px rgba(234,230,221,0.4)` | Outline ring when hovering calibratable key |
| **Home-row Tactile Dot** | `rgba(0, 0, 0, 0.40)` | Physical raised dot on `F`, `J`, and home row |

---

### 2.3 The Touch-Typing 8-Finger Palette

Each finger assignment uses an expressive pastel background paired with an explicitly matched dark ink tone for optimal legibility:

```
Pinky (L/R)       Ring (L/R)       Middle (L/R)       Index (L/R)       Thumb
  #D4537E          #7F77DD          #5DCAA5           #EF9F27         #B4B2A9
  Rose             Indigo Slate     Seafoam Mint      Tangerine       Pewter Gray
  Text: #4B1528    Text: #26215C    Text: #04342C     Text: #412402   Text: #2C2C2A
```

| Finger | Background Hex | Contrast Text Hex | Assigned Standard Keys |
| :--- | :--- | :--- | :--- |
| **Left Pinky** | `#D4537E` | `#4B1528` | \`, 1, Q, A, Z |
| **Left Ring** | `#7F77DD` | `#26215C` | 2, W, S, X |
| **Left Middle** | `#5DCAA5` | `#04342C` | 3, E, D, C |
| **Left Index** | `#EF9F27` | `#412402` | 4, 5, R, F, V, T, G, B |
| **Right Index** | `#EF9F27` | `#412402` | 6, 7, Y, H, N, U, J, M |
| **Right Middle** | `#5DCAA5` | `#04342C` | 8, I, K, `,` |
| **Right Ring** | `#7F77DD` | `#26215C` | 9, O, L, `.` |
| **Right Pinky** | `#D4537E` | `#4B1528` | 0, -, =, P, [, ], ;, ', /, \ |
| **Thumbs** | `#B4B2A9` | `#2C2C2A` | Spacebar (`Space`) |

---

## 3. Typography & Text Hierarchy

### 3.1 Typefaces

Typee imports Google Fonts in [index.html](file:///D:/Coding/Project/Typeee/typee_work/index.html):
```html
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
```

- **Body & Prose Font**: `'Inter', sans-serif`
  - Weights: `400` (Regular), `500` (Medium), `600` (Semi-bold)
  - Applied to: Navigation bar links, descriptive paragraphs, card explanations, tooltips.
- **Mono / Data / Mechanical Font**: `'IBM Plex Mono', monospace`
  - Weights: `400` (Regular), `500` (Medium), `600` (Semi-bold), `700` (Bold)
  - Applied to: Brand logo (`Typee`), buttons, target practice text, keycaps, numerical stats (WPM, Acc), code samples, section labels.

### 3.2 Typography Scale

| Style / Element | Font Family | Size | Weight | Line Height | Color |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hero Title** | `IBM Plex Mono` | `44px` | 500 | 1.25 | `--text` |
| **Calibration Display Key**| `IBM Plex Mono` | `56px` | 700 | 1.0 | `--text` |
| **Target Practice Text** | `IBM Plex Mono` | `24px` | 400 | 1.8 | Pending: `--muted` / Typed: `--text` |
| **Stat Big Value** | `IBM Plex Mono` | `24px` | 400 | 1.0 | `--text` |
| **Section Heading (H2)**| `IBM Plex Mono` | `20px` | 500 | 1.3 | `--text` |
| **Card Heading (H3)** | `Inter` | `15px` | 500 | 1.4 | `--text` |
| **Body Standard** | `Inter` | `14px - 16px` | 400 | 1.55 - 1.6 | `--muted` or `--text` |
| **Primary Buttons** | `IBM Plex Mono` | `14px` | 500 | 1.0 | `--bg` on `--accent` |
| **Keycap Labels** | `IBM Plex Mono` | `15px - 16px` | 700 | 1.0 | `FINGER_TEXT` |
| **Section Label** | `IBM Plex Mono` | `12px` | 400 | 1.0 | `--muted` |
| **Badge / Subtext** | `IBM Plex Mono` | `11px - 12px` | 600 | 1.0 | `--muted` |

---

## 4. Spacing, Layout & Grid Architecture

### 4.1 Page Shell
- **Max Width**: `1040px` (centered via `margin: 0 auto;`).
- **Horizontal Page Padding**: `32px` (desktop), `16px` (mobile).
- **Bottom Clearance**: `80px` padding to breathe before footer.
- **Header Navigation**: `max-width: 1040px`, padding `28px 32px 0`.

### 4.2 Spacing Scale
- `4px - 8px`: Keycap gaps, badges, inline pill padding.
- `12px - 16px`: Button padding, input padding, step headers.
- `20px - 28px`: Card inner padding, stat cell padding.
- `32px - 48px`: Typing container padding (`padding: 48px 40px`), modal padding.
- `60px - 90px`: Major vertical section rhythms (e.g., hero padding, stat row margin-bottom).

### 4.3 The "1px Gap Grid" Technique
For connected stat cards (seen on Landing and Report pages):
```css
.stat-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 1px;                 /* 1px gap reveals the background underneath */
  background: var(--border);/* The background acts as crisp 1px borders */
  border-radius: 10px;
  overflow: hidden;
}
.stat-cell {
  background: var(--panel); /* Solid cell surface */
  padding: 20px 24px;
}
```
*Why this is used*: Avoids double-border thickness issues (`1px + 1px = 2px`) between adjacent cards and keeps grid corners smoothly rounded.

---

## 5. Component Patterns & Visual Standards

### 5.1 Buttons

#### Primary Action Button
- **Appearance**: Warm amber solid fill, dark charcoal mono text.
- **CSS**:
  ```css
  .btn-primary {
    font-family: 'IBM Plex Mono', monospace;
    background: var(--accent);
    color: var(--bg);
    border: none;
    padding: 13px 22px;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: opacity 0.15s ease;
  }
  .btn-primary:hover { opacity: 0.92; }
  ```

#### Secondary / Ghost Button
- **Appearance**: Transparent background with 1px `--border` outline, `--muted` text turning to `--text` with `#3A3A32` border on hover.
- **CSS**:
  ```css
  .btn-secondary {
    font-family: 'IBM Plex Mono', monospace;
    background: transparent;
    color: var(--muted);
    border: 1px solid var(--border);
    padding: 13px 22px;
    border-radius: 6px;
    font-size: 14px;
    cursor: pointer;
    transition: color 0.15s, border-color 0.15s;
  }
  .btn-secondary:hover {
    color: var(--text);
    border-color: #3A3A32;
  }
  ```

#### Segmented Toggle (e.g. Mode Switcher)
- Outer container: `border: 1px solid var(--border); border-radius: 6px; overflow: hidden; display: flex;`
- Unselected tab: `background: none; color: var(--muted); padding: 6px 14px;`
- Active tab: `background: var(--accent); color: var(--bg); font-weight: 500;`

---

### 5.2 Cards & Panels

- **Card Shell**:
  - Background: `var(--panel)` (`#1E1E1B`)
  - Border Radius: `12px`
  - Border: `1px solid var(--border)` (`#2A2A24`) or borderless if within section
  - Focus Ring: `box-shadow: 0 0 0 1px #3A3A32;`

---

### 5.3 Keycaps & Keyboard Geometry

#### Full Size Keycap (`.fullkey`)
- **Height**: `54px` (`42px` on tablet/mobile)
- **Border Radius**: `8px`
- **Typography**: `IBM Plex Mono`, `16px`, weight `700`
- **Bevel Shadow**: `box-shadow: inset 0 -3px 0 rgba(0,0,0,0.18)`
- **Modifier Keys (`.fullkey-mod`)**:
  - Background: `#26261F`
  - Text Color: `var(--muted)` (`#8A8578`)
  - Font Size: `11px`, weight `600`, letter spacing `0.02em`
- **Home Row Raised Dot**:
  - Position: `absolute; bottom: 6px; left: 50%; transform: translateX(-50%);`
  - Size: `5px x 5px`, `border-radius: 50%`
  - Fill: `rgba(0, 0, 0, 0.4)`

---

### 5.4 Typing Experience & Feedback Loop

#### Active Typing Box (`.type-box`)
- Background: `var(--panel)` (`#1E1E1B`)
- Border Radius: `12px`
- Focus State: `box-shadow: 0 0 0 1px #3A3A32`
- Text Rendering:
  - `.char-pending`: `color: var(--muted);` (untyped letters)
  - `.char-correct`: `color: var(--text);` (successfully typed letters)
  - `.char-wrong`: `color: var(--danger); background: rgba(226,75,74,0.15);` (errors)
  - `.char-cursor`: `border-bottom: 2px solid var(--accent);` (animated typing marker)

#### Shake Animation on Error
```css
@keyframes shake {
  0%, 100% { transform: translateX(0); }
  25% { transform: translateX(-4px); }
  75% { transform: translateX(4px); }
}
.target-text.shake { animation: shake 0.15s ease; }
```

#### Persistent Mistake Hint Box (`.mistake-hint`)
- Minimum Height: `172px` (ensures zero layout shift when switching between idle and error states)
- Active Error State:
  - Background: `rgba(232, 176, 75, 0.08)`
  - Border: `1px solid rgba(232, 176, 75, 0.3)`
  - Arrow color: `var(--accent)` (`#E8B04B`)
- Idle State:
  - Background: `rgba(232, 176, 75, 0.04)`
  - Border: `1px solid var(--border)`
  - Text: Italic, `var(--muted)` (`#8A8578`)

---

### 5.5 Compass Mode Component (Directional Grid)

A 3×3 mini-grid showing physical keyboard proximity:
- **Container**: `display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px;`
- **Cell Sizes**: Small (`28px`), Medium (`38px`), Large (`48px`) with `border-radius: 6px`
- **Cell Varieties**:
  - Neighbor: `background: #26261F; color: var(--muted);`
  - Target / Center: `background: var(--accent); color: var(--bg); font-weight: 700;`
  - Mistake / Wrong Hit: `background: rgba(226, 75, 74, 0.18); color: var(--danger); border: 1px solid rgba(226, 75, 74, 0.5);`

---

## 6. Quick Tailwind CSS Configuration

If implementing this theme in Tailwind CSS in future projects, merge this configuration:

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        bg: '#151513',
        panel: '#1E1E1B',
        'panel-2': '#202019',
        'panel-mod': '#26261F',
        text: '#EAE6DD',
        muted: '#8A8578',
        'muted-2': '#5F5E5A',
        border: '#2A2A24',
        'border-hover': '#3A3A32',
        accent: '#E8B04B',
        sage: '#5B8C7B',
        danger: '#E24B4A',
        finger: {
          pinky: '#D4537E',
          'pinky-ink': '#4B1528',
          ring: '#7F77DD',
          'ring-ink': '#26215C',
          middle: '#5DCAA5',
          'middle-ink': '#04342C',
          index: '#EF9F27',
          'index-ink': '#412402',
          thumb: '#B4B2A9',
          'thumb-ink': '#2C2C2A',
        },
      },
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'monospace'],
      },
      boxShadow: {
        keycap: 'inset 0 -3px 0 rgba(0,0,0,0.18)',
      },
      borderRadius: {
        card: '12px',
        key: '8px',
        btn: '6px',
      }
    },
  },
};
```

---

## 7. Future UI Creation Checklist

When designing or writing code for a new page/component:
1. [ ] **Backgrounds**: Root container uses `#151513`; card surfaces use `#1E1E1B`. Avoid pure black (`#000000`) or cool darks (`#0f172a`).
2. [ ] **Borders**: Always use `#2A2A24` for default dividing lines and card borders. On hover, lighten to `#3A3A32`.
3. [ ] **Accents**: Use `--accent` (`#E8B04B`) sparingly for primary actions, active tabs, and cursors. Do not overuse on secondary content.
4. [ ] **Font Pairing**: Monospace (`IBM Plex Mono`) for headers, buttons, numbers, code, and keycaps; Sans-serif (`Inter`) for readable body paragraphs and descriptions.
5. [ ] **Buttons**: Primary buttons are amber with dark text; secondary buttons are transparent with 1px border.
6. [ ] **Keycaps**: Always maintain the `inset 0 -3px 0 rgba(0,0,0,0.18)` shadow for the tactile physical key effect.
7. [ ] **Layout**: Keep content constrained to `1040px` with generous vertical spacing (`60px - 90px` between sections).
