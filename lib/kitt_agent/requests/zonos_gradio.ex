defmodule KittAgent.Requests.ZonosGradio do
  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Kitts, Events, Talks}

  require Logger
  require Content

  # Zonos-v0.1-hybrid
  @model_type "Zyphra/Zonos-v0.1-hybrid"
  @gradio_default_url "http://localhost:7860"

  # --- Default Parameters (Ported from ComfyUI Client) ---
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
    speaking_rate: 15.0, # Characters per second (approx)
    pitch_std: 45.0,     # Pitch standard deviation (Intonation)
    vq_score: 0.78,
    fmax: 24000,
    dnsmos: 5.0,
    cfg_scale: 2.5
  }

  # --- Keyword Modifiers (Ported from ComfyUI Client) ---
  @modifiers %{
    # Basic Emotions
    "happy" => %{happiness: 0.8, pitch_std: 10.0},
    "joy" => %{happiness: 0.8, pitch_std: 15.0},
    "sad" => %{sadness: 0.9, speaking_rate: -2.0, pitch_std: -20.0},
    "cry" => %{sadness: 1.0, speaking_rate: -3.0, pitch_std: -10.0},
    "angry" => %{anger: 0.9, speaking_rate: 3.0, pitch_std: 30.0},
    "mad" => %{anger: 0.9, speaking_rate: 4.0, pitch_std: 40.0},
    "fear" => %{fear: 0.9, speaking_rate: 2.0, pitch_std: 10.0},
    "scared" => %{fear: 0.9, speaking_rate: 1.0},
    "surprise" => %{surprise: 0.9, pitch_std: 15.0},
    "shock" => %{surprise: 1.0, speaking_rate: -2.0},
    "disgust" => %{disgust: 0.9, speaking_rate: -3.0},

    # Nuance & Style
    "excited" => %{happiness: 0.5, surprise: 0.3, speaking_rate: 3.0, pitch_std: 20.0},
    "energetic" => %{happiness: 0.4, speaking_rate: 4.0, pitch_std: 20.0},
    "relaxed" => %{neutral: 0.5, happiness: 0.2, speaking_rate: -1.0, pitch_std: -10.0},
    "calm" => %{neutral: 0.6, speaking_rate: -2.0, pitch_std: -15.0},
    "serious" => %{neutral: 0.8, sadness: 0.1, speaking_rate: -1.0, pitch_std: -25.0},

    # Romance / Intimacy (If applicable to Kitt?)
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
    "flat" => %{pitch_std: -30.0}, # Monotone
    "dynamic" => %{pitch_std: 30.0} # Expressive
  }

  def process(%Content{} = content, %Kitt{} = kitt) do
    try do
      lang_code = lang_to_code(kitt.lang)
      speaker_audio = prepare_speaker_audio(kitt)

      # Resolve Zonos parameters based on mood
      params = resolve_parameters(content.mood)
      log_mood_details(content.message, content.mood, params)

      Logger.info("TTS: Generating audio for Content #{content.id} (Lang: #{lang_code})...")

      with {:ok, audio_url} <- call_gradio(content.message, params, lang_code, speaker_audio),
           {:ok, local_path} <- download_audio(audio_url, kitt),
           {:ok, updated_content} <- Events.update_content(content,
             %{audio_path: local_path}) do

        Talks.Queue.enqueue(kitt.id, updated_content)

        updated_content
        |> Events.broadcast_change()

        Logger.info("TTS: Completed. Saved to #{local_path}")
      else
        error ->
          Logger.error("TTS: Failed. Reason: #{inspect(error)}")
      end
    rescue
      e ->
        Logger.error("TTS: Exception: #{inspect(e)}")
    end
  end

  # ... (prepare_speaker_audio and upload_file remain the same) ...
  defp prepare_speaker_audio(%Kitt{} = kitt) do
    with path when is_binary(path) <- Kitts.resource_audio(kitt),
         true <- File.exists?(path) do
      try do
        with {:ok, remote_path} <- upload_file(path) do
          # Return as FileData object pointing to the uploaded file on Gradio server
          %{
            "path" => remote_path,
            "url" => "#{gradio_url()}/gradio_api/file=#{remote_path}",
            "orig_name" => Path.basename(path),
            "size" => File.stat!(path).size,
            "mime_type" => MIME.from_path(path),
            "is_stream" => false,
            "meta" => %{"_type" => "gradio.FileData"}
          }
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
      # Create a new multipart request
      # Use file_field to create a part for the file
      part =
        Multipart.Part.file_field(local_path, "files")
        |> then(fn p ->
          # Ensure content type is set
          %{p | headers: [{"Content-Type", mime_type} | p.headers]}
        end)

      multipart =
        Multipart.new()
        |> Multipart.add_part(part)

      content_type = Multipart.content_type(multipart, "multipart/form-data")
      content_length = Multipart.content_length(multipart)

      # Convert multipart struct to a binary body
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
        # 9: Speaker Audio (Reverted order)
        speaker_audio,
        # 7: Prefix Audio (Reverted order)
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
        0,
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

    # 1. Initiate Call
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

  defp resolve_parameters(mood) do
    mood_keywords =
      (mood || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z\s]/, "") # Remove punctuation
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
            max(5.0, min(30.0, v)) # Prevent too slow/fast
          k == :pitch_std ->
            max(5.0, min(200.0, v)) # Prevent crazy pitch
          true -> v
        end
      {k, new_v}
    end)
  end

  defp log_mood_details(text, mood, params) do
    emotions =
      [:happiness, :sadness, :disgust, :fear, :surprise, :anger, :other, :neutral]
      |> Enum.map(fn k -> {k, params[k]} end)
      |> Enum.filter(fn {_, v} -> v > 0.1 end) # Only show significant ones
      |> Enum.map(fn {k, v} -> "#{k}:#{Float.round(v, 2)}" end)
      |> Enum.join(", ")

    Logger.info("TTS: '#{String.slice(text, 0, 15)}...' [Mood: #{mood}] -> Rate:#{params.speaking_rate}, Pitch:#{params.pitch_std}, Emo:[#{emotions}]")
  end


  defp wait_for_sse(event_id) do
    url = "#{gradio_url()}/gradio_api/call/generate_audio/#{event_id}"

    # Simple SSE parser: gather lines until we find the data
    # Note: This is a blocking call, which is fine inside handle_cast for now.

    result = Req.get!(url, into: [], receive_timeout: 60_000)

    # Concatenate all chunks
    body = Enum.join(result.body)

    # Parse SSE messages
    # We look for `event: complete` followed by `data: [...]`

    if String.contains?(body, "event: complete") do
      parse_sse_data(body)
    else
      {:error, "TTS generation incomplete or timed out"}
    end
  end

  defp parse_sse_data(body) do
    # Regex to find the data line associated with completion. 
    # Usually format is:
    # event: complete
    # data: [...] 

    # We split by "event: complete" and take the part after it.
    case String.split(body, "event: complete") do
      [_, tail] ->
        # Now find "data: " line in tail
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
      {:ok, [audio_info, _seed]} ->
        # audio_info is like: %{"path" => "...", "url" => "...", ...}
        # The URL from Gradio might be relative or absolute.
        # API info says: "url": "http://ai.local:7860/gradio_api/file=/tmp/..."
        raw_url = audio_info["url"]
        # Fix potential malformed URL from Zonos (e.g. double prefix)
        url = String.replace(raw_url, "/gradio_a/gradio_api/", "/gradio_api/")

        Logger.debug("TTS Debug: Got audio URL: #{url} (Original: #{raw_url})")
        {:ok, url}

      {:error, _} ->
        {:error, "Failed to decode JSON data"}
    end
  end

  defp download_audio(url, %Kitt{} = kitt) do
    filename = "#{Ecto.UUID.generate()}.wav"
    local_rel_path = Kitts.path(kitt, filename)
    local_abs_path = Kitts.resource(kitt, filename)

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        File.write!(local_abs_path, body)
        {:ok, local_rel_path}

      {:ok, resp} ->
        {:error, "Download failed: #{resp.status}"}

      {:error, reason} ->
        {:error, "Download error: #{inspect(reason)}"}
    end
  end

  defp lang_to_code(lang) do
    case String.downcase(lang || "") do
      "japanese" -> "ja"
      "english" -> "en-us"
      "ja" -> "ja"
      "en" -> "en-us"
      # Default fallback
      _ -> "ja"
    end
  end

  def check_connection(url) do
    # Simple GET request to the root URL
    case Req.get(url) do
      {:ok, %{status: 200}} ->
        {:ok, "Connection successful"}

      {:ok, %{status: status}} ->
        {:error, "Connection failed. Status: #{status}"}

      {:error, exception} ->
        {:error, "Connection failed. Error: #{inspect(exception)}"}
    end
  end

  defp gradio_url(),
    do: KittAgent.Configs.get_config("zonos_gradio_url", @gradio_default_url)
end
