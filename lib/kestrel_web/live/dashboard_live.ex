defmodule KestrelWeb.DashboardLive do
  @moduledoc """
  The live dashboard. It subscribes to every bot over PubSub and renders a
  real-time leaderboard of (market x strategy) bots, per-market price cards,
  and a backtest panel that can replay any one strategy or compare them all,
  on crypto or stocks.

  Dark theme for long screen sessions. Geist for text, Geist Mono for every
  number (terminal-style tabular data). The chartreuse accent is from ramp.com.
  """
  use KestrelWeb, :live_view

  alias Kestrel.{Backtest, Engine, Market, Strategies}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Kestrel.PubSub, Engine.topic())

    bots =
      Engine.snapshot_all()
      |> Map.new(fn snap -> {snap.id, snap} end)

    {:ok,
     assign(socket,
       page_title: "Kestrel",
       bots: bots,
       backtest: nil,
       bt_compare: nil,
       bt_error: nil,
       bt_loading: false,
       bt_params: %{"asset" => "BTC-USD", "strategy" => "compare", "granularity" => "3600"}
     )}
  end

  @impl true
  def handle_info({:bot, id, snap}, socket) do
    {:noreply, assign(socket, :bots, Map.put(socket.assigns.bots, id, snap))}
  end

  @impl true
  def handle_event("run_backtest", %{"asset" => asset, "strategy" => strat, "granularity" => g}, socket) do
    asset =
      case String.trim(to_string(asset)) do
        "" -> "BTC-USD"
        a -> String.upcase(a)
      end

    gran = parse_int(g, 3600)

    # Fetch + compute off the LiveView process so the live dashboard never
    # freezes while we wait on a slow or rate-limited data source.
    socket =
      socket
      |> assign(:bt_params, %{"asset" => asset, "strategy" => strat, "granularity" => to_string(gran)})
      |> assign(:bt_loading, true)
      |> assign(:bt_error, nil)
      |> start_async(:backtest, fn -> compute_backtest(asset, strat, gran) end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:backtest, {:ok, result}, socket) do
    socket = assign(socket, :bt_loading, false)

    socket =
      case result do
        {:compare, cmp} -> assign(socket, bt_compare: cmp, backtest: nil, bt_error: nil)
        {:single, r} -> assign(socket, backtest: r, bt_compare: nil, bt_error: nil)
        {:error, msg} -> assign(socket, bt_error: msg, backtest: nil, bt_compare: nil)
      end

    {:noreply, socket}
  end

  def handle_async(:backtest, {:exit, reason}, socket) do
    {:noreply, assign(socket, bt_loading: false, bt_error: "Backtest crashed: #{inspect(reason)}")}
  end

  defp compute_backtest(asset, strat, gran) do
    case Market.closes(asset, gran) do
      {:ok, closes} when length(closes) >= 30 ->
        if strat == "compare" do
          {:compare, Backtest.compare(closes, Strategies.all(), start_cash: 20.0)}
        else
          case Strategies.get(strat) do
            nil ->
              {:error, "Unknown strategy."}

            spec ->
              {:single,
               closes
               |> Backtest.run(spec.module, spec.params, start_cash: 20.0)
               |> Map.put(:name, spec.name)}
          end
        end

      {:ok, _too_few} ->
        {:error, "Not enough data for #{asset}. Try another asset or timeframe."}

      {:error, reason} ->
        {:error, "Couldn't fetch #{asset}: #{inspect(reason)}"}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:leaderboard, leaderboard(assigns.bots))
      |> assign(:markets, markets(assigns.bots))
      |> assign(:bot_count, map_size(assigns.bots))

    ~H"""
    <div
      class="min-h-screen"
      style="background-color:#09090b;background-image:radial-gradient(#1b1b1f 1px,transparent 1px);background-size:22px 22px;"
    >
      <div class="w-full border-b border-zinc-800/80 bg-zinc-900/40 px-4 py-2 text-center text-xs text-zinc-400 backdrop-blur">
        Kestrel is a paper-trading sandbox. Virtual money, live prices, zero real orders.
      </div>

      <div class="mx-auto max-w-6xl px-5 py-8 space-y-6">
        <header class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="text-xl">🦅</span>
            <span class="font-display text-xl font-semibold tracking-tight text-white">kestrel</span>
          </div>
          <div class="inline-flex items-center gap-2 rounded-full border border-zinc-800 bg-zinc-900 px-3 py-1">
            <span class="relative flex h-2 w-2">
              <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent opacity-75">
              </span>
              <span class="relative inline-flex h-2 w-2 rounded-full bg-accent"></span>
            </span>
            <span class="text-[11px] font-medium uppercase tracking-wider text-zinc-400">
              Live · <span class="font-mono">{@bot_count}</span> bots · <span class="font-mono">{length(@markets)}</span> markets
            </span>
          </div>
        </header>

        <section>
          <div class="mb-2 text-[11px] font-medium uppercase tracking-wider text-zinc-500">Markets</div>
          <%= if @markets == [] do %>
            <div class="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-8 text-center text-sm text-zinc-400">
              Warming up. Fetching the first live prices from Coinbase.
            </div>
          <% else %>
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div :for={m <- @markets} class="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-4">
                <div class="flex items-center justify-between">
                  <span class="text-sm font-medium text-zinc-300">{m.product}</span>
                  <span class="font-mono text-lg font-semibold tracking-tight text-white">
                    {price_fmt(m.price)}
                  </span>
                </div>
                <svg viewBox="0 0 600 60" class="mt-3 h-12 w-full text-accent" preserveAspectRatio="none">
                  <polyline
                    :if={length(m.prices) > 1}
                    points={spark_points(m.prices, 600, 60)}
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linejoin="round"
                  />
                </svg>
              </div>
            </div>
          <% end %>
        </section>

        <section class="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-5">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="font-display text-base font-semibold tracking-tight text-white">
              Live leaderboard
            </h2>
            <span class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
              each bot trades a virtual <span class="font-mono">{money(@bots |> Map.values() |> List.first(%{}) |> Map.get(:start_cash, 20.0))}</span>
            </span>
          </div>

          <%= if @leaderboard == [] do %>
            <div class="py-8 text-center text-sm text-zinc-400">No bots reporting yet.</div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-zinc-800 text-left text-[11px] uppercase tracking-wider text-zinc-500">
                    <th class="py-2 pr-3 font-medium">#</th>
                    <th class="py-2 pr-3 font-medium">Strategy</th>
                    <th class="py-2 pr-3 font-medium">Market</th>
                    <th class="py-2 pr-3 font-medium">Position</th>
                    <th class="py-2 pr-3 text-right font-medium">Equity</th>
                    <th class="py-2 pr-3 text-right font-medium">Return</th>
                    <th class="py-2 pr-3 text-right font-medium">vs Hold</th>
                    <th class="py-2 text-right font-medium">Trades</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-800/70">
                  <tr
                    :for={{b, i} <- Enum.with_index(@leaderboard)}
                    class={["transition", i == 0 && "bg-accent/5"]}
                  >
                    <td class="py-2.5 pr-3 font-mono text-zinc-500">{i + 1}</td>
                    <td class="py-2.5 pr-3 font-display font-medium text-zinc-100">{b.strategy_name}</td>
                    <td class="py-2.5 pr-3 text-zinc-400">{b.product}</td>
                    <td class="py-2.5 pr-3">
                      <span class={[
                        "rounded-md px-2 py-0.5 text-xs font-medium",
                        if(b.position == :long,
                          do: "bg-emerald-500/10 text-emerald-400",
                          else: "bg-zinc-700/40 text-zinc-400"
                        )
                      ]}>
                        {if b.position == :long, do: "In " <> coin_label(b.product), else: "Cash"}
                      </span>
                    </td>
                    <td class="py-2.5 pr-3 text-right font-mono font-medium tabular-nums text-white">
                      {money(b.equity)}
                    </td>
                    <td class={["py-2.5 pr-3 text-right font-mono font-medium tabular-nums", gain_class(b.return_pct)]}>
                      {pct_fmt(b.return_pct)}
                    </td>
                    <td class={["py-2.5 pr-3 text-right font-mono tabular-nums", gain_class(b.return_pct - b.buy_hold_return_pct)]}>
                      {pct_fmt(b.return_pct - b.buy_hold_return_pct)}
                    </td>
                    <td class="py-2.5 text-right font-mono tabular-nums text-zinc-400">{b.trade_count}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="mt-3 text-xs text-zinc-500">
              "vs Hold" is each bot against simply buying and holding that same market. Mostly negative,
              and that is the lesson.
            </p>
          <% end %>
        </section>

        <section class="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-6">
          <h2 class="font-display text-base font-semibold tracking-tight text-white">
            Backtest · the time machine
          </h2>
          <p class="mt-1 text-xs text-zinc-400">
            Replay strategies over real history. Crypto like BTC-USD or ETH-USD, or a stock or index
            fund like SPY, VOO, AAPL. Compare them all against buy-and-hold.
          </p>

          <form phx-submit="run_backtest" class="mt-4 grid grid-cols-2 items-end gap-3 md:grid-cols-4">
            <label class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
              Asset
              <input
                type="text"
                name="asset"
                value={@bt_params["asset"]}
                class="mt-1 w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 font-mono text-sm font-medium normal-case tracking-normal text-zinc-100 focus:border-accent focus:outline-none"
              />
            </label>
            <label class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
              Strategy
              <select
                name="strategy"
                class="mt-1 w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm font-medium normal-case tracking-normal text-zinc-100 focus:border-accent focus:outline-none"
              >
                <option value="compare" selected={@bt_params["strategy"] == "compare"}>
                  Compare all
                </option>
                <option
                  :for={s <- Strategies.all()}
                  value={s.id}
                  selected={@bt_params["strategy"] == s.id}
                >
                  {s.name}
                </option>
              </select>
            </label>
            <label class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
              Timeframe
              <select
                name="granularity"
                class="mt-1 w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm font-medium normal-case tracking-normal text-zinc-100 focus:border-accent focus:outline-none"
              >
                <option value="3600" selected={@bt_params["granularity"] == "3600"}>1 hour (crypto)</option>
                <option value="21600" selected={@bt_params["granularity"] == "21600"}>6 hours (crypto)</option>
                <option value="86400" selected={@bt_params["granularity"] == "86400"}>1 day</option>
              </select>
            </label>
            <button
              type="submit"
              class="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-zinc-950 transition hover:brightness-95"
            >
              Run backtest
            </button>
          </form>

          <div :if={@bt_loading} class="mt-4 flex items-center gap-2 text-sm text-zinc-400">
            <span class="h-3 w-3 animate-spin rounded-full border-2 border-zinc-600 border-t-accent"></span>
            Running backtest, fetching data...
          </div>
          <div :if={@bt_error} class="mt-4 text-sm text-rose-400">{@bt_error}</div>

          <div :if={@bt_compare} class="mt-5">
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-zinc-800 text-left text-[11px] uppercase tracking-wider text-zinc-500">
                    <th class="py-2 pr-3 font-medium">Rank</th>
                    <th class="py-2 pr-3 font-medium">Strategy</th>
                    <th class="py-2 pr-3 text-right font-medium">Final</th>
                    <th class="py-2 pr-3 text-right font-medium">Return</th>
                    <th class="py-2 text-right font-medium">Trades</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-800/70">
                  <tr
                    :for={{r, i} <- Enum.with_index(@bt_compare.ranked)}
                    class={[i == 0 && "bg-accent/5"]}
                  >
                    <td class="py-2.5 pr-3 font-mono text-zinc-500">{i + 1}</td>
                    <td class="py-2.5 pr-3 font-display font-medium text-zinc-100">{r.name}</td>
                    <td class="py-2.5 pr-3 text-right font-mono tabular-nums text-white">
                      {money(r.final_equity)}
                    </td>
                    <td class={["py-2.5 pr-3 text-right font-mono font-medium tabular-nums", gain_class(r.return_pct)]}>
                      {pct_fmt(r.return_pct)}
                    </td>
                    <td class="py-2.5 text-right font-mono tabular-nums text-zinc-400">{r.trades}</td>
                  </tr>
                  <tr class="border-t-2 border-zinc-700">
                    <td class="py-2.5 pr-3 font-mono text-zinc-500">—</td>
                    <td class="py-2.5 pr-3 font-display font-medium text-accent">Buy &amp; hold (baseline)</td>
                    <td class="py-2.5 pr-3 text-right font-mono tabular-nums text-white">
                      {money(@bt_compare.buy_hold_equity)}
                    </td>
                    <td class={["py-2.5 pr-3 text-right font-mono font-medium tabular-nums", gain_class(@bt_compare.buy_hold_return_pct)]}>
                      {pct_fmt(@bt_compare.buy_hold_return_pct)}
                    </td>
                    <td class="py-2.5 text-right font-mono tabular-nums text-zinc-400">1</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="mt-3 text-xs text-zinc-500">
              <span class="font-mono">{price_fmt(@bt_compare.first_price)}</span>
              to <span class="font-mono">{price_fmt(@bt_compare.last_price)}</span>
              over <span class="font-mono">{@bt_compare.points}</span> bars.
              Beating buy-and-hold after fees is rare. Run a few assets and timeframes and watch how
              often the baseline wins.
            </p>
          </div>

          <div :if={@backtest} class="mt-5">
            <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
              <div class="rounded-xl bg-zinc-950/60 p-3">
                <div class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
                  {@backtest.name}
                </div>
                <div class="mt-1 font-mono font-semibold tracking-tight text-white">
                  {money(@backtest.final_equity)}
                </div>
                <div class={["font-mono text-xs", gain_class(@backtest.return_pct)]}>
                  {pct_fmt(@backtest.return_pct)}
                </div>
              </div>
              <div class="rounded-xl bg-zinc-950/60 p-3">
                <div class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
                  Buy &amp; hold
                </div>
                <div class="mt-1 font-mono font-semibold tracking-tight text-white">
                  {money(@backtest.buy_hold_equity)}
                </div>
                <div class={["font-mono text-xs", gain_class(@backtest.buy_hold_return_pct)]}>
                  {pct_fmt(@backtest.buy_hold_return_pct)}
                </div>
              </div>
              <div class="rounded-xl bg-zinc-950/60 p-3">
                <div class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">Trades</div>
                <div class="mt-1 font-mono font-semibold tracking-tight text-white">
                  {@backtest.trades}
                </div>
                <div class="font-mono text-xs text-zinc-500">{@backtest.points} bars</div>
              </div>
              <div class="rounded-xl bg-zinc-950/60 p-3">
                <div class="text-[11px] font-medium uppercase tracking-wider text-zinc-500">Verdict</div>
                <div class={["mt-1 font-display font-semibold tracking-tight", if(@backtest.beat_buy_hold, do: "text-emerald-400", else: "text-rose-400")]}>
                  {if @backtest.beat_buy_hold, do: "Strategy won", else: "Holding won"}
                </div>
              </div>
            </div>
          </div>
        </section>

        <div class="flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-zinc-800 pt-5 text-[11px] font-medium uppercase tracking-wider text-zinc-500">
          <span>Starting cash <span class="ml-1 rounded bg-zinc-800 px-1.5 py-0.5 font-mono normal-case tracking-normal text-zinc-300">{money(Engine.start_cash())}</span></span>
          <span>Fee <span class="ml-1 rounded bg-zinc-800 px-1.5 py-0.5 font-mono normal-case tracking-normal text-zinc-300">{Float.round(Engine.fee_rate() * 100, 2)}%</span></span>
          <span>Strategies <span class="ml-1 rounded bg-zinc-800 px-1.5 py-0.5 font-mono normal-case tracking-normal text-zinc-300">{length(Strategies.all())}</span></span>
          <span>Markets <span class="ml-1 rounded bg-zinc-800 px-1.5 py-0.5 font-mono normal-case tracking-normal text-zinc-300">{length(Engine.products())}</span></span>
          <span>Bots <span class="ml-1 rounded bg-zinc-800 px-1.5 py-0.5 font-mono normal-case tracking-normal text-zinc-300">{@bot_count}</span></span>
        </div>

        <footer class="pb-8 text-center text-[11px] uppercase tracking-wider text-zinc-600">
          Kestrel · paper trading only · state persists across restarts · crypto via Coinbase, stocks via Yahoo Finance
        </footer>
      </div>
    </div>
    """
  end

  defp leaderboard(bots) do
    bots |> Map.values() |> Enum.sort_by(& &1.return_pct, :desc)
  end

  defp markets(bots) do
    bots
    |> Map.values()
    |> Enum.group_by(& &1.product)
    |> Enum.map(fn {product, snaps} ->
      rep = Enum.find(snaps, &(&1.strategy_id == "hold")) || hd(snaps)
      %{product: product, price: rep.price, prices: rep.prices}
    end)
    |> Enum.sort_by(& &1.product)
  end

  defp money(nil), do: "—"
  defp money(n) when is_number(n), do: "$" <> :erlang.float_to_binary(n / 1, decimals: 2)

  defp price_fmt(nil), do: "—"
  defp price_fmt(n) when is_number(n), do: "$" <> :erlang.float_to_binary(n / 1, decimals: 2)

  defp pct_fmt(nil), do: "—"

  defp pct_fmt(n) when is_number(n) do
    sign = if n >= 0, do: "+", else: ""
    sign <> :erlang.float_to_binary(n / 1, decimals: 2) <> "%"
  end

  defp gain_class(n) when is_number(n) and n >= 0, do: "text-emerald-400"
  defp gain_class(_), do: "text-rose-400"

  defp coin_label(product), do: product |> String.split("-") |> List.first()

  defp spark_points(prices, w, h) when is_list(prices) and length(prices) > 1 do
    {min, max} = Enum.min_max(prices)
    range = if max - min == 0, do: 1.0, else: max - min
    n = length(prices)

    prices
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {p, i} ->
      x = i / (n - 1) * w
      y = h - (p - min) / range * h
      "#{Float.round(x, 1)},#{Float.round(y, 1)}"
    end)
  end

  defp spark_points(_prices, _w, _h), do: ""

  defp parse_int(s, default) do
    case Integer.parse(to_string(s || "")) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end
end
