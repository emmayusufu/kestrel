defmodule Kestrel.Portfolio do
  @moduledoc """
  A virtual (paper) portfolio. Pure data, zero side effects, so the exact
  same logic runs in the live trader and in the backtester.

  It holds `cash` (USD) and `coin` (units of the asset). Every trade pays a
  `fee_rate`, because pretending fees don't exist is exactly how a paper
  trader fools themselves into thinking a losing strategy wins.
  """

  @enforce_keys [:cash, :coin, :fee_rate, :start_cash]
  defstruct cash: 0.0, coin: 0.0, fee_rate: 0.006, trades: 0, start_cash: 0.0

  @type t :: %__MODULE__{
          cash: float(),
          coin: float(),
          fee_rate: float(),
          trades: non_neg_integer(),
          start_cash: float()
        }

  @doc "A fresh all-cash portfolio."
  def new(start_cash, fee_rate \\ 0.006) do
    cash = start_cash * 1.0
    %__MODULE__{cash: cash, coin: 0.0, fee_rate: fee_rate, trades: 0, start_cash: cash}
  end

  @doc "Go all-in: turn all cash into coin at `price`, minus fee. No-op if no cash."
  def buy(%__MODULE__{cash: cash} = p, _price) when cash <= 0.0, do: p

  def buy(%__MODULE__{} = p, price) when price > 0 do
    bought = p.cash * (1.0 - p.fee_rate) / price
    %{p | cash: 0.0, coin: p.coin + bought, trades: p.trades + 1}
  end

  @doc "Exit: turn all coin into cash at `price`, minus fee. No-op if holding nothing."
  def sell(%__MODULE__{coin: coin} = p, _price) when coin <= 0.0, do: p

  def sell(%__MODULE__{} = p, price) when price > 0 do
    proceeds = p.coin * price * (1.0 - p.fee_rate)
    %{p | cash: p.cash + proceeds, coin: 0.0, trades: p.trades + 1}
  end

  @doc "Total value if liquidated at `price` (the exit fee is left out here)."
  def equity(%__MODULE__{} = p, price), do: p.cash + p.coin * price

  @doc "Return against starting cash, as a percentage."
  def return_pct(%__MODULE__{start_cash: start} = p, price) when start != 0.0 do
    (equity(p, price) - start) / start * 100.0
  end

  def return_pct(%__MODULE__{}, _price), do: 0.0

  @doc "Are we currently holding the asset?"
  def holding?(%__MODULE__{coin: coin}), do: coin > 0.0
end
