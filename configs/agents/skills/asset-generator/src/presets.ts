import type { StylePreset } from "./types.js";

export const STYLE_PRESETS: Record<string, StylePreset> = {
  clay: {
    id: "clay",
    name: "3D Clay",
    aliases: ["3d-clay", "claymorphism", "matte-3d"],
    description: "Cute, volumetric 3D matte clay illustration with soft studio lighting",
    promptSuffix:
      "3D clay rendering, smooth matte clay texture, cute rounded volumetric shapes, soft ambient studio lighting, soft shadows, subtle pastel palette, minimal modern design, Blender Cycles 3D style",
    negativePrompt:
      "harsh shadows, glossy reflections, photorealistic human skin, noisy textures, complex background",
  },
  glossy: {
    id: "glossy",
    name: "3D Glossy / Premium Tech",
    aliases: ["3d-glossy", "apple", "fintech", "plastic"],
    description:
      "High-end 3D glossy plastic and glass render with vibrant colors and sharp specular highlights",
    promptSuffix:
      "Premium 3D render, glossy polished plastic and smooth glass materials, vibrant rich colors, polished finish, Apple aesthetic, subtle subsurface scattering, studio rim lighting, modern fintech app icon style, sharp specular highlights",
    negativePrompt: "rough matte textures, desaturated colors, noisy grains, grunge",
  },
  glass: {
    id: "glass",
    name: "Glassmorphism",
    aliases: ["glassmorphism", "frosted", "acrylic"],
    description: "Translucent frosted glass UI with chromatic refraction and luminous glow",
    promptSuffix:
      "Glassmorphism UI icon, translucent frosted glass layers, soft refractive glow, chromatic aberration edge highlights, subtle inner shadows, sleek and futuristic, modern iOS acrylic material design",
    negativePrompt: "opaque solid clay, heavy black shadows, flat monotone",
  },
  flat: {
    id: "flat",
    name: "Modern Flat Vector",
    aliases: ["flat-vector", "vector", "saas", "stripe"],
    description:
      "Clean modern flat vector graphic with crisp geometric shapes and bold solid colors",
    promptSuffix:
      "Modern flat vector illustration, clean geometric shapes, crisp bold outlines, vibrant solid color palette, minimalist SaaS style, Stripe or Notion aesthetic, balanced negative space, no complex 3D gradients",
    negativePrompt: "3D render, realistic photos, blurry edges, heavy textures",
  },
  iso: {
    id: "iso",
    name: "Isometric 3D",
    aliases: ["isometric", "infra", "architecture"],
    description:
      "Technical isometric view with precise 30-degree angles for cloud/architecture diagrams",
    promptSuffix:
      "Isometric 3D projection, technical architectural view, precise 30-degree isometric angles, clean lighting, modular components, cloud computing and tech infrastructure style, crisp details, sharp geometry",
    negativePrompt: "perspective distortion, fish-eye, random angles, blurry lines",
  },
  line: {
    id: "line",
    name: "Minimal Line Art",
    aliases: ["line-art", "outline", "minimal-line"],
    description:
      "Sophisticated continuous line art with elegant stroke weights and duotone accents",
    promptSuffix:
      "Minimalist line art illustration, elegant continuous contours, uniform crisp stroke width, sophisticated editorial aesthetic, clean modern Japanese design, subtle single-color accent",
    negativePrompt: "heavy solid fills, chaotic scribbles, photorealism",
  },
  duo: {
    id: "duo",
    name: "Modern Duotone",
    aliases: ["duotone", "gradient-duo", "brand-duo"],
    description: "Striking two-tone gradient aesthetic matching modern brand palettes",
    promptSuffix:
      "Modern duotone vector graphic, striking two-color gradient mapping, bold contrast, high-end branding aesthetic, tech startup UI accent style, smooth vector gradients",
    negativePrompt: "rainbow colors, multicolor noise, photographic realism",
  },
  neon: {
    id: "neon",
    name: "Tech Neon / Cyber",
    aliases: ["tech-neon", "cyber", "cyberpunk", "glow"],
    description: "Glowing neon wireframe and dark-mode cyberpunk tech assets",
    promptSuffix:
      "Cyberpunk tech aesthetic, glowing neon wireframes, luminescent cyan and purple light trails, dark futuristic UI elements, subtle holographic glow, dark mode landing page accent",
    negativePrompt: "bright daytime pastel, vintage watercolor, muddy earth tones",
  },
  badge: {
    id: "badge",
    name: "Sticker & Emblem Badge",
    aliases: ["sticker", "sticker-badge", "emblem"],
    description: "Die-cut playful sticker badge with crisp white contour outline",
    promptSuffix:
      "Die-cut sticker illustration, thick crisp white border contour outline, bold saturated colors, playful emblem badge, modern SaaS feature sticker, subtle soft drop shadow",
    negativePrompt: "faded edges, rough borders, photorealism",
  },
  sketch: {
    id: "sketch",
    name: "Hand-Drawn Doodle",
    aliases: ["hand-drawn", "doodle", "scribble"],
    description: "Approachable human hand-drawn sketches and playful ink doodles",
    promptSuffix:
      "Charming hand-drawn doodle, sketchy ink line work, organic human touch, playful scribbles, warm and approachable, whimsical accent graphic, editorial notebook sketch style",
    negativePrompt: "rigid 3D render, glossy plastic, clinical sterile shapes",
  },
  pastel: {
    id: "pastel",
    name: "Soft Watercolor & Pastel",
    aliases: ["watercolor", "soft-pastel", "organic"],
    description: "Gentle watercolor bleed and soothing pastel tones for lifestyle/health brands",
    promptSuffix:
      "Soft watercolor and pastel illustration, gentle pigment bleed, airy light colors, soothing texture, organic natural feel, lifestyle and wellness branding aesthetic",
    negativePrompt: "harsh neon, sharp black outlines, violent contrast",
  },
  paper: {
    id: "paper",
    name: "Layered Paper Craft",
    aliases: ["origami", "paper-cut", "craft"],
    description: "Tactile layered paper-cut art with delicate cast shadows and folds",
    promptSuffix:
      "Layered paper craft art, origami paper cutouts, tactile depth with subtle realistic shadow layers, crisp folded edges, tactile material design, crafted paper aesthetic",
    negativePrompt: "flat digital render, liquid textures, photorealistic metal",
  },
  pixel: {
    id: "pixel",
    name: "Retro Pixel Art",
    aliases: ["retro-pixel", "8bit", "16bit", "arcade"],
    description: "Nostalgic 16-bit arcade pixel art with crisp grid alignment",
    promptSuffix:
      "16-bit retro pixel art, crisp pixel grid alignment, nostalgic video game palette, charming pixelated icons, clean arcade aesthetic, no anti-aliasing blur",
    negativePrompt: "smooth vector gradients, high-res 3D, blurry compression",
  },
  real: {
    id: "real",
    name: "Isolated Studio Object",
    aliases: ["photo-object", "realistic", "studio"],
    description: "Ultra-crisp commercial product photography with dramatic studio lighting",
    promptSuffix:
      "Ultra-realistic studio product photography, isolated physical object, high-end commercial photo, dramatic studio key light, crisp 8k texture, shallow depth of field, tactile premium materials",
    negativePrompt: "cartoon, drawing, vector, illustration, blur, low resolution",
  },
};

export function resolveStyle(input?: string): StylePreset | undefined {
  if (!input) return undefined;
  const key = input.toLowerCase().trim();
  if (STYLE_PRESETS[key]) return STYLE_PRESETS[key];
  for (const preset of Object.values(STYLE_PRESETS)) {
    if (preset.aliases.includes(key) || preset.id === key) {
      return preset;
    }
  }
  return undefined;
}
