defmodule AutonomousOpponentV2Web.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component
  use Gettext, backend: AutonomousOpponentV2Web.Gettext

  attr :flash, :map, required: true
  attr :kind, :atom, default: nil
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block

  def flash_group(assigns) do
    # If kind is not specified, show all flash messages
    assigns = 
      if is_nil(assigns[:kind]) do
        assign(assigns, :flash_kinds, [:info, :error])
      else
        assign(assigns, :flash_kinds, [assigns.kind])
      end
      
    ~H"""
    <div class={["fixed top-2 right-2 z-50 flex w-full max-w-sm flex-col space-y-4", @class]}>
      <%= for kind <- @flash_kinds do %>
        <.flash
          :if={@flash && @flash[kind]}
          kind={kind}
          title={@title}
          flash={@flash}
          class="pointer-events-auto"
        >
          <%= @flash[kind] %>
        </.flash>
      <% end %>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :kind, :atom, required: true
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block

  def flash(assigns) do
    ~H"""
    <div
      id={"flash-group-alert-#{@kind}"}
      phx-leave-active="transition ease-in duration-150"
      phx-leave-from="opacity-100"
      phx-leave-to="opacity-0"
      role="alert"
      class={[
        "relative rounded-lg p-4 pr-10",
        @class,
        if(@kind == :info, do: " bg-green-50 text-green-800", else: ""),
        if(@kind == :error, do: " bg-red-50 text-red-800", else: "")
      ]}
    >
      <p :if={@title} class="font-semibold"><%= @title %></p>
      <p class="text-sm"><%= render_slot(@inner_block) %></p>
      <button
        type="button"
        class="absolute top-3 right-3"
        aria-label={gettext("Close")}
        phx-click={Phoenix.LiveView.JS.hide(to: "#flash-group-alert-#{@kind}")}
      >
        <span class="h-5 w-5"></span>
      </button>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(assigns) do
    ~H"""
    <span class={["inline-flex", @class]}>
      <!-- Icon placeholder: <%= @name %> -->
    </span>
    """
  end
end