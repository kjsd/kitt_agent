defmodule KittAgent.TTS.RequestBroker do
  use Rpcsdk.RequestBroker,
    supervisor: KittAgent.TTS.Supervisor,
    registry: KittAgent.TTS.Registry

  alias KittAgent.Datasets.Kitt
  alias KittAgent.Kitts

  def exec(%Kitt{id: id}, text), do: cast_stub(:exec, id, [text])
  
  @impl Rpcsdk.RequestBroker
  def get_key(%Kitt{id: id}), do: id

  @impl true
  def handle_cast({:exec, id, text}, s) do
    with %Kitt{lang: lang} <- Kitts.get_kitt(id) do
    end
    
    {:noreply, s}
  end

end
