package com.fps4.pricing.api;

/**
 * Body of POST /api/statements/run. No NotNull on period: a missing
 * key must reach the retained tier and fail its own BAD PERIOD check
 * (BR-API-08: missing period is equivalent to a bad period).
 */
public record StatementRunRequest(String period) {
}
