defmodule Kestrel.Store do
  @moduledoc """
  Tiny disk-backed key/value store on top of DETS (built into Erlang, no
  database needed). Bots write their portfolio and trade history here so the
  whole thing survives a restart. Reads and writes go straight to DETS; this
  GenServer just owns the table's lifecycle and periodically flushes it.
  """
  use GenServer
  require Logger

  @table :kestrel_store
  @sync_ms 30_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Fetch a value, or `default` if the key is absent or the table is closed."
  def get(key, default \\ nil) do
    case :dets.lookup(@table, key) do
      [{^key, value}] -> value
      _ -> default
    end
  rescue
    _ -> default
  end

  @doc "Store a value under `key`."
  def put(key, value) do
    :dets.insert(@table, {key, value})
  rescue
    _ -> :error
  end

  @impl true
  def init(:ok) do
    path = Application.get_env(:kestrel, __MODULE__, [])[:path] || "priv/kestrel_store.dets"
    File.mkdir_p!(Path.dirname(path))

    case :dets.open_file(@table, file: String.to_charlist(path), type: :set) do
      {:ok, @table} ->
        Process.send_after(self(), :sync, @sync_ms)
        {:ok, %{path: path}}

      {:error, reason} ->
        {:stop, {:dets_open_failed, reason}}
    end
  end

  @impl true
  def handle_info(:sync, state) do
    :dets.sync(@table)
    Process.send_after(self(), :sync, @sync_ms)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.sync(@table)
    :dets.close(@table)
    :ok
  end
end
