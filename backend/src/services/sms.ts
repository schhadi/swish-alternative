import type { FastifyBaseLogger } from "fastify";
import { maskPhone } from "../lib/phone.js";

/** Sends one-time codes. Real providers plug in here later; v1 ships the dev logger and a stub (docs/SPEC.md section 5). */
export interface SmsSender {
  send(phoneE164: string, message: string): Promise<void>;
}

/** Dev mode: the message (with the code) goes to the log instead of a phone. Never allowed in production. */
export class LogSmsSender implements SmsSender {
  constructor(private readonly log: FastifyBaseLogger) {}

  async send(phoneE164: string, message: string): Promise<void> {
    this.log.info({ sms: { to: maskPhone(phoneE164), body: message } }, "SMS not sent (SMS_SENDER=log)");
  }
}

/** Production placeholder until a real sender is wired in. */
export class NotImplementedSmsSender implements SmsSender {
  async send(): Promise<void> {
    throw new Error("SMS sending is not configured (SMS_SENDER=none)");
  }
}
