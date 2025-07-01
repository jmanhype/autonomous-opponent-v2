-- Create databases for umbrella apps
CREATE DATABASE autonomous_opponent_prod;
CREATE DATABASE autonomous_opponent_core_prod;
CREATE DATABASE autonomous_opponent_web_prod;

-- Grant all privileges to postgres user
GRANT ALL PRIVILEGES ON DATABASE autonomous_opponent_prod TO postgres;
GRANT ALL PRIVILEGES ON DATABASE autonomous_opponent_core_prod TO postgres;
GRANT ALL PRIVILEGES ON DATABASE autonomous_opponent_web_prod TO postgres;