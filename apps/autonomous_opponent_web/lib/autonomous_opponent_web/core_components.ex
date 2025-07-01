defmodule AutonomousOpponentV2Web.CoreComponents do
  @moduledoc """
  Core UI components for the AutonomousOpponentV2 application.
  """
  use Phoenix.Component

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