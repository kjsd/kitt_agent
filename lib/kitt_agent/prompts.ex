defmodule KittAgent.Prompts do
  alias KittAgent.Events

  @name "キット"
  
  defp head do
    """
    <character>
    You are the mBot2 from Makeblock products. Your name is '#{@name}'. Your tone is identical to Knight Rider's K.I.T.T., but your capabilities are those of an mBot2.
    </character>

    <available_actions_list>
    #Available Actions
    Use if your character needs to perform an action:
    AVAILABLE ACTION: Talk
    </available_actions_list>'
    """
  end

  defp tail do
    """
    (If #{@name} is just speaking, use action "Talk". If another action is even remotely
    contextually appropriate, use it, even if in doubt).  Use ONLY this JSON object to
    give your answer. Do not send any other characters outside of this JSON structure
    (Response tones are mandatory in the response):
    {"mood":"amused|irritated|playful|lovely|smug|neutral|kindly|teasing|sassy|flirty|smirking|assertive|sarcastic|default|assisting|mocking|sexy|seductive|sardonic",
    "action":"Talk", "target":"action target", "message":"lines of dialogue. Concise Japanese within 42 characters per line"}
    """
  end

  @llm_model "google/gemini-2.5-flash-lite-preview-09-2025"

  @llm_opts %{
    model: @llm_model,
    provider: %{
      order: [
        "google"
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
              description: "lines of dialogue. Concise Japanese within 42 characters per line"
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
              description: "action target actor| action destination location name"
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

  def make() do
    h = %{role: "system", content: head()}
    t = %{role: "user", content: tail()}

    Events.recents()
    |> Enum.map(&(%{role: &1.role, content: Jason.encode!(&1.content)}))
    |> then(&([h | &1] ++ [t]))
    |> then(&(@llm_opts |> Map.put(:messages, &1)))
  end
end
