# oracle-to-spring-strangler -- canonical entry points (ADR-0001)
# Respects DOCKER_HOST (e.g. DOCKER_HOST=ssh://ds2 make up)

.PHONY: up down clean logs smoke smoke-legacy smoke-m1 verify router-config router-reload

up:
	docker compose up -d --build

down:
	docker compose down

clean:  ## down + wipe volumes (next up re-seeds from scratch)
	docker compose down -v

logs:
	docker compose logs -f

smoke-legacy:
	bash scripts/smoke-legacy.sh

smoke-m1:  ## target service + router checks (FS-0003/0004)
	bash scripts/smoke-m1.sh

smoke: smoke-legacy smoke-m1

verify:  ## pricing-service test suite (needs Java 21 + Docker)
	cd services/pricing-service && ./mvnw -B verify

router-config:  ## regenerate nginx config from strangler/waves.yml
	python3 strangler/generate_router_config.py

router-reload: router-config  ## apply a wave flip to the running router
	docker compose exec router nginx -s reload
