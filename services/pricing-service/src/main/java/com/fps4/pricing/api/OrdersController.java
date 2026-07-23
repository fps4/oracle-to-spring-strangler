package com.fps4.pricing.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.fps4.pricing.orders.OrderLine;
import com.fps4.pricing.orders.OrderService;
import com.fps4.pricing.orders.PlacedOrder;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

/**
 * POST /api/orders -- the wave-2 endpoint (translate lane). A missing
 * lines array degrades to an empty order exactly like the legacy
 * JSON_TABLE loop that iterates zero times (BR-ORD-13).
 */
@RestController
@RequestMapping("/api/orders")
@Tag(name = "orders", description = "Order placement (translated PKG_ORDERS)")
public class OrdersController {

    private final OrderService orders;

    public OrdersController(OrderService orders) {
        this.orders = orders;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Place an order: credit check, stock reservation, audit -- one transaction")
    public PlaceOrderResponse place(@RequestBody PlaceOrderRequest request) {
        List<OrderLine> lines = request.lines() == null
                ? List.of()
                : request.lines().stream()
                        .map(l -> new OrderLine(l.productId(), l.qty()))
                        .toList();
        PlacedOrder placed = orders.place(request.customerId(), lines);
        return new PlaceOrderResponse(placed.orderId(), placed.status(), placed.total());
    }
}
