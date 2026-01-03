defmodule KittAgent.Requests.OpenRouter do
  alias KittAgent.Repo
  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Events, Summarizer, TTS, SystemActions}
  alias KittAgent.Requests.Prompts

  require Logger

  def list_models() do
    api_key =
      KittAgent.Configs.get_config("api_key") ||
        Application.get_env(:kitt_agent, :keys)[:openrouter]

    headers = if api_key, do: [{"Authorization", "Bearer #{api_key}"}], else: []

    case Req.get("https://openrouter.ai/api/v1/models", headers: headers) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        {:ok, Enum.map(models, fn m -> %{id: m["id"], name: m["name"]} end)}

      {:ok, e} ->
        {:error, e}

      {:error, e} ->
        {:error, e}
    end
  end

  def talk(%Kitt{} = kitt, user_text) do
    api_key =
      KittAgent.Configs.get_config("api_key") ||
        Application.get_env(:kitt_agent, :keys)[:openrouter]

    api_url =
      KittAgent.Configs.get_config("api_url") ||
        Application.get_env(:kitt_agent, :api_urls)[:openrouter]

    last_ev = Events.make_user_talk_event(user_text)

    case Req.post(api_url,
           json: kitt |> Prompts.make(last_ev),
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"HTTP-Referer", "https://www.kandj.org"},
             {"X-Title", "KJSD"}
           ]
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        with [choice | _] <- resp_body["choices"],
             {:ok, res} <- Jason.decode(choice["message"]["content"]) do
          last_ev |> Events.create_kitt_event(kitt)

          with {:ok, event} <-
                 Events.make_kitt_event(res)
                 |> Events.create_kitt_event(kitt) do
            if(
              Application.get_env(:kitt_agent, KittAgent.Requests, [])
              |> Keyword.get(:talk, [])
              |> Keyword.get(:enable_tts, true)
            ) do
              TTS.RequestBroker.exec(kitt, event.content)
            end

            if event.content.action == Content.action_system do
              SystemActions.Queue.enqueue(kitt.id, event.content)
            end

            if(
              Application.get_env(:kitt_agent, KittAgent.Requests, [])
              |> Keyword.get(:talk, [])
              |> Keyword.get(:enable_summarizer, true)
            ) do
              Summarizer.exec(kitt)
            end

            {:ok, event.content}
          end
        else
          e ->
            Logger.error(inspect(e))
            {:error, e}
        end

      {:ok, e} ->
        Logger.error(inspect(e))
        {:error, e}
    end
  end

  def summary(%Kitt{} = kitt, [_ | _] = events) do
    api_key =
      KittAgent.Configs.get_config("api_key") ||
        Application.get_env(:kitt_agent, :keys)[:openrouter]

    api_url =
      KittAgent.Configs.get_config("api_url") ||
        Application.get_env(:kitt_agent, :api_urls)[:openrouter]

    case Req.post(api_url,
           json: Prompts.summary(kitt, events),
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"HTTP-Referer", "https://www.kandj.org"},
             {"X-Title", "KJSD"}
           ]
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        with [choice | _] <- resp_body["choices"],
             res <- choice["message"]["content"] do
          {:ok, res}
        else
          e ->
            {:error, e}
        end

      {:ok, e} ->
        {:error, e}
    end
  end
end
