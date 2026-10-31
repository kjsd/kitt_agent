defmodule KittAgent.Requests.ZonosGradioTest do
  use ExUnit.Case, async: true

  alias KittAgent.Requests.ZonosGradio
  alias KittAgent.Requests.OpenAITTS

  describe "resolve_parameters/1" do
    test "resolves emotion and prosody parameters for Prompts moods" do
      for mood <- ~w(happy excited playful amused lovely sad sigh angry irritated pout whisper teasing sassy flirty smug sarcastic assertive sardonic seductive smirking mocking kindly assisting) do
        params = ZonosGradio.resolve_parameters(mood)
        assert is_map(params)
        assert params.speaking_rate >= 5.0 and params.speaking_rate <= 30.0
        assert params.pitch_std >= 5.0 and params.pitch_std <= 200.0
      end

      happy_params = ZonosGradio.resolve_parameters("happy")
      assert happy_params.happiness > 0.5

      sad_params = ZonosGradio.resolve_parameters("sad")
      assert sad_params.sadness > 0.5
      assert sad_params.speaking_rate < 15.0

      angry_params = ZonosGradio.resolve_parameters("angry")
      assert angry_params.anger > 0.5
      assert angry_params.speaking_rate > 15.0
    end
  end

  describe "clean_text_for_tts/1" do
    test "strips inline bracket tags and applies TTS dictionary replacements" do
      cleaned =
        ZonosGradio.clean_text_for_tts(
          "[sarcastic] ここは東白川村です。[chuckles] mBot2が100cm前進します。"
        )

      refute String.contains?(cleaned, "[")
      assert String.contains?(cleaned, "ひがししらかわむら")
      assert String.contains?(cleaned, "エムボットツー")
      assert String.contains?(cleaned, "100センチ")
    end
  end

  describe "prepare_chunks/1 and split_text/1" do
    test "splits multi-sentence dialogue and normalizes sentence-final punctuation" do
      raw =
        "[sarcastic] マイケル、了解です。\nmBot2で東白川村へ向かいます！ うーん…準備はいいですか〜…"

      chunks = ZonosGradio.prepare_chunks(raw)

      assert chunks == [
               "マイケル、了解です。",
               "エムボットツーでひがししらかわむらへ向かいます！",
               "うーん、準備はいいですか。"
             ]
    end

    test "removes trailing ellipsis before question/exclamation marks" do
      chunks = ZonosGradio.prepare_chunks("今のドリフト、なかなか決まったでしょう…？ 任せてください〜！")

      assert chunks == [
               "今のドリフト、なかなか決まったでしょう？",
               "任せてください！"
             ]
    end
  end

  describe "concat_wav_binaries/1 and wav_duration_sec/1" do
    test "concatenates multiple RIFF WAVE chunks with inter-sentence silence and computes duration" do
      wav1 = build_test_wav(44_100, 1.0)
      wav2 = build_test_wav(44_100, 1.5)

      assert {:ok, combined} = ZonosGradio.concat_wav_binaries([wav1, wav2])
      assert <<"RIFF", _size::unsigned-little-32, "WAVE", _rest::binary>> = combined

      # 1.0s + 0.1s silence + 1.5s = 2.6s
      assert ZonosGradio.wav_duration_sec(combined) == 2.6
    end
  end

  describe "OpenAITTS.prepare_input_text/2" do
    test "prefixes [mood] once when mood is non-neutral and cleans text" do
      result = OpenAITTS.prepare_input_text("[laughter] 東白川村へようこそ。", "excited")
      assert result == "[excited] ひがししらかわむらへようこそ。"

      neutral = OpenAITTS.prepare_input_text("通常モードです。", "neutral")
      assert neutral == "通常モードです。"
    end
  end

  defp build_test_wav(sample_rate, seconds) do
    channels = 1
    bits_per_sample = 16
    block_align = div(channels * bits_per_sample, 8)
    byte_rate = sample_rate * block_align
    num_samples = trunc(sample_rate * seconds)
    data_body = :binary.copy(<<1, 0>>, num_samples)

    fmt_body =
      <<1::unsigned-little-16, channels::unsigned-little-16, sample_rate::unsigned-little-32,
        byte_rate::unsigned-little-32, block_align::unsigned-little-16,
        bits_per_sample::unsigned-little-16>>

    fmt_chunk = <<"fmt ", byte_size(fmt_body)::unsigned-little-32, fmt_body::binary>>
    data_chunk = <<"data", byte_size(data_body)::unsigned-little-32, data_body::binary>>
    riff_size = 4 + byte_size(fmt_chunk) + byte_size(data_chunk)

    <<"RIFF", riff_size::unsigned-little-32, "WAVE", fmt_chunk::binary, data_chunk::binary>>
  end
end
