defmodule AutonomousOpponentV2.Core.FileUtils do
  @moduledoc """
  Safe file operations with proper error handling and locking support.
  """

  require Logger

  def safe_read(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, content}
      {:error, reason} ->
        Logger.debug("Failed to read file #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def safe_write(path, content, opts \\ []) do
    atomic = Keyword.get(opts, :atomic, true)
    lock = Keyword.get(opts, :lock, false)
    mode = Keyword.get(opts, :mode, [:write])

    if atomic do
      atomic_write(path, content, mode, lock)
    else
      direct_write(path, content, mode, lock)
    end
  end

  def safe_mkdir_p(path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.warning("Failed to create directory #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def safe_copy(source, destination, opts \\ []) do
    create_dirs = Keyword.get(opts, :create_dirs, true)

    if create_dirs do
      case safe_mkdir_p(Path.dirname(destination)) do
        :ok -> do_copy(source, destination, opts)
        error -> error
      end
    else
      do_copy(source, destination, opts)
    end
  end

  def with_file_lock(path, fun, timeout \\ 5000) do
    lock_path = path <> ".lock"

    case acquire_lock(lock_path, timeout) do
      {:ok, lock_file} ->
        try do
          result = fun.()
          {:ok, result}
        after
          release_lock(lock_file, lock_path)
        end
      {:error, reason} ->
        {:error, {:lock_failed, reason}}
    end
  end

  def with_temp_file(prefix \\ "autonomous_opponent_v2", fun) do
    temp_path = generate_temp_path(prefix)

    try do
      result = fun.(temp_path)
      {:ok, result}
    after
      cleanup_temp_file(temp_path)
    end
  end

  def cleanup_temp_files(pattern) do
    try do
      pattern
      |> Path.wildcard()
      |> Enum.each(fn path ->
        case File.rm(path) do
          :ok -> Logger.debug("Cleaned up temp file: #{path}")
          {:error, reason} -> Logger.warning("Failed to cleanup #{path}: #{inspect(reason)}")
        end
      end)
      :ok
    rescue
      error ->
        Logger.error("Error during temp file cleanup: #{inspect(error)}")
        {:error, error}
    end
  end

  defp atomic_write(path, content, mode, use_lock) do
    temp_path = path <> ".tmp." <> random_suffix()

    operation = fn ->
      case File.write(temp_path, content, mode) do
        :ok ->
          case File.rename(temp_path, path) do
            :ok ->
              :ok
            {:error, reason} ->
              File.rm(temp_path)
              {:error, reason}
          end
        error ->
          error
      end
    end

    if use_lock do
      case with_file_lock(path, operation) do
        {:ok, result} -> result
        {:error, {_lock_error, reason}} -> {:error, reason}
      end
    else
      operation.()
    end
  end

  defp direct_write(path, content, mode, use_lock) do
    operation = fn ->
      File.write(path, content, mode)
    end

    if use_lock do
      case with_file_lock(path, operation) do
        {:ok, result} -> result
        {:error, {_lock_error, reason}} -> {:error, reason}
      end
    else
      operation.()
    end
  end

  defp do_copy(source, destination, opts) do
    case File.copy(source, destination) do
      {:ok, bytes} ->
        if Keyword.get(opts, :preserve_timestamps, false) do
          preserve_timestamps(source, destination)
        end
        {:ok, bytes}
      {:error, reason} ->
        Logger.warning("Failed to copy #{source} to #{destination}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp preserve_timestamps(source, destination) do
    case File.stat(source) do
      {:ok, %File.Stat{mtime: mtime}} ->
        File.touch(destination, mtime)
      {:error, _reason} ->
        :ok
    end
  end

  defp acquire_lock(lock_path, timeout) do
    end_time = System.monotonic_time(:millisecond) + timeout
    do_acquire_lock(lock_path, end_time)
  end

  defp do_acquire_lock(lock_path, end_time) do
    case File.open(lock_path, [:write, :exclusive]) do
      {:ok, file} ->
        IO.write(file, "#{:os.getpid()}")
        {:ok, file}
      {:error, :eexist} ->
        if System.monotonic_time(:millisecond) < end_time do
          :timer.sleep(10)
          do_acquire_lock(lock_path, end_time)
        else
          {:error, :timeout}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp release_lock(file, lock_path) do
    File.close(file)
    File.rm(lock_path)
  end

  defp generate_temp_path(prefix) do
    timestamp = System.system_time(:nanosecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    Path.join(System.tmp_dir!(), "#{prefix}_#{timestamp}_#{random}")
  end

  defp cleanup_temp_file(path) do
    case File.rm(path) do
      :ok ->
        :ok
      {:error, :enoent} ->
        :ok
      {:error, reason} ->
        Logger.warning("Failed to cleanup temp file #{path}: #{inspect(reason)}")
    end
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
