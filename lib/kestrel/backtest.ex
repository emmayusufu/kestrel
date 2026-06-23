defmodule Kestrel.Backtest do
  @moduledoc """
  Replay a strategy over a list of historical closing prices and report how
  it would have done, measured honestly against simply buying and holding.

  Pure function: same inputs, same answer, no network. This is the time
  machine. It compresses months of "what if" into a few milliseconds.
  """

  alias Kestrel.Portfolio

  @doc """
  Run `strategy` (a module implementing `Kestrel.Strategy`) over `closes`,
  oldest -> newest. Options: `:start_cash` (default 20.0), `:fee_rate`
  (default 0.006). Returns a result map.
  """
  def run(closes, strategy, params, opts \\ []) when is_list(closes) do
    start_cash = Keyword.get(opts, :start_cash, 20.0)
    fee_rate = Keyword.get(opts, :fee_rate, 0.006)

    init = {Portfolio.new(start_cash, fee_rate), [], [], []}

    {final_p, _window, trade_log, equity_curve} =
      closes
      |> Enum.with_index()
      |> Enum.reduce(init, fn {price, i}, {p, window, log, curve} ->
        window = window ++ [price]
        target = strategy.decide(window, params)

        {p, log} =
          cond do
            target == :long and not Portfolio.holding?(p) ->
              {Portfolio.buy(p, price), [%{index: i, side: :buy, price: price} | log]}

            target == :flat and Portfolio.holding?(p) ->
              {Portfolio.sell(p, price), [%{index: i, side: :sell, price: price} | log]}

            true ->
              {p, log}
          end

        {p, window, log, [Portfolio.equity(p, price) | curve]}
      end)

    first = List.first(closes) || 0.0
    last = List.last(closes) || 0.0

    final_equity = Portfolio.equity(final_p, last)
    bh_equity = if first > 0, do: start_cash * last / first, else: start_cash

    %{
      start_cash: start_cash,
      fee_rate: fee_rate,
      points: length(closes),
      first_price: first,
      last_price: last,
      final_equity: final_equity,
      return_pct: pct(start_cash, final_equity),
      trades: final_p.trades,
      buy_hold_equity: bh_equity,
      buy_hold_return_pct: pct(start_cash, bh_equity),
      beat_buy_hold: final_equity > bh_equity,
      trade_log: Enum.reverse(trade_log),
      equity_curve: Enum.reverse(equity_curve)
    }
  end

  @doc """
  Run every strategy in `strategies` (a list of specs from
  `Kestrel.Strategies`) over the same `closes` and rank them against
  buy-and-hold. Returns a map with a ranked list and the hold baseline.
  """
  def compare(closes, strategies, opts \\ []) when is_list(closes) do
    runs =
      Enum.map(strategies, fn s ->
        r = run(closes, s.module, s.params, opts)

        %{
          id: s.id,
          name: s.name,
          return_pct: r.return_pct,
          final_equity: r.final_equity,
          trades: r.trades,
          beat_buy_hold: r.beat_buy_hold
        }
      end)

    baseline = run(closes, Kestrel.Strategy.BuyHold, %{}, opts)

    %{
      ranked: Enum.sort_by(runs, & &1.return_pct, :desc),
      buy_hold_return_pct: baseline.buy_hold_return_pct,
      buy_hold_equity: baseline.buy_hold_equity,
      start_cash: baseline.start_cash,
      points: baseline.points,
      first_price: baseline.first_price,
      last_price: baseline.last_price
    }
  end

  defp pct(start, _now) when start == 0.0, do: 0.0
  defp pct(start, now), do: (now - start) / start * 100.0
end
