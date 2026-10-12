import { Webhook } from "npm:standardwebhooks@1.0.0";

type EmailData = {
  email_action_type: string;
  token?: string;
  token_hash?: string;
  token_hash_new?: string;
};
type Payload = {
  user: { email: string; new_email?: string };
  email_data: EmailData;
};
type Config = { url: string; key: string; from: string; secret: string };
const copy: Record<string, [string, string]> = {
  signup: [
    "Confirm your Langkah account",
    "Confirm your email to begin your local walking missions.",
  ],
  recovery: [
    "Reset your Langkah password",
    "Continue to Langkah to choose a new password.",
  ],
  invite: [
    "You are invited to Langkah",
    "Continue to set up your Langkah account.",
  ],
  magiclink: [
    "Sign in to Langkah",
    "Continue to sign in to your Langkah account.",
  ],
  email_change: [
    "Confirm your Langkah email change",
    "Confirm the requested change to your account email.",
  ],
  reauthentication: [
    "Confirm your Langkah identity",
    "Enter this code in the app to confirm your identity.",
  ],
};
const escape = (value: string) =>
  value.replace(/[&<>"']/g, (c) =>
    ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    })[c]!);

// Exported so the real signed webhook path can be checked without sending email.
export async function handle(
  request: Request,
  config: Config,
  send = fetch,
): Promise<Response> {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }
  if (!config.secret) {
    return Response.json({ error: "Email hook is not configured" }, {
      status: 503,
    });
  }
  let payload: Payload;
  try {
    payload = new Webhook(config.secret.replace(/^v1,whsec_/, "")).verify(
      await request.text(),
      Object.fromEntries(request.headers),
    ) as Payload;
  } catch {
    return Response.json({ error: "Invalid webhook signature" }, {
      status: 401,
    });
  }
  if (!config.key || !config.from || !config.url) {
    return Response.json({ error: "Email provider is not configured" }, {
      status: 503,
    });
  }
  const data = payload.email_data;
  const user = payload.user;
  const content = data && copy[data.email_action_type];
  if (!content || !user?.email) {
    return Response.json({ error: "Invalid email action" }, { status: 400 });
  }
  const jobs: { to: string; hash?: string }[] = [];
  if (data.email_action_type === "reauthentication") {
    if (!/^\d{6,12}$/.test(data.token ?? "")) {
      return Response.json({ error: "Missing verification code" }, {
        status: 400,
      });
    }
    jobs.push({ to: user.email });
  } else if (data.email_action_type === "email_change" && user.new_email) {
    // Supabase's secure email-change contract swaps the old/new hash fields.
    if (data.token_hash_new) {
      jobs.push({ to: user.email, hash: data.token_hash_new });
    }
    if (data.token_hash) {
      jobs.push({ to: user.new_email, hash: data.token_hash });
    }
  } else if (data.token_hash || data.token_hash_new) {
    jobs.push({ to: user.email, hash: data.token_hash || data.token_hash_new });
  }
  if (!jobs.length) {
    return Response.json({ error: "Missing authentication token" }, {
      status: 400,
    });
  }
  try {
    const responses = await Promise.all(jobs.map(async (job) => {
      const query = new URLSearchParams({
        token: job.hash ?? "",
        type: data.email_action_type,
        redirect_to: "langkah://auth/callback",
      });
      const link = `${config.url}/auth/v1/verify?${query}`;
      const action = job.hash
        ? `<p><a href="${
          escape(link)
        }" style="display:inline-block;background:#c5ef67;color:#142b38;padding:16px 24px;border-radius:12px;text-decoration:none;font-weight:bold">Continue in Langkah</a></p><p style="font-size:12px;word-break:break-all">Or open: ${
          escape(link)
        }</p>`
        : `<p style="font-size:32px;letter-spacing:6px">${
          escape(data.token!)
        }</p>`;
      const html =
        `<!doctype html><html lang="en"><body style="margin:0;background:#f7f8f0;font-family:Arial,sans-serif;color:#142b38"><main style="max-width:540px;margin:32px auto;padding:32px;background:white;border-radius:20px"><p style="color:#176b50;font-weight:bold">LANGKAH · Walk your neighbourhood</p><h1 style="font-size:26px">${
          content[0]
        }</h1><p style="line-height:1.6">${
          content[1]
        }</p>${action}<p style="font-size:13px;color:#647069">Open the link on the Android phone where you requested it. If you did not request this, you can ignore this email.</p></main></body></html>`;
      const digest = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(
          `${request.headers.get("webhook-id")}:${job.to}`,
        ),
      );
      const idempotency = Array.from(
        new Uint8Array(digest),
        (b) => b.toString(16).padStart(2, "0"),
      ).join("");
      const response = await send("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${config.key}`,
          "Content-Type": "application/json",
          "Idempotency-Key": idempotency,
        },
        body: JSON.stringify({
          from: config.from,
          to: [job.to],
          subject: content[0],
          html,
          text: `${content[0]}\n\n${content[1]}\n\n${
            job.hash ? link : data.token
          }\n\nIf you did not request this, ignore this email.`,
        }),
        signal: AbortSignal.timeout(4000),
      });
      return response;
    }));
    for (const response of responses) {
      if (!response.ok) {
        const error = await response.json().catch(() => ({}));
        let detail = typeof error.message === "string"
          ? error.message
          : "No provider detail";
        // Keep useful validation details, never log credentials or recipients.
        for (
          const value of [
            config.key,
            config.secret,
            config.from,
            data.token,
            data.token_hash,
            data.token_hash_new,
            ...jobs.map((job) => job.to),
          ]
        ) {
          if (value) detail = detail.replaceAll(value, "[redacted]");
        }
        detail = detail.replace(
          /https?:\/\/\S+|[\w.+-]+@[\w.-]+|\b(?:re_|whsec_)[\w+/=-]+/g,
          "[redacted]",
        ).replace(/[\r\n]/g, " ").slice(0, 400);
        console.error(
          "Langkah email provider rejected",
          response.status,
          detail,
        );
        return Response.json({ error: "Email provider rejected delivery" }, {
          status: 502,
        });
      }
    }
    return Response.json({});
  } catch {
    // Never log email addresses, verification links, provider keys or tokens.
    console.error("Langkah email delivery failed");
    return Response.json({ error: "Email delivery failed" }, { status: 502 });
  }
}

if (import.meta.main) {
  Deno.serve((request) =>
    handle(request, {
      url: Deno.env.get("SUPABASE_URL") ?? "",
      key: Deno.env.get("RESEND_API_KEY") ?? "",
      from: Deno.env.get("AUTH_EMAIL_FROM") ?? "",
      secret: Deno.env.get("SEND_EMAIL_HOOK_SECRET") ?? "",
    })
  );
}
