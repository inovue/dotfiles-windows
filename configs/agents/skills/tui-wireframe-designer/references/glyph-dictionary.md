# Nerd Fonts (v3.x) Semantic Glyph Dictionary

This reference catalog defines the semantic mapping, Unicode escape codes, literal glyphs, and visual monospace widths for the TUI layout engine.

## Core Glyph Dictionary (Specification v3)

All glyphs listed here occupy **exactly 1 character column (1 ch)** in monospace terminal environments with Nerd Fonts (v3.x).

| Semantic Category | Unicode Escape | Literal Glyph | Visual Width | Usage & UI Context | Example Syntax |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **Brand / Logo** | `\uF1B2` |  | 1 ch | Application header logo, product brand icon | ` MyApp` |
| **Search / Filter** | `\uF002` |  | 1 ch | Search input prompt, filter bar, query box | `<  Search users... >` |
| **User / Profile** | `\uF007` |  | 1 ch | User account, avatar badge, auth status | `(  John Doe )` |
| **Lock / Security** | `\uF023` |  | 1 ch | Password input, secure badge, modal guard | `<  Password >` |
| **Notification** | `\uF0F3` |  | 1 ch | Alerts, unread notification counter, bell | `{  3 Alerts }` |
| **Settings / Gear** | `\uF013` |  | 1 ch | Preferences, config menu, options button | `(  Settings )` |
| **Primary / Play** | `\uF04B` |  | 1 ch | Primary call-to-action (CTA), start, run | `[  Deploy Now ]` |
| **Arrow Right** | `\uF061` |  | 1 ch | User flow transition, breadcrumbs, forward | `───  ( Click ) ───>` |
| **Image / Asset** | `\uF03E` |  | 1 ch | Image placeholder, thumbnail, canvas media | `[~  Banner Image ~]` |
| **Chart / Analytics** | `\uF080` |  | 1 ch | Metrics card, analytics view, dashboard | `[  Weekly Sales ]` |
| **Check (Inline)** | `\uF00C` |  | 1 ch | Success badge, completed status indicator | `{  Active }` |
| **Checked Box** | `\uF14A` |  | 1 ch | Selected checkbox, enabled toggle item | `[] Enable 2FA` |
| **Unchecked Box** | `\uF0C8` |  | 1 ch | Unselected checkbox, empty toggle item | `[] Remember me` |
| **Mobile Menu** | `\uF0C9` |  | 1 ch | Hamburger menu for SP/Tablet headers | `[  Menu ]` |

---

## Extended Semantic Glyphs (Common UI Controls)

| Semantic Category | Unicode Escape | Literal Glyph | Visual Width | Usage & UI Context |
| :--- | :--- | :---: | :---: | :--- |
| **Star / Favorite** | `\uF005` |  | 1 ch | Rating, pinned item, bookmark |
| **Refresh / Sync** | `\uF021` |  | 1 ch | Reload button, sync status |
| **Trash / Delete** | `\uF1F8` |  | 1 ch | Destructive CTA, delete icon |
| **Edit / Modify** | `\uF040` |  | 1 ch | Edit action, inline update pencil |
| **Folder** | `\uF07B` |  | 1 ch | Directory navigation, project tree |
| **File** | `\uF15B` |  | 1 ch | Document, log viewer, file item |
| **Terminal / CLI** | `\uF120` |  | 1 ch | Shell window, console prompt, logs |
| **Database** | `\uF1C0` |  | 1 ch | DB connection, data storage indicator |
| **Server / Host** | `\uF233` |  | 1 ch | Host status, cluster node |
| **Warning** | `\uF071` |  | 1 ch | Caution tag, non-fatal alert |
| **Error / Danger** | `\uF057` |  | 1 ch | Failed state, error chip, validation alert |
| **Info** | `\uF05A` |  | 1 ch | Tooltip, informational helper |
| **Help / FAQ** | `\uF059` |  | 1 ch | Help modal, question mark |
| **Calendar / Date** | `\uF073` |  | 1 ch | Date picker, scheduling input |
| **Clock / Time** | `\uF017` |  | 1 ch | Timestamp, elapsed duration |
| **Caret Down** | `\uF0D7` |  | 1 ch | Select dropdown trigger |
| **Caret Up** | `\uF0D8` |  | 1 ch | Collapsible accordion closed |
| **Caret Right** | `\uF0DA` |  | 1 ch | Sub-menu indicator, expandable tree |
| **Arrow Left** | `\uF060` |  | 1 ch | Back button, previous page |

---

## Character Width Invariant Rules

1. **ASCII Characters (`0x20` - `0x7E`)**: Weight = **1 ch**
2. **Nerd Font PUA Glyphs (`U+E000` - `U+F8FF`, `U+F0000` - `U+FFFFD`)**: Weight = **1 ch**
3. **East Asian Fullwidth / CJK (Kanji, Hiragana, Katakana, Fullwidth punctuation)**: Weight = **2 ch**
4. **Unicode Box-Drawing (`U+2500` - `U+257F`)**: Weight = **1 ch**
