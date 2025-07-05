defmodule AutonomousOpponentV2Core.AMCP.Message do
  @moduledoc """
  Defines the Advanced Model Context Protocol (aMCP) message structure.
  
  aMCP extends standard messaging with semantic context fusion, enabling AI agents
  to understand not just the data but its meaning, intent, and contextual relationships.
  This implementation follows the aMCP whitepaper specification for cybernetic intelligence.

  **Semantic Context Fusion:** Each message carries semantic metadata that enables
  intelligent routing, content-addressable storage, and cross-domain meaning transfer.
  
  **Design Principle #7:** Message IDs are content-based hashes to prevent race conditions
  and ensure deterministic identification across the distributed system.
  
  **aMCP Extensions:**
  - Semantic embeddings for content-addressable intelligence
  - Intent classification for intelligent routing
  - Priority and urgency for variety management
  - Provenance tracking for causal lineage
  - Context preservation across subsystem boundaries
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # Core aMCP fields
    field :id, :binary_id, primary_key: true # Content-based hash (CID-compatible)
    field :type, :string
    field :sender, :string
    field :recipient, :string
    field :payload, :map
    field :timestamp, :utc_datetime
    field :signature, :string
    
    # Semantic Context Fusion fields
    field :semantic_context, :map
    field :context, :map, default: %{}
    field :intent, :string
    field :priority, :string, default: "medium"
    field :urgency, :float, default: 0.5
    field :embedding, {:array, :float}
    field :provenance, :map
    field :variety_metrics, :map
    field :algedonic_valence, :float
    
    # VSM Routing fields
    field :vsm_target, :string
    field :control_loop, :string
    field :escalation_path, {:array, :string}
    
    # CRDT fields for distributed consciousness
    field :belief_set, :map
    field :confidence, :float, default: 1.0
    field :consensus_weight, :float, default: 1.0
    
    # CAIL (Content-Addressable Intelligence Lattice) fields
    field :content_hash, :string
    field :semantic_links, {:array, :string}
    field :lattice_position, {:array, :float}
    field :temporal_context, :map
  end

  @doc """
  Creates a new aMCP message with semantic context fusion and content-based ID
  """
  def new(attrs) do
    # Add timestamp if not provided
    attrs = case Map.get(attrs, :timestamp) do
      nil -> Map.put(attrs, :timestamp, DateTime.utc_now())
      _ -> attrs
    end
    
    # Enhance with semantic context fusion
    attrs = enhance_semantic_context(attrs)
    
    # Generate provenance chain
    attrs = generate_provenance(attrs)
    
    # Calculate variety metrics
    attrs = calculate_variety_metrics(attrs)
    
    # Generate content-based hash ID (CID-compatible)
    id = generate_content_hash(attrs)
    
    %__MODULE__{}
    |> changeset(Map.put(attrs, :id, id))
    |> apply_changes()
  end

  @doc """
  Creates a new aMCP message with semantic embedding generation
  """
  def new_with_embedding(attrs, embedding_service \\ nil) do
    attrs = if embedding_service && attrs[:payload] do
      # Generate semantic embedding from payload
      embedding = generate_semantic_embedding(attrs[:payload], embedding_service)
      Map.put(attrs, :embedding, embedding)
    else
      attrs
    end
    
    new(attrs)
  end

  @doc """
  Creates a new aMCP message for VSM subsystem communication
  """
  def new_vsm(attrs, vsm_target, control_loop \\ nil) do
    vsm_attrs = attrs
    |> Map.put(:vsm_target, vsm_target)
    |> Map.put(:control_loop, control_loop)
    |> Map.put(:type, "vsm_message")
    |> enhance_vsm_routing()
    
    new(vsm_attrs)
  end

  @doc """
  Creates a new aMCP message for algedonic (pain/pleasure) signals
  """
  def new_algedonic(attrs, valence, intensity \\ 1.0) do
    algedonic_attrs = attrs
    |> Map.put(:type, "algedonic_signal") 
    |> Map.put(:algedonic_valence, valence * intensity)
    |> Map.put(:priority, if(abs(valence) > 0.8, do: "critical", else: "high"))
    |> Map.put(:urgency, abs(valence))
    |> Map.put(:escalation_path, ["s3_control", "s5_policy"])
    
    new(algedonic_attrs)
  end

  @doc """
  Generates a deterministic content-based hash for message ID
  """
  def generate_content_hash(attrs) do
    # Exclude id and signature from hash calculation
    content = Map.drop(attrs, [:id, :signature])
    
    # Create deterministic string representation
    canonical = :erlang.term_to_binary(content, [:deterministic])
    
    # Generate SHA256 hash and convert to UUID format
    :crypto.hash(:sha256, canonical)
    |> Base.encode16(case: :lower)
    |> String.slice(0..31)
    |> format_as_uuid()
  end

  defp format_as_uuid(hex) do
    # Format as UUID v4-like string
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), 
      d::binary-size(4), e::binary-size(12)>> = hex
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  # Private helper functions
  
  defp enhance_semantic_context(attrs) do
    # Add semantic enrichment to context
    enhanced_context = Map.merge(attrs[:context] || %{}, %{
      semantic_tags: extract_semantic_tags(attrs[:payload]),
      topic_cluster: classify_topic(attrs[:payload]),
      complexity_score: calculate_complexity(attrs[:payload])
    })
    
    Map.put(attrs, :context, enhanced_context)
  end
  
  defp generate_provenance(attrs) do
    # Generate provenance chain
    provenance = %{
      origin_node: node(),
      creation_time: DateTime.utc_now(),
      processing_chain: [],
      trust_score: 1.0
    }
    
    Map.put(attrs, :provenance, provenance)
  end
  
  defp calculate_variety_metrics(attrs) do
    # Calculate Ashby's variety metrics
    payload_size = byte_size(inspect(attrs[:payload]))
    context_complexity = map_size(attrs[:context] || %{})
    
    variety_metrics = %{
      payload_variety: min(payload_size / 1000, 10.0),
      context_variety: min(context_complexity / 5, 10.0),
      total_variety: min((payload_size + context_complexity) / 1000, 20.0)
    }
    
    Map.put(attrs, :variety_metrics, variety_metrics)
  end
  
  defp enhance_vsm_routing(attrs) do
    # Add VSM-specific routing information
    routing_info = %{
      target_subsystems: determine_vsm_targets(attrs),
      routing_priority: calculate_routing_priority(attrs),
      escalation_path: build_escalation_path(attrs)
    }
    
    Map.put(attrs, :vsm_routing, routing_info)
  end
  
  defp generate_semantic_embedding(_payload, _service) do
    # Placeholder for semantic embedding generation
    # In a real implementation, this would call an embedding service
    %{
      vector: List.duplicate(0.0, 1536),  # OpenAI embedding size
      model: "text-embedding-ada-002",
      generated_at: DateTime.utc_now()
    }
  end
  
  # Helper functions for semantic context enhancement
  
  defp extract_semantic_tags(payload) when is_map(payload) do
    # Extract semantic tags from payload
    Map.keys(payload) |> Enum.take(5)
  end
  
  defp extract_semantic_tags(_), do: []
  
  defp classify_topic(payload) when is_map(payload) do
    # Classify topic based on payload content
    cond do
      Map.has_key?(payload, :vsm_subsystem) -> "vsm_control"
      Map.has_key?(payload, :algedonic) -> "consciousness"
      Map.has_key?(payload, :pattern) -> "pattern_recognition"
      true -> "general"
    end
  end
  
  defp classify_topic(_), do: "unknown"
  
  defp calculate_complexity(payload) when is_map(payload) do
    # Calculate complexity score (0.0 to 1.0)
    size_factor = min(map_size(payload) / 10, 1.0)
    nesting_factor = calculate_nesting_depth(payload) / 5
    min(size_factor + nesting_factor, 1.0)
  end
  
  defp calculate_complexity(_), do: 0.1
  
  defp calculate_nesting_depth(map) when is_map(map) do
    if map_size(map) == 0 do
      0
    else
      1 + (map |> Map.values() |> Enum.map(&calculate_nesting_depth/1) |> Enum.max())
    end
  end
  
  defp calculate_nesting_depth(_), do: 0
  
  defp determine_vsm_targets(attrs) do
    # Determine which VSM subsystems should receive this message
    case attrs[:type] do
      "vsm_operations" -> [:s1_operations]
      "vsm_coordination" -> [:s2_coordination]
      "vsm_control" -> [:s3_control]
      "vsm_intelligence" -> [:s4_intelligence]
      "vsm_policy" -> [:s5_policy]
      "algedonic_signal" -> [:s3_control, :s5_policy]
      _ -> [:s1_operations]
    end
  end
  
  defp calculate_routing_priority(attrs) do
    # Calculate routing priority based on content
    base_priority = case attrs[:priority] do
      "critical" -> 100
      "high" -> 75
      "medium" -> 50
      "low" -> 25
      _ -> 50
    end
    
    # Adjust based on urgency and algedonic valence
    urgency_boost = (attrs[:urgency] || 0.5) * 25
    algedonic_boost = abs(attrs[:algedonic_valence] || 0) * 25
    
    round(base_priority + urgency_boost + algedonic_boost)
  end
  
  defp build_escalation_path(attrs) do
    # Build escalation path based on message type and priority
    base_path = ["s1_operations", "s3_control"]
    
    if attrs[:priority] in ["critical", "high"] or (attrs[:algedonic_valence] || 0) |> abs() > 0.8 do
      base_path ++ ["s5_policy"]
    else
      base_path
    end
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:id, :type, :sender, :recipient, :payload, :context, :timestamp, :signature])
    |> validate_required([:id, :type, :sender, :payload, :context, :timestamp])
  end
end
