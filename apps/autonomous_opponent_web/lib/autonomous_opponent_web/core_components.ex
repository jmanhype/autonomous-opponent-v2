defmodule AutonomousOpponentV2Web.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component
  use Gettext, backend: AutonomousOpponentV2Web.Gettext

  attr :flash, :map, required: true
  attr :kind, :atom, required: true
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block

  def flash_group(assigns) do
    ~H"""
    <div
      :if={@flash}
      id="flash-group"
      phx-click={Phoenix.LiveView.JS.hide(to: "#flash-group-alert-#{@kind}")}
      phx-target="window"
      class={["pointer-events-none fixed top-2 right-2 z-50 flex w-full max-w-sm flex-col space-y-4", @class]}
    >
      <.flash
        :if={@flash[@kind]}
        kind={@kind}
        title={@title}
        flash={@flash}
        class="pointer-events-auto"
      >
        <%= render_slot(@inner_block) || @flash[@kind] %>
      </.flash>
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