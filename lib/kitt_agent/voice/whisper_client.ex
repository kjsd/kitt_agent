defmodule KittAgent.Voice.WhisperClient do
  @moduledoc """
  Client for OpenAI Whisper and compatible STT (Speech-to-Text) API endpoints.
  """
  require Logger

  @default_url "https://api.openai.com/v1/audio/transcriptions"
  @default_model "whisper-1"
  @default_lang "ja"

  @common_hallucinations [
    "ご視聴ありがとうございました",
    "チャンネル登録",
    "高評価",
    "おやすみなさい",
    "ご覧いただき",
    "最後までご視聴",
    "Thank you for watching",
    "Subtitles by",
    "Translated by"
  ]

  def whisper_url do
    KittAgent.Configs.get_config("stt_url") ||
      Application.get_env(:kitt_agent, :whisper_url) ||
      @default_url
  end

  def api_key do
    KittAgent.Configs.get_config("stt_key") ||
      KittAgent.Configs.get_config("api_key") ||
      Application.get_env(:kitt_agent, :openai_key) ||
      System.get_env("OPENAI_API_KEY")
  end

  def model do
    KittAgent.Configs.get_config("stt_model") || @default_model
  end

  def language do
    KittAgent.Configs.get_config("stt_lang") || @default_lang
  end

  @doc """
  Transcribes an audio source. Accepts:
  - `%Plug.Upload{path: path, filename: filename}`
  - file path as string (e.g. "/path/to/audio.wav")
  - raw audio binary (will be saved to a temp file)
  """
  def transcribe(audio_source, opts \\ [])

  def transcribe(%{path: path, filename: filename}, opts) when is_binary(path) do
    do_transcribe(path, filename, opts)
  end

  def transcribe(path, opts) when is_binary(path) and byte_size(path) < 1024 do
    if File.exists?(path) do
      filename = Path.basename(path)
      do_transcribe(path, filename, opts)
    else
      # Not an existing file path, treat as raw binary
      transcribe_binary(path, opts)
    end
  end

  def transcribe(audio_binary, opts) when is_binary(audio_binary) do
    transcribe_binary(audio_binary, opts)
  end

  defp transcribe_binary(audio_binary, opts) do
    temp_dir = System.tmp_dir!()
    ext = Keyword.get(opts, :ext, "wav")
    temp_path = Path.join(temp_dir, "kitt_talk_#{:os.system_time(:millisecond)}.#{ext}")
    File.write!(temp_path, audio_binary)

    try do
      do_transcribe(temp_path, Path.basename(temp_path), opts)
    after
      File.rm(temp_path)
    end
  end

  defp do_transcribe(file_path, filename, opts) do
    target_url = Keyword.get(opts, :url, whisper_url())
    target_key = Keyword.get(opts, :key, api_key())
    target_model = Keyword.get(opts, :model, model())
    target_lang = Keyword.get(opts, :lang, language())

    mime_type =
      case Path.extname(filename) |> String.downcase() do
        ".wav" -> "audio/wav"
        ".mp3" -> "audio/mpeg"
        ".m4a" -> "audio/m4a"
        ".webm" -> "audio/webm"
        ".ogg" -> "audio/ogg"
        _ -> "application/octet-stream"
      end

    multipart =
      Multipart.new()
      |> Multipart.add_part(
        Multipart.Part.file_field(file_path, "file")
        |> Map.update!(:headers, &[{"Content-Type", mime_type} | &1])
      )
      |> Multipart.add_part(Multipart.Part.text_field(target_model, "model"))
      |> Multipart.add_part(Multipart.Part.text_field(target_lang, "language"))

    content_type = Multipart.content_type(multipart, "multipart/form-data")
    body = Multipart.body_binary(multipart)

    headers =
      [{"Content-Type", content_type}] ++
        if target_key && target_key != "" do
          [{"Authorization", "Bearer #{target_key}"}]
        else
          []
        end

    Logger.info("🎤 STT Request to #{target_url} (model: #{target_model}, file: #{filename})")

    case Req.post(target_url, body: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        clean_text = filter_hallucination(text)
        Logger.info("🎤 STT Result: \"#{text}\" -> Filtered: \"#{clean_text}\"")
        {:ok, clean_text}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("❌ STT API Error (#{status}): #{inspect(resp_body)}")
        {:error, "STT API returned status #{status}: #{inspect(resp_body)}"}

      {:error, reason} ->
        Logger.error("❌ STT Network Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def filter_hallucination(nil), do: ""

  def filter_hallucination(text) do
    trimmed = String.trim(text)

    is_hallucination =
      Enum.any?(@common_hallucinations, fn h ->
        String.contains?(trimmed, h)
      end)

    is_garbage =
      trimmed == "" or
        String.match?(trimmed, ~r/^[、。．？！…\s]+$/)

    if is_hallucination or is_garbage do
      unless trimmed == "" do
        Logger.info("🚫 STT Hallucination/Garbage filtered: [#{trimmed}]")
      end

      ""
    else
      trimmed
    end
  end

  @doc """
  Verifies the connection to the STT API.
  """
  def check_connection(url, key) do
    if is_nil(url) or url == "" do
      {:error, "STT URL is required"}
    else
      headers =
        if key && key != "" do
          [{"Authorization", "Bearer #{key}"}]
        else
          []
        end

      # Attempt a quick check (either GET models or options)
      base_url =
        if String.ends_with?(url, "/audio/transcriptions") do
          String.replace_trailing(url, "/audio/transcriptions", "/models")
        else
          url
        end

      case Req.get(base_url, headers: headers, receive_timeout: 10_000) do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok, "Connected successfully (Status: #{status})"}

        {:ok, %{status: 401}} ->
          {:error, "Authentication failed (401 Unauthorized). Check API Key."}

        {:ok, %{status: status}} ->
          {:ok, "Server responded with status #{status}"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end
  end
end
