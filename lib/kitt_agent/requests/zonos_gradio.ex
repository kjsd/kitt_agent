defmodule KittAgent.Requests.ZonosGradio do
  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Kitts, Events, Talks}

  require Logger
  require Content

  # Zonos-v0.1-hybrid
  @model_type "Zyphra/Zonos-v0.1-hybrid"
  @gradio_default_url "http://localhost:7860"

  def process(%Content{} = content, %Kitt{} = kitt) do
    try do
      lang_code = lang_to_code(kitt.lang)
      speaker_audio = prepare_speaker_audio(kitt)

      Logger.info("TTS: Generating audio for Content #{content.id} (Lang: #{lang_code})...")

      with {:ok, audio_url} <- call_gradio(content.message, content.mood, lang_code,
                speaker_audio),
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

  defp call_gradio(text, mood, lang_code, speaker_audio) do
    # API: generate_audio
    # Inputs: [Model, Text, Lang, SpeakerAudio, PrefixAudio, ...Emotions..., VQ, Fmax, Pitch, Rate, DNSMOS, Denoise, CFG, ...Sampling..., Seed, RandSeed, UncondKeys]
    
    emotions = resolve_emotions(mood)

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
        emotions.happiness,
        # 49: Sadness
        emotions.sadness,
        # 50: Disgust
        emotions.disgust,
        # 51: Fear
        emotions.fear,
        # 54: Surprise
        emotions.surprise,
        # 55: Anger
        emotions.anger,
        # 56: Other
        emotions.other,
        # 57: Neutral
        emotions.neutral,
        # 17: VQ Score
        0.78,
        # 16: Fmax
        24000,
        # 18: Pitch Std
        60.0,
        # 19: Speaking Rate
        15.0,
        # 15: DNSMOS
        5.0,
        # 10: Denoise
        false,
        # 23: CFG Scale
        2.5,
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

  defp resolve_emotions(mood) do
    # Default based on Nina's personality (Optimistic/Happy)
    base = %{
      happiness: 1.0,
      sadness: 0.05,
      disgust: 0.05,
      fear: 0.05,
      surprise: 0.05,
      anger: 0.05,
      other: 0.1,
      neutral: 0.2
    }

    mood = String.downcase(mood || "")

    cond do
      contains_any?(mood, ["sad", "cry", "grief", "sorrow", "depress"]) ->
        %{base | sadness: 1.0, happiness: 0.05}

      contains_any?(mood, ["angr", "mad", "rage", "furious"]) ->
        %{base | anger: 1.0, happiness: 0.05}

      contains_any?(mood, ["fear", "scar", "anxio", "terrified"]) ->
        %{base | fear: 1.0, happiness: 0.05}

      contains_any?(mood, ["surpris", "shock", "amaz"]) ->
        %{base | surprise: 1.0, happiness: 0.5}

      contains_any?(mood, ["disgust", "yuck"]) ->
        %{base | disgust: 1.0, happiness: 0.05}

      contains_any?(mood, ["neutral", "calm", "serious"]) ->
        %{base | neutral: 1.0, happiness: 0.1}

      true ->
        base
    end
  end

  defp contains_any?(text, keywords) do
    Enum.any?(keywords, &String.contains?(text, &1))
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
