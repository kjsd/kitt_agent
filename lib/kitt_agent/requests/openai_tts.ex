defmodule KittAgent.Requests.OpenAITTS do
  @moduledoc """
  OpenAI-compatible Text-to-Speech (TTS) client for `openai-tts-bridge`.
  Calls `POST /v1/audio/speech` per sentence chunk with `[mood]` tag control and dynamic
  per-Kitt reference voice (`speaker_audio_base64`), supporting real-time LLM streaming
  prefetch, WebSocket `talk_chunk` delivery, and canonical RIFF WAVE concatenation.
  User pronunciation dictionaries and engine-specific text normalizations are delegated
  centrally to `openai-tts-bridge`.
  """

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Kitts, Events, Talks, StageLogger}

  require Logger
  require Content

  @default_url "http://nina.local:8080/v1"
  @default_model "tts-1"
  @default_voice "nina2"
  @inter_chunk_silence_sec 0.1
  @prefetch_table :tts_chunk_prefetch

  @doc """
  Processes a Content item: splits message into sentence chunks, consumes prefetched or
  newly synthesized WAV chunks via `openai-tts-bridge`, streams `talk_chunk` events to
  connected WebSocket clients, concatenates full WAV to disk, and enqueues to `Talks` /
  `SystemActions` as appropriate.
  """
  def process(%Content{} = content, %Kitt{} = kitt) do
    try do
      chunks = prepare_chunks(content.message || "")
      model = openai_tts_model()
      is_system_action = content.action == Content.action_system()

      StageLogger.tts_started("OpenAI TTS / #{model} (#{length(chunks)} chunk(s))")

      Logger.info(
        "TTS: Generating audio for Content #{content.id} (Model: #{model}, Chunks: #{length(chunks)}, Mood: #{inspect(content.mood)})..."
      )

      with {:ok, wav_binaries, pushed_any} <-
             synthesize_chunks(
               chunks,
               kitt,
               content.mood,
               true,
               not is_system_action
             ),
           {:ok, wav_binary} <- concat_wav_binaries(wav_binaries),
           {:ok, local_rel_path} <- save_audio(wav_binary, kitt),
           {:ok, %Content{} = updated_content} <-
             Events.update_content(
               content,
               %{audio_path: local_rel_path}
             ) do
        KittAgent.SystemActions.set_thinking(kitt.id, false)
        duration_sec = wav_duration_sec(wav_binary)

        if pushed_any do
          Talks.broadcast_ws(kitt.id, %{
            type: "talk_complete",
            id: updated_content.id,
            action: updated_content.action,
            message: updated_content.message,
            mood: updated_content.mood,
            audio_path: updated_content.audio_path
          })
        else
          Talks.enqueue_or_push(kitt.id, updated_content)
        end

        # If this is a SystemAction, enqueue it for the mBot2 AFTER the audio is ready.
        # If it is a Talk action and WebSocket streaming did not already enqueue per-chunk
        # `talk_led`, enqueue a virtual SystemAction (`talk_led`) for the full duration.
        if is_system_action do
          KittAgent.SystemActions.Queue.enqueue(kitt.id, updated_content)
        else
          if not pushed_any and KittAgent.SystemActions.queue_length(kitt.id) == 0 do
            KittAgent.SystemActions.enqueue_talk_led(kitt.id, duration_sec)
          end
        end

        updated_content
        |> Events.broadcast_change()

        StageLogger.tts_completed(duration_sec, is_system_action)
        Logger.info("TTS: Completed (#{duration_sec}s). Saved to #{local_rel_path}")
        {:ok, updated_content}
      else
        error ->
          KittAgent.SystemActions.set_thinking(kitt.id, false)
          Logger.error("TTS: Failed. Reason: #{inspect(error)}")
          Talks.broadcast_ws(kitt.id, %{type: "talk_complete", error: true})
          fallback_enqueue_system_action(content, kitt)
          {:error, error}
      end
    rescue
      e ->
        KittAgent.SystemActions.set_thinking(kitt.id, false)
        Logger.error("TTS: Exception: #{inspect(e)}")
        Talks.broadcast_ws(kitt.id, %{type: "talk_complete", error: true})
        fallback_enqueue_system_action(content, kitt)
        {:error, e}
    end
  end

  defp fallback_enqueue_system_action(%Content{} = content, %Kitt{} = kitt) do
    if content.action == Content.action_system() do
      Logger.warning("TTS: Enqueueing SystemAction despite TTS failure as a fallback.")
      KittAgent.SystemActions.Queue.enqueue(kitt.id, content)
    end
  end

  @doc """
  Formats input text for `openai-tts-bridge` using mood-only control.
  Strips stray inline bracket tags and Markdown formatting, leaving dictionary and
  engine-specific text normalization to `openai-tts-bridge`, and prefixes `[mood]`
  when `mood` is non-empty and not neutral/default.
  """
  def prepare_input_text(message, mood) do
    cleaned_text =
      (message || "")
      |> clean_text_for_tts()

    trimmed_mood = String.trim(mood || "")

    if trimmed_mood not in ["", "neutral", "normal", "default"] and cleaned_text != "" do
      "[#{trimmed_mood}] " <> cleaned_text
    else
      cleaned_text
    end
  end

  @doc """
  Splits text into individual sentence chunks by Japanese/English sentence-ending
  punctuation (`。`, `！`, `？`, `!`, `?`) and newlines, cleaning Markdown and inline tags
  while preserving natural punctuation (`…`, `〜`, etc.) for `openai-tts-bridge`.
  """
  def prepare_chunks(text) when is_binary(text) do
    chunks =
      text
      |> String.replace(~r/`{1,3}.*?`{1,3}/s, "")
      |> split_text()
      |> Enum.map(&clean_text_for_tts/1)
      |> Enum.filter(&speakable?/1)

    case chunks do
      [_ | _] ->
        chunks

      [] ->
        fallback = clean_text_for_tts(text)
        if speakable?(fallback), do: [fallback], else: []
    end
  end

  def prepare_chunks(_), do: []

  @doc """
  Splits text into sentences while keeping terminal punctuation attached to each sentence.
  """
  def split_text(text) when is_binary(text) do
    Regex.split(~r/([。！？!?]+|\r?\n+)/u, text, include_captures: true, trim: true)
    |> Enum.reduce([], fn part, acc ->
      if Regex.match?(~r/^([。！？!?]+|\r?\n+)$/u, part) do
        punct = String.trim(part)

        case acc do
          [current | rest] when punct != "" -> [current <> punct | rest]
          _ -> acc
        end
      else
        trimmed = String.trim(part)
        if trimmed != "", do: [trimmed | acc], else: acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Cleans Markdown, inline bracket emotion tags, parenthetical remarks, and emojis
  while keeping natural text and punctuation intact for `openai-tts-bridge`.
  """
  def clean_text_for_tts(text) do
    (text || "")
    # Remove Markdown bold/italic
    |> String.replace(~r/[\*\_]{1,3}/, "")
    # Remove code blocks
    |> String.replace(~r/`{1,3}.*?`{1,3}/s, "")
    # Strip inline bracket tags (e.g. [laughter], [sigh], [whisper])
    |> String.replace(~r/\[[a-zA-Z0-9_\-\s]+\]/, "")
    # Remove Japanese bracket tags (e.g. 【笑い】)
    |> String.replace(~r/【.*?】/, "")
    # Remove parenthetical stage remarks
    |> String.replace(~r/（.*?）|\(.*?\)/, "")
    # Remove emojis and control symbols while preserving ASCII, Japanese, punctuation, ellipses, and wave dashes
    |> String.replace(~r/[^\x00-\x7F\p{Hiragana}\p{Katakana}\p{Han}、。！？ー…〜～・\n]/u, "")
    # Collapse multiple whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp speakable?(text) when is_binary(text) do
    String.match?(text, ~r/[\p{Hiragana}\p{Katakana}\p{Han}a-zA-Z0-9]/u)
  end

  @doc """
  Extracts `mood` and any already-completed sentence chunks from an in-progress
  streaming LLM JSON string so TTS synthesis can begin while the LLM is still
  generating subsequent sentences or `parameter` (MicroPython code).
  """
  def extract_ready_tts_chunks(partial_json) when is_binary(partial_json) do
    with [_, mood] <- Regex.run(~r/"mood"\s*:\s*"([^"\\]+)"/, partial_json) do
      cond do
        # Case A: "message" field has a complete closing quote
        match = Regex.run(~r/"message"\s*:\s*"((?:\\.|[^"\\])*)"/s, partial_json) ->
          [_, raw_escaped] = match

          with {:ok, full_message} <- Jason.decode("\"#{raw_escaped}\""),
               [_ | _] = chunks <- prepare_chunks(full_message) do
            {:ok, mood, chunks}
          else
            _ -> :incomplete
          end

        # Case B: "message" field is still streaming; any sentence before the last chunk is complete
        match = Regex.run(~r/"message"\s*:\s*"((?:\\.|[^"\\])*)/s, partial_json) ->
          [_, raw_partial] = match

          with {:ok, partial_message} <- Jason.decode("\"#{raw_partial}\""),
               false <- String.contains?(partial_message, "`"),
               chunks when length(chunks) >= 2 <- prepare_chunks(partial_message),
               [_ | _] = completed_chunks <- Enum.drop(chunks, -1) do
            {:ok, mood, completed_chunks}
          else
            _ -> :incomplete
          end

        true ->
          :incomplete
      end
    else
      _ -> :incomplete
    end
  end

  def extract_ready_tts_chunks(_), do: :incomplete

  @doc """
  Starts background synthesis for completed sentence chunks in strict sequential order
  while the LLM is still streaming the remainder of the response.
  """
  def prefetch_chunks_async(%Kitt{} = kitt, mood, chunks)
      when is_binary(mood) and is_list(chunks) and chunks != [] do
    table = ensure_prefetch_table()
    now = System.monotonic_time(:millisecond)
    mood_key = normalize_mood_key(mood)

    chunks_with_keys =
      Enum.map(chunks, fn chunk -> {chunk, {kitt.id, mood_key, chunk}} end)

    new_items =
      chunks_with_keys
      |> Enum.with_index()
      |> Enum.filter(fn {{_chunk, key}, _idx} ->
        :ets.insert_new(table, {key, :in_progress, now})
      end)

    if new_items != [] do
      voice = resolve_voice(kitt)
      model = openai_tts_model()
      speaker_audio_b64 = load_speaker_audio_base64(kitt)

      Task.start(fn ->
        Enum.each(new_items, fn {{chunk, key}, idx} ->
          prev_key =
            if idx > 0 do
              elem(Enum.at(chunks_with_keys, idx - 1), 1)
            else
              nil
            end

          wait_for_prev_key(table, prev_key, System.monotonic_time(:millisecond) + 60_000)

          Logger.info("TTS Prefetch: Synthesizing early chunk [#{idx + 1}]: #{inspect(chunk)}")

          input_text = prepare_input_text(chunk, mood)

          case call_speech_api(input_text, voice, model, speaker_audio_b64) do
            {:ok, wav_binary} ->
              pushed? = maybe_push_chunk_ws(wav_binary, kitt, mood, chunk, idx, false)

              :ets.insert(
                table,
                {key, {:done, {:ok, wav_binary, pushed?}}, System.monotonic_time(:millisecond)}
              )

            {:error, reason} ->
              Logger.warning(
                "TTS Prefetch: Early chunk failed (will retry synchronously): #{inspect(reason)}"
              )

              :ets.delete(table, key)
          end
        end)
      end)
    end

    :ok
  end

  def prefetch_chunks_async(_, _, _), do: :ok

  @doc """
  Stores a pre-synthesized WAV binary into the prefetch cache (also used by unit tests).
  """
  def put_prefetched_chunk(kitt_id, mood, chunk, wav_binary) when is_binary(wav_binary) do
    table = ensure_prefetch_table()
    key = {kitt_id, normalize_mood_key(mood), chunk}

    :ets.insert(
      table,
      {key, {:done, {:ok, wav_binary, false}}, System.monotonic_time(:millisecond)}
    )

    :ok
  end

  @doc """
  Synthesizes (or consumes prefetched) sentence chunks in order, optionally streaming
  `talk_chunk` events over WebSocket and enqueueing per-chunk `talk_led` actions.
  """
  def synthesize_chunks(chunks, kitt, mood, stream_ws? \\ false, talk_led? \\ false)

  def synthesize_chunks([], _kitt, _mood, _stream_ws?, _talk_led?) do
    {:error, "No speakable text chunks"}
  end

  def synthesize_chunks(chunks, %Kitt{} = kitt, mood, stream_ws?, talk_led?) do
    table = ensure_prefetch_table()
    mood_key = normalize_mood_key(mood)
    total = length(chunks)
    keys = Enum.map(chunks, &{kitt.id, mood_key, &1})

    voice = resolve_voice(kitt)
    model = openai_tts_model()
    speaker_audio_b64 = load_speaker_audio_base64(kitt)

    result =
      chunks
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, [], false}, fn {chunk, idx}, {:ok, acc, pushed_acc} ->
        key = {kitt.id, mood_key, chunk}
        is_last = idx == total

        case await_prefetch_entry(table, key, System.monotonic_time(:millisecond) + 60_000) do
          {:ok, wav_binary, true} ->
            Logger.info(
              "TTS: Using prefetched & WS-pushed chunk [#{idx}/#{total}]: #{inspect(chunk)}"
            )

            KittAgent.SystemActions.set_thinking(kitt.id, false)

            if talk_led? do
              KittAgent.SystemActions.enqueue_talk_led(kitt.id, wav_duration_sec(wav_binary))
            end

            {:cont, {:ok, [wav_binary | acc], true}}

          {:ok, wav_binary, false} ->
            Logger.info("TTS: Using prefetched chunk [#{idx}/#{total}]: #{inspect(chunk)}")

            pushed_now =
              if stream_ws? do
                maybe_push_chunk_ws(wav_binary, kitt, mood, chunk, idx - 1, is_last)
              else
                false
              end

            if pushed_now and talk_led? do
              KittAgent.SystemActions.enqueue_talk_led(kitt.id, wav_duration_sec(wav_binary))
            end

            {:cont, {:ok, [wav_binary | acc], pushed_acc or pushed_now}}

          :miss ->
            Logger.info("TTS: Generating chunk [#{idx}/#{total}]: #{inspect(chunk)}")
            input_text = prepare_input_text(chunk, mood)

            case call_speech_api(input_text, voice, model, speaker_audio_b64) do
              {:ok, wav_binary} ->
                pushed_now =
                  if stream_ws? do
                    maybe_push_chunk_ws(wav_binary, kitt, mood, chunk, idx - 1, is_last)
                  else
                    false
                  end

                if pushed_now and talk_led? do
                  KittAgent.SystemActions.enqueue_talk_led(kitt.id, wav_duration_sec(wav_binary))
                end

                {:cont, {:ok, [wav_binary | acc], pushed_acc or pushed_now}}

              {:error, reason} ->
                {:halt, {:error, "Chunk #{idx}/#{total} failed: #{inspect(reason)}"}}
            end
        end
      end)

    Enum.each(keys, &:ets.delete(table, &1))

    case result do
      {:ok, rev_binaries, pushed_any} -> {:ok, Enum.reverse(rev_binaries), pushed_any}
      {:error, _} = err -> err
    end
  end

  @doc """
  Resolves speaker voice name. If kitt has an audio_path, uses its base name without extension.
  Otherwise falls back to config or default 'nina2'.
  """
  def resolve_voice(%Kitt{audio_path: audio_path})
      when is_binary(audio_path) and audio_path != "" do
    Path.basename(audio_path, Path.extname(audio_path))
  end

  def resolve_voice(_kitt) do
    case KittAgent.Configs.get_config("openai_tts_default_voice", @default_voice) do
      val when is_binary(val) and val != "" -> val
      _ -> @default_voice
    end
  end

  @doc """
  Loads the Kitt's uploaded reference audio file (if exists) and returns base64-encoded string.
  Returns nil if no audio file is registered or found.
  """
  def load_speaker_audio_base64(%Kitt{} = kitt) do
    with path when is_binary(path) <- Kitts.resource_audio(kitt),
         true <- File.exists?(path),
         {:ok, binary} <- File.read(path) do
      Base.encode64(binary)
    else
      _ -> nil
    end
  end

  def load_speaker_audio_base64(_), do: nil

  @doc """
  Sends request to OpenAI-compatible POST /audio/speech endpoint.
  Supports optional speaker_audio_base64 parameter for custom speaker cloning.
  Returns raw WAV binary data on success.
  """
  def call_speech_api(input_text, voice, model, custom_audio_b64 \\ nil) do
    base_url = openai_tts_url() |> String.trim_trailing("/")
    url = "#{base_url}/audio/speech"

    payload =
      %{
        "model" => model,
        "input" => input_text,
        "voice" => voice,
        "response_format" => "wav"
      }
      |> maybe_put_custom_audio(custom_audio_b64)

    headers = [
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: payload, headers: headers, receive_timeout: 45_000) do
      {:ok, %{status: 200, body: wav_binary}}
      when is_binary(wav_binary) and byte_size(wav_binary) > 0 ->
        {:ok, wav_binary}

      {:ok, %{status: status, body: body}} ->
        {:error, "API returned HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp maybe_put_custom_audio(payload, b64) when is_binary(b64) and b64 != "" do
    Map.put(payload, "speaker_audio_base64", b64)
  end

  defp maybe_put_custom_audio(payload, _), do: payload

  @doc """
  Computes audio duration in seconds from a RIFF WAVE binary using the `fmt ` chunk's
  `byte_rate` (supporting 24kHz Irodori-TTS, 44.1kHz Zonos, and any PCM format).
  """
  def wav_duration_sec(wav_binary) when is_binary(wav_binary) do
    {data_bytes, byte_rate} =
      case parse_wav_chunks(wav_binary) do
        {:ok,
         <<_fmt::unsigned-little-16, _ch::unsigned-little-16, _sr::unsigned-little-32,
           rate::unsigned-little-32, _::binary>>, data_body}
        when rate > 0 ->
          {byte_size(data_body), rate}

        _ ->
          rate =
            case wav_binary do
              <<"RIFF", _::binary-size(24), r::unsigned-little-32, _::binary>> when r > 0 -> r
              _ -> 48_000
            end

          {max(byte_size(wav_binary) - 44, 0), rate}
      end

    data_bytes
    |> Kernel./(byte_rate)
    |> Float.round(1)
    |> max(1.0)
  end

  @doc """
  Concatenates one or more RIFF WAVE binaries into a single canonical RIFF WAVE binary,
  inserting a short natural pause (`#{@inter_chunk_silence_sec}s` of digital silence)
  between sentence chunks.
  """
  def concat_wav_binaries([single_wav]) when is_binary(single_wav) do
    case parse_wav_chunks(single_wav) do
      {:ok, fmt_body, data_body} ->
        {:ok, build_wav_binary(fmt_body, data_body)}

      {:error, _} ->
        {:ok, single_wav}
    end
  end

  def concat_wav_binaries([_ | _] = wav_binaries) do
    parsed =
      Enum.reduce_while(wav_binaries, {:ok, nil, []}, fn wav, {:ok, first_fmt, data_acc} ->
        case parse_wav_chunks(wav) do
          {:ok, fmt_body, data_body} ->
            {:cont, {:ok, first_fmt || fmt_body, [data_body | data_acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case parsed do
      {:ok, fmt_body, rev_data_chunks} when is_binary(fmt_body) ->
        silence = build_silence_bytes(fmt_body, @inter_chunk_silence_sec)

        combined_data =
          rev_data_chunks
          |> Enum.reverse()
          |> Enum.intersperse(silence)
          |> IO.iodata_to_binary()

        {:ok, build_wav_binary(fmt_body, combined_data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def concat_wav_binaries([]), do: {:error, "No audio chunks generated"}

  @doc """
  Checks connection to the configured OpenAI TTS Bridge server by calling `/models` or `/health`.
  """
  def check_connection(url) do
    clean_url = String.trim_trailing(url || "", "/")

    case Req.get("#{clean_url}/models", receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        {:ok, "Connection successful (OpenAI API models endpoint verified)"}

      {:ok, %{status: status}} ->
        case Req.get("#{clean_url}/health", receive_timeout: 5_000) do
          {:ok, %{status: 200}} -> {:ok, "Connection successful"}
          _ -> {:error, "Connection failed. Status: #{status}"}
        end

      {:error, exception} ->
        {:error, "Connection failed. Error: #{inspect(exception)}"}
    end
  end

  def openai_tts_url() do
    case KittAgent.Configs.get_config("openai_tts_url", @default_url) do
      val when is_binary(val) and val != "" -> val
      _ -> @default_url
    end
  end

  def openai_tts_model() do
    case KittAgent.Configs.get_config("openai_tts_model", @default_model) do
      val when is_binary(val) and val != "" -> val
      _ -> @default_model
    end
  end

  @doc """
  Derives the `openai-tts-bridge` Web UI root URL from the configured `/v1` API base URL
  (e.g. `"http://nina.local:8080/v1"` -> `"http://nina.local:8080"`).
  """
  def bridge_ui_url(api_url \\ nil) do
    raw =
      case api_url do
        val when is_binary(val) and val != "" -> val
        _ -> openai_tts_url()
      end

    raw
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.replace_suffix("/v1", "")
  end

  defp maybe_push_chunk_ws(wav_binary, %Kitt{} = kitt, mood, chunk_text, chunk_idx, is_last) do
    if Talks.ws_connected?(kitt.id) do
      case save_temp_chunk_audio(wav_binary, kitt) do
        {:ok, chunk_rel_path} ->
          pushed =
            Talks.broadcast_ws(kitt.id, %{
              type: "talk_chunk",
              mood: mood,
              message: chunk_text,
              audio_path: chunk_rel_path,
              chunk_index: chunk_idx,
              is_last: is_last
            })

          if pushed do
            KittAgent.SystemActions.set_thinking(kitt.id, false)

            Logger.info(
              "TTS WS Stream: Pushed chunk [#{chunk_idx + 1}] (#{chunk_rel_path}, is_last=#{is_last})"
            )
          end

          pushed

        {:error, reason} ->
          Logger.warning("TTS WS Stream: Failed to save temp chunk audio: #{inspect(reason)}")
          false
      end
    else
      false
    end
  end

  defp save_temp_chunk_audio(wav_binary, %Kitt{} = kitt) when is_binary(wav_binary) do
    try do
      {:ok, canonical_wav} = concat_wav_binaries([wav_binary])
      filename = "chunk_#{Ecto.UUID.generate()}.wav"
      local_rel_path = Kitts.path(kitt, filename)
      local_abs_path = Kitts.resource(kitt, filename)

      File.mkdir_p!(Path.dirname(local_abs_path))
      File.write!(local_abs_path, canonical_wav)

      Task.start(fn ->
        Process.sleep(120_000)
        File.rm(local_abs_path)
      end)

      {:ok, local_rel_path}
    rescue
      e -> {:error, e}
    end
  end

  defp save_audio(wav_binary, %Kitt{} = kitt) do
    filename = "#{Ecto.UUID.generate()}.wav"
    local_rel_path = Kitts.path(kitt, filename)
    local_abs_path = Kitts.resource(kitt, filename)

    File.mkdir_p!(Path.dirname(local_abs_path))

    case File.write(local_abs_path, wav_binary) do
      :ok -> {:ok, local_rel_path}
      {:error, reason} -> {:error, "Failed to write audio file: #{inspect(reason)}"}
    end
  end

  defp normalize_mood_key(mood) do
    (mood || "default")
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp ensure_prefetch_table do
    case :ets.whereis(@prefetch_table) do
      :undefined ->
        try do
          :ets.new(@prefetch_table, [:named_table, :public, :set])
        rescue
          ArgumentError -> @prefetch_table
        end

      _tid ->
        prune_stale_prefetch_entries(@prefetch_table)
        @prefetch_table
    end
  end

  defp prune_stale_prefetch_entries(table) do
    cutoff = System.monotonic_time(:millisecond) - 60_000

    try do
      :ets.foldl(
        fn
          {key, _status, ts}, acc when ts < cutoff ->
            :ets.delete(table, key)
            acc

          _, acc ->
            acc
        end,
        :ok,
        table
      )
    rescue
      _ -> :ok
    end
  end

  defp wait_for_prev_key(_table, nil, _deadline), do: :ok

  defp wait_for_prev_key(table, prev_key, deadline) do
    case :ets.lookup(table, prev_key) do
      [{^prev_key, :in_progress, _ts}] ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(20)
          wait_for_prev_key(table, prev_key, deadline)
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp await_prefetch_entry(table, key, deadline) do
    case :ets.lookup(table, key) do
      [{^key, {:done, {:ok, wav_binary, pushed?}}, _ts}] ->
        {:ok, wav_binary, pushed?}

      [{^key, {:done, {:ok, wav_binary}}, _ts}] ->
        {:ok, wav_binary, false}

      [{^key, :in_progress, ts}] ->
        now = System.monotonic_time(:millisecond)

        if now < deadline and now - ts < 60_000 do
          Process.sleep(20)
          await_prefetch_entry(table, key, deadline)
        else
          :ets.delete(table, key)
          :miss
        end

      _ ->
        :miss
    end
  end

  defp parse_wav_chunks(<<"RIFF", _riff_size::unsigned-little-32, "WAVE", rest::binary>>) do
    do_parse_wav_chunks(rest, nil, [])
  end

  defp parse_wav_chunks(_), do: {:error, "Invalid RIFF WAVE header"}

  defp do_parse_wav_chunks(<<>>, fmt_body, data_acc)
       when is_binary(fmt_body) and data_acc != [] do
    {:ok, fmt_body, IO.iodata_to_binary(Enum.reverse(data_acc))}
  end

  defp do_parse_wav_chunks(
         <<chunk_id::binary-size(4), chunk_size::unsigned-little-32, rest::binary>>,
         fmt_body,
         data_acc
       )
       when byte_size(rest) >= chunk_size do
    <<chunk_body::binary-size(^chunk_size), after_chunk::binary>> = rest
    pad = rem(chunk_size, 2)

    remaining =
      if pad == 1 and byte_size(after_chunk) >= 1 do
        <<_pad_byte::8, tail::binary>> = after_chunk
        tail
      else
        after_chunk
      end

    case chunk_id do
      "fmt " ->
        do_parse_wav_chunks(remaining, fmt_body || chunk_body, data_acc)

      "data" ->
        do_parse_wav_chunks(remaining, fmt_body, [chunk_body | data_acc])

      _other ->
        do_parse_wav_chunks(remaining, fmt_body, data_acc)
    end
  end

  defp do_parse_wav_chunks(_rest, fmt_body, data_acc)
       when is_binary(fmt_body) and data_acc != [] do
    {:ok, fmt_body, IO.iodata_to_binary(Enum.reverse(data_acc))}
  end

  defp do_parse_wav_chunks(_, _, _), do: {:error, "Incomplete WAV chunks"}

  defp build_silence_bytes(
         <<_audio_format::unsigned-little-16, _num_channels::unsigned-little-16,
           _sample_rate::unsigned-little-32, byte_rate::unsigned-little-32,
           block_align::unsigned-little-16, _rest::binary>>,
         seconds
       )
       when byte_rate > 0 and block_align > 0 and seconds > 0 do
    frames = trunc(byte_rate * seconds / block_align)
    :binary.copy(<<0>>, frames * block_align)
  end

  defp build_silence_bytes(_fmt_body, _seconds), do: <<>>

  defp build_wav_binary(fmt_body, data_body) do
    fmt_chunk = <<"fmt ", byte_size(fmt_body)::unsigned-little-32, fmt_body::binary>>
    data_chunk = <<"data", byte_size(data_body)::unsigned-little-32, data_body::binary>>
    riff_size = 4 + byte_size(fmt_chunk) + byte_size(data_chunk)
    <<"RIFF", riff_size::unsigned-little-32, "WAVE", fmt_chunk::binary, data_chunk::binary>>
  end
end
