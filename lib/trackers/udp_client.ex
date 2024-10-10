defmodule Trackers.UdpClient do
  @type ip :: {pos_integer(), pos_integer(), pos_integer(), pos_integer()}

  @callback send_announce_message(message :: binary(), ip :: ip(), port :: pos_integer()) ::
              pos_integer()
end
