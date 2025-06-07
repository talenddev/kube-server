# Server Installation Scripts Library

A collection of repeatable, documented scripts for automating server installations on Linux systems.

## Overview

This library provides production-ready scripts for installing and configuring various server components. All scripts are designed to be:
- **Repeatable**: Can be run multiple times without causing issues
- **Self-contained**: Install all required dependencies
- **Well-documented**: Clear documentation on purpose and requirements
- **Tested**: Work on common Linux distributions

## Prerequisites

- Linux system (Ubuntu, Debian, CentOS, RHEL supported)
- Root access via sudo
- Internet connectivity for package downloads

## Directory Structure

```
├── scripts/
│   ├── web/          # Web server installations (nginx, apache, etc.)
│   ├── database/     # Database installations (mysql, postgresql, etc.)
│   ├── monitoring/   # Monitoring tools (prometheus, grafana, etc.)
│   ├── security/     # Security tools and hardening scripts
│   └── utilities/    # Common utilities and helper functions
├── docs/             # Detailed documentation
└── examples/         # Example configurations and usage
```

## Script Documentation Format

Each script includes:
1. **Purpose**: What the script does
2. **Dependencies**: Required system packages
3. **Variables**: Configurable parameters
4. **Usage**: How to run the script
5. **Post-installation**: What to do after running

## Usage

1. Clone this repository
2. Navigate to the desired script category
3. Review the script documentation
4. Run with sudo: `sudo ./script-name.sh`

## Contributing

When adding new scripts:
1. Follow the documentation template
2. Test on clean systems
3. Include rollback procedures where applicable
4. Add error handling and logging