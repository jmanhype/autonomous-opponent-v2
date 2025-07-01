defmodule AutonomousOpponentV2Core.Repo.Migrations.CreateVsmSystemsTable do
  use Ecto.Migration

  def change do
    create table(:vsm_systems, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :system_type, :string, null: false
      add :status, :string, null: false
      add :parent_id, :binary_id
      add :config, :map

      timestamps()
    end

    create unique_index(:vsm_systems, [:name])
  end
end
