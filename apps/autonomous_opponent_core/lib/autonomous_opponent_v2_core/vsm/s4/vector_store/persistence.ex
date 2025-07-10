defmodule AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence do
  @moduledoc """
  Persistence layer for HNSW vector index.
  
  Handles saving and loading the index to/from disk using Erlang Term Storage (ETS)
  disk format. This enables the S4 subsystem to maintain its pattern library
  across restarts.
  
  ## Wisdom Preservation
  
  ### Why Persistence Matters for S4
  S4's value comes from accumulated patterns over time. Without persistence,
  every restart means starting from scratch - no learned patterns, no historical
  context. This module ensures S4's "memory" survives process restarts.
  
  ### Design Decisions
  
  1. **ETS disk format**: Native Erlang format, fast and reliable. No need
     for JSON/Protocol Buffers overhead since we're Elixir-only.
     
  2. **Atomic writes**: Uses temporary file + rename to prevent corruption
     if save is interrupted. Better to have old data than corrupted data.
     
  3. **Versioned format**: Includes version number for future migration.
     S4 patterns will evolve; the storage format must handle upgrades.
  """
  
  require Logger
  
  # WISDOM: Index version for future migration support
  # Increment this when breaking changes are made to the index format
  @index_version 2
  @current_version 1  # Legacy support
  
  @doc """
  Saves HNSW index state to disk.
  
  Returns :ok on success, {:error, reason} on failure.
  """
  def save_index(path, state) do
    # Ensure directory exists
    :ok = File.mkdir_p(Path.dirname(path))
    
    # Create persistence data structure
    persistence_data = %{
      version: @index_version,
      legacy_version: @current_version,  # For backwards compatibility
      timestamp: DateTime.utc_now(),
      index_state: extract_index_state(state),
      metadata: %{
        node_count: state.node_count,
        m: state.m,
        ef: state.ef,
        distance_metric: detect_distance_metric(state.distance_fn),
        index_version: @index_version,
        features: [:telemetry, :batch_search, :pattern_expiry, :compaction]
      }
    }
    
    # Save to temporary file first (atomic write)
    temp_path = path <> ".tmp"
    
    try do
      # Save ETS tables
      save_ets_table(state.graph, graph_path(path))
      save_ets_table(state.data_table, data_path(path))
      save_ets_table(state.level_table, level_path(path))
      
      # Save metadata
      binary = :erlang.term_to_binary(persistence_data)
      File.write!(temp_path, binary)
      
      # Atomic rename
      File.rename!(temp_path, path)
      
      Logger.info("HNSW index saved to #{path} (#{state.node_count} nodes)")
      :ok
    rescue
      error ->
        # Clean up temporary file if exists
        File.rm(temp_path)
        Logger.error("Failed to save HNSW index: #{inspect(error)}")
        {:error, error}
    end
  end
  
  @doc """
  Loads HNSW index state from disk.
  
  Returns {:ok, state} on success, {:error, reason} on failure.
  """
  def load_index(path) do
    if File.exists?(path) do
      try do
        # Load metadata
        binary = File.read!(path)
        persistence_data = :erlang.binary_to_term(binary)
        
        # Version check and migration - handle both Map and Keyword list formats
        index_version = cond do
          is_map(persistence_data) -> persistence_data[:version] || persistence_data[:legacy_version] || 1
          Keyword.keyword?(persistence_data) -> Keyword.get(persistence_data, :version, Keyword.get(persistence_data, :legacy_version, 1))
          true -> 1
        end
        
        cond do
          index_version > @index_version ->
            {:error, {:unsupported_version, index_version}}
            
          index_version < @index_version ->
            # Perform migration
            Logger.info("Migrating index from version #{index_version} to #{@index_version}")
            migrated_data = migrate_index_data(persistence_data, index_version)
            load_migrated_index(migrated_data, path)
            
          true ->
            # Same version, load directly
            load_current_version_index(persistence_data, path)
        end
      rescue
        error ->
          Logger.error("Failed to load HNSW index: #{inspect(error)}")
          {:error, error}
      end
    else
      {:error, :file_not_found}
    end
  end
  
  @doc """
  Checks if an index file exists and is valid.
  """
  def index_exists?(path) do
    File.exists?(path) and 
    File.exists?(graph_path(path)) and
    File.exists?(data_path(path)) and
    File.exists?(level_path(path))
  end
  
  @doc """
  Removes index files from disk.
  """
  def delete_index(path) do
    files = [
      path,
      graph_path(path),
      data_path(path),
      level_path(path)
    ]
    
    Enum.each(files, &File.rm/1)
    :ok
  end
  
  @doc """
  Returns information about a persisted index without loading it.
  """
  def index_info(path) do
    if File.exists?(path) do
      try do
        binary = File.read!(path)
        persistence_data = :erlang.binary_to_term(binary)
        
        index_version = persistence_data[:version] || persistence_data[:legacy_version] || 1
        
        {:ok, %{
          version: index_version,
          saved_at: persistence_data.timestamp,
          node_count: persistence_data.metadata.node_count,
          parameters: Map.take(persistence_data.metadata, [:m, :ef, :distance_metric]),
          features: persistence_data.metadata[:features] || [],
          needs_migration: index_version < @index_version
        }}
      rescue
        _ -> {:error, :invalid_format}
      end
    else
      {:error, :file_not_found}
    end
  end
  
  # Private functions
  
  defp extract_index_state(state) do
    # Extract serializable parts of state
    Map.take(state, [
      :m, :max_m, :max_m0, :ef, :ef_construction,
      :ml, :entry_point, :node_count
    ])
  end
  
  defp save_ets_table(table, path) do
    :ets.tab2file(table, String.to_charlist(path))
  end
  
  defp load_ets_table(table, path) do
    case :ets.file2tab(String.to_charlist(path), [{:verify, true}]) do
      {:ok, loaded_table} ->
        try do
          # Copy data from loaded table to our table
          :ets.foldl(
            fn item, acc ->
              :ets.insert(table, item)
              acc
            end,
            :ok,
            loaded_table
          )
          # Delete the temporary loaded table
          :ets.delete(loaded_table)
          :ok
        rescue
          e ->
            # Ensure cleanup even if copying fails
            :ets.delete(loaded_table)
            {:error, {:copy_failed, e}}
        end
      
      {:error, _} = error ->
        error
    end
  end
  
  defp graph_path(base_path), do: base_path <> ".graph"
  defp data_path(base_path), do: base_path <> ".data"
  defp level_path(base_path), do: base_path <> ".levels"
  
  defp detect_distance_metric(distance_fn) do
    # Simple heuristic to detect metric type
    # Test with known vectors
    v1 = [1.0, 0.0]
    v2 = [0.0, 1.0]
    
    dist = distance_fn.(v1, v2)
    
    # Euclidean distance would be sqrt(2) ≈ 1.414
    # Cosine distance would be 1.0 (orthogonal vectors)
    if abs(dist - 1.0) < 0.01 do
      :cosine
    else
      :euclidean
    end
  end
  
  defp get_distance_function(:cosine) do
    &AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.cosine_distance/2
  end
  
  defp get_distance_function(:euclidean) do
    &AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.euclidean_distance/2
  end
  
  # WISDOM: Version migration ensures forward compatibility
  # Old indexes can be upgraded to use new features
  defp migrate_index_data(data, from_version) do
    case from_version do
      1 ->
        # Migration from v1 to v2
        # Add new fields that didn't exist in v1
        Map.merge(data, %{
          version: @index_version,
          metadata: Map.merge(data.metadata, %{
            index_version: @index_version,
            features: [:telemetry, :batch_search, :pattern_expiry, :compaction]
          })
        })
        
      _ ->
        # Unknown version, try to load anyway
        data
    end
  end
  
  defp load_current_version_index(persistence_data, path) do
    # Create new ETS tables
    graph = :ets.new(:hnsw_graph_loaded, [:set, :protected])
    data_table = :ets.new(:hnsw_data_loaded, [:set, :protected])
    level_table = :ets.new(:hnsw_levels_loaded, [:set, :protected])
    
    # Load ETS data with error handling
    with :ok <- load_ets_table(graph, graph_path(path)),
         :ok <- load_ets_table(data_table, data_path(path)),
         :ok <- load_ets_table(level_table, level_path(path)) do
      
      # Add timestamps to metadata if missing (for pattern expiry)
      maybe_add_timestamps(data_table)
      
      # Reconstruct state
      state = Map.merge(persistence_data.index_state, %{
        graph: graph,
        data_table: data_table,
        level_table: level_table,
        distance_fn: get_distance_function(persistence_data.metadata.distance_metric)
      })
      
      Logger.info("HNSW index loaded from #{path} (#{state.node_count} nodes, v#{@index_version})")
      {:ok, state}
    else
      {:error, reason} = error ->
        # Clean up tables on error
        :ets.delete(graph)
        :ets.delete(data_table)
        :ets.delete(level_table)
        Logger.error("Failed to load ETS tables: #{inspect(reason)}")
        error
    end
  end
  
  defp load_migrated_index(migrated_data, path) do
    load_current_version_index(migrated_data, path)
  end
  
  defp maybe_add_timestamps(data_table) do
    # Add timestamps to patterns that don't have them
    now = DateTime.utc_now()
    
    :ets.foldl(
      fn {node_id, vector, metadata}, _acc ->
        if not Map.has_key?(metadata, :inserted_at) do
          updated_metadata = Map.put(metadata, :inserted_at, now)
          :ets.insert(data_table, {node_id, vector, updated_metadata})
        end
      end,
      nil,
      data_table
    )
  end
end