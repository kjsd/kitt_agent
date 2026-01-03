defmodule KittAgent.EventsTest do
  use KittAgent.DataCase

  alias KittAgent.Events
  alias KittAgent.Datasets.Event

  describe "events" do
    setup do
      {:ok, kitt} =
        KittAgent.Kitts.create_kitt(%{
          name: "TestKitt",
          biography: %{
            vendor: "openai",
            model: "gpt-3.5-turbo",
            personality: "test"
          }
        })

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
          listener: "TestKitt",
          message: "Hello",
          mood: "neutral",
          status: "completed"
        }
      }

      {:ok, ev} = Events.create_kitt_event(event_params, kitt)

      assert ev.content.message == "Hello"

      assert_receive {[:event, :created], ^ev}
    end

    test "create_kitt_event!/2 creates an event and broadcasts it", %{kitt: kitt} do
      Events.subscribe()

      content_attrs = %{
        "action" => "Talk",
        "listener" => "User",
        "message" => "Meow",
        "mood" => "happy"
      }

      {:ok, ev} = Events.create_kitt_event(Events.make_kitt_event(content_attrs), kitt)

      assert ev.content.message == "Meow"

      assert_receive {[:event, :created], ^ev}
    end

    test "delete_events/1 deletes specified events", %{kitt: kitt} do
      {:ok, ev1} = Events.create_kitt_event(Events.make_user_talk_event("msg1"), kitt)
      {:ok, ev2} = Events.create_kitt_event(Events.make_user_talk_event("msg2"), kitt)
      {:ok, ev3} = Events.create_kitt_event(Events.make_user_talk_event("msg3"), kitt)

      Events.delete_events([ev1.id, ev3.id])

      remaining_events = Events.recents(kitt)
      remaining_ids = Enum.map(remaining_events, & &1.id)

      assert ev2.id in remaining_ids
      refute ev1.id in remaining_ids
      refute ev3.id in remaining_ids
    end
  end
end
