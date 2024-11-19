.PHONY: quality ct-install

.DEFAULT_GOAL := quality

quality:
	@echo "Running quality checks..."
	@./scripts/ah-lint.sh
	@./scripts/helm-docs.sh
	@./scripts/lint.sh
	@echo "Quality checks completed."

ct-install:
	@ct install --config .github/configs/ct-install.yaml
