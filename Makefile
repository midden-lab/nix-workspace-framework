# Test and maintenance entry points — CI (.github/workflows/test.yml) runs `make test`.

.PHONY: help test check integration audit update

help:  ## Show this help menu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

test: check integration  ## Run full test suite (check + integration)

check:  ## Pure regression suite (tests/checks.nix)
	nix flake check

integration:  ## Template onboarding + direnv end-to-end; needs a real Nix daemon
	./tests/integration.sh

audit:  ## Scan for leaked secrets/identifiers before committing (public repo)
	@if [ -f "$$HOME/.config/nix-workspace-framework/leak-patterns.txt" ]; then \
		grep -rinf "$$HOME/.config/nix-workspace-framework/leak-patterns.txt" . --exclude-dir=.git \
			&& (echo "FAIL: Leak patterns found in repository!" >&2; exit 1) \
			|| echo "Leak audit clean: no pattern matches found."; \
	else \
		echo "Notice: ~/.config/nix-workspace-framework/leak-patterns.txt not present. Skipped."; \
	fi

update:  ## Update nixpkgs pin and run tests
	nix flake update
	$(MAKE) test
