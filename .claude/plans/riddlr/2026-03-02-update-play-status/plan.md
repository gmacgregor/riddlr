# Play Status Lifecycle Enhancement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enhance riddle play status lifecycle with rescheduling support, cooldown controls, and draft rollback handling.

**Architecture:** Extend existing Ecto.Multi-based state transitions with worker cancellation/rescheduling logic. Add cooldown configuration field to Riddle schema. Update LiveView pages to display play_status. All transitions remain atomic via Multi.

**Tech Stack:** Phoenix LiveView, Ecto, Oban, PubSub

**User Requirements:**
- ✅ Cancel and reschedule workers when live_date changes
- ✅ Admin can skip OR extend 3-minute archive cooldown
- ✅ Cancel all workers when reverting to draft status
- ✅ Use `:game_lifecycle` queue (existing pattern)
- ✅ Display play_status in admin listing and edit pages

**Existing Infrastructure (from research):**
- Riddle schema with validated play_status transitions
- 3 Oban workers: ReadyRiddleTransitionWorker, LiveRiddleTransitionWorker, ArchiveRiddleTransitionWorker
- Auto-scheduling in RiddleLive.FormComponent
- Ecto.Multi pattern for atomic transitions
- PubSub broadcasts for real-time updates

---

## Task 1: Add Archive Cooldown Configuration

**Files:**
- Modify: `lib/riddlr/games/riddle.ex` (schema)
- Modify: `priv/repo/migrations/YYYYMMDDHHMMSS_add_archive_cooldown_to_riddles.exs` (create new)
- Test: `test/riddlr/games/riddle_test.exs`

### Step 1: Write failing test for archive_cooldown_minutes field

```elixir
# test/riddlr/games/riddle_test.exs
describe "archive_cooldown_minutes" do
  test "defaults to 3 minutes" do
    riddle = riddle_fixture()
    assert riddle.archive_cooldown_minutes == 3
  end

  test "accepts valid cooldown values" do
    attrs = %{archive_cooldown_minutes: 5}
    changeset = Riddle.changeset(%Riddle{}, valid_riddle_attrs(attrs))
    assert changeset.valid?
  end

  test "rejects negative cooldown values" do
    attrs = %{archive_cooldown_minutes: -1}
    changeset = Riddle.changeset(%Riddle{}, valid_riddle_attrs(attrs))
    refute changeset.valid?
    assert "must be greater than or equal to 0" in errors_on(changeset).archive_cooldown_minutes
  end

  test "allows zero to skip cooldown" do
    attrs = %{archive_cooldown_minutes: 0}
    changeset = Riddle.changeset(%Riddle{}, valid_riddle_attrs(attrs))
    assert changeset.valid?
  end
end
```

**Run:** `mix test test/riddlr/games/riddle_test.exs:line_number -v`
**Expected:** FAIL with "no field 'archive_cooldown_minutes'"

### Step 2: Create migration for archive_cooldown_minutes

```bash
mix ecto.gen.migration add_archive_cooldown_to_riddles
```

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_add_archive_cooldown_to_riddles.exs
defmodule Riddlr.Repo.Migrations.AddArchiveCooldownToRiddles do
  use Ecto.Migration

  def change do
    alter table(:riddles) do
      add :archive_cooldown_minutes, :integer, default: 3, null: false
    end
  end
end
```

**Run:** `mix ecto.migrate`
**Expected:** Migration runs successfully

### Step 3: Add field to Riddle schema

```elixir
# lib/riddlr/games/riddle.ex
schema "riddles" do
  # ... existing fields ...
  field :archive_cooldown_minutes, :integer, default: 3
  # ...
end

def changeset(riddle, attrs) do
  riddle
  |> cast(attrs, [..., :archive_cooldown_minutes])
  |> validate_required([...])
  |> validate_number(:archive_cooldown_minutes, greater_than_or_equal_to: 0)
  # ... other validations ...
end
```

**Run:** `mix test test/riddlr/games/riddle_test.exs -v`
**Expected:** PASS

### Step 4: Commit

```bash
git add lib/riddlr/games/riddle.ex priv/repo/migrations/*_add_archive_cooldown_to_riddles.exs test/riddlr/games/riddle_test.exs
git commit -m "feat: add configurable archive cooldown to riddles

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Update ArchiveRiddleTransitionWorker to Use Cooldown

**Files:**
- Modify: `lib/riddlr/workers/archive_riddle_transition_worker.ex`
- Test: `test/riddlr/workers/archive_riddle_transition_worker_test.exs`

### Step 1: Write failing test for cooldown configuration

```elixir
# test/riddlr/workers/archive_riddle_transition_worker_test.exs
describe "perform/1 with custom cooldown" do
  test "respects riddle's archive_cooldown_minutes setting" do
    riddle = riddle_fixture(%{
      play_status: "completed",
      publish_status: "published",
      archive_cooldown_minutes: 5
    })

    completed_at = DateTime.utc_now()

    # Job scheduled 5 minutes after completion (not default 3)
    scheduled_time = DateTime.add(completed_at, 5 * 60)

    args = %{"riddle_id" => riddle.id}
    job = %Oban.Job{args: args, scheduled_at: scheduled_time}

    assert :ok = ArchiveRiddleTransitionWorker.perform(job)

    updated = Repo.reload!(riddle)
    assert updated.play_status == "archived"
  end

  test "skips cooldown when archive_cooldown_minutes is 0" do
    riddle = riddle_fixture(%{
      play_status: "completed",
      publish_status: "published",
      archive_cooldown_minutes: 0
    })

    # Job can run immediately
    args = %{"riddle_id" => riddle.id}
    job = %Oban.Job{args: args, scheduled_at: DateTime.utc_now()}

    assert :ok = ArchiveRiddleTransitionWorker.perform(job)

    updated = Repo.reload!(riddle)
    assert updated.play_status == "archived"
  end
end
```

**Run:** `mix test test/riddlr/workers/archive_riddle_transition_worker_test.exs -v`
**Expected:** Tests may pass or fail depending on current implementation - verify behavior matches cooldown

### Step 2: Update complete_riddle to use cooldown configuration

```elixir
# lib/riddlr/games.ex (or relevant context module)
def complete_riddle(%Riddle{} = riddle) do
  Multi.new()
  |> Multi.update(:riddle, Riddle.play_status_changeset(riddle, "completed"))
  |> Multi.insert(:archive_job, fn %{riddle: updated_riddle} ->
    cooldown_seconds = updated_riddle.archive_cooldown_minutes * 60
    scheduled_time = DateTime.add(DateTime.utc_now(), cooldown_seconds)

    ArchiveRiddleTransitionWorker.new(
      %{"riddle_id" => updated_riddle.id},
      scheduled_at: scheduled_time,
      queue: :game_lifecycle
    )
  end)
  |> Multi.run(:broadcast, fn _repo, %{riddle: updated_riddle} ->
    Phoenix.PubSub.broadcast(
      Riddlr.PubSub,
      "riddles",
      {:riddle_saved, updated_riddle}
    )
    {:ok, updated_riddle}
  end)
  |> Repo.transaction()
end
```

**Run:** `mix test test/riddlr/workers/archive_riddle_transition_worker_test.exs -v`
**Expected:** PASS

### Step 3: Commit

```bash
git add lib/riddlr/workers/archive_riddle_transition_worker.ex lib/riddlr/games.ex test/riddlr/workers/archive_riddle_transition_worker_test.exs
git commit -m "feat: use configurable cooldown in archive worker

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Add Worker Cancellation Logic

**Files:**
- Create: `lib/riddlr/games/riddle_scheduler.ex`
- Test: `test/riddlr/games/riddle_scheduler_test.exs`

### Step 1: Write failing tests for worker cancellation

```elixir
# test/riddlr/games/riddle_scheduler_test.exs
defmodule Riddlr.Games.RiddleSchedulerTest do
  use Riddlr.DataCase, async: true
  import Riddlr.GamesFixtures
  alias Riddlr.Games.RiddleScheduler

  describe "cancel_pending_jobs/1" do
    test "cancels all scheduled jobs for a riddle" do
      riddle = riddle_fixture(%{publish_status: "published", play_status: "scheduled"})

      # Create some jobs for this riddle
      {:ok, _} = schedule_riddle(riddle)

      # Verify jobs exist
      pending_jobs = Oban.Job
      |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.all()

      assert length(pending_jobs) > 0

      # Cancel them
      assert {:ok, cancelled_count} = RiddleScheduler.cancel_pending_jobs(riddle.id)
      assert cancelled_count > 0

      # Verify jobs are cancelled
      remaining_jobs = Oban.Job
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.all()

      assert length(remaining_jobs) == 0
    end

    test "returns {:ok, 0} when no pending jobs exist" do
      riddle = riddle_fixture()
      assert {:ok, 0} = RiddleScheduler.cancel_pending_jobs(riddle.id)
    end
  end

  describe "reschedule_jobs/2" do
    test "cancels old jobs and creates new ones with updated live_date" do
      riddle = riddle_fixture(%{
        publish_status: "published",
        play_status: "scheduled",
        live_date: ~U[2026-04-01 10:00:00Z]
      })

      {:ok, _} = schedule_riddle(riddle)

      # Change live_date
      new_live_date = ~U[2026-04-01 14:00:00Z]

      assert {:ok, _count} = RiddleScheduler.reschedule_jobs(riddle.id, new_live_date)

      # Verify new jobs scheduled at correct times
      ready_job = Oban.Job
      |> where([j], j.worker == "Riddlr.Workers.ReadyRiddleTransitionWorker")
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.one()

      assert ready_job.scheduled_at == DateTime.add(new_live_date, -300)
    end
  end
end
```

**Run:** `mix test test/riddlr/games/riddle_scheduler_test.exs -v`
**Expected:** FAIL with "module RiddleScheduler not found"

### Step 2: Implement RiddleScheduler module

```elixir
# lib/riddlr/games/riddle_scheduler.ex
defmodule Riddlr.Games.RiddleScheduler do
  @moduledoc """
  Handles scheduling and rescheduling of Oban jobs for riddle state transitions.
  """
  import Ecto.Query
  alias Riddlr.Repo
  alias Riddlr.Workers.{ReadyRiddleTransitionWorker, LiveRiddleTransitionWorker}

  @doc """
  Cancels all pending (scheduled or available) jobs for a riddle.
  Returns {:ok, count} where count is number of cancelled jobs.
  """
  def cancel_pending_jobs(riddle_id) when is_integer(riddle_id) do
    riddle_id_string = to_string(riddle_id)

    {count, _} =
      Oban.Job
      |> where([j], j.worker in [
        "Riddlr.Workers.ReadyRiddleTransitionWorker",
        "Riddlr.Workers.LiveRiddleTransitionWorker",
        "Riddlr.Workers.ArchiveRiddleTransitionWorker"
      ])
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^riddle_id_string))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.update_all(set: [state: "cancelled"])

    {:ok, count}
  end

  @doc """
  Cancels existing jobs and schedules new ones based on updated live_date.
  Used when riddle's live_date changes.
  """
  def reschedule_jobs(riddle_id, new_live_date) when is_integer(riddle_id) do
    # Cancel existing jobs
    {:ok, _cancelled} = cancel_pending_jobs(riddle_id)

    # Schedule new jobs
    ready_time = DateTime.add(new_live_date, -300)  # 5 min before

    Multi.new()
    |> Multi.insert(:ready_job,
      ReadyRiddleTransitionWorker.new(
        %{"riddle_id" => riddle_id},
        scheduled_at: ready_time,
        queue: :game_lifecycle
      )
    )
    |> Multi.insert(:live_job,
      LiveRiddleTransitionWorker.new(
        %{"riddle_id" => riddle_id},
        scheduled_at: new_live_date,
        queue: :game_lifecycle
      )
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, 2}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end
end
```

**Run:** `mix test test/riddlr/games/riddle_scheduler_test.exs -v`
**Expected:** PASS

### Step 3: Commit

```bash
git add lib/riddlr/games/riddle_scheduler.ex test/riddlr/games/riddle_scheduler_test.exs
git commit -m "feat: add worker cancellation and rescheduling logic

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Handle live_date Changes in FormComponent

**Files:**
- Modify: `lib/riddlr_web/live/admin/riddle_live/form_component.ex`
- Test: `test/riddlr_web/live/admin/riddle_live/form_component_test.exs`

### Step 1: Write failing test for rescheduling on live_date change

```elixir
# test/riddlr_web/live/admin/riddle_live/form_component_test.exs
describe "handle_event save with live_date change" do
  test "reschedules workers when live_date changes for published riddle", %{conn: conn} do
    old_live_date = ~U[2026-04-01 10:00:00Z]
    riddle = riddle_fixture(%{
      publish_status: "published",
      play_status: "scheduled",
      live_date: old_live_date
    })

    # Schedule initial jobs
    {:ok, _} = Games.schedule_riddle(riddle)

    new_live_date = ~U[2026-04-01 14:00:00Z]

    {:ok, view, _html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

    result = view
    |> form("#riddle-form", riddle: %{live_date: new_live_date})
    |> render_submit()

    # Verify old jobs cancelled
    old_jobs = Oban.Job
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
    |> where([j], j.state in ["scheduled", "available"])
    |> where([j], j.scheduled_at == ^DateTime.add(old_live_date, -300))
    |> Repo.all()

    assert length(old_jobs) == 0

    # Verify new jobs scheduled
    new_jobs = Oban.Job
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
    |> where([j], j.state in ["scheduled", "available"])
    |> Repo.all()

    assert length(new_jobs) == 2  # ready + live
  end
end
```

**Run:** `mix test test/riddlr_web/live/admin/riddle_live/form_component_test.exs -v`
**Expected:** FAIL (rescheduling not implemented yet)

### Step 2: Add rescheduling logic to FormComponent save event

```elixir
# lib/riddlr_web/live/admin/riddle_live/form_component.ex
alias Riddlr.Games.RiddleScheduler

def handle_event("save", %{"riddle" => riddle_params}, socket) do
  save_riddle(socket, socket.assigns.action, riddle_params)
end

defp save_riddle(socket, :edit, riddle_params) do
  old_riddle = socket.assigns.riddle
  old_live_date = old_riddle.live_date
  new_live_date = riddle_params["live_date"]

  case Games.update_riddle(old_riddle, riddle_params) do
    {:ok, riddle} ->
      # Check if we need to reschedule
      if should_reschedule?(old_riddle, riddle, old_live_date, new_live_date) do
        RiddleScheduler.reschedule_jobs(riddle.id, riddle.live_date)
      end

      notify_parent({:saved, riddle})

      {:noreply,
       socket
       |> put_flash(:info, "Riddle updated successfully")
       |> push_patch(to: socket.assigns.patch)}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :changeset, changeset)}
  end
end

defp should_reschedule?(old_riddle, new_riddle, old_live_date, new_live_date) do
  # Reschedule if:
  # 1. Riddle is published
  # 2. Play status is scheduled or ready (jobs are pending)
  # 3. live_date actually changed
  new_riddle.publish_status == "published" and
    new_riddle.play_status in ["scheduled", "ready"] and
    old_live_date != new_live_date and
    not is_nil(new_live_date)
end
```

**Run:** `mix test test/riddlr_web/live/admin/riddle_live/form_component_test.exs -v`
**Expected:** PASS

### Step 3: Commit

```bash
git add lib/riddlr_web/live/admin/riddle_live/form_component.ex test/riddlr_web/live/admin/riddle_live/form_component_test.exs
git commit -m "feat: reschedule workers when live_date changes

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Handle Draft Rollback (Cancel All Workers)

**Files:**
- Modify: `lib/riddlr/games.ex` (or relevant context)
- Test: `test/riddlr/games_test.exs`

### Step 1: Write failing test for draft rollback

```elixir
# test/riddlr/games_test.exs
describe "update_riddle/2 with draft rollback" do
  test "cancels all pending workers when changing to draft status" do
    riddle = riddle_fixture(%{
      publish_status: "published",
      play_status: "scheduled",
      live_date: ~U[2026-04-01 10:00:00Z]
    })

    # Schedule jobs
    {:ok, _} = Games.schedule_riddle(riddle)

    # Verify jobs exist
    pending_before = Oban.Job
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
    |> where([j], j.state in ["scheduled", "available"])
    |> Repo.all()

    assert length(pending_before) > 0

    # Move back to draft
    {:ok, updated} = Games.update_riddle(riddle, %{publish_status: "draft"})

    assert updated.publish_status == "draft"

    # Verify jobs cancelled
    pending_after = Oban.Job
    |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
    |> where([j], j.state in ["scheduled", "available"])
    |> Repo.all()

    assert length(pending_after) == 0
  end
end
```

**Run:** `mix test test/riddlr/games_test.exs -v`
**Expected:** FAIL (cancellation not implemented)

### Step 2: Add cancellation logic to update_riddle

```elixir
# lib/riddlr/games.ex
alias Riddlr.Games.RiddleScheduler

def update_riddle(%Riddle{} = riddle, attrs) do
  old_publish_status = riddle.publish_status

  changeset = Riddle.changeset(riddle, attrs)
  new_publish_status = Ecto.Changeset.get_field(changeset, :publish_status)

  result = Repo.update(changeset)

  # Cancel workers if moving from published to draft
  if old_publish_status == "published" and new_publish_status == "draft" do
    with {:ok, updated_riddle} <- result do
      RiddleScheduler.cancel_pending_jobs(updated_riddle.id)
      {:ok, updated_riddle}
    end
  else
    result
  end
end
```

**Run:** `mix test test/riddlr/games_test.exs -v`
**Expected:** PASS

### Step 3: Commit

```bash
git add lib/riddlr/games.ex test/riddlr/games_test.exs
git commit -m "feat: cancel workers when riddle moved to draft

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Display play_status in Admin Index

**Files:**
- Modify: `lib/riddlr_web/live/admin/riddle_live/index.ex`
- Modify: `lib/riddlr_web/live/admin/riddle_live/index.html.heex`
- Test: `test/riddlr_web/live/admin/riddle_live/index_test.exs`

### Step 1: Write failing test for play_status display

```elixir
# test/riddlr_web/live/admin/riddle_live/index_test.exs
describe "index page play_status display" do
  test "displays play status for each riddle", %{conn: conn} do
    riddle1 = riddle_fixture(%{title: "Test 1", play_status: "closed"})
    riddle2 = riddle_fixture(%{title: "Test 2", play_status: "live"})

    {:ok, view, html} = live(conn, ~p"/admin/riddles")

    assert html =~ "closed"
    assert html =~ "live"

    # Verify they're in the correct rows
    assert view
    |> element("tr[data-riddle-id='#{riddle1.id}']")
    |> render() =~ "closed"

    assert view
    |> element("tr[data-riddle-id='#{riddle2.id}']")
    |> render() =~ "live"
  end

  test "shows badge styling for different statuses", %{conn: conn} do
    riddle = riddle_fixture(%{play_status: "live"})

    {:ok, _view, html} = live(conn, ~p"/admin/riddles")

    # Should have badge component for status
    assert html =~ ~r/<span[^>]*class="[^"]*badge[^"]*"[^>]*>live<\/span>/
  end
end
```

**Run:** `mix test test/riddlr_web/live/admin/riddle_live/index_test.exs -v`
**Expected:** FAIL (play_status not displayed)

### Step 2: Add play_status column to index template

```elixir
# lib/riddlr_web/live/admin/riddle_live/index.html.heex
<:col :let={{_id, riddle}} label="Title"><%= riddle.title %></:col>
<:col :let={{_id, riddle}} label="Category"><%= riddle.category.name %></:col>
<:col :let={{_id, riddle}} label="Publish Status"><%= riddle.publish_status %></:col>
<:col :let={{_id, riddle}} label="Play Status">
  <span class={[
    "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
    play_status_color(riddle.play_status)
  ]}>
    <%= riddle.play_status %>
  </span>
</:col>
<:col :let={{_id, riddle}} label="Difficulty"><%= riddle.difficulty %></:col>
```

### Step 3: Add helper function for status colors

```elixir
# lib/riddlr_web/live/admin/riddle_live/index.ex
defp play_status_color("closed"), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
defp play_status_color("scheduled"), do: "bg-blue-50 text-blue-700 ring-blue-700/10"
defp play_status_color("ready"), do: "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
defp play_status_color("live"), do: "bg-green-50 text-green-700 ring-green-600/20"
defp play_status_color("completed"), do: "bg-purple-50 text-purple-700 ring-purple-700/10"
defp play_status_color("archived"), do: "bg-gray-50 text-gray-500 ring-gray-500/10"
defp play_status_color(_), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
```

**Run:** `mix test test/riddlr_web/live/admin/riddle_live/index_test.exs -v`
**Expected:** PASS

### Step 4: Commit

```bash
git add lib/riddlr_web/live/admin/riddle_live/index.ex lib/riddlr_web/live/admin/riddle_live/index.html.heex test/riddlr_web/live/admin/riddle_live/index_test.exs
git commit -m "feat: display play_status in admin riddle index

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Display play_status in Admin Edit Page

**Files:**
- Modify: `lib/riddlr_web/live/admin/riddle_live/form_component.html.heex`
- Test: `test/riddlr_web/live/admin/riddle_live/form_component_test.exs`

### Step 1: Write failing test for edit page display

```elixir
# test/riddlr_web/live/admin/riddle_live/form_component_test.exs
describe "edit form play_status display" do
  test "shows current play status in form", %{conn: conn} do
    riddle = riddle_fixture(%{play_status: "scheduled"})

    {:ok, view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

    assert html =~ "Play Status"
    assert html =~ "scheduled"
  end

  test "shows archive cooldown field when riddle is completed", %{conn: conn} do
    riddle = riddle_fixture(%{play_status: "completed", archive_cooldown_minutes: 5})

    {:ok, _view, html} = live(conn, ~p"/admin/riddles/#{riddle}/edit")

    assert html =~ "Archive Cooldown"
    assert html =~ "5"
  end
end
```

**Run:** `mix test test/riddlr_web/live/admin/riddle_live/form_component_test.exs -v`
**Expected:** FAIL (fields not in form)

### Step 2: Add play_status display to form component

```elixir
# lib/riddlr_web/live/admin/riddle_live/form_component.html.heex
<.simple_form
  for={@form}
  id="riddle-form"
  phx-target={@myself}
  phx-change="validate"
  phx-submit="save"
>
  <!-- Existing fields... -->

  <div class="col-span-full">
    <label class="block text-sm font-medium leading-6 text-gray-900">
      Play Status
    </label>
    <div class="mt-2">
      <span class={[
        "inline-flex items-center rounded-md px-2 py-1 text-sm font-medium ring-1 ring-inset",
        play_status_color(@riddle.play_status)
      ]}>
        <%= @riddle.play_status %>
      </span>
      <p class="mt-2 text-sm text-gray-500">
        Play status is managed automatically by the system based on publish status and scheduling.
      </p>
    </div>
  </div>

  <%= if @riddle.play_status in ["completed", "archived"] do %>
    <.input
      field={@form[:archive_cooldown_minutes]}
      type="number"
      label="Archive Cooldown (minutes)"
      min="0"
      help="Minutes to wait before archiving after completion. Set to 0 to skip cooldown."
    />
  <% end %>

  <!-- Rest of form... -->
</.simple_form>
```

### Step 3: Add helper to form component module

```elixir
# lib/riddlr_web/live/admin/riddle_live/form_component.ex
defp play_status_color("closed"), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
defp play_status_color("scheduled"), do: "bg-blue-50 text-blue-700 ring-blue-700/10"
defp play_status_color("ready"), do: "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
defp play_status_color("live"), do: "bg-green-50 text-green-700 ring-green-600/20"
defp play_status_color("completed"), do: "bg-purple-50 text-purple-700 ring-purple-700/10"
defp play_status_color("archived"), do: "bg-gray-50 text-gray-500 ring-gray-500/10"
defp play_status_color(_), do: "bg-gray-50 text-gray-600 ring-gray-500/10"
```

**Run:** `mix test test/riddlr_web/live/admin/riddle_live/form_component_test.exs -v`
**Expected:** PASS

### Step 4: Commit

```bash
git add lib/riddlr_web/live/admin/riddle_live/form_component.ex lib/riddlr_web/live/admin/riddle_live/form_component.html.heex test/riddlr_web/live/admin/riddle_live/form_component_test.exs
git commit -m "feat: display play_status and cooldown in edit form

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Integration Test for Full Lifecycle

**Files:**
- Create: `test/riddlr/integration/riddle_lifecycle_test.exs`

### Step 1: Write comprehensive lifecycle integration test

```elixir
# test/riddlr/integration/riddle_lifecycle_test.exs
defmodule Riddlr.Integration.RiddleLifecycleTest do
  use Riddlr.DataCase, async: true
  import Riddlr.GamesFixtures
  alias Riddlr.Games

  describe "full riddle lifecycle" do
    test "riddle transitions through all states correctly" do
      # Start with draft riddle
      riddle = riddle_fixture(%{
        publish_status: "draft",
        play_status: "closed",
        live_date: DateTime.add(DateTime.utc_now(), 3600)  # 1 hour from now
      })

      # Step 1: Publish riddle -> should schedule workers
      {:ok, riddle} = Games.update_riddle(riddle, %{publish_status: "published"})
      {:ok, riddle} = Games.schedule_riddle(riddle)

      assert riddle.play_status == "scheduled"

      # Verify jobs scheduled
      jobs = Oban.Job
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.all()

      assert length(jobs) == 2  # ready + live

      # Step 2: Change live_date -> should reschedule
      new_live_date = DateTime.add(DateTime.utc_now(), 7200)  # 2 hours from now
      {:ok, riddle} = Games.update_riddle(riddle, %{live_date: new_live_date})

      updated_jobs = Oban.Job
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.all()

      assert length(updated_jobs) == 2
      # Verify new scheduled times match new_live_date

      # Step 3: Move to draft -> should cancel all jobs
      {:ok, riddle} = Games.update_riddle(riddle, %{publish_status: "draft"})

      remaining_jobs = Oban.Job
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> where([j], j.state in ["scheduled", "available"])
      |> Repo.all()

      assert length(remaining_jobs) == 0

      # Step 4: Test custom cooldown
      {:ok, riddle} = Games.update_riddle(riddle, %{
        publish_status: "published",
        play_status: "completed",
        archive_cooldown_minutes: 10
      })

      {:ok, _} = Games.complete_riddle(riddle)

      archive_job = Oban.Job
      |> where([j], j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker")
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> Repo.one()

      # Verify 10-minute delay
      expected_time = DateTime.add(DateTime.utc_now(), 10 * 60)
      assert DateTime.diff(archive_job.scheduled_at, expected_time, :second) < 5
    end

    test "zero cooldown archives immediately" do
      riddle = riddle_fixture(%{
        play_status: "completed",
        publish_status: "published",
        archive_cooldown_minutes: 0
      })

      {:ok, _} = Games.complete_riddle(riddle)

      archive_job = Oban.Job
      |> where([j], j.worker == "Riddlr.Workers.ArchiveRiddleTransitionWorker")
      |> where([j], fragment("?->>'riddle_id' = ?", j.args, ^to_string(riddle.id)))
      |> Repo.one()

      # Job should be available immediately
      assert archive_job.scheduled_at <= DateTime.utc_now()
    end
  end
end
```

**Run:** `mix test test/riddlr/integration/riddle_lifecycle_test.exs -v`
**Expected:** PASS (validates entire implementation)

### Step 2: Commit

```bash
git add test/riddlr/integration/riddle_lifecycle_test.exs
git commit -m "test: add comprehensive riddle lifecycle integration tests

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Update Documentation

**Files:**
- Modify: `lib/riddlr/games/riddle.ex` (add moduledoc)
- Create: `docs/riddle-lifecycle.md`

### Step 1: Add comprehensive moduledoc to Riddle schema

```elixir
# lib/riddlr/games/riddle.ex
defmodule Riddlr.Games.Riddle do
  @moduledoc """
  Riddle schema representing a puzzle in the system.

  ## Play Status Lifecycle

  Riddles transition through six play statuses in order:

      closed → scheduled → ready → live → completed → archived

  ### State Descriptions

  - **closed**: Initial state, not scheduled for play
  - **scheduled**: Published with live_date set, workers scheduled
  - **ready**: 5 minutes before live_date, ready to go live
  - **live**: Currently accepting answers from players
  - **completed**: First correct answer received, cooldown period starts
  - **archived**: Cooldown complete, riddle moved to archive

  ### Automatic Transitions

  State transitions are triggered by:

  1. **Manual scheduling**: Admin sets live_date + publish_status
  2. **Oban workers**: Time-based transitions (ready, live)
  3. **Player action**: First correct answer triggers completion
  4. **Cooldown timer**: Auto-archive after configurable delay

  ### Scheduling Behavior

  - **Rescheduling**: Changing live_date cancels old jobs and schedules new ones
  - **Draft rollback**: Moving to draft status cancels all pending workers
  - **Archive cooldown**: Configurable via `archive_cooldown_minutes` (default: 3)
    - Set to 0 to skip cooldown and archive immediately

  ### Example Flow

      # Publish riddle with live date
      {:ok, riddle} = Games.update_riddle(riddle, %{
        publish_status: "published",
        live_date: ~U[2026-04-01 14:00:00Z]
      })
      {:ok, riddle} = Games.schedule_riddle(riddle)
      # => play_status: "scheduled", 2 jobs scheduled

      # System automatically transitions:
      # - 13:55:00 => play_status: "ready"
      # - 14:00:00 => play_status: "live"
      # - [first correct answer] => play_status: "completed"
      # - [+3 minutes] => play_status: "archived"

  ## Fields

  See schema definition for complete field list.
  """

  # ... rest of schema ...
end
```

### Step 2: Create lifecycle documentation

```markdown
# docs/riddle-lifecycle.md
# Riddle Play Status Lifecycle

## Overview

Riddlr implements a six-state lifecycle for riddles, managing transitions from closed to archived status through a combination of manual admin actions, scheduled Oban workers, and player interactions.

## State Diagram

```
┌────────┐
│ closed │ (initial state)
└────┬───┘
     │ publish + schedule
     ▼
┌───────────┐
│ scheduled │ (workers queued)
└─────┬─────┘
      │ -5 min (worker)
      ▼
┌────────┐
│ ready  │ (about to go live)
└────┬───┘
     │ live_date reached (worker)
     ▼
┌──────┐
│ live │ (accepting answers)
└───┬──┘
    │ first correct answer
    ▼
┌───────────┐
│ completed │ (cooldown starts)
└─────┬─────┘
      │ +N minutes (worker)
      ▼
┌──────────┐
│ archived │ (final state)
└──────────┘
```

## Transition Triggers

### 1. Manual: Admin Scheduling
- **Trigger**: Admin sets `live_date` + `publish_status: "published"`
- **Action**: `Games.schedule_riddle/1`
- **Effect**:
  - Play status → `scheduled`
  - Enqueues ReadyRiddleTransitionWorker (-5 min)
  - Enqueues LiveRiddleTransitionWorker (at live_date)

### 2. Automatic: Ready Transition
- **Trigger**: 5 minutes before live_date
- **Worker**: `ReadyRiddleTransitionWorker`
- **Effect**: Play status → `ready`

### 3. Automatic: Live Transition
- **Trigger**: live_date reached
- **Worker**: `LiveRiddleTransitionWorker`
- **Effect**: Play status → `live`

### 4. Player-Driven: Completion
- **Trigger**: First correct answer submitted
- **Action**: Game logic calls `Games.complete_riddle/1`
- **Effect**:
  - Play status → `completed`
  - Enqueues ArchiveRiddleTransitionWorker (+N minutes)

### 5. Automatic: Archival
- **Trigger**: Cooldown period elapses
- **Worker**: `ArchiveRiddleTransitionWorker`
- **Effect**: Play status → `archived`

## Advanced Features

### Rescheduling

When a riddle's `live_date` changes while in `scheduled` or `ready` status:
1. All pending workers are cancelled
2. New workers are scheduled based on updated `live_date`

Implementation: `RiddleScheduler.reschedule_jobs/2`

### Draft Rollback

When a published riddle is moved back to draft:
1. All pending workers are cancelled
2. Play status remains unchanged (manual reset required if desired)

Implementation: `Games.update_riddle/2` with publish_status change detection

### Configurable Archive Cooldown

Admins can control the delay before archival:
- **Default**: 3 minutes
- **Range**: 0+ minutes
- **Zero cooldown**: Archives immediately after completion
- **Field**: `archive_cooldown_minutes`

## Worker Configuration

All workers use the `:game_lifecycle` queue:

```elixir
config :riddlr, Oban,
  queues: [
    game_lifecycle: 5  # 5 concurrent workers
  ]
```

Worker retry behavior:
- **Max attempts**: 3
- **Unique**: 1-hour window per riddle_id
- **Idempotency**: Workers check current state before transitioning

## Testing

See `test/riddlr/integration/riddle_lifecycle_test.exs` for comprehensive lifecycle tests covering:
- Full state progression
- Rescheduling behavior
- Draft rollback
- Custom cooldown configurations

## Admin UI

Play status is displayed in:
1. **Index page**: Badge-styled status column with color coding
2. **Edit page**: Read-only status display + cooldown configuration field

Color scheme:
- closed: gray
- scheduled: blue
- ready: yellow
- live: green
- completed: purple
- archived: gray
```

### Step 3: Commit

```bash
git add lib/riddlr/games/riddle.ex docs/riddle-lifecycle.md
git commit -m "docs: add comprehensive riddle lifecycle documentation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Final Verification Steps

### Step 1: Run full test suite

```bash
mix test
```

**Expected:** All tests pass

### Step 2: Run format and compile checks

```bash
mix format
mix compile --warnings-as-errors
```

**Expected:** No warnings, clean compilation

### Step 3: Run Credo (if available)

```bash
mix credo --strict
```

**Expected:** No issues

### Step 4: Manual verification checklist

- [ ] Create test riddle in UI
- [ ] Publish and schedule it
- [ ] Verify workers appear in Oban UI
- [ ] Change live_date, verify rescheduling
- [ ] Move to draft, verify workers cancelled
- [ ] Check play_status displays in index
- [ ] Check play_status + cooldown field in edit form
- [ ] Test zero cooldown (immediate archive)
- [ ] Test extended cooldown (10+ minutes)

---

## Unresolved Questions

1. **Should we add admin override buttons** to manually trigger transitions (e.g., "Force Live Now" button)?
2. **Notification system**: Should admins receive alerts when riddles go live or complete?
3. **Metrics**: Do we want to track transition timestamps (scheduled_at, went_live_at, completed_at)?
4. **Rollback safety**: Should moving to draft also reset play_status to closed, or preserve it?
5. **Queue monitoring**: Should we add alerts for stuck/failed transition workers?

---

## Summary

**Total Tasks**: 9
**New Files**: 4 (migration, RiddleScheduler, 2 test files, 1 doc)
**Modified Files**: 8
**Estimated Time**: 3-4 hours

**Dependencies**:
- Existing Riddle schema with play_status
- Existing Oban workers (pattern to follow)
- Existing LiveView pages (enhancement)

**Key Patterns**:
- TDD throughout (test → fail → implement → pass → commit)
- Ecto.Multi for atomic operations
- PubSub for real-time updates
- Idempotent workers with state guards
- DRY helper functions for status colors
