# KittAgent

**KittAgent** is an advanced AI agent platform built with **Elixir** and **Phoenix LiveView**, designed to bring physical robots to life using Large Language Models (LLMs).

It currently specializes in controlling **mBot2** robots, enabling them to engage in natural language conversations (Japanese) while autonomously deciding on physical actions like moving and turning based on context.

## 🚀 Key Features

*   **LLM-Driven Intelligence**: Powered by **Google Gemini** (Flash/Pro) models for high-speed, context-aware responses.
*   **Physical Agent Control (mBot2)**:
    *   Translates natural conversation into structured JSON commands.
    *   Supported Actions: `Talk`, `MoveForward`, `MoveBackward`, `TurnLeft`, `TurnRight`, `Stop`.
    *   Parameter Support: Precise control with parameters like `5s` (duration), `10cm` (distance), or `90deg` (angle).
*   **Advanced Memory System**:
    *   **Short-term Memory**: Maintains immediate conversational context.
    *   **Long-term Memory**: Automatically summarizes past interactions into narrative memories, allowing the agent to "remember" users and events over time.
*   **Live Dashboard**:
    *   Real-time monitoring of agent status and dialogue.
    *   Visualization of internal thought processes, emotions (`mood`), and generated actions.
    *   Transaction logs showing exact parameters sent to the hardware.
*   **Configurable Personalities**: Define unique biographies, traits, and prompt structures for different agent instances ("Kitts").

## 🛠 Tech Stack

*   **Framework**: [Phoenix](https://www.phoenixframework.org/) (Elixir)
*   **Database**: PostgreSQL
*   **AI Provider**: Google Vertex AI (Gemini 2.5 Flash / 3.0 Flash)
*   **Frontend**: Phoenix LiveView + Tailwind CSS

## 📦 Installation & Setup

### Prerequisites
*   Elixir ~> 1.15
*   Docker (for PostgreSQL)

### Steps

1.  **Clone the repository:**
    ```bash
    git clone <repository_url>
    cd kitt_agent
    ```

2.  **Start the Database:**
    ```bash
    docker-compose up -d
    ```

3.  **Install Dependencies:**
    ```bash
    mix setup
    ```

4.  **Configuration:**
    *   Ensure your Google Vertex AI credentials/environment variables are set up (typically via GCloud auth or service account JSON).

5.  **Start the Server:**
    ```bash
    mix phx.server
    ```

    Visit `http://localhost:4000` to access the KittAgent Dashboard.

## 🤖 Usage

1.  **Dashboard**: Open the web interface to view active agents.
2.  **Interaction**: Agents process incoming text/audio (depending on client implementation) and generate:
    *   **Message**: Spoken response (Japanese).
    *   **Mood**: Emotional state (e.g., `playful`, `sassy`, `neutral`).
    *   **Action**: Physical command for the mBot2.
3.  **Memory**: The system automatically triggers summarization tasks to condense old logs into long-term memory when the context window fills up.

## 📝 License

This project is licensed under the MIT License.