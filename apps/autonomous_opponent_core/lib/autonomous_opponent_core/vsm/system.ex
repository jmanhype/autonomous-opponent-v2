defmodule AutonomousOpponentV2Core.VSM.System do
  @moduledoc """
  Ecto schema for VSM System records.
  These records define the components that the VSM Supervisor will dynamically start.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, primary_key: true} # ID should be set externally, ideally with a content-based hash
  @foreign_key_type :binary_id
  

  schema "vsm_systems" do
    field :name, :string
    field :description, :string
    field :system_type, :string # e.g., "s1", "s2", "s3", "s4", "s5", "subsystem"
    field :status, :string # e.g., "active", "inactive"
    field :parent_id, :binary_id
    field :config, :map # Flexible field for component-specific configuration

    timestamps()
  end

  @doc false
  def changeset(system, attrs) do
    system
    |> cast(attrs, [:name, :description, :system_type, :status, :parent_id, :config])
    |> validate_required([:name, :system_type, :status])
  end
end
