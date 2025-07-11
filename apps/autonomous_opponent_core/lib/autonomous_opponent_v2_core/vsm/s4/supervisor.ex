defmodule AutonomousOpponentV2Core.VSM.S4.Supervisor do
  @moduledoc """
  Supervisor for S4 Intelligence subsystem components.
  
  Manages:
  - Pattern HNSW Bridge for event pattern indexing
  - HNSW Index for vector similarity search
  - Pattern Indexer for transforming patterns to vectors
  """
  
  use Supervisor
  require Logger
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # HNSW Index - must start first
      {AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex,
        name: :hnsw_index,
        m: 16,
        ef: 200,
        distance_metric: :cosine,
        persist: true
      },
      
      # Pattern Indexer
      {AutonomousOpponentV2Core.VSM.S4.VectorStore.PatternIndexer,
        name: AutonomousOpponentV2Core.VSM.S4.PatternIndexer,
        hnsw_server: :hnsw_index,
        vector_dimensions: 100
      },
      
      # Pattern HNSW Bridge - connects EventBus to HNSW
      {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge,
        hnsw_name: :hnsw_index,
        indexer_name: AutonomousOpponentV2Core.VSM.S4.PatternIndexer
      }
    ]
    
    opts = [
      strategy: :one_for_all,  # If one dies, restart all
      max_restarts: 3,
      max_seconds: 5
    ]
    
    Logger.info("🧠 S4 Supervisor starting HNSW components for pattern intelligence")
    
    Supervisor.init(children, opts)
  end
end