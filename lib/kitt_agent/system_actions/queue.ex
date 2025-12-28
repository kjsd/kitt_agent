defmodule KittAgent.SystemActions.Queue do
  use Rpcsdk.Queue,
    supervisor: KittAgent.SystemActions.Supervisor,
    registry: KittAgent.SystemActions.Registry
end
