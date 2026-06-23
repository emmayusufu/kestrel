defmodule Kestrel.Strategy.SmaCrossover do
  @moduledoc """
  The classic moving-average crossover. When the short average sits above
  the long average, the recent trend is up, so be long. When it drops back
  below, step aside into cash.

  params: `%{short: pos_integer, long: pos_integer}`

  Honest note: this is a teaching strategy, not a money printer. Over most
  periods, after fees, it tends to lose to simply buying and holding. The
  point is to *see* that for yourself in the backtester.
  """
  @behaviour Kestrel.Strategy

  alias Kestrel.Strategy

  @impl true
  def decide(prices, params) do
    short = Map.get(params, :short, 5)
    long = Map.get(params, :long, 20)

    with s when not is_nil(s) <- Strategy.sma(prices, short),
         l when not is_nil(l) <- Strategy.sma(prices, long) do
      if s > l, do: :long, else: :flat
    else
      _ -> :flat
    end
  end
end
