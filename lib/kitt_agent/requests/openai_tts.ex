defmodule KittAgent.Requests.OpenAITTS do
  @moduledoc """
  OpenAI-compatible Text-to-Speech (TTS) client.
  Calls standard POST /v1/audio/speech endpoint (supported by zonos2-openai-bridge, OpenAI, etc.).
  Supports dynamic speaker cloning by transmitting Kitt's reference audio via speaker_audio_base64.
  """

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.{Kitts, Events, Talks, StageLogger}
  alias KittAgent.Requests.ZonosGradio

  require Logger
  require Content

  @default_url "http://nina.local:8080/v1"
  @default_model "zonos2"
  @default_voice "nina2"

  @doc """
  Processes a Content item: prepares prompt with emotion tag, generates speech audio via
  OpenAI-compatible TTS API, saves WAV to disk, and enqueues to Talks.Queue (and SystemActions.Queue if applicable).
  """
  def process(%Content{} = content, %Kitt{} = kitt) do
    try do
      input_text = prepare_input_text(content.message, content.mood)
      voice = resolve_voice(kitt)
      model = KittAgent.Configs.get_config("openai_tts_model", @default_model)
      speaker_audio_b64 = load_speaker_audio_base64(kitt)

      StageLogger.tts_started("OpenAI TTS / #{model}")

      Logger.debug(
        "TTS: Generating audio for Content #{content.id} (Voice: #{voice}, Custom Audio: #{is_binary(speaker_audio_b64)}, Mood: #{inspect(content.mood)})..."
      )

      with {:ok, wav_binary} <- call_speech_api(input_text, voice, model, speaker_audio_b64),
           {:ok, local_rel_path} <- save_audio(wav_binary, kitt),
           {:ok, %Content{} = updated_content} <-
             Events.update_content(
               content,
               %{audio_path: local_rel_path}
             ) do
        duration_sec =
          max(byte_size(wav_binary) - 44, 0)
          |> Kernel./(88_200)
          |> Float.round(1)
          |> max(1.0)

        is_system_action = updated_content.action == KittAgent.Datasets.Content.action_system()

        Talks.Queue.enqueue(kitt.id, updated_content)

        # If this is a SystemAction, enqueue it for the mBot2 AFTER the audio is ready.
        # If it is a Talk action, enqueue a virtual SystemAction (`talk_led`) for mBot2's front LEDs.
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
        Logger.debug("TTS: Completed. Saved to #{local_rel_path}")
        {:ok, updated_content}
      else
        error ->
          Logger.error("TTS: Failed. Reason: #{inspect(error)}")
          fallback_enqueue_system_action(content, kitt)
          {:error, error}
      end
    rescue
      e ->
        Logger.error("TTS: Exception: #{inspect(e)}")
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
  Formats input text for OpenAI-compatible TTS (`openai-tts-bridge`) using mood-only control.
  Strips any stray inline bracket tags, applies TTS dictionary normalizations,
  and prefixes `[mood]` once for the entire message when `mood` is non-empty and not neutral/default.
  """
  def prepare_input_text(message, mood) do
    cleaned_text =
      (message || "")
      |> ZonosGradio.clean_text_for_tts()

    trimmed_mood = String.trim(mood || "")

    if trimmed_mood not in ["", "neutral", "normal", "default"] and cleaned_text != "" do
      "[#{trimmed_mood}] " <> cleaned_text
    else
      cleaned_text
    end
  end

  @doc """
  Resolves speaker voice name. If kitt has an audio_path, uses its base name without extension.
  Otherwise falls back to config or default 'nina2'.
  """
  def resolve_voice(%Kitt{audio_path: audio_path}) when is_binary(audio_path) and audio_path != "" do
    Path.basename(audio_path, Path.extname(audio_path))
  end

  def resolve_voice(_kitt) do
    KittAgent.Configs.get_config("openai_tts_default_voice", @default_voice)
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
      {:ok, %{status: 200, body: wav_binary}} when is_binary(wav_binary) and byte_size(wav_binary) > 0 ->
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
  Checks connection to the configured OpenAI TTS server by calling /models or /health.
  """
  def check_connection(url) do
    clean_url = String.trim_trailing(url || "", "/")

    case Req.get("#{clean_url}/models", receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        {:ok, "Connection successful (OpenAI API models endpoint verified)"}

      {:ok, %{status: status}} ->
        # Fallback to health endpoint if /models returns unexpected status
        case Req.get("#{clean_url}/health", receive_timeout: 5_000) do
          {:ok, %{status: 200}} -> {:ok, "Connection successful"}
          _ -> {:error, "Connection failed. Status: #{status}"}
        end

      {:error, exception} ->
        {:error, "Connection failed. Error: #{inspect(exception)}"}
    end
  end

  def openai_tts_url() do
    KittAgent.Configs.get_config("openai_tts_url", @default_url) || @default_url
  end
end
