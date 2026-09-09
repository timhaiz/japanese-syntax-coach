**Comparison target**

- Source visual truth: `/Users/niix/Downloads/IMG_1061.PNG` (1179 × 2556 px mobile Safari capture).
- Implementation: Chrome browser capture of `http://127.0.0.1:3100/`, taken after the homepage update on 2026-09-09.
- State: signed out / first lesson, 0% progress. The source has a signed-in, second-lesson state; content values therefore intentionally differ while the page hierarchy is compared.

**Findings**

- No P0/P1/P2 issues remain. The implementation preserves the reference’s mobile hierarchy: compact brand header, course pill, personal greeting, two-line hero, right-aligned circular lesson progress, primary lesson CTA, three-column statistics, and a single continuation card above persistent navigation.
- Intentional copy change: the hero now says “一课一练，把句型练成反射。” and explains the learning loop: sentence-pattern review followed by 20 active-output questions. This makes the existing one-lesson unlock rule visible without adding a competing daily-training flow.
- Intentional state change: the implementation’s progress ring and statistics are live values from the current lesson, rather than fixed screenshot values.

**Required fidelity surfaces**

- Fonts and typography: Plus Jakarta Sans and Noto Sans JP retain the reference’s compact rounded sans hierarchy; the hero uses a larger dark lead with a green second line.
- Spacing and layout rhythm: the hero copy flexes on narrow screens while the 112 px progress ring stays aligned to the lower copy block; statistics and the lesson card retain a clear, touch-friendly vertical rhythm.
- Colors and visual tokens: cream canvas, ink CTA, mint lesson card, green mastery state and pale-orange course pill all follow the source palette.
- Image quality and assets: the source uses no required raster illustration or product imagery inside the app viewport; existing product mark and navigation remain unchanged.
- Copy and content: homepage language now reinforces “一课一练 → 句型骨架 → 主动输出” and does not promise the removed daily 10-question plan.

**Primary interactions tested**

- “开始第 1 课” opens the 20-question lesson flow.
- “课程地图” and bottom navigation remain functional.
- All 21 lesson-flow browser tests pass.

**Implementation checklist**

- [x] Turn the hero into a single-lesson learning loop.
- [x] Keep current lesson progress and overall mastery as live data.
- [x] Rename the continuation area to a lesson path and clarify the grammar-first workflow.
- [x] Verify current page flow, type checking, production build, and browser regression coverage.

**Follow-up polish**

- [P3] When a dedicated icon set is introduced project-wide, replace the legacy text-glyph navigation icons consistently across the app.

final result: passed
