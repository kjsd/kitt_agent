defmodule KittAgent.Voice.EmotionStateTest do
  use ExUnit.Case, async: true

  alias KittAgent.Voice.EmotionState
  alias KittAgent.Voice.Zonos2Client

  describe "classify_tag/1" do
    test "classifies Carry tags and One-Shot tags accurately" do
      assert {:carry, "whisper", _} = EmotionState.classify_tag("whispering")
      assert {:carry, "sarcastic", _} = EmotionState.classify_tag("sarcastically")
      assert {:carry, "teasing", _} = EmotionState.classify_tag("playfully")
      assert {:carry, "gently", _} = EmotionState.classify_tag("softly")
      assert {:carry, "calm", _} = EmotionState.classify_tag("calmly")

      assert {:oneshot, "laughter", _} = EmotionState.classify_tag("chuckles")
      assert {:oneshot, "sigh", _} = EmotionState.classify_tag("sighs")
      assert {:oneshot, "gasp", _} = EmotionState.classify_tag("gasps")
      assert {:oneshot, "clear throat", _} = EmotionState.classify_tag("clears throat")
    end
  end

  describe "propagate_sentences/1" do
    test "carries persistent tone across sentences until overridden or reset by [calm]" do
      sentences = [
        "[sarcastic] 成功確率はわずか2%です。",
        "[chuckle] もっとも、あなたには関係ない数字でしょうが。",
        "[calm] 準備は完了しています。"
      ]

      propagated = EmotionState.propagate_sentences(sentences)

      assert propagated == [
               "[sarcastic] 成功確率はわずか2%です。",
               "[sarcastic] [chuckle] もっとも、あなたには関係ない数字でしょうが。",
               "[calm] 準備は完了しています。"
             ]
    end

    test "does not carry one-shot tags to the next sentence" do
      sentences = [
        "[sigh] やれやれ、また無茶をしますね。",
        "センサーの数値は正常です。"
      ]

      propagated = EmotionState.propagate_sentences(sentences)

      assert propagated == [
               "[sigh] やれやれ、また無茶をしますね。",
               "センサーの数値は正常です。"
             ]
    end
  end

  describe "resolve_zonos2_params/2 and Zonos2Client.extract_tags_and_params/2" do
    test "supports all 25 Kitt moods including sarcastic, teasing, gently, assertive" do
      for mood <- [
            "happy",
            "excited",
            "playful",
            "amused",
            "lovely",
            "sad",
            "sigh",
            "angry",
            "irritated",
            "pout",
            "whisper",
            "teasing",
            "sassy",
            "flirty",
            "smug",
            "sarcastic",
            "assertive",
            "sardonic",
            "seductive",
            "smirking",
            "mocking",
            "kindly",
            "assisting"
          ] do
        params = EmotionState.resolve_zonos2_params("了解しました。", mood)
        assert params["emotion_enabled"] == true, "Expected emotion_enabled=true for mood=#{mood}"
      end

      for neutral_mood <- ["neutral", "default", ""] do
        params = EmotionState.resolve_zonos2_params("了解しました。", neutral_mood)
        assert params["emotion_enabled"] == false
        assert params["accurate_mode"] == false
        assert params["speaking_rate_enabled"] == true
        assert params["speaking_rate"] == 13.0
      end
    end

    test "determines Zonos 2 parameters solely from mood and strips stray inline tags cleanly" do
      {clean_text, params} =
        Zonos2Client.extract_tags_and_params(
          "[whisper] [chuckle] 内緒の話ですよ。",
          "sarcastic"
        )

      assert clean_text == "内緒の話ですよ。"
      assert params == Zonos2Client.resolve_mood_params("sarcastic")
      assert params["emotion_enabled"] == true
      assert is_map(params["emotion_sliders"])
      assert params["emotion_sliders"]["happy"] > 0.0
      assert params["emotion_sliders"]["angry"] > 0.0
      assert params["speaking_rate_enabled"] == true
      assert is_number(params["speaking_rate"])
    end

    test "ignores inline tags when mood is neutral or excited" do
      {clean_text, params} =
        Zonos2Client.extract_tags_and_params("[calm] 通常モードに戻ります。", "excited")

      assert clean_text == "通常モードに戻ります。"
      assert params == Zonos2Client.resolve_mood_params("excited")
      assert params["emotion_enabled"] == true
      assert params["accurate_mode"] == false
      assert params["speaking_rate_enabled"] == true
      assert params["speaking_rate"] == 14.18
    end
  end

  describe "OpenAITTS.prepare_input_text/2 integration" do
    test "decorates single and multi-sentence text using mood only and strips inline tags" do
      alias KittAgent.Requests.OpenAITTS

      assert OpenAITTS.prepare_input_text("Hello Kitt", nil) == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "happy") == "[happy] Hello Kitt"
      assert OpenAITTS.prepare_input_text("[sigh] Oh no", "sad") == "[sad] Oh no"

      multi = "[whisper] ここから先は内緒です。[chuckle] 誰にも言わないでくださいね。"

      assert OpenAITTS.prepare_input_text(multi, "neutral") ==
               "ここから先は内緒です。 誰にも言わないでくださいね。"

      assert OpenAITTS.prepare_input_text(multi, "whisper") ==
               "[whisper] ここから先は内緒です。 誰にも言わないでくださいね。"
    end
  end
end
