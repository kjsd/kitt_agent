defmodule KittAgent.Requests do
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Prompts
  alias KittAgent.Events
  alias KittAgent.Summarizer
  alias KittAgent.SystemActions.Queue

  require Logger

  def talk(%Kitt{} = kitt, user_text) do
    api_key = Application.get_env(:kitt_agent, :keys)[:openrouter]

    last_ev = Events.make_user_talk_event(user_text)

    case Req.post(Application.get_env(:kitt_agent, :api_urls)[:openrouter],
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

          res
          |> Events.make_kitt_event()
          |> Events.create_kitt_event(kitt)
          |> elem(1)
          |> Events.system_actions()
          |> then(&if(match?([_|_], &1), do: Queue.enqueue(kitt.id, &1)))

          kitt.id |> Summarizer.exec()

          {:ok, res}
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
    api_key = Application.get_env(:kitt_agent, :keys)[:openrouter]

    case Req.post(Application.get_env(:kitt_agent, :api_urls)[:openrouter],
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
