defmodule KittAgentWeb.HomeLiveTest do
  use KittAgentWeb.ConnCase

  import Phoenix.LiveViewTest
  alias KittAgent.Datasets.Kitt
  alias KittAgent.Events

  setup do
    kitt =
      %Kitt{name: "DashboardKitt", vendor: "openai", model: "gpt-4"}
      |> KittAgent.Repo.insert!()

    %{kitt: kitt}
  end

  test "connected mount subscribes to events", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/kitt-web")
    # Checking subscription indirectly via behavior or internal state is hard from outside.
    # But we can verify if the view updates when an event is broadcasted.
  end

  test "updates events list when a new event is broadcasted", %{conn: conn, kitt: kitt} do
    {:ok, view, html} = live(conn, ~p"/kitt-web")

    refute html =~ "New Message from Test"

    # Simulate an event creation elsewhere
    event_params = %KittAgent.Datasets.Event{
      role: "user",
      content: %KittAgent.Datasets.Content{
        action: "Talk",
        parameters: "none",
        timestamp: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        target: kitt.name,
        message: "New Message from Test"
      }
    }

    # This triggers the broadcast
    Events.create_event(kitt, event_params)

    # Verify the view updates
    assert render(view) =~ "New Message from Test"
  end
end
