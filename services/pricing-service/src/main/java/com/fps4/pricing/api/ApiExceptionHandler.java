package com.fps4.pricing.api;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.fps4.pricing.domain.InvalidQuantityException;
import com.fps4.pricing.domain.LegacyNotFoundException;
import com.fps4.pricing.orders.CreditLimitExceededException;
import com.fps4.pricing.orders.EmptyOrderException;
import com.fps4.pricing.orders.InsufficientStockException;
import com.fps4.pricing.statements.BadPeriodException;

/**
 * RFC 7807 problem responses (FS-0003 scope 4), carrying the frozen
 * legacy HTTP error contract (legacy/ords/modules.sql header):
 *
 *   ORA-20001 credit exceeded    -> 422
 *   ORA-20002 insufficient stock -> 409
 *   ORA-20003 bad period         -> 400
 *   ORA-20010/-20012 validation  -> 400
 *   NO_DATA_FOUND (ORA-01403)    -> 404
 *
 * The {@code error_code} extension property keeps the original ORA
 * code on the wire as a parity-mapping aid (BR-API-09): the FS-0005
 * harness maps legacy {@code error_code} bodies onto these problems.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(InvalidQuantityException.class)
    public ProblemDetail invalidQuantity(InvalidQuantityException e) {
        return problem(HttpStatus.BAD_REQUEST, "ORA-20010", e);
    }

    @ExceptionHandler(EmptyOrderException.class)
    public ProblemDetail emptyOrder(EmptyOrderException e) {
        return problem(HttpStatus.BAD_REQUEST, "ORA-20012", e);
    }

    @ExceptionHandler(BadPeriodException.class)
    public ProblemDetail badPeriod(BadPeriodException e) {
        return problem(HttpStatus.BAD_REQUEST, "ORA-20003", e);
    }

    @ExceptionHandler(LegacyNotFoundException.class)
    public ProblemDetail notFound(LegacyNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "ORA-01403", e);
    }

    @ExceptionHandler(CreditLimitExceededException.class)
    public ProblemDetail creditExceeded(CreditLimitExceededException e) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "ORA-20001", e);
    }

    @ExceptionHandler(InsufficientStockException.class)
    public ProblemDetail insufficientStock(InsufficientStockException e) {
        return problem(HttpStatus.CONFLICT, "ORA-20002", e);
    }

    private static ProblemDetail problem(HttpStatus status, String oraCode, RuntimeException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, e.getMessage());
        problem.setProperty("error_code", oraCode);
        return problem;
    }
}
