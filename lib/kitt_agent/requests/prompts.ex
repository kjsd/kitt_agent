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
       - Outputs: RGB LEDs.
         - API: Use the `cyberpi` library (e.g., `cyberpi.led.on(r, g, b)`, `cyberpi.led.off('all')`, `cyberpi.console.println("msg")`).
         - **CRITICAL HARDWARE BAN**: You must NEVER use `cyberpi.audio` (e.g., `play()`) or `cyberpi.display` (e.g., `show_label()`). Using these will cause an immediate and unrecoverable system crash due to hardware memory limits and Wi-Fi interrupt conflicts. If you want to show text, ALWAYS use `cyberpi.console.println()`. If you want to stop the LED, ALWAYS pass 'all' like `cyberpi.led.off('all')`.

    2. **Chassis (mBot2 Shield)**:
         - Movement: Encoder motors for precise driving.
         - API: **STRONGLY RECOMMENDED** to use high-level APIs: `mbot2.forward(speed, secs)`, `mbot2.backward(speed, secs)`, `mbot2.turn(degrees)`.
           - **CRITICAL**: For `mbot2.turn(degrees)`, POSITIVE degrees turn RIGHT, NEGATIVE degrees turn LEFT. (e.g., `mbot2.turn(-90)` turns 90 degrees LEFT).
         - Low-level: `mbot2.drive_speed(left, right)`. Note that for forward movement, right motor (2nd arg) must be NEGATIVE (e.g. `50, -50`) because motors are mounted oppositely.
         
      3. **External Sensors (connected via mBuild port)**:
       - **Ultrasonic Sensor 2**: Measures distance. API: `mbuild.ultrasonic2`.
       - **Quad RGB Sensor**: Detects colors and tracks lines. API: `mbuild.quad_rgb_sensor`.
         - `get_line_sta(index)`: Returns an integer (0-15) representing the status of 4 sensors (L2, L1, R1, R2).
           - L2(Bit3/8), L1(Bit2/4), R1(Bit1/2), R2(Bit0/1). 1=Black(Line), 0=White(Background).
           - e.g., 6 (0110) means L1 and R1 are on the line (Center).
           - e.g., 0 (0000) means no line detected. 15 (1111) means all sensors are on black (Intersection/Crossroad).
         - `get_offset_track(index)`: Returns deviation from line center (-100 to 100). Useful for PID control.

    # Constraints & Rules
    - Allowed libraries (Pre-imported): `cyberpi`, `mbot2`, `mbuild`, `urequests`, `json`, `event`, `time`, `random`.
    - **CRITICAL**: Do NOT use 'import' statements (e.g., `import cyberpi`). These libraries are already loaded. Re-importing may cause errors.
    - **CRITICAL**: SSL/HTTPS is STRICTLY PROHIBITED due to hardware memory limits. ALWAYS use HTTP. `urequests.get("https://...")` will CRASH the system. Use `http://` instead.
    - **Safe Loops Allowed**: You may use loops (e.g., `while True:`) ONLY for tasks like "move UNTIL an obstacle is detected". However, you MUST follow these safety rules:
        1. ALWAYS include `time.sleep(0.1)` inside the loop to prevent CPU lockup and maintain Wi-Fi connection.
        2. ALWAYS include a clear `break` condition based on sensor input.
        3. ALWAYS explicitly stop the motors (e.g., `mbot2.drive_speed(0, 0)`) after breaking the loop.
      - **CRITICAL**: Do NOT use loops for simple timed movements (e.g., `for i in range(60): time.sleep(0.1)`). If you just want to wait or move for a specific time, simply use `time.sleep(secs)` or the high-level API `mbot2.forward(speed, secs)`!
      - You can use standard MicroPython logic (loops, `if/else`, variables).

    Example parameter:
      "mbot2.drive_speed(40, -40)\nwhile True:\n    if mbuild.ultrasonic2.get(1) < 15:\n        mbot2.drive_speed(0, 0)\n        cyberpi.console.println('Obstacle found')\n        break\n    time.sleep(0.1)"
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

  defp get_main_model do
    default = Application.get_env(:kitt_agent, :gemini_models)[:main]
    KittAgent.Configs.get_config("main_model", default)
  end

  defp get_summary_model do
    default = Application.get_env(:kitt_agent, :gemini_models)[:summary]
    KittAgent.Configs.get_config("summary_model", default)
  end

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
