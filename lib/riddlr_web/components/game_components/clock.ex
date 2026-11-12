defmodule RiddlrWeb.GameComponents.Clock do
  @moduledoc """
  The time pieces of the player screens: the split-flap countdown and the
  drop time, with its line in the player's own zone.

  These render the `rg-` markup styled by `assets/css/game.css`.
  """
  use Phoenix.Component

  alias RiddlrWeb.DropTime
  alias RiddlrWeb.GameCopy

  # The clock formats below are mirrored in `assets/js/clock.js`, which the
  # `.Flaps` hook uses. Change both together; the two test files share one
  # table of cases.

  @day 86_400

  @typedoc "A clock digit group and the unit word shown under it, if any."
  @type group :: {digits :: String.t(), unit :: String.t() | nil}

  @doc """
  Splits seconds into the clock's digit groups, each with the unit word
  shown under it. From one day up the groups are days, hours and minutes,
  labelled "days", "hours", "mins", or "day", "hour", "min" for a count of
  one (no seconds). Under a day they are
  `HH`, `MM`, `SS` from one hour up, or `MM`, `SS` below, with no labels.
  Negative seconds read as zero.
  """
  @spec clock_groups(integer()) :: [group()]
  def clock_groups(seconds) when is_integer(seconds) do
    case split(seconds) do
      {0, 0, m, s} ->
        [{pad(m), nil}, {pad(s), nil}]

      {0, h, m, s} ->
        [{pad(h), nil}, {pad(m), nil}, {pad(s), nil}]

      {d, h, m, _s} ->
        [{pad(d), plural(d, "day")}, {pad(h), plural(h, "hour")}, {pad(m), plural(m, "min")}]
    end
  end

  @doc """
  Formats seconds as a clock: `MM:SS`, `HH:MM:SS` from one hour up, or
  `DD:HH:MM` from one day up. See `clock_groups/1`.
  """
  @spec clock_str(integer()) :: String.t()
  def clock_str(seconds) when is_integer(seconds) do
    seconds |> clock_groups() |> Enum.map_join(":", &elem(&1, 0))
  end

  @doc """
  The clock as a screen reader says it, e.g. "6 days, 20 hours, 48 minutes"
  from one day up, or `clock_str/1` below.
  """
  @spec clock_spoken(integer()) :: String.t()
  def clock_spoken(seconds) when is_integer(seconds) do
    case split(seconds) do
      {d, h, m, _s} when d > 0 ->
        Enum.join([unit(d, "day"), unit(h, "hour"), unit(m, "minute")], ", ")

      _ ->
        clock_str(seconds)
    end
  end

  @spec split(integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  defp split(seconds) do
    secs = max(seconds, 0)
    {div(secs, @day), secs |> rem(@day) |> div(3600), secs |> rem(3600) |> div(60), rem(secs, 60)}
  end

  @spec unit(non_neg_integer(), String.t()) :: String.t()
  defp unit(n, word), do: "#{n} #{plural(n, word)}"

  @spec plural(non_neg_integer(), String.t()) :: String.t()
  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  @spec pad(non_neg_integer()) :: String.t()
  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc """
  A split-flap clock counting down to a riddle's start.

  The server renders the first value from `seconds`. After that the `.Flaps`
  hook owns the digits: it counts down once a second, re-syncs on each
  `countdown-tick` push event, and flips only the digits that change. The
  container is `phx-update="ignore"`, so LiveView still patches
  `data-seconds` but leaves the digits to the hook.

  From one day up the clock shows `DD:HH:MM` with "days", "hours" and
  "mins" under the tile pairs (`rg-flaps--days`). Under a day it shows
  `HH:MM:SS` (`rg-flaps--long`) or `MM:SS`, with no labels. See
  `clock_groups/1`. In the days layout the last minute tile pulses once a
  second (`rg-flap--pulse`), so the clock moves between flips.
  """
  attr :id, :string, required: true
  attr :seconds, :integer, required: true, doc: "seconds to count down"

  @spec flaps(map()) :: Phoenix.LiveView.Rendered.t()
  def flaps(assigns) do
    groups = clock_groups(assigns.seconds)
    days? = match?([{_, unit} | _] when is_binary(unit), groups)

    assigns =
      assign(assigns,
        groups: Enum.with_index(groups),
        days?: days?,
        long?: not days? and length(groups) == 3,
        spoken: clock_spoken(assigns.seconds)
      )

    ~H"""
    <div
      id={@id}
      class={[
        "rg-flaps",
        @long? && "rg-flaps--long",
        @days? && "rg-flaps--days",
        urgency(@seconds)
      ]}
      role="timer"
      aria-label={"#{@spoken} #{GameCopy.clock_label_tail()}"}
      data-label-tail={GameCopy.clock_label_tail()}
      data-seconds={@seconds}
      phx-hook=".Flaps"
      phx-update="ignore"
    >
      <%= for {{digits, unit}, i} <- @groups do %>
        <span :if={i > 0} class="rg-flaps__sep" aria-hidden="true">:</span>
        <span :if={unit} class="rg-flaps__group">
          <span
            :for={{d, j} <- Enum.with_index(String.graphemes(digits))}
            class={if pulse?(unit, j, digits), do: "rg-flap rg-flap--pulse", else: "rg-flap"}
            aria-hidden="true"
          >{d}</span>
          <span class="rg-flaps__unit" aria-hidden="true">{unit}</span>
        </span>
        <span :for={d <- String.graphemes(digits)} :if={!unit} class="rg-flap" aria-hidden="true">{d}</span>
      <% end %>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Flaps">
      import {clockGroups, clockSpoken} from "@/js/clock"

      // The cells' shape, e.g. "dd:dd" or "[dddays]:[ddhours]:[ddmins]".
      const shapeOf = (groups) =>
        groups
          .map(([digits, unit]) => (unit ? `[${"d".repeat(digits.length)}${unit}]` : "d".repeat(digits.length)))
          .join(":")

      // The same shape, read back from the cells in the DOM. LiveView strips
      // data-* attributes it did not render, so the hook cannot keep it on
      // the element.
      const shapeIn = (el) =>
        [...el.children]
          .map((n) => {
            if (n.classList.contains("rg-flaps__sep")) return ":"
            if (n.classList.contains("rg-flaps__group")) {
              const tiles = n.querySelectorAll(".rg-flap").length
              return `[${"d".repeat(tiles)}${n.querySelector(".rg-flaps__unit").textContent}]`
            }
            return "d"
          })
          .join("")

      const tile = (cls = "rg-flap") => `<span class="${cls}" aria-hidden="true"></span>`
      const sep = '<span class="rg-flaps__sep" aria-hidden="true">:</span>'

      const cellsFor = (groups) =>
        groups
          .map(([digits, unit]) => {
            // Mirrors pulse?/3: the last minute tile pulses.
            const tiles =
              unit === "min" || unit === "mins"
                ? tile().repeat(digits.length - 1) + tile("rg-flap rg-flap--pulse")
                : tile().repeat(digits.length)
            return unit
              ? `<span class="rg-flaps__group">${tiles}<span class="rg-flaps__unit" aria-hidden="true">${unit}</span></span>`
              : tiles
          })
          .join(sep)

      export default {
        mounted() {
          this.seconds = parseInt(this.el.dataset.seconds, 10) || 0
          this.handleEvent("countdown-tick", ({ seconds }) => {
            this.seconds = seconds
            this.start()
            this.render()
          })
          this.start()
          this.render()
        },
        destroyed() {
          clearInterval(this.timer)
        },
        // Restart the local second so it lines up with the server's tick.
        start() {
          clearInterval(this.timer)
          this.timer = setInterval(() => {
            this.seconds = Math.max(0, this.seconds - 1)
            this.render()
          }, 1000)
        },
        render() {
          const groups = clockGroups(this.seconds)
          const days = groups[0][1] !== null
          const el = this.el

          // Rebuild the cells only when the shape changes: crossing an hour
          // or a day, or the day count gaining a digit.
          if (shapeIn(el) !== shapeOf(groups)) el.innerHTML = cellsFor(groups)
          el.classList.toggle("rg-flaps--long", !days && groups.length === 3)
          el.classList.toggle("rg-flaps--days", days)

          const digits = [...groups.map(([d]) => d).join("")]
          el.querySelectorAll(".rg-flap").forEach((node, i) => {
            const c = digits[i]
            if (node.textContent === c) return
            node.textContent = c
            node.classList.remove("is-tick")
            // Force a reflow so the browser restarts the flip animation.
            void node.offsetWidth
            node.classList.add("is-tick")
          })

          // Mirrors urgency/1.
          el.classList.toggle("is-crit", this.seconds <= 5)
          el.classList.toggle("is-warn", this.seconds > 5 && this.seconds <= 10)
          el.setAttribute("aria-label", `${clockSpoken(this.seconds)} ${el.dataset.labelTail}`)
        }
      }
    </script>
    """
  end

  # From one day up the last minute tile pulses, so the clock moves between
  # flips. `pulse?/3` picks the tile. The `.Flaps` hook mirrors this.
  @spec pulse?(String.t(), non_neg_integer(), String.t()) :: boolean()
  defp pulse?(unit, index, digits),
    do: unit in ~w(min mins) and index == String.length(digits) - 1

  # The clock's warning class. The `.Flaps` hook mirrors these thresholds.
  @spec urgency(integer()) :: String.t() | nil
  defp urgency(seconds) when seconds <= 5, do: "is-crit"
  defp urgency(seconds) when seconds <= 10, do: "is-warn"
  defp urgency(_seconds), do: nil

  @doc """
  A drop date and time in the display zone (Eastern), e.g. `Nov 3, 1:17pm EST`
  or `Today at 1:17pm EST`. See `RiddlrWeb.DropTime`.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :now, DateTime, doc: "what today is judged from; defaults to the clock"
  attr :format, :string, default: "short", values: ~w(short long)
  attr :local, :boolean, default: true, doc: "add the `drop_local/1` line after the time"

  attr :mid_sentence, :boolean,
    default: false,
    doc: "lowercase Today and Tomorrow, for a time that follows a lead such as \"Drops\""

  @spec drop_time(map()) :: Phoenix.LiveView.Rendered.t()
  def drop_time(assigns) do
    assigns =
      assigns
      |> assign_new(:now, fn -> Riddlr.Clock.utc_now() end)
      |> then(fn %{at: at, now: now} = assigns ->
        opts = [mid_sentence: assigns.mid_sentence]

        assign(assigns,
          iso: DateTime.to_iso8601(at),
          short: DropTime.short(at, now, opts),
          long: DropTime.long(at, now, opts)
        )
      end)

    ~H"""
    <%!-- No whitespace between the parts: it would show as a space before the comma. --%>
    <time :if={@format == "short"} id={@id} datetime={@iso}>{@short}</time>
    <time :if={@format == "long"} id={@id} datetime={@iso}>{@long.lead}<span class="rg-underlined">{@long.marked}</span></time><.drop_local
      :if={@local}
      id={"#{@id}-local"}
      at={@at}
    />
    """
  end

  @doc """
  The line under a drop time that gives it in the player's own zone, e.g.
  "Your time: Today at 10:17am PST".

  It starts hidden. The `.LocalDrop` hook shows it only when the browser's
  zone has a different UTC offset from the display zone at the drop instant,
  so Eastern players never see it. `drop_time/1` adds it by default; place it
  yourself, with `local={false}` there, when the time sits mid-sentence.
  """
  attr :id, :string, required: true
  attr :at, DateTime, required: true

  @spec drop_local(map()) :: Phoenix.LiveView.Rendered.t()
  def drop_local(assigns) do
    ~H"""
    <span
      id={@id}
      class="rg-drop-local"
      data-at={DateTime.to_iso8601(@at)}
      data-zone={DropTime.zone()}
      phx-hook=".LocalDrop"
      phx-update="ignore"
      hidden
    >
      {GameCopy.Home.drop_local_lead()} <span data-local-text></span>
    </span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalDrop">
      import {localDropText} from "@/js/drop_time"

      export default {
        mounted() {
          const browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone
          const text = localDropText(this.el.dataset.at, browserZone, this.el.dataset.zone)
          if (!text) return
          this.el.querySelector("[data-local-text]").textContent = text
          this.el.hidden = false
        }
      }
    </script>
    """
  end
end
