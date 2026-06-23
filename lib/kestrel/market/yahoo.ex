defmodule Kestrel.Market.Yahoo do
  @moduledoc """
  Free stock, ETF, and index data from Yahoo Finance's public chart API. No
  API key. This is what lets you backtest an index fund like SPY or VOO over
  years and watch buy-and-hold quietly win.

  Yahoo rate-limits, so this retries transient failures with backoff and falls
  back from the `query1` host to `query2`.
  """

  @hosts [
    "https://query1.finance.yahoo.com/v8/finance/chart/",
    "https://query2.finance.yahoo.com/v8/finance/chart/"
  ]
  @ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"

  @doc "Daily closing prices, oldest -> newest, over `range` (e.g. \"5y\")."
  def closes(symbol, range \\ "5y", interval \\ "1d") do
    fetch(@hosts, symbol, range, interval)
  end

  @doc "Most recent daily close, used as a stand-in 'spot' for stocks."
  def last_price(symbol) do
    case closes(symbol, "5d", "1d") do
      {:ok, [_ | _] = closes} -> {:ok, List.last(closes)}
      {:ok, _} -> {:error, :no_data}
      err -> err
    end
  end

  defp fetch([], _symbol, _range, _interval), do: {:error, :rate_limited}

  defp fetch([host | rest], symbol, range, interval) do
    url = host <> URI.encode(String.upcase(to_string(symbol)))

    case Req.get(url,
           params: [range: range, interval: interval],
           headers: [{"user-agent", @ua}, {"accept", "application/json"}],
           receive_timeout: 12_000,
           retry: :transient,
           max_retries: 3
         ) do
      {:ok, %{status: 200, body: %{"chart" => %{"result" => [result | _]}}}} ->
        parse(result)

      {:ok, %{status: 200, body: %{"chart" => %{"error" => error}}}} when not is_nil(error) ->
        {:error, {:yahoo, error}}

      # rate limited or transport hiccup: try the next host
      {:ok, %{status: 429}} ->
        fetch(rest, symbol, range, interval)

      {:error, _reason} ->
        fetch(rest, symbol, range, interval)

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}
    end
  end

  defp parse(result) do
    closes =
      result
      |> get_in(["indicators", "quote"])
      |> case do
        [quote | _] -> Map.get(quote, "close", [])
        _ -> []
      end
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(&1 * 1.0))

    if closes == [], do: {:error, :no_data}, else: {:ok, closes}
  end
end
