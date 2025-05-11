# Creditcoin Docker for macOS

This project is a collection of scripts for easily setting up and managing Creditcoin nodes using Docker and OrbStack in a macOS environment.

## Key Features

- Creditcoin 3.0 node setup and management (`add3node.sh`)
- Creditcoin 2.0 legacy node setup and management (`add2node.sh`)
- Node cleanup and removal (`cleanup2.sh`, `cleanup3.sh`)
- Various options support: telemetry activation/deactivation, custom node names, pruning settings, etc.

## Installation

### Prerequisites

- macOS operating system
- Administrator privileges (required for some installation steps)

### Setup

1. Install utility scripts:

```bash
./setup.sh
```

2. Apply changes:

```bash
# zsh (default macOS shell)
source ~/.zshrc

# or bash
source ~/.bash_profile
```

3. OrbStack Configuration:
   - OrbStack must be managed through the **desktop application**.
   - After installation, open OrbStack.app and complete the initial setup.
   - Enable the auto-start option in the OrbStack app settings to start on system boot.

## Usage

### Creditcoin 3.0 Node Creation

```bash
./add3node.sh <node_number> [options]

# Options:
#   -v, --version      Node version (default: 3.39.0-mainnet)
#   -t, --telemetry    Enable telemetry (default: disabled)
#   -n, --name         Node name (default: 3Node<number>)
#   -p, --pruning      Pruning value setting (default: 0, no option added if 0)

# Usage examples:
./add3node.sh 0                      # Create node with default settings
./add3node.sh 1 -v 3.32.0-mainnet    # Create node with stable version
./add3node.sh 2 -t                   # Create node with telemetry enabled
./add3node.sh 3 -n ValidatorA        # Create node with specified name
./add3node.sh 4 -p 1000              # Create node with pruning value 1000
```

### Creditcoin 2.0 Legacy Node Creation

```bash
./add2node.sh <node_number> [options]

# Options:
#   -v, --version      Node version (default: 2.230.2-mainnet)
#   -t, --telemetry    Enable telemetry (default: disabled)
#   -n, --name         Node name (default: Node<number>)

# Usage examples:
./add2node.sh 0                        # Create node with default settings
./add2node.sh 1 -t -n ValidatorLegacy  # Create node with telemetry enabled and name
```

### Node Cleanup

```bash
# Creditcoin 2.0 legacy node cleanup
./cleanup2.sh

# Creditcoin 3.0 node cleanup
./cleanup3.sh
```

## Utility Commands

After running the setup script, the following commands become available:

### Node Management Commands

- `status` - Display a summary of all nodes' status
- `infoAll` - Show detailed information for all running nodes
- `checkVersion [node_name]` - Check node version
- `checkHealth [node_name]` - Check node health status
- `checkName [node_name]` - Check node name
- `checkPeers [node_name]` - Check node peers information
- `checkChain [node_name]` - Check chain status
- `getLatestBlock [node_name]` - Get latest block info
- `rotatekey [node_name]` - Rotate session keys
- `payout [node_name]` - Execute payout for a specific node
- `payoutAll` - Execute payouts for all running 3.0 nodes
- `payoutAllLegacy` - Execute payouts for all running 2.0 nodes
- `genkey [node_name]` - Generate node keys

### Docker Management Commands
- `cdcd` - Navigate to the Creditcoin Docker directory
- `dps` - List running containers
- `dpsa` - List all containers (including stopped ones)
- `dstats` - Show resource usage of containers
- `dip` - Show container IP addresses
- `drestart [container]` - Restart a container
- `dstop [container]` - Stop a container
- `dstart [container]` - Start a container
- `dlog [container]` - Show container logs
- `restartAll` - Restart all running nodes
- `stopAll` - Stop all running nodes
- `startAll` - Start all stopped nodes
- `dkill [node_name]` - Completely remove a specific node with confirmation prompt

### Session Keys Management Commands
- `backupkeys [node_name]` - Backup session keys of a node (stops the node if needed)
- `restorekeys [backup_file] [target_node]` - Restore session keys to a node (stops the node if needed)

### Shell Management Commands
- `updatesh` - Reload shell configuration (.zshrc or .bash_profile)
- `editsh` - Edit shell configuration
- `editdc` - Edit docker-compose.yml
- `editdcl` - Edit docker-compose-legacy.yml
- `editdf` - Edit Dockerfile
- `editdfl` - Edit Dockerfile.legacy
- `editenv` - Edit .env file

## Session Keys Management

Session keys are essential for validator operations. The utility provides two commands for securely managing session keys:

1. **Backing Up Session Keys**:
   ```bash
   backupkeys 3node0
   ```
   This command will:
   - Stop the node if it's running (after confirmation)
   - Backup session keys to a tar.gz file in the current directory
   - Restart the node if it was running

2. **Restoring Session Keys**:
   ```bash
   restorekeys ./3node0-keys-20250507-1234.tar.gz 3node1
   ```
   This command will:
   - Stop the target node if it's running (after confirmation)
   - Backup existing keys (if any)
   - Restore session keys from the backup file
   - Ask to restart the node

**Important**: Never run two nodes with the same session keys simultaneously, as this could result in slashing penalties.

## General Precautions

- Cleanup scripts delete all related containers, images, volumes, and directories. Backing up your data before use is recommended.
- The `dkill` command completely removes a specific node by stopping the container, removing it, and deleting all associated data.
- Sufficient system resources are required for node operation.
- When telemetry is enabled, node information is made public to the Creditcoin network.

## macOS Specific Notes

- These scripts are specifically optimized for macOS environments
- OrbStack must be managed through the desktop application
- OrbStack should be configured to start automatically at system boot (set in app settings)
- If accessing via SSH from a remote server, first run the OrbStack.app on local macOS to complete the initial setup

## Contributing

If you wish to contribute, you can participate in the following ways:

1. **Issue Reporting**: If you discover bugs or have improvement suggestions, please let us know through GitHub issues.
2. **Documentation**: You can contribute by improving documentation or adding usage examples.
3. **Testing**: Test in various environments and share your results.
4. **Optimization**: Script optimization and performance improvement suggestions are welcome.

All contributions are subject to review and approval by the administrator. Please contact the administrator before contributing.

## License

This project is proprietary software with all rights reserved. Unauthorized copying, distribution, or modification is prohibited. For usage permissions, please contact the author.

© 2025 sigmo2nd. All Rights Reserved.