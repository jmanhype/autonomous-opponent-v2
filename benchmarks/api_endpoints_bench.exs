defmodule AutonomousOpponent.Benchmarks.APIEndpoints do
  @moduledoc """
  Performance benchmarks for all API endpoints.
  Measures response times and memory usage for different scenarios.
  """

  def run do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
    {:ok, _} = Application.ensure_all_started(:autonomous_opponent_web)

    # Configure benchmarking scenarios
    scenarios = %{
      "health_check" => &benchmark_health_check/0,
      "consciousness_state" => &benchmark_consciousness_state/0,
      "vsm_status" => &benchmark_vsm_status/0,
      "llm_query_cached" => &benchmark_llm_query_cached/0,
      "llm_query_mock" => &benchmark_llm_query_mock/0,
      "event_publish" => &benchmark_event_publish/0,
      "amqp_message" => &benchmark_amqp_message/0
    }

    # Run benchmarks with different input sizes
    input_sizes = %{
      "small" => generate_small_payload(),
      "medium" => generate_medium_payload(),
      "large" => generate_large_payload()
    }

    Benchee.run(
      scenarios,
      time: 10,
      memory_time: 2,
      warmup: 2,
      parallel: 1,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.HTML, file: "benchmarks/output/api_endpoints.html"},
        {Benchee.Formatters.JSON, file: "benchmarks/output/api_endpoints.json"}
      ],
      inputs: input_sizes,
      before_each: fn input -> input end,
      print: %{
        fast_warning: false
      }
    )
  end

  # Benchmark functions
  defp benchmark_health_check do
    # Simulate API call to health endpoint
    conn = build_conn(:get, "/api/health")
    AutonomousOpponentWeb.Router.call(conn, [])
  end

  defp benchmark_consciousness_state do
    # Simulate API call to consciousness state
    conn = build_conn(:get, "/api/consciousness/state")
    AutonomousOpponentWeb.Router.call(conn, [])
  end

  defp benchmark_vsm_status do
    # Simulate API call to VSM status
    conn = build_conn(:get, "/api/vsm/status")
    AutonomousOpponentWeb.Router.call(conn, [])
  end

  defp benchmark_llm_query_cached do
    # Test cached LLM response
    conn = build_conn(:post, "/api/llm/query", %{
      prompt: "What is 2+2?",
      use_cache: true
    })
    AutonomousOpponentWeb.Router.call(conn, [])
  end

  defp benchmark_llm_query_mock do
    # Test mocked LLM response
    conn = build_conn(:post, "/api/llm/query", %{
      prompt: "Explain quantum computing",
      use_mock: true
    })
    AutonomousOpponentWeb.Router.call(conn, [])
  end

  defp benchmark_event_publish do
    # Test event bus publishing
    AutonomousOpponentV2Core.EventBus.publish(:benchmark_event, %{
      timestamp: DateTime.utc_now(),
      data: "benchmark payload"
    })
  end

  defp benchmark_amqp_message do
    # Test AMQP message sending (if enabled)
    if Application.get_env(:autonomous_opponent_core, :amqp_enabled, false) do
      AutonomousOpponentV2Core.AMQP.Publisher.publish(
        "vsm.s1.operations",
        Jason.encode!(%{type: "benchmark", timestamp: DateTime.utc_now()})
      )
    else
      # Simulate the operation if AMQP is disabled
      :ok
    end
  end

  # Helper functions
  defp build_conn(method, path, body \\ nil) do
    conn = %Plug.Conn{
      method: method |> to_string() |> String.upcase(),
      path_info: String.split(path, "/", trim: true),
      request_path: path,
      params: body || %{},
      host: "localhost",
      port: 4000,
      scheme: :http
    }

    if body do
      conn
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, body)
    else
      conn
    end
  end

  defp generate_small_payload do
    %{
      size: "small",
      data: "Simple test payload",
      items: Enum.map(1..10, &"item_#{&1}")
    }
  end

  defp generate_medium_payload do
    %{
      size: "medium",
      data: String.duplicate("Medium payload data. ", 50),
      items: Enum.map(1..100, fn i -> 
        %{id: i, name: "item_#{i}", value: :rand.uniform(1000)}
      end)
    }
  end

  defp generate_large_payload do
    %{
      size: "large",
      data: String.duplicate("Large payload data for stress testing. ", 200),
      items: Enum.map(1..1000, fn i -> 
        %{
          id: i, 
          name: "item_#{i}", 
          value: :rand.uniform(10000),
          metadata: %{
            created_at: DateTime.utc_now(),
            tags: Enum.map(1..10, &"tag_#{&1}"),
            description: "Description for item #{i}"
          }
        }
      end)
    }
  end
end

# Run the benchmark if this file is executed directly
if System.get_env("RUN_BENCHMARK") == "true" do
  AutonomousOpponent.Benchmarks.APIEndpoints.run()
end