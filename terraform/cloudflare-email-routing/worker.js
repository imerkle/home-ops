export default {
  async email(message, env, ctx) {
    // Generate a unique ID for the email object
    const id = crypto.randomUUID() + ".eml";
    
    // Store the raw email stream directly into the bound R2 bucket
    await env.EMAIL_BUCKET.put(id, message.raw);
    
    console.log(`Saved email from ${message.from} to ${id} in R2`);
  }
};
