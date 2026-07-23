#!/usr/bin/env python3
"""Generate the nginx route config from waves.yml (FS-0004 scope 2).

The router stays dumb by design (ADR-0005): every routed endpoint
becomes one nginx `location` proxying to whichever stack waves.yml
names, plus the X-Served-By debug header. Deterministic output --
regenerating from an unchanged waves.yml is a byte-identical no-op
(FS-0004 acceptance; CI enforces it).

Stdlib only. Parses a deliberately constrained YAML subset (two-space
indents, `key: value`, `- ` list items) so no PyYAML dependency is
needed on CI runners or dev machines.

Usage: generate_router_config.py [waves.yml] [output.conf]
"""

import sys
from pathlib import Path

VALID_BACKENDS = {"legacy", "target"}
VALID_STATUSES = {"planned", "cut-over", "rolled-back"}


def parse_waves(text):
    """Parse the constrained waves.yml shape into (router, endpoints)."""
    router = {}
    endpoints = []
    section = None          # 'router' | 'waves'
    wave = None             # current wave attrs
    endpoint = None         # current endpoint attrs

    def flush_endpoint():
        nonlocal endpoint
        if endpoint is not None:
            for key in ("path", "backend"):
                if key not in endpoint:
                    raise ValueError(f"endpoint missing '{key}': {endpoint}")
            if endpoint["backend"] not in VALID_BACKENDS:
                raise ValueError(f"bad backend '{endpoint['backend']}' for {endpoint['path']}")
            endpoints.append(dict(endpoint))
            endpoint = None

    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()

        if indent == 0:
            flush_endpoint()
            section = stripped.rstrip(":")
            if section not in ("router", "waves"):
                raise ValueError(f"unknown top-level section '{section}'")
            continue

        if section == "router":
            key, _, value = stripped.partition(":")
            router[key.strip()] = value.strip()
            continue

        # waves section
        if stripped.startswith("- wave:"):
            flush_endpoint()
            wave = {"wave": stripped.split(":", 1)[1].strip()}
            continue
        if stripped.startswith("- path:"):
            flush_endpoint()
            endpoint = {"path": stripped.split(":", 1)[1].strip(), "wave": wave["wave"]}
            continue
        key, _, value = stripped.partition(":")
        key, value = key.strip(), value.strip()
        if endpoint is not None and key == "backend":
            endpoint["backend"] = value
        elif wave is not None and key == "status":
            if value not in VALID_STATUSES:
                raise ValueError(f"bad wave status '{value}'")
            wave[key] = value
        elif wave is not None:
            wave[key] = value

    flush_endpoint()
    for key in ("listen", "legacy_upstream", "target_upstream"):
        if key not in router:
            raise ValueError(f"router section missing '{key}'")
    return router, endpoints


def split_upstream(upstream):
    """'http://ords:8080/ords/legacy' -> ('http://ords:8080', '/ords/legacy')."""
    scheme, _, rest = upstream.partition("://")
    host, slash, prefix = rest.partition("/")
    return f"{scheme}://{host}", f"{slash}{prefix}".rstrip("/")


def location_block(router, endpoint):
    backend = endpoint["backend"]
    host, prefix = split_upstream(router[f"{backend}_upstream"])
    # variable proxy_pass + rewrite defers DNS to request time (Docker's
    # embedded resolver below): the router starts and keeps running even
    # while one stack is down -- it answers 502 for that stack only
    return (
        f"    # wave {endpoint['wave']}: {endpoint['path']} -> {backend}\n"
        f"    location {endpoint['path']} {{\n"
        f"        set $upstream_{backend} {host};\n"
        f"        rewrite ^/api(/.*)$ {prefix}$1 break;\n"
        f"        proxy_pass $upstream_{backend};\n"
        f"        proxy_set_header Host $host;\n"
        f"        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
        f"        add_header X-Served-By {backend} always;\n"
        f"    }}\n"
    )


def render(router, endpoints):
    blocks = "\n".join(location_block(router, e) for e in endpoints)
    return f"""\
# =====================================================================
# GENERATED FILE -- DO NOT EDIT (FS-0004: no hand-edited duplication).
# Source of truth: strangler/waves.yml. Regenerate: make router-config
# =====================================================================

server {{
    listen {router['listen']};

    # the router is deliberately dumb (ADR-0005): route + debug header,
    # no auth, no rewriting beyond the strangler prefix mapping.
    # 127.0.0.11 = Docker's embedded DNS (per-request resolution)
    resolver 127.0.0.11 valid=10s ipv6=off;

{blocks}
    location = /router/healthz {{
        default_type text/plain;
        return 200 'ok';
    }}

    # unrouted /api paths are an explicit 404, not a silent fallthrough
    location / {{
        default_type application/json;
        return 404 '{{"error_code":"ROUTER-404","message":"no wave routes this path (see strangler/waves.yml)"}}';
    }}
}}
"""


def main():
    waves_path = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent / "waves.yml")
    out_path = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).parent / "nginx" / "default.conf")
    router, endpoints = parse_waves(waves_path.read_text())
    out_path.write_text(render(router, endpoints))
    print(f"wrote {out_path} ({len(endpoints)} routes)")


if __name__ == "__main__":
    main()
