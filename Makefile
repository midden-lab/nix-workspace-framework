# Test entry points — CI (.github/workflows/test.yml) runs exactly these,
# so a green `make test` locally means a green build.

.PHONY: test check integration

test: check integration  ## everything

check:  ## pure regression suite (tests/checks.nix)
	nix flake check

integration:  ## template onboarding + direnv end-to-end; needs a real Nix daemon
	./tests/integration.sh
