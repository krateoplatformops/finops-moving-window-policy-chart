NAMESPACE?=default

create:
	rm -f ./chart/templates/configmap.yaml
	@echo "Creating configmap with individual form-file flags for each .rego file"
	@FILES=$$(find ./policies -name "*.rego"); \
	CMD="kubectl create configmap -n $(NAMESPACE) policies"; \
	for file in $$FILES; do \
		BASENAME=$$(basename $$file); \
		CMD="$$CMD --from-file ./policies/$$BASENAME"; \
	done; \
	$$CMD --dry-run=client -o yaml > ./chart/templates/configmap.yaml
	sed -i '' '/creationTimestamp: null/d' ./chart/templates/configmap.yaml
	sed -i '' '/  namespace: opa-system/d' ./chart/templates/configmap.yaml
	sed -i '' 's/  name: policies/  name: {{ include "finops-moving-window-policy.fullname" . }}/g' ./chart/templates/configmap.yaml