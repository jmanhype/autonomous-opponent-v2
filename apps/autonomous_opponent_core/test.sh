#!/bin/bash
# Test runner script with proper environment setup

export MIX_ENV=test
export AUTONOMOUS_OPPONENT_CORE_DATABASE_URL="postgres://postgres:postgres@localhost/autonomous_opponent_core_test"
export AUTONOMOUS_OPPONENT_V2_DATABASE_URL="postgres://postgres:postgres@localhost/autonomous_opponent_v2_test"

mix test $@