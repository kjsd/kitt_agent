defmodule KittAgentWeb.HomeLiveTest do
  use KittAgentWeb.ConnCase

  import Phoenix.LiveViewTest
  alias KittAgent.Events

  setup do
    {:ok, kitt} =
      KittAgent.Kitts.create_kitt(%{
        name: "DashboardKitt",
        biography: %{vendor: "openai", model: "gpt-4", personality: "test"}
      })

    %{kitt: kitt}
  end

  test "connected mount subscribes to events", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/kitt-web")
    # Checking subscription indirectly via behavior or internal state is hard from outside.
    # But we can verify if the view updates when an event is broadcasted.
  end

  test "updates events list when a new event is broadcasted", %{conn: conn, kitt: kitt} do
    {:ok, view, html} = live(conn, ~p"/kitt-web")

    # Select the test kitt explicitly to ensure we are watching it
    view
    |> element("form select[name=id]")
    |> render_change(%{"id" => to_string(kitt.id)})

    refute html =~ "New Message from Test"

    # Simulate an event creation elsewhere
    event_params = %KittAgent.Datasets.Event{
      role: "user",
      content: %KittAgent.Datasets.Content{
        action: "Talk",
        listener: kitt.name,
        message: "New Message from Test",
        mood: "neutral",
        status: "completed"
      }
    }

    # This triggers the broadcast
    Events.create_kitt_event(event_params, kitt)

    # Verify the view updates
    assert render(view) =~ "New Message from Test"
  end

  test "switches kitt and updates recent transactions", %{conn: conn, kitt: kitt1} do
    # Create another kitt
    {:ok, kitt2} =
      KittAgent.Kitts.create_kitt(%{
        name: "OtherKitt",
        biography: %{vendor: "openai", model: "gpt-3.5-turbo", personality: "test"}
      })

    # Create events for both
    Events.create_kitt_event(
      %KittAgent.Datasets.Event{
        role: "user",
        content: %KittAgent.Datasets.Content{
          action: "Talk",
          listener: kitt1.name,
          message: "Message for Kitt 1",
          mood: "neutral",
          status: "completed"
        }
      },
      kitt1
    )

    Events.create_kitt_event(
      %KittAgent.Datasets.Event{
        role: "user",
        content: %KittAgent.Datasets.Content{
          action: "Talk",
          listener: kitt2.name,
          message: "Message for Kitt 2",
          mood: "neutral",
          status: "completed"
        }
      },
      kitt2
    )

    {:ok, view, _html} = live(conn, ~p"/kitt-web")

    # Explicitly select kitt1
    view
    |> element("form select[name=id]")
    |> render_change(%{"id" => to_string(kitt1.id)})

    # Check if kitt1's message is visible and kitt2's is not
    output = render(view)
    assert output =~ "Message for Kitt 1"
    refute output =~ "Message for Kitt 2"

    # Change the select value to kitt2
    view
    |> element("form select[name=id]")
    |> render_change(%{"id" => to_string(kitt2.id)})

    # Now kitt2's message should be visible
    output = render(view)
    assert output =~ "Message for Kitt 2"
    refute output =~ "Message for Kitt 1"
  end
end
