defmodule KittAgent.Prompts do
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event
  alias KittAgent.Datasets.Content
  alias KittAgent.Events
  alias KittAgent.Memories

  require Content

  defp head(%Kitt{biography: bio} = kitt) do
    personality = bio.personality |> String.replace("%%NAME%%", kitt.name)
    memory = kitt |> Memories.last_content()

    """
    <character>
    <name>#{kitt.name}</name>
    <model>#{kitt.model}</model>
    <vendor>#{kitt.vendor}</vendor>
    <birthday>#{Date.to_string(kitt.birthday)}</birthday>
    <hometown>#{kitt.hometown}</hometown>
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
    AVAILABLE ACTION: #{Content.action_talk} (Use this for normal conversation)
    AVAILABLE ACTION: #{Content.action_system} (Use this to perform physical movements)

    If you choose "#{Content.action_system}", you must provide a list of actions in the "system_actions" field.
    Supported physical actions:
    - MoveForward (parameters: "duration_sec" or "distance_cm", e.g. "5s", "10cm")
    - MoveBackward (parameters: "duration_sec" or "distance_cm", e.g. "5s", "10cm")
    - TurnLeft (parameters: "angle_degrees" or "duration_sec", e.g. "90deg", "1s")
    - TurnRight (parameters: "angle_degrees" or "duration_sec", e.g. "90deg", "1s")
    - Stop (parameters: "none")
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
    "action":"#{Content.action_talk}|#{Content.action_system}", "system_actions": [{"action": "MoveForward", "parameter": "10cm"}], "listener":"target to talk", "message":"#{prop_message(kitt)}"}
    """
  end

  @standard_model "google/gemini-2.5-flash-lite-preview-09-2025"
  @summary_model "google/gemini-3-flash-preview"

  def llm_opts(%Kitt{} = kitt, model) do
    %{
      model: model,
      provider: %{
        order: [
          "google-vertex"
        ]
      },
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
                description: "Choose '#{Content.action_talk}' for dialogue, or '#{Content.action_system}' to perform physical movements.",
                enum: [
                  "#{Content.action_talk}",
                  "#{Content.action_system}"
                ]
              },
              system_actions: %{
                type: "array",
                description: "List of actions to perform if action is '#{Content.action_system}'",
                items: %{
                  type: "object",
                  properties: %{
                    action: %{
                      type: "string",
                      enum: ["MoveForward", "MoveBackward", "TurnLeft", "TurnRight", "Stop"]
                    },
                    parameter: %{
                      type: "string",
                      description: "e.g. '5s', '10cm', '90deg'"
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
                "listener",
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

    kitt
    |> Events.recents()
    |> then(&(&1 ++ [last_ev]))
    |> Enum.map(&%{role: &1.role, content: Jason.encode!(&1.content)})
    |> then(&([h | &1] ++ [t]))
    |> then(&(llm_opts(kitt, @standard_model) |> Map.put(:messages, &1)))
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
      |> Enum.map(&Events.with_timestamp(&1, kitt))
      |> Enum.map(&("[#{&1.timestamp}] #{&1.role}: #{&1.content.message} (Mood: #{&1.content.mood})"))
      |> Enum.join("\n")

    messages = [
      %{role: "system", content: summary_system_prompt(kitt)},
      %{role: "user", content: "Middle term memory:\n" <> memory},
      %{role: "user", content: "Conversation Log:\n" <> conversation_text}
    ]

    llm_opts(kitt, @summary_model)
    |> Map.drop([:response_format, :structured_outputs])
    |> Map.put(:messages, messages)
  end
end
