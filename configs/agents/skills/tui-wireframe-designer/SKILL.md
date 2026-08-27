---
name: tui-wireframe-designer
description: >-
  Advanced TUI (Terminal User Interface) wireframe and interaction flow rendering engine.
  Transforms UI concepts, responsive wireframes (PC: 80ch, Tablet: 56ch, Smartphone: 32ch),
  and multi-step user navigation flows (Flow: 120ch) into strictly aligned Unicode box-drawing
  diagrams with Nerd Fonts (v3.x) glyphs. Use when designing CLI layouts, terminal dashboards,
  responsive text wireframes, or ascii/unicode UX flows. Do not use for frontend HTML/CSS/SVG code.
---

# TUI Wireframe & User Flow Design Engine

An enterprise-grade layout and rendering engine that converts interface specifications, wireframe ideas, and interaction architectures into mathematically aligned Unicode Box-Drawing diagrams.

## Engine Metadata
- **Engine**: TUI Flexbox & Flow Engine v6.0-Enterprise
- **Target Environment**: Nerd Fonts (v3.x) & Monospace Terminals (UTF-8)
- **Output Target**: Single ```text code block with zero external conversational chatter

---

## 🔒 1. Output Contract (Strict Invariants)

Every response generated under this engine MUST adhere to these three inviolable rules:

1. **OUTPUT ENCLOSURE**: Generate **ONLY** a single ````text ```` code block.
2. **NO EXTERNAL TEXT**: Omit greetings, intros, conversational preambles, notes, and post-explanations (Zero conversational tokens outside the block).
3. **ABSOLUTE ALIGNMENT**: The rightmost border character `│` (or corner `┐`, `┘`, `┤`) **MUST land on Column W for EVERY single line without exception**.

---

## 📐 2. Canvas Specifications

Set the Canvas Target Width ($W$) based on requested layout mode:

| Mode | Canvas Target Width ($W$) | Primary Layout Purpose | Default Column Split |
| :--- | :---: | :--- | :--- |
| **PC Mode** | **$W = 80\text{ ch}$** | Multi-column, side-by-side flex layouts, admin consoles | Sidebar (20ch) + Main (58ch) |
| **Tablet Mode** | **$W = 56\text{ ch}$** | Condensed 2-column or stacked card layouts | Equal split (26ch + 26ch) |
| **SP Mode** | **$W = 32\text{ ch}$** | Smartphone single-column vertical stack, mobile navigation | Single vertical stack (30ch) |
| **User Flow Mode** | **$W = 120\text{ ch}$** | Multi-step user navigation flows, wizard state machines | Multi-box horizontal transitions |

---

## 🧮 3. Grid Arithmetic & Alignment Algorithm

To ensure mathematical precision and prevent ragged borders, compute exact display widths before appending the right-hand border:

### Character Width Table

| Character Category | Unicode Range / Sample | Monospace Column Width |
| :--- | :--- | :---: |
| **Half-width ASCII** | `a-z`, `0-9`, spaces, `[`, `]`, `<`, `>`, `(`, `)`, `{`, `}`, `|` | **$1\text{ ch}$** |
| **Nerd Font v3 Glyphs** | PUA (`\uF1B2`, `\uF002`, `\uF007`, `\uF023`, `\uF0F3`, `\uF013`, `\uF04B`, `\uF061`, etc.) | **$1\text{ ch}$** |
| **Box-Drawing & Blocks** | `┌`, `┐`, `└`, `┘`, `├`, `┤`, `┬`, `┴`, `┼`, `─`, `│`, `╭`, `╮`, `╯`, `╰` | **$1\text{ ch}$** |
| **Full-width CJK** | Japanese Kanji (`漢字`), Hiragana (`あ`), Katakana (`ア`), Fullwidth symbols (`【`, `】`, `、`, `。`) | **$2\text{ ch}$** |
| **East Asian Ambiguous** | Japanese Symbols (`※`, `…`, `★`, `☆`, `▲`, `▼`, `◆`, `◇`, `○`, `●`, `“`, `”`, `　`全角スペース) | **$2\text{ ch}$** (in CJK/NF fonts) |
| **Emojis & Pictographs** | `🚀`, `💡`, `🔥`, `🎉` (U+1F300..U+1FAFF) | **$2\text{ ch}$** |

### Mathematical Equation per Line

$$\text{Line\_Content\_Width} = (\text{Count\_ASCII} \times 1) + (\text{Count\_Glyphs} \times 1) + (\text{Count\_Box} \times 1) + (\text{Count\_CJK/Ambiguous} \times 2)$$

$$\text{Required\_Padding\_Spaces} = W - 2 - \text{Line\_Content\_Width}$$

### Multi-Column Flexbox Partitioning Rule
When dividing an internal layout into two columns with an internal divider `│`:
$$\text{Col}_1\text{\_Width} + 1\text{ (Divider)} + \text{Col}_2\text{\_Width} = W - 2$$
Every row in that container MUST ensure $\text{Col}_1\text{\_Width}$ is constant to avoid bent/jagged vertical dividers.

### Border Closure Rule
Each internal line MUST start with `'│'`, contain the content, pad with exactly `Required_Padding_Spaces` half-width spaces (`' '`), and terminate with `'│'`.

```text
│<─── Content (Line_Content_Width ch) ───><─── Padding Spaces (Required_Padding_Spaces ch) ───>│  <-- Total W
```

---

## 🔣 4. Semantic Glyphs & Component Grammar

Render UI controls using exact literal Nerd Font characters (see [references/glyph-dictionary.md](./references/glyph-dictionary.md) for full catalog):

| UI Semantic Control | Visual Notation | Meaning & Usage |
| :--- | :--- | :--- |
| **Brand / Header Logo** | ` MyApp` (`\uF1B2`) | Application logo and brand identifier |
| **Search / Filter Input** | `<  Search users... >` (`\uF002`) | Text search input with label |
| **User Profile Badge** | `(  John Doe )` (`\uF007`) | Logged-in user badge, avatar chip |
| **Password / Secure Field** | `<  Password >` (`\uF023`) | Security / masked input field |
| **Notification Alert** | `{  3 New }` (`\uF0F3`) | Notification counter, unread alert |
| **Settings / Config** | `(  Settings )` (`\uF013`) | Configuration and preferences trigger |
| **Primary CTA Button** | `[  Deploy Now ]` (`\uF04B`) | Accentuated primary call-to-action |
| **Secondary Button** | `( Cancel )` | Ghost / outlined alternative button |
| **Checkbox (Checked/Unchecked)** | `[] Enabled` (`\uF14A`) / `[] Disabled` (`\uF0C8`) | Toggle checkbox item |
| **Radio Option** | `(•) Annual Plan` / `( ) Monthly Plan` | Mutually exclusive radio selector |
| **Media / Asset Viewport** | `[~  Hero Graphic ~]` (`\uF03E`) | Image, chart, or canvas placeholder |
| **Analytics / Chart Card** | `[  Weekly Sales: $12k ]` (`\uF080`) | Metric display tile |
| **Status Badge / Tag** | `{  Active }` (`\uF00C`) / `{  Error }` | State indicator chip |
| **Mobile Hamburger Menu** | `[  Menu ]` (`\uF0C9`) | Condensed navigation trigger for SP/Tablet |
| **Flow Action Transition** | `───  ( Action: Click ) ───>` (`\uF061`) | Page transition / navigation step |
| **Modal Window Container** | `┌─[  Modal: Title ]─────┐` | Nested or adjacent dialog window |

For detailed component patterns (headers, navbars, sidebars, forms, dialogs), refer to [references/component-patterns.md](./references/component-patterns.md).

---

## ⚡ 5. Execution Protocol (Step-by-Step)

Follow this 5-step procedure on every diagram request:

1. **Step 1: Identify Canvas Mode & Fix Target Width ($W$)**
   - Check if prompt specifies PC ($W=80$), Tablet ($W=56$), Smartphone ($W=32$), or User Flow ($W=120$).
   - Default to PC ($W=80$) if unspecified.

2. **Step 2: Partition Flexbox Grid Structure**
   - Design the horizontal layout slices (Top Header $\to$ Main Flex Container $\to$ Footer Action Bar).
   - Divide internal panels using single-line box characters (`┌─┬─┐`, `│ │ │`, `├─┼─┤`, `└─┴─┘`).

3. **Step 3: Insert Component Semantics**
   - Place buttons (`[  ... ]`), inputs (`<  ... >`), badges (`{ ... }`), and literal glyphs (``, ``, ``, etc.).

4. **Step 4: 1-Shot AutoFit & Deterministic Alignment (Fastest & Rock-Solid)**
   - Run the high-speed helper script in **a single command**:
     ```bash
     python scripts/tui_box_helper.py autofit --mode pc [--split 45,32] --file draft.txt
     ```
   - AutoFit automatically detects multi-column dividers (`│`), titled box borders (`┌─[ Title ]──┐`), applies safe truncation with `...` if overflowing, and forces **every single line to exactly $W$ columns in under 15ms**.
   - Built-in UI generators:
     - Sliders: `python scripts/tui_box_helper.py slider --val 2038 --min 2026 --max 2094 --width 76 --label-left "2026 (32歳)" --label-right "2094 (100歳)"`
     - Progress Bars: `python scripts/tui_box_helper.py progress --val 65 --max 100 --width 20`

5. **Step 5: Emit Single Text Block (Output Contract Enforcement)**
   - Output the wireframe enclosed strictly in ````text ```` without any surrounding prose.

---

## ⚠️ 6. Anti-Patterns & Common Failure Modes

| Anti-Pattern | Why It Fails | Strict Remedy |
| :--- | :--- | :--- |
| **Visual Space Eyeballing** | LLMs cannot "see" monospace padding; right border becomes jagged and misaligned. | **Always run `tui_box_helper.py pad`** or strictly compute arithmetic equation. |
| **Ambiguous Unicode Glyphs (`※`, `★`, `…`)** | `East_Asian_Width = A` varies between browser font (1ch) and terminal font (2ch), causing unpredictable right-border rupture. | **Ban ambiguous glyphs**. Use `...` (ASCII dots), `[注]` / `{  }`, and `[重要]`. |
| **CJK Single-Width Assumption** | Japanese Kanji/Kana rendered as 1 column will cause the right border to push 1-10 columns past $W$. | Count all CJK glyphs as **2 columns** ($2\text{ ch}$). |
| **Conversational Preamble / Epilogue** | Adding "Here is your wireframe:" violates Output Contract Rule 2. | **Zero conversational tokens**. Output ONLY the text block. |
| **ASCII Icon Degradation** | Replacing `` with `[Search]` wastes space and loses TUI aesthetic fidelity. | Use **literal Nerd Font v3 glyphs** (``, ``, ``, ``, etc.). |
| **Broken Box Intersections** | Using `┌───┬───┐` at top but `├───┴───┤` at next divider without matching column alignment. | Ensure vertical divider column index is consistent across all intersecting rows. |

---

## 🛠️ 7. Deterministic Alignment Helper Tool

When running within an environment with terminal execution capabilities, use the bundled Python tool [scripts/tui_box_helper.py](./scripts/tui_box_helper.py):

```bash
# Validate an existing diagram file against target width (e.g. 80ch)
python scripts/tui_box_helper.py validate --mode pc --file wireframe.txt

# Automatically pad raw content lines to exact width
python scripts/tui_box_helper.py pad --mode pc --file raw_content.txt

# Wrap raw lines into a complete titled box
python scripts/tui_box_helper.py frame --mode pc --title " Dashboard" --file content.txt
```

---

## 📚 8. Progressive Reference Links

- **Glyph Reference**: [references/glyph-dictionary.md](./references/glyph-dictionary.md) (All Unicode escapes & glyphs)
- **Component Patterns**: [references/component-patterns.md](./references/component-patterns.md) (Navbars, forms, sidebars, modals)
- **PC Mode Reference (W=80)**: [examples/pc-dashboard.md](./examples/pc-dashboard.md)
- **Tablet Mode Reference (W=56)**: [examples/tablet-two-column.md](./examples/tablet-two-column.md)
- **SP Mode Reference (W=32)**: [examples/sp-mobile-stack.md](./examples/sp-mobile-stack.md)
- **User Flow Reference (W=120)**: [examples/user-flow-diagram.md](./examples/user-flow-diagram.md)
