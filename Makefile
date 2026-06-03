# grove-pau-deploy Makefile
#
# Prerequisites:
#   - ETH_FROM: deployer address
#   - MAINNET_RPC_URL: mainnet RPC URL
#   - MAINNET_API_KEY: Etherscan key (for --verify)
#   - foundry keystore account named "deployer" (cast wallet import deployer --interactive)
#
# Deployment order (per env):
#   1. deploy    — deploys AccessControls, Controller and AdministeredAgent (0-Deploy.s.sol)
#   2. configure — migrates config and transfers admin roles to the final admin (1-Configure.s.sol)
#
# Inputs:
#   0-Deploy:    script/input/{chainId}/deploy-mainnet-{env}.json
#   1-Configure: script/input/{chainId}/config-mainnet-{env}.json
#
# Each target has -dryrun variant that simulates without broadcasting or verifying.

# --------------------------------------------------------------------------------------------------
# Build & Test                                                                                     #
# --------------------------------------------------------------------------------------------------

build:
	forge build

test:
	forge test

clean:
	forge clean

# --------------------------------------------------------------------------------------------------
# 0-Deploy: AccessControls + Controller + AdministeredAgent                                        #
# --------------------------------------------------------------------------------------------------

deploy-mainnet-production:
	ENV=production forge script script/0-Deploy.s.sol:DeployAccessControlsAndController \
		--sender $(ETH_FROM) --account deployer --broadcast --verify --rpc-url $(MAINNET_RPC_URL)

deploy-mainnet-staging:
	ENV=staging forge script script/0-Deploy.s.sol:DeployAccessControlsAndController \
		--sender $(ETH_FROM) --account deployer --broadcast --verify --rpc-url $(MAINNET_RPC_URL)

deploy-mainnet-production-dryrun:
	ENV=production forge script script/0-Deploy.s.sol:DeployAccessControlsAndController \
		--sender $(ETH_FROM) --account deployer --rpc-url $(MAINNET_RPC_URL)

deploy-mainnet-staging-dryrun:
	ENV=staging forge script script/0-Deploy.s.sol:DeployAccessControlsAndController \
		--sender $(ETH_FROM) --account deployer --rpc-url $(MAINNET_RPC_URL)

# --------------------------------------------------------------------------------------------------
# 1-Configure: copy config + transfer admin roles                                                  #
# --------------------------------------------------------------------------------------------------

configure-mainnet-production:
	ENV=production forge script script/1-Configure.s.sol:ConfigureController \
		--sender $(ETH_FROM) --account deployer --broadcast --verify --rpc-url $(MAINNET_RPC_URL)

configure-mainnet-staging:
	ENV=staging forge script script/1-Configure.s.sol:ConfigureController \
		--sender $(ETH_FROM) --account deployer --broadcast --verify --rpc-url $(MAINNET_RPC_URL)

configure-mainnet-production-dryrun:
	ENV=production forge script script/1-Configure.s.sol:ConfigureController \
		--sender $(ETH_FROM) --account deployer --rpc-url $(MAINNET_RPC_URL)

configure-mainnet-staging-dryrun:
	ENV=staging forge script script/1-Configure.s.sol:ConfigureController \
		--sender $(ETH_FROM) --account deployer --rpc-url $(MAINNET_RPC_URL)
