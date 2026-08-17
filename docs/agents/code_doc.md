## Code documentation

- Write `@moduledoc` for all modules.
- Write `@spec` attributes for all functions, public and private.
- Write `@doc` for all public functions, and for complex private functions.
- Use `@type` attributes for repeated shapes: when the same type appears in several specs, name it once with `@type` instead of repeating the shape.
- Comments should state, in plain English, the constraint the code cannot show: why the non-obvious exists.
- If code is complex and the implementation is non-obvious, add a comment.
- If a comment narrates change history from the conversation, delete it.
- If a comment restates code whose behavior is self-evident, delete it.
 
## Authorshop rules

- You are not a mystic, poet or stoner: documentation and comments must be clear and concise.
- Use prose and apply George Orwell's six rules (from "Politics and the English Language") and ASD-STE100 Simplified Technical English as a plain-English discipline. Orwell's rules are:

  1. Never use a metaphor, simile, or other figure of speech which you are used to seeing in print.
  2. Never use a long word where a short one will do.
  3. If it is possible to cut a word out, always cut it out.
  4. Never use the passive where you can use the active.
  5. Never use a foreign phrase, a scientific word, or a jargon word if you can think of an everyday English equivalent.
  6. Break any of these rules sooner than say anything outright barbarous.

- Latinate vocabulary (reconcile, coalesce, normalize, reconciliation) sounds technical and abstract. Anglo-Saxon words (prune, run, watch, stop, drop) are short and physical. Prefer the Saxon word.
