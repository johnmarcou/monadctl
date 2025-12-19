# monadctl

Minimal control tool for managing Monad blockchain nodes.

## Installation

```bash
install -m 0755 <(curl https://raw.githubusercontent.com/johnmarcou/monadctl/refs/heads/main/monadctl) /usr/local/bin/monadctl
```

## Usage

```bash
# Spin up a new node
monadctl up [network] [disk]

# Stop the node
monadctl down

# Service management
monadctl start          # Start services
monadctl stop           # Stop services
monadctl restart        # Restart services

# Node operations
monadctl reset          # Soft reset (download forkpoint and validators)
monadctl reset --hard   # Hard reset (restore from snapshot)
monadctl flush          # Clear workspace, database and logs

# Configuration
monadctl config         # Print node configuration
monadctl edit           # Edit node configuration
monadctl reload         # Reload configuration

# Monitoring
monadctl status         # Show node status
monadctl init           # Initialize node configuration
```

## Default Configuration

- Network: `mainnet`
- Config file: `/home/monad/monad-bft/config/node.toml`
- Default disk: `nvme1n1`

## Warning

This script is experimental and not officially supported. Use at your own risk.
