export default {
  async email(message, env, ctx) {
    // Generate a unique ID for the email object
    const id = `${Date.now()}-${crypto.randomUUID()}.eml`;
    
    // Extract metadata if available
    const subject = message.headers.get("subject") || "";
    
    // Convert stream to ArrayBuffer for reliable R2 storage
    const rawBuffer = await new Response(message.raw).arrayBuffer();
    
    // Store the raw email directly into the bound R2 bucket
    await env.EMAIL_BUCKET.put(id, rawBuffer, {
      customMetadata: {
        from: message.from || "",
        to: message.to || "",
        subject: subject
      }
    });
    
    console.log(`Saved email from ${message.from} to ${message.to} (ID: ${id}) in R2`);
  }
};
