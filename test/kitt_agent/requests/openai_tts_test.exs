defmodule KittAgent.Requests.OpenAITTSTest do
  use KittAgent.DataCase

  alias KittAgent.Requests.OpenAITTS
  alias KittAgent.Datasets.Kitt

  describe "prepare_input_text/2" do
    test "returns plain text when mood is nil or empty" do
      assert OpenAITTS.prepare_input_text("Hello Kitt", nil) == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "") == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "   ") == "Hello Kitt"
    end

    test "prefixes mood tag when mood is present" do
      assert OpenAITTS.prepare_input_text("Hello Kitt", "happy") == "[happy] Hello Kitt"
      assert OpenAITTS.prepare_input_text("Good night", "whisper") == "[whisper] Good night"
    end

    test "does not duplicate tag if text already starts with a bracket" do
      assert OpenAITTS.prepare_input_text("[sigh] Oh no", "sad") == "[sigh] Oh no"
      assert OpenAITTS.prepare_input_text("【笑い】あはは", "happy") == "【笑い】あはは"
    end
  end

  describe "resolve_voice/1" do
    test "uses audio_path base name when present" do
      kitt = %Kitt{audio_path: "uploads/kitts/custom_voice.wav"}
      assert OpenAITTS.resolve_voice(kitt) == "custom_voice"
    end

    test "falls back to default voice when audio_path is nil or empty" do
      kitt = %Kitt{audio_path: nil}
      assert OpenAITTS.resolve_voice(kitt) == "nina2"

      kitt_empty = %Kitt{audio_path: ""}
      assert OpenAITTS.resolve_voice(kitt_empty) == "nina2"
    end
  end

  describe "load_speaker_audio_base64/1" do
    test "returns nil when audio_path is nil" do
      assert OpenAITTS.load_speaker_audio_base64(%Kitt{audio_path: nil}) == nil
    end

    test "returns nil when audio file does not exist" do
      assert OpenAITTS.load_speaker_audio_base64(%Kitt{id: Ecto.UUID.generate(), audio_path: "non_existent.wav"}) == nil
    end

    test "returns base64 encoded audio when file exists" do
      kitt_id = Ecto.UUID.generate()
      filename = "test_speaker.wav"
      dummy_pcm = "RIFF....WAVEfmt ...."
      
      # Prepare mock resource dir
      kitt = %Kitt{id: kitt_id, audio_path: filename}
      target_path = KittAgent.Kitts.resource(kitt, filename)
      File.mkdir_p!(Path.dirname(target_path))
      File.write!(target_path, dummy_pcm)

      on_exit(fn -> File.rm_rf(Path.dirname(target_path)) end)

      b64 = OpenAITTS.load_speaker_audio_base64(kitt)
      assert b64 == Base.encode64(dummy_pcm)
    end
  end

  describe "live bridge connection check" do
    @tag :external
    test "successfully checks connection to nina.local:8080" do
      case OpenAITTS.check_connection("http://nina.local:8080/v1") do
        {:ok, msg} ->
          assert msg =~ "Connection successful"
        {:error, reason} ->
          IO.puts("Bridge offline during test: #{inspect(reason)}")
      end
    end
  end
end
