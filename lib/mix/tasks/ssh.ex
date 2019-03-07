defmodule Mix.Tasks.Ssh do
  use Mix.Task
  import Mix.Nerves.Utils

  @shortdoc "Write a firmware image to an SDCard"

  @mount System.find_executable("mount")
  @bash System.find_executable("bash")
  @fixsd System.find_executable("e2fsck")

  @moduledoc """
  Generate an SSH keypair and store in a file on the SDCard.

  ## Examples

  ```
  # Upgrade the contents of the SDCard located at /dev/mmcblk0
  mix burn --device /dev/mmcblk0 --task upgrade
  ```
  """

  @impl true
  def run(_argv) do
    preflight()
    debug_info("SSH Generate")
    partition_name = get_partition_name()

    {:ok, keypair} = RsaEx.generate_keypair("4096")
    ssh(keypair, partition_name)
  end

  defp ssh({priv, pub}, part_name) do
    ask_pass = System.get_env("SUDO_ASKPASS") || "/usr/bin/ssh-askpass"
    System.put_env("SUDO_ASKPASS", ask_pass)

    part_name
    |> Path.basename()
    |> get_partition_info()
    |> case do
      [] -> Mix.raise("SD card not found")
      {_any, nil} ->
        setup_sdcard(priv, pub, part_name)
      {_any, mountpoint} -> generate_ssh_pair(priv, pub, mountpoint)
    end
  end

  defp setup_sdcard(priv, pub, part_name) do
    home = System.user_home!() |> Path.basename()
    device_name = part_name |> Path.basename

    part_path = "/media/#{home}"

    IO.puts "Fix SD card..."
    shell("sudo", [@fixsd, "-y", "/dev/#{device_name}"])

    IO.puts "Mount SD card..."
    shell("sudo", [@mount, "/dev/#{device_name}", part_path, "-t", "ext4"])

    {_uuid, mountpoint} =
      part_name
      |> Path.basename()
      |> get_partition_info()

    generate_ssh_pair(priv, pub, mountpoint)
  end

  defp generate_ssh_pair(priv, pub, mountpoint) do
    IO.puts "Generating SSH pair..."
    pbkey = System.get_env("PBKEY") || pub

    args = [@bash] ++ ["-c"] ++ ["echo \"#{pbkey}\" > #{mountpoint}/pub_key.txt"]

    shell("sudo", args)

    pkey = System.get_env("PKEY") || priv

    args = [@bash] ++ ["-c"] ++ ["echo  \"#{pkey} \" > #{mountpoint}/priv_key.txt"]

    shell("sudo", args)
  end

  defp get_partition_info(basename) do
    {result, _code} = System.cmd("lsblk", ["--include", "8", "--list", "-J", "-o", "UUID,NAME,MOUNTPOINT"])

    if result == "" do
      Mix.raise("Could not auto detect your SD card partition to mount")
    end

    result
    |> Jason.decode!()
    |> Kernel.get_in(["blockdevices"])
    |> Enum.reduce([], fn device, acc ->
      device
      |> Kernel.get_in(["name"])
      |> String.equivalent?(basename)
      |> case do
        true ->
          uuid = Kernel.get_in(device, ["uuid"])
          mountpoint = Kernel.get_in(device, ["mountpoint"])
          acc ++ {uuid, mountpoint}
        false -> acc
      end
    end)
  end

  defp get_partition_name() do
    {result, _code} = System.cmd("lsblk", ["--all", "--list", "-J"])

    if result == "" do
      Mix.raise("Could not auto detect your SD card partition to mount")
    end

    result
    |> Jason.decode!()
    |> Kernel.get_in(["blockdevices"])
    |> Enum.reduce([], fn device, acc ->
      device
      |> Kernel.get_in(["rm"])
      |> is_one?()
      |> case do
        true ->
          device
          |> Kernel.get_in(["size"])
          |> is_512M?()
          |> case do
            true -> acc ++ ["/dev/" <> Kernel.get_in(device, ["name"])]
            false -> acc
          end
        false -> acc
      end
    end)
  end

  defp is_one?("1"), do: true
  defp is_one?(_any), do: false

  defp is_512M?("512M"), do: true
  defp is_512M?(_any), do: false

  # This is a fix for linux when running through sudo.
  # Sudo will strip the environment and therefore any variables
  # that are set during device provisioning.
  @doc false
  def provision_env() do
    System.get_env()
    |> Enum.filter(fn {k, _} ->
      String.starts_with?(k, "NERVES_") or String.equivalent?(k, "SERIAL_NUMBER")
    end)
    |> Enum.map(fn {k, v} -> k <> "=" <> v end)
  end
end
