# Kestrel

Kestrel is a paper-trading bot and backtesting engine for crypto and stocks, built with Elixir and Phoenix LiveView. It runs a fleet of trading bots against live market data, paper-executes their trades with virtual money, and streams the results to a real-time dashboard. It needs no API keys, places no real orders, and risks no real money.

The stack is Elixir, Phoenix 1.7, and LiveView 1.0 on the BEAM. Market data comes from the public Coinbase and Yahoo Finance APIs. State persists to DETS, so there is no database to set up.

## What it does

- Runs one bot per market and strategy combination, each as its own supervised process. With the default config that is three crypto markets and four strategies, so twelve bots trade side by side.
- Polls live prices, runs each strategy on every tick, and paper-executes buys and sells against a virtual portfolio that charges a trading fee.
- Streams every bot's equity, position, and recent trades to a live leaderboard over PubSub, with no page reloads.
- Backtests any strategy over historical prices and ranks the result against buy-and-hold, on crypto or stocks.
- Survives restarts, because each bot writes its state to disk and reloads it on boot.

## How it works

The live engine is a small supervision tree under the application supervisor.

- `Kestrel.Engine.Ticker` is one process per market. It polls the spot price on an interval, every 10 seconds by default, and broadcasts it on that market's PubSub topic. If a fetch fails it logs and keeps ticking.
- `Kestrel.Engine.Bot` is one process per market and strategy pair. It subscribes to its market's price feed, asks its strategy what to do on each tick, and paper-trades the result through `Kestrel.Portfolio`. It persists its state after any trade and on a regular interval, then broadcasts a snapshot on the shared `bots` topic.
- `Kestrel.Store` is a thin wrapper over DETS that owns the on-disk table and flushes it periodically. Bots read and write straight through it.
- `KestrelWeb.DashboardLive` subscribes to the `bots` topic and updates in place as snapshots arrive.

Each bot is an isolated process, so one crashing does not touch the others. Its supervisor restarts it under a one_for_one strategy and it reloads its last saved state from disk.

### Market data

`Kestrel.Market` routes a symbol to the right source. Symbols with a dash like `BTC-USD` are treated as crypto and go to Coinbase. Plain tickers like `SPY` or `AAPL` go to Yahoo Finance. Both are public endpoints that need no key. Coinbase gives live spot prices and historical candles. Yahoo gives daily closes going back years, which is what lets you backtest an index fund over a long horizon.

### The backtester

`Kestrel.Backtest` is a pure function. It replays a strategy over a list of historical closing prices, oldest first, and reports the final equity, return, trade count, and how it did against simply buying and holding. The `compare/3` helper runs every strategy over the same prices and ranks them. Since it does no network calls, it is fast and easy to test. The dashboard runs it in a background task, so a slow data fetch never freezes the live view.

## Strategies

Each strategy is a module that implements one function, `decide/2`. It looks at recent prices and returns a desired position. The position is `:long` to be in the asset, `:flat` to be in cash, or `:hold` to keep whatever it already holds. Turning that decision into an actual trade is the engine's and the backtester's job, so the same strategy code runs both live and in backtests.

Kestrel ships with four strategies.

- `SmaCrossover` goes long when the short moving average sits above the long one and steps to cash when it drops below. The default is a 5 over 20 crossover.
- `Rsi` buys when the Relative Strength Index looks oversold and steps aside when it looks overbought.
- `BuyDip` buys after price falls a set percentage below its recent high and exits after it rises above its recent low.
- `BuyHold` buys once and holds. It is the baseline every other strategy has to beat.

These are teaching strategies, not money printers. After fees, most of them tend to lose to plain buy-and-hold over most periods. Seeing that for yourself in the backtester is the whole point.

## Getting started

You need Elixir 1.14 or newer and a recent Erlang/OTP (developed on OTP 28). You also need an internet connection, since the bots fetch live prices. There is no database and there are no API keys.

Install dependencies and build assets, then start the server.

```
mix setup
mix phx.server
```

Open [localhost:4000](http://localhost:4000) in your browser.

To run inside IEx so you can inspect the engine while it runs:

```
iex -S mix phx.server
```

`mix setup` fetches the Elixir dependencies and installs and builds the front-end assets with Tailwind and esbuild. In development, Phoenix LiveDashboard is also served at `/dev/dashboard`.

## Configuration

Engine settings live in `config/config.exs` under `Kestrel.Engine`.

```elixir
config :kestrel, Kestrel.Engine,
  products: ["BTC-USD", "ETH-USD", "SOL-USD"],
  poll_ms: 10_000,
  start_cash: 20.0,
  fee_rate: 0.006
```

- `products` is the list of markets to trade. Add or remove symbols to change which bots run.
- `poll_ms` is how often each ticker fetches a price, in milliseconds.
- `start_cash` is the virtual balance every bot starts with.
- `fee_rate` is the fraction charged on each trade, so `0.006` is 0.6%.

The live engine can be switched off with `config :kestrel, :start_engine, false`. It is off in the test environment so the suite never touches the network. Bot state persists to the DETS file configured under `Kestrel.Store`, which defaults to `priv/kestrel_store.dets`. Delete that file to reset every bot to a clean slate.

## Project layout

```
lib/kestrel/
  engine.ex            facade over the live engine
  engine/ticker.ex     one price poller per market
  engine/bot.ex        one paper-trading bot per market and strategy
  store.ex             DETS persistence
  portfolio.ex         pure virtual portfolio (cash, coin, fees)
  backtest.ex          pure historical replay and ranking
  market.ex            routes symbols to Coinbase or Yahoo
  market/coinbase.ex   crypto spot prices and candles
  market/yahoo.ex      stock and index daily closes
  strategy.ex          the Strategy behaviour and shared helpers
  strategy/*.ex        the individual strategies
lib/kestrel_web/
  live/dashboard_live.ex   the real-time dashboard
```

## Testing

```
mix test
```

The engine is disabled in the test environment, so the suite runs with no network access.

## A note on paper trading

Kestrel trades with virtual money only. It never places a real order and never connects to a brokerage or exchange account. It is a learning project for exploring trading strategies, market data, and Elixir's concurrency model. None of it is financial advice.
