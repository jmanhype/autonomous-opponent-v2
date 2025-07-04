#!/bin/bash
# RabbitMQ wrapper script to use the Generic Unix version with proper Erlang

# Set RabbitMQ home to our extracted version
export RABBITMQ_HOME="/Users/speed/autonomous-opponent-v2/tmp/rabbitmq_server-4.0.4"

# Set configuration paths
export RABBITMQ_CONFIG_FILE="/opt/homebrew/etc/rabbitmq/rabbitmq"
export RABBITMQ_CONF_ENV_FILE="/opt/homebrew/etc/rabbitmq/rabbitmq-env.conf"
export RABBITMQ_ENABLED_PLUGINS_FILE="/opt/homebrew/etc/rabbitmq/enabled_plugins"

# Set data directories to use Homebrew locations
export RABBITMQ_MNESIA_BASE="/opt/homebrew/var/lib/rabbitmq/mnesia"
export RABBITMQ_LOG_BASE="/opt/homebrew/var/log/rabbitmq"

# Ensure directories exist
mkdir -p "$RABBITMQ_MNESIA_BASE"
mkdir -p "$RABBITMQ_LOG_BASE"

# Execute the appropriate command
case "$1" in
    server)
        exec "$RABBITMQ_HOME/sbin/rabbitmq-server" "${@:2}"
        ;;
    ctl)
        exec "$RABBITMQ_HOME/sbin/rabbitmqctl" "${@:2}"
        ;;
    plugins)
        exec "$RABBITMQ_HOME/sbin/rabbitmq-plugins" "${@:2}"
        ;;
    diagnostics)
        exec "$RABBITMQ_HOME/sbin/rabbitmq-diagnostics" "${@:2}"
        ;;
    *)
        echo "Usage: $0 {server|ctl|plugins|diagnostics} [args...]"
        exit 1
        ;;
esac