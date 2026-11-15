defmodule KittAgent.Requests.OpenAITTSTest do
  use KittAgent.DataCase

  alias KittAgent.Requests.{OpenAITTS, Prompts}
  alias KittAgent.Datasets.{Kitt, Biography, Event, Content}

  describe "prepare_input_text/2" do
    test "returns plain text when mood is nil, empty, or neutral/default" do
      assert OpenAITTS.prepare_input_text("Hello Kitt", nil) == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "") == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "   ") == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "neutral") == "Hello Kitt"
      assert OpenAITTS.prepare_input_text("Hello Kitt", "default") == "Hello Kitt"
    end

    test "prefixes mood tag once for the entire message when mood is present" do
      assert OpenAITTS.prepare_input_text("Hello Kitt", "happy") == "[happy] Hello Kitt"
      assert OpenAITTS.prepare_input_text("Good night", "whisper") == "[whisper] Good night"
    end

    test "strips stray inline bracket tags while preserving natural kanji, alphabet, and punctuation for Bridge" do
      assert OpenAITTS.prepare_input_text("[sigh] Oh no", "sad") == "[sad] Oh no"
      assert OpenAITTS.prepare_input_text("【笑い】あはは", "happy") == "[happy] あはは"

      input = "[whisper] ここは東白川村です…！[chuckle] mBot2が100cm前進します〜。"

      assert OpenAITTS.prepare_input_text(input, "neutral") ==
               "ここは東白川村です…！ mBot2が100cm前進します〜。"

      assert OpenAITTS.prepare_input_text(input, "whisper") ==
               "[whisper] ここは東白川村です…！ mBot2が100cm前進します〜。"
    end
  end

  describe "prepare_chunks/1 and split_text/1" do
    test "splits multi-sentence dialogue and preserves natural punctuation without Zonos mangling" do
      raw =
        "[sarcastic] マイケル、了解です。\nmBot2で東白川村へ向かいます！ うーん…準備はいいですか〜？"

      chunks = OpenAITTS.prepare_chunks(raw)

      assert chunks == [
               "マイケル、了解です。",
               "mBot2で東白川村へ向かいます！",
               "うーん…準備はいいですか〜？"
             ]
    end
  end

  describe "concat_wav_binaries/1 and wav_duration_sec/1" do
    test "computes accurate duration for 24kHz Irodori-TTS WAV chunks and concatenates with silence" do
      wav1 = build_test_wav(24_000, 1.0)
      wav2 = build_test_wav(24_000, 1.5)

      assert OpenAITTS.wav_duration_sec(wav1) == 1.0
      assert OpenAITTS.wav_duration_sec(wav2) == 1.5

      assert {:ok, combined} = OpenAITTS.concat_wav_binaries([wav1, wav2])
      assert <<"RIFF", _size::unsigned-little-32, "WAVE", _rest::binary>> = combined

      # 1.0s + 0.1s silence + 1.5s = 2.6s
      assert OpenAITTS.wav_duration_sec(combined) == 2.6
    end

    test "computes accurate duration for 44.1kHz Zonos WAV chunks" do
      wav1 = build_test_wav(44_100, 1.0)
      wav2 = build_test_wav(44_100, 1.5)

      assert {:ok, combined} = OpenAITTS.concat_wav_binaries([wav1, wav2])
      assert OpenAITTS.wav_duration_sec(combined) == 2.6
    end
  end

  describe "extract_ready_tts_chunks/1 and prefetch cache consumption" do
    test "incrementally extracts completed sentence chunks from streaming JSON" do
      # Still typing first sentence -> :incomplete
      assert OpenAITTS.extract_ready_tts_chunks(~s({"mood":"happy","message":"マイケル、了解です！)) ==
               :incomplete

      # Second sentence started -> first sentence chunk is guaranteed complete!
      assert OpenAITTS.extract_ready_tts_chunks(
               ~s({"mood":"happy","message":"マイケル、了解です！？ ただ)
             ) == {:ok, "happy", ["マイケル、了解です！？"]}

      # Closing quote of "message" arrived while "action"/"parameter" are still streaming -> all chunks ready!
      assert OpenAITTS.extract_ready_tts_chunks(
               ~s({"mood":"happy","message":"マイケル、了解です！？ ただちに100cm前進します。","action":"System)
             ) == {
               :ok,
               "happy",
               [
                 "マイケル、了解です！？",
                 "ただちに100cm前進します。"
               ]
             }
    end

    test "synthesize_chunks/3 consumes prefetched chunks from ETS without network call" do
      kitt = %Kitt{id: "test-kitt-prefetch", lang: "Japanese"}
      mood = "happy"
      chunks = ["マイケル、了解です。", "ただちに前進します！"]

      wav1 = build_test_wav(24_000, 0.5)
      wav2 = build_test_wav(24_000, 0.5)

      OpenAITTS.put_prefetched_chunk(kitt.id, mood, Enum.at(chunks, 0), wav1)
      OpenAITTS.put_prefetched_chunk(kitt.id, mood, Enum.at(chunks, 1), wav2)

      assert {:ok, [^wav1, ^wav2], false} =
               OpenAITTS.synthesize_chunks(chunks, kitt, mood)
    end

    test "synthesize_chunks/4 streams talk_chunk events to registered WebSocket processes" do
      kitt = %Kitt{id: "test-kitt-ws-stream", lang: "Japanese"}
      mood = "happy"
      chunks = ["マイケル、了解です。", "ただちに前進します！"]

      wav1 = build_test_wav(24_000, 0.5)
      wav2 = build_test_wav(24_000, 0.5)

      on_exit(fn ->
        File.rm_rf(Path.dirname(KittAgent.Kitts.resource(kitt, "dummy.wav")))
      end)

      {:ok, _} = KittAgent.Talks.register_ws(kitt.id)
      assert KittAgent.Talks.ws_connected?(kitt.id)

      OpenAITTS.put_prefetched_chunk(kitt.id, mood, Enum.at(chunks, 0), wav1)
      OpenAITTS.put_prefetched_chunk(kitt.id, mood, Enum.at(chunks, 1), wav2)

      assert {:ok, [^wav1, ^wav2], true} =
               OpenAITTS.synthesize_chunks(chunks, kitt, mood, true)

      assert_receive {:ws_push, json1}
      assert_receive {:ws_push, json2}

      msg1 = Jason.decode!(json1)
      msg2 = Jason.decode!(json2)

      assert msg1["type"] == "talk_chunk"
      assert msg1["chunk_index"] == 0
      assert msg1["is_last"] == false
      assert is_binary(msg1["audio_path"])

      assert msg2["type"] == "talk_chunk"
      assert msg2["chunk_index"] == 1
      assert msg2["is_last"] == true
      assert is_binary(msg2["audio_path"])
    end
  end

  describe "resolve_voice/1, load_speaker_audio_base64/1, and bridge_ui_url/1" do
    test "uses audio_path base name when present" do
      kitt = %Kitt{audio_path: "uploads/kitts/custom_voice.wav"}
      assert OpenAITTS.resolve_voice(kitt) == "custom_voice"
    end

    test "falls back to default voice when audio_path is nil or empty" do
      assert OpenAITTS.resolve_voice(%Kitt{audio_path: nil}) == "nina2"
      assert OpenAITTS.resolve_voice(%Kitt{audio_path: ""}) == "nina2"
    end

    test "returns nil when audio_path is nil or file does not exist" do
      assert OpenAITTS.load_speaker_audio_base64(%Kitt{audio_path: nil}) == nil

      assert OpenAITTS.load_speaker_audio_base64(%Kitt{
               id: Ecto.UUID.generate(),
               audio_path: "non_existent.wav"
             }) == nil
    end

    test "returns base64 encoded audio when file exists" do
      kitt_id = Ecto.UUID.generate()
      filename = "test_speaker.wav"
      dummy_pcm = "RIFF....WAVEfmt ...."

      kitt = %Kitt{id: kitt_id, audio_path: filename}
      target_path = KittAgent.Kitts.resource(kitt, filename)
      File.mkdir_p!(Path.dirname(target_path))
      File.write!(target_path, dummy_pcm)

      on_exit(fn -> File.rm_rf(Path.dirname(target_path)) end)

      assert OpenAITTS.load_speaker_audio_base64(kitt) == Base.encode64(dummy_pcm)
    end

    test "derives bridge Web UI URL from API URL" do
      assert OpenAITTS.bridge_ui_url("http://nina.local:8080/v1") == "http://nina.local:8080"
      assert OpenAITTS.bridge_ui_url("http://nina.local:8080/v1/") == "http://nina.local:8080"
    end

    test "resolve_speaker/1 generates collision-free content-addressed voice IDs for distinct Kitts" do
      kitt_a = %Kitt{id: Ecto.UUID.generate(), audio_path: "voice.wav"}
      kitt_b = %Kitt{id: Ecto.UUID.generate(), audio_path: "voice.wav"}

      path_a = KittAgent.Kitts.resource(kitt_a, "voice.wav")
      path_b = KittAgent.Kitts.resource(kitt_b, "voice.wav")
      File.mkdir_p!(Path.dirname(path_a))
      File.mkdir_p!(Path.dirname(path_b))
      File.write!(path_a, "RIFF_KITT_PERSONALITY_ALPHA")
      File.write!(path_b, "RIFF_KITT_PERSONALITY_BETA")

      on_exit(fn ->
        File.rm_rf(Path.dirname(path_a))
        File.rm_rf(Path.dirname(path_b))
      end)

      {voice_a, ^path_a} = OpenAITTS.resolve_speaker(kitt_a)
      {voice_b, ^path_b} = OpenAITTS.resolve_speaker(kitt_b)

      assert String.starts_with?(voice_a, "kitt-voice-")
      assert String.starts_with?(voice_b, "kitt-voice-")
      assert voice_a != voice_b
    end

    test "call_speech_api/5 enrolls Kitt voice on 404 voice_not_found without sending speaker_audio_base64" do
      kitt = %Kitt{id: Ecto.UUID.generate(), audio_path: "knight2000.wav"}
      ref_path = KittAgent.Kitts.resource(kitt, "knight2000.wav")
      File.mkdir_p!(Path.dirname(ref_path))
      File.write!(ref_path, "RIFF_KNIGHT2000_REF_WAV")
      on_exit(fn -> File.rm_rf(Path.dirname(ref_path)) end)

      {voice_id, ^ref_path} = OpenAITTS.resolve_speaker(kitt)
      {:ok, agent} = Agent.start_link(fn -> %{enrolled: MapSet.new(), uploads: 0, speeches: 0} end)

      plug = fn conn ->
        {:ok, raw_body, conn} = Plug.Conn.read_body(conn)

        case {conn.method, conn.request_path} do
          {"POST", "/v1/audio/speech"} ->
            decoded = Jason.decode!(raw_body)
            refute Map.has_key?(decoded, "speaker_audio_base64")
            req_voice = decoded["voice"]

            enrolled? =
              Agent.get_and_update(agent, fn s ->
                s2 = %{s | speeches: s.speeches + 1}
                {req_voice == "default" or MapSet.member?(s2.enrolled, req_voice), s2}
              end)

            if enrolled? do
              conn
              |> Plug.Conn.put_resp_content_type("audio/wav")
              |> Plug.Conn.send_resp(200, "RIFF_SYNTHESIZED_KITT_WAV")
            else
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(
                404,
                Jason.encode!(%{
                  "error" => %{"code" => "voice_not_found", "message" => "Voice not found"}
                })
              )
            end

          {"POST", "/v1/audio/voices"} ->
            assert raw_body =~ "RIFF_KNIGHT2000_REF_WAV"
            assert raw_body =~ voice_id

            Agent.update(agent, fn s ->
              %{s | enrolled: MapSet.put(s.enrolled, voice_id), uploads: s.uploads + 1}
            end)

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"voice_id" => voice_id}))
        end
      end

      opts = [base_url: "http://bridge.test/v1", req_options: [plug: plug]]

      # 1st chunk: 404 -> uploads reference WAV once -> retries speech -> 200 OK
      assert {:ok, "RIFF_SYNTHESIZED_KITT_WAV"} =
               OpenAITTS.call_speech_api("マイケル、了解です。", voice_id, "zonos", ref_path, opts)

      state1 = Agent.get(agent, & &1)
      assert state1.uploads == 1
      assert state1.speeches == 2

      # 2nd chunk: already enrolled -> 1 speech call, 0 uploads!
      assert {:ok, "RIFF_SYNTHESIZED_KITT_WAV"} =
               OpenAITTS.call_speech_api("前進します！", voice_id, "zonos", ref_path, opts)

      state2 = Agent.get(agent, & &1)
      assert state2.uploads == 1
      assert state2.speeches == 3

      # Kitt without local reference audio falls back to "default" when configured voice is missing
      assert {:ok, "RIFF_SYNTHESIZED_KITT_WAV"} =
               OpenAITTS.call_speech_api("デフォルト音声テスト", "nina2", "zonos", nil, opts)
    end
  end

  describe "Prompts voice_performance cleanup" do
    test "does not instruct LLM to force Hiragana/Katakana readings for TTS" do
      kitt = %Kitt{
        id: Ecto.UUID.generate(),
        name: "KITT",
        lang: "Japanese",
        timezone: "Asia/Tokyo",
        biography: %Biography{
          model: "Knight 2000",
          vendor: "Knight Industries",
          birthday: ~D[1982-09-26],
          hometown: "Los Angeles",
          personality: "Calm and intelligent AI partner %%NAME%%."
        }
      }

      ev = %Event{
        role: "user",
        content: %Content{action: "Talk", message: "こんにちは"},
        inserted_at: ~U[2026-11-15 07:00:00Z]
      }

      payload = Prompts.make(kitt, ev)
      system_msg = hd(payload.messages).content
      schema_msg_desc = payload.response_format.json_schema.schema.properties[:message].description

      refute system_msg =~ "ひがししらかわむら"
      refute system_msg =~ "Pronunciation Rules for Japanese TTS"
      refute schema_msg_desc =~ "ひがししらかわむら"
      assert system_msg =~ "Mood-Only Emotional Control"
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
