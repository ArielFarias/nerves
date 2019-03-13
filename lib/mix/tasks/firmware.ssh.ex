defmodule Mix.Tasks.Firmware.Ssh do
  use Mix.Task

  @shortdoc "Build a firmware bundle and write it to an SDCard"

  @moduledoc """
  This task calls `mix firmware.ssh`
  """

  @impl true
  def run(args) do
    Mix.Task.run("ssh", args)
  end
end
