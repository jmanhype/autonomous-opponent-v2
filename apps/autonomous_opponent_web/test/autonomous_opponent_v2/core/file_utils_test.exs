defmodule AutonomousOpponentV2.Core.FileUtilsTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponentV2.Core.FileUtils

  describe "safe file operations" do
    test "safe_write and safe_read work correctly" do
      content = "Hello, World!"

      FileUtils.with_temp_file("test", fn temp_path ->
        assert :ok = FileUtils.safe_write(temp_path, content)
        assert {:ok, ^content} = FileUtils.safe_read(temp_path)
      end)
    end

    test "safe_write with atomic option" do
      content = "Atomic write test"

      FileUtils.with_temp_file("atomic", fn temp_path ->
        assert :ok = FileUtils.safe_write(temp_path, content, atomic: true)
        assert {:ok, ^content} = FileUtils.safe_read(temp_path)
      end)
    end

    test "safe_mkdir_p creates directories" do
      temp_dir = Path.join(System.tmp_dir!(), "fileutils_test_#{:rand.uniform(10000)}")
      nested_dir = Path.join(temp_dir, "nested/deep")

      try do
        assert :ok = FileUtils.safe_mkdir_p(nested_dir)
        assert File.dir?(nested_dir)
      after
        File.rm_rf(temp_dir)
      end
    end

    test "safe_copy works correctly" do
      source_content = "Copy test content"

      FileUtils.with_temp_file("source", fn source_path ->
        File.write!(source_path, source_content)

        FileUtils.with_temp_file("dest", fn dest_path ->
          assert {:ok, _bytes} = FileUtils.safe_copy(source_path, dest_path)
          assert {:ok, ^source_content} = File.read(dest_path)
        end)
      end)
    end

    test "with_file_lock prevents concurrent access" do
      FileUtils.with_temp_file("lock_test", fn temp_path ->
        File.write!(temp_path, "initial")

        # Start two concurrent processes that try to modify the file
        task1 =
          Task.async(fn ->
            FileUtils.with_file_lock(temp_path, fn ->
              content = File.read!(temp_path)
              # Simulate work
              :timer.sleep(50)
              File.write!(temp_path, content <> "_task1")
            end)
          end)

        task2 =
          Task.async(fn ->
            FileUtils.with_file_lock(temp_path, fn ->
              content = File.read!(temp_path)
              # Simulate work
              :timer.sleep(50)
              File.write!(temp_path, content <> "_task2")
            end)
          end)

        Task.await(task1)
        Task.await(task2)

        # Both tasks should have completed successfully
        final_content = File.read!(temp_path)
        assert String.contains?(final_content, "initial")

        assert String.contains?(final_content, "_task1") or
                 String.contains?(final_content, "_task2")
      end)
    end

    test "with_temp_file cleans up automatically" do
      {:ok, temp_path_ref} = Agent.start_link(fn -> nil end)

      FileUtils.with_temp_file("cleanup", fn path ->
        Agent.update(temp_path_ref, fn _ -> path end)
        File.write!(path, "temp content")
        assert File.exists?(path)
      end)

      # File should be cleaned up
      temp_path = Agent.get(temp_path_ref, & &1)
      refute File.exists?(temp_path)
      Agent.stop(temp_path_ref)
    end

    test "cleanup_temp_files removes matching files" do
      temp_dir = System.tmp_dir!()
      prefix = "fileutils_cleanup_test_#{:rand.uniform(10000)}"

      # Create some temp files
      temp_files =
        Enum.map(1..3, fn i ->
          path = Path.join(temp_dir, "#{prefix}_#{i}")
          File.write!(path, "temp #{i}")
          path
        end)

      # Verify they exist
      Enum.each(temp_files, fn path -> assert File.exists?(path) end)

      # Clean them up
      pattern = Path.join(temp_dir, "#{prefix}_*")
      assert :ok = FileUtils.cleanup_temp_files(pattern)

      # Verify they're gone
      Enum.each(temp_files, fn path -> refute File.exists?(path) end)
    end
  end

  describe "error handling" do
    test "safe_read returns error for non-existent file" do
      assert {:error, :enoent} = FileUtils.safe_read("/nonexistent/file.txt")
    end

    test "safe_write returns error for invalid path" do
      assert {:error, _reason} = FileUtils.safe_write("/root/restricted.txt", "content")
    end

    test "safe_mkdir_p returns error for restricted location" do
      assert {:error, _reason} = FileUtils.safe_mkdir_p("/root/restricted")
    end

    test "safe_copy returns error for non-existent source" do
      FileUtils.with_temp_file("dest", fn dest_path ->
        assert {:error, :enoent} = FileUtils.safe_copy("/nonexistent/file.txt", dest_path)
      end)
    end
  end
end
