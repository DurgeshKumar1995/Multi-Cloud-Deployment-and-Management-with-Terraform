.PHONY: deps test fmt compose-check local-up local-down local-terraform

deps:
	python3 -m pip install -r requirements.txt

test:
	python3 -m unittest discover -s app/tests -v

fmt:
	terraform fmt -recursive

compose-check:
	docker compose -f local/docker-compose.yml config --quiet

local-up:
	docker compose -f local/docker-compose.yml up --build -d

local-down:
	docker compose -f local/docker-compose.yml down

local-terraform:
	terraform -chdir=environments/local init
	terraform -chdir=environments/local apply -auto-approve
