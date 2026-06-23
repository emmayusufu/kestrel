defmodule Kestrel.Strategy.BuyHold do
  @moduledoc """
  Buy once, then hold forever. The honest baseline every other strategy has
  to beat. On the leaderboard its return should sit a hair under a pure hold
  (it pays one entry fee), which is a nice sanity check that the math is right.
  """
  @behaviour Kestrel.Strategy

  @impl true
  def decide(_prices, _params), do: :long
end
