defmodule KittAgent.Requests.OpenRouter do
  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Events, Summarizer, TTS, SystemActions, StageLogger}
  alias KittAgent.Requests.{Prompts, ZonosGradio}

  require Content
  require Logger

  @receive_timeout 60_000

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

    tts_enabled? =
      Application.get_env(:kitt_agent, KittAgent.Requests, [])
      |> Keyword.get(:talk, [])
      |> Keyword.get(:enable_tts, true)

    if tts_enabled? do
      ZonosGradio.warm_speaker_audio_async(kitt)
    end

    StageLogger.llm_started(user_text)

    payload =
      kitt
      |> Prompts.make(last_ev)
      |> Map.put(:stream, true)

    initial_stream_state = %{
      raw_chunks: [],
      sse_buffer: "",
      content_acc: "",
      prefetched_count: 0
    }

    into_fun = fn {:data, chunk}, {req, resp} ->
      state = Map.get(resp.private, :openrouter_stream, initial_stream_state)
      new_state = consume_stream_chunk(state, chunk, kitt, tts_enabled?)
      {:cont, {req, Req.Response.put_private(resp, :openrouter_stream, new_state)}}
    end

    case Req.post(api_url,
           json: payload,
           into: into_fun,
           receive_timeout: @receive_timeout,
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"HTTP-Referer", "https://www.kandj.org"},
             {"X-Title", "KJSD"}
           ]
         ) do
      {:ok, %{status: 200} = resp} ->
        with {:ok, res} <- extract_final_response(resp, initial_stream_state, kitt, tts_enabled?) do
          last_ev |> Events.create_kitt_event(kitt)

          with {:ok, event} <-
                 Events.make_kitt_event(res)
                 |> Events.create_kitt_event(kitt) do
            StageLogger.llm_completed(event.content)

            if tts_enabled? do
              # TTS will handle enqueuing the SystemAction after audio is generated to sync them.
              TTS.RequestBroker.exec(kitt, event.content)
            else
              # If TTS is disabled, enqueue SystemAction immediately.
              if event.content.action == Content.action_system() do
                SystemActions.Queue.enqueue(kitt.id, event.content)
              end
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
            Logger.error("OpenRouter talk decode/event error: #{inspect(e)}")
            {:error, e}
        end

      {:ok, e} ->
        Logger.error("OpenRouter talk unexpected response: #{inspect(e)}")
        {:error, e}

      {:error, e} ->
        Logger.error("OpenRouter talk transport error: #{inspect(e)}")
        {:error, e}
    end
  end

  defp consume_stream_chunk(state, chunk, %Kitt{} = kitt, tts_enabled?) when is_binary(chunk) do
    combined = state.sse_buffer <> chunk
    lines = String.split(combined, "\n")
    {complete_lines, [rem_buffer]} = Enum.split(lines, -1)

    state_with_raw = %{
      state
      | raw_chunks: [chunk | state.raw_chunks],
        sse_buffer: rem_buffer
    }

    Enum.reduce(complete_lines, state_with_raw, fn line, acc ->
      process_sse_line(String.trim_trailing(line, "\r"), acc, kitt, tts_enabled?)
    end)
  end

  defp process_sse_line("data: " <> data_str, state, %Kitt{} = kitt, tts_enabled?) do
    trimmed = String.trim(data_str)

    if trimmed == "" or trimmed == "[DONE]" do
      state
    else
      case Jason.decode(trimmed) do
        {:ok, %{"choices" => [%{"delta" => %{"content" => delta}} | _]}}
        when is_binary(delta) and delta != "" ->
          new_content_acc = state.content_acc <> delta
          maybe_trigger_tts_prefetch(%{state | content_acc: new_content_acc}, kitt, tts_enabled?)

        _ ->
          state
      end
    end
  end

  defp process_sse_line(_line, state, _kitt, _tts_enabled?), do: state

  defp maybe_trigger_tts_prefetch(state, %Kitt{} = kitt, true) do
    case ZonosGradio.extract_ready_tts_chunks(state.content_acc) do
      {:ok, mood, ready_chunks} when length(ready_chunks) > state.prefetched_count ->
        ZonosGradio.prefetch_chunks_async(kitt, mood, ready_chunks)
        %{state | prefetched_count: length(ready_chunks)}

      _ ->
        state
    end
  end

  defp maybe_trigger_tts_prefetch(state, _kitt, _tts_enabled?), do: state

  defp extract_final_response(resp, initial_stream_state, %Kitt{} = kitt, tts_enabled?) do
    state =
      resp.private
      |> Map.get(:openrouter_stream, initial_stream_state)
      |> then(fn s ->
        if s.sse_buffer != "" do
          process_sse_line(String.trim_trailing(s.sse_buffer, "\r"), %{s | sse_buffer: ""}, kitt, tts_enabled?)
        else
          s
        end
      end)

    cond do
      state.content_acc != "" ->
        Jason.decode(state.content_acc)

      is_map(resp.body) and is_list(resp.body["choices"]) ->
        with [choice | _] <- resp.body["choices"] do
          Jason.decode(choice["message"]["content"])
        end

      true ->
        raw_body = state.raw_chunks |> Enum.reverse() |> IO.iodata_to_binary()

        with {:ok, decoded} <- Jason.decode(raw_body),
             [choice | _] <- decoded["choices"] do
          Jason.decode(choice["message"]["content"])
        end
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
           receive_timeout: @receive_timeout,
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
        Logger.error("OpenRouter summary unexpected response: #{inspect(e)}")
        {:error, e}

      {:error, e} ->
        Logger.error("OpenRouter summary transport error: #{inspect(e)}")
        {:error, e}
    end
  end

  def check_connection(url, api_key) do
    headers = [{"Authorization", "Bearer #{api_key}"}]

    # Send an empty JSON object. 
    # If the endpoint is chat/completions, it will likely return 400 (Bad Request) or 422 
    # because "messages" field is missing. This confirms the server is reachable and the endpoint exists.
    # If we get 401, it means the endpoint is reached but key is wrong.
    case Req.post(url, json: %{}, headers: headers) do
      {:ok, %{status: status}} when status in [200, 400, 422] ->
        {:ok, "Connection successful (Status: #{status})"}

      {:ok, %{status: 401}} ->
        {:error, "Connection successful, but Unauthorized (401). Check API Key."}

      {:ok, %{status: status}} ->
        {:error, "Connection failed. Status: #{status}"}

      {:error, exception} ->
        {:error, "Connection failed. Error: #{inspect(exception)}"}
    end
  end
end
