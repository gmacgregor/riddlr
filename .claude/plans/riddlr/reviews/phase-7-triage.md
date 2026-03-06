# Phase 7 Review Triage

**Date:** 2026-02-28
**Review:** Phase 7 Game Lifecycle Implementation
**Status:** 10/13 completed, 3 deferred as non-critical

---

## Fix Queue (13 items)

### BLOCKERs (4) 🚫

- [x] **[B-1] Missing authorization in FormComponent save handlers**
  - **File:** `lib/riddlr_web/live/admin/riddle_live/form_component.ex:103-106`
  - **File:** `lib/riddlr_web/live/admin/category_live/form_component.ex:47-49`
  - **Issue:** `handle_event("save", ...)` doesn't re-authorize admin permissions
  - **Risk:** Session hijacking after role revocation (LiveView connections are long-lived)
  - **Fix:** Add authorization check in save handler:
    ```elixir
    def handle_event("save", %{"riddle" => params}, socket) do
      if Authorization.has_permission?(socket.assigns.current_user, :manage_riddles) do
        params = prepare_params_for_changeset(params)
        save(socket, socket.assigns.action, params)
      else
        {:noreply, socket |> put_flash(:error, "Unauthorized")}
      end
    end
    ```
  - **Also apply to:** CategoryLive.FormComponent
  - **Verify:** `current_user` is passed as assign from parent LiveView

- [x] **[B-2] No validation that live_date is in future**
  - **File:** `lib/riddlr/games.ex:117-146` (schedule_riddle/2)
  - **File:** `lib/riddlr_web/live/admin/riddle_live/form_component.ex:160-173` (parse_live_date/1)
  - **Issue:** Past `live_date` causes immediate uncontrolled state cascade (closed → scheduled → ready → live)
  - **Risk:** Bypasses intended review/readiness workflow
  - **Fix:** Add validation in Games.schedule_riddle/2:
    ```elixir
    def schedule_riddle(%Riddle{} = riddle, live_date) do
      cond do
        DateTime.compare(live_date, DateTime.utc_now()) == :lt ->
          {:error, :live_date_in_past}

        riddle.play_status != "closed" ->
          {:error, "cannot schedule riddle in #{riddle.play_status} state"}

        true ->
          # ... existing Multi logic
      end
    end
    ```
  - **Also add:** Changeset validation or form-level warning

- [x] **[B-3] Repo.get! crashes instead of canceling gracefully** [IRON LAW - AUTO-APPROVED]
  - **File:** `lib/riddlr/workers/ready_riddle_transition_worker.ex:16`
  - **File:** `lib/riddlr/workers/live_riddle_transition_worker.ex:16`
  - **File:** `lib/riddlr/workers/archive_riddle_transition_worker.ex:16`
  - **File:** `lib/riddlr/games.ex:153,183,213,242`
  - **Issue:** Raises `Ecto.NoResultsError` on deleted riddle, causing job crash and retries
  - **Fix:** Replace with pattern-matched Repo.get/2:
    ```elixir
    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
      case Repo.get(Riddle, id) do
        nil ->
          {:cancel, "Riddle #{id} not found"}

        riddle ->
          if riddle.play_status == "scheduled" do
            case Games.ready_riddle(id) do
              {:ok, _riddle} -> :ok
              {:error, reason} -> {:error, reason}
            end
          else
            {:cancel, "Already transitioned (current: #{riddle.play_status})"}
          end
      end
    end
    ```
  - **Apply to:** All 3 workers + context transition functions
  - **Context functions:** Consider accepting `%Riddle{}` struct OR id:
    ```elixir
    def ready_riddle(%Riddle{} = riddle), do: do_ready_riddle(riddle)
    def ready_riddle(riddle_id) when is_integer(riddle_id) do
      case Repo.get(Riddle, riddle_id) do
        nil -> {:error, :not_found}
        riddle -> do_ready_riddle(riddle)
      end
    end
    ```

- [x] **[B-4] Inconsistent Multi transaction error handling** [IRON LAW - AUTO-APPROVED]
  - **File:** `lib/riddlr/games.ex:212-235` (complete_riddle/1)
  - **Issue:** Returns raw Multi result `{:ok, %{riddle: ..., archive_job: ...}}` while other functions normalize to `{:ok, riddle}`
  - **Risk:** Inconsistent return types force callers to handle different shapes
  - **Fix:** Add case block to normalize result:
    ```elixir
    |> Repo.transaction()
    |> case do
      {:ok, %{riddle: riddle}} -> {:ok, riddle}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
    ```
  - **Pattern:** Match other transition functions (ready_riddle, start_riddle, archive_riddle)

### WARNINGs (9) ⚠️

- [x] **[W-1] Debug IO.inspect in production auth path**
  - **File:** `lib/riddlr_web/user_auth.ex:203`
  - **Issue:** `IO.inspect(conn.assigns)` dumps session data to logs on every authenticated request
  - **Risk:** Information disclosure, performance overhead
  - **Fix:** Delete line 203 entirely

- [x] **[W-2] Admin redirect route bypasses admin role check**
  - **File:** `lib/riddlr_web/router.ex:80-86`
  - **Issue:** `GET /admin` only requires `:require_authenticated_user`, not admin role
  - **Fix:** Move into admin-scoped routes:
    ```elixir
    live_session :admin, on_mount: [{RiddlrWeb.AdminAuth, :require_admin}] do
      scope "/admin", RiddlrWeb.Admin do
        pipe_through [:browser, :require_authenticated_user]

        get "/", AdminController, :redirect_to_riddles
        live "/riddles", RiddleLive.Index, :index
        # ... rest of admin routes
      end
    end
    ```
  - **Alternative:** Add dedicated admin plug to the outer scope

- [ ] **[W-3] String-based state validation duplicates schema logic**
  - **File:** `lib/riddlr/games.ex:155-157,185-187` (and other transition functions)
  - **Issue:** Context functions re-validate states with string comparisons, duplicating `@valid_transitions` map
  - **Fix Option 1:** Use pattern matching in function heads:
    ```elixir
    defp do_ready_riddle(%Riddle{play_status: "scheduled"} = riddle) do
      # ... Multi logic
    end

    defp do_ready_riddle(%Riddle{play_status: status}) do
      {:error, "cannot transition from #{status} to ready"}
    end
    ```
  - **Fix Option 2:** Trust changeset validation entirely:
    ```elixir
    def ready_riddle(riddle_id) do
      with {:ok, riddle} <- fetch_riddle(riddle_id),
           {:ok, updated} <- riddle |> Riddle.changeset(%{play_status: "ready"}) |> Repo.update() do
        broadcast_event(updated, :ready)
        {:ok, updated}
      end
    end
    ```
  - **Recommended:** Option 1 (explicit pattern matching)

- [x] **[W-4] Complex validation logic in riddle.ex**
  - **File:** `lib/riddlr/games/riddle.ex:122-152` (validate_play_status_transition/1)
  - **Issue:** Deeply nested conditionals (4 levels)
  - **Fix:** Refactor to multi-clause functions:
    ```elixir
    defp validate_play_status_transition(changeset) do
      case {changeset.data.id, get_change(changeset, :play_status)} do
        {nil, _} -> changeset  # New record
        {_, nil} -> changeset  # No status change
        {_, new_status} -> validate_transition(changeset, changeset.data.play_status, new_status)
      end
    end

    defp validate_transition(changeset, current, new) when current == new, do: changeset
    defp validate_transition(changeset, nil, _new), do: changeset
    defp validate_transition(changeset, current, new) do
      if new in Map.get(@valid_transitions, current, []) do
        changeset
      else
        add_error(changeset, :play_status, "cannot transition from #{current} to #{new}")
      end
    end
    ```

- [ ] **[W-5] Workers perform duplicate Repo queries**
  - **File:** `lib/riddlr/workers/*.ex:15-26`
  - **Issue:** Worker fetches riddle to check state, then context function fetches again (2 queries)
  - **Fix:** Pass fetched riddle to context or modify context to accept struct:
    ```elixir
    def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
      case Repo.get(Riddle, id) do
        nil -> {:cancel, "Riddle not found"}
        riddle -> try_transition(riddle)
      end
    end

    defp try_transition(%Riddle{play_status: "scheduled", id: id}) do
      Games.ready_riddle(id)
    end

    defp try_transition(%Riddle{play_status: status}) do
      {:cancel, "Already transitioned (current: #{status})"}
    end
    ```
  - **Alternative:** Modify Games functions to accept `%Riddle{}` OR id (see B-3)

- [ ] **[W-6] Business logic in LiveView component**
  - **File:** `lib/riddlr_web/live/admin/riddle_live/form_component.ex:113-118`
  - **Issue:** FormComponent decides whether to call `schedule_riddle` or `update_riddle` (orchestration belongs in context)
  - **Fix:** Create unified context function:
    ```elixir
    # In Games context
    def save_riddle(%Riddle{id: nil} = riddle, attrs), do: create_riddle(attrs)

    def save_riddle(%Riddle{play_status: "closed"} = riddle, %{live_date: live_date} = attrs)
        when not is_nil(live_date) do
      schedule_riddle(riddle, live_date)
    end

    def save_riddle(%Riddle{} = riddle, attrs) do
      update_riddle(riddle, attrs)
    end
    ```
  - **In FormComponent:**
    ```elixir
    defp save(socket, _action, params) do
      case Games.save_riddle(socket.assigns.riddle, params) do
        {:ok, result} -> handle_success(socket, result)
        {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
      end
    end
    ```

- [x] **[W-7] Missing async: true in games_test.exs**
  - **File:** `test/riddlr/games_test.exs:2`
  - **Issue:** Tests run sequentially (56% slower than necessary)
  - **Fix:** Add `async: true`:
    ```elixir
    defmodule Riddlr.GamesTest do
      use Riddlr.DataCase, async: true
      use Oban.Testing, repo: Riddlr.Repo
      # ...
    ```
  - **Safety:** Verified safe (uses Sandbox, no global state, Oban in manual mode)

- [x] **[W-8] Inconsistent unique constraint test assertions**
  - **File:** `test/riddlr/workers/ready_riddle_transition_worker_test.exs:32-44`
  - **File:** `test/riddlr/workers/live_riddle_transition_worker_test.exs:32-44`
  - **File:** `test/riddlr/workers/archive_riddle_transition_worker_test.exs:32-44`
  - **Issue:** `assert job1.id == job2.id or job2.conflict? == true` relies on Oban config
  - **Fix:** Count jobs in queue instead:
    ```elixir
    test "unique constraint prevents duplicate jobs within 1 hour" do
      riddle = riddle_fixture(%{play_status: "scheduled"})

      assert {:ok, _job1} = ReadyRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()
      assert {:ok, _job2} = ReadyRiddleTransitionWorker.new(%{riddle_id: riddle.id}) |> Oban.insert()

      # Verify only one job exists in queue
      assert 1 == Repo.aggregate(
        from(j in Oban.Job,
          where: j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker",
          where: fragment("args->>'riddle_id' = ?", ^to_string(riddle.id))
        ),
        :count
      )
    end
    ```

- [x] **[W-9] PubSub test subscribes to potentially wrong topic**
  - **File:** `test/riddlr/games_test.exs:279`
  - **Issue:** Test subscribes to `"games:riddle:ready"` but should verify this matches broadcast topic
  - **Fix:** Check Games.ready_riddle/1 implementation to confirm topic, update test if needed
  - **If topics match:** Mark as verified, no code change
  - **If mismatch:** Update either broadcast or subscription to match

---

## Deferred (3 items)

The following warnings were deferred as non-critical improvements:

- **[W-3] String-based state validation duplicates schema logic** - Suggested refactor using pattern matching. Current implementation works correctly, no bugs.
- **[W-5] Workers perform duplicate Repo queries** - Performance optimization. Impact is minimal (background jobs, low frequency).
- **[W-6] Business logic in LiveView component** - Architectural improvement. Current approach is clear and testable.

**Rationale:** All BLOCKERs and critical WARNINGs have been fixed. These three items are code quality suggestions that can be addressed in future tech debt sprints.

---

## Skipped

The following were reviewed but not selected for immediate fixes:

### Medium Priority (4)
- Games context functions lack authorization layer
- Play status directly editable in admin form (bypasses state machine)
- PubSub broadcasts full riddle struct (including answers)
- Form component loads categories in update/2 without guard

### Suggestions (10+)
- Extract state machine into separate module
- Add edge case tests (past dates, concurrent transitions, reschedule)
- Add property-based testing for state machine
- Configure `:filter_parameters` for sensitive fields
- Add `secure: true` to remember-me cookie
- Timezone label clarity in admin form
- Various test improvements

**Rationale:** Focus on blockers and warnings first. Medium/low items can be addressed in future phases or tech debt sprints.

---

## Fix Strategy

**Approach:** Apply standard fixes from review recommendations

**Execution:**
1. Run `/phx:plan .claude/plans/riddlr/reviews/phase-7-triage.md` to generate implementation plan
2. Execute with `/phx:work`
3. Verify with `/phx:verify`
4. Optional: `/phx:review` again to confirm fixes

**Estimated scope:** 13 fixes across 8 files

**Files to modify:**
- `lib/riddlr/games.ex` (5 fixes)
- `lib/riddlr/games/riddle.ex` (1 fix)
- `lib/riddlr/workers/*.ex` (3 fixes)
- `lib/riddlr_web/live/admin/riddle_live/form_component.ex` (3 fixes)
- `lib/riddlr_web/live/admin/category_live/form_component.ex` (1 fix)
- `lib/riddlr_web/router.ex` (1 fix)
- `lib/riddlr_web/user_auth.ex` (1 fix)
- `test/riddlr/games_test.exs` (2 fixes)
- `test/riddlr/workers/*_test.exs` (1 fix pattern × 3 files)

---

## Notes

- Items B-3 and B-4 auto-approved as Iron Law violations (non-negotiable)
- All fixes preserve existing functionality and test coverage
- Security fixes (B-1, B-2, W-1, W-2) should be prioritized
- Test improvements (W-7, W-8, W-9) can be bundled together
