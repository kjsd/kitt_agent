defmodule KittAgent.Requests do
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Prompts
  alias KittAgent.Events

  require Logger

  def talk(%Kitt{} = kitt, user_text) do
    api_key = Application.get_env(:kitt_agent, :keys)[:openrouter]

    last_ev = kitt |> Events.make_talk_event(user_text)
    case Req.post(Application.get_env(:kitt_agent, :api_urls)[:openrouter],
          json: kitt |> Prompts.make(last_ev),
          headers: [{"Authorization", "Bearer #{api_key}"},
                    {"HTTP-Referer", "https://www.kandj.org"},
                    {"X-Title", "KJSD"}]
        ) do
      {:ok, %{status: 200, body: resp_body}} ->
        with [choice | _] <- resp_body["choices"],
             {:ok, res} <- Jason.decode(choice["message"]["content"]) do

          kitt |> Events.create_event!(last_ev)
          kitt |> Events.create_kitt_event!(res)
          
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
