defmodule KittAgent.Requests.ZonosGradio do
  @moduledoc """
  Zonos v0.1 Gradio Text-to-Speech (TTS) client.
  Communicates with the Zonos Gradio server (`Zyphra/Zonos-v0.1-hybrid`) via `/gradio_api`,
  mapping response mood to Zonos emotion & prosody parameters and cloning Kitt's reference audio.
  """

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Kitts, Events, Talks, StageLogger}

  require Logger
  require Content

  # Zonos-v0.1-hybrid
  @model_type "Zyphra/Zonos-v0.1-hybrid"
  @gradio_default_url "http://nina.local:7860"
  @inter_chunk_silence_sec 0.1

  @default_tts_dictionary String.trim("""
                          東白川村=ひがししらかわむら
                          東白川=ひがししらかわ
                          mBot2=エムボットツー
                          mBot=エムボット
                          CyberPi=サイバーパイ
                          Makeblock=メイクブロック
                          mBuild=エムビルド
                          K.I.T.T.=キット
                          KITT=キット
                          Kitt=キット
                          Knight Rider=ナイトライダー
                          LED=エルイーディー
                          RGB=アールジービー
                          RPM=アールピーエム
                          Wi-Fi=ワイファイ
                          WiFi=ワイファイ
                          AI=エーアイ
                          OK=オーケー
                          """)

  # --- Default Parameters ---
  @default_params %{
    # Emotions (0.0 - 1.0)
    happiness: 0.05,
    sadness: 0.05,
    disgust: 0.05,
    fear: 0.05,
    surprise: 0.05,
    anger: 0.05,
    other: 0.05,
    neutral: 0.2,

    # Audio Controls
    # Characters per second (approx)
    speaking_rate: 15.0,
    # Pitch standard deviation (Intonation)
    pitch_std: 45.0,
    vq_score: 0.78,
    fmax: 24000,
    dnsmos: 5.0,
    cfg_scale: 2.5
  }

  # --- Keyword Modifiers ---
  @modifiers %{
    # Basic Emotions
    "happy" => %{happiness: 0.8, pitch_std: 10.0},
    "joy" => %{happiness: 0.8, pitch_std: 15.0},
    "sad" => %{sadness: 0.9, speaking_rate: -2.0, pitch_std: -20.0},
    "cry" => %{sadness: 1.0, speaking_rate: -3.0, pitch_std: -10.0},
    "sigh" => %{sadness: 0.5, other: 0.3, speaking_rate: -2.5, pitch_std: -15.0},
    "angry" => %{anger: 0.9, speaking_rate: 3.0, pitch_std: 30.0},
    "mad" => %{anger: 0.9, speaking_rate: 4.0, pitch_std: 40.0},
    "irritated" => %{anger: 0.6, disgust: 0.2, speaking_rate: 1.5, pitch_std: 15.0},
    "pout" => %{anger: 0.4, sadness: 0.3, speaking_rate: -1.0, pitch_std: 10.0},
    "fear" => %{fear: 0.9, speaking_rate: 2.0, pitch_std: 10.0},
    "scared" => %{fear: 0.9, speaking_rate: 1.0},
    "surprise" => %{surprise: 0.9, pitch_std: 15.0},
    "shock" => %{surprise: 1.0, speaking_rate: -2.0},
    "disgust" => %{disgust: 0.9, speaking_rate: -3.0},

    # Nuance & Style
    "excited" => %{happiness: 0.5, surprise: 0.3, speaking_rate: 3.0, pitch_std: 20.0},
    "energetic" => %{happiness: 0.4, speaking_rate: 4.0, pitch_std: 20.0},
    "playful" => %{happiness: 0.6, surprise: 0.2, speaking_rate: 1.5, pitch_std: 15.0},
    "amused" => %{happiness: 0.6, speaking_rate: 0.5, pitch_std: 10.0},
    "lovely" => %{happiness: 0.7, other: 0.2, speaking_rate: -1.0, pitch_std: 10.0},
    "kindly" => %{happiness: 0.5, neutral: 0.3, speaking_rate: -1.0, pitch_std: -5.0},
    "assisting" => %{neutral: 0.6, happiness: 0.2, pitch_std: -5.0},
    "neutral" => %{neutral: 0.6},
    "default" => %{},
    "relaxed" => %{neutral: 0.5, happiness: 0.2, speaking_rate: -1.0, pitch_std: -10.0},
    "calm" => %{neutral: 0.6, speaking_rate: -2.0, pitch_std: -15.0},
    "serious" => %{neutral: 0.8, sadness: 0.1, speaking_rate: -1.0, pitch_std: -25.0},
    "assertive" => %{neutral: 0.5, anger: 0.2, speaking_rate: 1.5, pitch_std: 10.0},
    "teasing" => %{happiness: 0.5, other: 0.3, speaking_rate: -0.5, pitch_std: 15.0},
    "sassy" => %{happiness: 0.4, other: 0.3, speaking_rate: 1.0, pitch_std: 20.0},
    "smug" => %{happiness: 0.4, neutral: 0.4, speaking_rate: -1.0, pitch_std: 5.0},
    "smirking" => %{happiness: 0.4, other: 0.2, speaking_rate: -1.0, pitch_std: 5.0},
    "sarcastic" => %{neutral: 0.5, disgust: 0.2, other: 0.2, speaking_rate: -1.0, pitch_std: 10.0},
    "sardonic" => %{neutral: 0.5, disgust: 0.3, speaking_rate: -1.5, pitch_std: 5.0},
    "mocking" => %{happiness: 0.3, disgust: 0.3, speaking_rate: 0.5, pitch_std: 15.0},

    # Romance / Intimacy
    "flirty" => %{other: 0.6, happiness: 0.3, speaking_rate: -2.0, pitch_std: 10.0},
    "seductive" => %{other: 0.6, neutral: 0.3, speaking_rate: -4.0, pitch_std: 10.0},
    "sexy" => %{other: 0.7, neutral: 0.2, speaking_rate: -3.0, pitch_std: 15.0},
    "whisper" => %{neutral: 0.5, other: 0.4, speaking_rate: -3.0, pitch_std: -20.0},
    "intimate" => %{other: 0.4, neutral: 0.4, speaking_rate: -2.0, pitch_std: -10.0},
    "breathless" => %{other: 0.5, fear: 0.1, speaking_rate: -1.0, pitch_std: 5.0},
    "panting" => %{other: 0.6, fear: 0.2, speaking_rate: 2.0, pitch_std: 10.0},
    "moan" => %{other: 0.8, speaking_rate: -5.0},

    # Speed & Pitch explicit controls
    "fast" => %{speaking_rate: 5.0},
    "slow" => %{speaking_rate: -5.0},
    "flat" => %{pitch_std: -30.0},
    "dynamic" => %{pitch_std: 30.0}
  }

  @doc """
  Returns the default TTS pronunciation dictionary text (`word=reading` per line).
  """
  def default_tts_dictionary, do: @default_tts_dictionary

  @doc """
  Returns the active TTS dictionary string from DB config (`tts_dictionary`),
  falling back to `@default_tts_dictionary` when unset or blank.
  """
  def get_tts_dictionary_text do
    try do
      case KittAgent.Configs.get_config("tts_dictionary", @default_tts_dictionary) do
        val when is_binary(val) ->
          if String.trim(val) == "", do: @default_tts_dictionary, else: val

        _ ->
          @default_tts_dictionary
      end
    rescue
      _ -> @default_tts_dictionary
    catch
      :exit, _ -> @default_tts_dictionary
    end
  end

  def process(%Content{} = content, %Kitt{} = kitt) do
    try do
      lang_code = lang_to_code(kitt.lang)
      chunks = prepare_chunks(content.message || "")
      clean_text = Enum.join(chunks, " ")

      # Resolve Zonos parameters based on mood
      params = resolve_parameters(content.mood)
      log_mood_details(clean_text, content.mood, params)

      StageLogger.tts_started("Zonos TTS (#{length(chunks)} chunk(s))")

      Logger.info(
        "TTS: Generating audio for Content #{content.id} (Lang: #{lang_code}, Chunks: #{length(chunks)})..."
      )

      with {:ok, wav_binaries, pushed_any} <-
             synthesize_chunks(chunks, params, lang_code, kitt, content.mood, true),
           {:ok, wav_binary} <- concat_wav_binaries(wav_binaries),
           {:ok, local_path} <- save_audio(wav_binary, kitt),
           {:ok, %Content{} = updated_content} <-
             Events.update_content(
               content,
               %{audio_path: local_path}
             ) do
        duration_sec = wav_duration_sec(wav_binary)
        is_system_action = updated_content.action == KittAgent.Datasets.Content.action_system()

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
        # If it is a Talk action, enqueue a virtual SystemAction (`talk_led`) so mBot2's
        # front ultrasonic LEDs blink in sync with the audio duration.
        if is_system_action do
          KittAgent.SystemActions.Queue.enqueue(kitt.id, updated_content)
        else
          if KittAgent.SystemActions.queue_length(kitt.id) == 0 do
            talk_led_action = %Content{
              updated_content
              | action: KittAgent.Datasets.Content.action_system(),
                status: KittAgent.Datasets.Content.status_pending(),
                parameter: "talk_led(#{duration_sec})"
            }

            KittAgent.SystemActions.Queue.enqueue(kitt.id, talk_led_action)
          end
        end

        updated_content
        |> Events.broadcast_change()

        StageLogger.tts_completed(duration_sec, is_system_action)
        Logger.info("TTS: Completed. Saved to #{local_path}")
        {:ok, updated_content}
      else
        error ->
          Logger.error("TTS: Failed. Reason: #{inspect(error)}")
          Talks.broadcast_ws(kitt.id, %{type: "talk_complete", error: true})
          fallback_enqueue_system_action(content, kitt)
          {:error, error}
      end
    rescue
      e ->
        Logger.error("TTS: Exception: #{inspect(e)}")
        Talks.broadcast_ws(kitt.id, %{type: "talk_complete", error: true})
        fallback_enqueue_system_action(content, kitt)
        {:error, e}
    end
  end

  defp fallback_enqueue_system_action(%Content{} = content, %Kitt{} = kitt) do
    if content.action == KittAgent.Datasets.Content.action_system() do
      Logger.warning("TTS: Enqueueing SystemAction despite TTS failure as a fallback.")
      KittAgent.SystemActions.Queue.enqueue(kitt.id, content)
    end
  end

  @doc """
  Computes audio duration in seconds from a RIFF WAVE binary.
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
              _ -> 88_200
            end

          {max(byte_size(wav_binary) - 44, 0), rate}
      end

    data_bytes
    |> Kernel./(byte_rate)
    |> Float.round(1)
    |> max(1.0)
  end

  @doc """
  Splits text into individual sentence chunks by Japanese/English sentence-ending punctuation
  (`。`, `！`, `？`, `!`, `?`) and newlines, cleans each chunk for TTS, and normalizes
  sentence-final punctuation so Zonos v0.1's phonemizer cleanly terminates each sentence.
  """
  def prepare_chunks(text) when is_binary(text) do
    chunks =
      text
      # Remove multi-line code blocks before splitting on newlines
      |> String.replace(~r/`{1,3}.*?`{1,3}/s, "")
      |> split_text()
      |> Enum.map(&clean_text_for_tts/1)
      |> Enum.filter(&speakable?/1)
      |> Enum.map(&normalize_chunk_punctuation/1)

    case chunks do
      [_ | _] ->
        chunks

      [] ->
        fallback =
          text
          |> clean_text_for_tts()
          |> normalize_chunk_punctuation()

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
  Normalizes punctuation within a single TTS sentence chunk so Zonos v0.1 (`espeak-ng`)
  gets clean prosody boundaries and never trails off into mumbling/hallucination on trailing `…` or `〜`.
  """
  def normalize_chunk_punctuation(chunk) when is_binary(chunk) do
    cleaned =
      chunk
      |> String.replace("!", "！")
      |> String.replace("?", "？")
      # Strip trailing ellipses, tildes, dots, or spaces right before sentence-final ！/？/。
      |> String.replace(~r/[…〜～\.・\s]+([。！？]+)$/u, "\\1")
      # Strip trailing ellipses, tildes, commas, dots, or spaces at the end of the chunk
      |> String.replace(~r/[、,，…〜～\.・\s]+$/u, "")
      # Convert mid-sentence ellipses into a clean Japanese comma pause
      |> String.replace(~r/…+/u, "、")
      # Convert remaining wave dashes into standard Japanese long vowel mark (ー)
      |> String.replace(~r/[〜～]+/u, "ー")
      # Collapse duplicate commas
      |> String.replace(~r/、+/u, "、")
      |> String.trim()

    cond do
      cleaned == "" ->
        ""

      String.match?(cleaned, ~r/[。！？]$/u) ->
        cleaned

      true ->
        cleaned <> "。"
    end
  end

  defp speakable?(text) when is_binary(text) do
    String.match?(text, ~r/[\p{Hiragana}\p{Katakana}\p{Han}a-zA-Z0-9]/u)
  end

  @doc """
  Cleans tags, Markdown, and non-pronounceable characters from text,
  and applies the DB-managed TTS pronunciation dictionary & unit normalizations.
  """
  def clean_text_for_tts(text) do
    (text || "")
    # Remove Markdown bold/italic
    |> String.replace(~r/[\*\_]{1,3}/, "")
    # Remove code blocks
    |> String.replace(~r/`{1,3}.*?`{1,3}/s, "")
    # Strip any bracket tags completely (e.g. [laughter], [sigh], [whisper], [clear throat])
    |> String.replace(~r/\[[a-zA-Z0-9_\-\s]+\]/, "")
    # Remove Japanese bracket tags (e.g. 【笑い】)
    |> String.replace(~r/【.*?】/, "")
    # Remove parentheses and their content
    |> String.replace(~r/（.*?）|\(.*?\)/, "")
    # Apply DB-managed TTS pronunciation dictionary & unit normalizations
    |> apply_tts_dictionary()
    # Remove emojis and unknown symbols (preserve Japanese characters, punctuation, ellipses, and wavy dash)
    |> String.replace(~r/[^\x00-\x7F\p{Hiragana}\p{Katakana}\p{Han}、。！？ー…〜\n]/u, "")
    # Collapse multiple whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Applies the DB-managed `tts_dictionary` (`word=reading` lines) and common unit normalizations
  so TTS accurately pronounces place names (e.g. 東白川村) and English terms (e.g. mBot2, LED, RPM, cm).
  """
  def apply_tts_dictionary(text) when is_binary(text) do
    entries =
      get_tts_dictionary_text()
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.flat_map(fn line ->
        case String.split(line, ~r/\s*(?:=|=>|→)\s*/, parts: 2) do
          [word, reading] when word != "" and reading != "" -> [{word, reading}]
          _ -> []
        end
      end)
      # Replace longer words first (e.g., "東白川村" before "東白川", "mBot2" before "mBot")
      |> Enum.sort_by(fn {word, _reading} -> -String.length(word) end)

    text
    |> normalize_units_for_tts()
    |> then(fn acc_text ->
      Enum.reduce(entries, acc_text, fn {word, reading}, acc ->
        if String.match?(word, ~r/^[\x00-\x7F]+$/) do
          Regex.replace(Regex.compile!(Regex.escape(word), "i"), acc, reading)
        else
          String.replace(acc, word, reading)
        end
      end)
    end)
  end

  defp normalize_units_for_tts(text) do
    text
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*km\/h\b/i, "\\1キロ")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*cm\/s\b/i, "秒速\\1センチ")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*m\/s\b/i, "秒速\\1メートル")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*cm\b/i, "\\1センチ")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*mm\b/i, "\\1ミリ")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*km\b/i, "\\1キロ")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*m\b/i, "\\1メートル")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*(?:deg|°)/i, "\\1度")
    |> String.replace(~r/(\d+(?:\.\d+)?)\s*[%％]/u, "\\1パーセント")
  end

  @doc """
  Extracts `mood` and any already-completed sentence chunks from an in-progress
  streaming LLM JSON string so Zonos TTS synthesis can begin while the LLM is
  still generating subsequent sentences or `parameter` (MicroPython code).
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
  Pre-warms the speaker reference audio upload in the background so the Gradio `FileData`
  is cached in `:persistent_term` before the first TTS chunk starts.
  """
  def warm_speaker_audio_async(%Kitt{} = kitt) do
    if KittAgent.Requests.tts_provider() == "zonos" do
      Task.start(fn -> prepare_speaker_audio(kitt, false) end)
    end

    :ok
  end

  @doc """
  Starts background synthesis for completed sentence chunks in strict sequential order
  while the LLM is still streaming the remainder of the response.
  """
  def prefetch_chunks_async(%Kitt{} = kitt, mood, chunks)
      when is_binary(mood) and is_list(chunks) and chunks != [] do
    if KittAgent.Requests.tts_provider() == "zonos" do
      table = ensure_prefetch_table()
      now = System.monotonic_time(:millisecond)
      mood_key = normalize_mood_key(mood)

      chunks_with_keys =
        chunks
        |> Enum.map(fn chunk -> {chunk, {kitt.id, mood_key, chunk}} end)

      new_items =
        chunks_with_keys
        |> Enum.with_index()
        |> Enum.filter(fn {{_chunk, key}, _idx} ->
          :ets.insert_new(table, {key, :in_progress, now})
        end)

      if new_items != [] do
        lang_code = lang_to_code(kitt.lang)
        params = resolve_parameters(mood)

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

            case synthesize_single_chunk(chunk, params, lang_code, kitt) do
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

  def prepare_speaker_audio(%Kitt{} = kitt, force_refresh \\ false) do
    with path when is_binary(path) <- Kitts.resource_audio(kitt),
         {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(path) do
      cache_key = {__MODULE__, :speaker_audio, gradio_url(), path, mtime, size}

      case if(force_refresh, do: nil, else: :persistent_term.get(cache_key, nil)) do
        %{"path" => _} = cached ->
          cached

        _ ->
          try do
            with {:ok, remote_path} <- upload_file(path) do
              file_data = %{
                "path" => remote_path,
                "url" => "#{gradio_url()}/gradio_api/file=#{remote_path}",
                "orig_name" => Path.basename(path),
                "size" => size,
                "mime_type" => MIME.from_path(path),
                "is_stream" => false,
                "meta" => %{"_type" => "gradio.FileData"}
              }

              :persistent_term.put(cache_key, file_data)
              file_data
            else
              e ->
                Logger.error("TTS: Failed to upload speaker audio: #{inspect(e)}")
                nil
            end
          rescue
            e ->
              Logger.error("TTS: Failed to process speaker audio: #{inspect(e)}")
              nil
          end
      end
    else
      _ ->
        Logger.warning("TTS: Speaker audio file not found for: #{inspect(kitt)}")
        nil
    end
  end

  defp upload_file(local_path) do
    url = "#{gradio_url()}/gradio_api/upload"
    mime_type = MIME.from_path(local_path)

    try do
      part =
        Multipart.Part.file_field(local_path, "files")
        |> then(fn p ->
          %{p | headers: [{"Content-Type", mime_type} | p.headers]}
        end)

      multipart =
        Multipart.new()
        |> Multipart.add_part(part)

      content_type = Multipart.content_type(multipart, "multipart/form-data")
      content_length = Multipart.content_length(multipart)
      body = Multipart.body_binary(multipart)

      headers = [
        {"Content-Type", content_type},
        {"Content-Length", to_string(content_length)}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 200, body: [remote_path | _]}} ->
          {:ok, remote_path}

        {:ok, resp} ->
          {:error, "Upload failed with status #{resp.status}: #{inspect(resp.body)}"}

        {:error, reason} ->
          {:error, "Upload error: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "Upload exception: #{inspect(e)}"}
    end
  end

  defp call_gradio(text, params, lang_code, speaker_audio) do
    # API: generate_audio
    # Inputs: [Model, Text, Lang, SpeakerAudio, PrefixAudio, ...Emotions..., VQ, Fmax, Pitch, Rate, DNSMOS, Denoise, CFG, ...Sampling..., Seed, RandSeed, UncondKeys]

    Logger.debug("TTS Debug: Sending Payload with Model Type: #{@model_type}")

    payload = %{
      data: [
        # 3: Model Type
        @model_type,
        # 4: Text
        text,
        # 5: Language
        lang_code,
        # 9: Speaker Audio
        speaker_audio,
        # 7: Prefix Audio
        nil,
        # 48: Happiness
        params.happiness,
        # 49: Sadness
        params.sadness,
        # 50: Disgust
        params.disgust,
        # 51: Fear
        params.fear,
        # 54: Surprise
        params.surprise,
        # 55: Anger
        params.anger,
        # 56: Other
        params.other,
        # 57: Neutral
        params.neutral,
        # 17: VQ Score
        params.vq_score,
        # 16: Fmax
        params.fmax,
        # 18: Pitch Std
        params.pitch_std,
        # 19: Speaking Rate
        params.speaking_rate,
        # 15: DNSMOS
        params.dnsmos,
        # 10: Denoise
        false,
        # 23: CFG Scale
        params.cfg_scale,
        # 37: Top P
        0,
        # 38: Min K
        0,
        # 39: Min P
        0.05,
        # 31: Linear
        0.5,
        # 32: Confidence
        0.4,
        # 33: Quadratic
        0.0,
        # 24: Seed
        420,
        # 25: Randomize Seed
        true,
        # 44: Unconditional Keys
        ["emotion"]
      ]
    }

    case Req.post("#{gradio_url()}/gradio_api/call/generate_audio", json: payload) do
      {:ok, %{status: 200, body: %{"event_id" => event_id}}} ->
        wait_for_sse(event_id)

      {:ok, resp} ->
        {:error, "Gradio API error: #{inspect(resp.body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Parameter Resolution Helpers ---

  @doc """
  Resolves Zonos emotion and prosody parameters from the `mood` string.
  """
  def resolve_parameters(mood) do
    mood_keywords =
      (mood || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z\s]/, "")
      |> String.split()

    Enum.reduce(mood_keywords, @default_params, fn word, current_params ->
      case Map.get(@modifiers, word) do
        nil -> current_params
        mods -> merge_params(current_params, mods)
      end
    end)
    |> clamp_params()
  end

  defp merge_params(base, mods) do
    Enum.reduce(mods, base, fn {key, delta}, acc ->
      Map.update(acc, key, delta, &(&1 + delta))
    end)
  end

  defp clamp_params(params) do
    params
    |> Map.new(fn {k, v} ->
      new_v =
        cond do
          k in [:happiness, :sadness, :disgust, :fear, :surprise, :anger, :other, :neutral] ->
            max(0.0, min(1.0, v))

          k == :speaking_rate ->
            max(5.0, min(30.0, v))

          k == :pitch_std ->
            max(5.0, min(200.0, v))

          true ->
            v
        end

      {k, new_v}
    end)
  end

  defp log_mood_details(text, mood, params) do
    emotions =
      [:happiness, :sadness, :disgust, :fear, :surprise, :anger, :other, :neutral]
      |> Enum.map(fn k -> {k, params[k]} end)
      |> Enum.filter(fn {_, v} -> v > 0.1 end)
      |> Enum.map(fn {k, v} -> "#{k}:#{Float.round(v * 1.0, 2)}" end)
      |> Enum.join(", ")

    Logger.info(
      "TTS: '#{String.slice(text, 0, 15)}...' [Mood: #{mood}] -> Rate:#{params.speaking_rate}, Pitch:#{params.pitch_std}, Emo:[#{emotions}]"
    )
  end

  defp wait_for_sse(event_id) do
    url = "#{gradio_url()}/gradio_api/call/generate_audio/#{event_id}"

    result = Req.get!(url, into: [], receive_timeout: 60_000)
    body = Enum.join(result.body)

    if String.contains?(body, "event: complete") do
      parse_sse_data(body)
    else
      {:error, "TTS generation incomplete or timed out"}
    end
  end

  defp parse_sse_data(body) do
    case String.split(body, "event: complete") do
      [_, tail] ->
        case Regex.run(~r/data: (.*)\n/, tail) do
          [_, json_str] ->
            decode_gradio_response(json_str)

          _ ->
            Logger.debug("TTS Debug: No data line found in tail: #{inspect(tail)}")
            {:error, "Could not find data in SSE response"}
        end

      _ ->
        Logger.debug("TTS Debug: No complete event found in body: #{inspect(body)}")
        {:error, "No completion event found"}
    end
  end

  defp decode_gradio_response(json_str) do
    case Jason.decode(json_str) do
      {:ok, [audio_info | _]} when is_map(audio_info) ->
        raw_url = audio_info["url"]
        url = String.replace(raw_url, "/gradio_a/gradio_api/", "/gradio_api/")

        Logger.debug("TTS Debug: Got audio URL: #{url} (Original: #{raw_url})")
        {:ok, url}

      {:ok, %{"url" => raw_url}} ->
        url = String.replace(raw_url, "/gradio_a/gradio_api/", "/gradio_api/")
        {:ok, url}

      {:error, _} ->
        {:error, "Failed to decode JSON data"}
    end
  end

  def synthesize_chunks(chunks, params, lang_code, kitt, mood) do
    case synthesize_chunks(chunks, params, lang_code, kitt, mood, false) do
      {:ok, wav_binaries, _pushed_any} -> {:ok, wav_binaries}
      {:error, _} = err -> err
    end
  end

  def synthesize_chunks([], _params, _lang_code, _kitt, _mood, _stream_ws?) do
    {:error, "No speakable text chunks"}
  end

  def synthesize_chunks(chunks, params, lang_code, %Kitt{} = kitt, mood, stream_ws?) do
    table = ensure_prefetch_table()
    mood_key = normalize_mood_key(mood)
    total = length(chunks)
    keys = Enum.map(chunks, &{kitt.id, mood_key, &1})

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

            {:cont, {:ok, [wav_binary | acc], true}}

          {:ok, wav_binary, false} ->
            Logger.info("TTS: Using prefetched chunk [#{idx}/#{total}]: #{inspect(chunk)}")

            pushed_now =
              if stream_ws? do
                maybe_push_chunk_ws(wav_binary, kitt, mood, chunk, idx - 1, is_last)
              else
                false
              end

            {:cont, {:ok, [wav_binary | acc], pushed_acc or pushed_now}}

          :miss ->
            Logger.info("TTS: Generating chunk [#{idx}/#{total}]: #{inspect(chunk)}")

            case synthesize_single_chunk(chunk, params, lang_code, kitt) do
              {:ok, wav_binary} ->
                pushed_now =
                  if stream_ws? do
                    maybe_push_chunk_ws(wav_binary, kitt, mood, chunk, idx - 1, is_last)
                  else
                    false
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

  defp synthesize_single_chunk(chunk, params, lang_code, %Kitt{} = kitt) do
    speaker_audio = prepare_speaker_audio(kitt, false)

    case do_call_and_download(chunk, params, lang_code, speaker_audio) do
      {:ok, wav_binary} ->
        {:ok, wav_binary}

      {:error, _reason} when not is_nil(speaker_audio) ->
        Logger.info("TTS: Refreshing cached speaker audio and retrying chunk once...")
        fresh_speaker = prepare_speaker_audio(kitt, true)
        do_call_and_download(chunk, params, lang_code, fresh_speaker)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_call_and_download(chunk, params, lang_code, speaker_audio) do
    with {:ok, audio_url} <- call_gradio(chunk, params, lang_code, speaker_audio),
         {:ok, wav_binary} <- download_audio_binary(audio_url) do
      {:ok, wav_binary}
    end
  end

  defp normalize_mood_key(mood) do
    (mood || "default")
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp ensure_prefetch_table do
    table = :zonos_chunk_prefetch

    case :ets.whereis(table) do
      :undefined ->
        try do
          ets_opts =
            case Process.whereis(KittAgent.Supervisor) do
              pid when is_pid(pid) -> [:named_table, :public, :set, {:heir, pid, nil}]
              _ -> [:named_table, :public, :set]
            end

          :ets.new(table, ets_opts)
        rescue
          ArgumentError -> table
        end

      _tid ->
        prune_stale_prefetch_entries(table)
        table
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

  defp download_audio_binary(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, resp} ->
        {:error, "Download failed: #{resp.status}"}

      {:error, reason} ->
        {:error, "Download error: #{inspect(reason)}"}
    end
  end

  defp save_audio(wav_binary, %Kitt{} = kitt) when is_binary(wav_binary) do
    filename = "#{Ecto.UUID.generate()}.wav"
    local_rel_path = Kitts.path(kitt, filename)
    local_abs_path = Kitts.resource(kitt, filename)

    File.mkdir_p!(Path.dirname(local_abs_path))
    File.write!(local_abs_path, wav_binary)
    {:ok, local_rel_path}
  end

  @doc """
  Concatenates one or more RIFF WAVE binaries into a single canonical RIFF WAVE binary,
  inserting a short natural pause (`#{@inter_chunk_silence_sec}s` of digital silence) between sentence chunks.
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

  defp lang_to_code(lang) do
    case String.downcase(lang || "") do
      "japanese" -> "ja"
      "english" -> "en-us"
      "ja" -> "ja"
      "en" -> "en-us"
      _ -> "ja"
    end
  end

  def check_connection(url) do
    clean_url = String.trim_trailing(url || @gradio_default_url, "/")

    case Req.get(clean_url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        {:ok, "Connection successful"}

      {:ok, %{status: status}} ->
        {:error, "Connection failed. Status: #{status}"}

      {:error, exception} ->
        {:error, "Connection failed. Error: #{inspect(exception)}"}
    end
  end

  def gradio_url do
    (KittAgent.Configs.get_config("zonos_gradio_url", @gradio_default_url) || @gradio_default_url)
    |> String.trim_trailing("/")
  end
end
