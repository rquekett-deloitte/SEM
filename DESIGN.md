# Design System

## Direction

The Scenario Economic Model is a light-mode analytical application expressed through Deloitte branding and statistical-publication discipline. It prioritises traceability, comparison and dense information over decorative dashboard treatments.

## Colour

- `#111111`: high-emphasis text and rules.
- `#86bc25`: Deloitte action green and successful run state.
- `#639416`: darker green for interactive text and focus support.
- `#008a83`: primary scenario series in charts.
- `#777777`: baseline comparison series.
- `#f5f5f2`: neutral application canvas.
- `#ffffff`: working surfaces.
- `#d8d8d4`: rules, chart grids and structural boundaries.

Colour is restrained. Green communicates action, selection and readiness; it is not scattered as decoration. Charts rely on line style as well as colour so the scenario and baseline remain distinguishable.

## Typography

Use Segoe UI with Tahoma and generic sans-serif fallbacks. Headings are compact and semibold or bold. Supporting labels are smaller, neutral and direct. Numerical output uses tabular figures; run identifiers use a monospace face because they are machine-readable data.

## Layout

The desktop application uses a persistent white navigation rail, a broad light results workspace and a fixed-width white scenario builder. Results begin with scenario context, followed by a selectable metric strip, the primary chart and the scenario ledger. At tablet widths the navigation becomes an off-canvas panel. Below 900px the scenario builder moves beneath results, and below 620px metrics form a two-column grid while wide charts become horizontally scrollable.

## Components

- Navigation uses quiet gray labels on white with a pale green active field and a stronger green rule.
- Metric selectors are joined into one ruled strip rather than presented as floating cards.
- Charts use white grounds, fine gray horizontal rules, restrained axes, a solid teal scenario line and dashed gray baseline.
- Forms use square, lightly bordered controls with explicit labels and visible focus rings.
- Primary actions are solid Deloitte green with black text.
- Scenario status is expressed with text and a small coloured dot.
- Scenario history is a compact responsive table with stable run IDs.

## Interaction

Controls use native semantics and remain keyboard accessible. Loading is represented at the run action and status indicator. Errors identify the failed action in a bordered message. Motion is limited to run-state feedback and the mobile navigation transition, and is disabled by reduced-motion preferences.
