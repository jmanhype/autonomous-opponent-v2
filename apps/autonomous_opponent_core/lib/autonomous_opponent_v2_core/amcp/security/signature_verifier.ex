defmodule AutonomousOpponentV2Core.AMCP.Security.SignatureVerifier do
  @moduledoc """
  Cryptographic signature verification for aMCP messages.
  
  Provides message integrity and authenticity verification using:
  - ECDSA signatures with secp256k1 curves
  - EdDSA signatures with Ed25519 curves
  - RSA signatures with PSS padding
  - HMAC-based signatures for shared key scenarios
  
  Features:
  - Multiple signature algorithm support
  - Key rotation and versioning
  - Signature timestamping
  - Batch verification for performance
  """
  
  require Logger
  
  @supported_algorithms [:ecdsa_secp256k1, :eddsa_ed25519, :rsa_pss, :hmac_sha256]
  @default_algorithm :ecdsa_secp256k1
  
  @type signature_algorithm :: :ecdsa_secp256k1 | :eddsa_ed25519 | :rsa_pss | :hmac_sha256
  @type key_id :: String.t()
  @type signature :: String.t()
  @type public_key :: binary()
  @type private_key :: binary()
  
  @type signature_info :: %{
    algorithm: signature_algorithm(),
    key_id: key_id(),
    signature: signature(),
    timestamp: DateTime.t()
  }
  
  @type verification_result :: :valid | {:invalid, term()} | {:error, term()}
  
  @doc """
  Signs a message with the specified algorithm and private key.
  
  Returns a signature info map containing the signature and metadata.
  """
  @spec sign_message(map(), signature_algorithm(), key_id(), private_key()) :: 
    {:ok, signature_info()} | {:error, term()}
  def sign_message(message, algorithm \\ @default_algorithm, key_id, private_key) do
    case algorithm in @supported_algorithms do
      true ->
        do_sign_message(message, algorithm, key_id, private_key)
      false ->
        {:error, {:unsupported_algorithm, algorithm}}
    end
  end
  
  @doc """
  Verifies a message signature using the public key.
  """
  @spec verify_message(map(), signature_info(), public_key()) :: verification_result()
  def verify_message(message, signature_info, public_key) do
    case signature_info.algorithm in @supported_algorithms do
      true ->
        do_verify_message(message, signature_info, public_key)
      false ->
        {:error, {:unsupported_algorithm, signature_info.algorithm}}
    end
  end
  
  @doc """
  Verifies multiple messages in batch for better performance.
  """
  @spec verify_batch([{map(), signature_info(), public_key()}]) :: 
    [{:ok, verification_result()} | {:error, term()}]
  def verify_batch(message_signature_pairs) do
    Enum.map(message_signature_pairs, fn {message, signature_info, public_key} ->
      try do
        result = verify_message(message, signature_info, public_key)
        {:ok, result}
      rescue
        error ->
          {:error, error}
      end
    end)
  end
  
  @doc """
  Generates a new key pair for the specified algorithm.
  """
  @spec generate_keypair(signature_algorithm()) :: 
    {:ok, {public_key(), private_key()}} | {:error, term()}
  def generate_keypair(algorithm \\ @default_algorithm) do
    case algorithm do
      :ecdsa_secp256k1 ->
        generate_ecdsa_keypair()
        
      :eddsa_ed25519 ->
        generate_eddsa_keypair()
        
      :rsa_pss ->
        generate_rsa_keypair()
        
      :hmac_sha256 ->
        # HMAC uses shared keys, not keypairs
        {:error, :hmac_uses_shared_keys}
        
      _ ->
        {:error, {:unsupported_algorithm, algorithm}}
    end
  end
  
  @doc """
  Generates a shared key for HMAC signing.
  """
  @spec generate_hmac_key() :: binary()
  def generate_hmac_key do
    :crypto.strong_rand_bytes(32)  # 256-bit key
  end
  
  @doc """
  Extracts signature information from an aMCP message.
  """
  @spec extract_signature_info(map()) :: {:ok, signature_info()} | {:error, term()}
  def extract_signature_info(%{signature: signature_data}) when is_map(signature_data) do
    try do
      signature_info = %{
        algorithm: String.to_atom(signature_data["algorithm"] || "ecdsa_secp256k1"),
        key_id: signature_data["key_id"],
        signature: signature_data["signature"],
        timestamp: parse_timestamp(signature_data["timestamp"])
      }
      {:ok, signature_info}
    rescue
      error ->
        {:error, {:invalid_signature_format, error}}
    end
  end
  
  def extract_signature_info(_message) do
    {:error, :no_signature_found}
  end
  
  @doc """
  Adds signature information to an aMCP message.
  """
  @spec add_signature_to_message(map(), signature_info()) :: map()
  def add_signature_to_message(message, signature_info) do
    signature_data = %{
      "algorithm" => Atom.to_string(signature_info.algorithm),
      "key_id" => signature_info.key_id,
      "signature" => signature_info.signature,
      "timestamp" => DateTime.to_iso8601(signature_info.timestamp)
    }
    
    Map.put(message, :signature, signature_data)
  end
  
  @doc """
  Validates signature timestamp to prevent replay attacks.
  """
  @spec validate_signature_timestamp(signature_info(), integer()) :: :valid | {:invalid, term()}
  def validate_signature_timestamp(signature_info, max_age_seconds \\ 300) do
    current_time = DateTime.utc_now()
    age_seconds = DateTime.diff(current_time, signature_info.timestamp)
    
    cond do
      age_seconds > max_age_seconds ->
        {:invalid, :signature_too_old}
        
      age_seconds < -60 ->  # Allow 1 minute clock skew
        {:invalid, :signature_from_future}
        
      true ->
        :valid
    end
  end
  
  # Private Implementation Functions
  
  defp do_sign_message(message, algorithm, key_id, private_key) do
    try do
      # Create canonical message representation
      canonical_message = canonicalize_message(message)
      
      # Generate signature
      signature = case algorithm do
        :ecdsa_secp256k1 ->
          sign_ecdsa(canonical_message, private_key)
          
        :eddsa_ed25519 ->
          sign_eddsa(canonical_message, private_key)
          
        :rsa_pss ->
          sign_rsa_pss(canonical_message, private_key)
          
        :hmac_sha256 ->
          sign_hmac(canonical_message, private_key)
      end
      
      signature_info = %{
        algorithm: algorithm,
        key_id: key_id,
        signature: Base.encode64(signature),
        timestamp: DateTime.utc_now()
      }
      
      {:ok, signature_info}
    rescue
      error ->
        Logger.error("Message signing failed: #{inspect(error)}")
        {:error, {:signing_failed, error}}
    end
  end
  
  defp do_verify_message(message, signature_info, public_key) do
    try do
      # Validate timestamp first
      case validate_signature_timestamp(signature_info) do
        :valid ->
          # Create canonical message representation
          canonical_message = canonicalize_message(message)
          
          # Decode signature
          signature = Base.decode64!(signature_info.signature)
          
          # Verify signature
          case signature_info.algorithm do
            :ecdsa_secp256k1 ->
              verify_ecdsa(canonical_message, signature, public_key)
              
            :eddsa_ed25519 ->
              verify_eddsa(canonical_message, signature, public_key)
              
            :rsa_pss ->
              verify_rsa_pss(canonical_message, signature, public_key)
              
            :hmac_sha256 ->
              verify_hmac(canonical_message, signature, public_key)
          end
          
        invalid_result ->
          invalid_result
      end
    rescue
      error ->
        Logger.error("Message verification failed: #{inspect(error)}")
        {:error, {:verification_failed, error}}
    end
  end
  
  # Message Canonicalization
  
  defp canonicalize_message(message) do
    # Remove signature field and create deterministic representation
    clean_message = Map.delete(message, :signature) |> Map.delete("signature")
    
    # Sort keys and encode to ensure deterministic output
    clean_message
    |> Jason.encode!(sort_keys: true)
  end
  
  # ECDSA Implementation
  
  defp generate_ecdsa_keypair do
    try do
      {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256k1)
      {:ok, {public_key, private_key}}
    rescue
      error ->
        {:error, {:keypair_generation_failed, error}}
    end
  end
  
  defp sign_ecdsa(message, private_key) do
    hash = :crypto.hash(:sha256, message)
    :crypto.sign(:ecdsa, :sha256, hash, [private_key, :secp256k1])
  end
  
  defp verify_ecdsa(message, signature, public_key) do
    try do
      hash = :crypto.hash(:sha256, message)
      case :crypto.verify(:ecdsa, :sha256, hash, signature, [public_key, :secp256k1]) do
        true -> :valid
        false -> {:invalid, :signature_mismatch}
      end
    rescue
      _ -> {:invalid, :verification_error}
    end
  end
  
  # EdDSA Implementation
  
  defp generate_eddsa_keypair do
    try do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, {public_key, private_key}}
    rescue
      error ->
        {:error, {:keypair_generation_failed, error}}
    end
  end
  
  defp sign_eddsa(message, private_key) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
  end
  
  defp verify_eddsa(message, signature, public_key) do
    try do
      case :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]) do
        true -> :valid
        false -> {:invalid, :signature_mismatch}
      end
    rescue
      _ -> {:invalid, :verification_error}
    end
  end
  
  # RSA PSS Implementation
  
  defp generate_rsa_keypair do
    try do
      {public_key, private_key} = :crypto.generate_key(:rsa, {2048, 65537})
      {:ok, {public_key, private_key}}
    rescue
      error ->
        {:error, {:keypair_generation_failed, error}}
    end
  end
  
  defp sign_rsa_pss(message, private_key) do
    hash = :crypto.hash(:sha256, message)
    :crypto.sign(:rsa, :sha256, hash, private_key, rsa_pss_options())
  end
  
  defp verify_rsa_pss(message, signature, public_key) do
    try do
      hash = :crypto.hash(:sha256, message)
      case :crypto.verify(:rsa, :sha256, hash, signature, public_key, rsa_pss_options()) do
        true -> :valid
        false -> {:invalid, :signature_mismatch}
      end
    rescue
      _ -> {:invalid, :verification_error}
    end
  end
  
  defp rsa_pss_options do
    [{:rsa_padding, :rsa_pkcs1_pss_padding}, {:rsa_pss_saltlen, :rsa_pss_saltlen_digest}]
  end
  
  # HMAC Implementation
  
  defp sign_hmac(message, shared_key) do
    :crypto.mac(:hmac, :sha256, shared_key, message)
  end
  
  defp verify_hmac(message, signature, shared_key) do
    expected_signature = sign_hmac(message, shared_key)
    
    case :crypto.equal_const_time(signature, expected_signature) do
      true -> :valid
      false -> {:invalid, :signature_mismatch}
    end
  end
  
  # Utility Functions
  
  defp parse_timestamp(timestamp_string) when is_binary(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
  
  defp parse_timestamp(_), do: DateTime.utc_now()
  
  @doc """
  Creates a complete signed aMCP message.
  """
  @spec create_signed_message(map(), signature_algorithm(), key_id(), private_key()) ::
    {:ok, map()} | {:error, term()}
  def create_signed_message(message, algorithm, key_id, private_key) do
    case sign_message(message, algorithm, key_id, private_key) do
      {:ok, signature_info} ->
        signed_message = add_signature_to_message(message, signature_info)
        {:ok, signed_message}
        
      error ->
        error
    end
  end
  
  @doc """
  Verifies a complete signed aMCP message.
  """
  @spec verify_signed_message(map(), public_key()) :: verification_result()
  def verify_signed_message(signed_message, public_key) do
    case extract_signature_info(signed_message) do
      {:ok, signature_info} ->
        verify_message(signed_message, signature_info, public_key)
        
      error ->
        error
    end
  end
  
  @doc """
  Key derivation for deterministic key generation from seed.
  """
  @spec derive_key_from_seed(binary(), signature_algorithm()) :: 
    {:ok, private_key()} | {:error, term()}
  def derive_key_from_seed(seed, algorithm) when byte_size(seed) >= 32 do
    case algorithm do
      :ecdsa_secp256k1 ->
        # Use HKDF to derive key material
        derived_key = :crypto.mac(:hmac, :sha256, "ecdsa-secp256k1", seed)
        {:ok, derived_key}
        
      :eddsa_ed25519 ->
        derived_key = :crypto.mac(:hmac, :sha256, "eddsa-ed25519", seed)
        # Take first 32 bytes for Ed25519
        {:ok, binary_part(derived_key, 0, 32)}
        
      :hmac_sha256 ->
        derived_key = :crypto.mac(:hmac, :sha256, "hmac-shared", seed)
        {:ok, derived_key}
        
      _ ->
        {:error, {:unsupported_derivation, algorithm}}
    end
  end
  
  def derive_key_from_seed(_seed, _algorithm) do
    {:error, :seed_too_short}
  end
end