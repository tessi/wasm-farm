defmodule WasmFarmerWeb.FarmLive do
  use WasmFarmerWeb, :live_view

  @impl true
  def mount(%{"id" => farm_id, "new_manual_bot" => create_new_manual_bot}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WasmFarmer.PubSub, "farm:#{farm_id}")

      # Get updated farm state
      farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, farm_id})

      if farm do
        if create_new_manual_bot do
          bot_id = Ecto.UUID.generate()
          GenServer.cast(WasmFarmer.Game.GameServer, {:add_bot, farm_id, bot_id, 0, 0, self()})
          farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, farm_id})

          {:ok,
           assign(socket, farm: farm, farm_id: farm_id, bot_id: bot_id, min_log_level: :debug)}
        else
          {:ok, assign(socket, farm: farm, farm_id: farm_id, min_log_level: :debug)}
        end
      else
        {:ok, redirect(socket, to: ~p"/farms")}
      end
    else
      {:ok, assign(socket, farm: nil, farm_id: farm_id, min_log_level: :debug)}
    end
  end

  @impl true
  def mount(%{"id" => farm_id}, session, socket) do
    mount(%{"id" => farm_id, "new_manual_bot" => false}, session, socket)
  end

  @impl true
  def terminate(_reason, socket) do
    if connected?(socket) and socket.assigns[:bot_id] do
      GenServer.cast(
        WasmFarmer.Game.GameServer,
        {:remove_bot, socket.assigns.farm_id, socket.assigns.bot_id, self()}
      )
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
    {:noreply, assign(socket, farm: farm)}
  end

  @impl true
  def handle_info(:deleted, socket) do
    {:noreply, redirect(socket, to: ~p"/farms")}
  end

  @impl true
  def handle_event("bot_action", %{"bot_id" => bot_id, "action" => action}, socket) do
    if bot_id == socket.assigns.bot_id do
      action = String.to_existing_atom(action)

      GenServer.cast(
        WasmFarmer.Game.GameServer,
        {:bot_action, socket.assigns.farm_id, bot_id, action}
      )

      farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
      {:noreply, assign(socket, farm: farm)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sell", %{"resource" => resource, "amount" => amount}, socket) do
    resource = String.to_existing_atom(resource)
    amount = String.to_integer(amount)
    GenServer.cast(WasmFarmer.Game.GameServer, {:sell, socket.assigns.farm_id, resource, amount})
    farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
    {:noreply, assign(socket, farm: farm)}
  end

  @impl true
  def handle_event(
        "buy",
        %{"bot_id" => bot_id, "resource" => resource, "amount" => amount},
        socket
      ) do
    if bot_id == socket.assigns.bot_id do
      resource = String.to_existing_atom(resource)
      amount = String.to_integer(amount)

      GenServer.cast(
        WasmFarmer.Game.GameServer,
        {:buy, socket.assigns.farm_id, bot_id, resource, amount}
      )

      farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
      {:noreply, assign(socket, farm: farm)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_display_name", %{"bot_id" => bot_id, "value" => display_name}, socket) do
    if bot_id == socket.assigns.bot_id do
      GenServer.cast(
        WasmFarmer.Game.GameServer,
        {:update_bot_display_name, socket.assigns.farm_id, bot_id, display_name, self()}
      )

      farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
      {:noreply, assign(socket, farm: farm)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    action =
      case key do
        "ArrowLeft" -> "move_left"
        "ArrowRight" -> "move_right"
        "ArrowUp" -> "move_up"
        "ArrowDown" -> "move_down"
        "a" -> "move_left"
        "d" -> "move_right"
        "w" -> "move_up"
        "s" -> "move_down"
        "e" -> "seed"
        "r" -> "harvest"
        "t" -> "water"
        "y" -> "plow"
        "f" -> {:buy, "energy", 10}
        "F" -> {:buy, "energy", 100}
        "g" -> {:buy, "seeds", 5}
        "G" -> {:buy, "seeds", 50}
        "h" -> {:buy, "water", 10}
        "H" -> {:buy, "water", 100}
        "c" -> {:sell, "wheat", 1}
        "C" -> {:sell, "wheat", 10}
        "v" -> {:sell, "grass", 1}
        "V" -> {:sell, "grass", 10}
        _ -> nil
      end

    case action do
      {:buy, resource, amount} ->
        GenServer.cast(
          WasmFarmer.Game.GameServer,
          {:buy, socket.assigns.farm_id, socket.assigns.bot_id, String.to_existing_atom(resource),
           amount}
        )

        farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
        {:noreply, assign(socket, farm: farm)}

      {:sell, resource, amount} ->
        GenServer.cast(
          WasmFarmer.Game.GameServer,
          {:sell, socket.assigns.farm_id, String.to_existing_atom(resource), amount}
        )

        farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
        {:noreply, assign(socket, farm: farm)}

      action when is_binary(action) ->
        GenServer.cast(
          WasmFarmer.Game.GameServer,
          {:bot_action, socket.assigns.farm_id, socket.assigns.bot_id,
           String.to_existing_atom(action)}
        )

        farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, socket.assigns.farm_id})
        {:noreply, assign(socket, farm: farm)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_log_level", %{"level" => level}, socket) do
    level = String.to_existing_atom(level)
    {:noreply, assign(socket, min_log_level: level)}
  end

  defp field_color(field) do
    case field.content do
      :empty ->
        {"bg-gray-200", ""}

      :plowed ->
        {"bg-brown-200", ""}

      :grass ->
        case field.growth_stage do
          0 -> {"bg-green-100", ""}
          1 -> {"bg-green-200", ""}
          2 -> {"bg-green-300", ""}
          3 -> {"bg-green-400", ""}
          4 -> {"bg-green-500", "☘️"}
        end

      :wheat ->
        case field.growth_stage do
          0 -> {"bg-yellow-100", "🫘"}
          1 -> {"bg-yellow-200", "🌱"}
          2 -> {"bg-yellow-300", "🌿"}
          3 -> {"bg-yellow-400", "🌿"}
          4 -> {"bg-yellow-500", "🌾"}
        end
    end
  end

  defp bot_icon(bot, owned) do
    case bot.current_action do
      nil -> if owned, do: "🤖", else: "👾"
      :idle -> if owned, do: "🤖", else: "👾"
      :move_left -> "👈"
      :move_right -> "👉"
      :move_up -> "👆"
      :move_down -> "👇"
      :seed -> "🌱"
      :water -> "💧"
      :harvest -> "✂️"
      :plow -> "🚜"
    end
  end

  defp bot_names do
    prefixes = [
      "Agri",
      "Farm",
      "Crop",
      "Soil",
      "Seed",
      "Harvest",
      "Field",
      "Grow",
      "Water",
      "Sun",
      "Rain",
      "Earth",
      "Green",
      "Fresh",
      "Rustic",
      "Country",
      "Rural",
      "Pasture",
      "Meadow",
      "Orchard"
    ]

    suffixes = [
      "Bot",
      "Helper",
      "Master",
      "Guardian",
      "Scout",
      "Sower",
      "Watcher",
      "Guide",
      "Friend",
      "Buddy",
      "Pal",
      "Mate",
      "Pro",
      "Expert",
      "Wizard",
      "Genius",
      "Whiz",
      "Ace",
      "Star",
      "Champ"
    ]

    for prefix <- prefixes, suffix <- suffixes do
      "#{prefix} #{suffix}"
    end
  end

  defp random_bot_name(bot_id) do
    index = :erlang.phash2(bot_id, length(bot_names()))
    Enum.at(bot_names(), index)
  end

  defp log_level_weight(level) do
    case level do
      :debug -> 0
      :info -> 1
      :warn -> 2
      :error -> 3
    end
  end
end
