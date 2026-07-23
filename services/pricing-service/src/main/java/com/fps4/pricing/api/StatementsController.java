package com.fps4.pricing.api;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fps4.pricing.statements.StatementRunResult;
import com.fps4.pricing.statements.StatementService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

/**
 * POST /api/statements/run -- the wave-3 endpoint (retain lane): thin
 * HTTP face of the converted PL/pgSQL month-end run.
 */
@RestController
@RequestMapping("/api/statements")
@Tag(name = "statements", description = "Month-end statement run (retained PKG_STATEMENTS, transitional tier)")
public class StatementsController {

    private final StatementService statements;

    public StatementsController(StatementService statements) {
        this.statements = statements;
    }

    @PostMapping("/run")
    @Operation(summary = "Run (or rerun) the month-end statements for a YYYY-MM period")
    public StatementRunResponse run(@RequestBody StatementRunRequest request) {
        StatementRunResult result = statements.run(request.period());
        return new StatementRunResponse(result.period(), result.statements());
    }
}
