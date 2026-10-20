defmodule KittAgent.Voice.EmotionState do
  @moduledoc """
  3-Layer Emotion Blending & Carry-Over System for KittAgent TTS.

  Manages three layers of vocal expression across multi-chunk sentences:
  1. **Base Mood (`mood`)**: Turn-wide emotional foundation from the LLM's JSON `mood` field.
  2. **Carry Tag (`[whisper]`, `[teasing]`, `[sarcastic]`, `[gently]`, etc.)**: Persistent tone/style tag
     that carries over to subsequent sentences in the same turn until another Carry Tag appears
     (or `[calm]` / `[neutral]` resets it).
  3. **One-Shot Tag (`[chuckles]`, `[laughter]`, `[sigh]`, `[gasp]`, etc.)**: Instantaneous reaction
     that applies only to the current sentence and never bleeds into the next sentence.
  """

  @tag_regex ~r/\[([a-zA-Z0-9_\-\s]+)\]/
  @speakable_regex ~r/[\p{Hiragana}\p{Katakana}\p{Han}a-zA-Z0-9]/u

  @intensifier_prefixes [
    "very ",
    "deep ",
    "deeply ",
    "heavy ",
    "heavily ",
    "strong ",
    "strongly ",
    "intense ",
    "intensely ",
    "extremely ",
    "super "
  ]

  @softener_prefixes [
    "slightly ",
    "soft ",
    "softly ",
    "mild ",
    "mildly ",
    "faint ",
    "faintly ",
    "little ",
    "a bit ",
    "emotion-",
    "style-",
    "sfx-"
  ]

  # ============================================================================
  # Carry Tag Profiles (Persistent across sentences until overridden)
  # ============================================================================
  @carry_profiles %{
    "happy" => %{
      sliders: %{"happy" => 0.6},
      valence: 0.4,
      arousal: 0.25,
      cfg_scale: 1.05,
      speed: 1.0,
      emotion_enabled: true,
      accurate_mode: false
    },
    "excited" => %{
      sliders: %{"happy" => 0.7, "surprised" => 0.2},
      valence: 0.55,
      arousal: 0.45,
      cfg_scale: 1.1,
      speed: 1.05,
      emotion_enabled: true,
      accurate_mode: false
    },
    "teasing" => %{
      sliders: %{"happy" => 0.6},
      valence: 0.35,
      arousal: 0.25,
      cfg_scale: 1.05,
      speed: 0.96,
      emotion_enabled: true,
      accurate_mode: false
    },
    "sarcastic" => %{
      sliders: %{"angry" => 0.3, "happy" => 0.25},
      valence: -0.1,
      arousal: 0.15,
      cfg_scale: 1.05,
      speed: 0.96,
      emotion_enabled: true,
      accurate_mode: false
    },
    "assertive" => %{
      sliders: %{"happy" => 0.35, "angry" => 0.15},
      valence: 0.2,
      arousal: 0.3,
      cfg_scale: 1.05,
      speed: 1.02,
      emotion_enabled: true,
      accurate_mode: false
    },
    "gently" => %{
      sliders: %{"happy" => 0.45},
      valence: 0.4,
      arousal: -0.2,
      cfg_scale: 1.05,
      speed: 0.94,
      emotion_enabled: true,
      accurate_mode: false
    },
    "whisper" => %{
      sliders: %{"happy" => 0.15},
      valence: 0.15,
      arousal: -0.25,
      cfg_scale: nil,
      speed: 0.88,
      emotion_enabled: true,
      accurate_mode: false
    },
    "shy" => %{
      sliders: %{"happy" => 0.3, "surprised" => 0.2},
      valence: 0.15,
      arousal: -0.1,
      cfg_scale: 1.05,
      speed: 0.93,
      emotion_enabled: true,
      accurate_mode: false
    },
    "pout" => %{
      sliders: %{"angry" => 0.55},
      valence: -0.25,
      arousal: 0.3,
      cfg_scale: 1.05,
      speed: 0.98,
      emotion_enabled: true,
      accurate_mode: false
    },
    "angry" => %{
      sliders: %{"angry" => 0.65},
      valence: -0.4,
      arousal: 0.45,
      cfg_scale: 1.1,
      speed: 1.0,
      emotion_enabled: true,
      accurate_mode: false
    },
    "exasperated" => %{
      sliders: %{"angry" => 0.4, "sad" => 0.25},
      valence: -0.3,
      arousal: -0.15,
      cfg_scale: 1.05,
      speed: 0.95,
      emotion_enabled: true,
      accurate_mode: false
    },
    "sad" => %{
      sliders: %{"sad" => 0.65},
      valence: -0.4,
      arousal: -0.25,
      cfg_scale: 1.05,
      speed: 0.92,
      emotion_enabled: true,
      accurate_mode: false
    },
    "worried" => %{
      sliders: %{"sad" => 0.45, "surprised" => 0.2},
      valence: -0.3,
      arousal: 0.15,
      cfg_scale: 1.05,
      speed: 0.95,
      emotion_enabled: true,
      accurate_mode: false
    },
    "trembling" => %{
      sliders: %{"sad" => 0.5, "surprised" => 0.25},
      valence: -0.4,
      arousal: 0.25,
      cfg_scale: 1.05,
      speed: 0.9,
      emotion_enabled: true,
      accurate_mode: false
    },
    "pleading" => %{
      sliders: %{"sad" => 0.45, "happy" => 0.15},
      valence: -0.15,
      arousal: 0.15,
      cfg_scale: 1.05,
      speed: 0.94,
      emotion_enabled: true,
      accurate_mode: false
    },
    "sleepy" => %{
      sliders: %{"sad" => 0.25, "happy" => 0.15},
      valence: 0.0,
      arousal: -0.45,
      cfg_scale: 1.0,
      speed: 0.88,
      emotion_enabled: true,
      accurate_mode: false
    },
    "relieved" => %{
      sliders: %{"happy" => 0.4},
      valence: 0.35,
      arousal: -0.2,
      cfg_scale: 1.05,
      speed: 0.95,
      emotion_enabled: true,
      accurate_mode: false
    },
    "fast" => %{
      sliders: %{"surprised" => 0.25},
      valence: 0.0,
      arousal: 0.45,
      cfg_scale: 1.05,
      speed: 1.15,
      emotion_enabled: true,
      accurate_mode: false
    },
    "slowly" => %{
      sliders: %{"happy" => 0.15},
      valence: 0.1,
      arousal: -0.25,
      cfg_scale: 1.0,
      speed: 0.88,
      emotion_enabled: true,
      accurate_mode: false
    },
    "calm" => %{
      sliders: %{},
      valence: nil,
      arousal: -0.2,
      cfg_scale: nil,
      speed: 0.92,
      emotion_enabled: true,
      accurate_mode: false,
      reset_carry: true
    }
  }

  # ============================================================================
  # One-Shot Tag Profiles (Current sentence only, never carried over)
  # ============================================================================
  @oneshot_profiles %{
    "laughter" => %{
      sliders: %{"happy" => 0.7},
      valence: 0.45,
      arousal: 0.3,
      cfg_scale: 1.1,
      speed: 1.0,
      emotion_enabled: true,
      accurate_mode: false
    },
    "sigh" => %{
      sliders: %{"sad" => 0.65},
      valence: -0.4,
      arousal: -0.25,
      cfg_scale: 1.05,
      speed: 0.92,
      emotion_enabled: true,
      accurate_mode: false
    },
    "surprised" => %{
      sliders: %{"surprised" => 0.7},
      valence: nil,
      arousal: 0.5,
      cfg_scale: 1.1,
      speed: 1.0,
      emotion_enabled: true,
      accurate_mode: false
    },
    "gasp" => %{
      sliders: %{"surprised" => 0.75},
      valence: -0.1,
      arousal: 0.6,
      cfg_scale: 1.1,
      speed: 1.04,
      emotion_enabled: true,
      accurate_mode: false
    },
    "sobbing" => %{
      sliders: %{"sad" => 0.8},
      valence: -0.55,
      arousal: 0.2,
      cfg_scale: 1.1,
      speed: 0.88,
      emotion_enabled: true,
      accurate_mode: false
    },
    "yawn" => %{
      sliders: %{"sad" => 0.3},
      valence: 0.0,
      arousal: -0.5,
      cfg_scale: 1.0,
      speed: 0.85,
      emotion_enabled: true,
      accurate_mode: false
    },
    "panting" => %{
      sliders: %{"surprised" => 0.35, "happy" => 0.25},
      valence: 0.1,
      arousal: 0.45,
      cfg_scale: 1.05,
      speed: 0.92,
      emotion_enabled: true,
      accurate_mode: false
    },
    "screaming" => %{
      sliders: %{"surprised" => 0.55, "angry" => 0.35},
      valence: -0.35,
      arousal: 0.7,
      cfg_scale: 1.15,
      speed: 1.08,
      emotion_enabled: true,
      accurate_mode: false
    },
    "tsk" => %{
      sliders: %{"angry" => 0.55},
      valence: -0.35,
      arousal: 0.2,
      cfg_scale: 1.05,
      speed: 0.95,
      emotion_enabled: true,
      accurate_mode: false
    },
    "questioning" => %{
      sliders: %{"surprised" => 0.4, "happy" => 0.15},
      valence: 0.1,
      arousal: 0.2,
      cfg_scale: 1.05,
      speed: 0.96,
      emotion_enabled: true,
      accurate_mode: false
    },
    "stuttering" => %{
      sliders: %{"surprised" => 0.5, "sad" => 0.2},
      valence: -0.2,
      arousal: 0.4,
      cfg_scale: 1.05,
      speed: 1.04,
      emotion_enabled: true,
      accurate_mode: false
    },
    "humming" => %{
      sliders: %{"happy" => 0.65},
      valence: 0.5,
      arousal: 0.2,
      cfg_scale: 1.05,
      speed: 0.95,
      emotion_enabled: true,
      accurate_mode: false
    },
    "nod" => %{
      sliders: %{},
      valence: nil,
      arousal: -0.15,
      cfg_scale: nil,
      speed: 0.94,
      emotion_enabled: true,
      accurate_mode: false,
      reset_carry: true
    },
    "clear throat" => %{
      sliders: %{},
      valence: nil,
      arousal: nil,
      cfg_scale: nil,
      speed: 0.95,
      emotion_enabled: false,
      accurate_mode: false
    }
  }

  # ============================================================================
  # Tag Classification & Normalization
  # ============================================================================

  @doc """
  Classifies a raw tag name into `{:carry, canonical_tag, profile}`,
  `{:oneshot, canonical_tag, profile}`, or `:unknown`.
  """
  def classify_tag(raw_tag) when is_binary(raw_tag) do
    normalized =
      raw_tag
      |> String.trim()
      |> String.downcase()
      |> strip_modifier_prefix()

    case do_classify(normalized) do
      {:carry, canonical} ->
        {:carry, canonical, Map.fetch!(@carry_profiles, canonical)}

      {:oneshot, canonical} ->
        {:oneshot, canonical, Map.fetch!(@oneshot_profiles, canonical)}

      :unknown ->
        :unknown
    end
  end

  def classify_tag(_), do: :unknown

  defp strip_modifier_prefix(tag) do
    Enum.find_value(@intensifier_prefixes ++ @softener_prefixes, tag, fn prefix ->
      if String.starts_with?(tag, prefix) do
        String.replace_prefix(tag, prefix, "") |> String.trim()
      else
        nil
      end
    end)
  end

  # --- Carry Tags ---
  defp do_classify(t)
       when t in [
              "happy",
              "happily",
              "cheerful",
              "cheerfully",
              "glad",
              "gladly",
              "joy",
              "joyful",
              "joyfully",
              "delighted",
              "delightedly",
              "pleased",
              "amused",
              "amusedly",
              "smile",
              "smiling",
              "bright",
              "brightly",
              "proud",
              "proudly",
              "fun"
            ],
       do: {:carry, "happy"}

  defp do_classify(t)
       when t in [
              "excited",
              "excitedly",
              "excitement",
              "enthusiastic",
              "enthusiastically",
              "ecstatic",
              "thrilled",
              "elated"
            ],
       do: {:carry, "excited"}

  defp do_classify(t)
       when t in [
              "teasing",
              "teasingly",
              "tease",
              "coaxing",
              "coaxingly",
              "playful",
              "playfully",
              "mischievous",
              "mischievously",
              "flirtatious",
              "flirtatiously",
              "flirty",
              "sassy",
              "sassily",
              "smug",
              "smugly",
              "smirk",
              "smirks",
              "smirking",
              "coy",
              "coyly",
              "cheeky",
              "sly",
              "slyly",
              "witty",
              "wittily"
            ],
       do: {:carry, "teasing"}

  defp do_classify(t)
       when t in [
              "sarcastic",
              "sarcastically",
              "sardonic",
              "sardonically",
              "mocking",
              "mockingly",
              "ironic",
              "ironically",
              "wry",
              "wryly",
              "cynical",
              "cynically"
            ],
       do: {:carry, "sarcastic"}

  defp do_classify(t)
       when t in [
              "assertive",
              "assertively",
              "confident",
              "confidently",
              "firm",
              "firmly",
              "decisive",
              "decisively",
              "authoritative"
            ],
       do: {:carry, "assertive"}

  defp do_classify(t)
       when t in [
              "gently",
              "gentle",
              "tender",
              "tenderly",
              "softly",
              "affectionate",
              "affectionately",
              "loving",
              "lovingly",
              "lovely",
              "warm",
              "warmly",
              "soothing",
              "soothingly",
              "sweet",
              "sweetly",
              "love",
              "kindly",
              "caring",
              "caringly",
              "assisting",
              "polite",
              "politely",
              "respectful",
              "respectfully"
            ],
       do: {:carry, "gently"}

  defp do_classify(t)
       when t in [
              "whisper",
              "whispering",
              "whispers",
              "whispered",
              "intimate",
              "intimately",
              "sexy",
              "seductive",
              "seductively",
              "sensual",
              "sensually",
              "sultry",
              "conspiratorial",
              "conspiratorially",
              "confidential",
              "confidentially",
              "secret",
              "secretive",
              "secretively",
              "murmur",
              "murmurs",
              "murmuring",
              "hushed",
              "quiet",
              "quietly",
              "under breath"
            ],
       do: {:carry, "whisper"}

  defp do_classify(t)
       when t in [
              "shy",
              "shyly",
              "bashful",
              "bashfully",
              "embarrassed",
              "embarrassedly",
              "blushing",
              "self-conscious",
              "modest",
              "demure"
            ],
       do: {:carry, "shy"}

  defp do_classify(t)
       when t in [
              "pout",
              "pouting",
              "pouty",
              "sulking",
              "sulk",
              "sulkily",
              "grumpy",
              "grumpily",
              "petulant",
              "petulantly",
              "dissatisfaction",
              "dissatisfaction-hnn",
              "displeased",
              "dissatisfied"
            ],
       do: {:carry, "pout"}

  defp do_classify(t)
       when t in [
              "angry",
              "angrily",
              "anger",
              "mad",
              "furious",
              "furiously",
              "irritated",
              "irritatedly",
              "frustrated",
              "frustratedly",
              "indignant",
              "indignantly",
              "outraged",
              "bitter",
              "bitterly",
              "resentful",
              "hostile",
              "fierce",
              "fiercely",
              "stern",
              "sternly",
              "alert"
            ],
       do: {:carry, "angry"}

  defp do_classify(t)
       when t in [
              "exasperated",
              "exasperatedly",
              "annoyed",
              "fed up",
              "rolling eyes",
              "eye roll",
              "dismissive",
              "dismissively",
              "unimpressed",
              "deadpan",
              "monotone",
              "flat",
              "flatly",
              "dry",
              "dryly",
              "cold",
              "coldly",
              "aloof"
            ],
       do: {:carry, "exasperated"}

  defp do_classify(t)
       when t in [
              "sad",
              "sadly",
              "sadness",
              "sorrow",
              "sorrowful",
              "sorrowfully",
              "melancholic",
              "melancholy",
              "depressed",
              "disappointed",
              "apologetic",
              "apologetically",
              "lonely",
              "heartbroken",
              "grief",
              "mournful",
              "mournfully",
              "hurt",
              "dejected",
              "dejectedly",
              "downcast",
              "somber",
              "somberly"
            ],
       do: {:carry, "sad"}

  defp do_classify(t)
       when t in [
              "worried",
              "worriedly",
              "worry",
              "anxious",
              "anxiously",
              "concerned",
              "uneasy",
              "uneasily",
              "troubled",
              "apprehensive",
              "apprehensively",
              "nervous",
              "nervously"
            ],
       do: {:carry, "worried"}

  defp do_classify(t)
       when t in [
              "trembling",
              "trembling voice",
              "quavering",
              "shaking",
              "shaky",
              "shakily",
              "timid",
              "timidly",
              "hesitant",
              "hesitantly",
              "unsure",
              "uncertain",
              "uncertainly",
              "fearful",
              "fearfully",
              "scared",
              "frightened",
              "terrified",
              "afraid",
              "vulnerable"
            ],
       do: {:carry, "trembling"}

  defp do_classify(t)
       when t in [
              "plead",
              "pleads",
              "pleading",
              "pleadingly",
              "beg",
              "begs",
              "begging",
              "implore",
              "imploring",
              "imploringly",
              "earnest",
              "earnestly"
            ],
       do: {:carry, "pleading"}

  defp do_classify(t)
       when t in [
              "sleepy",
              "sleepily",
              "drowsy",
              "drowsily",
              "tired",
              "tiredly",
              "weary",
              "wearily",
              "exhausted",
              "languid",
              "languidly",
              "sluggish",
              "bored",
              "lazily"
            ],
       do: {:carry, "sleepy"}

  defp do_classify(t)
       when t in [
              "relieved",
              "relief",
              "content",
              "contented",
              "contentedly",
              "satisfied",
              "satisfiedly",
              "peaceful",
              "peacefully",
              "serene",
              "serenely"
            ],
       do: {:carry, "relieved"}

  defp do_classify(t)
       when t in [
              "fast",
              "quickly",
              "rapidly",
              "hurried",
              "hurriedly",
              "rushed",
              "urgently",
              "urgent",
              "frantically",
              "hasty",
              "hastily"
            ],
       do: {:carry, "fast"}

  defp do_classify(t)
       when t in [
              "slowly",
              "slow",
              "deliberately",
              "unhurried",
              "measured"
            ],
       do: {:carry, "slowly"}

  defp do_classify(t)
       when t in [
              "calm",
              "calmly",
              "composed",
              "serious",
              "seriously",
              "solemn",
              "solemnly",
              "neutral",
              "normal",
              "default",
              "narration"
            ],
       do: {:carry, "calm"}

  # --- One-Shot Tags ---
  defp do_classify(t)
       when t in [
              "laughter",
              "laugh",
              "laughs",
              "laughing",
              "chuckle",
              "chuckles",
              "chuckling",
              "giggle",
              "giggles",
              "giggling",
              "snicker",
              "snickers",
              "snickering",
              "titters",
              "cackle",
              "cackles",
              "chortle",
              "wry laugh",
              "bitter laugh",
              "nervous laugh"
            ],
       do: {:oneshot, "laughter"}

  defp do_classify(t)
       when t in [
              "sigh",
              "sighs",
              "sighing",
              "exhale",
              "exhales",
              "groan",
              "groans",
              "groaning",
              "resigned",
              "resignedly",
              "weary sigh",
              "relieved sigh"
            ],
       do: {:oneshot, "sigh"}

  defp do_classify(t)
       when t in [
              "surprise-wa",
              "surprise-oh",
              "surprise-ah",
              "surprise-yo",
              "surprised",
              "surprise",
              "shock",
              "shocked",
              "startled",
              "astonished",
              "amazed",
              "astounded",
              "stunned",
              "dumbfounded",
              "awed",
              "awe",
              "exclamation"
            ],
       do: {:oneshot, "surprised"}

  defp do_classify(t)
       when t in [
              "gasp",
              "gasps",
              "gasping",
              "sharp intake of breath",
              "intake of breath",
              "catches breath"
            ],
       do: {:oneshot, "gasp"}

  defp do_classify(t)
       when t in [
              "cry",
              "cries",
              "crying",
              "sob",
              "sobs",
              "sobbing",
              "weep",
              "weeps",
              "weeping",
              "sniffle",
              "sniffles",
              "sniffling",
              "whimper",
              "whimpers",
              "whimpering",
              "tears",
              "tearfully"
            ],
       do: {:oneshot, "sobbing"}

  defp do_classify(t)
       when t in [
              "yawn",
              "yawns",
              "yawning",
              "stifled yawn"
            ],
       do: {:oneshot, "yawn"}

  defp do_classify(t)
       when t in [
              "pant",
              "pants",
              "panting",
              "breathless",
              "breathlessly",
              "out of breath",
              "heavy breathing",
              "moan",
              "moans",
              "moaning"
            ],
       do: {:oneshot, "panting"}

  defp do_classify(t)
       when t in [
              "scream",
              "screams",
              "screaming",
              "shriek",
              "shrieks",
              "yelp",
              "yelps",
              "shout",
              "shouts",
              "shouting",
              "yell",
              "yells",
              "yelling"
            ],
       do: {:oneshot, "screaming"}

  defp do_classify(t)
       when t in [
              "tsk",
              "tut",
              "tsks",
              "tuts",
              "click tongue",
              "clicks tongue",
              "tongue click",
              "scoff",
              "scoffs"
            ],
       do: {:oneshot, "tsk"}

  defp do_classify(t)
       when t in [
              "question-oh",
              "questioning",
              "questioningly",
              "questioning voice",
              "wondering",
              "wonderingly",
              "curious",
              "curiously",
              "puzzled",
              "confused",
              "confusedly",
              "perplexed",
              "skeptical",
              "doubtful",
              "thoughtful",
              "thoughtfully",
              "pensive",
              "pondering"
            ],
       do: {:oneshot, "questioning"}

  defp do_classify(t)
       when t in [
              "stutter",
              "stutters",
              "stuttering",
              "stammer",
              "stammers",
              "stammering",
              "flustered",
              "panicked",
              "panicking",
              "rattled"
            ],
       do: {:oneshot, "stuttering"}

  defp do_classify(t)
       when t in [
              "hum",
              "hums",
              "humming",
              "sing",
              "sings",
              "singing"
            ],
       do: {:oneshot, "humming"}

  defp do_classify(t)
       when t in [
              "confirmation-en",
              "confirmation",
              "nod",
              "nods",
              "nodding",
              "agree",
              "agreement",
              "backchannel",
              "mm-hmm",
              "uh-huh"
            ],
       do: {:oneshot, "nod"}

  defp do_classify(t)
       when t in [
              "clear throat",
              "clears throat",
              "clearing throat",
              "throat clear",
              "ahem",
              "cough",
              "coughs",
              "coughing",
              "sneeze",
              "sneezes",
              "pause",
              "pauses",
              "hesitates",
              "beat",
              "gulp",
              "gulps",
              "swallow",
              "swallows"
            ],
       do: {:oneshot, "clear throat"}

  defp do_classify(_), do: :unknown

  # ============================================================================
  # Tag Extraction & Sentence Carry Propagation
  # ============================================================================

  @doc """
  Extracts all recognized `[tag]` annotations from `text` in order of appearance.
  Returns a list of `{:carry | :oneshot, raw_tag, canonical_tag, profile}`.
  """
  def extract_tags(text) when is_binary(text) do
    @tag_regex
    |> Regex.scan(text)
    |> Enum.reduce([], fn [_full, raw_tag], acc ->
      case classify_tag(raw_tag) do
        {:carry, canonical, profile} ->
          [{:carry, raw_tag, canonical, profile} | acc]

        {:oneshot, canonical, profile} ->
          [{:oneshot, raw_tag, canonical, profile} | acc]

        :unknown ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  def extract_tags(_), do: []

  @doc """
  Propagates the active Carry Tag into `sentence` and returns `{decorated_sentence, next_carry_tag}`.

  - If `sentence` contains a Carry Tag (e.g. `[whisper]`, `[sarcastic]`, `[teasing]`), that tag
    becomes `next_carry_tag` (or `nil` if the tag is `[calm]`/`[neutral]`).
  - If `sentence` does NOT contain a Carry Tag and `current_carry_tag` is active,
    `[current_carry_tag]` is prepended to `sentence` while keeping `next_carry_tag = current_carry_tag`.
  - One-Shot tags (`[chuckles]`, `[sigh]`, etc.) in `sentence` stay in `sentence` and are never
    stored in `next_carry_tag`.
  """
  def propagate_carry(sentence, current_carry_tag) when is_binary(sentence) do
    tags = extract_tags(sentence)
    carry_tags = for {:carry, _raw, canonical, _profile} <- tags, do: canonical

    case List.last(carry_tags) do
      nil ->
        if is_binary(current_carry_tag) and current_carry_tag != "" and
             String.match?(sentence, @speakable_regex) do
          {"[#{current_carry_tag}] " <> sentence, current_carry_tag}
        else
          {sentence, current_carry_tag}
        end

      "calm" ->
        {sentence, nil}

      new_carry ->
        {sentence, new_carry}
    end
  end

  def propagate_carry(sentence, current_carry_tag), do: {sentence, current_carry_tag}

  @doc """
  Propagates Carry Tags across a list of sentence chunks.
  """
  def propagate_sentences(sentences, initial_carry \\ nil) when is_list(sentences) do
    {decorated, _final_carry} = Enum.map_reduce(sentences, initial_carry, &propagate_carry/2)
    decorated
  end

  @doc """
  Resolves the canonical tag name for a `mood` string.
  Returns `{:ok, canonical_tag, kind, profile}` or `:none`.
  """
  def resolve_mood(mood) when is_binary(mood) do
    cleaned_mood =
      mood
      |> String.trim()
      |> String.downcase()
      |> String.replace_prefix("silent_", "")
      |> String.trim()

    cond do
      cleaned_mood in ["", "neutral", "normal", "default", "silent"] ->
        :none

      true ->
        case classify_tag(cleaned_mood) do
          {:carry, "calm", _profile} ->
            :none

          {:carry, canonical, profile} ->
            {:ok, canonical, :carry, profile}

          {:oneshot, canonical, profile} ->
            {:ok, canonical, :oneshot, profile}

          :unknown ->
            resolve_mood_substring(cleaned_mood)
        end
    end
  end

  def resolve_mood(_), do: :none

  defp resolve_mood_substring(lower_mood) do
    cond do
      String.contains?(lower_mood, ["happy", "laugh", "excited", "joy", "fun", "amused", "pleased"]) ->
        {:ok, "happy", :carry, Map.fetch!(@carry_profiles, "happy")}

      String.contains?(lower_mood, ["whisper", "sweet", "intimate", "seductive"]) ->
        {:ok, "whisper", :carry, Map.fetch!(@carry_profiles, "whisper")}

      String.contains?(lower_mood, ["sarcastic", "sardonic", "mocking"]) ->
        {:ok, "sarcastic", :carry, Map.fetch!(@carry_profiles, "sarcastic")}

      String.contains?(lower_mood, ["teasing", "coax", "playful", "sassy", "flirty", "smug", "smirk"]) ->
        {:ok, "teasing", :carry, Map.fetch!(@carry_profiles, "teasing")}

      String.contains?(lower_mood, ["assertive", "confident"]) ->
        {:ok, "assertive", :carry, Map.fetch!(@carry_profiles, "assertive")}

      String.contains?(lower_mood, ["pout", "sulk", "dissatisfaction"]) ->
        {:ok, "pout", :carry, Map.fetch!(@carry_profiles, "pout")}

      String.contains?(lower_mood, ["angry", "mad", "annoyed", "irritated"]) ->
        {:ok, "angry", :carry, Map.fetch!(@carry_profiles, "angry")}

      String.contains?(lower_mood, ["sad", "sigh", "depressed", "sorrow"]) ->
        {:ok, "sad", :carry, Map.fetch!(@carry_profiles, "sad")}

      String.contains?(lower_mood, ["shy", "bashful", "embarrassed"]) ->
        {:ok, "shy", :carry, Map.fetch!(@carry_profiles, "shy")}

      String.contains?(lower_mood, ["gentle", "gently", "tender", "lovely", "kindly", "assisting"]) ->
        {:ok, "gently", :carry, Map.fetch!(@carry_profiles, "gently")}

      true ->
        :none
    end
  end

  @doc """
  Decorates a sentence or multi-sentence text for OpenAI-compatible TTS (`openai-tts-bridge`).
  Ensures Carry Tags propagate across sentences and falls back to `[mood]` when a sentence
  does not already start with a bracketed tag and has no active Carry Tag.
  """
  def decorate_for_openai(text, mood \\ "neutral") when is_binary(text) do
    trimmed_text = String.trim(text)
    trimmed_mood = String.trim(mood || "")

    raw_mood_tag =
      if trimmed_mood in ["", "neutral", "normal", "default"] do
        nil
      else
        trimmed_mood
      end

    parts = Regex.split(~r/([。！？\n]+)/u, trimmed_text, include_captures: true, trim: true)
    sentences = reconstruct_with_punct(parts, [])

    case sentences do
      [] ->
        trimmed_text

      list ->
        {decorated_list, _} =
          Enum.map_reduce(list, nil, fn sentence, active_carry ->
            {prop_sentence, next_carry} = propagate_carry(sentence, active_carry)

            starts_with_bracket? =
              String.starts_with?(prop_sentence, "[") or String.starts_with?(prop_sentence, "【")

            has_carry_or_calm? =
              Enum.any?(extract_tags(prop_sentence), fn {kind, _, _, _} -> kind == :carry end)

            final_sentence =
              if not starts_with_bracket? and not has_carry_or_calm? and is_nil(next_carry) and
                   is_binary(raw_mood_tag) and String.match?(prop_sentence, @speakable_regex) do
                "[#{raw_mood_tag}] " <> prop_sentence
              else
                prop_sentence
              end

            {final_sentence, next_carry}
          end)

        Enum.join(decorated_list, " ")
        |> String.replace(~r/[ \t]+/, " ")
        |> String.trim()
    end
  end

  defp reconstruct_with_punct([], acc), do: Enum.reverse(acc)

  defp reconstruct_with_punct([s, punct | tail], acc) do
    reconstruct_with_punct(tail, [String.trim(s <> punct) | acc])
  end

  defp reconstruct_with_punct([s | tail], acc) do
    reconstruct_with_punct(tail, [String.trim(s) | acc])
  end

  # ============================================================================
  # Zonos 2 3-Layer Parameter Blending
  # ============================================================================

  @doc """
  Computes the blended Zonos 2 emotion parameter map for a single sentence chunk
  given `text` (which may contain Carry and/or One-Shot tags) and `mood` (Base Mood).
  """
  def resolve_zonos2_params(text, mood \\ "neutral") when is_binary(text) do
    tags = extract_tags(text)

    carry_profiles = for {:carry, _raw, _canon, profile} <- tags, do: profile
    oneshot_profiles = for {:oneshot, _raw, _canon, profile} <- tags, do: profile

    carry_profile = List.last(carry_profiles)
    oneshot_profile = merge_same_layer_profiles(oneshot_profiles)

    base_profile =
      case resolve_mood(mood) do
        {:ok, _canon, _kind, profile} -> scale_base_profile(profile)
        :none -> nil
      end

    default_params = %{
      "emotion_enabled" => false,
      "accurate_mode" => false,
      "speaking_rate_enabled" => true,
      "speaking_rate" => 13.0
    }

    cond do
      # Explicit calm/confirmation tag with no emotional one-shot override
      not is_nil(carry_profile) and
          (carry_profile.emotion_enabled == false or Map.get(carry_profile, :reset_carry, false)) and
          is_nil(oneshot_profile) ->
        Map.merge(default_params, profile_to_zonos_map(carry_profile))

      not is_nil(oneshot_profile) and
          (oneshot_profile.emotion_enabled == false or Map.get(oneshot_profile, :reset_carry, false)) and
          is_nil(carry_profile) ->
        Map.merge(default_params, profile_to_zonos_map(oneshot_profile))

      # All 3 layers active: Base (0.20) + Carry (0.30) + One-Shot (0.50)
      not is_nil(base_profile) and not is_nil(carry_profile) and not is_nil(oneshot_profile) ->
        blended =
          blend_weighted([
            {base_profile, 0.20},
            {carry_profile, 0.30},
            {oneshot_profile, 0.50}
          ])

        Map.merge(default_params, profile_to_zonos_map(blended))

      # Carry (0.35) + One-Shot (0.65)
      not is_nil(carry_profile) and not is_nil(oneshot_profile) ->
        blended =
          blend_weighted([
            {carry_profile, 0.35},
            {oneshot_profile, 0.65}
          ])

        Map.merge(default_params, profile_to_zonos_map(blended))

      # Base (0.30) + Carry (0.70)
      not is_nil(base_profile) and not is_nil(carry_profile) ->
        blended =
          blend_weighted([
            {base_profile, 0.30},
            {carry_profile, 0.70}
          ])

        Map.merge(default_params, profile_to_zonos_map(blended))

      # Base (0.35) + One-Shot (0.65)
      not is_nil(base_profile) and not is_nil(oneshot_profile) ->
        blended =
          blend_weighted([
            {base_profile, 0.35},
            {oneshot_profile, 0.65}
          ])

        Map.merge(default_params, profile_to_zonos_map(blended))

      # Carry only (1.0)
      not is_nil(carry_profile) ->
        Map.merge(default_params, profile_to_zonos_map(carry_profile))

      # One-Shot only (1.0)
      not is_nil(oneshot_profile) ->
        Map.merge(default_params, profile_to_zonos_map(oneshot_profile))

      # Base Mood only (fallback)
      not is_nil(base_profile) ->
        Map.merge(default_params, profile_to_zonos_map(base_profile))

      # No tags and neutral mood
      true ->
        default_params
    end
  end

  defp scale_base_profile(%{emotion_enabled: false} = profile), do: profile

  defp scale_base_profile(profile) do
    scaled_sliders =
      Map.new(profile.sliders, fn {k, v} ->
        {k, Float.round(v * 0.75, 2)}
      end)

    scaled_valence =
      if is_number(profile.valence), do: Float.round(profile.valence * 0.8, 2), else: nil

    scaled_arousal =
      if is_number(profile.arousal), do: Float.round(profile.arousal * 0.8, 2), else: nil

    %{
      profile
      | sliders: scaled_sliders,
        valence: scaled_valence,
        arousal: scaled_arousal
    }
  end

  defp merge_same_layer_profiles([]), do: nil
  defp merge_same_layer_profiles([single]), do: single

  defp merge_same_layer_profiles(profiles) do
    weight = 1.0 / length(profiles)
    weighted = Enum.map(profiles, fn p -> {p, weight} end)
    blend_weighted(weighted)
  end

  defp blend_weighted(weighted_profiles) do
    emotional =
      Enum.filter(weighted_profiles, fn {p, _w} -> p.emotion_enabled end)

    if emotional == [] do
      {last_p, _} = List.last(weighted_profiles)
      last_p
    else
      total_w = Enum.reduce(emotional, 0.0, fn {_p, w}, acc -> acc + w end)
      normalized = Enum.map(emotional, fn {p, w} -> {p, w / total_w} end)

      # 1. Blend sliders
      raw_sliders =
        Enum.reduce(normalized, %{}, fn {p, w}, acc ->
          Enum.reduce(p.sliders, acc, fn {emotion, val}, s_acc ->
            Map.update(s_acc, emotion, val * w, &(&1 + val * w))
          end)
        end)

      # Normalize if slider sum > 1.0 to prevent Zonos 2 saturation distortion
      slider_sum = Enum.reduce(raw_sliders, 0.0, fn {_k, v}, acc -> acc + v end)

      blended_sliders =
        raw_sliders
        |> Map.new(fn {k, v} ->
          scaled = if slider_sum > 1.0, do: v / slider_sum, else: v
          {k, Float.round(scaled, 2)}
        end)
        |> Enum.reject(fn {_k, v} -> v <= 0.01 end)
        |> Map.new()

      # 2. Blend valence
      blended_valence = blend_optional_axis(normalized, :valence)

      # 3. Blend arousal
      blended_arousal = blend_optional_axis(normalized, :arousal)

      # 4. Blend cfg_scale
      blended_cfg = blend_optional_axis(normalized, :cfg_scale)

      # 5. Blend speed
      any_custom_speed? =
        Enum.any?(weighted_profiles, fn {p, _w} ->
          is_number(p.speed) and abs(p.speed - 1.0) > 0.001
        end)

      blended_speed =
        if any_custom_speed? do
          all_w = Enum.reduce(weighted_profiles, 0.0, fn {_p, w}, acc -> acc + w end)

          speed_val =
            Enum.reduce(weighted_profiles, 0.0, fn {p, w}, acc ->
              acc + (p.speed || 1.0) * (w / all_w)
            end)

          Float.round(max(0.75, min(1.35, speed_val)), 2)
        else
          1.0
        end

      %{
        sliders: blended_sliders,
        valence: blended_valence,
        arousal: blended_arousal,
        cfg_scale: blended_cfg,
        speed: blended_speed,
        emotion_enabled: true,
        accurate_mode: false
      }
    end
  end

  defp blend_optional_axis(normalized_profiles, key) do
    present =
      Enum.filter(normalized_profiles, fn {p, _w} ->
        is_number(Map.get(p, key))
      end)

    case present do
      [] ->
        nil

      list ->
        w_sum = Enum.reduce(list, 0.0, fn {_p, w}, acc -> acc + w end)

        val =
          Enum.reduce(list, 0.0, fn {p, w}, acc ->
            acc + Map.get(p, key) * (w / w_sum)
          end)

        Float.round(val, 2)
    end
  end

  defp profile_to_zonos_map(%{emotion_enabled: false} = profile) do
    %{
      "emotion_enabled" => false,
      "accurate_mode" => profile.accurate_mode
    }
    |> maybe_put_speed(profile.speed)
  end

  defp profile_to_zonos_map(profile) do
    %{
      "emotion_enabled" => true,
      "accurate_mode" => profile.accurate_mode,
      "emotion_sliders" => profile.sliders
    }
    |> maybe_put("emotion_valence", profile.valence)
    |> maybe_put("emotion_arousal", profile.arousal)
    |> maybe_put("emotion_cfg_scale", profile.cfg_scale)
    |> maybe_put_speed(profile.speed)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  # Zonos 2 defines 8 speaking-rate buckets where Bucket 2 ("11-14" B/s) is natural Japanese pace
  # and Bucket 3 ("14-17" B/s) is lively/fast Japanese pace. Using `speed` directly in Zonos 2
  # multiplies against 19.0 B/s (Bucket 4 "17-21"), which makes brisk reference voices speak too fast.
  # Mapping `speed` via `13.5 * speed` locks normal/calm speech to Bucket 2 and excited speech to Bucket 3.
  defp maybe_put_speed(map, speed) when is_number(speed) and speed > 0 do
    map
    |> Map.put("speaking_rate_enabled", true)
    |> Map.put("speaking_rate", Float.round(13.5 * speed, 2))
  end

  defp maybe_put_speed(map, _), do: map
end
