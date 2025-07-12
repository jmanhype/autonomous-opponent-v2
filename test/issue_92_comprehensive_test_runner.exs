#!/usr/bin/env elixir

defmodule Issue92ComprehensiveTestRunner do
  @moduledoc """
  Comprehensive test runner for Issue #92: VSM Pattern Integration

  Runs all test suites for Issue #92 implementation and provides detailed reporting.
  """

  def run do
    IO.puts("""

    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                               ║
    ║  🧠 ISSUE #92 COMPREHENSIVE TEST SUITE                                       ║
    ║     VSM Pattern Integration: S4 Intelligence Pattern Processing              ║
    ║                                                                               ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝

    Starting comprehensive test execution for Issue #92...

    """)

    test_suites = [
      %{
        name: "Unit Tests: S4 Intelligence Pattern Handlers",
        file: "test/autonomous_opponent_core/vsm/s4/intelligence_pattern_test.exs",
        tags: ["unit", "issue_92"],
        description: "Tests S4 Intelligence pattern event subscriptions and processing"
      },
      %{
        name: "Unit Tests: PatternDetector S4 Publishing",
        file: "test/autonomous_opponent_core/amcp/temporal/pattern_detector_s4_test.exs",
        tags: ["unit", "issue_92"],
        description: "Tests PatternDetector S4-specific event publishing functionality"
      },
      %{
        name: "Integration Tests: Complete Pattern Flow",
        file: "test/integration/issue_92_complete_integration_test.exs",
        tags: ["integration", "issue_92", "end_to_end"],
        description: "End-to-end tests from PatternDetector → EventBus → S4 Intelligence"
      },
      %{
        name: "Property-Based Tests: Pattern Processing",
        file: "test/property/issue_92_pattern_properties_test.exs",
        tags: ["property", "issue_92"],
        description: "Property-based tests using StreamData for pattern processing invariants"
      },
      %{
        name: "Performance Tests: Throughput & Scalability",
        file: "test/performance/issue_92_performance_test.exs",
        tags: ["performance", "issue_92"],
        description: "Performance tests for throughput, latency, memory usage, and scalability"
      }
    ]

    results = run_test_suites(test_suites)
    generate_comprehensive_report(results)
  end

  defp run_test_suites(test_suites) do
    IO.puts("📋 Running #{length(test_suites)} test suites...\n")

    Enum.map(test_suites, fn suite ->
      IO.puts("🧪 Running: #{suite.name}")
      IO.puts("   File: #{suite.file}")
      IO.puts("   Description: #{suite.description}")
      IO.puts("   Tags: #{Enum.join(suite.tags, ", ")}")

      start_time = System.monotonic_time(:millisecond)

      # Check if test file exists
      if File.exists?(suite.file) do
        # Run the specific test file
        {output, exit_code} =
          System.cmd("mix", ["test", suite.file, "--trace"],
            stderr_to_stdout: true,
            cd: System.cwd!()
          )

        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        result = %{
          suite: suite,
          exit_code: exit_code,
          output: output,
          duration: duration,
          success: exit_code == 0,
          file_exists: true
        }

        if result.success do
          IO.puts("   ✅ PASSED (#{duration}ms)")
        else
          IO.puts("   ❌ FAILED (#{duration}ms)")
        end
      else
        result = %{
          suite: suite,
          exit_code: -1,
          output: "Test file not found: #{suite.file}",
          duration: 0,
          success: false,
          file_exists: false
        }

        IO.puts("   ⚠️  FILE NOT FOUND")
        result
      end

      IO.puts("")
      result
    end)
  end

  defp generate_comprehensive_report(results) do
    total_suites = length(results)
    passed_suites = Enum.count(results, & &1.success)
    failed_suites = total_suites - passed_suites
    total_duration = Enum.sum(Enum.map(results, & &1.duration))

    IO.puts("""

    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                               ║
    ║  📊 COMPREHENSIVE TEST RESULTS - ISSUE #92                                   ║
    ║                                                                               ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝

    🎯 Overall Results:
       • Total Test Suites: #{total_suites}
       • Passed: #{passed_suites}
       • Failed: #{failed_suites}
       • Success Rate: #{Float.round(passed_suites / total_suites * 100, 1)}%
       • Total Duration: #{total_duration}ms (#{Float.round(total_duration / 1000, 2)}s)

    📋 Detailed Results:
    """)

    Enum.with_index(results, 1)
    |> Enum.each(fn {result, index} ->
      status_icon = if result.success, do: "✅", else: "❌"
      file_status = if result.file_exists, do: "", else: " (FILE MISSING)"

      IO.puts("   #{index}. #{status_icon} #{result.suite.name}#{file_status}")
      IO.puts("      Duration: #{result.duration}ms")
      IO.puts("      File: #{result.suite.file}")

      if not result.success do
        IO.puts("      Error Output:")
        # Show first few lines of error output
        error_lines = String.split(result.output, "\n") |> Enum.take(5)

        Enum.each(error_lines, fn line ->
          IO.puts("        #{line}")
        end)

        if length(String.split(result.output, "\n")) > 5 do
          IO.puts("        ... (truncated)")
        end
      end

      IO.puts("")
    end)

    # Feature Coverage Analysis
    IO.puts("""
    🎯 Feature Coverage Analysis:
    """)

    analyze_feature_coverage(results)

    # Recommendations
    IO.puts("""
    💡 Recommendations:
    """)

    generate_recommendations(results)

    # Next Steps
    IO.puts("""
    🚀 Next Steps for Issue #92:
    """)

    if passed_suites == total_suites do
      IO.puts("""
         ✅ All tests passing! Issue #92 implementation is ready for production.
         
         Recommended next steps:
         1. ✅ Merge PR #116 to master
         2. 🔄 Deploy to staging environment for integration testing
         3. 📊 Monitor performance metrics in staging
         4. 🚀 Deploy to production with monitoring
         5. 📝 Update documentation with new VSM pattern flow capabilities
      """)
    else
      IO.puts("""
         ⚠️  Some tests are failing. Address issues before deployment:
         
         Immediate actions:
         1. 🔍 Investigate failing tests (see detailed output above)
         2. 🛠️  Fix implementation issues
         3. 🧪 Re-run tests until all pass
         4. 💻 Consider adding additional test coverage
         5. 📋 Update PR #116 with fixes
      """)
    end

    IO.puts("""

    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                               ║
    ║  🏁 ISSUE #92 TEST EXECUTION COMPLETE                                        ║
    ║                                                                               ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝

    For detailed test output, see individual test files.
    For Issue #92 implementation details, see: ISSUE_92_IMPLEMENTATION_SUMMARY.md

    """)

    # Return summary for programmatic use
    %{
      total_suites: total_suites,
      passed: passed_suites,
      failed: failed_suites,
      success_rate: passed_suites / total_suites,
      total_duration: total_duration,
      all_passed: passed_suites == total_suites,
      results: results
    }
  end

  defp analyze_feature_coverage(results) do
    coverage_areas = [
      {"S4 Intelligence Event Subscriptions", has_pattern?(results, "subscription")},
      {"Pattern Event Processing", has_pattern?(results, "pattern.*processing")},
      {"Environmental Signal Handling", has_pattern?(results, "environmental.*signal")},
      {"Vector Storage Integration", has_pattern?(results, "vector.*storage")},
      {"Strategy Updates", has_pattern?(results, "strategy.*update")},
      {"Error Handling & Recovery", has_pattern?(results, "error.*handling")},
      {"Performance & Scalability", has_pattern?(results, "performance")},
      {"Property-Based Validation", has_pattern?(results, "property")},
      {"End-to-End Integration", has_pattern?(results, "integration")}
    ]

    Enum.each(coverage_areas, fn {area, covered} ->
      status = if covered, do: "✅", else: "❌"
      IO.puts("     #{status} #{area}")
    end)
  end

  defp has_pattern?(results, pattern) do
    regex = Regex.compile!(pattern, "i")

    Enum.any?(results, fn result ->
      Regex.match?(regex, result.suite.name) or
        Regex.match?(regex, result.suite.description) or
        Enum.any?(result.suite.tags, &Regex.match?(regex, &1))
    end)
  end

  defp generate_recommendations(results) do
    failed_results = Enum.filter(results, fn result -> not result.success end)

    cond do
      length(failed_results) == 0 ->
        IO.puts("""
           ✅ All tests passing! Consider these enhancements:
           
           • Add stress tests for extreme load conditions
           • Add chaos engineering tests for fault tolerance
           • Add benchmark comparisons with baseline performance
           • Add monitoring and alerting integration tests
        """)

      Enum.any?(failed_results, &(&1.file_exists == false)) ->
        missing_files = Enum.filter(failed_results, &(&1.file_exists == false))

        IO.puts("""
           📝 Missing test files detected:
           
        """)

        Enum.each(missing_files, fn result ->
          IO.puts("     • Create: #{result.suite.file}")
        end)

      true ->
        IO.puts("""
           🔧 Test failures detected. Common solutions:
           
           • Ensure EventBus is properly started in test setup
           • Verify S4 Intelligence subscribes to required events
           • Check pattern data structure compatibility
           • Validate timeout values for async operations
           • Ensure proper cleanup between tests
        """)
    end
  end
end

# Auto-run if this script is executed directly
if System.argv() |> Enum.any?(&(&1 == "--run")) do
  Issue92ComprehensiveTestRunner.run()
else
  IO.puts("""
  Issue #92 Comprehensive Test Runner

  Usage:
    elixir test/issue_92_comprehensive_test_runner.exs --run

  Or from iex:
    Issue92ComprehensiveTestRunner.run()
  """)
end
