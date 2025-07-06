defmodule AutonomousOpponentV2Core.Connections.HTTPClientTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.Connections.HTTPClient
  
  describe "HTTP methods" do
    test "GET request" do
      assert {:ok, response} = HTTPClient.get("https://httpbin.org/get")
      assert response.status == 200
      assert is_binary(response.body)
    end
    
    test "POST request with JSON" do
      body = %{name: "test", value: 123}
      
      assert {:ok, response} = HTTPClient.post(
        "https://httpbin.org/post",
        body,
        json: true
      )
      
      assert response.status == 200
    end
    
    test "automatic pool selection" do
      # OpenAI URL should use openai pool
      assert {:ok, _} = HTTPClient.get("https://api.openai.com/health", pool: :openai)
      
      # Random URL should use default pool
      assert {:ok, _} = HTTPClient.get("https://example.com")
    end
    
    test "custom headers" do
      headers = [{"x-custom-header", "test-value"}]
      
      assert {:ok, response} = HTTPClient.get(
        "https://httpbin.org/headers",
        headers: headers,
        json: true
      )
      
      assert response.body["headers"]["X-Custom-Header"] == "test-value"
    end
    
    test "timeout handling" do
      assert {:error, :timeout} = HTTPClient.get(
        "https://httpbin.org/delay/10",
        timeout: 100
      )
    end
  end
  
  describe "retry logic" do
    test "retries on transient failures" do
      # This would need a flaky endpoint to test properly
      # For now, just verify the option is accepted
      assert {:ok, _} = HTTPClient.get(
        "https://httpbin.org/get",
        retry: 3,
        retry_delay: 100
      )
    end
  end
  
  describe "JSON handling" do
    test "automatically encodes JSON body" do
      data = %{test: "data", number: 42}
      
      assert {:ok, response} = HTTPClient.post(
        "https://httpbin.org/post",
        data,
        json: true
      )
      
      assert response.body["json"] == %{"test" => "data", "number" => 42}
    end
    
    test "automatically decodes JSON response" do
      assert {:ok, response} = HTTPClient.get(
        "https://httpbin.org/json",
        json: true
      )
      
      assert is_map(response.body)
    end
  end
end