defmodule Kestrel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        KestrelWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:kestrel, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Kestrel.PubSub}
      ] ++ engine_children() ++ [KestrelWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kestrel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The live paper-trading engine: a Store for persistence, a Registry to name
  # processes, one Ticker per market, and one Bot per (market x strategy).
  # Disabled in test (see config/test.exs) so the suite never touches the
  # network. Bots subscribe to price topics, so PubSub must already be up.
  defp engine_children do
    if Application.get_env(:kestrel, :start_engine, true) do
      tickers =
        for product <- Kestrel.Engine.products() do
          Supervisor.child_spec(
            {Kestrel.Engine.Ticker, product: product, poll_ms: Kestrel.Engine.poll_ms()},
            id: {:ticker, product}
          )
        end

      bots =
        for spec <- Kestrel.Engine.bot_specs() do
          Supervisor.child_spec({Kestrel.Engine.Bot, spec}, id: {:bot, spec.id})
        end

      [
        Kestrel.Store,
        {Registry, keys: :unique, name: Kestrel.Engine.Registry}
      ] ++ tickers ++ bots
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KestrelWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
