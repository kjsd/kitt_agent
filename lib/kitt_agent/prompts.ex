defmodule KittAgent.Prompts do
  alias KittAgent.Events
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts

  defp head(%Kitt{} = kitt) do
    bio = Kitts.biography(kitt)
    personality = bio.personality |> String.replace("%%NAME%%", kitt.name)
    
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

    <available_actions_list>
    #Available Actions
    Use if your character needs to perform an action:
    AVAILABLE ACTION: Talk
    </available_actions_list>'
    """
    |> String.replace("%%NAME%%", kitt.name)
    |> String.replace("%%MODEL%%", kitt.model)
    |> String.replace("%%VENDOR%%", kitt.vendor)
    |> String.replace("%%BIRTHDAY%%", kitt.birthday |> Date.to_string)
    |> String.replace("%%HOMETOWN%%", kitt.hometown)
    |> String.replace("%%PERSONALITY%%", personality)
  end    
    
  defp tail(%Kitt{} = kitt) do
    """
    (If %%NAME%% is just speaking, use action "Talk". If another action is even remotely
    contextually appropriate, use it, even if in doubt).  Use ONLY this JSON object to
    give your answer. Do not send any other characters outside of this JSON structure
    (Response tones are mandatory in the response):
    {"mood":"amused|irritated|playful|lovely|smug|neutral|kindly|teasing|sassy|flirty|smirking|assertive|sarcastic|default|assisting|mocking|sexy|seductive|sardonic",
    "action":"Talk", "target":"action target", "message":"lines of dialogue."}
    """
    |> String.replace("%%NAME%%", kitt.name)
  end

  @prop_message "Concise Japanese dialogue. If exceeding 42 characters, break lines at natural pauses within the conversation. The number of characters per line must never exceed 42."

  @llm_model "google/gemini-2.5-flash-lite-preview-09-2025"

  @llm_opts %{
    model: @llm_model,
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
              ]
            },
            target: %{
              type: "string",
              description: "action target actor or object"
            },
            required: [
              "message",
              "mood",
              "action",
              "target"
            ],
            additionalProperties: false
          },
          strict: true
        }
      }
    }
  }

  def make(%Kitt{} = kitt, last_ev) do
    h = %{role: "system", content: head(kitt)}
    t = %{role: "user", content: tail(kitt)}

    kitt
    |> Events.recents()
    |> then(&(&1 ++ [last_ev]))
    |> Enum.map(&(%{role: &1.role, content: Jason.encode!(&1.content)}))
    |> then(&([h | &1] ++ [t]))
    |> then(&(@llm_opts |> Map.put(:messages, &1)))
  end

end
