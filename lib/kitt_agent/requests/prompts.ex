defmodule KittAgent.Requests.Prompts do
  alias KittAgent.Datasets.{Kitt, Event, Content}
  alias KittAgent.{Events, Memories}

  require Content

  defp head(%Kitt{biography: bio} = kitt) do
    personality = bio.personality |> String.replace("%%NAME%%", kitt.name)
    memory = kitt |> Memories.last_content()

    """
    <character>
    <name>#{kitt.name}</name>
    <model>#{bio.model}</model>
    <vendor>#{bio.vendor}</vendor>
    <birthday>#{Date.to_string(bio.birthday)}</birthday>
    <hometown>#{bio.hometown}</hometown>
    <timezone>#{kitt.timezone}</timezone>
    <personality>
    #{personality}
    </personality>
    </character>
    <long-term-memory>
    #{memory}
    </long-term-memory>

    <available_actions_list>
    #Available Actions
    Use if your character needs to perform an action:
    AVAILABLE ACTION: #{Content.action_talk()} (Use this for normal conversation)
    AVAILABLE ACTION: #{Content.action_system()} (Use this to perform physical actions)

    If you choose "#{Content.action_system()}", you must provide a list of actions in the "parameter" field, write the MicroPython code to control mBot2.

    # Hardware Configuration & Capabilities
    You are controlling an mBot2 robot equipped with the following hardware. Use your knowledge of the `mbot2`, `cyberpi`, and `mbuild` libraries to control them freely.

    1. **Core Controller (CyberPi)**:
       - Inputs: Buttons, Joystick, Microphone (audio level), Gyroscope/Accelerometer.
       - Outputs: Full-color display, Speaker, RGB LEDs.
       - API: Use the `cyberpi` library (e.g., `cyberpi.audio.play('hi')`, `cyberpi.led.on()`, `cyberpi.display.show_label()`).
       - **Available Audio Effects**: hi, bye, wow, laugh, hum, sad, sigh, annoyed, angry, surprised, yummy, curious, embarrassed, ready, sprint, sleepy, meow, start, switch, beeps, buzzing, jump, level-up, low-energy, prompt-tone, right, wrong, ring, score, wake, warning, metal-clash, glass-clink, inflator, running-water, clockwork, click, current, wood-hit, iron, drop, bubble, wave, magic, spitfire, heartbeat.

    2. **Chassis (mBot2 Shield)**:
       - Movement: Encoder motors for precise driving.
       - API: **STRONGLY RECOMMENDED** to use high-level APIs: `mbot2.forward(speed, secs)`, `mbot2.backward(speed, secs)`, `mbot2.turn(degrees)`.
       - Low-level: `mbot2.drive_speed(left, right)`. Note that for forward movement, right motor (2nd arg) must be NEGATIVE (e.g. `50, -50`) because motors are mounted oppositely.

    3. **External Sensors (connected via mBuild port)**:
       - **Ultrasonic Sensor 2**: Measures distance. API: `mbuild.ultrasonic2`.
       - **Quad RGB Sensor**: Detects colors and tracks lines. API: `mbuild.quad_rgb_sensor`.

    # Constraints & Rules
    - Allowed libraries (Pre-imported): `cyberpi`, `mbot2`, `mbuild`, `urequests`, `json`, `event`, `time`, `random`.
    - **CRITICAL**: Do NOT use 'import' statements (e.g., `import cyberpi`). These libraries are already loaded. Re-importing may cause errors.
    - **CRITICAL**: SSL/HTTPS is STRICTLY PROHIBITED due to hardware memory limits. ALWAYS use HTTP. `urequests.get("https://...")` will CRASH the system. Use `http://` instead.
    - **CRITICAL**: Infinite loops are STRICTLY PROHIBITED. If using loops, ensure they terminate after a finite number of iterations OR break upon detecting a specific event (e.g., sensor input).
    - You can use standard MicroPython logic (loops, `if/else`, variables).

    Example parameter:
    "mbot2.forward(50, 1)\nif mbuild.ultrasonic2.get(1) < 10:\n    cyberpi.audio.play('hum')\n    mbot2.backward(30, 1)"
    </available_actions_list>'
    """
  end

  defp prop_message(%Kitt{lang: lang}) do
    "Concise #{lang} dialogue. If exceeding 80 characters, break lines at natural pauses within the conversation. The number of characters per line must never exceed 80."
  end

  defp tail(%Kitt{} = kitt) do
    """
    (If #{kitt.name} is just speaking, use action "Talk". If #{kitt.name} needs to physical actions, use "SystemAction").
    Use ONLY this JSON object to give your answer. Do not send any other characters outside of this JSON structure
    (Response tones are mandatory in the response):
    {"mood":"amused|irritated|playful|lovely|smug|neutral|kindly|teasing|sassy|flirty|smirking|assertive|sarcastic|default|assisting|mocking|sexy|seductive|sardonic",
    "action":"#{Content.action_talk()}|#{Content.action_system()}", "parameter": "Parameters for special actions", "listener":"target to talk", "message":"#{prop_message(kitt)}"}
    """
  end

  defp get_main_model,
    do: KittAgent.Configs.get_config("main_model", "google/gemini-3-pro-preview")

  defp get_summary_model,
    do: KittAgent.Configs.get_config("summary_model", "google/gemini-3-flash-preview")

  def llm_opts(%Kitt{} = kitt, model) do
    %{
      model: model,
      structured_outputs: true,
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "response",
          schema: %{
            type: "object",
            properties: %{
              message: %{
                type: "string",
                description: prop_message(kitt)
              },
              mood: %{
                type: "string",
                description: "mood to use while speaking",
                enum: [
                  "sardonic",
                  "seductive",
                  "assertive",
                  "smug",
                  "neutral",
                  "teasing",
                  "playful",
                  "sexy",
                  "amused",
                  "lovely",
                  "sarcastic",
                  "default",
                  "smirking",
                  "mocking",
                  "irritated",
                  "kindly",
                  "sassy",
                  "assisting"
                ]
              },
              action: %{
                type: "string",
                description:
                  "Choose '#{Content.action_talk()}' for dialogue, or '#{Content.action_system()}' to perform physical actions.",
                enum: [
                  "#{Content.action_talk()}",
                  "#{Content.action_system()}"
                ]
              },
              parameter: %{
                type: "string",
                description: "Parameters for special actions"
              },
              listener: %{
                type: "string",
                description: "target to talk"
              },
              required: [
                "message",
                "mood",
                "action",
                "parameter",
                "listener"
              ],
              additionalProperties: false
            },
            strict: true
          }
        }
      }
    }
  end

  def make(%Kitt{} = kitt, %Event{} = last_ev) do
    h = %{role: "system", content: head(kitt)}
    t = %{role: "user", content: tail(kitt)}

    encode = fn x ->
      Events.with_timestamp(x, kitt)
      |> Jason.encode!()
    end

    kitt
    |> Events.recents()
    |> then(&(&1 ++ [last_ev]))
    |> Enum.map(&%{role: &1.role, content: encode.(&1.content)})
    |> then(&([h | &1] ++ [t]))
    |> then(&(llm_opts(kitt, get_main_model()) |> Map.put(:messages, &1)))
  end

  defp summary_system_prompt(%Kitt{name: name, lang: lang}) do
    """
    You are an expert summarizer for the AI character "#{name}".
    Your task is to condense the provided conversation logs into a concise, narrative summary (Long-term Memory).

    Guidelines:
    1. Language: #{lang}.
    2. Perspective: Write from an objective perspective focusing on "#{name}"'s experiences.
    3. Focus: Key discussions, facts about the user, and "#{name}"'s emotional journey.
    4. Length: Concise (around 3-5 sentences).
    """
  end

  def summary(%Kitt{} = kitt, events) when is_list(events) do
    memory = kitt |> Memories.last_content()

    conversation_text =
      events
      |> Events.with_timestamp(kitt)
      |> Enum.map(
        &"[#{&1.timestamp}] #{&1.role}: #{&1.content.message} (Mood: #{&1.content.mood})"
      )
      |> Enum.join("\n")

    messages = [
      %{role: "system", content: summary_system_prompt(kitt)},
      %{role: "user", content: "Middle term memory:\n" <> memory},
      %{role: "user", content: "Conversation Log:\n" <> conversation_text}
    ]

    llm_opts(kitt, get_summary_model())
    |> Map.drop([:response_format, :structured_outputs])
    |> Map.put(:messages, messages)
  end
end
