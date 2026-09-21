# 📐 FlavorFlow HRMS — Design & Delivery Rules

Har UI/feature change inna rules naal hovega. No exceptions.

## The Rule: DESIGN → APPROVE → IMPLEMENT (IDENTICAL) → WORKING → DEPLOY

1. **Design first (chat vich mockup)** — Main pehlan screen da mockup/preview
   bana ke dikhaunga (image ya description naal). Code ton PEHLAN.
2. **Tuhada approval** — "OK" mile taan hi implementation shuru.
3. **Pixel-matched implementation** — Jo approve hoya, **ohi exact UI** build
   hovega. Alag kuch nahi banega. Differences mile ta bug samjho.
4. **Features MUST keep working** — Sirf "sundar dikhe" nahi chalda:
   - Saare forms/buttons/actions functionally test hon
   - `npm run build` green (typecheck pass)
   - Deploy ton baad live verify (main curl/navigator naal confirm karan)
5. **Data zero-loss** — Koi UI change database/data nu touch nahi karega.
   Schema change hovelte pehlan daske confirm karvayange.
6. **One deploy pipeline** — Change push → CircleCI green → live verify →
   fer hi "done" bolange.

## Current UI milestone
- **v1** — functional Tailwind UI (simple)
- **v2** ✅ LIVE — premium dark sidebar, SVG icons, gradient hero, mobile
  bottom-nav, branded login, animations
- **v3** — planned: data-driven redesign (dekho use-feadback ke saath)
