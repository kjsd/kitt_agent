defmodule KittAgent.Voice.Zonos2Client do
  @moduledoc """
  Direct client for Zonos 2 Text-to-Speech server running on nina.local:1919 (FastAPI / Mini-SGLang).
  Supports 44.1kHz high-fidelity DAC audio, unified response-wide mood parameters,
  multi-chunk sentence concatenation, and speaker cloning using Kitt's reference audio.
  """

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Kitts, Events, Talks}
  alias KittAgent.Voice.EmotionState

  require Logger
  require Content

  @default_url "http://nina.local:1919"
  @default_speaker "nina2"

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


  @doc """
  Processes a Content item: extracts emotion tags, performs multi-chunk Zonos 2 synthesis,
  converts 44.1kHz float32 PCM to 16-bit WAV, saves to disk, and enqueues to Talks.Queue (and SystemActions.Queue if applicable).
  """
  def process(%Content{} = content, %Kitt{} = kitt) do
    try do
      base_url = zonos2_url()
      speaker_name = resolve_speaker_name(kitt)
      custom_audio_b64 = load_speaker_audio_base64(kitt)

      Logger.info(
        "Zonos2 TTS: Generating audio for Content #{content.id} (Speaker: #{speaker_name}, Custom Audio: #{is_binary(custom_audio_b64)}, Mood: #{inspect(content.mood)})..."
      )

      with {:ok, wav_binary} <- generate_audio_multi(content.message, content.mood, base_url, speaker_name, custom_audio_b64),
           {:ok, local_rel_path} <- save_audio(wav_binary, kitt),
           {:ok, updated_content} <-
             Events.update_content(
               content,
               %{audio_path: local_rel_path}
             ) do
        Talks.Queue.enqueue(kitt.id, updated_content)

        # If this is a SystemAction, enqueue it for the mBot2 AFTER the audio is ready
        if updated_content.action == KittAgent.Datasets.Content.action_system() do
          KittAgent.SystemActions.Queue.enqueue(kitt.id, updated_content)
        end

        updated_content
        |> Events.broadcast_change()

        Logger.info("Zonos2 TTS: Completed. Saved to #{local_rel_path} (#{byte_size(wav_binary)} bytes)")
        {:ok, updated_content}
      else
        error ->
          Logger.error("Zonos2 TTS: Failed. Reason: #{inspect(error)}")
          fallback_enqueue_system_action(content, kitt)
          {:error, error}
      end
    rescue
      e ->
        Logger.error("Zonos2 TTS: Exception: #{inspect(e)}")
        fallback_enqueue_system_action(content, kitt)
        {:error, e}
    end
  end

  defp fallback_enqueue_system_action(%Content{} = content, %Kitt{} = kitt) do
    if content.action == KittAgent.Datasets.Content.action_system() do
      Logger.warning("Zonos2 TTS: Enqueueing SystemAction despite TTS failure as a fallback.")
      KittAgent.SystemActions.Queue.enqueue(kitt.id, content)
    end
  end

  @doc """
  Generates audio binary (16-bit PCM WAV) for multi-sentence text using 3-layer emotion blending
  (Base `mood` + Carry Tag + One-Shot Tag) across sentence chunks.
  """
  def generate_audio_multi(raw_text, mood, base_url, speaker_name, custom_audio_b64) do
    chunks =
      split_text(raw_text || "")
      |> Enum.reject(&(&1 == ""))
      |> EmotionState.propagate_sentences()
      |> Enum.map(&extract_tags_and_params(&1, mood))
      |> Enum.filter(fn {chunk, _} ->
        String.match?(chunk, ~r/[\p{Hiragana}\p{Katakana}\p{Han}a-zA-Z0-9]/u)
      end)

    if chunks == [] do
      {:error, :unpronounceable_text}
    else
      # Generate float32 PCM for each chunk using its blended 3-layer emotion_params
      pcm_results =
        Enum.reduce_while(chunks, {:ok, []}, fn {chunk, emotion_params}, {:ok, acc} ->
          case call_zonos2(base_url, speaker_name, custom_audio_b64, chunk, emotion_params) do
            {:ok, pcm} -> {:cont, {:ok, [pcm | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case pcm_results do
        {:ok, pcm_list} ->
          # Seamlessly concatenate raw PCM buffers, then convert to 16-bit RIFF WAV
          combined_pcm = pcm_list |> Enum.reverse() |> IO.iodata_to_binary()
          wav_data = float32_to_pcm16_wav(combined_pcm, 44100, 1)
          {:ok, wav_data}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Splits text into chunks by punctuation marks for sentence-by-sentence processing.
  """
  def split_text(text) do
    Regex.split(~r/([。！？\n]+)/u, text, include_captures: true, trim: true)
    |> reconstruct_sentences([])
  end

  defp reconstruct_sentences([], acc), do: Enum.reverse(acc)
  defp reconstruct_sentences([text, punct | tail], acc) do
    reconstruct_sentences(tail, [text <> punct | acc])
  end
  defp reconstruct_sentences([text | tail], acc) do
    reconstruct_sentences(tail, [text | acc])
  end

  @doc """
  Resolves base emotion parameters from the response-level `mood` string via `EmotionState`.
  """
  def resolve_mood_params(mood) when is_binary(mood) do
    EmotionState.resolve_zonos2_params("", mood)
  end

  def resolve_mood_params(_), do: EmotionState.resolve_zonos2_params("", "neutral")

  @doc """
  Extracts clean text and resolves 3-layer blended emotion params (Base `mood` + Carry Tag + One-Shot Tag).
  """
  def extract_tags_and_params(text, mood \\ "neutral") do
    final_params = EmotionState.resolve_zonos2_params(text, mood)
    clean_text = clean_text_for_tts(text)
    {clean_text, final_params}
  end

  @doc """
  Cleans tags, Markdown, and non-pronounceable characters from text,
  and applies the DB-managed TTS pronunciation dictionary & unit normalizations.
  """
  def clean_text_for_tts(text) do
    text
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
  so Zonos 2 accurately pronounces place names (e.g. 東白川村) and English terms (e.g. mBot2, LED, RPM, cm).
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
  Converts 32-bit float Little Endian PCM binary to standard 16-bit signed integer RIFF WAVE (Format 1).
  Ensures full hardware and software compatibility across Android AudioTrack, browsers, and players.
  """
  def float32_to_pcm16_wav(float32_pcm, sample_rate \\ 44100, channels \\ 1) do
    pcm16 = float32_to_pcm16(float32_pcm, <<>>)
    data_size = byte_size(pcm16)
    bytes_per_sample = 2
    byte_rate = sample_rate * channels * bytes_per_sample
    block_align = channels * bytes_per_sample
    bits_per_sample = 16

    # RIFF WAVE header with format 1 (PCM Integer)
    header = <<
      "RIFF",
      (36 + data_size)::unsigned-little-32,
      "WAVE",
      "fmt ",
      16::unsigned-little-32,
      1::unsigned-little-16,            # AudioFormat: 1 = PCM (Integer)
      channels::unsigned-little-16,     # NumChannels: 1 = Mono
      sample_rate::unsigned-little-32,  # SampleRate: 44100
      byte_rate::unsigned-little-32,    # ByteRate: 44100 * 1 * 2 = 88200
      block_align::unsigned-little-16,  # BlockAlign: 1 * 2 = 2
      bits_per_sample::unsigned-little-16, # BitsPerSample: 16
      "data",
      data_size::unsigned-little-32
    >>

    header <> pcm16
  end

  defp float32_to_pcm16(<<>>, acc), do: acc
  defp float32_to_pcm16(<<s::float-little-32, rest::binary>>, acc) do
    c = max(-1.0, min(1.0, s))
    i = round(c * 32767.0)
    float32_to_pcm16(rest, <<acc::binary, i::signed-little-16>>)
  end

  defp call_zonos2(base_url, speaker_name, custom_audio_b64, text, emotion_params) do
    endpoint = "#{String.trim_trailing(base_url, "/")}/tts/generate"

    # Dynamic max_tokens based on text length to guarantee no infinite loop (Zonos 2 uses ~15-20 audio tokens per Japanese char)
    # A 50-char sentence needs ~800-1000 tokens (~10-12s). We provide a safe upper bound:
    max_tokens = min(2048, max(500, String.length(text) * 25 + 450))

    payload =
      %{
        "text" => text,
        "language" => "ja",
        "speaker_embedding_name" => speaker_name,
        "stream" => false,
        "max_tokens" => max_tokens
      }
      |> maybe_put_custom_audio(custom_audio_b64)
      |> Map.merge(emotion_params)

    Logger.info("🎙️ Requesting Zonos 2 TTS: \"#{String.slice(text, 0, 30)}...\" [speaker=#{speaker_name}]")

    case Req.post(endpoint, json: payload, receive_timeout: 45_000) do
      {:ok, %{status: 200, body: pcm_data}} when is_binary(pcm_data) and byte_size(pcm_data) > 0 ->
        {:ok, pcm_data}

      {:ok, %{status: status, body: body}} ->
        Logger.error("❌ Zonos 2 TTS HTTP Error #{status}: #{inspect(body)}")
        {:error, "Zonos 2 returned status #{status}"}

      {:error, reason} ->
        Logger.error("❌ Zonos 2 TTS Connection Failed: #{inspect(reason)}")
        {:error, "Zonos 2 connection failed: #{inspect(reason)}"}
    end
  end

  defp maybe_put_custom_audio(payload, b64) when is_binary(b64) and b64 != "" do
    Map.put(payload, "speaker_audio_base64", b64)
  end

  defp maybe_put_custom_audio(payload, _) do
    speaker_id =
      case payload["speaker_embedding_name"] do
        "nina" -> "default_e9a8401ead1dea46"
        "nina2" -> "default_e9a8401ead1dea46"
        other -> other
      end

    Map.put(payload, "speaker_embedding_id", speaker_id)
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

  @doc """
  Resolves speaker voice name. If kitt has an audio_path, uses its base name without extension.
  Otherwise falls back to config or default 'nina2'.
  """
  def resolve_speaker_name(%Kitt{audio_path: audio_path}) when is_binary(audio_path) and audio_path != "" do
    Path.basename(audio_path, Path.extname(audio_path))
  end

  def resolve_speaker_name(_kitt) do
    KittAgent.Configs.get_config("zonos2_default_speaker", @default_speaker)
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
  Returns the configured Zonos 2 API base URL.
  """
  def zonos2_url do
    KittAgent.Configs.get_config("zonos2_url", @default_url)
  end

  @doc """
  Checks connection to the configured Zonos 2 server.
  """
  def check_connection(url) do
    clean_url = String.trim_trailing(url || "", "/")

    case Req.get("#{clean_url}/openapi.json", receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        {:ok, "Connection successful (Zonos 2 FastAPI verified)"}

      {:ok, %{status: status}} ->
        case Req.get("#{clean_url}/docs", receive_timeout: 5_000) do
          {:ok, %{status: 200}} -> {:ok, "Connection successful (docs verified)"}
          _ -> {:error, "Connection failed. Status: #{status}"}
        end

      {:error, exception} ->
        {:error, "Connection failed. Error: #{inspect(exception)}"}
    end
  end
end
