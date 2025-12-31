defmodule KittAgent.TTS.RequestBroker do
  use Rpcsdk.RequestBroker,
    supervisor: KittAgent.TTS.Supervisor,
    registry: KittAgent.TTS.Registry

  alias KittAgent.Datasets.{Kitt, Content}
  alias KittAgent.Events
  alias KittAgent.Requests

  require Logger
  
  def exec(%Kitt{} = kitt, %Content{id: id}), do: cast_stub(:exec, kitt, [id])
  
  @impl Rpcsdk.RequestBroker
  def get_key(%Kitt{id: id}), do: id

  @impl true
  def handle_cast({:exec, kitt, id}, s) do
    # Reload content to ensure we have latest state and associations
    with %Content{} = c <- Events.get_content(id) do
        Requests.process_tts(c, kitt)
    else
      _ ->
        Logger.error("TTS: Content #{id} not found.")
    end
    
    {:noreply, s}
  end

end
