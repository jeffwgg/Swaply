enum CheckoutFlowKind {
  /// Single item purchase: show product price, optional shipping, Stripe when total > 0.
  purchase,

  /// Item-for-item: show two rows; no product subtotal; Stripe only when shipping fee > 0.
  swap,
}
