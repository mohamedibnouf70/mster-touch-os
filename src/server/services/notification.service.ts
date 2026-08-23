import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { NotificationChannel, NotificationPriority } from "@/types/enums";
import { logger } from "@/lib/logger";

export type NotificationPayload = {
  organizationId: string;
  recipientProfileId: string;
  type: string;
  title: string;
  message: string;
  entityType?: string | null;
  entityId?: string | null;
  priority?: NotificationPriority;
};

export interface NotificationChannelAdapter {
  readonly channel: NotificationChannel;
  send(notificationId: string, payload: NotificationPayload): Promise<void>;
}

export class InAppChannel implements NotificationChannelAdapter {
  readonly channel = "in_app" as const;

  constructor(private readonly supabase: SupabaseClient) {}

  async send(notificationId: string, payload: NotificationPayload): Promise<void> {
    void payload;
    await this.supabase.from("notification_deliveries").insert({
      notification_id: notificationId,
      channel: this.channel,
      status: "delivered",
      attempted_at: new Date().toISOString(),
    });
  }
}

export class EmailChannel implements NotificationChannelAdapter {
  readonly channel = "email" as const;
  async send(): Promise<void> {
    // Phase 8
  }
}

export class WhatsAppChannel implements NotificationChannelAdapter {
  readonly channel = "whatsapp" as const;
  async send(): Promise<void> {
    // Phase 8
  }
}

export class PushChannel implements NotificationChannelAdapter {
  readonly channel = "push" as const;
  async send(): Promise<void> {
    // Future channel
  }
}

export class NotificationService {
  constructor(
    private readonly supabase: SupabaseClient,
    private readonly channels: NotificationChannelAdapter[],
  ) {}

  async notify(payload: NotificationPayload): Promise<string | null> {
    const { data, error } = await this.supabase
      .from("notifications")
      .insert({
        organization_id: payload.organizationId,
        recipient_profile_id: payload.recipientProfileId,
        type: payload.type,
        title: payload.title,
        message: payload.message,
        entity_type: payload.entityType ?? null,
        entity_id: payload.entityId ?? null,
        priority: payload.priority ?? "normal",
      })
      .select("id")
      .single<{ id: string }>();

    if (error || !data) {
      logger.error("Failed to create in-app notification", { message: error?.message });
      return null;
    }

    for (const channel of this.channels) {
      if (channel.channel !== "in_app") {
        continue;
      }
      await channel.send(data.id, payload);
    }

    return data.id;
  }
}

export function createNotificationService(supabase: SupabaseClient): NotificationService {
  return new NotificationService(supabase, [new InAppChannel(supabase)]);
}
