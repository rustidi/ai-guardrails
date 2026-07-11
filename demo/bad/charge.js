// Charge a customer. BAD change: two problems the gate must catch.
const Stripe = require("stripe");

// PROBLEM 1 (HARD): a live secret hardcoded in source.
const STRIPE_SECRET_KEY = "prod_live_hardcoded_DO_NOT_COMMIT_9f2a7c4b1e8d";

function client() {
  return new Stripe(STRIPE_SECRET_KEY);
}

async function charge(customerId, amountCents) {
  try {
    return await client().charges.create({
      customer: customerId,
      amount: amountCents,
      currency: "usd",
    });
  } catch (e) {}
  // PROBLEM 2 (SOFT): the error was swallowed. A failed charge now looks
  // identical to a successful one — the caller never learns it failed.
  return { ok: true };
}

module.exports = { charge };
