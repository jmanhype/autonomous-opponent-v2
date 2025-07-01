#!/bin/bash
# VSM-specific Task Master commands for development workflow

# VSM Subsystem Implementation Flow
vsm_implement_subsystem() {
    local subsystem=$1
    echo "🧠 Implementing VSM $subsystem with cybernetic analysis..."
    
    # Generate subsystem tasks
    task-master parse-prd --input="vsm-${subsystem}-prd.txt" --model=vsm-architect
    
    # Get cybernetic compliance analysis
    echo "🔍 Analyzing Beer's principle compliance..."
    task-master analyze-complexity --model=vsm-architect --focus="$subsystem cybernetic viability"
    
    # Show next implementation task
    task-master next --tags="vsm,${subsystem}" --model=implementation
}

# V1 Component Integration Flow
v1_integration_analysis() {
    local component=$1
    echo "🔧 Analyzing V1 $component for VSM integration..."
    
    # Component readiness assessment
    task-master analyze-complexity --model=component-analysis --focus="$component VSM integration"
    
    # Security implications
    task-master analyze-complexity --model=security-audit --focus="$component security hardening"
    
    # Implementation strategy
    task-master next --tags="v1,integration,$component" --model=implementation
}

# Security Hardening Flow
security_sprint() {
    echo "🔒 Starting security hardening sprint..."
    
    # Generate security tasks
    task-master parse-prd --input="security-hardening-prd.txt" --model=security-audit
    
    # Critical security analysis
    task-master next --priority=critical --tags=security --model=security-audit
    
    # Show security compliance status
    task-master status --filter="tags:security"
}

# Daily VSM Development Flow
daily_vsm_standup() {
    echo "📊 Daily VSM Development Standup"
    echo "================================"
    
    # Show today's priorities
    echo "🎯 Today's Priorities:"
    task-master next --limit=3 --model=vsm-architect
    
    # Component readiness status
    echo "📈 Component Readiness:"
    task-master status --filter="tags:v1" --model=component-analysis
    
    # Security status
    echo "🔒 Security Status:"
    task-master status --filter="tags:security,priority:critical"
    
    # VSM implementation progress
    echo "🧠 VSM Progress:"
    task-master status --filter="tags:vsm" --model=vsm-architect
}

# Phase transition readiness check
phase_readiness_check() {
    local phase=$1
    echo "✅ Phase $phase Readiness Assessment"
    echo "=================================="
    
    # Analyze completion criteria
    task-master analyze-complexity --model=vsm-architect --focus="Phase $phase completion criteria"
    
    # Component status
    task-master status --filter="tags:phase-$phase" --model=component-analysis
    
    # Security compliance
    task-master status --filter="tags:security,phase-$phase" --model=security-audit
}

# Export functions for use
export -f vsm_implement_subsystem
export -f v1_integration_analysis  
export -f security_sprint
export -f daily_vsm_standup
export -f phase_readiness_check

echo "VSM Task Master commands loaded!"
echo "Available commands:"
echo "  vsm_implement_subsystem [s1|s2|s3|s4|s5]"
echo "  v1_integration_analysis [component_name]"
echo "  security_sprint"
echo "  daily_vsm_standup"
echo "  phase_readiness_check [0|1|2|3]"