import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { logger } from "@/lib/logger";

export type AuditInput = {
  organizationId: string;
  action: string;
  entityType: string;
  entityId: string;
  previousValues?: Record<string, unknown> | null;
  newValues?: Record<string, unknown> | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  correlationId?: string | null;
};

export class AuditService {
  constructor(private readonly supabase: SupabaseClient) {}

  async log(input: AuditInput): Promise<void> {
    const { error } = await this.supabase.rpc("log_audit", {
      p_organization_id: input.organizationId,
      p_action: input.action,
      p_entity_type: input.entityType,
      p_entity_id: input.entityId,
      p_previous_values: input.previousValues ?? null,
      p_new_values: input.newValues ?? null,
      p_ip_address: input.ipAddress ?? null,
      p_user_agent: input.userAgent ?? null,
      p_correlation_id: input.correlationId ?? null,
    });

    if (error) {
      logger.error("Failed to write audit log", { action: input.action, message: error.message });
    }
  }
}
