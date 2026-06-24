defmodule Kestrel.Engine.Ticker do
  @moduledoc """
  One supervised price poller per product. It fetches the live spot price on
  an interval and broadcasts it on that product's PubSub topic. If a fetch
  fails it logs and keeps ticking. Many of these run at once, one per market.
  """
  use GenServer
  require Logger

  alias Kestrel.Market.Coinbase
  alias Kestrel.Engine

  @doc "PubSub topic carrying price ticks for a product."
  def topic(product), do: "market:" <> product

  def start_link(opts) do
    product = Keyword.fetch!(opts, :product)
    GenServer.start_link(__MODULE__, opts, name: Engine.ticker_via(product))
  end

  @impl true
  def init(opts) do
    state = %{
      product: Keyword.fetch!(opts, :product),
      poll_ms: Keyword.get(opts, :poll_ms, 10_000)
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case Coinbase.spot_price(state.product) do
      {:ok, price} ->
        Phoenix.PubSub.broadcast(
          Kestrel.PubSub,
          topic(state.product),
          {:price, state.product, price, System.system_time(:second)}
        )

      {:error, reason} ->
        Logger.warning("[kestrel] ticker #{state.product} failed: #{inspect(reason)}")
    end

    Process.send_after(self(), :poll, state.poll_ms)
    {:noreply, state}
  end
end
