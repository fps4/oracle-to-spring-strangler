package com.fps4.pricing.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.fps4.pricing.config.SecurityConfig;
import com.fps4.pricing.orders.CreditLimitExceededException;
import com.fps4.pricing.orders.InsufficientStockException;
import com.fps4.pricing.orders.OrderLine;
import com.fps4.pricing.orders.OrderService;
import com.fps4.pricing.orders.PlacedOrder;

@WebMvcTest(OrdersController.class)
@Import(SecurityConfig.class)
class OrdersControllerTest {

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private OrderService orders;

    @Test
    @DisplayName("201: order_id, literal OPEN, total; no Location header (BR-API-04)")
    void placedOrderShape() throws Exception {
        when(orders.place(eq(1L), anyList()))
                .thenReturn(new PlacedOrder(100001L, "OPEN", new BigDecimal("89.95")));

        mvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customer_id":1,"lines":[{"product_id":1000,"qty":5}]}
                                """))
                .andExpect(status().isCreated())
                .andExpect(header().doesNotExist("Location"))
                .andExpect(jsonPath("$.order_id").value(100001))
                .andExpect(jsonPath("$.status").value("OPEN"))
                .andExpect(jsonPath("$.total").value(89.95));

        ArgumentCaptor<List<OrderLine>> lines = ArgumentCaptor.captor();
        verify(orders).place(eq(1L), lines.capture());
        assertThat(lines.getValue()).containsExactly(new OrderLine(1000L, 5L));
    }

    @Test
    @DisplayName("missing lines array degrades to an empty order, not a bean-validation reject (BR-ORD-13)")
    void missingLinesBecomesEmptyList() throws Exception {
        when(orders.place(eq(1L), eq(List.of())))
                .thenThrow(new com.fps4.pricing.orders.EmptyOrderException());

        mvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customer_id\":1}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.detail").value("ORDER HAS NO LINES"))
                .andExpect(jsonPath("$.error_code").value("ORA-20012"));
    }

    @Test
    @DisplayName("422 problem: credit limit exceeded, error_code ORA-20001 (BR-API-05)")
    void creditExceededProblem() throws Exception {
        when(orders.place(any(), anyList())).thenThrow(new CreditLimitExceededException(3L));

        mvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customer_id":3,"lines":[{"product_id":1000,"qty":100}]}
                                """))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.detail").value("CREDIT LIMIT EXCEEDED FOR CUSTOMER 3"))
                .andExpect(jsonPath("$.error_code").value("ORA-20001"));
    }

    @Test
    @DisplayName("409 problem: insufficient stock, error_code ORA-20002 (BR-API-05)")
    void insufficientStockProblem() throws Exception {
        when(orders.place(any(), anyList())).thenThrow(new InsufficientStockException(1003L));

        mvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customer_id":1,"lines":[{"product_id":1003,"qty":100}]}
                                """))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.detail").value("INSUFFICIENT STOCK FOR PRODUCT 1003"))
                .andExpect(jsonPath("$.error_code").value("ORA-20002"));
    }
}
