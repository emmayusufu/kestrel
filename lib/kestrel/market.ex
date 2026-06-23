defmodule Kestrel.Market do
  @moduledoc """
  Front door for market data. It routes a symbol to the right source:
  crypto pairs (anything with a dash, like `BTC-USD`) go to Coinbase, plain
  tickers (like `SPY` or `AAPL`) go to Yahoo Finance. One function, either
  asset class.
  """

  alias Kestrel.Market.{Coinbase, Yahoo}

  @doc "True for crypto pair symbols like \"BTC-USD\"."
  def crypto?(symbol), do: String.contains?(symbol, "-")

  @doc """
  Closing prices oldest -> newest. `granularity` (seconds) drives crypto
  candles. Stocks are always daily and use a multi-year range instead.
  """
  def closes(symbol, granularity \\ 3600) do
    if crypto?(symbol) do
      Coinbase.closes(symbol, granularity)
    else
      Yahoo.closes(symbol, "5y", "1d")
    end
  end

  @doc "Latest price. Live spot for crypto, most recent daily close for stocks."
  def spot_price(symbol) do
    if crypto?(symbol), do: Coinbase.spot_price(symbol), else: Yahoo.last_price(symbol)
  end
end
