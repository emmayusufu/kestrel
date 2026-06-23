defmodule Kestrel.Strategies do
  @moduledoc """
  The registry of strategies Kestrel runs. Each entry is a spec with a stable
  `id` (used for bot names and persistence keys), a display `name`, the
  implementing `module`, and its default `params`.
  """

  alias Kestrel.Strategy.{SmaCrossover, Rsi, BuyDip, BuyHold}

  @doc "All strategies, in display order."
  def all do
    [
      %{id: "sma", name: "SMA 5/20", module: SmaCrossover, params: %{short: 5, long: 20}},
      %{id: "rsi", name: "RSI 14", module: Rsi, params: %{period: 14, low: 30, high: 70}},
      %{id: "dip", name: "Buy the dip", module: BuyDip, params: %{window: 20, drop: 0.03, rise: 0.03}},
      %{id: "hold", name: "Buy & hold", module: BuyHold, params: %{}}
    ]
  end

  @doc "Look up one strategy spec by id."
  def get(id), do: Enum.find(all(), &(&1.id == id))
end
