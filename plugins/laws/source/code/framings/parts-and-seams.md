## [FRAMING:parts-and-seams] - a program is parts joined at seams

A program is not a pile of statements. It is a set of parts and the seams where they
meet, and its quality is decided almost entirely at the seams - how you cut the parts,
what shape their edges are, when they touch, and where the outside world leaks in.
The interior code of a part is nearly irrelevant to system quality; you can rewrite a
part's guts freely if its seam is right, and you cannot save a system whose seams are
wrong no matter how beautiful the guts are.

Run your hand over the code, metaphorically. A **smooth** seam is one your hand glides
over - the part's type is exactly the shape of its legal variability, nothing more:
anything it admits is automatically valid, anything valid it admits. Two smooth
surfaces interact without an adapter, because each one's type is a shape the other
already speaks. Composition becomes free. Each smooth block joins the pool of
available building blocks, and any new requirement is usually 95% something already
buildable from existing blocks plus a thin layer of binder. N smooth blocks yield
roughly N² compositions of capability, and velocity *accelerates* as the pool grows.

A **rough** seam snags. Its type is bespoke to the one caller that needed it, or it
admits illegal states every caller must defend against, or it encodes its variability
in the *names of functions* (twenty `filterByX`, `filterByY`, `filterByZ`) rather than
in *values flowing across one boundary* (one `filter(predicate, list)` that admits
infinite predicates). Rough pieces do not compose; they **crystallize** - each one
adds constraints every future piece must work around, so the cost of new work grows
with `feature × accumulated-roughness`. Same multiplier as the smooth case, opposite
sign, and the sign is determined by whether you smoothed the piece before moving on.

This framing has four faces, and the laws divide among them:
- **How you cut** - where the part boundaries fall (`[LAW:decomposition]` and its boundary
  corollaries).
- **What the seams are made of** - the types at the boundaries
  (`[LAW:types-are-the-program]` and its dataflow corollaries).
- **When things happen** - ordering and lifecycle (`[LAW:no-ambient-temporal-coupling]`).
- **Where the world intrudes** - effects and I/O (`[LAW:effects-at-boundaries]`).

The first two faces are deeply developed below; the last two are acknowledged and
real but intentionally less elaborated for now - they are slated for expansion, not
optional.
