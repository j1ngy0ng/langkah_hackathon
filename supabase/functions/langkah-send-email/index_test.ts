import { Webhook } from "npm:standardwebhooks@1.0.0";
import { handle } from "./index.ts";

Deno.test("signed Langkah auth emails: signature, callback, retries, email change and failures", async () => {
  const assert = (condition: unknown, message: string) => {
    if (!condition) throw new Error(message);
  };
  const config = {
    url: "https://example.supabase.co",
    key: "test-only-provider-key",
    from: "Langkah <auth@example.com>",
    secret: `v1,whsec_${btoa("a-test-secret-with-at-least-32-bytes")}`,
  };
  const signer = new Webhook(config.secret.replace(/^v1,whsec_/, ""));
  const calls: {
    url: string;
    headers: Headers;
    body: { to: string[]; html: string; text: string; subject: string };
  }[] = [];
  const send: typeof fetch = async (input, options) => {
    calls.push({
      url: String(input),
      headers: new Headers(options?.headers),
      body: JSON.parse(String(options?.body)),
    });
    return Response.json({ id: "test-only" });
  };
  const request = (
    data: Record<string, unknown>,
    newEmail?: string,
    date = new Date(),
  ) => {
    const body = JSON.stringify({
      user: { email: "old@example.com", new_email: newEmail },
      email_data: data,
    });
    return new Request("https://example.test/hook", {
      method: "POST",
      body,
      headers: {
        "webhook-id": "event-test",
        "webhook-timestamp": String(Math.floor(date.getTime() / 1000)),
        "webhook-signature": signer.sign("event-test", date, body),
      },
    });
  };
  assert(
    (await handle(new Request("https://example.test/hook"), config, send))
      .status === 405,
    "POST required",
  );
  assert(
    (await handle(
      new Request("https://example.test/hook", { method: "POST", body: "{}" }),
      config,
      send,
    )).status === 401,
    "Unsigned request rejected",
  );
  assert(calls.length === 0, "No email sent before signature verification");
  assert(
    (await handle(
      request(
        { email_action_type: "signup", token_hash: "hash" },
        undefined,
        new Date(Date.now() - 600000),
      ),
      config,
      send,
    )).status === 401,
    "Expired signature rejected",
  );
  const signup = {
    email_action_type: "signup",
    token_hash: "signup-hash",
    redirect_to: "https://attacker.example",
  };
  assert(
    (await handle(request(signup), config, send)).status === 200,
    "Signed signup succeeds",
  );
  assert(
    calls[0].url === "https://api.resend.com/emails",
    "Only Resend endpoint used",
  );
  assert(
    calls[0].body.html.includes("Langkah") &&
      !calls[0].body.html.includes("Mystery Malaysia"),
    "Langkah branding",
  );
  assert(
    calls[0].body.text.includes(
      "redirect_to=langkah%3A%2F%2Fauth%2Fcallback",
    ) && !calls[0].body.text.includes("attacker"),
    "Only app callback used",
  );
  const key = calls[0].headers.get("Idempotency-Key");
  assert(
    (await handle(request(signup), config, send)).status === 200 &&
      calls[1].headers.get("Idempotency-Key") === key,
    "Retry uses same idempotency key",
  );
  assert(
    (await handle(
      request({ email_action_type: "recovery", token_hash: "recovery-hash" }),
      config,
      send,
    )).status === 200,
    "Recovery succeeds",
  );
  assert(
    calls[2].body.subject.includes("password") &&
      calls[2].body.text.includes("type=recovery"),
    "Recovery action preserved",
  );
  const changeStart = calls.length;
  assert(
    (await handle(
      request({
        email_action_type: "email_change",
        token_hash: "new-address-hash",
        token_hash_new: "old-address-hash",
      }, "new@example.com"),
      config,
      send,
    )).status === 200,
    "Secure email change succeeds",
  );
  const old = calls.slice(changeStart).find((c) =>
    c.body.to[0] === "old@example.com"
  )!;
  const fresh = calls.slice(changeStart).find((c) =>
    c.body.to[0] === "new@example.com"
  )!;
  assert(
    old.body.text.includes("token=old-address-hash") &&
      fresh.body.text.includes("token=new-address-hash"),
    "Hash sent to correct recipient",
  );
  assert(
    old.headers.get("Idempotency-Key") !== fresh.headers.get("Idempotency-Key"),
    "Recipient keys differ",
  );
  assert(
    (await handle(request({ email_action_type: "signup" }), config, send))
      .status === 400,
    "Missing token rejected",
  );
  assert(
    (await handle(
      request({ email_action_type: "reauthentication", token: "12345678" }),
      config,
      send,
    )).status === 200,
    "OTP action supported",
  );
  assert(
    calls.at(-1)!.body.text.includes("12345678") &&
      !calls.at(-1)!.body.text.includes("/auth/v1/verify"),
    "OTP sent as code",
  );
  assert(
    (await handle(request(signup), { ...config, key: "" }, send)).status ===
      503,
    "Missing provider config fails closed",
  );
  const rejected: typeof fetch = () =>
    Promise.resolve(
      Response.json({
        message:
          `Invalid from field: ${config.from}; recipient old@example.com; key ${config.key}`,
      }, { status: 400 }),
    );
  const logs: unknown[][] = [];
  const originalError = console.error;
  let failed: Response;
  console.error = (...args) => logs.push(args);
  try {
    failed = await handle(request(signup), config, rejected);
  } finally {
    console.error = originalError;
  }
  assert(
    failed.status === 502 && !(await failed.text()).includes(config.key),
    "Provider failure does not report success or leak credentials",
  );
  const log = JSON.stringify(logs);
  assert(
    log.includes("Invalid from field") && log.includes("400") &&
      !log.includes(config.key) && !log.includes("example.com"),
    "Provider diagnostics preserve validation detail and redact private values",
  );
});
