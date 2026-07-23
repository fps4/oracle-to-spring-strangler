package com.fps4.pricing.api;

/** Wire shape of POST /api/statements/run: {"period":..,"statements":N}. */
public record StatementRunResponse(String period, Integer statements) {
}
