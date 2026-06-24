defmodule Kestrel.Engine do
  @moduledoc """
  Facade over the live trading engine. It knows which products and strategies
  are configured, derives the full set of bots (one per product x strategy),
  resolves process names through the Registry, and can snapshot every bot for
  the dashboard.
  """

  alias Kestrel.Engine.Bot

  @registry Kestrel.Engine.Registry

  def cfg, do: Application.get_env(:kestrel, __MODULE__, [])
  def products, do: cfg()[:products] || ["BTC-USD"]
  def poll_ms, do: cfg()[:poll_ms] || 10_000
  def start_cash, do: cfg()[:start_cash] || 20.0
  def fee_rate, do: cfg()[:fee_rate] || 0.006

  def strategies, do: Kestrel.Strategies.all()

  @doc "Stable id for a bot, e.g. \"btc-usd:sma\"."
  def bot_id(product, strategy_id), do: String.downcase(product) <> ":" <> strategy_id

  @doc "Every bot we run: the cross product of markets and strategies."
  def bot_specs do
    for product <- products(), s <- strategies() do
      %{
        id: bot_id(product, s.id),
        product: product,
        strategy_id: s.id,
        strategy_name: s.name,
        module: s.module,
        params: s.params
      }
    end
  end

  @doc "PubSub topic each bot broadcasts its snapshot on."
  def topic, do: "bots"

  def registry, do: @registry
  def ticker_via(product), do: {:via, Registry, {@registry, {:ticker, product}}}
  def bot_via(id), do: {:via, Registry, {@registry, {:bot, id}}}

  @doc "Current snapshot of every bot, skipping any that aren't answering."
  def snapshot_all do
    bot_specs()
    |> Enum.map(fn spec ->
      try do
        Bot.snapshot(spec.id)
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
