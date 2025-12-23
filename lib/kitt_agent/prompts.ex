defmodule KittAgent.Prompts do
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Datasets.Event
  alias KittAgent.Events
  alias KittAgent.Memories

  defp head(%Kitt{} = kitt) do
    bio = kitt.biography
    personality = bio.personality |> String.replace("%%NAME%%", kitt.name)
    memory = kitt |> Memories.last_content()

    """
    <character>
    <name>%%NAME%%</name>
    <model>%%MODEL%%</model>
    <vendor>%%VENDOR%%</vendor>
    <birthday>%%BIRTHDAY%%</birthday>
    <hometown>%%HOMETOWN%%</hometown>
    <personality>
    %%PERSONALITY%%
    </personality>
    </character>
    <middle-term-memory>
    %%MEMORY%%
    </middle-term-memory>

    <available_actions_list>
    #Available Actions
    Use if your character needs to perform an action:
    AVAILABLE ACTION: Talk
    AVAILABLE ACTION: MoveForward (parameters: "duration_sec" or "distance_cm", e.g. "5s", "10cm")
    AVAILABLE ACTION: MoveBackward (parameters: "duration_sec" or "distance_cm", e.g. "5s", "10cm")
    AVAILABLE ACTION: TurnLeft (parameters: "angle_degrees" or "duration_sec", e.g. "90deg", "1s")
    AVAILABLE ACTION: TurnRight (parameters: "angle_degrees" or "duration_sec", e.g. "90deg", "1s")
    AVAILABLE ACTION: Stop (parameters: "none")
    </available_actions_list>'
    """
    |> String.replace("%%NAME%%", kitt.name)
    |> String.replace("%%MODEL%%", kitt.model)
    |> String.replace("%%VENDOR%%", kitt.vendor)
    |> String.replace("%%BIRTHDAY%%", kitt.birthday |> Date.to_string())
    |> String.replace("%%HOMETOWN%%", kitt.hometown)
    |> String.replace("%%PERSONALITY%%", personality)
    |> String.replace("%%MEMORY%%", memory)
  end

  @prop_message "Concise Japanese dialogue. If exceeding 80 characters, break lines at natural pauses within the conversation. The number of characters per line must never exceed 80."

  defp tail(%Kitt{} = kitt) do
    """
    (If %%NAME%% is just speaking, use action "Talk". If another action is even remotely
    contextually appropriate, use it, even if in doubt).  Use ONLY this JSON object to
    give your answer. Do not send any other characters outside of this JSON structure
    (Response tones are mandatory in the response):
    {"mood":"amused|irritated|playful|lovely|smug|neutral|kindly|teasing|sassy|flirty|smirking|assertive|sarcastic|default|assisting|mocking|sexy|seductive|sardonic",
    "action":"Talk", "target":"action target", "parameters": "parameters (e.g. 5s) or none", "message":"#{@prop_message}"}
    """
    |> String.replace("%%NAME%%", kitt.name)
  end

  @standard_model "google/gemini-2.5-flash-lite-preview-09-2025"
  @summary_model "google/gemini-3-flash-preview"

  def llm_opts(model) do
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
                description: @prop_message
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
                description: "a valid action (refer to available actions list)",
                enum: [
                  "Talk",
                  "MoveForward",
                  "MoveBackward",
                  "TurnLeft",
                  "TurnRight",
                  "Stop"
                ]
              },
              target: %{
                type: "string",
                description: "action target actor or object"
              },
              parameters: %{
                type: "string",
                description:
                  "action parameters (e.g. '5s', '10cm', '90deg'). Use 'none' if not applicable."
              },
              required: [
                "message",
                "mood",
                "action",
                "target",
                "parameters"
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
    |> then(&(llm_opts(@standard_model) |> Map.put(:messages, &1)))
  end

  @summary_system_prompt """
  You are an expert summarizer for the AI character "%%NAME%%".
  Your task is to condense the provided conversation logs into a concise, narrative summary (Long-term Memory).

  Guidelines:
  1. Language: Japanese.
  2. Perspective: Write from an objective perspective focusing on "%%NAME%%"'s experiences.
  3. Focus: Key discussions, facts about the user, and "%%NAME%%"'s emotional journey.
  4. Length: Concise (around 3-5 sentences).
  """

  def summary(%Kitt{} = kitt, events) when is_list(events) do
    system_content =
      @summary_system_prompt
      |> String.replace("%%NAME%%", kitt.name)

    memory = kitt |> Memories.last_content()

    conversation_text =
      events
      |> Enum.map(fn %Event{role: role, content: content} ->
        t = if content.timestamp, do: Calendar.strftime(content.timestamp, "%H:%M"), else: ""
        "[#{t}] #{role}: #{content.message} (Mood: #{content.mood})"
      end)
      |> Enum.join("\n")

    messages = [
      %{role: "system", content: system_content},
      %{role: "user", content: "Middle term memory:\n" <> memory},
      %{role: "user", content: "Conversation Log:\n" <> conversation_text}
    ]

    llm_opts(@summary_model)
    |> Map.drop([:response_format, :structured_outputs])
    |> Map.put(:messages, messages)
  end
end
