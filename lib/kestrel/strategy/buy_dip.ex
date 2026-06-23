defmodule Kestrel.Strategy.BuyDip do
  @moduledoc """
  Buy the dip. If price falls `drop` below the recent high, buy. If it then
  rises `rise` above the recent low, take the gain and step out. Otherwise
  hold. A simple contrarian counterpoint to the trend-following SMA.

  params: `%{window: pos_integer, drop: float, rise: float}` (drop/rise as
  fractions, e.g. 0.03 = 3%).
  """
  @behaviour Kestrel.Strategy

  @impl true
  def decide(prices, params) when is_list(prices) do
    window = Map.get(params, :window, 20)
    drop = Map.get(params, :drop, 0.03)
    rise = Map.get(params, :rise, 0.03)

    if length(prices) < 2 do
      :hold
    else
      recent = Enum.take(prices, -window)
      high = Enum.max(recent)
      low = Enum.min(recent)
      price = List.last(prices)

      cond do
        price <= high * (1.0 - drop) -> :long
        price >= low * (1.0 + rise) -> :flat
        true -> :hold
      end
    end
  end
end
