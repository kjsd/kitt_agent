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

  describe "OpenAITTS.prepare_input_text/2" do
    test "prefixes [mood] once when mood is non-neutral and cleans text" do
      result = OpenAITTS.prepare_input_text("[laughter] 東白川村へようこそ。", "excited")
      assert result == "[excited] ひがししらかわむらへようこそ。"

      neutral = OpenAITTS.prepare_input_text("通常モードです。", "neutral")
      assert neutral == "通常モードです。"
    end
  end
end
