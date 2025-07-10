#!/bin/bash
# Check system status via HTTP endpoint
curl -s http://localhost:4000/health | jq . || echo "Health endpoint failed"
