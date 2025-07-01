alias AutonomousOpponentV2Core.Repo
alias AutonomousOpponentV2Core.VSM.System
require Logger

# Clear existing data (optional, for development)
Repo.delete_all(System)

# Seed VSM Systems
Logger.info("Seeding VSM Systems...")

%System{name: "System 5", system_type: "s5", status: "active"} |> Repo.insert!()
%System{name: "System 4", system_type: "s4", status: "active"} |> Repo.insert!()
%System{name: "System 3", system_type: "s3", status: "active"} |> Repo.insert!()
%System{name: "System 2", system_type: "s2", status: "active"} |> Repo.insert!()
%System{name: "Subsystem 1", system_type: "s1", status: "active"} |> Repo.insert!()
%System{name: "Subsystem 2", system_type: "s1", status: "active"} |> Repo.insert!()
%System{name: "Subsystem 3", system_type: "s1", status: "active"} |> Repo.insert!()
%System{name: "Subsystem 4", system_type: "s1", status: "active"} |> Repo.insert!()
%System{name: "Subsystem 5", system_type: "s1", status: "active"} |> Repo.insert!()

Logger.info("VSM Systems seeded successfully.")