defmodule KittAgent.SystemActionsTest do
  use KittAgent.DataCase

  alias KittAgent.SystemActions.Queue
  alias KittAgent.Kitts

  describe "system action queue" do
    setup do
      {:ok, kitt} =
        Kitts.create_kitt(%{name: "Test Kitt", lang: "Japanese", timezone: "Asia/Tokyo"})

      %{kitt: kitt}
    end

    test "can enqueue actions", %{kitt: kitt} do
      actions = [
        %{action: "test_action", parameter: "param", target: "target"}
      ]

      # enqueue自体が成功することを確認
      assert :ok = Queue.enqueue(kitt.id, actions)

      # Queueの中身を確認
      assert ^actions = Queue.dequeue(kitt.id)

      # もう一度dequeueするとnilになるはず（中身が空だから）
      assert nil == Queue.dequeue(kitt.id)
    end

    test "terminates queue when requested", %{kitt: kitt} do
      Queue.enqueue(kitt.id, [])

      # プロセスが存在することを確認（dequeueがエラーにならなければOK）
      assert [] = Queue.dequeue(kitt.id)

      Queue.terminate(kitt.id)

      # プロセスが終了していることを確認（dequeueがnilを返すはず）
      # Rpcsdk.Queueのdequeueはtry-catchで:exitを捕捉してnilを返す実装になっているため
      assert nil == Queue.dequeue(kitt.id)
    end
  end
end
