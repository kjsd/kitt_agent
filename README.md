# KittAgent

**KittAgent** is an advanced AI agent platform built with **Elixir** and **Phoenix LiveView**, designed to bring physical robots to life using Large Language Models (LLMs).

It currently specializes in controlling **mBot2** robots, enabling them to engage in natural language conversations while autonomously deciding on physical actions like moving and turning based on context.

## 📖 Documentation

- **[GitHub Wiki](https://github.com/kjsd/kitt_agent/wiki)**: Comprehensive guide and tutorials.
- **[Web API Specification](./API_SPEC.md)**: Details on available REST API endpoints for clients.

## 🚀 Key Features

### 1. Real-time Interaction Dashboard
*   **Direct Communication**: Chat directly with your agents via the web interface to test personality and responsiveness.
*   **Multimedia Feedback**: 
    *   **Audio Playback**: Listen to generated voice responses directly in the feed (integrated with TTS engines like Zonos).
    *   **Visual Logs**: See immediate feedback on role, message content, and mood.
*   **Transaction Management**: View and clean up recent interaction logs.
*   **Action Inspection**: Inspect complex `SystemActions` in a formatted, scrollable code view to verify parameters.

### 2. Advanced Agent Management ("Kitts")
*   **Comprehensive Profiles**: Manage multiple agents with distinct profiles including Name, Model, Vendor, Birthday, and Hometown.
*   **Localization Support**:
    *   **Language Selection**: Choose from 18+ languages (Japanese, English, Swahili, etc.) for your agent's communication.
    *   **Timezone Awareness**: Selectable timezone support (via `Tzdata`) to ground the agent in a specific locale.
*   **Personality Engine**: Define complex biographies and behavioral traits ("Personality"). Long descriptions are easily managed via pop-up modals.
*   **Smart Defaults**: Automatically applies system-wide default language and timezone settings to new agents.

### 3. LLM-Driven Intelligence & Control
*   **Flexible Model Selection**:
    *   **Main Conversation Model**: Choose any model supported by your provider (e.g., Gemini 2.0 Flash) for agent dialogue.
    *   **Summarization Model**: Select a specialized model for high-quality memory consolidation.
*   **Custom LLM Providers**: Configure custom API endpoints and keys (e.g., OpenRouter) directly from the settings menu.
*   **Structured Outputs**: Enforces strict JSON Schema for all LLM responses to ensure reliable parsing.
*   **Physical Capabilities (SystemActions)**:
    *   **Direct Code Generation**: The agent generates **MicroPython code** dynamically to control the robot, allowing for complex and adaptive behaviors beyond simple preset commands.
    *   **Hardware Control**:
        *   **Core (CyberPi)**: Control LEDs, speaker, display, and read inputs (buttons, gyro, mic).
        *   **Chassis (mBot2)**: Precise movement control (speed, duration, turning).
        *   **Sensors (mBuild)**: Access external modules like Ultrasonic Sensor 2 and Quad RGB Sensor.
    *   **Flexible Logic**: Supports conditional logic and loops within the generated code (e.g., "Forward until obstacle < 10cm, then turn").

### 4. Comprehensive Activity Monitoring ("Activities")
*   **Live Audit Log**: A dedicated "Activities" dashboard to track all historical agent responses and decisions.
*   **Status Management**: Monitor and manually override action statuses (`pending`, `processing`, `completed`, `failed`).
    *   **Formatted Code Blocks**: Ensure long parameters are readable without breaking the layout.
    *   **Queue Maintenance**: Monitor real-time queue depths and manually clear "Talk" or "System Action" queues (globally or per-agent) to prevent stale task accumulation.
    *   **Advanced Filtering**: Filter logs by Kitt, Status, or Role to pinpoint specific events.

### 5. Dual-Layer Memory Architecture
*   **Short-term Memory (Events)**: Maintains a log of recent interactions for immediate context.
*   **Long-term Memory (Memories)**:
    *   **Auto-Summarization**: A background process condense new events into narrative summaries.
    *   **Persistent Context**: Summaries are injected into the system prompt, providing a persistent sense of history.

### 6. Centralized Configuration ("Settings")
*   **System Defaults**: Set global defaults for new agent creation.
*   **LLM Provider Setup**: Update API keys and Base URLs without touching environment variables or restarting the server.
*   **Model Management**: Switch between different LLM models for conversation and summarization on the fly.

## 🤖 Physical Action Architecture & Client Design

KittAgent employs a distributed client architecture designed to overcome the resource constraints of microcontroller-based robots like **mBot2**.

### Dual-Queue System
To handle different types of agent outputs efficiently, the system maintains two separate, independent queues:

1.  **Talk Queue (`Talks.Queue`)**: Stores audio response data (TTS-generated WAV files).
2.  **System Action Queue (`SystemActions.Queue`)**: Stores physical command data (MicroPython code).

### Client Roles
*   **mBot2 (Robot Client)**:
    *   **Primary Role**: Physical execution.
    *   **Mechanism**: Polls the **System Action Queue**, retrieves generated **MicroPython code**, and executes it locally to perform actions (move, turn, LED control).
    *   **Constraint**: Due to limited memory and processing power, it does *not* handle audio playback.
*   **Companion Device (Mobile/PC Client)**:
    *   **Primary Role**: Voice interaction.
    *   **Mechanism**: Polls the **Talk Queue** and plays back the audio responses.
    *   **Benefit**: This offloads the heavy lifting of audio streaming/decoding from the robot, ensuring smooth, uninterrupted movement and clear voice output.

## 🛠 Tech Stack
*   **Core**: Elixir, Phoenix Framework (LiveView)
*   **Database**: PostgreSQL (with `pgvector` support planned/ready)
*   **AI Provider**: OpenRouter (default), or any OpenAI-compatible API
*   **TTS Provider**: Zonos (Gradio) / Custom Audio Pipelines
*   **Styling**: Tailwind CSS + DaisyUI
*   **Infrastructure**: Docker & Docker Compose

## 🗄 Database Schema Overview

*   **kitts**: Core agent metadata.
*   **biographies**: Detailed "Personality" text.
*   **events**: Raw log of interactions.
*   **contents**: Structured data for each event (message, action, mood, status, audio paths).
*   **system_actions**: Specific parameters for physical movements.
*   **memories**: Narrative summaries generated by the agent.
*   **configs**: Global key-value settings (LLM models, API credentials, defaults).

## 📦 Installation & Setup

### Prerequisites
*   Docker & Docker Compose

### Quick Start

1.  **Clone & Setup:**
    ```bash
    git clone <repository_url>
    cd kitt_agent
    docker compose run --rm app mix setup
    ```

2.  **Initial Configuration:**
    1. Start the server: `docker compose up`
    2. Visit `http://localhost:4000/kitt-web/settings`
    3. Configure your **API Key** and **API Base URL** (OpenRouter default: `https://openrouter.ai/api/v1/chat/completions`).
    4. Select your preferred **Main** and **Summary** models.

3.  **Create your first Kitt:**
    Navigate to the **KITTs** page and click **New Kitt**.

## 📝 License

This project is licensed under the MIT License.
