package com.fps4.pricing.statements;

/** Echo of a month-end run: the period and how many statements it wrote. */
public record StatementRunResult(String period, int statements) {
}
