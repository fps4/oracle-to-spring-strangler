package com.fps4.pricing.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.fps4.pricing.config.SecurityConfig;
import com.fps4.pricing.statements.BadPeriodException;
import com.fps4.pricing.statements.StatementRunResult;
import com.fps4.pricing.statements.StatementService;

@WebMvcTest(StatementsController.class)
@Import(SecurityConfig.class)
class StatementsControllerTest {

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private StatementService statements;

    @Test
    @DisplayName("200: {\"period\":..,\"statements\":N} (BR-API-08)")
    void runShape() throws Exception {
        when(statements.run("2026-05")).thenReturn(new StatementRunResult("2026-05", 7));

        mvc.perform(post("/api/statements/run")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"period\":\"2026-05\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.period").value("2026-05"))
                .andExpect(jsonPath("$.statements").value(7));
    }

    @Test
    @DisplayName("400 problem: bad period, error_code ORA-20003 (BR-API-08)")
    void badPeriodProblem() throws Exception {
        when(statements.run(any())).thenThrow(new BadPeriodException("2007-13"));

        mvc.perform(post("/api/statements/run")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"period\":\"2007-13\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.detail").value("BAD PERIOD: 2007-13"))
                .andExpect(jsonPath("$.error_code").value("ORA-20003"));
    }
}
