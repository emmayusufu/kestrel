defmodule Kestrel.Strategy.Rsi do
  @moduledoc """
  Relative Strength Index, a mean-reversion strategy. When RSI drops below
  `low` the asset looks oversold, so buy. When it climbs above `high` it
  looks overbought, so step aside. In between, hold whatever you have.

  params: `%{period: pos_integer, low: number, high: number}`
  """
  @behaviour Kestrel.Strategy

  @impl true
  def decide(prices, params) do
    period = Map.get(params, :period, 14)
    low = Map.get(params, :low, 30)
    high = Map.get(params, :high, 70)

    case rsi(prices, period) do
      nil -> :hold
      r when r < low -> :long
      r when r > high -> :flat
      _ -> :hold
    end
  end

  @doc "Wilder-style RSI over the last `period` deltas. nil until there's enough data."
  def rsi(prices, period) when is_list(prices) and length(prices) > period do
    deltas =
      prices
      |> Enum.take(-(period + 1))
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    avg_gain = deltas |> Enum.map(&max(&1, 0.0)) |> Enum.sum() |> Kernel./(period)
    avg_loss = deltas |> Enum.map(&max(-&1, 0.0)) |> Enum.sum() |> Kernel./(period)

    cond do
      avg_loss == 0.0 and avg_gain == 0.0 -> 50.0
      avg_loss == 0.0 -> 100.0
      true -> 100.0 - 100.0 / (1.0 + avg_gain / avg_loss)
    end
  end

  def rsi(_prices, _period), do: nil
end
