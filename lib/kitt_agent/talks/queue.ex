defmodule KittAgent.Talks.Queue do
  use Rpcsdk.Queue,
    supervisor: KittAgent.Talks.Supervisor,
    registry: KittAgent.Talks.Registry
end
