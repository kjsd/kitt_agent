# KittAgent Web API Specification

KittAgent provides a RESTful API for interacting with Kitt instances, managing conversations, and handling physical system actions.

## Base URL

The base URL for the API is relative to the hosted server root.
Example: `https://your-kitt-agent-server.com`

## Data Structures

### Content Object
Represents a unit of interaction, either a spoken message or a system action.

```json
{
  "id": 123,
  "action": "Talk",
  "parameter": null,
  "message": "Hello, how are you?",
  "listener": "User",
  "mood": "Happy",
  "status": "completed",
  "audio_path": "/uploads/path/to/audio.wav",
  "timestamp": "2023-10-27T10:00:00Z"
}
```

| Field | Type | Description |
|---|---|---|
| `id` | integer | Unique identifier for the content. |
| `action` | string | Type of content: `"Talk"` or `"SystemAction"`. |
| `parameter` | string \| null | Additional parameters for system actions (e.g., Python code for mBot2). |
| `message` | string | The text content of the speech or description of the action. |
| `listener` | string | The intended target of the message. |
| `mood` | string | The emotional state of the agent. |
| `status` | string | Current status: `"pending"`, `"processing"`, `"completed"`, `"failed"`. |
| `audio_path` | string \| null | Path to the generated audio file (if applicable). |
| `timestamp` | string \| null | ISO 8601 timestamp (virtual field). |

---

## Endpoints

### 1. Talk to Kitt
Sends a user message to a specific Kitt and receives a response.

- **Method:** `POST`
- **Path:** `/kitt/:id/talk`
- **Params:**
    - `id` (integer): ID of the Kitt agent.

**Request Body:**

```json
{
  "text": "Hello, Kitt!"
}
```

**Response:**

Returns a [Content Object](#content-object) representing the agent's response.

```json
{
  "id": 101,
  "action": "Talk",
  "message": "Hi there! I'm doing great.",
  "mood": "Excited",
  "status": "pending",
  ...
}
```

### 2. Dequeue Talk (Audio)
Retrieves the next available spoken message (with generated audio) from the queue. This is typically used by audio playback clients.

- **Method:** `GET`
- **Path:** `/kitt/:id/talks`
- **Params:**
    - `id` (integer): ID of the Kitt agent.

**Response:**

- Returns a [Content Object](#content-object) if audio is ready.
- Returns `null` if the queue is empty or audio is not yet generated.

### 3. Dequeue Pending Action
Retrieves the next pending system action (physical movement, etc.) from the queue. This is typically used by physical agent clients (e.g., mBot2).

- **Method:** `GET`
- **Path:** `/kitt/:id/actions/pending`
- **Params:**
    - `id` (integer): ID of the Kitt agent.

**Response:**

- Returns a [Content Object](#content-object) with `status: "pending"`.
- Returns `null` if no actions are pending.

> **Note:** Fetching an action via this endpoint automatically updates its status to `processing`.

### 4. Complete Action
Marks a specific system action as successfully completed.

- **Method:** `POST`
- **Path:** `/kitt/:id/actions/:content_id/complete`
- **Params:**
    - `id` (integer): ID of the Kitt agent.
    - `content_id` (integer): ID of the Content being completed.

**Response:**

```json
{
  "status": "OK"
}
```

### 5. Fail Action
Marks a specific system action as failed.

- **Method:** `POST`
- **Path:** `/kitt/:id/actions/:content_id/fail`
- **Params:**
    - `id` (integer): ID of the Kitt agent.
    - `content_id` (integer): ID of the Content that failed.

**Response:**

```json
{
  "status": "OK"
}
```
