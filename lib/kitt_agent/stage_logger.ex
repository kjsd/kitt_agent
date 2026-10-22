defmodule KittAgent.StageLogger do
  @moduledoc """
  Stage monitor presentation logger for live demonstrations.
  Formats STT, LLM responses, MicroPython action code, TTS synthesis,
  and mBot2 execution status into clear, high-visibility blocks.
  """
  require Logger

  alias KittAgent.Datasets.Content
  require Content

  @cyan IO.ANSI.cyan()
  @bright_cyan IO.ANSI.bright() <> IO.ANSI.cyan()
  @bright_green IO.ANSI.bright() <> IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @bright_yellow IO.ANSI.bright() <> IO.ANSI.yellow()
  @bright_magenta IO.ANSI.bright() <> IO.ANSI.magenta()
  @bright_white IO.ANSI.bright() <> IO.ANSI.white()
  @faint IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @double_line String.duplicate("═", 62)
  @single_line String.duplicate("─", 62)

  def stt_started do
    Logger.info("""
    \n#{@bright_cyan}#{@double_line}#{@reset}
    🎤 #{@bright_cyan}[STEP 1/4] 音声を受信しました！音声認識 (Whisper STT) を実行中...#{@reset}
    """)
  end

  def stt_ignored(raw_text \\ "") do
    detail =
      if is_binary(raw_text) and String.trim(raw_text) != "" do
        " (ノイズ判定: \"#{String.trim(raw_text)}\")"
      else
        ""
      end

    Logger.info("""
    🚫 #{@faint}[STT] 有効な発話が検出されなかったためスキップしました#{detail}#{@reset}
    #{@faint}#{@double_line}#{@reset}
    """)
  end

  def llm_started(user_text) do
    Logger.info("""
    #{@cyan}#{@single_line}#{@reset}
    🗣️ #{@bright_yellow}[STEP 2/4] ユーザーの言葉 (認識結果):#{@reset}
       #{@bright_white}「 #{user_text} 」#{@reset}

    🧠 #{@bright_magenta}K.I.T.T. の頭脳 (LLM) が返答と制御プログラムを生成中...#{@reset}
    """)
  end

  def llm_completed(%Content{} = content) do
    mood = content.mood || "neutral"
    message = format_message(content.message || "")

    code_section =
      if content.action == Content.action_system() and is_binary(content.parameter) and
           String.trim(content.parameter) != "" do
        "\n\n" <> format_code_box(content.parameter)
      else
        ""
      end

    Logger.info("""
    #{@cyan}#{@single_line}#{@reset}
    💬 #{@bright_green}[STEP 3/4] K.I.T.T. の返答 (Mood: #{mood}):#{@reset}
    #{message}#{code_section}
    """)
  end

  def tts_started(provider_label) do
    Logger.info("""
    #{@cyan}#{@single_line}#{@reset}
    🔊 #{@bright_cyan}[STEP 4/4] 音声合成 (#{provider_label}) を生成中...#{@reset}
    """)
  end

  def tts_completed(duration_sec, is_system_action \\ false) do
    next_msg =
      if is_system_action do
        "キットが発話＆アクションを開始します！"
      else
        "キットが発話を開始します！"
      end

    Logger.info("""
    ✅ #{@bright_green}音声合成完了！ (#{duration_sec}秒) -> #{next_msg}#{@reset}
    #{@bright_cyan}#{@double_line}#{@reset}
    """)
  end

  def mbot_action_started(%Content{} = content) do
    if real_system_action?(content) do
      Logger.info(
        "🚀 #{@bright_yellow}[mBot2] アクションプログラムの実行を開始しました！#{@reset}"
      )
    end
  end

  def mbot_action_completed(%Content{} = content) do
    if real_system_action?(content) do
      Logger.info(
        "🏁 #{@bright_green}[mBot2] アクションプログラムの実行が完了しました！#{@reset}\n"
      )
    end
  end

  def mbot_action_failed(%Content{} = content) do
    if real_system_action?(content) do
      Logger.warning(
        "⚠️ #{@bright_yellow}[mBot2] アクションプログラムの実行中にエラーが発生しました#{@reset}\n"
      )
    end
  end

  defp real_system_action?(%Content{action: action, parameter: param}) do
    action == Content.action_system() and
      is_binary(param) and
      String.trim(param) != "" and
      not String.starts_with?(param, "talk_led(")
  end

  defp format_message(msg) do
    lines =
      msg
      |> String.trim()
      |> String.split("\n")

    case lines do
      [single] ->
        "   #{@bright_white}「 #{single} 」#{@reset}"

      multiple ->
        formatted =
          multiple
          |> Enum.with_index()
          |> Enum.map(fn {line, idx} ->
            prefix = if idx == 0, do: "   「 ", else: "      "
            suffix = if idx == length(multiple) - 1, do: " 」", else: ""
            "#{@bright_white}#{prefix}#{line}#{suffix}#{@reset}"
          end)
          |> Enum.join("\n")

        formatted
    end
  end

  defp format_code_box(code) do
    lines =
      code
      |> String.trim()
      |> String.split("\n")

    max_len =
      lines
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> 40 end)
      |> max(48)

    border = String.duplicate("─", max_len + 2)

    body =
      lines
      |> Enum.map_join("\n", fn line ->
        "   #{@yellow}│#{@reset} #{@bright_white}#{line}#{@reset}"
      end)

    """
    🤖 #{@bright_yellow}生成された mBot2 制御プログラム (MicroPython):#{@reset}
       #{@yellow}┌#{border}┐#{@reset}
    #{body}
       #{@yellow}└#{border}┘#{@reset}\
    """
  end
end
