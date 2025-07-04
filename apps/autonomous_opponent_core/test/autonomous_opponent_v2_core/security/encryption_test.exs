defmodule AutonomousOpponentV2Core.Security.EncryptionTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.Security.Encryption
  
  describe "encrypt/1 and decrypt/1" do
    test "encrypts and decrypts string values" do
      plaintext = "sensitive data 123"
      
      assert {:ok, ciphertext} = Encryption.encrypt(plaintext)
      assert is_binary(ciphertext)
      assert ciphertext != plaintext
      
      assert {:ok, decrypted} = Encryption.decrypt(ciphertext)
      assert decrypted == plaintext
    end
    
    test "produces different ciphertext for same plaintext" do
      plaintext = "test data"
      
      {:ok, cipher1} = Encryption.encrypt(plaintext)
      {:ok, cipher2} = Encryption.encrypt(plaintext)
      
      # Due to random IV, ciphertexts should differ
      assert cipher1 != cipher2
      
      # But both should decrypt to same value
      assert {:ok, plaintext} = Encryption.decrypt(cipher1)
      assert {:ok, plaintext} = Encryption.decrypt(cipher2)
    end
    
    test "handles empty strings" do
      assert {:ok, encrypted} = Encryption.encrypt("")
      assert {:ok, ""} = Encryption.decrypt(encrypted)
    end
    
    test "handles unicode strings" do
      plaintext = "Hello 世界 🔐"
      
      assert {:ok, encrypted} = Encryption.encrypt(plaintext)
      assert {:ok, decrypted} = Encryption.decrypt(encrypted)
      assert decrypted == plaintext
    end
    
    test "returns error for invalid ciphertext" do
      assert {:error, :decryption_failed} = Encryption.decrypt("invalid_base64!")
      assert {:error, :decryption_failed} = Encryption.decrypt("aGVsbG8=")  # Valid base64 but not encrypted
    end
  end
  
  describe "generate_key/0" do
    test "generates valid encryption keys" do
      key1 = Encryption.generate_key()
      key2 = Encryption.generate_key()
      
      assert is_binary(key1)
      assert is_binary(key2)
      assert key1 != key2
      
      # Should be base64 encoded 32-byte key
      {:ok, decoded} = Base.decode64(key1)
      assert byte_size(decoded) == 32
    end
  end
  
  describe "derive_key/2" do
    test "derives consistent key from password" do
      password = "my_secure_password"
      salt = :crypto.strong_rand_bytes(16) |> Base.encode64()
      
      {key1, ^salt} = Encryption.derive_key(password, Base.decode64!(salt))
      {key2, ^salt} = Encryption.derive_key(password, Base.decode64!(salt))
      
      assert key1 == key2
    end
    
    test "generates different keys for different passwords" do
      salt = :crypto.strong_rand_bytes(16)
      
      {key1, _} = Encryption.derive_key("password1", salt)
      {key2, _} = Encryption.derive_key("password2", salt)
      
      assert key1 != key2
    end
    
    test "generates different keys for different salts" do
      password = "my_password"
      
      {key1, salt1} = Encryption.derive_key(password)
      {key2, salt2} = Encryption.derive_key(password)
      
      assert key1 != key2
      assert salt1 != salt2
    end
  end
  
  describe "EncryptedString Ecto type" do
    test "casts string values" do
      assert {:ok, "test"} = Encryption.EncryptedString.cast("test")
      assert :error = Encryption.EncryptedString.cast(123)
      assert :error = Encryption.EncryptedString.cast(nil)
    end
    
    test "dumps values to encrypted format" do
      {:ok, encrypted} = Encryption.EncryptedString.dump("sensitive")
      
      assert is_binary(encrypted)
      assert encrypted != "sensitive"
      
      # Should be valid base64
      assert {:ok, _} = Base.decode64(encrypted)
    end
    
    test "loads encrypted values" do
      # First encrypt a value
      {:ok, encrypted} = Encryption.EncryptedString.dump("secret_data")
      
      # Then load it back
      assert {:ok, "secret_data"} = Encryption.EncryptedString.load(encrypted)
    end
    
    test "round trip encryption" do
      original = "my secret api key"
      
      {:ok, dumped} = Encryption.EncryptedString.dump(original)
      {:ok, loaded} = Encryption.EncryptedString.load(dumped)
      
      assert loaded == original
    end
  end
end