# oracle-to-spring-strangler -- canonical entry points (ADR-0001)
# Respects DOCKER_HOST (e.g. DOCKER_HOST=ssh://ds2 make up)

.PHONY: up down clean logs smoke smoke-legacy

up:
	docker compose up -d

down:
	docker compose down

clean:  ## down + wipe volumes (next up re-seeds from scratch)
	docker compose down -v

logs:
	docker compose logs -f

smoke-legacy:
	bash scripts/smoke-legacy.sh

# M0: smoke == legacy smoke. M1 adds router + target checks (FS-0006).
smoke: smoke-legacy
