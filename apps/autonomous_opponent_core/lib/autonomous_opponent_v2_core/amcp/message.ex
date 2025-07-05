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

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:id, :type, :sender, :recipient, :payload, :context, :timestamp, :signature])
    |> validate_required([:id, :type, :sender, :payload, :context, :timestamp])
  end
end
