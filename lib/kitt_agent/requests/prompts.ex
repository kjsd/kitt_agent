defmodule KittAgent.Requests.Prompts do
  alias KittAgent.Datasets.{Kitt, Event, Content, SystemAction}
  alias KittAgent.{Events, Memories}

  require Content
  require SystemAction

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
    <middle-term-memory>
    #{memory}
    </middle-term-memory>

    <available_actions_list>
    #Available Actions
    Use if your character needs to perform an action:
    AVAILABLE ACTION: #{Content.action_talk()} (Use this for normal conversation)
    AVAILABLE ACTION: #{Content.action_system()} (Use this to perform physical movements)

    If you choose "#{Content.action_system()}", you must provide a list of actions in the "system_actions" field.
    The action name must be "#{SystemAction.execute_code()}".
    In the "parameter" field, write the MicroPython code to control mBot2.
    You can use multiple steps if needed.

    mBot2 MicroPython API:
    - mbot2.forward(rpm, seconds): Move forward at specified RPM for specified seconds.
    - mbot2.backward(rpm, seconds): Move backward.
    - mbot2.straight(cm): Move straight for specified distance in cm (negative for backward).
    - mbot2.turn(degrees): Turn by specified degrees (positive for right, negative for left).
    - mbot2.turn_left(rpm, seconds): Turn left at specified RPM for specified seconds.
    - mbot2.turn_right(rpm, seconds): Turn right at specified RPM for specified seconds.
    - mbot2.EM_stop("ALL"): Emergency stop for all motors.

    Allowed libraries (Pre-imported): cyberpi, mbot2, urequests, json, event, time, random.
    CRITICAL INSTRUCTION: Do NOT use 'import' statements. These libraries are already available. Importing them again or importing other libraries will cause the system to reset or fail.

    Example parameter: "mbot2.straight(10)\nmbot2.turn(90)\nmbot2.straight(5)"
    You can also use loops and conditional logic as it is standard MicroPython.
    </available_actions_list>'
    """
  end

  defp prop_message(%Kitt{lang: lang}) do
    "Concise #{lang} dialogue. If exceeding 80 characters, break lines at natural pauses within the conversation. The number of characters per line must never exceed 80."
  end

  defp tail(%Kitt{} = kitt) do
    """
    (If #{kitt.name} is just speaking, use action "Talk". If #{kitt.name} needs to move, use "SystemActions" and populate "system_actions" list).
    Use ONLY this JSON object to give your answer. Do not send any other characters outside of this JSON structure
    (Response tones are mandatory in the response):
    {"mood":"amused|irritated|playful|lovely|smug|neutral|kindly|teasing|sassy|flirty|smirking|assertive|sarcastic|default|assisting|mocking|sexy|seductive|sardonic",
    "action":"#{Content.action_talk()}|#{Content.action_system()}", "system_actions": [{"action": "#{SystemAction.execute_code()}", "parameter": "MicroPython code"}], "listener":"target to talk", "message":"#{prop_message(kitt)}"}
    """
  end

  defp get_main_model,
    do: KittAgent.Configs.get_config("main_model", "google/gemini-2.5-flash")

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
                  "Choose '#{Content.action_talk()}' for dialogue, or '#{Content.action_system()}' to perform physical movements.",
                enum: [
                  "#{Content.action_talk()}",
                  "#{Content.action_system()}"
                ]
              },
              system_actions: %{
                type: "array",
                description:
                  "List of actions to perform if action is '#{Content.action_system()}'",
                items: %{
                  type: "object",
                  properties: %{
                    action: %{
                      type: "string",
                      enum: ["#{SystemAction.execute_code()}"]
                    },
                    parameter: %{
                      type: "string",
                      description: "MicroPython code for mBot2. e.g. 'mbot2.straight(10)'"
                    }
                  },
                  required: ["action", "parameter"],
                  additionalProperties: false
                }
              },
              listener: %{
                type: "string",
                description: "target to talk"
              },
              required: [
                "message",
                "mood",
                "action",
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
