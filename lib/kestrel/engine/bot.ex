defmodule Kestrel.Engine.Bot do
  @moduledoc """
  One paper-trading bot for a single (product, strategy) pair. It subscribes
  to its product's price feed, runs its strategy on every tick, paper-executes
  against a virtual portfolio, persists to the Store so it survives restarts,
  and broadcasts a snapshot on the shared "bots" topic for the dashboard.

  Dozens of these run side by side, each its own supervised process. If one
  crashes, its supervisor restarts it and it reloads its state from disk. The
  rest never notice. This is the BEAM doing what it was built for.
  """
  use GenServer

  alias Kestrel.Portfolio
  alias Kestrel.Engine
  alias Kestrel.Engine.Ticker
  alias Kestrel.Store

  @max_history 500
  @persist_every 30

  def start_link(spec), do: GenServer.start_link(__MODULE__, spec, name: Engine.bot_via(spec.id))

  @doc "Synchronously fetch a bot's current snapshot."
  def snapshot(id), do: GenServer.call(Engine.bot_via(id), :snapshot)

  @impl true
  def init(spec) do
    base = %{
      id: spec.id,
      product: spec.product,
      strategy_id: spec.strategy_id,
      strategy_name: spec.strategy_name,
      module: spec.module,
      params: spec.params,
      portfolio: Portfolio.new(Engine.start_cash(), Engine.fee_rate()),
      prices: [],
      target: :hold,
      price: nil,
      start_price: nil,
      start_cash: Engine.start_cash(),
      trades: [],
      started_at: System.system_time(:second),
      ticks: 0
    }

    state = restore(base)
    Phoenix.PubSub.subscribe(Kestrel.PubSub, Ticker.topic(spec.product))
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, public(state), state}

  @impl true
  def handle_info({:price, _product, price, ts}, state) do
    prices = Enum.take(state.prices ++ [price], -@max_history)
    start_price = state.start_price || price
    target = state.module.decide(prices, state.params)

    {portfolio, trades, traded?} =
      cond do
        target == :long and not Portfolio.holding?(state.portfolio) ->
          {Portfolio.buy(state.portfolio, price),
           [%{side: :buy, price: price, at: ts} | state.trades], true}

        target == :flat and Portfolio.holding?(state.portfolio) ->
          {Portfolio.sell(state.portfolio, price),
           [%{side: :sell, price: price, at: ts} | state.trades], true}

        true ->
          {state.portfolio, state.trades, false}
      end

    ticks = state.ticks + 1

    state = %{
      state
      | prices: prices,
        price: price,
        start_price: start_price,
        target: target,
        portfolio: portfolio,
        trades: trades,
        ticks: ticks
    }

    if traded? or rem(ticks, @persist_every) == 0, do: persist(state)
    Phoenix.PubSub.broadcast(Kestrel.PubSub, Engine.topic(), {:bot, state.id, public(state)})
    {:noreply, state}
  end

  # A UI-safe snapshot of the bot.
  defp public(state) do
    price = state.price
    equity = if price, do: Portfolio.equity(state.portfolio, price), else: state.start_cash

    bh =
      if price && state.start_price && state.start_price > 0 do
        state.start_cash * price / state.start_price
      else
        state.start_cash
      end

    %{
      id: state.id,
      product: state.product,
      strategy_id: state.strategy_id,
      strategy_name: state.strategy_name,
      price: price,
      position: if(Portfolio.holding?(state.portfolio), do: :long, else: :flat),
      cash: state.portfolio.cash,
      coin: state.portfolio.coin,
      equity: equity,
      return_pct: pct(state.start_cash, equity),
      start_cash: state.start_cash,
      fee_rate: state.portfolio.fee_rate,
      trade_count: state.portfolio.trades,
      buy_hold_equity: bh,
      buy_hold_return_pct: pct(state.start_cash, bh),
      beating_hold: equity > bh,
      params: state.params,
      prices: Enum.take(state.prices, -120),
      trades: Enum.take(state.trades, 8),
      started_at: state.started_at
    }
  end

  defp persist(state) do
    Store.put({:bot, state.id}, %{
      cash: state.portfolio.cash,
      coin: state.portfolio.coin,
      fee_rate: state.portfolio.fee_rate,
      ptrades: state.portfolio.trades,
      start_cash: state.portfolio.start_cash,
      trades: Enum.take(state.trades, 50),
      prices: Enum.take(state.prices, -100),
      target: state.target,
      start_price: state.start_price,
      started_at: state.started_at
    })
  end

  defp restore(base) do
    case Store.get({:bot, base.id}) do
      %{} = s ->
        portfolio = %Portfolio{
          cash: s.cash,
          coin: s.coin,
          fee_rate: s.fee_rate,
          trades: s.ptrades,
          start_cash: s.start_cash
        }

        %{
          base
          | portfolio: portfolio,
            trades: s.trades || [],
            prices: s.prices || [],
            target: s.target || :hold,
            start_price: s.start_price,
            started_at: s.started_at || base.started_at
        }

      _ ->
        base
    end
  rescue
    _ -> base
  end

  defp pct(start, _now) when start == 0.0, do: 0.0
  defp pct(start, now), do: (now - start) / start * 100.0
end
