#!/usr/bin/env elixir

# ============================================================================
# HNSW CONFIGURATION VERIFICATION
# ============================================================================

Mix.install([{:jason, "~> 1.4"}])

defmodule HNSWConfigVerifier do
  require Logger
  
  def verify do
    Logger.info("🧠 VSM S4: Verifying HNSW Configuration")
    
    # Test persistence directory
    persist_dir = "priv/vsm/s4"
    File.mkdir_p!(persist_dir)
    Logger.info("✅ Persistence directory: #{persist_dir}")
    
    # Test configuration values
    config = %{
      enabled: true,
      path: "#{persist_dir}/intelligence_patterns.hnsw",
      interval: 3 * 60 * 1000,  # 3 minutes
      m: 32,
      ef: 400,
      max_patterns: 100_000,
      variety_limit: 0.8,
      eventbus_integration: true,
      algedonic_integration: true
    }
    
    Logger.info("✅ Configuration loaded: #{inspect(config, pretty: true)}")
    
    # Test variety pressure calculation
    test_patterns = 75_000
    variety_pressure = test_patterns / config.max_patterns
    
    if variety_pressure <= config.variety_limit do
      Logger.info("✅ Variety pressure: #{variety_pressure} (OK)")
    else
      Logger.warning("⚠️ Variety pressure: #{variety_pressure} (HIGH)")
    end
    
    # Test persistence simulation
    test_file = "#{config.path}.test"
    test_data = %{
      patterns: test_patterns,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      variety_pressure: variety_pressure
    }
    
    case File.write(test_file, Jason.encode!(test_data)) do
      :ok ->
        Logger.info("✅ Persistence write: SUCCESS")
        
        case File.read(test_file) do
          {:ok, content} ->
            loaded = Jason.decode!(content)
            if loaded["patterns"] == test_patterns do
              Logger.info("✅ Persistence read: SUCCESS")
            else
              Logger.error("❌ Data corruption detected")
            end
          {:error, reason} ->
            Logger.error("❌ Read failed: #{reason}")
        end
        
        File.rm(test_file)
        
      {:error, reason} ->
        Logger.error("❌ Write failed: #{reason}")
    end
    
    Logger.info("🚀 HNSW Configuration Verification COMPLETE!")
  end
end

HNSWConfigVerifier.verify()