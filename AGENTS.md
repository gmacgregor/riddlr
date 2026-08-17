## Conventions & Boundaries

<important if="architecting features, creating plans, refactoring, triaging bugs">

- Split development tasks into thin vertical slices of functionality that provide incremental value with each iteration and allow you to validate solution effectiveness more immediately.
- Do not develop large horizontal layers that must be completed before the next layer can be tackled.
- If a TDD or Test-Driven-Development skill is in your context, load it and follow its guidance.
- Commit code changes when directly instructed by the user to do so or when a skill in your context instructs you to do so.

<!-- ELIXIR-PHOENIX-PLUGIN:START -->
## Elixir Phoenix Plugin usage
@docs/elixir_phoenix_plugin.md
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

</important>

<important if="writing moduledoc, function spec, doc strings, code comments">

## Code comments and documentation
@docs/agents/code_doc.md

</important>

<important if="git commiting code changes">

## Version control
- Use conventional commits and include both a commit summary and description.
- If commits relate to a specific issue, include the issue number in the summary message, i.e `fix(#123): ...`.
- If the current branch is a feature branch, include the feature name in the summary message, i.e `fix(feature-name): ...`. If you don't know what `feature-name` to use, supply a suggestion and ask the user.

</important>

### Issue tracker
GitHub Issues on `gmacgregor/riddlr`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels
Default five-role vocabulary, label strings unchanged. See `docs/agents/triage-labels.md`.

### Domain docs
Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
