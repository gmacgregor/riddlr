---
name: do-work
description: Plan, implement, and validate a unit of work in this repo, then optionally commit it. Use when the user asks to build a feature, fix a bug, or otherwise wants a task implemented end-to-end.
---

# Do Work

A unit of work moves through four steps, in order. Don't skip ahead to implementation before the plan is confirmed, and don't call the work done before the feedback loop is clean.

## 1. Understand the task

Read any referenced plans or specs. Explore the codebase to understand the context of the work. Ask the user clarifying questions if the task or scope is unclear or ambiguous before proceeding. If asking a question with options, provide the user your recommended option and very brief reasoning about why you think it most favourable.

Done when you understand the task and have no further questions.

## 2. Plan (optional)

If the task has not already been planned, create a plan for it.

- Explore the relevant code first. Identify what files need to change and what files need to be added.
- Note any existing patterns or conventions in nearby code.
- Break the work into small, testable slices.
- Write the full plan as visible reply text. Your reasoning is hidden from the user and does not count as presenting it.
- Then end your turn and wait for approval. Do not use `ask_user` to approve a plan.

Done when the plan has been presented and the user has confirmed it.

## 3. Implement

Work through the plan step by step. Use red/green/refactor, one test at a time in tracer-bullet style, no exceptions.

1. Write a single failing test for the smallest vertical slice of behaviour
2. Run the test and confirm it fails (red)
3. Write the minimum code to make it pass (green)
4. Repeat from step 1 for the next slice of behaviour
5. Refactor if needed while keeping tests green

Each test should target one thin vertical slice through the system. Do not write all tests upfront: write one, make it pass then move to the next.

Done when every slice in the plan is implemented and all tests pass.

## 4. Validate

Run the feedback loops and fix any issues.

```
mix format
mix test
```

Done when both commands exit clean with no errors.

## 5. Review Changes

Invoke the code-review skill tool and then the phx:review skill tool. If no such skills exist, notify the user that a code review skill could not be determined and then abandon this step. Otherwise, follow its instructions and re-run the validation step. If skill instructions suggest using multiple agents, then select different models from the current orchestrator model. Notify the user when the skills complete.

Done when the step is either abandoned or the skills have been successfully invoked and changes validated.

## 6. Update Documentation (optional)

When your task affects the meaning of a term already documented in the project [`GLOSSARY.md`](../../../GLOSSARY.md) then update the file. If it introduces a new glossary term then suggest the term and its definition to the user and let them decide if it should be added. Update [`DOMAIN.md`](../../../docs/DOMAIN.md) when changes are made to how Riddlr works, in domain terms. Ask the user for clarity when its ambiguous if your change merits a glossary or domain document update.

Done when project glossary and domain documents are updated, or skipped, depending on what was just implemented.

## 6. Commit (optional) & Close Issue (optional)

Ask the user if you should commit your changes and close the issue (assuming the work performed has one or more associated issues). When closing the issue, leave a succinct comment outlining what action was taken and remove any associated labels that no longer make sense given issue closure i.e. "TODO" or "ready-for-agent".

Done when changes are committed and any associated issues are closed.
