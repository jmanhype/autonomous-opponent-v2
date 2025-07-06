defmodule AutonomousOpponentV2Core.Intelligence.MockLLM do
  @moduledoc """
  Mock LLM provider for ultra-fast development.
  Provides instant, predictable responses without API calls.
  """

  require Logger

  @behaviour AutonomousOpponentV2Core.Intelligence.LLMProviderBehaviour

  # Mock responses for different intents
  @mock_responses %{
    "combat_analysis" => [
      "Analyzing combat patterns... The opponent shows vulnerability to feints followed by low kicks. Their guard drops 0.3 seconds after each jab attempt. Recommend exploiting this timing window with counter-strikes.",
      "Combat assessment complete. Target exhibits orthodox stance with tendency to overcommit on crosses. Suggest utilizing lateral movement and check hooks to capitalize on balance shifts.",
      "Pattern detected: Opponent telegraphs power shots with shoulder dip. Defensive recommendation: slip right and counter with left hook to body. Success probability: 78%."
    ],
    "strategy_generation" => [
      "Strategic approach formulated: Phase 1 - Establish range control with jabs and teeps. Phase 2 - Test reactions with feint combinations. Phase 3 - Execute high-percentage counters based on observed patterns.",
      "Optimal strategy identified: Pressure fighting with emphasis on body work. Break down opponent's conditioning in rounds 1-2, capitalize with head hunting in round 3.",
      "Tactical recommendation: Switch-hitting stance changes every 30 seconds to disrupt opponent's timing. Mix levels aggressively. Force opponent to reset constantly."
    ],
    "pattern_recognition" => [
      "Pattern analysis complete: Opponent favors 1-2-3 combination (65% frequency). Timing: 1.2s between initiation and completion. Defensive gap: 0.4s window after third strike.",
      "Behavioral pattern detected: Target retreats linearly when pressured. Tendency to throw panic hooks when cornered. Exploit with angular approaches and level changes.",
      "Movement pattern identified: Opponent circles predictably to their power side. Counter-strategy: Cut off ring with lateral steps, force engagement in center."
    ],
    "emotional_state" => [
      "Emotional assessment: Opponent showing signs of frustration - increased respiration, tighter movements, telegraphing strikes. Confidence level decreasing. Recommend maintaining pressure.",
      "Psychological profile: Target exhibits high confidence initially but deteriorates under sustained pressure. Emotional volatility increases after body shots. Mental fortitude: 6/10.",
      "Current state analysis: Opponent displaying fatigue indicators - dropped hands, mouth breathing, reduced lateral movement. Emotional state: desperate. Time to increase offensive output."
    ],
    "weakness_identification" => [
      "Critical weakness identified: Poor head movement when throwing combinations. Exploitable with simultaneous counters. Secondary weakness: Neglects body defense when head hunting.",
      "Vulnerability assessment: Limited footwork repertoire - primarily linear movement. Struggles with angles. Balance compromised during power shots. Recommend angle-based attacks.",
      "Weakness analysis complete: 1) Drops right hand when jabbing. 2) Static head position. 3) Predictable rhythm. 4) Poor recovery after missing. Priority target: Lead hand control."
    ],
    "training_recommendation" => [
      "Training focus areas: 1) Slip and rip drills for counter-punching. 2) Footwork patterns emphasizing angles. 3) Body conditioning for inside fighting. 4) Feint incorporation.",
      "Skill development priorities: Improve head movement integration with offense. Develop switch-hitting capabilities. Enhance ring generalship. Work on combination breaking.",
      "Technical improvements needed: Tighten defensive shell between exchanges. Develop proactive footwork. Master distance management. Incorporate more feints and level changes."
    ],
    "general" => [
      "Analysis complete. Multiple strategic options available. Recommend aggressive approach with calculated risks. Maintain pressure while preserving energy for later rounds.",
      "System assessment finished. Opponent presents moderate challenge with exploitable patterns. Confidence in victory: 82%. Execute game plan with precision.",
      "Evaluation concluded. Target shows technical proficiency but mental fragility. Apply psychological pressure through pace and variety. Victory achievable through attrition."
    ]
  }

  @impl true
  def chat(messages, options \\ []) do
    # Simulate small delay if configured
    delay = Application.get_env(:autonomous_opponent_core, :llm_mock_delay, 50)
    if delay > 0, do: Process.sleep(delay)

    # Extract intent from messages or options
    intent = extract_intent(messages, options)
    
    # Get appropriate mock response
    response = get_mock_response(intent)
    
    # Log mock usage
    Logger.debug("MockLLM responding to intent: #{intent}")
    
    {:ok, response}
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    # For streaming, we'll return the response in chunks
    case chat(messages, options) do
      {:ok, response} ->
        # Split response into chunks to simulate streaming
        chunks = String.split(response, " ")
        stream = Stream.map(chunks, fn chunk -> 
          # Tiny delay between chunks for realism
          Process.sleep(10)
          {:chunk, chunk <> " "}
        end)
        
        {:ok, stream}
        
      error -> error
    end
  end

  @impl true
  def validate_config(config) do
    # Mock provider doesn't need real config
    {:ok, config}
  end

  @impl true
  def name do
    "mock"
  end

  @impl true
  def supports_streaming? do
    true
  end

  @impl true
  def format_messages(messages) do
    # Simply return messages as-is for mock
    messages
  end

  # Private functions

  defp extract_intent(messages, options) do
    # Check options first
    intent = Keyword.get(options, :intent)
    
    # If no explicit intent, analyze the messages
    intent || analyze_messages_for_intent(messages)
  end

  defp analyze_messages_for_intent(messages) do
    # Get the last user message
    last_message = 
      messages
      |> Enum.reverse()
      |> Enum.find(fn msg -> 
        msg[:role] == "user" || msg["role"] == "user"
      end)
    
    content = (last_message[:content] || last_message["content"] || "") |> String.downcase()
    
    cond do
      String.contains?(content, ["combat", "fight", "strike", "attack"]) ->
        "combat_analysis"
      String.contains?(content, ["strategy", "plan", "approach", "tactic"]) ->
        "strategy_generation"
      String.contains?(content, ["pattern", "behavior", "tendency", "habit"]) ->
        "pattern_recognition"
      String.contains?(content, ["emotion", "mental", "psychology", "state"]) ->
        "emotional_state"
      String.contains?(content, ["weakness", "vulnerability", "exploit", "flaw"]) ->
        "weakness_identification"
      String.contains?(content, ["train", "improve", "develop", "practice"]) ->
        "training_recommendation"
      true ->
        "general"
    end
  end

  defp get_mock_response(intent) do
    # Get responses for the intent
    responses = Map.get(@mock_responses, intent, @mock_responses["general"])
    
    # Add some variety by picking a random response
    Enum.random(responses)
  end

  @doc """
  Add a custom mock response for testing specific scenarios.
  Useful for development when you need specific responses.
  """
  def add_mock_response(intent, response) do
    # Store in process dictionary for this session
    current = Process.get(:custom_mock_responses, %{})
    Process.put(:custom_mock_responses, Map.put(current, intent, response))
  end

  @doc """
  Clear all custom mock responses.
  """
  def clear_custom_responses do
    Process.delete(:custom_mock_responses)
  end
end