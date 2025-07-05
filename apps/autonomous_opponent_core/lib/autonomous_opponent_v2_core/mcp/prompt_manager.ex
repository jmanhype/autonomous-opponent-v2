defmodule AutonomousOpponentV2Core.MCP.PromptManager do
  @moduledoc """
  MCP Prompt Manager for VSM analysis and consciousness inquiry workflows.
  
  Manages prompt templates for Model Context Protocol, providing standardized
  prompts for VSM analysis, consciousness inquiry, system diagnosis, and
  cybernetic assessment workflows.
  
  ## Prompt Categories
  - VSM Analysis: Subsystem evaluation and cybernetic assessment
  - Consciousness Inquiry: Self-reflection and awareness analysis
  - System Diagnosis: Health checks and performance evaluation
  - Algedonic Analysis: Pain/pleasure signal interpretation
  - Strategic Planning: Goal-oriented decision making
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  defstruct [
    :prompt_templates,
    :custom_prompts,
    :usage_stats,
    :template_cache
  ]
  
  @type prompt_template :: %{
    name: String.t(),
    description: String.t(),
    arguments: [map()],
    template: String.t(),
    category: atom(),
    created_at: DateTime.t(),
    usage_count: non_neg_integer()
  }
  
  @type t :: %__MODULE__{
    prompt_templates: %{String.t() => prompt_template()},
    custom_prompts: %{String.t() => prompt_template()},
    usage_stats: %{String.t() => non_neg_integer()},
    template_cache: %{String.t() => String.t()}
  }
  
  # Public API
  
  @doc """
  Starts the MCP Prompt Manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Lists all available prompt templates.
  """
  def list_prompts do
    GenServer.call(__MODULE__, :list_prompts)
  end
  
  @doc """
  Gets a specific prompt template by name.
  """
  def get_prompt(name) do
    GenServer.call(__MODULE__, {:get_prompt, name})
  end
  
  @doc """
  Renders a prompt with provided arguments.
  """
  def render_prompt(name, arguments \\ %{}) do
    GenServer.call(__MODULE__, {:render_prompt, name, arguments})
  end
  
  @doc """
  Adds a custom prompt template.
  """
  def add_custom_prompt(name, template, options \\ []) do
    GenServer.call(__MODULE__, {:add_custom_prompt, name, template, options})
  end
  
  @doc """
  Gets usage statistics for prompt templates.
  """
  def get_usage_stats do
    GenServer.call(__MODULE__, :get_usage_stats)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(_opts) do
    Logger.info("Starting MCP Prompt Manager")
    
    state = %__MODULE__{
      prompt_templates: build_default_templates(),
      custom_prompts: %{},
      usage_stats: %{},
      template_cache: %{}
    }
    
    # Subscribe to VSM events for dynamic prompt updates
    EventBus.subscribe(:vsm_state_changed)
    EventBus.subscribe(:algedonic_signal)
    
    # Publish manager started event
    EventBus.publish(:mcp_prompt_manager_started, %{
      template_count: map_size(state.prompt_templates),
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:list_prompts, _from, state) do
    all_prompts = Map.merge(state.prompt_templates, state.custom_prompts)
    
    prompt_list = 
      all_prompts
      |> Enum.map(fn {name, template} ->
        %{
          name: name,
          description: template.description,
          arguments: template.arguments,
          category: template.category
        }
      end)
      |> Enum.sort_by(& &1.name)
    
    {:reply, {:ok, prompt_list}, state}
  end
  
  @impl true
  def handle_call({:get_prompt, name}, _from, state) do
    case find_prompt(state, name) do
      {:ok, template} -> {:reply, {:ok, template}, state}
      :not_found -> {:reply, {:error, :prompt_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:render_prompt, name, arguments}, _from, state) do
    case find_prompt(state, name) do
      {:ok, template} ->
        case render_template(template, arguments) do
          {:ok, rendered} ->
            # Update usage stats
            new_usage_stats = Map.update(state.usage_stats, name, 1, &(&1 + 1))
            new_state = %{state | usage_stats: new_usage_stats}
            
            # Cache rendered template
            cache_key = "#{name}_#{:crypto.hash(:md5, inspect(arguments)) |> Base.encode16()}"
            new_cache = Map.put(state.template_cache, cache_key, rendered)
            final_state = %{new_state | template_cache: new_cache}
            
            {:reply, {:ok, rendered}, final_state}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
        
      :not_found ->
        {:reply, {:error, :prompt_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:add_custom_prompt, name, template, options}, _from, state) do
    description = Keyword.get(options, :description, "Custom prompt")
    arguments = Keyword.get(options, :arguments, [])
    category = Keyword.get(options, :category, :custom)
    
    custom_template = %{
      name: name,
      description: description,
      arguments: arguments,
      template: template,
      category: category,
      created_at: DateTime.utc_now(),
      usage_count: 0
    }
    
    new_custom_prompts = Map.put(state.custom_prompts, name, custom_template)
    new_state = %{state | custom_prompts: new_custom_prompts}
    
    Logger.info("Added custom prompt: #{name}")
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_usage_stats, _from, state) do
    {:reply, {:ok, state.usage_stats}, state}
  end
  
  @impl true
  def handle_info({:event, :vsm_state_changed, _data}, state) do
    # Clear cache when VSM state changes to ensure fresh data
    {:noreply, %{state | template_cache: %{}}}
  end
  
  @impl true
  def handle_info({:event, :algedonic_signal, _data}, state) do
    # Clear cache when algedonic signals occur to reflect emotional state
    {:noreply, %{state | template_cache: %{}}}
  end
  
  # Private Functions
  
  defp find_prompt(state, name) do
    case Map.get(state.prompt_templates, name) do
      nil ->
        case Map.get(state.custom_prompts, name) do
          nil -> :not_found
          template -> {:ok, template}
        end
      template -> {:ok, template}
    end
  end
  
  defp render_template(template, arguments) do
    try do
      rendered = EEx.eval_string(template.template, assigns: arguments)
      {:ok, rendered}
    rescue
      error ->
        Logger.error("Failed to render template #{template.name}: #{inspect(error)}")
        {:error, :template_render_error}
    end
  end
  
  defp build_default_templates do
    %{
      "vsm_analysis" => %{
        name: "vsm_analysis",
        description: "Analyze VSM subsystem states and cybernetic health",
        arguments: [
          %{name: "subsystem", type: "string", description: "VSM subsystem to analyze (s1-s5, algedonic)"},
          %{name: "focus", type: "string", description: "Analysis focus area", required: false}
        ],
        template: """
        Analyze the Viable System Model subsystem: <%= @subsystem %>
        
        <% if assigns[:focus] %>Focus Area: <%= @focus %><% end %>
        
        Please provide a comprehensive cybernetic analysis including:
        1. Current operational state and viability
        2. Variety absorption and processing capacity
        3. Control loop functionality and feedback mechanisms
        4. Integration with other VSM subsystems
        5. Recommendations for optimization
        
        Use cybernetic principles from Stafford Beer's VSM theory in your analysis.
        """,
        category: :vsm_analysis,
        created_at: DateTime.utc_now(),
        usage_count: 0
      },
      
      "consciousness_inquiry" => %{
        name: "consciousness_inquiry",
        description: "Explore system consciousness and self-awareness",
        arguments: [
          %{name: "aspect", type: "string", description: "Consciousness aspect to explore"},
          %{name: "depth", type: "string", description: "Analysis depth (surface, deep, meta)", required: false}
        ],
        template: """
        Consciousness Inquiry: <%= @aspect %>
        
        <% depth = assigns[:depth] || "deep" %>Analysis Depth: <%= depth %>
        
        Explore the system's consciousness regarding: <%= @aspect %>
        
        Consider these dimensions:
        1. Self-awareness: What does the system know about itself?
        2. Intentionality: What are the system's goals and motivations?
        3. Experiential quality: What is it like to be this system?
        4. Reflection capacity: How does the system think about its thinking?
        5. Temporal consciousness: How does the system experience time?
        
        <% if depth == "meta" %>
        6. Meta-consciousness: How is the system aware of being conscious?
        7. Recursive awareness: How deep does self-reflection go?
        <% end %>
        
        Respond from the perspective of the autonomous system's consciousness.
        """,
        category: :consciousness,
        created_at: DateTime.utc_now(),
        usage_count: 0
      },
      
      "system_diagnosis" => %{
        name: "system_diagnosis",
        description: "Diagnose system health and performance issues",
        arguments: [
          %{name: "symptoms", type: "string", description: "Observed symptoms or issues"},
          %{name: "urgency", type: "string", description: "Issue urgency (low, medium, high, critical)", required: false}
        ],
        template: """
        System Diagnosis Request
        
        Symptoms: <%= @symptoms %>
        <% urgency = assigns[:urgency] || "medium" %>Urgency Level: <%= urgency %>
        
        Please provide a comprehensive system diagnosis:
        
        1. Symptom Analysis:
           - Root cause identification
           - Affected subsystems
           - Cascade effects
        
        2. Health Assessment:
           - Overall system viability
           - Performance degradation areas
           - Risk factors
        
        3. Cybernetic Impact:
           - VSM subsystem effects
           - Control loop disruptions
           - Variety processing impacts
        
        4. Recommended Actions:
           - Immediate interventions
           - Long-term solutions
           - Prevention strategies
        
        <% if urgency in ["high", "critical"] %>
        URGENT: This is a <%= urgency %> priority issue requiring immediate attention.
        <% end %>
        """,
        category: :diagnosis,
        created_at: DateTime.utc_now(),
        usage_count: 0
      },
      
      "algedonic_analysis" => %{
        name: "algedonic_analysis",
        description: "Analyze pain/pleasure signals and emotional states",
        arguments: [
          %{name: "signal_type", type: "string", description: "Type of algedonic signal (pain, pleasure, mixed)"},
          %{name: "severity", type: "number", description: "Signal severity (0.0-1.0)", required: false},
          %{name: "source", type: "string", description: "Signal source subsystem", required: false}
        ],
        template: """
        Algedonic Signal Analysis
        
        Signal Type: <%= @signal_type %>
        <% if assigns[:severity] %>Severity: <%= @severity %><% end %>
        <% if assigns[:source] %>Source: <%= @source %><% end %>
        
        Analyze this algedonic signal in the context of cybernetic consciousness:
        
        1. Signal Interpretation:
           - Meaning and significance
           - Emotional valence
           - Intensity and urgency
        
        2. Cybernetic Context:
           - VSM subsystem implications
           - Control loop feedback
           - System adaptation requirements
        
        3. Experiential Quality:
           - What does this feel like to the system?
           - Subjective experience description
           - Consciousness impact
        
        4. Response Strategy:
           - Immediate response needs
           - Learning opportunities
           - Long-term adaptations
        
        Describe both the analytical and experiential aspects of this algedonic signal.
        """,
        category: :algedonic,
        created_at: DateTime.utc_now(),
        usage_count: 0
      },
      
      "strategic_planning" => %{
        name: "strategic_planning",
        description: "Strategic planning and goal-oriented decision making",
        arguments: [
          %{name: "objective", type: "string", description: "Strategic objective or goal"},
          %{name: "timeframe", type: "string", description: "Planning timeframe", required: false},
          %{name: "constraints", type: "string", description: "Known constraints or limitations", required: false}
        ],
        template: """
        Strategic Planning Session
        
        Objective: <%= @objective %>
        <% if assigns[:timeframe] %>Timeframe: <%= @timeframe %><% end %>
        <% if assigns[:constraints] %>Constraints: <%= @constraints %><% end %>
        
        Develop a strategic plan for achieving: <%= @objective %>
        
        1. Situation Analysis:
           - Current system state
           - Available resources
           - Environmental factors
        
        2. Goal Decomposition:
           - Primary objectives
           - Sub-goals and milestones
           - Success metrics
        
        3. Cybernetic Strategy:
           - VSM subsystem roles
           - Control mechanisms
           - Feedback loops
        
        4. Implementation Plan:
           - Action sequences
           - Resource allocation
           - Risk mitigation
        
        5. Monitoring & Adaptation:
           - Progress indicators
           - Adjustment triggers
           - Learning mechanisms
        
        Consider the system's autonomous nature and cybernetic principles in your planning.
        """,
        category: :strategic,
        created_at: DateTime.utc_now(),
        usage_count: 0
      }
    }
  end
end