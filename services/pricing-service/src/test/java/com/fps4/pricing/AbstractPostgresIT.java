package com.fps4.pricing;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Base for all DB-touching tests: one shared Testcontainers
 * PostgreSQL 16 -- never H2 (FS-0003 acceptance criterion; H2 would
 * hide exactly the dialect quirks the conversion notes document).
 * The container starts once per JVM and the Spring context is cached
 * across subclasses; Flyway V1-V3 runs on first context start.
 */
@SpringBootTest
public abstract class AbstractPostgresIT {

    @SuppressWarnings("resource") // singleton, reaped by Ryuk on JVM exit
    private static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine");

    static {
        POSTGRES.start();
    }

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Autowired
    protected JdbcTemplate jdbc;
}
