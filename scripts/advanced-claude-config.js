// Advanced Claude Code configuration for VSM development
// Direct SDK usage for specialized VSM analysis

import { createClaudeCode } from 'task-master-ai/ai-providers/custom-sdk/claude-code';

// VSM Cybernetic Architect - Read-only analysis with VSM focus
export const vsmArchitect = createClaudeCode({
  defaultSettings: {
    maxTurns: 8, // Complex cybernetic analysis requires multiple iterations
    customSystemPrompt: `You are a cybernetic systems architect expert in Stafford Beer's Viable System Model. 
    Analyze all code and architecture through the lens of:
    - Beer's 5 subsystem principles (S1-S5)
    - Variety engineering and Ashby's Law
    - Algedonic channels for pain/pleasure signals
    - Recursive viability and autonomous operation
    - Environmental coupling and adaptation
    
    Focus on authentic VSM implementation, not superficial labeling.`,
    allowedTools: ['Read', 'LS', 'Grep', 'Glob'], // Read-only for architecture analysis
    disallowedTools: ['Write', 'Edit', 'MultiEdit'] // Prevent accidental modifications
  }
});

// V1 Component Integration Specialist - Full access for integration work
export const v1Integrator = createClaudeCode({
  defaultSettings: {
    maxTurns: 5,
    customSystemPrompt: `You are a systems integration specialist focused on integrating V1 components 
    with V2's VSM framework. Analyze component readiness, identify integration points, and provide 
    practical implementation strategies. Focus on:
    - V1 component capabilities and limitations
    - VSM integration patterns and adapters
    - Performance implications and optimizations
    - Integration testing strategies`,
    allowedTools: ['Read', 'LS', 'Grep', 'Glob', 'Edit', 'MultiEdit'], // Full access for integration
    disallowedTools: ['Bash'] // Prevent system command execution
  }
});

// Security Hardening Specialist - Security-focused analysis and implementation
export const securityHardener = createClaudeCode({
  defaultSettings: {
    maxTurns: 3, // Focused security analysis
    customSystemPrompt: `You are a cybersecurity specialist focused on hardening the VSM system.
    Analyze code for security vulnerabilities, implement proper secrets management, and ensure
    compliance with security best practices. Focus on:
    - Exposed API keys and credential management
    - Input validation and sanitization
    - Encryption and secure communication
    - Audit logging and compliance
    - Access control and permission management`,
    allowedTools: ['Read', 'LS', 'Grep', 'Edit'], // Limited write access for security fixes
    disallowedTools: ['Bash', 'Write'] // Prevent system commands and file creation
  }
});

// Performance Optimizer - Read-only performance analysis
export const performanceOptimizer = createClaudeCode({
  defaultSettings: {
    maxTurns: 4,
    customSystemPrompt: `You are a performance optimization specialist for Elixir/OTP systems.
    Analyze code for performance bottlenecks, memory usage, and scalability issues. Focus on:
    - GenServer state management and message passing
    - Supervision tree optimization
    - Memory allocation and garbage collection
    - Concurrency patterns and race conditions
    - Database query optimization and connection pooling`,
    allowedTools: ['Read', 'LS', 'Grep', 'Glob'], // Read-only for analysis
    disallowedTools: ['Write', 'Edit', 'MultiEdit', 'Bash']
  }
});

// Usage examples for Task Master integration
export const vsmTaskConfigs = {
  // For cybernetic architecture analysis
  'vsm-analysis': {
    model: vsmArchitect('opus'),
    focus: 'VSM compliance and Beer\'s principle adherence'
  },
  
  // For V1 component integration
  'v1-integration': {
    model: v1Integrator('sonnet'),
    focus: 'Component readiness and integration complexity'
  },
  
  // For security hardening
  'security-hardening': {
    model: securityHardener('sonnet'),
    focus: 'Security vulnerabilities and hardening strategy'
  },
  
  // For performance optimization
  'performance-optimization': {
    model: performanceOptimizer('sonnet'),
    focus: 'Performance bottlenecks and optimization opportunities'
  }
};

// Integration with Task Master workflow
export function getSpecializedModel(taskType, complexity = 'standard') {
  const modelMap = {
    'vsm-subsystem': vsmArchitect(complexity === 'high' ? 'opus' : 'sonnet'),
    'v1-integration': v1Integrator('sonnet'),
    'security-task': securityHardener('sonnet'),
    'performance-task': performanceOptimizer('sonnet')
  };
  
  return modelMap[taskType] || vsmArchitect('sonnet');
}