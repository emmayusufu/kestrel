defmodule Kestrel.Strategy do
  @moduledoc """
  A strategy looks at recent prices and returns a *desired position*:
  `:long` (be in the asset), `:flat` (be in cash), or `:hold` (keep whatever
  position you already have). The engine and the backtester are what turn a
  change in desired position into an actual buy or sell. Keeping strategies as
  pure decision functions means they are trivial to test and to reuse live and
  in backtests.
  """

  @type position :: :long | :flat | :hold

  @callback decide(prices :: [float()], params :: map()) :: position()

  @doc "Simple moving average of the last `n` prices. Returns nil if there isn't enough data yet."
  def sma(prices, n) when is_list(prices) and n > 0 do
    if length(prices) < n do
      nil
    else
      window = Enum.take(prices, -n)
      Enum.sum(window) / n
    end
  end
end
