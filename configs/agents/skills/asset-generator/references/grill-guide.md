# Visual Grill Protocol — Zero-Guessing Asset Alignment

> Inspired by **Matt Pocock's `/grill-me` tree-walking interview skill** and **Addy Osmani's design system principles**.

---

## ⚡ The 4 Failure Modes of AI Asset Generation

Why do generated images often fail expectations?
1. **Tone Mismatch**: The brand is a friendly medical app, but the AI generates neon cyberpunk icons.
2. **Color Incoherence**: The landing page uses subtle indigo & zinc, but the AI generates loud saturated yellow & red assets.
3. **Vague Metaphors**: For "Security", the user envisioned a golden shield & lock, but the AI generated a robotic CCTV camera.
4. **Semantic Drift**: A wordmark cell requested "FINANCIAL FANTASY" text but the model rendered a shield icon or single-letter monogram instead.
5. **Layout Collision**: The hero visual occupies the entire screen, leaving no negative space for the headline copy and CTA buttons.

---

## 🌲 The 4-Branch Visual Design Tree

Before generating any images, walk down this tree systematically.

```text
                      [Visual Asset Request]
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
 1. Brand Context        2. Style Preset        3. Motif & Metaphor     4. UI Composition
 (Codebase First)        (With Recommended)     (Concrete Details)      (Negative Space)
   - Primary colors        - 3D Clay / Glass      - Physical objects      - right-heavy (Hero)
   - Industry tone         - Flat / Isometric     - Colors & Materials    - centered (Cards)
```

---

## 📋 The 4 Golden Rules of Visual Grilling

1. **Codebase Exploration First (Do Not Ask Obvious Questions)**:
   - Before asking the user about colors or product description, inspect \`src/styles/global.css\` (tokens like \`--primary\`, \`--background\`) and \`src/data/site-config.ts\` or component copy.
   - Use discovered facts to seed your recommendations.

2. **Always Provide a Clear Recommendation (Prefix with (Recommended))**:
   - Don't ask open-ended questions like *"What style do you want?"*.
   - Ask structured multiple-choice questions with explicit rationales:
     - *(Recommended) Option A: 3D Clay (\`clay\`) — Friendly, approachable, matches your B2C SaaS audience.*
     - *Option B: 3D Glossy (\`glossy\`) — Apple/Fintech look with rich reflections.*

3. **Concrete Physical Metaphors (Never Use Abstract Words)**:
   - Break abstract concepts into concrete physical items:
     - ❌ "AI Automation" → ⭕ "A friendly 3D robot arm assembling modular blocks with glowing cyan joints"
     - ❌ "Fast Performance" → ⭕ "A miniature aerodynamic rocket launching from a glowing speedometer gauge"
     - ❌ "Data Security" → ⭕ "A chunky golden padlock surrounded by three floating translucent shield rings"

4. **Dry-Run Confirmation with \`--print-prompt\`**:
   - Write \`cells.json\` and pass \`--items @cells.json\` (never inline JSON on PowerShell).
   - Present the synthesized prompt; verify every \`[Row, Col]\` line before API calls.
   - CLI exits with error if cell count ≠ grid size (no silent fallback).
