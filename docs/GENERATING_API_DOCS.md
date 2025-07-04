# Generating API Documentation for MCP Gateway

This guide explains how to generate comprehensive API documentation for the MCP Gateway modules using ExDoc.

## Setup

### 1. Add ExDoc Dependency

First, add the `ex_doc` dependency to your `mix.exs` file:

```elixir
defp deps do
  [
    # ... existing dependencies ...
    {:ex_doc, "~> 0.31", only: :dev, runtime: false}
  ]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

### 2. Configure Documentation

Add documentation configuration to your `mix.exs`:

```elixir
def project do
  [
    # ... existing configuration ...
    name: "MCP Gateway",
    source_url: "https://github.com/jmanhype/autonomous-opponent-v2",
    homepage_url: "https://github.com/jmanhype/autonomous-opponent-v2",
    docs: [
      main: "MCP Gateway",
      logo: "priv/static/images/logo.png",
      extras: [
        "README.md",
        "docs/MCP_GATEWAY_IMPLEMENTATION.md",
        "docs/MCP_GATEWAY_TROUBLESHOOTING.md",
        "docs/MCP_GATEWAY_TESTING.md"
      ],
      groups_for_extras: [
        "Guides": ~r/docs\/.*/
      ],
      groups_for_modules: [
        "Core": [
          AutonomousOpponentCore.MCP.Gateway,
          AutonomousOpponentCore.MCP.Transport.Router
        ],
        "Transports": [
          AutonomousOpponentCore.MCP.Transport.WebSocket,
          AutonomousOpponentCore.MCP.Transport.HTTPSSE
        ],
        "Infrastructure": [
          AutonomousOpponentCore.MCP.Pool.ConnectionPool,
          AutonomousOpponentCore.MCP.LoadBalancer.ConsistentHash
        ],
        "Phoenix Integration": [
          AutonomousOpponentWeb.MCPChannel,
          AutonomousOpponentWeb.MCPSocket,
          AutonomousOpponentWeb.MCPSSEController
        ]
      ],
      nest_modules_by_prefix: [
        AutonomousOpponentCore.MCP,
        AutonomousOpponentWeb
      ],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  ]
end

defp before_closing_body_tag(:html) do
  """
  <script>
    // Add custom JS for better navigation
    document.addEventListener('DOMContentLoaded', function() {
      // Highlight current module in sidebar
      const currentPath = window.location.pathname;
      const links = document.querySelectorAll('.sidebar a');
      links.forEach(link => {
        if (link.getAttribute('href') === currentPath) {
          link.classList.add('current');
        }
      });
    });
  </script>
  <style>
    .sidebar a.current {
      font-weight: bold;
      color: #5e35b1;
    }
  </style>
  """
end

defp before_closing_body_tag(_), do: ""
```

## Generating Documentation

### Basic Generation

To generate the API documentation:

```bash
mix docs
```

This will create documentation in the `doc/` directory.

### Advanced Options

```bash
# Generate docs with specific formatter
mix docs --formatter html

# Generate docs with custom output directory
mix docs --output custom_docs

# Generate docs for a specific app in umbrella
cd apps/autonomous_opponent_core && mix docs

# Generate docs with assets
mix docs --assets priv/static
```

### Viewing Documentation

After generation, open the documentation:

```bash
# macOS
open doc/index.html

# Linux
xdg-open doc/index.html

# Windows
start doc/index.html

# Or start a local server
cd doc && python -m http.server 8000
# Then visit http://localhost:8000
```

## Documentation Best Practices

### Module Documentation

Ensure all modules have comprehensive `@moduledoc`:

```elixir
defmodule AutonomousOpponentCore.MCP.Gateway do
  @moduledoc """
  Main supervisor for the MCP Gateway.
  
  The Gateway manages all transport layers (WebSocket and HTTP+SSE) and provides
  intelligent routing, connection pooling, and VSM integration.
  
  ## Architecture
  
  The Gateway supervises the following components:
  
  * `Transport.WebSocket` - WebSocket transport handler
  * `Transport.HTTPSSE` - Server-Sent Events transport
  * `Transport.Router` - Intelligent message routing
  * `Pool.ConnectionPool` - Connection pool management
  * `LoadBalancer.ConsistentHash` - Load distribution
  
  ## Configuration
  
      config :autonomous_opponent_core, :mcp_gateway,
        pool: [size: 100, overflow: 50],
        transports: [
          websocket: [...],
          http_sse: [...]
        ]
  
  ## Examples
  
      # Start the gateway (usually done by application supervisor)
      {:ok, pid} = Gateway.start_link([])
      
      # Connect a client
      {:ok, conn} = Gateway.connect("client_123", transport: :websocket)
  """
  
  use Supervisor
  # ... rest of module
end
```

### Function Documentation

Document all public functions with `@doc`:

```elixir
@doc """
Connects a client to the gateway using the specified transport.

## Parameters

  * `client_id` - Unique identifier for the client
  * `opts` - Connection options
    * `:transport` - Transport type (`:websocket` or `:http_sse`), defaults to `:auto`
    * `:metadata` - Optional metadata map for the connection
    * `:priority` - Connection priority (`:low`, `:normal`, `:high`)

## Returns

  * `{:ok, connection}` - Successful connection with connection struct
  * `{:error, reason}` - Connection failed with reason

## Examples

    # Auto-select transport
    {:ok, conn} = Gateway.connect("user_123")
    
    # Force specific transport
    {:ok, conn} = Gateway.connect("user_123", transport: :websocket)
    
    # With metadata
    {:ok, conn} = Gateway.connect("user_123", 
      transport: :http_sse,
      metadata: %{device: "mobile", version: "2.1.0"}
    )

## Errors

Common error reasons:

  * `:pool_exhausted` - Connection pool is full
  * `:rate_limited` - Client exceeded rate limit
  * `:transport_unavailable` - Requested transport is down
  * `:policy_violation` - VSM policy prevents connection
"""
@spec connect(String.t(), keyword()) :: {:ok, Connection.t()} | {:error, atom()}
def connect(client_id, opts \\ []) do
  # Implementation
end
```

### Type Specifications

Add type specs for better documentation:

```elixir
@type client_id :: String.t()
@type transport_type :: :websocket | :http_sse
@type connection_opts :: [
  transport: transport_type,
  metadata: map(),
  priority: :low | :normal | :high
]

@type connection :: %Connection{
  id: String.t(),
  client_id: client_id(),
  transport: transport_type(),
  connected_at: DateTime.t(),
  metadata: map()
}

@type error_reason :: 
  :pool_exhausted |
  :rate_limited |
  :transport_unavailable |
  :policy_violation |
  atom()
```

### Callback Documentation

For behaviours and protocols:

```elixir
defmodule AutonomousOpponentCore.MCP.Transport do
  @moduledoc """
  Behaviour for MCP transport implementations.
  
  Transport modules must implement this behaviour to be compatible
  with the gateway routing system.
  """
  
  @doc """
  Registers a connection for the given client.
  
  Called when a client connects through this transport.
  """
  @callback register_connection(client_id :: String.t(), pid :: pid()) :: 
    :ok | {:error, term()}
  
  @doc """
  Sends a message to the connected client.
  
  The transport should handle encoding and delivery.
  """
  @callback send_message(client_id :: String.t(), message :: map()) ::
    :ok | {:error, term()}
    
  @doc """
  Checks if the transport is healthy and can accept connections.
  """
  @callback health_check() :: {:ok, map()} | {:error, term()}
end
```

## Custom Documentation Pages

Create custom guides in the `guides/` directory:

```markdown
# guides/getting_started.md
# Getting Started with MCP Gateway

This guide walks you through setting up and using the MCP Gateway...

## Installation

1. Add the dependency...
2. Configure...
3. Start the application...

## First Connection

Let's create your first connection...
```

Then include them in your docs configuration:

```elixir
docs: [
  extras: [
    "guides/getting_started.md",
    "guides/architecture.md",
    "guides/deployment.md"
  ],
  groups_for_extras: [
    "Tutorials": Path.wildcard("guides/tutorials/*.md"),
    "How-To Guides": Path.wildcard("guides/how_to/*.md"),
    "References": Path.wildcard("guides/references/*.md")
  ]
]
```

## Hosting Documentation

### GitHub Pages

1. Generate docs:
   ```bash
   mix docs
   ```

2. Copy to gh-pages branch:
   ```bash
   git checkout --orphan gh-pages
   git rm -rf .
   cp -r doc/* .
   git add .
   git commit -m "Update documentation"
   git push origin gh-pages
   ```

3. Access at: `https://yourusername.github.io/your-repo/`

### Documentation CI/CD

Add to `.github/workflows/docs.yml`:

```yaml
name: Generate Documentation
on:
  push:
    branches: [main, master]

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
          
      - name: Install Dependencies
        run: |
          mix deps.get
          mix compile
          
      - name: Generate Documentation
        run: mix docs
        
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./doc
```

## Documentation Checklist

Before generating final documentation:

- [ ] All public modules have `@moduledoc`
- [ ] All public functions have `@doc` with examples
- [ ] All callbacks are documented
- [ ] Type specs are added where appropriate
- [ ] Examples compile and work
- [ ] Links between modules work
- [ ] Custom guides are included
- [ ] Logo and assets are in place
- [ ] Search functionality works
- [ ] Mobile responsive layout

## Troubleshooting

### Missing Modules

If some modules don't appear:
- Ensure they have `@moduledoc` (even if just `@moduledoc false`)
- Check they're compiled: `mix compile --force`
- Verify module naming matches patterns

### Broken Links

ExDoc will warn about broken links:
```
[warning] documentation references function 
AutonomousOpponentCore.MCP.Gateway.connect/2 but it doesn't exist
```

Fix by ensuring the referenced function exists or update the link.

### Large Documentation

For large projects:
```elixir
docs: [
  # Generate docs for only specific apps
  source_beam: ["_build/dev/lib/autonomous_opponent_core/ebin"],
  
  # Limit module depth
  nest_modules_by_prefix: [
    AutonomousOpponentCore.MCP
  ]
]
```

---

Following these steps will generate comprehensive, well-organized API documentation for the MCP Gateway that integrates seamlessly with the implementation, troubleshooting, and testing guides.