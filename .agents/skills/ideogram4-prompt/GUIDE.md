# Ideogram 4 Prompting Guide (Distilled)

Ideogram 4 requires **structured JSON captions** — plain text prompts will fail or trigger safety filters. The JSON schema provides fine-grained control over composition, style, color, and spatial layout.

## The Three Top-Level Fields

| Field                          | Required?                       | Purpose                                                     |
| ------------------------------ | ------------------------------- | ----------------------------------------------------------- |
| `high_level_description`       | Optional (strongly recommended) | 1–2 sentence summary of the entire image                    |
| `style_description`            | Optional                        | Visual style, lighting, medium, color palette               |
| `compositional_deconstruction` | **Required**                    | Spatial layout with bounding boxes and element descriptions |

## `style_description` Rules

Must contain **exactly one** of `photo` (photographic) or `art_style` (illustration, 3D, painting, etc.). Key order is **strict**:

- **Photo captions:** `aesthetics` → `lighting` → `photo` → `medium` → `color_palette`
- **Non-photo captions:** `aesthetics` → `lighting` → `medium` → `art_style` → `color_palette`

`color_palette` is optional but must be last if present.

| Field           | Type         | Example                                                                           |
| --------------- | ------------ | --------------------------------------------------------------------------------- |
| `aesthetics`    | string       | `"moody, cinematic, desaturated"`                                                 |
| `lighting`      | string       | `"golden hour, rim light, dramatic shadows"`                                      |
| `photo`         | string       | `"35mm, f/1.4, bokeh"` (photo only)                                               |
| `medium`        | string       | `"photograph"`, `"illustration"`, `"3d_render"`, `"painting"`, `"graphic_design"` |
| `art_style`     | string       | `"flat vector illustration, bold outlines"` (non-photo only)                      |
| `color_palette` | list[string] | `["#1B1B2F", "#162447", "#E43F5A"]` — up to 16 hex colors                         |

## `compositional_deconstruction` Rules

`background` must come before `elements`. Each element has a fixed key order:

- **`type: "obj"`** → `type` → `bbox` → `desc` → `color_palette`
- **type: "text"** → `type` → `bbox` → `text` → `desc` → `color_palette`

| Field           | Type         | Notes                                                                       |
| --------------- | ------------ | --------------------------------------------------------------------------- |
| `background`    | string       | Environment description (required)                                          |
| `elements`      | list[dict]   | Objects (`"obj"`) and text (`"text"`) with optional bounding boxes          |
| `bbox`          | list[int]    | `[y_min, x_min, y_max, x_max]` in 0–1000 coords, origin top-left. Optional. |
| `text`          | string       | Literal text to render (only for `type: "text"`)                            |
| `color_palette` | list[string] | Per-element palette, up to 5 hex entries                                    |

## Critical Rules

1. **Key order matters** — the model was trained on JSON with consistent key ordering. Deviating degrades quality.
2. **Hex colors must be uppercase** — `#RRGGBB` format only (e.g. `#1B1B2F`, not `#1b1b2f` or `#fff`).
3. **JSON encoding** — use `separators=(",", ":")` and `ensure_ascii=False` (no `\uXXXX` escapes).
4. **Color palette tips** — include background colors, use contrast pairs (highlight + shadow), max 16 global / 5 per-element.
5. **Safety filter** — NSFW content is blocked. Non-JSON prompts have a high false-positive rate.

## Minimal Valid Prompt

```json
{
  "compositional_deconstruction": {
    "background": "A plain white background.",
    "elements": [{ "type": "obj", "desc": "A red apple on a wooden table." }]
  }
}
```

## Full Example (Photograph)

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
        "desc": "A golden retriever with a fluffy coat, standing on a red skateboard with all four paws. Its tongue is out and ears are flapping in the wind."
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

## Full Example (Graphic Design with Text)

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
      {
        "type": "text",
        "text": "ACME TECH",
        "desc": "Bold dark grey sans-serif company name across the upper third of the card."
      },
      {
        "type": "text",
        "text": "hello@acme.tech",
        "desc": "Small blue sans-serif contact email near the bottom of the card."
      }
    ]
  }
}
```
