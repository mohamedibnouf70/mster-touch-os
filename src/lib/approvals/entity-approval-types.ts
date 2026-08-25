const supportedEntityTypes = [
  "purchase_request",
  "quotation_comparison",
  "quotation_recommendation",
  "purchase_order",
  "supplier_invoice",
  "client_valuation",
  "variation",
] as const;

export type SupportedEntityType = (typeof supportedEntityTypes)[number];

export function isEntityApprovalTypeSupported(entityType: string): entityType is SupportedEntityType {
  return supportedEntityTypes.includes(entityType as SupportedEntityType);
}
