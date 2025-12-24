defmodule KittAgent.EventsTest do
  use KittAgent.DataCase

  alias KittAgent.Events
  alias KittAgent.Datasets.{Kitt, Event}

  describe "events" do
    setup do
      kitt =
        %Kitt{name: "TestKitt", vendor: "openai", model: "gpt-3.5-turbo"}
        |> KittAgent.Repo.insert!()

      %{kitt: kitt}
    end

    test "subscribe/0 subscribes to events topic" do
      Events.subscribe()
      # No error means subscription was successful (basic check)
      # To verify, we can check if we receive messages after broadcasting (tested below)
    end

    test "create_event!/2 creates an event and broadcasts it", %{kitt: kitt} do
      Events.subscribe()

      event_params = %Event{
        role: "user",
        content: %KittAgent.Datasets.Content{
          action: "Talk",
          parameters: "none",
          timestamp: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          target: "TestKitt",
          message: "Hello"
        }
      }

      {:ok, ev} = Events.create_event(kitt, event_params)

      assert ev.content.message == "Hello"

      assert_receive {[:event, :created], ^ev}
    end

    test "create_kitt_event!/2 creates an event and broadcasts it", %{kitt: kitt} do
      Events.subscribe()

      content_attrs = %{
        "action" => "Reply",
        "parameters" => "none",
        "target" => "User",
        "message" => "Meow"
      }

      {:ok, ev} = Events.create_kitt_event(kitt, content_attrs)

      assert ev.content.message == "Meow"

      assert_receive {[:event, :created], ^ev}
    end

    test "delete_events/1 deletes specified events", %{kitt: kitt} do
      {:ok, ev1} = Events.create_event(kitt, Events.make_talk_event(kitt, "msg1"))
      {:ok, ev2} = Events.create_event(kitt, Events.make_talk_event(kitt, "msg2"))
      {:ok, ev3} = Events.create_event(kitt, Events.make_talk_event(kitt, "msg3"))

      assert {2, _} = Events.delete_events([ev1.id, ev3.id])

      remaining_events = Events.recents(kitt)
      remaining_ids = Enum.map(remaining_events, & &1.id)

      assert ev2.id in remaining_ids
      refute ev1.id in remaining_ids
      refute ev3.id in remaining_ids
    end
  end
end
