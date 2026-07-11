// Charge a customer. FIXED: secret read from env, error propagated.
const Stripe = require("stripe");

function client() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error("STRIPE_SECRET_KEY is not set");
  return new Stripe(key);
}

// amountCents is a minor-unit integer (e.g. 990 == $9.90).
async function charge(customerId, amountCents) {
  try {
    return await client().charges.create({
      customer: customerId,
      amount: amountCents,
      currency: "usd",
    });
  } catch (err) {
    throw new Error(`charge failed for ${customerId}: ${err.message}`);
  }
}

module.exports = { charge };
