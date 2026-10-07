set shell := ["bash", "-uc"]
import '.cicd/workflow.just'

# List the recipes
default:
    @just --list

# Check fleet.toml against the inventory contract of the pinned tools (.cicd)
check-inventory:
    python3 .cicd/fleet/lib/check-inventory.py fleet.toml

