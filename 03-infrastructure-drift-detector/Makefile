.PHONY: up apply drift simulate test down
up:        ; docker compose up -d
apply:     ; terraform -chdir=terraform init && terraform -chdir=terraform apply -auto-approve
simulate:  ; ./scripts/simulate_drift.sh
drift:     ; python3 drift_detector/detector.py --workdir terraform --report-dir reports
test:      ; python3 -m unittest -v tests.test_detector
down:      ; terraform -chdir=terraform destroy -auto-approve; docker compose down
