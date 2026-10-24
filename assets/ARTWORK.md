# Microphone illustration and device label

The base illustration for `mic-air-original.png` was generated from the text prompt below with the built-in image_gen tool on 2026-10-24. No input image, product photograph, reference render, logo, or brand artwork was supplied for that base image. The unlabelled base is preserved in the v1.0.8 Git tag (SHA256 `75AB1FB533C539CF347959365D0E900E675C477341BDCFB96EDB2547C4984DF2`).

For v1.0.9, the same built-in tool edited that project illustration to add the ordinary text `Insta360` on its front face, at the user's request, to identify the compatible device. Only the project illustration was supplied as the edit target; no official product photograph or logo asset was supplied. This is a labelled concept illustration, not an official product photograph or an endorsement. Third-party names and trademarks remain with their respective rights holders; the project does not grant trademark rights. The generated alpha channel is preserved. No CLI fallback or raster post-processing was used.

The first label edit was then revised with the same built-in tool: the user requested much larger lettering at the centre of the circular face. Both edit prompts are recorded below. The final asset preserves the generated transparent alpha without raster post-processing.

## Final label placement prompt (v1.0.9)

```text
Use case: precise-object-edit.
Input image 1 is the EDIT TARGET: an existing transparent microphone illustration with the word Insta360 on it.
User correction: the lettering is too small and sits off-center. Change ONLY the lettering size and placement. Remove the existing small lettering and put the exact word "Insta360" in MUCH LARGER, bold light-silver/off-white letters across the EXACT VISUAL CENTER of the ROUND FRONT FACE of the microphone. Center on the circular face itself, not on the entire image or on the blank area left of the diagonal grooves. The word should span about 70 to 75 percent of the visible front-face width, crossing the middle diagonal grooves naturally; its horizontal midpoint must match the face midpoint, and its vertical midpoint must lie at the mid-height of the face. Move it substantially right and down compared with the current lettering. The text must feel dominant, balanced, and immediately legible at a 128-pixel icon size. Keep the full word on one line. Use a clean heavy sans-serif with a simple shallow raised/printed finish and an approximately level baseline, with only the subtle perspective needed to sit on the face. Exact spelling: "Insta360".
Keep every other element unchanged: whole microphone shape, composition, transparent margins, side button, blue LED, grooves, camera angle, perspective, material, shading, and lighting. Do not change the microphone body into a different product. Do not add any other text, emblem, badge, border or object. Preserve genuinely transparent alpha outside the object; no opaque background or checkerboard. Square transparent PNG.
```

## Initial label edit prompt (v1.0.9)

```text
Use case: precise-object-edit.
Asset type: transparent PNG microphone illustration for a Windows desktop app, displayed at 128 x 128 pixels.
Input image 1 is the EDIT TARGET: the project's existing generic round microphone illustration. It is not an official photograph.
Primary request: add the exact text "Insta360" to the FRONT FACE of this existing microphone, so users can identify the compatible device immediately. Make the inscription large enough to stay clearly readable when the whole image is reduced to 128 pixels. Use a clean bold ordinary sans-serif, light silver/off-white lettering, sitting naturally on the microphone surface with subtle printed or shallow raised appearance. It should run across the central front face below the blue status LED, with very slight perspective matching that surface. Exact spelling and capitalization: I n s t a 3 6 0, joined as "Insta360".
Keep unchanged: microphone silhouette, shape, angle, camera position, side button, blue LED, existing diagonal grooves, material texture, lighting, overall scale, margins, and transparent background. This is a single targeted text addition to the supplied image. Preserve the existing illustration rather than redesigning it into an official product render.
Background: genuinely transparent alpha outside the microphone. No opaque background, checkerboard, floor, cast shadow, extra shapes, badges, captions, or text outside the device.
Constraints: the only new element is the exact word "Insta360" on the microphone front. Do not add a front button, additional logo graphic, company icon, slogan, copyright mark, or any additional words. Output a square PNG with transparent background.
```

## Application icon

`app-icon.svg` is an original geometric microphone symbol: an off-white capsule, curved stand and base on a deep-green rounded square. The vector source is included in this directory. `app-icon.ico` contains 16, 32, 48 and 256 pixel PNG frames, drawn directly from the same geometric coordinates by `scripts/New-AppIcon.ps1` with System.Drawing. No existing bitmap, third-party icon, brand mark or AI image was used to create this application icon. Both the SVG and generator are covered by the project's MIT license.

To regenerate the icon on Windows:

```powershell
.\scripts\New-AppIcon.ps1
```

## Base microphone generation prompt (v1.0.8)

```text
Use case: stylized-concept.
Asset type: original transparent illustration for an open-source Windows microphone-button application, displayed at 128 pixels.
Generate a brand-new original concept illustration entirely from this text. No reference images, no recreation of any existing product photograph or render.
Subject: one small round coin-shaped dark charcoal wireless clip-on microphone transmitter. A shallow cylindrical body in a three-quarter view, with one small oval multifunction button visibly protruding from the LEFT SIDE RIM. The front surface has a restrained original pattern of diagonal geometric grooves and one tiny blue status LED.
Style: refined matte 3D illustration, simple and clean, with subtle material texture. Soft studio lighting and a faint deep forest-green #172E2A reflected fill, designed to sit comfortably on a warm off-white #F8FAF9 app surface.
Composition: isolated complete object, centered in a square canvas, occupying about 80 percent of the canvas with even margins. Keep the side button clearly readable. The outer silhouette must be crisp and readable as a small UI illustration.
Background: genuinely transparent alpha outside the object. No floor, no opaque background, no checkerboard drawn into the image. No cast shadow outside the object.
Constraints: absolutely NO logos, brands, trademark lettering, model names, words, numbers, watermark, caption, arrows, receiver, wire, hand, screen, or other objects. Do not add a large button on the front face. This is an original generic microphone concept illustration, not a product photograph.
```

## Fallback voice illustration

`voice-illustration.png` was independently generated from the following text with the built-in image_gen tool. No reference images were supplied. It is an original generic speech-bubble and waveform illustration, used when the user's installed input-method icon cannot be found. It is not an official Doubao logo or mascot. Its generated transparent alpha channel is preserved; no CLI fallback or raster post-processing was used.

### Final voice generation prompt

```text
Use case: stylized-concept.
Asset type: small polished desktop application illustration, displayed at about 128x128.
Primary request: a refined 3D speech bubble with a clear voice waveform inside, representing voice dictation in Doubao. It is a generic voice-input illustration, not an official Doubao logo or mascot.
Subject: one rounded speech bubble with a short lower tail, gently raised like a compact premium physical object. Inside are five rounded vertical waveform bars of different heights. No face, no character, no microphone device, no letters.
Style: restrained polished product-like 3D illustration with precise simple geometry, soft matte material, light beveled edges and soft studio lighting. It must pair with a small charcoal round microphone product illustration.
Color palette: deep forest green #172E2A bubble with a subtle sage green rim and warm off-white #F8FAF9 waveform. Elegant and calm, no neon glow, no oversaturation.
Composition: a single complete centered object in a square image, occupying about 80 percent of the canvas, even margins, very slightly three-quarter angle while keeping the waveform highly legible at small size. No floor or other objects.
Background: truly transparent alpha outside the object, no opaque background and no checkerboard pattern drawn into the image.
Text: no text, captions, labels, logo, brand mark, watermark or surrounding decorations.
```
