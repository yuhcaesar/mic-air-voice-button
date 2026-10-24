# Original microphone artwork

`mic-air-original.png` is an original generic microphone concept illustration generated from the text prompt below with the built-in image_gen tool on 2026-10-24. No input image, product photograph, reference render, logo, or brand artwork was supplied. No CLI fallback or raster post-processing was used.

The image depicts a small round wireless microphone and a side button for use as a UI illustration. It is not an official product image and does not reproduce a brand mark. The generated alpha channel is preserved.

## Application icon

`app-icon.svg` is an original geometric microphone symbol: an off-white capsule, curved stand and base on a deep-green rounded square. The vector source is included in this directory. `app-icon.ico` contains 16, 32, 48 and 256 pixel PNG frames, drawn directly from the same geometric coordinates by `scripts/New-AppIcon.ps1` with System.Drawing. No existing bitmap, third-party icon, brand mark or AI image was used to create this application icon. Both the SVG and generator are covered by the project's MIT license.

To regenerate the icon on Windows:

```powershell
.\scripts\New-AppIcon.ps1
```

## Final microphone generation prompt

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
