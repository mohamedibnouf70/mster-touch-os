/** Map commercial entity types to application routes for My Actions / search links. */
export function commercialEntityHref(entityType: string, entityId: string): string | null {
  const map: Record<string, (id: string) => string> = {
    purchase_request: (id) => `/procurement/purchase-requests/${id}`,
    rfq: (id) => `/procurement/rfqs/${id}`,
    supplier_quotation: (id) => `/procurement/quotations/${id}`,
    quotation_comparison: (id) => `/procurement/rfqs/${id}/comparison`,
    purchase_order: (id) => `/procurement/purchase-orders/${id}`,
    goods_receipt: (id) => `/procurement/goods-receipts/${id}`,
    supplier_invoice: (id) => `/finance/supplier-invoices/${id}`,
    supplier_payment: (id) => `/finance/supplier-invoices/${id}`,
    client_valuation: (id) => `/finance/client-valuations/${id}`,
    client_invoice: (id) => `/finance/client-invoices/${id}`,
    project_contract: (id) => `/finance/client-valuations/${id}`,
    contract_milestone: (id) => `/finance/client-valuations/${id}`,
    variation: (id) => `/finance/variations/${id}`,
    supplier: (id) => `/procurement/suppliers/${id}`,
  };
  const fn = map[entityType];
  return fn ? fn(entityId) : null;
}

export function searchResultHref(type: string, id: string): string | null {
  return commercialEntityHref(type, id);
}
