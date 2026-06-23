defmodule Kestrel.Market.Coinbase do
  @moduledoc """
  Public Coinbase market data. No API key, no auth, read-only.

  Spot price comes from the Coinbase retail API. Historical candles come
  from the Coinbase Exchange public API, which is what the backtester eats.
  Both endpoints are free and need nothing but an internet connection.
  """

  @spot_url "https://api.coinbase.com/v2/prices"
  @exchange_url "https://api.exchange.coinbase.com/products"
  @ua "kestrel-paper-bot/0.1 (learning project)"
  @timeout 8_000

  @doc """
  Latest spot price for a product like `"BTC-USD"`.
  Returns `{:ok, float}` or `{:error, reason}`.
  """
  def spot_price(product \\ "BTC-USD") do
    case Req.get("#{@spot_url}/#{product}/spot", req_opts()) do
      {:ok, %{status: 200, body: %{"data" => %{"amount" => amount}}}} ->
        {:ok, to_float(amount)}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Historical candles for backtesting, ordered oldest -> newest.

  `granularity` is in seconds and must be one of 60, 300, 900, 3600, 21600,
  86400. Coinbase returns at most ~300 candles per call. Each candle is
  `%{time, open, high, low, close, volume}`.
  """
  def candles(product \\ "BTC-USD", granularity \\ 3600) do
    case Req.get("#{@exchange_url}/#{product}/candles",
           Keyword.put(req_opts(), :params, granularity: granularity)
         ) do
      {:ok, %{status: 200, body: rows}} when is_list(rows) ->
        candles =
          rows
          |> Enum.map(fn [time, low, high, open, close, volume] ->
            %{
              time: time,
              low: to_float(low),
              high: to_float(high),
              open: to_float(open),
              close: to_float(close),
              volume: to_float(volume)
            }
          end)
          |> Enum.sort_by(& &1.time)

        {:ok, candles}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Just the closing prices, oldest -> newest. What most strategies want."
  def closes(product \\ "BTC-USD", granularity \\ 3600) do
    with {:ok, candles} <- candles(product, granularity) do
      {:ok, Enum.map(candles, & &1.close)}
    end
  end

  defp req_opts, do: [headers: [{"user-agent", @ua}], receive_timeout: @timeout, retry: false]

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
