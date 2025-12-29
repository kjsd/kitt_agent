defmodule KittAgentWeb.SettingsLive.Index do
  use KittAgentWeb, :live_view

  alias KittAgent.Configs
  alias KittAgent.Requests

  @impl true
  def mount(_params, _session, socket) do
    configs = 
      Configs.all_configs()
      |> Map.put_new("default_lang", "Japanese")
      |> Map.put_new("default_timezone", "Asia/Tokyo")
    
    models = 
      case Requests.list_models() do
        {:ok, list} -> list
        _ -> []
      end

    # タイムゾーン一覧の取得（tzdataがdepsにある想定）
    timezones = Tzdata.zone_list()

    # 主要言語
    languages = [
      "Arabic",
      "Chinese",
      "Dutch",
      "English",
      "French",
      "German",
      "Hindi",
      "Indonesian",
      "Italian",
      "Japanese",
      "Korean",
      "Portuguese",
      "Russian",
      "Spanish",
      "Swahili",
      "Thai",
      "Turkish",
      "Vietnamese"
    ]

    {:ok,
     socket
     |> assign(page_title: "Settings")
     |> assign(configs: configs)
     |> assign(models: models)
     |> assign(timezones: timezones)
     |> assign(languages: languages)}
  end

  @impl true
  def handle_event("save", %{"key" => key, "value" => value}, socket) do
    Configs.set_config(key, value)
    configs = Configs.all_configs()
    {:noreply, assign(socket, configs: configs) |> put_flash(:info, "Setting updated.")}
  end

  @impl true
  def handle_event("save_all", params, socket) do
    Enum.each(params, fn {k, v} -> 
      if k != "_target", do: Configs.set_config(k, v)
    end)
    configs = Configs.all_configs()
    {:noreply, assign(socket, configs: configs) |> put_flash(:info, "All settings saved.")}
  end
end
