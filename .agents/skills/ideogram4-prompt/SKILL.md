---
name: ideogram4-prompt
description: >
  Generate valid Ideogram 4 JSON prompts from natural language descriptions.
  Use when the user asks to create an image prompt for Ideogram 4, generate a
  JSON caption for text-to-image, convert a plain-text idea into an Ideogram 4
  structured prompt, or says anything about making/generating/creating an image,
  picture, illustration, poster, logo, artwork, or visual design for Ideogram 4.
  Also triggers on requests to "make me a picture", "generate an image", "create
  a prompt for", or "turn this into an Ideogram 4 caption". Always use this skill
  when the output needs to be a valid Ideogram 4 JSON caption.
---

Convert natural language image descriptions into valid Ideogram 4 JSON captions.
The model was trained exclusively on structured JSON — plain text prompts fail or
trigger safety filters.

## Schema

```
{
  "high_level_description": "1-2 sentence summary (optional but recommended)",
  "style_description": { ... },
  "compositional_deconstruction": { "background": "...", "elements": [ ... ] }
}
```

`compositional_deconstruction` is **required**. `background` must precede `elements`.

### `style_description` — strict key order

- **Photo:** `aesthetics` → `lighting` → `photo` → `medium` → `color_palette`
- **Non-photo:** `aesthetics` → `lighting` → `medium` → `art_style` → `color_palette`

Use exactly one of `photo` (photographic) or `art_style` (illustration, 3D, painting, etc.).
`color_palette` is optional but must be last if present.

| Field           | Type   | Example                                                 |
| --------------- | ------ | ------------------------------------------------------- |
| `aesthetics`    | string | `"moody, cinematic, desaturated"`                       |
| `lighting`      | string | `"golden hour, rim light, dramatic shadows"`            |
| `photo`         | string | `"35mm, f/1.4, bokeh"` (photo only)                     |
| `medium`        | string | `"photograph"`, `"illustration"`, `"3d_render"`, etc.   |
| `art_style`     | string | `"flat vector illustration, bold outlines"` (non-photo) |
| `color_palette` | list   | Up to 16 uppercase `#RRGGBB` hex colors                 |

### Element key order

- **obj:** `type` → `bbox` → `desc` → `color_palette`
- **text:** `type` → `bbox` → `text` → `desc` → `color_palette`

`bbox` and `color_palette` are optional per element (max 5 hex colors).

### Bounding boxes

`[y_min, x_min, y_max, x_max]` in 0–1000 normalized coords, origin top-left.

| Position | Bbox                    |
| -------- | ----------------------- |
| Center   | `[100, 100, 900, 900]`  |
| Upper    | `[50, 50, 400, 950]`    |
| Lower    | `[600, 50, 950, 950]`   |
| Left     | `[100, 0, 900, 450]`    |
| Right    | `[100, 550, 900, 1000]` |

Avoid overlapping bboxes unless elements genuinely overlap.

### Medium Reference

| User says                                           | `medium`           |
| --------------------------------------------------- | ------------------ |
| photo, photograph, realistic, cinematic, film       | `"photograph"`     |
| illustration, drawing, sketch, digital/concept art  | `"illustration"`   |
| retro, vintage, poster art, anime, manga, pixel art | `"illustration"`   |
| comic, graphic novel                                | `"illustration"`   |
| 3d, blender, cinema4d, octane, low-poly, voxel      | `"3d_render"`      |
| painting, oil, acrylic, watercolor, gouache, pastel | `"painting"`       |
| graphic design, logo, vector, flat design, ui       | `"graphic_design"` |

### Color Name → Hex

| Color  | Hex       | Variants                                  |
| ------ | --------- | ----------------------------------------- |
| red    | `#D32F2F` | deep `#C41E3A`, bright `#FF1744`          |
| blue   | `#1565C0` | navy `#0D47A1`, sky `#42A5F5`             |
| green  | `#2E7D32` | forest `#1B5E20`, lime `#66BB6A`          |
| yellow | `#F9A825` | bright `#FDD835`, amber `#FF8F00`         |
| pink   | `#E91E63` | pastel `#F48FB1`, neon `#FF1744`          |
| cyan   | `#00BCD4` | neon `#00E5FF`, teal `#26C6DA`            |
| purple | `#7B1FA2` | deep `#4A148C`, lavender `#CE93D8`        |
| orange | `#EF6C00` | vibrant `#FF6D00`, soft `#FFA726`         |
| black  | `#1A1A1A` | true `#0D0D0D`, charcoal `#2C2C2C`        |
| white  | `#FFFFFF` | off-white `#F5F5F5`, light grey `#E0E0E0` |
| grey   | `#616161` | dark `#424242`, light `#9E9E9E`           |
| gold   | `#FFB300` | light `#FFD54F`, amber `#FF8F00`          |
| brown  | `#5D4037` | dark `#3E2723`, tan `#8D6E63`             |
| teal   | `#00796B` | deep `#004D40`, mint `#4DB6AC`            |
| coral  | `#FF7043` | soft `#FF8A65`, burnt `#F4511E`           |

Include background colors and contrast pairs (highlight + shadow).

### JSON Encoding

- Compact separators: `(",", ":")` — no spaces after `:` or `,`
- No `\uXXXX` escapes — literal Unicode only
- No trailing commas, uppercase hex only (`#RRGGBB`, never `#fff`)
- Valid JSON that parses without errors

## Workflow

1. **Parse** — extract subject, setting, style, mood, colors, text-to-render.
2. **Determine caption type** — photo (`photo` field) or artistic (`art_style`). Default to photograph.
3. **Decompose spatially** — assign bboxes for multiple subjects, text placement, foreground/background separation.
4. **Build color palette** — convert named colors to uppercase hex.
5. **Construct JSON** — follow schema key ordering exactly.
6. **Self-validate** — valid JSON, correct key order, uppercase hex, compact separators, `background` before `elements`, no markdown fences.
7. **Output raw JSON only** — no fences, no preamble, no explanation.

## Handling Input

- **Vague requests** — make reasonable creative choices; don't ask for clarification unless the subject is entirely unclear.
- **Text in image** — use `type: "text"` elements with exact `text` field + bbox.
- **Color mentions** — always convert to hex in `color_palette`.
- **Multiple subjects** — separate elements with bboxes.
- **No style specified** — pick a fitting default.

## Examples

### Minimal valid prompt

```json
{
  "compositional_deconstruction": {
    "background": "A plain white background.",
    "elements": [{ "type": "obj", "desc": "A red apple on a wooden table." }]
  }
}
```

### Photograph

```json
{
  "high_level_description": "A golden retriever riding a skateboard down a sunny sidewalk.",
  "style_description": {
    "aesthetics": "warm, playful, vibrant",
    "lighting": "bright afternoon sunlight, long soft shadows",
    "photo": "shallow depth of field, eye-level, 85mm lens",
    "medium": "photograph",
    "color_palette": ["#F5C542", "#87CEEB", "#4A4A4A", "#FFFFFF", "#2E8B57"]
  },
  "compositional_deconstruction": {
    "background": "A sun-drenched suburban sidewalk lined with green hedges and a white picket fence. Dappled light filters through overhead trees.",
    "elements": [
      {
        "type": "obj",
        "bbox": [200, 300, 800, 900],
        "desc": "A golden retriever with a fluffy coat, standing on a red skateboard with all four paws. Tongue out, ears flapping."
      },
      {
        "type": "obj",
        "bbox": [250, 750, 750, 950],
        "desc": "A worn red skateboard with black wheels rolling along the concrete sidewalk."
      }
    ]
  }
}
```

### Graphic design with text

```json
{
  "high_level_description": "A clean, modern business card layout for a tech company.",
  "style_description": {
    "aesthetics": "minimal, professional, geometric",
    "lighting": "even, diffuse studio lighting",
    "medium": "graphic_design",
    "art_style": "flat vector design, generous whitespace, sans-serif typography",
    "color_palette": ["#FFFFFF", "#F0F0F0", "#333333", "#0066FF", "#00CC88"]
  },
  "compositional_deconstruction": {
    "background": "A solid off-white card surface with subtle paper texture.",
    "elements": [
      { "type": "text", "text": "ACME TECH", "desc": "Bold dark grey sans-serif company name across the upper third." },
      { "type": "text", "text": "hello@acme.tech", "desc": "Small blue sans-serif contact email near the bottom." }
    ]
  }
}
```
