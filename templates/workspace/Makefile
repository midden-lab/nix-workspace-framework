.PHONY: help check update update-framework sync-hooks verify

help:  ## Show this help menu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

check:  ## Validate flake and evaluate devShells
	nix flake check

update:  ## Update all inputs and validate
	nix flake update
	nix flake check
	@echo "\nAll flake inputs updated and verified. Run 'direnv reload' in active project shells."

update-framework:  ## Update framework input, re-sync hooks.zsh, and validate
	nix flake update framework
	nix run .#sync-hooks
	nix flake check
	@echo "\nFramework updated and hooks.zsh synchronized."

sync-hooks:  ## Regenerate ./hooks.zsh from the currently pinned framework
	nix run .#sync-hooks

verify:  ## Verify tool banners across devShells
	@echo "=== Example devShell ==="
	@nix develop .#example --command versions
