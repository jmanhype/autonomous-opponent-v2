defmodule AutonomousOpponentV2Web.CoreComponents do
  @moduledoc """
  Core UI components for the AutonomousOpponentV2 application.
  """
  use Phoenix.Component
  use Gettext, backend: AutonomousOpponentV2Web.Gettext

  @doc """
  Flash message group component
  """
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

  @doc """
  Flash message component
  """
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
      class={
        "relative rounded-lg p-4 pr-10"
        <> @class
        <> if(@kind == :info, do: " bg-green-50 text-green-800", else: "")
        <> if(@kind == :error, do: " bg-red-50 text-red-800", else: "")
      }
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

  @doc """
  Basic button component
  """
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :variant, :string, default: "primary"
  attr :size, :string, default: "md"
  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2",
        variant_class(@variant),
        size_class(@size),
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Input component
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :error, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global

  def input(assigns) do
    ~H"""
    <div class="mb-4">
      <%= if @label do %>
        <label for={@id} class="block text-sm font-medium text-gray-700 mb-1">
          <%= @label %>
        </label>
      <% end %>
      <input
        id={@id}
        name={@name}
        type={@type}
        class={[
          "w-full px-3 py-2 border rounded-md shadow-sm focus:outline-none focus:ring-1",
          error_class(@error),
          @class
        ]}
        {@rest}
      />
      <%= if @error do %>
        <p class="mt-1 text-sm text-red-600"><%= @error %></p>
      <% end %>
    </div>
    """
  end

  @doc """
  Icon component
  """
  attr :name, :string, required: true
  attr :class, :string, default: ""

  def icon(assigns) do
    ~H"""
    <span class={["inline-flex", @class]}>
      <!-- Icon placeholder: <%= @name %> -->
    </span>
    """
  end

  defp variant_class("primary"), do: "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
  defp variant_class("secondary"), do: "bg-gray-200 text-gray-900 hover:bg-gray-300 focus:ring-gray-500"
  defp variant_class("danger"), do: "bg-red-600 text-white hover:bg-red-700 focus:ring-red-500"
  defp variant_class(_), do: "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"

  defp size_class("sm"), do: "px-3 py-1.5 text-sm rounded"
  defp size_class("md"), do: "px-4 py-2 text-base rounded-md"
  defp size_class("lg"), do: "px-6 py-3 text-lg rounded-lg"
  defp size_class(_), do: "px-4 py-2 text-base rounded-md"

  defp error_class(nil), do: "border-gray-300 focus:border-blue-500 focus:ring-blue-500"
  defp error_class(_), do: "border-red-300 focus:border-red-500 focus:ring-red-500"
end