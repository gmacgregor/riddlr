---
name: do-work
description: Plan, implement, and validate a unit of work in this repo, then optionally commit it. Use when the user asks to build a feature, fix a bug, or otherwise wants a task implemented end-to-end.
---

# Do Work

A unit of work moves through four steps, in order. Don't skip ahead to implementation before the plan is confirmed, and don't call the work done before the feedback loop is clean.

## 1. Understand the task

Read any referenced plans or specs. Explore the codebase to understand the context of the work. Ask the user clarifying questions if the task or scope is unclear or ambiguous before proceeding.

Done when you understand the task and have no further questions.

## 2. Plan (optional)

If the task has not already been planned, create a plan for it.

- Explore the relevant code first. Identify what files need to change and what files need to be added. 
- Note any existing patterns or conventions in nearby code.
- Break the work into small, testable slices.
- Present the plan to the user and get approval before proceeding.

Done when the user has confirmed the plan.

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

## 5. Commit (optional) & Close Issue (optional)

Ask the user if you should commit your changes. If work was performed against a specific issue, ask if you should commit changes and also close the issue.

Done when the user has confirmed that you should/should not commit and/or close the issue.
