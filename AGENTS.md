## Conventions & Boundaries

<important if="architecting features, creating plans, refactoring, triaging bugs">

- Split development tasks into thin vertical slices of functionality that provide incremental value with each iteration and allow you to validate solution effectiveness more immediately.
- Do not develop large horizontal layers that must be completed before the next layer can be tackled.
- If a TDD or Test-Driven-Development skill is in your context, load it and follow its guidance.
- Commit code changes when directly instructed by the user to do so or when a skill in your context instructs you to do so.

</important>

<important if="writing moduledoc, function docstrings, or comments">

- You are not a mystic, poet or stoner: documentation and comments must be clear and concise. 
- Always use prose and apply Orwell's rules ("Politics and the English Language"):

> Never use a long word where a short one will do.
  If it is possible to cut a word out, always cut it out.
  Never use the passive where you can use the active.
  Never use a foreign phrase, a scientific word, or a jargon word if you can think of an everyday English equivalent.

- Latinate vocabulary (reconcile, coalesce, normalize, reconciliation) sounds technical and abstract; Anglo-Saxon words (prune, run, watch, stop, drop, walk) are short and physical. Prefer the Saxon word.
- Comments should state, in plain English, the constraint the code cannot show: why the non-obvious exists.
- If code is complex and the implementation is non-obvious, add a comment.
- If a function contains complex behaviors or side effects, add a doc comment.
- If a comment narrates change history from the conversation, delete it.
- If a comment restates code whose behavior is self-evident, delete it.

</important>

<important if="git commiting code changes">

- Use conventional commits and include both a commit summary and description.
- If commits relate to a specific issue, include the issue number in the summary message, i.e `fix(#123): ...`.
- If the current branch is a feature branch, include the feature name in the summary message, i.e `fix(feature-name): ...`. If you don't know what `feature-name` to use, supply a suggestion and ask the user.

</important>

## Agent skills

### Issue tracker

GitHub Issues on `gmacgregor/riddlr`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, label strings unchanged. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

<!-- ELIXIR-PHOENIX-PLUGIN:START -->
## Elixir Phoenix Plugin usage
@docs/ELIXIR_PHOENIX_PLUGIN.md
<!-- ELIXIR-PHOENIX-PLUGIN:END -->

<!-- usage-rules-start -->

<!-- phoenix:ecto-start -->
## phoenix:ecto usage
@deps/phoenix/usage-rules/ecto.md
<!-- phoenix:ecto-end -->

<!-- phoenix:elixir-start -->
## phoenix:elixir usage
@deps/phoenix/usage-rules/elixir.md
<!-- phoenix:elixir-end -->

<!-- phoenix:html-start -->
## phoenix:html usage
@deps/phoenix/usage-rules/html.md
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## phoenix:liveview usage
@deps/phoenix/usage-rules/liveview.md
<!-- phoenix:liveview-end -->

<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
@deps/phoenix/usage-rules/phoenix.md
<!-- phoenix:phoenix-end -->

<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

@deps/usage_rules/usage-rules.md
<!-- usage_rules-end -->

<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
@deps/usage_rules/usage-rules/elixir.md
<!-- usage_rules:elixir-end -->

<!-- usage_rules:otp-start -->
## usage_rules:otp usage
@deps/usage_rules/usage-rules/otp.md
<!-- usage_rules:otp-end -->

<!-- usage-rules-end -->
